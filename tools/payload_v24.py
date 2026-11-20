"""payload_v24.py, what v24 does to the payloads. Called from patch_payload.py
after v23's patch_all.

ALL.COMMUTE: THE STATIONS ARE THE PAGE'S OWN DATA. Marko, 9.10.2026: "make station
cache permanent. If you can always compare with the stream, recent streams, but
cache it as they are coming. We want to have permanent layout of the station on
both maps available even before map is loaded because it is very much local, it is
not streamed."

Until now the stations were permanent on the phone's disk (stations.json, merged
into and never trimmed, and a copy shipped inside the installer), but the PAGE still
asked the server for the ones near you every time, so on a slow start or a stopped
server it drew nothing. Now:

  the page keeps its own copy of every station in the browser (localStorage). It
  draws the map first, then the stations from that copy, before it asks the
  server for anything: no key request, no status, no stops. Both maps, because
  the stations are drawn by the same code on the free map and on Google's.
  The server publishes the whole list at /stations.json with a revision, the page
  checks the revision in /status and fetches the list only when it has changed,
  so the copy follows the stream without being streamed.

  every rebuild COMPARES the feed with what was cached and keeps the result: how
  many platforms the feed has, how many are new, moved (5 m or more), renamed, and
  how many cached ones the feed no longer lists (kept, never removed). The report
  is in stations.json, in /status, and in the app's Settings.
"""

_OLD_SAVE = ('def save_stations(st):\n'
             '    """Whole file or nothing: written beside it and renamed over it."""\n'
             '    tmp = STATIONS_PATH + ".tmp"\n'
             '    with open(tmp, "w", encoding="utf-8") as f:\n'
             '        json.dump({"updated": int(time.time()), "count": len(st), "stops": st},\n'
             '                  f, ensure_ascii=False, separators=(",", ":"))\n'
             '    os.replace(tmp, STATIONS_PATH)\n')

_NEW_SAVE = ('def _dist_m(a_lat, a_lon, b_lat, b_lon):\n'
             '    p = math.pi / 180\n'
             '    x = (b_lon - a_lon) * p * math.cos((a_lat + b_lat) / 2 * p)\n'
             '    y = (b_lat - a_lat) * p\n'
             '    return 6371000.0 * math.hypot(x, y)\n'
             '\n'
             '\n'
             'def save_stations(st, changes=None):\n'
             '    """Whole file or nothing: written beside it and renamed over it. `changes`\n'
             '    is what comparing the feed with the cache found, kept beside the stations."""\n'
             '    if changes is None:\n'
             '        try:\n'
             '            with open(STATIONS_PATH, encoding="utf-8") as f:\n'
             '                changes = json.load(f).get("changes")\n'
             '        except Exception:\n'
             '            changes = None\n'
             '    tmp = STATIONS_PATH + ".tmp"\n'
             '    doc = {"updated": int(time.time()), "count": len(st), "stops": st}\n'
             '    if changes:\n'
             '        doc["changes"] = changes\n'
             '    with open(tmp, "w", encoding="utf-8") as f:\n'
             '        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))\n'
             '    os.replace(tmp, STATIONS_PATH)\n')

ALL_FIXES = [
    ('APP_VERSION = "v46"\nAPP_BUILD = "b46"', 'APP_VERSION = "v47"\nAPP_BUILD = "b47"'),
    ('<div class="kv"><span>Interface</span><b>stations · v46</b></div>',
     '<div class="kv"><span>Interface</span><b>stations · v47</b></div>'),
    ('ALLC_UI_VERSION="v46"', 'ALLC_UI_VERSION="v47"'),

    # ---- the rebuild compares the feed with the cache, and keeps the answer ----
    (_OLD_SAVE, _NEW_SAVE),
    ('    for sid, (la, lo) in coord.items():\n'
     '        if sid in not_platform and sid not in served:\n',
     '    # v24: compare the feed with what was cached before merging it in\n'
     '    changes = {"at": int(time.time()), "feed": 0, "n_added": 0, "added": [],\n'
     '               "renamed": 0, "moved": 0, "not_in_feed": 0}\n'
     '    seen = set()\n'
     '    for sid, (la, lo) in coord.items():\n'
     '        if sid in not_platform and sid not in served:\n'),
    ('        perm[sid] = [nm, la, lo, brg]\n',
     '        changes["feed"] += 1\n'
     '        seen.add(sid)\n'
     '        if prev is None:\n'
     '            changes["n_added"] += 1\n'
     '            if len(changes["added"]) < 50:\n'
     '                changes["added"].append(sid)\n'
     '        else:\n'
     '            if nm and prev[0] and nm != prev[0]:\n'
     '                changes["renamed"] += 1\n'
     '            if _dist_m(prev[1], prev[2], la, lo) >= 5:\n'
     '                changes["moved"] += 1\n'
     '        perm[sid] = [nm, la, lo, brg]\n'),
    ('    srows = [(sid, v[0], v[1], v[2], v[3]) for sid, v in perm.items()]\n',
     '    changes["not_in_feed"] = sum(1 for k in perm if k not in seen)\n'
     '    log("stations compared with the feed: %d in the feed, %d new, %d moved, %d renamed, "\n'
     '        "%d kept that the feed no longer lists" % (changes["feed"], changes["n_added"],\n'
     '                                                  changes["moved"], changes["renamed"],\n'
     '                                                  changes["not_in_feed"]))\n'
     '    srows = [(sid, v[0], v[1], v[2], v[3]) for sid, v in perm.items()]\n'),
    ('        save_stations(perm)\n    except Exception as e:\n        log("could not write stations.json',
     '        save_stations(perm, changes)\n    except Exception as e:\n        log("could not write stations.json'),

    # ---- the server publishes the list, with a revision ----
    ('def stations_ready():\n',
     '_meta_mem = {"key": None, "meta": {}}\n'
     '\n'
     '\n'
     'def stations_meta():\n'
     '    """The revision of the stations (a hash of the list itself, so a rebuild that\n'
     '    changed nothing does not make every page download it again), how many there\n'
     '    are, and what the last comparison with the feed found."""\n'
     '    try:\n'
     '        stt = os.stat(STATIONS_PATH)\n'
     '    except OSError:\n'
     '        return {}\n'
     '    key = (stt.st_mtime, stt.st_size)\n'
     '    if _meta_mem["key"] != key:\n'
     '        try:\n'
     '            import hashlib as _hl\n'
     '            with open(STATIONS_PATH, encoding="utf-8") as f:\n'
     '                d = json.load(f)\n'
     '            st = d.get("stops", {})\n'
     '            rev = _hl.sha1(json.dumps(st, sort_keys=True, separators=(",", ":")).encode()).hexdigest()[:12]\n'
     '            _meta_mem["meta"] = {"stations_rev": rev, "stations_count": len(st),\n'
     '                                 "stations_changes": d.get("changes")}\n'
     '            _meta_mem["key"] = key\n'
     '        except Exception:\n'
     '            return _meta_mem["meta"]\n'
     '    return _meta_mem["meta"]\n'
     '\n'
     '\n'
     'def stations_ready():\n'),
    ('"stations": bool(station_rows())}\n',
     '"stations": bool(station_rows())}\n    out.update(stations_meta())\n'),
    ('    def _json(self, payload, code=200):\n',
     '    def _raw(self, body, ctype, etag, code=200):\n'
     '        self.send_response(code)\n'
     '        self.send_header("Content-Type", ctype)\n'
     '        self.send_header("ETag", \'"%s"\' % etag)\n'
     '        self.send_header("Content-Length", str(len(body)))\n'
     '        self.end_headers()\n'
     '        self.wfile.write(body)\n'
     '\n'
     '    def _json(self, payload, code=200):\n'),
    ('            if route == "/stops":\n',
     '            if route == "/stations.json":\n'
     '                meta = stations_meta()\n'
     '                if not meta:\n'
     '                    return self._json({"ok": False, "reason": "no stations yet"}, 404)\n'
     '                if (self.headers.get("If-None-Match") or "").strip(\'"\') == meta["stations_rev"]:\n'
     '                    self.send_response(304)\n'
     '                    self.send_header("ETag", \'"%s"\' % meta["stations_rev"])\n'
     '                    self.end_headers()\n'
     '                    return\n'
     '                with open(STATIONS_PATH, "rb") as f:\n'
     '                    body = f.read()\n'
     '                return self._raw(body, "application/json; charset=utf-8", meta["stations_rev"])\n'
     '            if route == "/stops":\n'),

    # ---- the page keeps its own copy, draws from it first ----
    ('let STOPSEQ = 0;              // the newest stations request; an older answer is dropped\n',
     'let STOPSEQ = 0;              // the newest stations request; an older answer is dropped\n'
     '/* THE STATIONS ARE THE PAGE\'S OWN DATA (v24). Every station is kept in the browser,\n'
     '   drawn before anything is asked of the server, and refreshed only when the\n'
     '   server says the list has changed. */\n'
     'let STATION_DB = [], STATION_REV = "";\n'
     'function setStationDB(d){\n'
     '  const st = (d && d.stops) || {};\n'
     '  STATION_DB = Object.keys(st).map(id => { const v = st[id];\n'
     '    return { stop_id: id, name: v[0], lat: v[1], lon: v[2], bearing: v[3] }; });\n'
     '  STATION_REV = (d && d.rev) || "";\n'
     '}\n'
     'function loadStationCache(){\n'
     '  try { const raw = localStorage.getItem("ac2_stations"); if (raw) setStationDB(JSON.parse(raw)); }\n'
     '  catch (e) { STATION_DB = []; }\n'
     '}\n'
     'async function refreshStationCache(rev){\n'
     '  try {\n'
     '    const d = await fetch("stations.json", { cache: "no-cache" }).then(r => r.json());\n'
     '    if (!d || !d.stops) return;\n'
     '    d.rev = rev || "";\n'
     '    setStationDB(d);\n'
     '    try { localStorage.setItem("ac2_stations", JSON.stringify({ rev: d.rev, stops: d.stops })); } catch (e) {}\n'
     '    loadStops();\n'
     '  } catch (e) { /* the copy already held stays */ }\n'
     '}\n'
     '/* the same question /stops answers, answered from the copy */\n'
     'function localStops(at, r, wantMin){\n'
     '  const radii = wantMin ? [r, r * 2, r * 4, 1500, 2500, 4000, 6000].filter(x => x >= r) : [r];\n'
     '  let found = [];\n'
     '  for (const R of radii) {\n'
     '    const dlat = R / 111320, dlon = R / (111320 * Math.max(Math.cos(at.lat * Math.PI / 180), 0.2));\n'
     '    found = [];\n'
     '    for (const s of STATION_DB) {\n'
     '      if (s.lat < at.lat - dlat || s.lat > at.lat + dlat || s.lon < at.lng - dlon || s.lon > at.lng + dlon) continue;\n'
     '      const d = metres(at.lat, at.lng, s.lat, s.lon);\n'
     '      if (d <= R) found.push({ stop_id: s.stop_id, name: s.name, lat: s.lat, lon: s.lon,\n'
     '        dist: Math.round(d), bearing: s.bearing == null ? null : Math.round(s.bearing * 10) / 10 });\n'
     '    }\n'
     '    if (found.length >= wantMin) break;\n'
     '  }\n'
     '  found.sort((a, b) => a.dist - b.dist);\n'
     '  return { ok: true, stops: found.slice(0, 60) };\n'
     '}\n'),
    ('async function loadStops(){\n  if (!INDEX_OK) return;\n',
     'async function loadStops(){\n  if (!INDEX_OK && !STATION_DB.length) return;\n'),
    ('    let d = await fetch("stops?lat=" + at.lat + "&lon=" + at.lng + "&r=" + RADIUS + "&widen=0",\n'
     '      { cache: "no-store" }).then(r => r.json());\n'
     '    let widened = false;\n'
     '    if (d.ok && !(d.stops || []).length) {\n'
     '      d = await fetch("stops?lat=" + at.lat + "&lon=" + at.lng + "&r=" + RADIUS + "&widen=1",\n'
     '        { cache: "no-store" }).then(r => r.json());\n'
     '      widened = true;\n'
     '    }\n',
     '    let d, widened = false;\n'
     '    if (STATION_DB.length) {\n'
     '      // from the page\'s own copy: no request, so no wait and no server needed\n'
     '      d = localStops(at, RADIUS, 0);\n'
     '      if (!d.stops.length) { d = localStops(at, RADIUS, 6); widened = true; }\n'
     '    } else {\n'
     '      d = await fetch("stops?lat=" + at.lat + "&lon=" + at.lng + "&r=" + RADIUS + "&widen=0",\n'
     '        { cache: "no-store" }).then(r => r.json());\n'
     '      if (d.ok && !(d.stops || []).length) {\n'
     '        d = await fetch("stops?lat=" + at.lat + "&lon=" + at.lng + "&r=" + RADIUS + "&widen=1",\n'
     '          { cache: "no-store" }).then(r => r.json());\n'
     '        widened = true;\n'
     '      }\n'
     '    }\n'),
    ('(async function(){\n'
     '  try {\n'
     '    const d = await fetch("api-keys", { cache: "no-store" }).then(r => r.json());\n'
     '    API_KEY = (d.keys || [])[0] || "";\n'
     '  } catch (e) { API_KEY = ""; }\n'
     '  setDot(!!API_KEY);\n'
     '  initFreeMap();\n'
     '  applyLayers();\n',
     '(async function(){\n'
     '  // v24: the map, then the stations from the page\'s own copy, before a single request\n'
     '  initFreeMap();\n'
     '  applyLayers();\n'
     '  loadStationCache();\n'
     '  if (STATION_DB.length) loadStops();\n'
     '  try {\n'
     '    const d = await fetch("api-keys", { cache: "no-store" }).then(r => r.json());\n'
     '    API_KEY = (d.keys || [])[0] || "";\n'
     '  } catch (e) { API_KEY = ""; }\n'
     '  setDot(!!API_KEY);\n'),
    ('    if (d.ok || d.stations) { INDEX_OK = true; if (!STOPS.length) loadStops(); }\n',
     '    // the copy follows the stream: fetched again only when the server\'s list has changed\n'
     '    if (d.stations_rev && d.stations_rev !== STATION_REV) refreshStationCache(d.stations_rev);\n'
     '    if (d.ok || d.stations) { INDEX_OK = true; if (!STOPS.length) loadStops(); }\n'),
    ('      \'<div class="kv"><span>Stations</span><b>\' + (d.ok ? "cached" : "not cached") + \'</b></div>\' +\n',
     '      \'<div class="kv"><span>Stations</span><b>\' + (STATION_DB.length ? STATION_DB.length + " kept for good"\n'
     '        : (d.ok ? "cached" : "not cached")) + \'</b></div>\' +\n'
     '      (d.stations_changes ? \'<div class="kv"><span>Last feed</span><b>\' + d.stations_changes.feed + " platforms, " +\n'
     '        d.stations_changes.n_added + " new, " + d.stations_changes.moved + " moved, " +\n'
     '        d.stations_changes.renamed + " renamed</b></div>" : "") +\n'),
]


def patch_all(src):
    for old, new in ALL_FIXES:
        if src.count(old) != 1:
            raise SystemExit("payload_v24: all, this anchor matches %d times, not once:\n    %s"
                             % (src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)
    return src
