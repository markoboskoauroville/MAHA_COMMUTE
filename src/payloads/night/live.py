
# ===========================================================================
# THE LIVE FEED, night.commute v10
#
# Spliced into night_server.py at build time by tools/patch_payload.py. It is
# not in the payload, because src/payloads holds the files as they were handed
# over and every change to one of them is a visible transformation with a
# witness and a test.
#
# WHAT ZET PUBLISHES, MEASURED AGAINST THE LIVE TAP ON 16.9.2026 AT 01:03
#
# Sixty six entities, and they come in PAIRS that are never one entity:
#
#     X8HIDLT03R       a TripUpdate     trip 0_23_3302_33_10017, route 33
#     X8HIDLT03R_460   a VehiclePosition, same trip, car 460, 45.7997,15.9713
#
# Thirty one carried a TripUpdate, thirty five carried a VehiclePosition, and
# ZERO carried both. So a delay and a position for one tram arrive as two
# separate entities and are joined here on the trip id.
#
# THE TRIP DESCRIPTOR CARRIES route_id, AND THAT IS THE WHOLE JOIN
#
# Field 5 of the TripDescriptor is the route, in plain text, on every entity.
# Nothing has to be matched against the static schedule to know that a tram is
# a 33, which matters because that match does not work: this project measured
# the live trip ids against the published build on 31.8.2026 and the whole-id
# join hit zero of 501. Reading route_id off the feed steps around the problem
# rather than solving it, and it is the reason this file is short.
#
# WHAT IT DOES NOT CARRY
#
# No bearing, no speed, no stop_id, no current_stop_sequence, no status: all
# measured absent, on every one of the thirty five positions. So which stop a
# tram is at is worked out HERE, from the coordinate and the line's own list of
# stations, and which way it is facing is worked out from the stops its
# TripUpdate still has ahead of it.
#
# THE HEADER TIMESTAMP IS READ, AND IT IS THE POINT
#
# A feed that stopped publishing forty minutes ago answers 200, parses, and is
# the right size. The only thing that gives it away is the timestamp in its own
# header, so that is read on every fetch and its age travels with the answer.
# A tram drawn from a dead feed is worse than an empty map, because the map
# says nothing while the drawing says something false.
#
# WHY THE ARRIVAL TIME IS NOT TAKEN FROM THE FEED'S OWN PREDICTIONS
#
# Measured over the whole feed, 62 stop time updates: THIRTY OF THEM CARRY NO
# TIME AT ALL, and every single one of those thirty claims a delay of exactly
# zero. That is ZET's shape for "nothing known", and read naively it says "on
# time" about a tram nobody is tracking. So an update with no time is never
# allowed to produce a delay.
#
# Of the thirty two that do carry a time, most are for stops the tram has
# ALREADY PASSED, some by the best part of an hour, and the delays beside them
# included 3605 and 24000 seconds. A tram is not six hours late; that row is
# measuring against the wrong service day.
#
# So the feed is believed about WHERE A TRAM IS, which it is good at, and the
# timetable this app already holds is believed about HOW LONG IT TAKES TO GET
# HERE, which the feed is bad at. A prediction from the feed is used only when
# it exists for the stop being asked about and has not already happened.
# ===========================================================================
import math
import struct

GTFS_RT_URL = "https://zet.hr/gtfs-rt-protobuf"
RT_TIMEOUT = 12
RT_CACHE_S = 8          # several polls in a row share one download
FRESH_S = 120           # newer than this and the feed is simply live
STALE_S = 600           # older than this and nothing may be drawn from it
# Half an hour. The night trams run about every fifty minutes, so a delay
# larger than this is not a late tram, it is a row measured against the wrong
# service day. The wire carried 24000 seconds in one reading, and 3605 in
# another: that second one is an hour and five seconds, which is the shape of
# a clock an hour out rather than of a tram an hour late.
DELAY_SANE_S = 1800

# Zagreb, generously. A tram outside this box is not a Zagreb tram, and a
# coordinate of 0,0 is the shape a missing coordinate arrives in.
LAT_MIN, LAT_MAX = 45.60, 46.05
LON_MIN, LON_MAX = 15.65, 16.30

_RT_CACHE = {"at": 0.0, "body": None}
_RT_LOCK = threading.Lock()


# ---------------------------------------------------------------------------
# a protobuf reader that reads only what it needs
#
# The phone has no protobuf library and this is not worth one. Every field on
# the wire carries its own type, so a field nobody here understands is skipped
# by its length instead of being guessed at.
# ---------------------------------------------------------------------------

def _rt_varint(b, i):
    shift = 0
    val = 0
    while i < len(b):
        c = b[i]
        val |= (c & 0x7F) << shift
        i += 1
        if not c & 0x80:
            return val, i
        shift += 7
        if shift > 70:
            raise ValueError("varint too long")
    raise ValueError("varint ran off the end")


def _rt_fields(b, start=0, end=None):
    """Yield (field number, wire type, value) across one message."""
    i = start
    end = len(b) if end is None else end
    while i < end:
        key, i = _rt_varint(b, i)
        fn, wt = key >> 3, key & 7
        if wt == 0:
            v, i = _rt_varint(b, i)
            yield fn, wt, v
        elif wt == 2:
            ln, i = _rt_varint(b, i)
            if i + ln > end:
                raise ValueError("length delimited field runs past the end")
            yield fn, wt, b[i:i + ln]
            i += ln
        elif wt == 1:
            yield fn, wt, b[i:i + 8]
            i += 8
        elif wt == 5:
            yield fn, wt, b[i:i + 4]
            i += 4
        else:
            raise ValueError("wire type %d, which this feed should not contain" % wt)


def _rt_signed(v):
    # A delay of minus ninety seconds is on the wire as a 64 bit two's
    # complement, so an early tram reads as 18446744073709551526 until this
    # runs. Early trams are the ones this gets wrong if it is forgotten.
    return v - (1 << 64) if v >= (1 << 63) else v


def _rt_trip(b):
    """TripDescriptor -> {trip_id, route_id, direction_id}."""
    out = {}
    for fn, wt, v in _rt_fields(b):
        if fn == 1 and wt == 2:
            out["trip_id"] = v.decode("utf-8", "replace")
        elif fn == 5 and wt == 2:
            out["route_id"] = v.decode("utf-8", "replace")
        elif fn == 6 and wt == 0:
            out["direction_id"] = v
    return out


def _rt_event(b):
    """StopTimeEvent -> (time, delay)."""
    t = d = None
    for fn, wt, v in _rt_fields(b):
        if fn == 1 and wt == 0:
            d = _rt_signed(v)
        elif fn == 2 and wt == 0:
            t = v
    return t, d


def _rt_stu(b):
    """StopTimeUpdate -> (stop_id, time, delay). Departure wins over arrival."""
    stop_id = None
    t = d = None
    got_dep = False
    for fn, wt, v in _rt_fields(b):
        if fn == 4 and wt == 2:
            stop_id = v.decode("utf-8", "replace")
        elif fn == 3 and wt == 2:
            t, d = _rt_event(v)
            got_dep = True
        elif fn == 2 and wt == 2 and not got_dep:
            t, d = _rt_event(v)
    return stop_id, t, d


def _rt_position(b):
    """Position -> (lat, lon). Bearing and speed are not published."""
    lat = lon = None
    for fn, wt, v in _rt_fields(b):
        if fn == 1 and wt == 5:
            lat = struct.unpack("<f", v)[0]
        elif fn == 2 and wt == 5:
            lon = struct.unpack("<f", v)[0]
    return lat, lon


def parse_rt(body):
    """The whole feed -> {ts, entities, trips}, trips keyed by trip id.

    The two halves of one tram arrive as two entities and are merged here, so
    a trip that has both ends up with its delay and its coordinate together.
    """
    out = {"ts": None, "entities": 0, "trips": {}}

    def trip_slot(desc):
        tid = desc.get("trip_id")
        if not tid:
            return None
        slot = out["trips"].get(tid)
        if slot is None:
            slot = out["trips"][tid] = {
                "trip_id": tid, "route_id": desc.get("route_id") or "",
                "direction_id": desc.get("direction_id"),
                "stops": {}, "lat": None, "lon": None, "veh": "", "pos_ts": None,
            }
        if not slot["route_id"] and desc.get("route_id"):
            slot["route_id"] = desc["route_id"]
        if slot["direction_id"] is None and desc.get("direction_id") is not None:
            slot["direction_id"] = desc["direction_id"]
        return slot

    for fn, wt, v in _rt_fields(body):
        if fn == 1 and wt == 2:                       # FeedHeader
            for hf, hw, hv in _rt_fields(v):
                if hf == 3 and hw == 0:
                    out["ts"] = hv
        elif fn == 2 and wt == 2:                     # FeedEntity
            out["entities"] += 1
            for ef, ew, ev in _rt_fields(v):
                if ef == 3 and ew == 2:               # TripUpdate
                    slot = None
                    stus = []
                    for f, w, x in _rt_fields(ev):
                        if f == 1 and w == 2:
                            slot = trip_slot(_rt_trip(x))
                        elif f == 2 and w == 2:
                            stus.append(_rt_stu(x))
                    if slot is not None:
                        for stop_id, t, d in stus:
                            if stop_id:
                                slot["stops"][stop_id] = {"t": t, "d": d}
                elif ef == 4 and ew == 2:             # VehiclePosition
                    slot = None
                    lat = lon = None
                    veh = ""
                    pts = None
                    for f, w, x in _rt_fields(ev):
                        if f == 1 and w == 2:
                            slot = trip_slot(_rt_trip(x))
                        elif f == 2 and w == 2:
                            lat, lon = _rt_position(x)
                        elif f == 5 and w == 0:
                            pts = x
                        elif f == 8 and w == 2:       # VehicleDescriptor
                            for vf, vw, vv in _rt_fields(x):
                                if vf in (1, 2) and vw == 2:
                                    veh = veh or vv.decode("utf-8", "replace")
                    if slot is not None and lat is not None and lon is not None:
                        # 0,0 is how a missing coordinate arrives, and the
                        # Adriatic is how a broken one does.
                        if LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX:
                            slot["lat"], slot["lon"] = lat, lon
                            slot["veh"] = veh
                            slot["pos_ts"] = pts
    return out


def fetch_rt():
    """The feed, at most once every RT_CACHE_S seconds."""
    with _RT_LOCK:
        now = time.time()
        if _RT_CACHE["body"] is not None and now - _RT_CACHE["at"] < RT_CACHE_S:
            return _RT_CACHE["body"]
        req = urllib.request.Request(
            GTFS_RT_URL, headers={"User-Agent": "nightcommute-live/1"})
        with urllib.request.urlopen(req, timeout=RT_TIMEOUT) as r:
            body = r.read()
        # A captive portal answers 200 with a web page, and a web page parses
        # as protobuf far enough to produce nonsense rather than an error.
        if body[:15].lstrip()[:1] == b"<":
            raise ValueError("the feed answered with a web page, not a feed")
        # Small is not the same as wrong, and this nearly got it wrong. At
        # 01:03 the feed measured 6327 bytes for 65 vehicles, which is about
        # 97 bytes each, so a floor of a couple of hundred bytes would have
        # thrown away a perfectly good feed at half past four in the morning
        # with two trams left running. That is the exact hour this app is for.
        # So the floor is only what cannot be a feed at all, and whether the
        # bytes mean anything is left to the reader below.
        if len(body) < 8:
            raise ValueError("%d bytes is too small to be anything" % len(body))
        _RT_CACHE["at"] = now
        _RT_CACHE["body"] = body
        return body


# ---------------------------------------------------------------------------
# placing a tram on a line
# ---------------------------------------------------------------------------

def _hav(lat1, lon1, lat2, lon2):
    """Metres between two coordinates."""
    R = 6371000.0
    t = math.pi / 180.0
    dla = (lat2 - lat1) * t
    dlo = (lon2 - lon1) * t
    h = (math.sin(dla / 2) ** 2 +
         math.cos(lat1 * t) * math.cos(lat2 * t) * math.sin(dlo / 2) ** 2)
    return 2 * R * math.asin(min(1.0, math.sqrt(h)))


def _stop_index(net):
    """stop_id -> (line, direction, station name, index along the line).

    Built from each line's own stopmap, which is how a station name becomes
    the two stop ids it wears, one per direction. This is the index that lets
    a live trip's stop ids say which way it is going without ever matching a
    trip id.
    """
    idx = {}
    for ln, L in (net.get("lines") or {}).items():
        order = {name: i for i, name in enumerate(L.get("stations") or [])}
        for name, ids in (L.get("stopmap") or {}).items():
            for d, sid in enumerate(ids or []):
                if sid:
                    idx[sid] = (ln, d, name, order.get(name, -1))
    return idx


def _direction_of(trip, ln, idx):
    """Which way this tram is going: 0 along the line's listed order, 1 back.

    The stop ids its TripUpdate still carries are the honest answer, because
    each direction wears its own set of them. Where there is no TripUpdate the
    trip id is read instead: 0_23_3302_33_10017 is route 33, pattern 02, and
    the pattern's last digit has matched the direction on every trip measured.
    That is a pattern and not a promise, so which of the two answered is
    carried out with the answer.
    """
    votes = [0, 0]
    for sid in trip["stops"]:
        hit = idx.get(sid)
        if hit and hit[0] == ln:
            votes[hit[1]] += 1
    if votes[0] or votes[1]:
        return (0 if votes[0] >= votes[1] else 1), "stops"

    parts = trip["trip_id"].split("_")
    if len(parts) > 3 and parts[2].startswith(parts[3]):
        pat = parts[2][len(parts[3]):]
        if pat.isdigit() and int(pat) in (1, 2):
            return int(pat) - 1, "pattern"
    if trip.get("direction_id") in (0, 1):
        return trip["direction_id"], "descriptor"
    return None, "unknown"


def _nearest_station(net, coords, ln, lat, lon):
    """The station on THIS line the tram is closest to: (name, index, metres).

    Restricted to the line's own stations on purpose. A 33 standing beside a
    31's stop is at its own next stop, not at the 31's, and a nearest-of-all
    search says the second thing.
    """
    L = (net.get("lines") or {}).get(ln) or {}
    best = (None, -1, None)
    bd = None
    for i, name in enumerate(L.get("stations") or []):
        c = coords.get(name)
        if not c:
            continue
        d = _hav(lat, lon, c[0], c[1])
        if bd is None or d < bd:
            bd = d
            best = (name, i, d)
    return best


def _locate_from_stops(coords, ln, idx, trip, now):
    """Where a tram ZET is not locating has to be, from its own stop times.

    Two ways, and the answer says which one it was, because they are not worth
    the same. Between a stop just left and a stop due, at the fraction of the
    way the clock says, is a reckoned position and is as good as day.commute's
    bus. Sitting on the last stop it was seen at is weaker and is only offered
    with the age of that sighting attached, so "it was here four minutes ago"
    never reads as "it is here".

    Returns (lat, lon, source, age) or None.
    """
    timed = []
    for sid, upd in trip["stops"].items():
        hit = idx.get(sid)
        t = upd.get("t")
        if hit and hit[0] == ln and t and hit[2] in coords:
            timed.append((t, hit[2]))
    if not timed:
        return None
    timed.sort()

    for i in range(len(timed) - 1):
        t0, n0 = timed[i]
        t1, n1 = timed[i + 1]
        if t0 <= now <= t1:
            f = 0.0 if t1 == t0 else float(now - t0) / float(t1 - t0)
            a, b = coords[n0], coords[n1]
            return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f,
                    "reckoned", 0)

    past = [x for x in timed if x[0] <= now]
    if past:
        t0, n0 = past[-1]
        c = coords[n0]
        return (c[0], c[1], "laststop", int(now - t0))
    return None


def _running_times(net, sched):
    """How long this line takes between its stations, from its own timetable.

    {line: {direction: [seconds at each station, along the line's listed
    order]}}. Built by reading tonight's trips and taking, at each station,
    the median of what they do, so one trip standing at a terminal with its
    doors open does not become the running time for everybody.

    This is what answers "how long until it reaches me". The feed cannot: its
    stop predictions are mostly for stops already behind the tram.
    """
    out = {}
    for ln, L in (net.get("lines") or {}).items():
        stations = L.get("stations") or []
        stopmap = L.get("stopmap") or {}
        per_dir = {}
        for d in (0, 1):
            ids = [(stopmap.get(n) or ["", ""])[d] if len(stopmap.get(n) or []) > d
                   else "" for n in stations]
            trips = ((sched.get(ln) or {}).get(str(d))) or []
            samples = [[] for _ in stations]
            for trip in trips:
                # Every station's offset is measured from the same trip's own
                # first station, so trips starting at different times still
                # agree about how long the run takes.
                base = None
                for i, sid in enumerate(ids):
                    if sid and sid in trip:
                        base = trip[sid]
                        break
                if base is None:
                    continue
                for i, sid in enumerate(ids):
                    if sid and sid in trip:
                        samples[i].append(trip[sid] - base)
            cum = []
            for s in samples:
                if s:
                    s.sort()
                    cum.append(int(s[len(s) // 2]))
                else:
                    cum.append(None)
            # Both directions are indexed along the SAME listed order, so the
            # numbers run downhill for direction 1. The subtraction that
            # matters, cum[yours] - cum[the tram's], comes out positive in the
            # direction of travel either way, which is the only property
            # anything downstream relies on.
            #
            # The key is a string because this table goes out as JSON, where
            # an integer key becomes a string anyway. Writing it as one here
            # means the browser and the tests are reading the same shape the
            # server is, rather than one it turns into on the way out.
            per_dir[str(d)] = cum
        out[ln] = per_dir
    return out


def _best_delay(stops, now):
    """How late this tram is, or None when the feed has not actually said.

    A delay needs a TIME beside it. Thirty of the sixty two stop time updates
    in the feed carried none, and every single one of those thirty claimed a
    delay of exactly zero, so believing them writes "on time" against every
    tram ZET has lost track of.

    A delay also has to be a plausible size. The wire carried 3605 and 24000
    in one reading. A night tram is not six hours late; that row is being
    measured against the wrong service day, and it is thrown away rather than
    shown.

    Of what is left, the stop nearest to now wins, and a stop still ahead
    beats one already passed.
    """
    best = None
    out = None
    for upd in stops.values():
        t, dl = upd.get("t"), upd.get("d")
        if dl is None or not t or abs(dl) > DELAY_SANE_S:
            continue
        cand = (0 if t >= now else 1, abs(t - now))
        if best is None or cand < best:
            best, out = cand, int(dl)
    return out


def _in_night_window(now=None):
    """23:50 to 04:40, which is when there is a night tram to be found."""
    now = now or datetime.datetime.now()
    m = now.hour * 60 + now.minute
    return m >= 23 * 60 + 50 or m <= 4 * 60 + 40


def live_payload(now=None):
    """Every night tram the feed is carrying, placed on its line.

    Never raises. A feed that will not answer is a state this has to report,
    not an exception the browser has to guess at from a 500.
    """
    now = int(now or time.time())
    out = {"ok": False, "now": now, "trams": [], "entities": 0,
           "feed_ts": None, "age": None, "state": "unknown",
           "window": _in_night_window(), "routes": list(NIGHT_ROUTES)}
    try:
        feed = parse_rt(fetch_rt())
        # It parsed, which after the reader above is a low bar: a page of
        # zeroes parses into nothing at all. A feed says either what time it
        # is or what is moving, and something that says neither is not one.
        if feed["ts"] is None and feed["entities"] == 0:
            raise ValueError("no timestamp and no vehicles, so this is not a feed")
    except Exception as e:
        out["state"] = "unreachable"
        out["reason"] = str(e)
        _log("live: %r" % (e,))
        return out

    out["ok"] = True
    out["entities"] = feed["entities"]
    out["feed_ts"] = feed["ts"]
    if feed["ts"]:
        age = now - feed["ts"]
        out["age"] = age
        # A clock is wrong in one of the two machines when this is negative,
        # and the phone's is the likelier of the two. Either way it is not a
        # reason to call a live feed stale.
        out["state"] = ("ahead" if age < -FRESH_S else
                        "live" if age <= FRESH_S else
                        "late" if age <= STALE_S else "stale")
    else:
        out["state"] = "undated"

    try:
        net = json.load(open(NIGHT_JSON, encoding="utf-8"))
        coords = json.load(open(COORDS_JSON, encoding="utf-8"))
    except Exception as e:
        out["reason"] = "the night network is not built yet: %s" % e
        return out
    try:
        sched = json.load(open(SCHED_JSON, encoding="utf-8"))
    except Exception:
        sched = {}

    out["run"] = _running_times(net, sched)
    idx = _stop_index(net)
    for trip in feed["trips"].values():
        ln = trip["route_id"]
        if ln not in NIGHT_ROUTES:
            continue
        d, dsrc = _direction_of(trip, ln, idx)
        L = (net.get("lines") or {}).get(ln) or {}
        lat, lon, psrc, pos_age = trip["lat"], trip["lon"], "gps", None
        if lat is not None and trip["pos_ts"]:
            pos_age = max(0, now - trip["pos_ts"])
        if lat is None:
            guess = _locate_from_stops(coords, ln, idx, trip, now)
            if guess:
                lat, lon, psrc, pos_age = guess
        if lat is None:
            psrc = "none"

        near = near_i = near_m = None
        if lat is not None:
            near, near_i, near_m = _nearest_station(net, coords, ln, lat, lon)

        # The feed's own prediction, kept only where it is worth something:
        # for a stop this tram has NOT already passed. Most of them are for
        # stops behind it, which answer a question nobody asked.
        ahead = {}
        for sid, upd in trip["stops"].items():
            hit = idx.get(sid)
            t = upd.get("t")
            if hit and hit[0] == ln and t and t >= now - 30:
                ahead[sid] = t

        delay = _best_delay(trip["stops"], now)

        out["trams"].append({
            "line": ln,
            "trip": trip["trip_id"],
            "car": trip["veh"],
            "dir": d,
            "dir_src": dsrc,
            "towards": (L.get("termB") if d == 0 else L.get("termA")) if d is not None else "",
            "lat": (round(lat, 5) if lat is not None else None),
            "lon": (round(lon, 5) if lon is not None else None),
            "pos_src": psrc,
            "pos_age": pos_age,
            "near": near,
            "near_i": near_i,
            "near_m": (int(near_m) if near_m is not None else None),
            "delay": delay,
            "ahead": ahead,
        })

    out["trams"].sort(key=lambda x: (x["line"], x["near_i"] if x["near_i"] is not None else 999))
    return out
