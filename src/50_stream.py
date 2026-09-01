#!/usr/bin/env python3
"""stream.py, written by the MAHA COMMUTE installer.

Two jobs, one file, shared by all three apps because all three drink from
the same two ZET taps:

    the static schedule    https://www.zet.hr/gtfs-scheduled/latest   a zip
    the live feed          https://zet.hr/gtfs-rt-protobuf            protobuf

    python stream.py check     say whether what is arriving is sound
    python stream.py refresh   throw the cached copies away
    python stream.py refresh --check   both, in that order

WHY THIS EXISTS

An app that asks "did the download work" gets yes, and shows old data with
total confidence. Every one of the three apps checks the transport and none
of them checks the CARGO. A feed can be:

    stalled       200 OK, right size, right shape, and a header timestamp
                  from forty minutes ago. This is the common one and it is
                  invisible without reading that timestamp
    thin          200 OK and eleven vehicles in a city that runs six hundred
    disagreeing   live trip ids that are not in the static build the app is
                  holding, because ZET published a new schedule and the app
                  is a day behind. The field does not fit the timetable
    expired       a static build whose calendar ended before today
    misplaced     vehicles at 0,0 or in the Adriatic
    skewed        nothing wrong with the feed at all, the phone's clock is out

Each of those is a different fault with a different fix, and from inside the
app they all look the same: wrong numbers on the screen. So each is measured
separately and named separately.

Nothing here writes to any app's folder except to delete a cache. It never
touches a key, a station index, a stored timetable or a note.
"""

import json
import os
import struct
import sys
import time
import zipfile

APPHOME = os.path.join(os.path.expanduser("~"), ".maha.commute")
RT_URL = "https://zet.hr/gtfs-rt-protobuf"
STATIC_URL = "https://www.zet.hr/gtfs-scheduled/latest"
UA = "maha.commute-stream/1"

# Zagreb, generously. A vehicle outside this is not a vehicle.
LAT_MIN, LAT_MAX = 45.60, 46.05
LON_MIN, LON_MAX = 15.65, 16.30

# What may be deleted, per app. An allowlist and not a wildcard, because a
# refresh that also takes the station index or the stored timetables costs
# an hour of rebuilding and looks like the refresh broke the app.
CACHES = {
    "day": {
        "dir": ".commute",
        "files": ["zet_gtfs.zip", "bus.json", "trips_path.json", "gtfs_meta.json"],
        "dirs": ["daycache"],
        "keep": ["google-api.txt", "gemini-api.txt", "settings.json", "port",
                 "server.log", "pinned.txt"],
    },
    "night": {
        "dir": ".nightcommute",
        "files": ["zet_gtfs.zip"],
        "dirs": [],
        "keep": ["gmaps-api.txt", "gemini-api.txt", "port", "server.out"],
    },
    "all": {
        "dir": ".all.commute",
        "files": ["zet_gtfs.zip"],
        "dirs": [],
        "keep": ["google-api.txt", "gemini-api.txt", "stations.json",
                 "timetables", "all.html", "all_commute_server.py", "port"],
    },
}

STATE = os.path.join(APPHOME, "stream_state.json")


# ---------------------------------------------------------------------------
# a protobuf reader that reads only what it needs
#
# GTFS realtime is protobuf, and the phone has no protobuf library. Only
# three things are wanted: the header timestamp, how many entities there
# are, and the trip id and position inside each one. Wire types are enough
# for that: every field carries its own type, so an unknown field is
# skipped by length rather than guessed at.
# ---------------------------------------------------------------------------

def _varint(b, i):
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


def _fields(b, start=0, end=None):
    """Yield (field_number, wire_type, value_or_slice) across one message."""
    i = start
    end = len(b) if end is None else end
    while i < end:
        key, i = _varint(b, i)
        fn, wt = key >> 3, key & 7
        if wt == 0:
            v, i = _varint(b, i)
            yield fn, wt, v
        elif wt == 1:
            v = b[i:i + 8]
            i += 8
            yield fn, wt, v
        elif wt == 2:
            ln, i = _varint(b, i)
            if i + ln > end:
                raise ValueError("length delimited field runs past the end")
            yield fn, wt, b[i:i + ln]
            i += ln
        elif wt == 5:
            v = b[i:i + 4]
            i += 4
            yield fn, wt, v
        else:
            raise ValueError("wire type %d, which this feed should not contain" % wt)


def parse_feed(b):
    """FeedMessage -> a small dictionary. Raises on anything malformed."""
    out = {"header_ts": None, "version": None, "entities": 0,
           "trip_ids": [], "positions": [], "entity_ts": []}
    for fn, wt, v in _fields(b):
        if fn == 1 and wt == 2:                      # FeedHeader
            for hfn, hwt, hv in _fields(v):
                if hfn == 1 and hwt == 2:
                    out["version"] = hv.decode("utf-8", "replace")
                elif hfn == 3 and hwt == 0:
                    out["header_ts"] = hv
        elif fn == 2 and wt == 2:                    # FeedEntity
            out["entities"] += 1
            _entity(v, out)
    return out


def _entity(b, out):
    for fn, wt, v in _fields(b):
        if wt != 2:
            continue
        if fn in (3, 4):                             # TripUpdate, VehiclePosition
            for sfn, swt, sv in _fields(v):
                if sfn == 1 and swt == 2:            # TripDescriptor
                    for tfn, twt, tv in _fields(sv):
                        if tfn == 1 and twt == 2:
                            out["trip_ids"].append(tv.decode("utf-8", "replace"))
                elif fn == 4 and sfn == 2 and swt == 2:   # Position
                    lat = lon = None
                    for pfn, pwt, pv in _fields(sv):
                        if pfn == 1 and pwt == 5:
                            lat = struct.unpack("<f", pv)[0]
                        elif pfn == 2 and pwt == 5:
                            lon = struct.unpack("<f", pv)[0]
                    if lat is not None and lon is not None:
                        out["positions"].append((lat, lon))
                elif swt == 0 and sfn in (4, 5):     # a timestamp on the entity
                    if sv > 1000000000:
                        out["entity_ts"].append(sv)


# ---------------------------------------------------------------------------
# the checks
# ---------------------------------------------------------------------------

class Result(list):
    def add(self, level, name, detail):
        self.append((level, name, detail))

    @property
    def bad(self):
        return sum(1 for lvl, _, _ in self if lvl == "bad")

    @property
    def warn(self):
        return sum(1 for lvl, _, _ in self if lvl == "warn")


def _get(url, timeout=20):
    import urllib.request
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read()
        # Lower cased on the way out. dict(r.headers) keeps the server's own
        # capitalisation and a plain dict lookup is case sensitive, so
        # headers.get("Content-Type") came back None against the real feed
        # and the "is this an HTML error page" check would never have fired.
        # A check that cannot fire looks exactly like a check that passes.
        heads = {k.lower(): v for k, v in r.headers.items()}
        return body, r.status, heads, time.time() - t0


def _state():
    try:
        with open(STATE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _save_state(s):
    os.makedirs(APPHOME, exist_ok=True)
    tmp = STATE + ".new"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(s, f)
    os.replace(tmp, STATE)


def check_live(res, state):
    """The live feed: does it arrive, is it fresh, is it moving, does it fit."""
    try:
        body, status, headers, took = _get(RT_URL)
    except Exception as e:
        res.add("bad", "live feed", "did not answer: %s" % e)
        return None
    ctype = headers.get("content-type", "")
    res.add("ok", "live feed answered", "%d, %d bytes, %.1fs" % (status, len(body), took))

    # A captive portal or an error page is HTML and is still 200.
    if body[:15].lstrip()[:1] == b"<" or "html" in ctype.lower():
        res.add("bad", "live feed shape", "this is a web page, not a feed")
        return None
    if len(body) < 200:
        res.add("bad", "live feed size", "%d bytes is too small to be a feed" % len(body))
        return None
    try:
        feed = parse_feed(body)
    except Exception as e:
        res.add("bad", "live feed parse", "malformed protobuf: %s" % e)
        return None

    now = int(time.time())
    ts = feed["header_ts"]
    if not ts:
        res.add("warn", "live feed timestamp", "the feed carries no header timestamp")
    else:
        age = now - ts
        if age < 0:
            res.add("warn", "live feed timestamp",
                    "dated %ds in the FUTURE, so one of the two clocks is wrong" % -age)
        elif age <= 120:
            res.add("ok", "live feed is fresh", "%ds old" % age)
        elif age <= 600:
            res.add("warn", "live feed is late", "%d minutes old" % (age // 60))
        else:
            res.add("bad", "live feed is stale",
                    "%d minutes old. The numbers on the screen are from then, "
                    "not from now" % (age // 60))

    # An independent witness. The header timestamp is written by whoever
    # builds the feed; Last-Modified is written by the server that serves it.
    # When those two disagree by a lot, something in between is holding a
    # copy, and that is a different fault from a publisher that has stopped.
    lm = headers.get("last-modified")
    if lm and ts:
        try:
            import email.utils
            lmts = int(email.utils.parsedate_to_datetime(lm).timestamp())
            drift = abs(lmts - ts)
            if drift > 300:
                res.add("warn", "feed and server disagree",
                        "the body says %ds ago, the server says %ds ago, so "
                        "something between them is serving a copy"
                        % (now - ts, now - lmts))
            else:
                res.add("ok", "server agrees with the body", "within %ds" % drift)
        except Exception:
            pass

    # Stalled: the same header timestamp handed out again, some time later.
    prev = state.get("rt")
    if prev and ts and prev.get("header_ts") == ts:
        gap = int(time.time() - prev.get("seen_at", 0))
        if gap > 90:
            res.add("bad", "live feed is stalled",
                    "the same timestamp %ds apart, so nothing is being published" % gap)
    if ts:
        state["rt"] = {"header_ts": ts, "seen_at": int(time.time()),
                       "entities": feed["entities"]}

    # Thin: a collapse in vehicle count is a fault even when everything parses.
    n = feed["entities"]
    base = state.get("rt_baseline")
    if n == 0:
        res.add("bad", "live feed is empty", "0 vehicles")
    elif base and n < max(5, base * 0.3):
        res.add("bad", "live feed is thin",
                "%d vehicles against a usual %d" % (n, base))
    elif base and n < base * 0.6:
        res.add("warn", "live feed is thin", "%d vehicles against a usual %d" % (n, base))
    else:
        res.add("ok", "live vehicles", "%d" % n)
    if n:
        state["rt_baseline"] = int(base * 0.8 + n * 0.2) if base else n

    # Misplaced: a position outside Zagreb is not a Zagreb tram.
    bad_pos = [p for p in feed["positions"]
               if not (LAT_MIN <= p[0] <= LAT_MAX and LON_MIN <= p[1] <= LON_MAX)]
    if feed["positions"]:
        if bad_pos:
            res.add("bad", "vehicles off the map",
                    "%d of %d outside Zagreb, first at %.4f,%.4f"
                    % (len(bad_pos), len(feed["positions"]), bad_pos[0][0], bad_pos[0][1]))
        else:
            res.add("ok", "vehicle positions", "%d, all inside Zagreb" % len(feed["positions"]))

    # Skew: if the phone's clock is out, every departure is wrong and the
    # feed is innocent. Worth separating, because the fix is a different one.
    if feed["entity_ts"]:
        newest = max(feed["entity_ts"])
        skew = now - newest
        if abs(skew) > 900 and ts and abs(now - ts) > 900:
            res.add("warn", "clock",
                    "the phone and the feed disagree by %d minutes. Check the "
                    "phone's own clock before blaming ZET" % (abs(skew) // 60))
    return feed


def check_static(res, feed):
    """The schedule each app is holding: is it current, and does the live
    feed agree with it. This is the one that catches 'the field does not
    fit the timetable'."""
    for app, spec in CACHES.items():
        z = os.path.join(os.path.expanduser("~"), spec["dir"], "zet_gtfs.zip")
        if not os.path.exists(z):
            res.add("ok", "%s schedule" % app, "no cached copy yet")
            continue
        age_h = (time.time() - os.path.getmtime(z)) / 3600.0
        try:
            with zipfile.ZipFile(z) as zf:
                names = zf.namelist()
                if "trips.txt" not in names:
                    res.add("bad", "%s schedule" % app, "the zip has no trips.txt")
                    continue
                ymd = time.strftime("%Y%m%d")
                covered = None
                if "calendar.txt" in names:
                    covered = False
                    head = None
                    for raw in zf.open("calendar.txt"):
                        line = raw.decode("utf-8", "replace").strip()
                        if head is None:
                            head = [c.strip() for c in line.split(",")]
                            continue
                        row = dict(zip(head, line.split(",")))
                        if row.get("start_date", "0") <= ymd <= row.get("end_date", "9"):
                            covered = True
                            break
                trip_ids = set()
                head = None
                for raw in zf.open("trips.txt"):
                    line = raw.decode("utf-8", "replace").strip()
                    if head is None:
                        head = [c.strip() for c in line.split(",")]
                        continue
                    row = dict(zip(head, line.split(",")))
                    if row.get("trip_id"):
                        trip_ids.add(row["trip_id"])
        except zipfile.BadZipFile:
            res.add("bad", "%s schedule" % app, "the cached zip is not a zip")
            continue
        except Exception as e:
            res.add("bad", "%s schedule" % app, "unreadable: %s" % e)
            continue

        if covered is False:
            res.add("bad", "%s schedule expired" % app,
                    "no service period in it covers today. Refresh it")
        elif age_h > 24 * 8:
            res.add("warn", "%s schedule age" % app, "%d days old" % (age_h / 24))
        else:
            res.add("ok", "%s schedule" % app,
                    "%d trips, %d hours old" % (len(trip_ids), age_h))

        # The agreement check. Live trip ids that the held schedule has never
        # heard of mean the two are from different builds, and every lookup
        # against them silently misses.
        if feed and feed["trip_ids"] and trip_ids:
            live = set(feed["trip_ids"])
            miss = live - trip_ids
            pct = 100.0 * len(miss) / len(live)
            if pct >= 50:
                res.add("bad", "%s does not fit the field" % app,
                        "%.0f%% of live trips are not in this schedule, so the two "
                        "are different builds" % pct)
            elif pct >= 10:
                res.add("warn", "%s partly fits the field" % app,
                        "%.0f%% of live trips are unknown to it" % pct)
            else:
                res.add("ok", "%s fits the field" % app,
                        "%.0f%% of live trips unknown, which is normal churn" % pct)


def check_reachable(res):
    """The static tap itself, without downloading forty megabytes."""
    import urllib.request
    req = urllib.request.Request(STATIC_URL, method="HEAD",
                                 headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            ln = r.headers.get("Content-Length")
            res.add("ok", "schedule tap", "%d%s" % (r.status,
                    ", %s bytes" % ln if ln else ""))
    except Exception as e:
        res.add("warn", "schedule tap", "no answer to a HEAD: %s" % e)


# ---------------------------------------------------------------------------
# refresh
# ---------------------------------------------------------------------------

def refresh(only=None):
    import shutil
    home = os.path.expanduser("~")
    removed, kept, freed = 0, 0, 0
    for app, spec in CACHES.items():
        if only and app != only:
            continue
        base = os.path.join(home, spec["dir"])
        if not os.path.isdir(base):
            continue
        for name in spec["files"]:
            p = os.path.join(base, name)
            if os.path.isfile(p):
                freed += os.path.getsize(p)
                os.remove(p)
                removed += 1
        for name in spec["dirs"]:
            p = os.path.join(base, name)
            if os.path.isdir(p):
                for root, _, files in os.walk(p):
                    for f in files:
                        freed += os.path.getsize(os.path.join(root, f))
                        removed += 1
                shutil.rmtree(p, ignore_errors=True)
        kept += sum(1 for k in spec["keep"] if os.path.exists(os.path.join(base, k)))
    st = _state()
    st.pop("rt", None)
    _save_state(st)
    return removed, kept, freed


# ---------------------------------------------------------------------------

COLOURS = {"ok": "\033[1;32m", "warn": "\033[38;5;214m", "bad": "\033[1;31m"}
OFF = "\033[0m"
MARK = {"ok": "ok  ", "warn": "look", "bad": "FAIL"}


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "check"
    tty = sys.stdout.isatty()

    def paint(level, text):
        return (COLOURS[level] + text + OFF) if tty else text

    if cmd == "refresh":
        removed, kept, freed = refresh()
        print("  %s  %d cached files thrown away, %.1f MB"
              % (paint("ok", "refreshed"), removed, freed / 1048576.0))
        print("  %d keys, indexes and stored timetables left alone" % kept)
        print("  each app rebuilds its schedule the next time it starts")
        if "--check" not in argv:
            return 0
        print("")

    res = Result()
    state = _state()
    feed = check_live(res, state)
    check_static(res, feed)
    check_reachable(res)
    _save_state(state)

    print("")
    # Stacked, like the key tester, for the same reason: a phone terminal
    # is about fifty characters and a feed error arrives longer than that.
    import textwrap
    for level, name, detail in res:
        print("  %s  %s" % (paint(level, MARK[level]), name))
        for chunk in textwrap.wrap(detail, 44, break_long_words=True):
            print("        %s" % chunk)
    print("")
    print("  %d checks, %d faults, %d worth a look"
          % (len(res), res.bad, res.warn))
    if res.bad:
        print("  a refresh is the first thing to try:  maha-commute refresh")
    print("")
    return 1 if res.bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
