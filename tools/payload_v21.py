"""payload_v21.py, what v21 does to the payloads. Called from patch_payload.py.

ALL.COMMUTE: THE STATIONS ARE PERMANENT. Marko, 8.10.2026: "make this app cache
all stations so they are permanent. Stations are not moving, only schedule is
changing." and, on the same day: "sometimes these labels for station are
showing, sometimes they're not."

WHY THE LABELS CAME AND WENT. The index was rebuilt every morning from the
timetable of that one day, and the `stops` table was filled from "the stops
that see a departure today". So a station was a by-product of the schedule:

  - a stop served only on weekdays had no label on a Sunday
  - a stop served only by a night line (its rides are filed under the day
    before, as 24:10) had no label on most days
  - a stop on a line that was diverted for the week vanished for the week
  - the label returned the day the timetable did

and the station you had watched, with its colour and its place on the map,
was gone from under the finger with no change in the world. Reproduced with a
four stop feed: three stops on a day with the special service, two on the day
without, and the night stop never.

THE FIX. Stations are their own file, `stations.json`, and the schedule is a
separate thing that is rebuilt around it. Each rebuild MERGES the feed's stops
into the file and never removes one. A bearing, which is worked out from the
rides that leave the stop, is kept from the last day it could be worked out, so
a stop that is quiet today keeps the way it faces. The first rebuild after the
update also takes in every stop of the old index, so nothing already known is
lost. `stops` in the index is filled from the file, so every station is there
whether or not anything leaves it today, and the server reads the file
directly when the index is being rebuilt or has been cleared, so the map is
never without stations. Clearing the index no longer clears the stations.

EVERY STATION IS CARRIED INSIDE THE APP. Marko, 8.10.2026: "hardcode all the
station positions in this app, so stations are shown immediately, always". The
installer writes src/payloads/stations_seed.json (2523 platforms, made from the
real feed by tools/make_stations_seed.py) to ~/.all.commute/stations.json when
there is none, so the first screen draws every station with no download and no
network. Rebuilds merge the live feed into that file and never remove from it.

Two stops in ZET's own feed have coordinates in Russia and Belarus (Kvaternikov
trg, 236_10 at 74.19, 70.74 and 236_13 at 52.91, 29.68). They are dropped when
the feed is read, because a stop that far away is a typo, and because a
bearing worked out from one is nonsense for its neighbours.
"""
import os as _os
with open(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), "..", "src", "payloads",
                        "stations_seed.json"), encoding="utf-8") as _f:
    _SEED = _f.read().strip()
if "ALLC_STATIONS_SEED" in _SEED:
    raise SystemExit("payload_v21: the stations seed contains its own heredoc delimiter")

SEED_STEP = (
    'step "putting every station on the phone"\n'
    'if [ ! -s "$APPDIR/stations.json" ]; then\n'
    "  cat > \"$APPDIR/stations.json.tmp\" << 'ALLC_STATIONS_SEED'\n"
    + _SEED + "\n"
    "ALLC_STATIONS_SEED\n"
    '  mv -f "$APPDIR/stations.json.tmp" "$APPDIR/stations.json"\n'
    "fi\n"
    "done_\n\n")

ALL_FIXES = [
    ('step "installing the station indexer"', SEED_STEP + 'step "installing the station indexer"'),
    ('            coord[r["stop_id"]] = (float(r["stop_lat"]), float(r["stop_lon"]))\n',
     '            _la, _lo = float(r["stop_lat"]), float(r["stop_lon"])\n'
     '            if not (45.3 < _la < 46.3 and 15.3 < _lo < 16.7):\n'
     '                raise ValueError("outside the Zagreb area")\n'
     '            coord[r["stop_id"]] = (_la, _lo)\n'),
    ('APP_VERSION = "v43"\nAPP_BUILD = "b43"', 'APP_VERSION = "v44"\nAPP_BUILD = "b44"'),
    ('<div class="kv"><span>Interface</span><b>stations · v43</b></div>',
     '<div class="kv"><span>Interface</span><b>stations · v44</b></div>'),

    # ---- the rebuild: merge into the permanent file, never replace it -----
    ('CACHE_ZIP = os.path.join(APPDIR, "zet_gtfs.zip")\n',
     'CACHE_ZIP = os.path.join(APPDIR, "zet_gtfs.zip")\n'
     'STATIONS_PATH = os.path.join(APPDIR, "stations.json")\n'),

    ('def db_fresh_for(ymd):\n',
     'def load_stations():\n'
     '    """The permanent stations: {stop_id: [name, lat, lon, bearing]}."""\n'
     '    try:\n'
     '        with open(STATIONS_PATH, encoding="utf-8") as f:\n'
     '            d = json.load(f)\n'
     '        st = d.get("stops") if isinstance(d, dict) else None\n'
     '        return st if isinstance(st, dict) else {}\n'
     '    except Exception:\n'
     '        return {}\n'
     '\n'
     '\n'
     'def save_stations(st):\n'
     '    """Whole file or nothing: written beside it and renamed over it."""\n'
     '    tmp = STATIONS_PATH + ".tmp"\n'
     '    with open(tmp, "w", encoding="utf-8") as f:\n'
     '        json.dump({"updated": int(time.time()), "count": len(st), "stops": st},\n'
     '                  f, ensure_ascii=False, separators=(",", ":"))\n'
     '    os.replace(tmp, STATIONS_PATH)\n'
     '\n'
     '\n'
     'def db_fresh_for(ymd):\n'),

    # ZET's stops.txt lists 1275 PARENT stations (location_type 1: "98" over its
    # platforms "98_1", "98_2") beside the 2525 platforms. A parent has no
    # departures of its own, and keeping it would draw a second label on top of
    # its own platforms. Only platforms are stations here.
    ('    coord = {}\n    for r in rows(zf, "stops.txt"):\n        try:\n',
     '    coord = {}\n    not_platform = set()\n    for r in rows(zf, "stops.txt"):\n'
     '        if (r.get("location_type") or "0").strip() != "0":\n'
     '            not_platform.add(r.get("stop_id"))\n        try:\n'),

    ('    served = {r[0] for r in con.execute("select distinct stop_id from dep")}\n'
     '    log("%d stops actually see a departure today" % len(served))\n'
     '    srows = []\n'
     '    for sid in served:\n'
     '        la, lo = coord[sid]\n'
     '        s_, c_ = sin_sum.get(sid), cos_sum.get(sid)\n'
     '        brg = None\n'
     '        if s_ is not None and (abs(s_) > 1e-9 or abs(c_) > 1e-9):\n'
     '            brg = (math.degrees(math.atan2(s_, c_)) + 360.0) % 360.0\n'
     '        srows.append((sid, name.get(sid, ""), la, lo, brg))\n'
     '    con.executemany("insert or replace into stops values(?,?,?,?,?)", srows)\n'
     '    nstops = len(srows)\n',
     '    served = {r[0] for r in con.execute("select distinct stop_id from dep")}\n'
     '    log("%d stops actually see a departure today" % len(served))\n'
     '    # v21: stations are permanent. What the feed knows is merged into the\n'
     '    # file and nothing is ever taken out of it; the schedule is rebuilt\n'
     '    # around it. A stop with nothing leaving it today is still a station.\n'
     '    perm = load_stations()\n'
     '    if not perm:\n'
     '        # the first rebuild after the update: keep what the old index knew\n'
     '        try:\n'
     '            old = sqlite3.connect(DB_PATH)\n'
     '            for sid, nm, la, lo, br in old.execute(\n'
     '                    "select stop_id, name, lat, lon, bearing from stops"):\n'
     '                perm[str(sid)] = [nm, la, lo, br]\n'
     '            old.close()\n'
     '        except Exception:\n'
     '            pass\n'
     '    for sid, (la, lo) in coord.items():\n'
     '        if sid in not_platform and sid not in served:\n'
     '            continue                # a parent station is not somewhere you stand\n'
     '        s_, c_ = sin_sum.get(sid), cos_sum.get(sid)\n'
     '        brg = None\n'
     '        if s_ is not None and (abs(s_) > 1e-9 or abs(c_) > 1e-9):\n'
     '            brg = (math.degrees(math.atan2(s_, c_)) + 360.0) % 360.0\n'
     '        prev = perm.get(sid)\n'
     '        if brg is None and prev:\n'
     '            brg = prev[3]          # keep the way it faced on the last day it could be told\n'
     '        nm = name.get(sid, "") or (prev[0] if prev else "")\n'
     '        perm[sid] = [nm, la, lo, brg]\n'
     '    srows = [(sid, v[0], v[1], v[2], v[3]) for sid, v in perm.items()]\n'
     '    try:\n'
     '        save_stations(perm)\n'
     '    except Exception as e:\n'
     '        log("could not write stations.json: %r" % (e,))\n'
     '    con.executemany("insert or replace into stops values(?,?,?,?,?)", srows)\n'
     '    nstops = len(srows)\n'
     '    log("%d stations kept for good, %d with a departure today" % (nstops, len(served)))\n'),

    # ---- the server: read the file when the index is not there -------------
    ('def index_ready():\n',
     'STATIONS_PATH = os.path.join(APPDIR, "stations.json")\n'
     '_stations_mem = {"mtime": None, "rows": []}\n'
     '\n'
     '\n'
     'def station_rows():\n'
     '    """Every station there has ever been, from stations.json. [] if none."""\n'
     '    try:\n'
     '        mt = os.path.getmtime(STATIONS_PATH)\n'
     '    except OSError:\n'
     '        return []\n'
     '    if _stations_mem["mtime"] != mt:\n'
     '        try:\n'
     '            with open(STATIONS_PATH, encoding="utf-8") as f:\n'
     '                st = json.load(f).get("stops", {})\n'
     '            _stations_mem["rows"] = [\n'
     '                {"stop_id": k, "name": v[0], "lat": v[1], "lon": v[2], "bearing": v[3]}\n'
     '                for k, v in st.items()]\n'
     '            _stations_mem["mtime"] = mt\n'
     '        except Exception:\n'
     '            return _stations_mem["rows"]\n'
     '    return _stations_mem["rows"]\n'
     '\n'
     '\n'
     'def stations_ready():\n'
     '    """Stations are there if the file has them or the index does."""\n'
     '    return bool(station_rows()) or index_ready()\n'
     '\n'
     '\n'
     'def index_ready():\n'),

    ('    con = db()\n'
     '    rows = con.execute(\n'
     '        "select stop_id, name, lat, lon, bearing from stops"\n'
     '        " where lat between ? and ? and lon between ? and ?",\n'
     '        (lat - dlat, lat + dlat, lon - dlon, lon + dlon)).fetchall()\n'
     '    con.close()\n',
     '    rows = [r for r in station_rows()\n'
     '            if lat - dlat <= r["lat"] <= lat + dlat and lon - dlon <= r["lon"] <= lon + dlon]\n'
     '    if not rows and index_ready():\n'
     '        con = db()\n'
     '        rows = con.execute(\n'
     '            "select stop_id, name, lat, lon, bearing from stops"\n'
     '            " where lat between ? and ? and lon between ? and ?",\n'
     '            (lat - dlat, lat + dlat, lon - dlon, lon + dlon)).fetchall()\n'
     '        con.close()\n'),

    ('                if not index_ready():\n'
     '                    return self._json({"ok": False, "reason": not_ready()})\n'
     '                found, used = stops_near(',
     '                if not stations_ready():\n'
     '                    return self._json({"ok": False, "reason": not_ready()})\n'
     '                found, used = stops_near('),

    ('                if not index_ready():\n'
     '                    return self._json({"ok": False, "reason": not_ready(), "stops": []})\n'
     '                if len(term) < 2:\n'
     '                    return self._json({"ok": True, "stops": []})\n'
     '                con = db()\n'
     '                rows = con.execute(\n'
     '                    "select stop_id, name, lat, lon, bearing from stops"\n'
     '                    " where name like ? or stop_id like ? order by name limit 80",\n'
     '                    ("%" + term + "%", term + "%")).fetchall()\n'
     '                con.close()\n',
     '                if not stations_ready():\n'
     '                    return self._json({"ok": False, "reason": not_ready(), "stops": []})\n'
     '                if len(term) < 2:\n'
     '                    return self._json({"ok": True, "stops": []})\n'
     '                tl = term.lower()\n'
     '                rows = sorted((r for r in station_rows()\n'
     '                               if tl in (r["name"] or "").lower() or r["stop_id"].startswith(term)),\n'
     '                              key=lambda r: r["name"] or "")[:80]\n'
     '                if not rows and index_ready():\n'
     '                    con = db()\n'
     '                    rows = con.execute(\n'
     '                        "select stop_id, name, lat, lon, bearing from stops"\n'
     '                        " where name like ? or stop_id like ? order by name limit 80",\n'
     '                        ("%" + term + "%", term + "%")).fetchall()\n'
     '                    con.close()\n'),
    # ---- the page: the first fix can arrive before the map exists ----------
    # `pageshow` and `focus` call autoLocate() while boot is still awaiting
    # the key, so on a phone that answers quickly the first GPS fix lands
    # BEFORE initFreeMap(). applyFix then threw in drawMe (.addTo(null)) after
    # it had already stored ME, so "first" was never true again, the map never
    # moved to you, and the stations (loaded around you) were drawn a
    # kilometre off screen. Whether the labels showed depended on a race.
    ('let ME = null, meMk = null, meRing = null;',
     'let ME = null, meMk = null, meRing = null;\n'
     'let CENTRED = false;          // true once the map has really been moved to you\n'
     '// The map moves to you ONLY when you press the locate button (WANT_CENTRE), or\n'
     '// once on the very first run, before there is any view of yours to keep. The\n'
     '// dot moves by itself; the map never follows it and never changes zoom.\n'
     'let WANT_CENTRE = false, HAD_VIEW = !!LS.get("view", null);\n'
     'let STOPSEQ = 0;              // the newest stations request; an older answer is dropped\n'),
    ('  const first = !ME;\n'
     '  const moved = ME ? metres(ME.lat, ME.lng, f.lat, f.lng) : 1e9;\n'
     '  ME = { lat: f.lat, lng: f.lng, acc: f.acc, n: f.n };\n'
     '  drawMe();\n'
     '  updateAccBox(); paintChip();\n'
     '  if (first || !inView(ME.lat, ME.lng)) setView(ME, Math.max(17, curZoom()));\n',
     '  const moved = ME ? metres(ME.lat, ME.lng, f.lat, f.lng) : 1e9;\n'
     '  ME = { lat: f.lat, lng: f.lng, acc: f.acc, n: f.n };\n'
     '  // No map yet: the fix is kept (FIXES) and boot calls this again the moment\n'
     '  // the map is up. Nothing is drawn onto a map that is not there.\n'
     '  if (!map && !gmap) return;\n'
     '  drawMe();\n'
     '  updateAccBox(); paintChip();\n'
     '  if (WANT_CENTRE || (!CENTRED && !HAD_VIEW)) { setView(ME, Math.max(17, curZoom())); CENTRED = true; WANT_CENTRE = false; }\n'),
    ('  initFreeMap();\n  applyLayers();\n',
     '  initFreeMap();\n  applyLayers();\n'
     '  if (FIXES.length) applyFix(true);     // a fix that beat the map here\n'),
    ('  b.classList.add("busy");\n  if (ME) setView(ME, Math.max(17, curZoom()));\n',
     '  b.classList.add("busy");\n  WANT_CENTRE = true;          // the button, and only the button, brings the map to you\n  if (ME) { setView(ME, Math.max(17, curZoom())); WANT_CENTRE = false; }\n'),
    # a slow answer must not overwrite a newer one
    ('  lastStopFetch = at;\n  hud("Reading the stations around you…", true);\n',
     '  lastStopFetch = at;\n  const seq = ++STOPSEQ;\n  hud("Reading the stations around you…", true);\n'),
    ('    if (!d.ok) { hud("Server said: " + esc(d.reason || "no reason given")); return; }\n'
     '    STOPS = (d.stops || []).slice(0, 8);\n',
     '    if (seq !== STOPSEQ) return;       // a newer request has gone out since\n'
     '    if (!d.ok) { hud("Server said: " + esc(d.reason || "no reason given")); return; }\n'
     '    STOPS = (d.stops || []).slice(0, 8);\n'),
    # stations are there before the schedule is
    ('    if (d.ok) {\n'
     '      INDEX_OK = true;\n'
     '      if (indexTimer) { clearInterval(indexTimer); indexTimer = null; }\n'
     '      if (!STOPS.length) loadStops();\n'
     '      return;\n'
     '    }\n'
     '    hud("Building the station index. This runs once a day…", true);\n'
     '    if (!indexTimer) indexTimer = setInterval(watchIndex, 4000);\n',
     '    // The stations are permanent (stations.json), so they are drawn at once\n'
     '    // even while the schedule is being rebuilt behind them.\n'
     '    if (d.ok || d.stations) { INDEX_OK = true; if (!STOPS.length) loadStops(); }\n'
     '    if (d.ok) {\n'
     '      if (indexTimer) { clearInterval(indexTimer); indexTimer = null; }\n'
     '      return;\n'
     '    }\n'
     '    if (!d.stations) hud("Building the station index. This runs once a day…", true);\n'
     '    if (!indexTimer) indexTimer = setInterval(watchIndex, 4000);\n'),
    ('def index_status():\n    out = {"ok": index_ready(), "state": BUILD_STATE["state"],\n           "state_reason": BUILD_STATE["reason"]}\n',
     'def index_status():\n    out = {"ok": index_ready(), "state": BUILD_STATE["state"],\n           "state_reason": BUILD_STATE["reason"],\n           "stations": bool(station_rows())}\n'),
]


def patch_all(src):
    """After v20's patch_all, because the version anchors are v20's output."""
    for old, new in ALL_FIXES:
        if src.count(old) != 1:
            raise SystemExit("payload_v21: all, this anchor matches %d times, not once:\n    %s"
                             % (src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)
    return src
