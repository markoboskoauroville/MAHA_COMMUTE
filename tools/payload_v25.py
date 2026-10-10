"""payload_v25.py, what v25 does to the payloads. Called from patch_payload.py
after v24's patch_all (the anchors are v24's output).

Marko, 10.10.2026: "Everything what can be common between the three apps should be
common. The station list also, so you can build a server inside the app with the
station list which progressively updates the station list as I am scrolling through
the map and keeps it cached forever."

WHAT IS COMMON NOW (one copy, in ~/.maha.commute/common/, which the umbrella makes)

  zet_gtfs.zip and its .meta.json   the ZET timetable. day, night and all each used to
                                    keep and download their own 12 MB copy; they now read
                                    and write ONE, written whole or not at all (a
                                    temporary file renamed over it), so two apps
                                    rebuilding at once cannot leave half a file.
  stations.json                     every ZET platform, merged into and never trimmed
                                    (v21 to v24), now shared rather than all.commute's own.
  osm_stops.json                    stops found by scrolling, below.
  ../keys/google-api.txt            the one Google key (v22).

THE STATION SERVER (all.commute)

The page used to draw the stations around the GPS dot only. It now draws the stations
in the map's VIEW, whatever the view is: scroll, and the stations follow, from the
page's own copy, with no request. At zoom 14 and out there are too many to label, so it
says to zoom in; 15 shows the 12 nearest the centre, 16 the 20, 17 the 28, 18 and in 36.

Beyond ZET's own network (a village, another city) the list is empty, so the app
discovers stops as you scroll: for each 14-zoom tile in view that has no known station,
the SERVER asks OpenStreetMap's Overpass for its bus and tram stops, one tile every 5
seconds, and keeps the answer in osm_stops.json for ever, the empty ones too, so a tile
is never asked twice. The page keeps what it is told (localStorage, also for ever) and
remembers which tiles are done. Those stops have no ZET timetable: their label is the
stop's name, and their dashboard shows the photograph and nothing coming. Overpass is
asked only from zoom 15 in, only for tiles with no ZET station, and can be turned off with
MAHA_OVERPASS_URL=off. It is the one place this app sends a map position anywhere, which
is why it is written here and in MEMORY.md.
"""

# ---- common paths, in the three payloads ------------------------------------
_ATOMIC_ZIP = ('                tmp_zip = CACHE_ZIP + ".tmp"\n'
               '                os.makedirs(os.path.dirname(CACHE_ZIP), exist_ok=True)\n'
               '                with open(tmp_zip, "wb") as f:\n'
               '                    f.write(data)\n'
               '                os.replace(tmp_zip, CACHE_ZIP)    # whole file or nothing, shared by three apps\n')

# ------------------------------------------------------------- all.commute
SERVER_DISCOVERY = r'''# ---- v25: the common station service ----------------------------------------
OSM_PATH = os.path.join(COMMON_DIR, "osm_stops.json")
OVERPASS_URL = os.environ.get("MAHA_OVERPASS_URL", "https://overpass-api.de/api/interpreter")
_osm = {"lock": threading.Lock(), "doc": None, "q": [], "worker": False, "last": 0.0, "fail": {}}


def _osm_doc():
    if _osm["doc"] is None:
        try:
            with open(OSM_PATH, encoding="utf-8") as f:
                d = json.load(f)
            if not isinstance(d, dict):
                d = {}
        except Exception:
            d = {}
        d.setdefault("stops", {})
        d.setdefault("tiles", {})
        _osm["doc"] = d
    return _osm["doc"]


def _osm_save():
    os.makedirs(COMMON_DIR, exist_ok=True)
    tmp = OSM_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(_osm["doc"], f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, OSM_PATH)


def _tile_of(lat, lon, z=14):
    n = 2 ** z
    x = int((lon + 180.0) / 360.0 * n)
    y = int((1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n)
    return x, y


def _tile_box(x, y, z=14):
    n = 2 ** z

    def lat(yy):
        return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * yy / n))))
    return lat(y + 1), x / n * 360.0 - 180.0, lat(y), (x + 1) / n * 360.0 - 180.0   # s, w, n, e


def _tile_known(x, y):
    """A tile is known when it was discovered once, or ZET already has a station in it."""
    with _osm["lock"]:
        if "%d/%d" % (x, y) in _osm_doc()["tiles"]:
            return True
    s, w, n, e = _tile_box(x, y)
    return any(s <= r["lat"] <= n and w <= r["lon"] <= e for r in station_rows())


def _overpass(s, w, n, e):
    q = ('[out:json][timeout:25];(node["highway"="bus_stop"](%f,%f,%f,%f);'
         'node["railway"~"^(tram_stop|station|halt)$"](%f,%f,%f,%f););out body;') % (s, w, n, e, s, w, n, e)
    req = urllib.request.Request(
        OVERPASS_URL, data=urllib.parse.urlencode({"data": q}).encode(),
        headers={"User-Agent": "MAHA-COMMUTE all.commute (a local app, one request per map tile, cached for good)"})
    with urllib.request.urlopen(req, timeout=40) as r:
        d = json.loads(r.read().decode("utf-8", "replace"))
    out = {}
    for el in d.get("elements", []):
        if el.get("type") != "node" or "lat" not in el:
            continue
        t = el.get("tags") or {}
        name = (t.get("name") or t.get("ref") or ("tram stop" if t.get("railway") else "bus stop"))[:40]
        out["osm:n%d" % el["id"]] = [name, round(el["lat"], 6), round(el["lon"], 6), None]
    return out


def _osm_worker():
    while True:
        with _osm["lock"]:
            if not _osm["q"]:
                _osm["worker"] = False
                return
            x, y = _osm["q"].pop(0)
        until = _osm["fail"].get((x, y), 0)
        if time.time() < until:
            continue                         # backing off after a failure; the page asks again
        wait = float(os.environ.get("MAHA_OVERPASS_GAP", "5")) - (time.time() - _osm["last"])
        if wait > 0:
            time.sleep(wait)
        _osm["last"] = time.time()
        try:
            found = _overpass(*_tile_box(x, y))
        except Exception as e:
            _osm["fail"][(x, y)] = time.time() + 15
            _log("overpass failed for tile 14/%d/%d: %r" % (x, y, e))
            continue
        with _osm["lock"]:
            d = _osm_doc()
            d["stops"].update(found)
            d["tiles"]["%d/%d" % (x, y)] = {"at": int(time.time()), "n": len(found)}
            try:
                _osm_save()
            except Exception as e:
                _log("could not write osm_stops.json: %r" % (e,))
        _log("discovered %d stops in tile 14/%d/%d" % (len(found), x, y))


def _osm_enqueue(x, y):
    with _osm["lock"]:
        if (x, y) not in _osm["q"]:
            _osm["q"].append((x, y))
        if not _osm["worker"]:
            _osm["worker"] = True
            threading.Thread(target=_osm_worker, daemon=True).start()


def stations_view(s, w, n, e, zoom):
    """What the map is looking at: the discovered stops inside it, and how many tiles
    of it are still being asked for. The ZET stations are not sent: the page has them."""
    out = []
    with _osm["lock"]:
        for k, v in _osm_doc()["stops"].items():
            if s <= v[1] <= n and w <= v[2] <= e:
                out.append([k, v[0], v[1], v[2], None])
                if len(out) >= 600:
                    break
    pending = 0
    if zoom >= 15 and OVERPASS_URL != "off":
        x0, y0 = _tile_of(n, w)
        x1, y1 = _tile_of(s, e)
        tiles = [(x, y) for x in range(min(x0, x1), max(x0, x1) + 1)
                 for y in range(min(y0, y1), max(y0, y1) + 1)][:16]
        for (x, y) in tiles:
            if _tile_known(x, y):
                continue
            pending += 1
            _osm_enqueue(x, y)
    return {"ok": True, "osm": out, "pending": pending}


'''

SERVER_ROUTE = '''            if route == "/stations/view":
                try:
                    vs, vw = float(q["s"][0]), float(q["w"][0])
                    vn, ve = float(q["n"][0]), float(q["e"][0])
                    vz = int(float(q.get("zoom", ["0"])[0]))
                except Exception:
                    return self._json({"ok": False, "reason": "s, w, n, e and zoom are needed"}, 400)
                if not (-90 <= vs < vn <= 90 and -180 <= vw < ve <= 180) or vn - vs > 0.6 or ve - vw > 0.9:
                    return self._json({"ok": False, "reason": "that is not a map view"}, 400)
                return self._json(stations_view(vs, vw, vn, ve, vz))
'''

# the page
PAGE_JS = r'''/* v25: THE STATIONS FOLLOW THE MAP. Whatever the map is looking at, the stations in it
   are drawn, from the page's own copy. Beyond ZET's network the server discovers stops
   tile by tile as you scroll (stations_view in the server), the page keeps them for
   good, and remembers which tiles are done. */
let STATION_X = {}, STOPSIG = "", TILESDONE = {}, DISC_TRIES = {}, VIEW_T = null, VIEWINFO = null;
function isOsm(id){ return String(id).indexOf("osm:") === 0; }
function pinText(s){
  if (!isOsm(s.stop_id)) return s.stop_id;
  const n = s.name || "stop";
  return n.length > 14 ? n.slice(0, 13) + "…" : n;
}
function mergeExtras(){
  const have = new Set(STATION_DB.map(s => s.stop_id));
  Object.keys(STATION_X).forEach(id => {
    if (have.has(id)) return;
    const v = STATION_X[id];
    STATION_DB.push({ stop_id: id, name: v[0], lat: v[1], lon: v[2], bearing: v[3] });
  });
}
function viewBounds(){
  try {
    if (usingGoogle()) {
      const b = gmap.getBounds(); if (!b) return null;
      const sw = b.getSouthWest(), ne = b.getNorthEast(), c = gmap.getCenter();
      return { s: sw.lat(), w: sw.lng(), n: ne.lat(), e: ne.lng(), z: gmap.getZoom(), cy: c.lat(), cx: c.lng() };
    }
    if (!map) return null;
    const b = map.getBounds(), c = map.getCenter();
    return { s: b.getSouth(), w: b.getWest(), n: b.getNorth(), e: b.getEast(), z: map.getZoom(), cy: c.lat, cx: c.lng };
  } catch (e) { return null; }
}
function viewStops(){
  const v = viewBounds();
  const cap = v.z >= 18 ? 36 : (v.z === 17 ? 28 : (v.z === 16 ? 20 : (v.z === 15 ? 12 : 0)));
  VIEWINFO = { z: v.z, cap: cap, n: 0 };
  if (!cap) return { ok: true, stops: [] };
  const mlat = (v.n - v.s) * 0.03, mlon = (v.e - v.w) * 0.03;
  const ref = ME ? { lat: ME.lat, lng: ME.lng } : { lat: v.cy, lng: v.cx };
  const inView = [];
  for (const s of STATION_DB) {
    if (s.lat < v.s + mlat || s.lat > v.n - mlat || s.lon < v.w + mlon || s.lon > v.e - mlon) continue;
    inView.push({ stop_id: s.stop_id, name: s.name, lat: s.lat, lon: s.lon,
      bearing: s.bearing == null ? null : Math.round(s.bearing * 10) / 10,
      dc: metres(v.cy, v.cx, s.lat, s.lon), dist: Math.round(metres(ref.lat, ref.lng, s.lat, s.lon)) });
  }
  inView.sort((a, b) => a.dc - b.dc);
  VIEWINFO.n = inView.length;
  return { ok: true, stops: inView.slice(0, cap) };
}
function viewLine(){
  const i = VIEWINFO;
  if (!i) return "";
  if (!i.cap) return "Zoom in to see the stations. They are labelled from zoom 15.";
  if (!STOPS.length) return "No station in this view. Scroll or zoom out a little.";
  return "<b>" + STOPS.length + "</b> of " + i.n + " station" + (i.n === 1 ? "" : "s") +
    " in view. Tap a station to see what is coming.";
}
function scheduleView(){ clearTimeout(VIEW_T); VIEW_T = setTimeout(loadStops, 250); }
function tileKeys(v){
  const n = 16384;
  const tx = lon => Math.floor((lon + 180) / 360 * n);
  const ty = lat => Math.floor((1 - Math.asinh(Math.tan(lat * Math.PI / 180)) / Math.PI) / 2 * n);
  const keys = [], x0 = tx(v.w), x1 = tx(v.e), y0 = ty(v.n), y1 = ty(v.s);
  for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) { keys.push(x + "/" + y); if (keys.length >= 16) return keys; }
  return keys;
}
function tileHasStation(k){
  const n = 16384, p = k.split("/"), x = +p[0], y = +p[1];
  const lat = yy => Math.atan(Math.sinh(Math.PI * (1 - 2 * yy / n))) * 180 / Math.PI;
  const s = lat(y + 1), nn = lat(y), w = x / n * 360 - 180, e = (x + 1) / n * 360 - 180;
  return STATION_DB.some(t => !isOsm(t.stop_id) && t.lat >= s && t.lat <= nn && t.lon >= w && t.lon <= e);
}
async function maybeDiscover(){
  const v = viewBounds();
  if (!v || v.z < 15) return;
  // a tile that ZET already has stations in, or that was done before, is never asked about
  const keys = tileKeys(v).filter(k => !TILESDONE[k] && !tileHasStation(k));
  if (!keys.length) return;
  const tag = keys.join(",");
  DISC_TRIES[tag] = (DISC_TRIES[tag] || 0) + 1;
  if (DISC_TRIES[tag] > 8) return;
  try {
    const d = await fetch("stations/view?s=" + v.s.toFixed(5) + "&w=" + v.w.toFixed(5) + "&n=" + v.n.toFixed(5) +
      "&e=" + v.e.toFixed(5) + "&zoom=" + v.z, { cache: "no-store" }).then(r => r.json());
    if (!d || !d.ok) return;
    let added = false;
    (d.osm || []).forEach(r => { if (!STATION_X[r[0]]) { STATION_X[r[0]] = [r[1], r[2], r[3], r[4]]; added = true; } });
    if (added) { try { localStorage.setItem("ac2_stations_x", JSON.stringify(STATION_X)); } catch (e) {} mergeExtras(); }
    if (!d.pending) {
      keys.forEach(k => { TILESDONE[k] = 1; });
      try { localStorage.setItem("ac2_tiles", JSON.stringify(Object.keys(TILESDONE))); } catch (e) {}
    } else setTimeout(maybeDiscover, 8000);
    if (added) scheduleView();
  } catch (e) { /* offline: the next move asks again */ }
}
'''

_BOARD_NONE = ('{ ok: true, departures: [], feed_ok: false, osm: true }')

ALL_FIXES = [
    ('APP_VERSION = "v47"\nAPP_BUILD = "b47"', 'APP_VERSION = "v48"\nAPP_BUILD = "b48"'),
    ('<div class="kv"><span>Interface</span><b>stations · v47</b></div>',
     '<div class="kv"><span>Interface</span><b>stations · v48</b></div>'),
    ('ALLC_UI_VERSION="v47"', 'ALLC_UI_VERSION="v48"'),

    # ---- common paths: the stations and the timetable are shared -------------
    ('STATIONS_PATH = os.path.join(APPDIR, "stations.json")\n_stations_mem = {"mtime": None, "rows": []}\n',
     '# v25: one folder for what the three apps share (MAHA_COMMON lets a test move it)\n'
     'COMMON_DIR = os.environ.get("MAHA_COMMON") or os.path.expanduser("~/.maha.commute/common")\n'
     'STATIONS_PATH = os.path.join(COMMON_DIR, "stations.json")\n'
     '_stations_mem = {"mtime": None, "rows": []}\n'),
    ('CACHE_ZIP = os.path.join(APPDIR, "zet_gtfs.zip")\nSTATIONS_PATH = os.path.join(APPDIR, "stations.json")\n',
     '# v25: the timetable and the stations are shared by all three apps, in one folder\n'
     'COMMON_DIR = os.environ.get("MAHA_COMMON") or os.path.expanduser("~/.maha.commute/common")\n'
     'CACHE_ZIP = os.path.join(COMMON_DIR, "zet_gtfs.zip")\n'
     'STATIONS_PATH = os.path.join(COMMON_DIR, "stations.json")\n'),
    ('                with open(CACHE_ZIP, "wb") as f:\n                    f.write(data)\n', _ATOMIC_ZIP),
    ('    tmp = STATIONS_PATH + ".tmp"\n    doc = {"updated"',
     '    os.makedirs(os.path.dirname(STATIONS_PATH), exist_ok=True)\n'
     '    tmp = STATIONS_PATH + ".tmp"\n    doc = {"updated"'),
    # the seed goes to the common folder, and an older install's stations move there
    ('step "putting every station on the phone"\n'
     'if [ ! -s "$APPDIR/stations.json" ]; then\n'
     "  cat > \"$APPDIR/stations.json.tmp\" << 'ALLC_STATIONS_SEED'\n",
     'step "putting every station on the phone"\n'
     'COMMON="${MAHA_COMMON:-$HOME/.maha.commute/common}"; mkdir -p "$COMMON"\n'
     '# an older install kept its stations and its timetable beside the app: they move to the\n'
     '# common folder, which all three apps share\n'
     'if [ -s "$APPDIR/stations.json" ] && [ ! -s "$COMMON/stations.json" ]; then\n'
     '  mv -f "$APPDIR/stations.json" "$COMMON/stations.json"\n'
     'fi\n'
     'if [ -s "$APPDIR/zet_gtfs.zip" ] && [ ! -s "$COMMON/zet_gtfs.zip" ]; then\n'
     '  cp -f "$APPDIR/zet_gtfs.zip" "$COMMON/zet_gtfs.zip"\n'
     '  [ -s "$APPDIR/zet_gtfs.zip.meta.json" ] && cp -f "$APPDIR/zet_gtfs.zip.meta.json" "$COMMON/zet_gtfs.zip.meta.json"\n'
     'fi\n'
     'if [ ! -s "$COMMON/stations.json" ]; then\n'
     "  cat > \"$COMMON/stations.json.tmp\" << 'ALLC_STATIONS_SEED'\n"),
    ('ALLC_STATIONS_SEED\n  mv -f "$APPDIR/stations.json.tmp" "$APPDIR/stations.json"\nfi\ndone_\n',
     'ALLC_STATIONS_SEED\n  mv -f "$COMMON/stations.json.tmp" "$COMMON/stations.json"\nfi\ndone_\n'),

    # ---- the station server --------------------------------------------------
    ('def stations_ready():\n', SERVER_DISCOVERY + 'def stations_ready():\n'),
    ('            if route == "/stations.json":\n', SERVER_ROUTE + '            if route == "/stations.json":\n'),
    ('_STATE_CHANGING = ("/rebuild", "/cache/clear", "/sched-delete")',
     '_STATE_CHANGING = ("/rebuild", "/cache/clear", "/sched-delete", "/stations/view")'),

    # ---- the page: the stations follow the map --------------------------------
    ('let STATION_DB = [], STATION_REV = "";\n', PAGE_JS + 'let STATION_DB = [], STATION_REV = "";\n'),
    ('  STATION_REV = (d && d.rev) || "";\n}\n',
     '  STATION_REV = (d && d.rev) || "";\n  mergeExtras();\n}\n'),
    ('  try { const raw = localStorage.getItem("ac2_stations"); if (raw) setStationDB(JSON.parse(raw)); }\n'
     '  catch (e) { STATION_DB = []; }\n',
     '  try { STATION_X = JSON.parse(localStorage.getItem("ac2_stations_x") || "{}") || {}; } catch (e) { STATION_X = {}; }\n'
     '  try { (JSON.parse(localStorage.getItem("ac2_tiles") || "[]") || []).forEach(k => { TILESDONE[k] = 1; }); } catch (e) {}\n'
     '  try { const raw = localStorage.getItem("ac2_stations"); if (raw) setStationDB(JSON.parse(raw)); else mergeExtras(); }\n'
     '  catch (e) { STATION_DB = []; }\n'),
    ('  hud("Reading the stations around you…", true);\n'
     '  try {\n'
     '    let d, widened = false;\n'
     '    if (STATION_DB.length) {\n'
     '      // from the page\'s own copy: no request, so no wait and no server needed\n'
     '      d = localStops(at, RADIUS, 0);\n'
     '      if (!d.stops.length) { d = localStops(at, RADIUS, 6); widened = true; }\n'
     '    } else {\n',
     '  if (!STATION_DB.length) hud("Reading the stations around you…", true);\n'
     '  try {\n'
     '    let d, widened = false, viewMode = false;\n'
     '    if (STATION_DB.length && viewBounds()) {\n'
     '      // the stations in whatever the map is looking at, from the page\'s own copy\n'
     '      viewMode = true;\n'
     '      d = viewStops();\n'
     '    } else if (STATION_DB.length) {\n'
     '      d = localStops(at, RADIUS, 0);\n'
     '      if (!d.stops.length) { d = localStops(at, RADIUS, 6); widened = true; }\n'
     '    } else {\n'),
    ('    STOPS = (d.stops || []).slice(0, 8);\n    assignColours(STOPS);\n    drawStars();\n',
     '    STOPS = viewMode ? (d.stops || []) : (d.stops || []).slice(0, 8);\n'
     '    assignColours(STOPS);\n'
     '    const sig = STOPS.map(s => s.stop_id).join(",");\n'
     '    const changed = !viewMode || sig !== STOPSIG;\n'
     '    STOPSIG = sig;\n'
     '    if (changed) drawStars(); else layoutPins();\n'),
    ('    if (!STOPS.length) hud("No station anywhere near. Try the radius in ⚙.");\n',
     '    if (viewMode) hud(viewLine());\n'
     '    else if (!STOPS.length) hud("No station anywhere near. Try the radius in ⚙.");\n'),
    ('    refreshBoards();\n  } catch (e) {\n    hud("Could not reach the server: " + esc(e.message || e));\n',
     '    if (!viewMode || changed) refreshBoards();\n'
     '    if (viewMode) maybeDiscover();\n'
     '  } catch (e) {\n    hud("Could not reach the server: " + esc(e.message || e));\n'),
    ('function stopsLine(){\n  const n = STOPS.length;\n',
     'function stopsLine(){\n  if (STATION_DB.length && viewBounds()) { viewStops(); return viewLine(); }\n  const n = STOPS.length;\n'),
    ('  map.on("moveend", layoutPins);\n', '  map.on("moveend", scheduleView);\n'),
    ('  gmap.addListener("idle", layoutPins);\n', '  gmap.addListener("idle", scheduleView);\n'),

    # the boards: only the nearest few and the watched station, never one per station in view
    ('async function refreshBoards(){\n'
     '  if (!STOPS.length) return;\n'
     '  /* the first warms the server\'s realtime cache, the rest ride behind it\n'
     '     instead of all reaching for the feed at the same moment */\n'
     '  await fetchBoard(STOPS[0]);\n'
     '  await Promise.all(STOPS.slice(1).map(fetchBoard));\n',
     'async function refreshBoards(){\n'
     '  const list = STOPS.slice(0, 8);\n'
     '  // the watched station keeps refreshing wherever the map has been scrolled to\n'
     '  if (WATCH && !list.some(s => s.stop_id === WATCH.stop_id)) list.push(WATCH);\n'
     '  if (!list.length) return;\n'
     '  /* the first warms the server\'s realtime cache, the rest ride behind it\n'
     '     instead of all reaching for the feed at the same moment */\n'
     '  await fetchBoard(list[0]);\n'
     '  await Promise.all(list.slice(1).map(fetchBoard));\n'),
    ('async function fetchBoard(s){\n  try {\n',
     'async function fetchBoard(s){\n'
     '  // a stop found by scrolling has no ZET timetable: nothing to ask\n'
     '  if (isOsm(s.stop_id)) { BOARDS[s.stop_id] = ' + _BOARD_NONE + '; return; }\n  try {\n'),
    ('  let b = null;\n  try {\n    b = await fetch("board?stop=" + encodeURIComponent(s.stop_id) +\n',
     '  if (isOsm(s.stop_id)) {\n'
     '    BOARDS[s.stop_id] = ' + _BOARD_NONE + ';\n'
     '    if (SEL === s) renderDash();\n    updateWatchBar();\n    return;\n  }\n'
     '  let b = null;\n  try {\n    b = await fetch("board?stop=" + encodeURIComponent(s.stop_id) +\n'),
    ('\'">\' + esc(s.stop_id) +\n    (ab ? \' <i>\' + ab + \'</i>\' : "")',
     '\'">\' + esc(pinText(s)) +\n    (ab ? \' <i>\' + ab + \'</i>\' : "")'),
    ('  document.getElementById("dId").textContent = s.stop_id;\n',
     '  document.getElementById("dId").textContent = isOsm(s.stop_id) ? "OSM" : s.stop_id;\n'),
    ('<span class="svpinlabel">\' + esc(s.stop_id) + \'</span>',
     '<span class="svpinlabel">\' + esc(pinText(s)) + \'</span>'),
]

# ------------------------------------------------------------- day.commute
DAY_FIXES = [
    ('COMMUTE_VERSION="v18"', 'COMMUTE_VERSION="v19"'),
    ('APP_VERSION = "v18"', 'APP_VERSION = "v19"'),
    ('(v.version || "v18")', '(v.version || "v19")'),
    ('if (el) el.textContent = "v18 (a)"; });', 'if (el) el.textContent = "v19 (a)"; });'),
    ('CACHE_ZIP = os.environ.get(\n    "GTFS_CACHE", os.path.join(os.path.dirname(OUT_PATH), "zet_gtfs.zip"))\n',
     '# v25: the ZET timetable is one file in a folder the three apps share\n'
     'COMMON_DIR = os.environ.get("MAHA_COMMON") or os.path.expanduser("~/.maha.commute/common")\n'
     'CACHE_ZIP = os.environ.get("GTFS_CACHE", os.path.join(COMMON_DIR, "zet_gtfs.zip"))\n'),
    ('                with open(CACHE_ZIP, "wb") as f:\n                    f.write(data)\n', _ATOMIC_ZIP),
]

# ----------------------------------------------------------- night.commute
NIGHT_FIXES = [
    ('NIGHT_VERSION="v14 (a)"', 'NIGHT_VERSION="v15 (a)"'),
    ('APP_VERSION = "v14"', 'APP_VERSION = "v15"'),
    ('(v.version||"v14")', '(v.version||"v15")'),
    ('textContent="v14 (a)"; });', 'textContent="v15 (a)"; });'),
    ('installed  night.commute v14 (a)', 'installed  night.commute v15 (a)'),
    ('CACHE_ZIP = os.path.join(APPDIR, "zet_gtfs.zip")\n',
     '# v25: the ZET timetable is one file in a folder the three apps share\n'
     'COMMON_DIR = os.environ.get("MAHA_COMMON") or os.path.expanduser("~/.maha.commute/common")\n'
     'CACHE_ZIP = os.path.join(COMMON_DIR, "zet_gtfs.zip")\n'),
    ('            os.makedirs(APPDIR, exist_ok=True)\n            open(CACHE_ZIP, "wb").write(data)\n',
     '            os.makedirs(COMMON_DIR, exist_ok=True)\n'
     '            with open(CACHE_ZIP + ".tmp", "wb") as _zf:\n'
     '                _zf.write(data)\n'
     '            os.replace(CACHE_ZIP + ".tmp", CACHE_ZIP)    # whole file or nothing, shared by three apps\n'),
]


def _apply(src, fixes, who):
    for old, new in fixes:
        if src.count(old) != 1:
            raise SystemExit("payload_v25: %s, this anchor matches %d times, not once:\n    %s"
                             % (who, src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)
    return src


def patch_all(src):
    return _apply(src, ALL_FIXES, "all")


def patch_day(src):
    return _apply(src, DAY_FIXES, "day")


def patch_night(src):
    return _apply(src, NIGHT_FIXES, "night")
