#!/usr/bin/env bash
# night.commute.v9.sh  (Commute family — night-tram app installer)  v9 (a)
# Night Commute — the night-tram companion of the Commute family (Day Commute
# is the daytime app; this is Night Commute). It focuses ONLY on Zagreb's four
# night trams (31, 32, 33, 34), which take over the network from 23:50 to 04:40.
# No daytime lines, no radius, no bus-PDF clutter. It is a learning tool: search
# any two stations and it tells you which night tram connects them, with a
# transfer when there is no direct line, plus a clear map with station names.
#
#   bash night.commute.v9.sh            Enter = offline install
#   bash night.commute.v9.sh --offline  skip the python check
set -e
NIGHT_VERSION="v9 (a)"
BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
APPDIR="$HOME/.nightcommute"

MODE=""
for a in "$@"; do
  case "$a" in
    --online|--full|--deps) MODE="online" ;;
    --offline) MODE="offline" ;;
    -h|--help) printf "usage: bash night.commute.v9.sh [--online] [--offline]\n"; exit 0 ;;
  esac
done

if [ -t 1 ]; then
  A="\033[1;36m"; M="\033[1;35m"; OK="\033[1;32m"; WARN="\033[1;33m"
  KEY="\033[1;37m"; DIM="\033[0;90m"; OFF="\033[0m"
else
  A=""; M=""; OK=""; WARN=""; KEY=""; DIM=""; OFF=""
fi
type_line() { local s="$1"; local i
  for ((i=0; i<${#s}; i++)); do printf "%s" "${s:$i:1}"; sleep 0.004; done; printf "\n"; }
step() { printf "  ${A}▸${OFF} %s" "$1"; local i; for i in 1 2 3; do printf "."; sleep 0.10; done; }
done_() { printf " ${OK}ok${OFF}\n"; }
skip_() { printf " ${DIM}skipped${OFF}\n"; }

clear 2>/dev/null
printf "\n"
printf "  ${A}▌${OFF} "; type_line "$(printf '%bNIGHT.COMMUTE%b  installer %s' "$KEY" "$OFF" "$NIGHT_VERSION")"
printf "  ${A}▌${OFF} ${DIM}Moon | the night, the Commute family${OFF}\n\n"

if [ -z "$MODE" ]; then
  printf "  install mode:\n"
  printf "    ${KEY}Enter${OFF}  ${DIM}offline, skip the python check (fast)${OFF}\n"
  printf "    ${KEY}y${OFF}      ${DIM}check & install python${OFF}\n"
  printf "\n  ${A}>${OFF} "
  IFS= read -r ANS || ANS=""
  case "$ANS" in [yY]*) MODE="online" ;; *) MODE="offline" ;; esac
fi
printf "  ${DIM}mode: %s${OFF}\n\n" "$MODE"

step "checking Termux"
if [ -z "${PREFIX:-}" ] || [ ! -d "$BIN" ]; then
  printf " ${WARN}this installer is for Termux on Android${OFF}\n"; exit 1
fi
done_

if [ "$MODE" = "online" ]; then
  step "python runtime"
  if ! command -v python3 >/dev/null 2>&1; then
    printf " ${WARN}installing${OFF}\n"
    pkg install -y python >/dev/null 2>&1 || yes | pkg install python
    step "python runtime"
  fi
  done_
else
  step "python check"; skip_
fi

step "app folder"
mkdir -p "$APPDIR" 2>/dev/null || true
done_

step "wiping old night build"
# Kill every running night server (new name and the legacy nightram name), so
# no stale process keeps serving the old page. Then delete the old app folders
# and any old commands entirely, so nothing from a previous build survives.
pkill -9 -f night_server.py 2>/dev/null || true
pkill -9 -f nightram 2>/dev/null || true
pkill -9 -f "night.html" 2>/dev/null || true
sleep 1
rm -rf "$HOME/.nightcommute" 2>/dev/null || true
rm -rf "$HOME/.nightram" 2>/dev/null || true
for oldcmd in nightram nightcommute; do
  rm -f "$BIN/$oldcmd" "$HOME/.local/bin/$oldcmd" 2>/dev/null || true
done
mkdir -p "$APPDIR" 2>/dev/null || true
done_

GEMINI_KEYFILE="$APPDIR/gemini-api.txt"
GMAPS_KEY="__MAHA_GOOGLE_KEY__"

step "google maps key"
GMAPS_KEYFILE="$APPDIR/gmaps-api.txt"
GDROP=""
for c in "./Google-maps-api.txt" "./gmaps-api.txt" "$HOME/storage/downloads/Google-maps-api.txt" "$HOME/downloads/Google-maps-api.txt"; do
  [ -f "$c" ] && { GDROP="$c"; break; }
done
if [ -n "$GDROP" ]; then
  grep -v '^[[:space:]]*$' "$GDROP" | head -1 > "$GMAPS_KEYFILE"
  printf " ${DIM}(from %s)${OFF}" "$GDROP"
elif [ ! -f "$GMAPS_KEYFILE" ]; then
  printf '%s\n' "$GMAPS_KEY" > "$GMAPS_KEYFILE"
fi
done_

step "api key"
DROP=""
for c in "./gemini-api.txt" "$HOME/storage/downloads/gemini-api.txt" "$HOME/downloads/gemini-api.txt"; do
  [ -f "$c" ] && { DROP="$c"; break; }
done
if [ -n "$DROP" ]; then
  grep -v '^[[:space:]]*$' "$DROP" > "$GEMINI_KEYFILE"
  printf " ${DIM}(from %s)${OFF}" "$DROP"
fi
done_

step "installing night data"
# ---- night network data (authoritative, embedded) ----
cat > "$APPDIR/night.json" << 'NIGHT_DATA_JSON'
{"note": "ZET night trams 31-34, 23:50-04:40. Data from ZET + zgportal 2026-05.", "lines": {"31": {"name": "Črnomerec – Savski most", "termA": "Črnomerec", "termB": "Savski most", "stations": ["Črnomerec", "Ilica", "Trg bana Jelačića", "Glavni kolodvor", "Branimirova", "Autobusni kolodvor", "Avenija Marina Držića", "Most mladosti", "Avenija Dubrovnik", "Jadranski most (Arena)", "Savski most"], "departA": ["00:11", "01:04", "01:54", "02:48", "03:44", "04:37"], "departB": ["00:12", "01:03", "01:56", "02:49", "03:42", "04:36"]}, "32": {"name": "Prečko – Borongaj", "termA": "Prečko", "termB": "Borongaj", "stations": ["Prečko", "Jarun", "Horvaćanska", "Selska", "Savska (Cibona/Mimara/HNK)", "Ilica", "Trg bana Jelačića", "Trg žrtava fašizma", "Zvonimirova", "Borongaj"], "departA": ["23:50", "00:38", "01:26", "02:15", "03:03", "03:51", "04:39"], "departB": ["23:50", "00:38", "01:26", "02:15", "03:03", "03:51", "04:40"]}, "33": {"name": "Gračansko Dolje – Savišće", "termA": "Gračansko Dolje", "termB": "Savišće", "stations": ["Gračansko Dolje", "Gračani", "Mihaljevac", "Ksaverska", "Ribnjak", "Draškovićeva", "Branimirova", "Glavni kolodvor", "Vodnikova", "Savska (Cibona)", "Ulica grada Vukovara (Lisinski/NSK)", "Žitnjak", "Ulica grada Gospića", "Savišće"], "departA": ["00:19", "01:16", "02:12", "03:14", "04:10"], "departB": ["00:19", "01:16", "02:13", "03:10", "04:06"]}, "34": {"name": "Ljubljanica – Dubec", "termA": "Ljubljanica", "termB": "Dubec", "stations": ["Ljubljanica", "Ozaljska", "Tratinska", "Savska (Mimara/HNK)", "Ilica", "Trg bana Jelačića", "Glavni kolodvor", "Branimirova", "Draškovićeva", "Vlaška", "Maksimirska (ZOO/Maksimir)", "Dubrava", "Avenija Dubrava", "Dubec"], "departA": ["23:59", "00:51", "01:43", "02:36", "03:25"], "departB": ["00:01", "00:52", "01:44", "02:36", "03:29", "04:20"]}}}
NIGHT_DATA_JSON

cat > "$APPDIR/coords.json" << 'NIGHT_COORDS_JSON'
{"Črnomerec": [45.8206, 15.9358], "Ilica": [45.8106, 15.9666], "Trg bana Jelačića": [45.8131, 15.9775], "Glavni kolodvor": [45.8045, 15.9788], "Branimirova": [45.806, 15.982], "Autobusni kolodvor": [45.801, 15.993], "Avenija Marina Držića": [45.796, 15.993], "Most mladosti": [45.789, 15.993], "Avenija Dubrovnik": [45.777, 15.972], "Jadranski most (Arena)": [45.776, 15.943], "Savski most": [45.786, 15.933], "Prečko": [45.786, 15.913], "Jarun": [45.79, 15.925], "Horvaćanska": [45.793, 15.943], "Selska": [45.8, 15.956], "Savska (Cibona/Mimara/HNK)": [45.805, 15.968], "Trg žrtava fašizma": [45.815, 15.987], "Zvonimirova": [45.813, 15.997], "Borongaj": [45.821, 16.018], "Gračansko Dolje": [45.85, 15.96], "Gračani": [45.847, 15.962], "Mihaljevac": [45.842, 15.966], "Ksaverska": [45.833, 15.97], "Ribnjak": [45.82, 15.98], "Draškovićeva": [45.813, 15.984], "Vodnikova": [45.806, 15.97], "Savska (Cibona)": [45.804, 15.968], "Ulica grada Vukovara (Lisinski/NSK)": [45.802, 15.988], "Žitnjak": [45.796, 16.03], "Ulica grada Gospića": [45.798, 16.015], "Savišće": [45.793, 16.04], "Ljubljanica": [45.795, 15.935], "Ozaljska": [45.8, 15.942], "Tratinska": [45.803, 15.952], "Savska (Mimara/HNK)": [45.806, 15.968], "Vlaška": [45.818, 15.988], "Maksimirska (ZOO/Maksimir)": [45.823, 16.0], "Dubrava": [45.834, 16.03], "Avenija Dubrava": [45.833, 16.045], "Dubec": [45.83, 16.06]}
NIGHT_COORDS_JSON
done_

step "installing server"
cat > "$APPDIR/night_server.py" << 'NC_SERVER_PY'
#!/usr/bin/env python3
"""Night Commute local server. Serves night.html and the night data, plus a
tiny PDF cache + Gemini reader, a key-status check, and a ZET GTFS night-tram
schedule builder (routes 31-34) with a curated offline fallback."""
import os, json, time, base64, hashlib, threading, urllib.parse, urllib.request
import urllib.error, io, csv, zipfile, collections, datetime
import http.server, socketserver, logging

APP_VERSION = "v9"
APP_BUILD = "n9-a"
APPDIR = os.environ.get("NIGHTCOMMUTE_DIR", os.path.expanduser("~/.nightcommute"))
START_PORT = int(os.environ.get("NIGHTCOMMUTE_PORT", "8087"))
PORTFILE = os.path.join(APPDIR, "port")
GEMINI_KEYFILE = os.path.join(APPDIR, "gemini-api.txt")
GMAPS_KEYFILE = os.path.join(APPDIR, "gmaps-api.txt")
PDF_DIR = os.path.join(APPDIR, "pdf")
LOGFILE = os.path.join(APPDIR, "server.log")
ALLOWED = {"night.html", "night.json", "coords.json", "favicon.ico"}
MIME = {".html":"text/html; charset=utf-8", ".json":"application/json",
        ".ico":"image/x-icon"}
logging.basicConfig(filename=LOGFILE, level=logging.INFO)
def _log(m):
    try: logging.info(m)
    except Exception: pass

ZET_NIGHT_PDF = ("https://www.zet.hr/UserDocsImages/"
                 "Tramvajske%20linije%20-%20vozni%20red/{r}.pdf")
GEMINI_MODELS = ["gemini-2.5-flash", "gemini-2.0-flash"]
_LOCK = threading.Lock()

# ============================================================================
# GTFS night-tram schedule engine (routes 31-34). Rebuilds the network and
# tonight's real timetable from the ZET GTFS zip, with the curated night.json
# shipped by the installer as an offline fallback. Same-shaped output as the
# curated data (lines{name,termA,termB,stations,departA,departB}) plus a
# per-station stopmap and a real per-trip schedule, so the routing UI is
# unchanged and only the times become real.
# ============================================================================
GTFS_URLS = ["https://www.zet.hr/gtfs-scheduled/latest",
             "https://zet.hr/gtfs-scheduled/latest"]
CACHE_ZIP = os.path.join(APPDIR, "zet_gtfs.zip")
GTFS_META = CACHE_ZIP + ".meta.json"
NIGHT_JSON = os.path.join(APPDIR, "night.json")
COORDS_JSON = os.path.join(APPDIR, "coords.json")
SCHED_JSON = os.path.join(APPDIR, "night_sched.json")
NIGHT_META = os.path.join(APPDIR, "night_meta.json")
NIGHT_ROUTES = ("31", "32", "33", "34")
_BUILD_LOCK = threading.Lock()
_BUILDING = {"on": False}

def _sx(s):
    p = s.split(":"); return int(p[0]) * 3600 + int(p[1]) * 60 + int(p[2])
def _clk(sec):
    sec %= 86400; return "%02d:%02d" % (sec // 3600, (sec % 3600) // 60)
def _rows(zf, name):
    with zf.open(name) as f:
        return list(csv.DictReader(io.TextIOWrapper(f, encoding="utf-8")))

def _operating_date(now, svc_by_date):
    d = now.date()
    if now.hour < 5: d = d - datetime.timedelta(days=1)
    ymd = d.strftime("%Y%m%d"); svc = svc_by_date.get(ymd, set())
    if not svc:
        keys = sorted(svc_by_date)
        if keys:
            near = min(keys, key=lambda k: abs(int(k) - int(ymd)))
            return near, svc_by_date[near]
    return ymd, svc

def build_night_from_zip(zip_bytes, now=None):
    now = now or datetime.datetime.now()
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        stops = {}; coord = {}
        for r in _rows(zf, "stops.txt"):
            stops[r["stop_id"]] = r["stop_name"]
            try: coord[r["stop_id"]] = [round(float(r["stop_lat"]), 5), round(float(r["stop_lon"]), 5)]
            except Exception: pass
        tinfo = {}
        for r in _rows(zf, "trips.txt"):
            if r["route_id"] in NIGHT_ROUTES:
                tinfo[r["trip_id"]] = (r["route_id"], r["direction_id"], r["service_id"].strip('"'))
        want = set(tinfo); times = collections.defaultdict(list)
        with zf.open("stop_times.txt") as f:
            for r in csv.DictReader(io.TextIOWrapper(f, encoding="utf-8")):
                t = r["trip_id"]
                if t in want:
                    times[t].append((int(r["stop_sequence"]), r["stop_id"], _sx(r["departure_time"])))
        for t in times: times[t].sort()
        svc_by_date = collections.defaultdict(set)
        for r in _rows(zf, "calendar_dates.txt"):
            if r["exception_type"] == "1":
                svc_by_date[r["date"].strip('"')].add(r["service_id"].strip('"'))
        feedver = ""
        try: feedver = _rows(zf, "feed_info.txt")[0].get("feed_version", "")
        except Exception: pass
    ymd, service = _operating_date(now, svc_by_date)
    lines = {}; sched = {}; coords_out = {}
    for rt in NIGHT_ROUTES:
        canon = {}
        for dr in ("0", "1"):
            pats = collections.Counter(); trips_here = []
            for t, (r2, d2, sv) in tinfo.items():
                if r2 == rt and d2 == dr and sv in service:
                    seq = tuple(sid for _, sid, _ in times[t]); pats[seq] += 1
                    trips_here.append({sid: sec for _, sid, sec in times[t]})
            canon[dr] = list(pats.most_common(1)[0][0]) if pats else []
            sched.setdefault(rt, {})[dr] = trips_here
        def dedupe(ids):
            out = []; last = None
            for s in ids:
                nm = stops.get(s, s)
                if nm != last: out.append(s); last = nm
            return out
        ids0 = dedupe(canon["0"]); ids1 = dedupe(canon["1"])
        names0 = [stops.get(s, s) for s in ids0]
        rev = {stops.get(s, s): s for s in ids1}
        stopmap = {}
        for s in ids0:
            nm = stops.get(s, s); stopmap[nm] = [s, rev.get(nm, "")]
        def term_times(dr, term_id):
            return [_clk(x) for x in sorted(m[term_id] for m in sched[rt][dr] if term_id in m)]
        termA = names0[0] if names0 else ""; termB = names0[-1] if names0 else ""
        lines[rt] = {"name": (termA + " \u2013 " + termB) if termA else rt,
                     "termA": termA, "termB": termB, "stations": names0, "stopmap": stopmap,
                     "departA": term_times("0", ids0[0]) if ids0 else [],
                     "departB": term_times("1", ids1[0]) if ids1 else []}
        for s in ids0 + ids1:
            nm = stops.get(s, s)
            if s in coord and nm not in coords_out: coords_out[nm] = coord[s]
    net = {"note": "Rebuilt from ZET GTFS %s, service %s (%s)" % (feedver, "/".join(sorted(service)), ymd),
           "source": "gtfs", "feed_version": feedver, "service_date": ymd,
           "built": int(time.time()), "lines": lines}
    meta = {"source": "gtfs", "feed_version": feedver, "service_date": ymd,
            "built": int(time.time()), "service": sorted(service)}
    return net, coords_out, sched, meta

def _get_gtfs(force=False):
    meta = {}
    try: meta = json.load(open(GTFS_META, encoding="utf-8"))
    except Exception: meta = {}
    cached = None
    if os.path.isfile(CACHE_ZIP):
        try: cached = open(CACHE_ZIP, "rb").read()
        except Exception: cached = None
    headers = {"User-Agent": "Mozilla/5.0 (Android; nightcommute)"}
    if cached is not None and not force:
        if meta.get("etag"): headers["If-None-Match"] = meta["etag"]
        if meta.get("last_modified"): headers["If-Modified-Since"] = meta["last_modified"]
    last = None
    for url in GTFS_URLS:
        try:
            req = urllib.request.Request(url, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    data = resp.read(); rh = resp.headers
            except urllib.error.HTTPError as he:
                if he.code == 304 and cached is not None:
                    return cached, False
                raise
            if data[:2] != b"PK":
                last = "not a zip from %s" % url; continue
            os.makedirs(APPDIR, exist_ok=True)
            open(CACHE_ZIP, "wb").write(data)
            try:
                json.dump({"etag": rh.get("ETag", ""), "last_modified": rh.get("Last-Modified", "")},
                          open(GTFS_META, "w", encoding="utf-8"))
            except Exception: pass
            return data, True
        except Exception as e:
            last = repr(e)
    if cached is not None: return cached, False
    raise RuntimeError("gtfs download failed: %s" % last)

def night_meta():
    try: return json.load(open(NIGHT_META, encoding="utf-8"))
    except Exception: return {"source": "fallback"}

def night_stale(now=None):
    now = now or datetime.datetime.now()
    m = night_meta()
    if m.get("source") != "gtfs": return True
    d = now.date()
    if now.hour < 5: d = d - datetime.timedelta(days=1)
    return m.get("service_date") != d.strftime("%Y%m%d")

def rebuild_night(force=False, now=None):
    with _BUILD_LOCK:
        _BUILDING["on"] = True
        try:
            data, _ = _get_gtfs(force=force)
            net, coords, sched, meta = build_night_from_zip(data, now=now)
            os.makedirs(APPDIR, exist_ok=True)
            json.dump(net, open(NIGHT_JSON, "w", encoding="utf-8"), ensure_ascii=False)
            json.dump(coords, open(COORDS_JSON, "w", encoding="utf-8"), ensure_ascii=False)
            json.dump(sched, open(SCHED_JSON, "w", encoding="utf-8"), ensure_ascii=False)
            json.dump(meta, open(NIGHT_META, "w", encoding="utf-8"), ensure_ascii=False)
            _log("night rebuilt from gtfs %s service %s" % (meta.get("feed_version"), meta.get("service_date")))
            return {"ok": True, "meta": meta}
        except Exception as e:
            _log("night rebuild failed %r" % e)
            return {"ok": False, "reason": repr(e)}
        finally:
            _BUILDING["on"] = False

def _bg_rebuild_if_stale():
    try:
        if night_stale(): rebuild_night(force=False)
    except Exception as e:
        _log("bg rebuild %r" % e)

def read_gemini_keys():
    try:
        with open(GEMINI_KEYFILE, encoding="utf-8") as f:
            return [x.strip() for x in f if x.strip()]
    except OSError:
        return []
def write_gemini_keys(keys):
    os.makedirs(APPDIR, exist_ok=True)
    with open(GEMINI_KEYFILE, "w", encoding="utf-8") as f:
        f.write("\n".join(keys) + ("\n" if keys else ""))

def write_gmaps_key(key):
    os.makedirs(APPDIR, exist_ok=True)
    with open(GMAPS_KEYFILE, "w", encoding="utf-8") as f:
        f.write((key or "").strip() + "\n")

def read_gmaps_key():
    try:
        with open(GMAPS_KEYFILE, encoding="utf-8") as f:
            for ln in f:
                ln=ln.strip()
                if ln: return ln
    except OSError:
        pass
    return ""

def _safe(r): return "".join(c for c in r if c.isalnum())[:4]
def _pdf_path(r): return os.path.join(PDF_DIR, _safe(r) + ".pdf")
def _sched_path(r): return os.path.join(PDF_DIR, _safe(r) + ".json")

def _download_pdf(r):
    path = _pdf_path(r); os.makedirs(PDF_DIR, exist_ok=True)
    if os.path.isfile(path):            # permanent cache
        return path
    url = ZET_NIGHT_PDF.format(r=urllib.parse.quote(_safe(r)))
    req = urllib.request.Request(url, headers={"User-Agent": "nightcommute/1"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
    if data[:5] != b"%PDF-":
        raise ValueError("not a PDF")
    with open(path, "wb") as f:
        f.write(data)
    return path

def _gemini_parse(r, pdf_bytes, key):
    prompt = ("This PDF is a ZET Zagreb NIGHT tram timetable for line " + _safe(r) +
        ". Extract departure times from each terminal. Reply ONLY minified JSON: "
        '{"directions":[{"terminal":"name","times":["HH:MM",...]}]} 24h sorted.')
    body = json.dumps({"contents":[{"parts":[
        {"inline_data":{"mime_type":"application/pdf","data":base64.b64encode(pdf_bytes).decode()}},
        {"text":prompt}]}],"generationConfig":{"temperature":0}}).encode()
    last=None
    for model in GEMINI_MODELS:
        u=("https://generativelanguage.googleapis.com/v1beta/models/"+model+
           ":generateContent?key="+urllib.parse.quote(key))
        try:
            req=urllib.request.Request(u,data=body,headers={"Content-Type":"application/json"})
            with urllib.request.urlopen(req,timeout=90) as resp:
                out=json.loads(resp.read().decode("utf-8","replace"))
            txt=out["candidates"][0]["content"]["parts"][0]["text"].strip().strip("`")
            if txt.lower().startswith("json"): txt=txt[4:].strip()
            j=json.loads(txt[txt.find("{"):txt.rfind("}")+1])
            j["source"]="gemini:"+model
            return j
        except Exception as e:
            last=e; _log("gemini %s %r"%(model,e))
    raise RuntimeError("gemini failed: %r"%(last,))

def pdf_sched_for(r, force=False):
    with _LOCK:
        path=_download_pdf(r)
        pdf=open(path,"rb").read(); digest=hashlib.md5(pdf).hexdigest()
        sp=_sched_path(r)
        if not force:
            try:
                c=json.load(open(sp,encoding="utf-8"))
                if c.get("md5")==digest and c.get("directions") is not None:
                    c["cached"]=True; return c
            except Exception: pass
        parsed=None; err=None
        for k in read_gemini_keys():
            try: parsed=_gemini_parse(r,pdf,k); break
            except Exception as e: err=repr(e)
        if parsed is None:
            parsed={"directions":None,"source":"none",
                    "error":err or "no Gemini key set"}
        parsed["md5"]=digest; parsed["route"]=_safe(r); parsed["fetched"]=int(time.time())
        try: json.dump(parsed,open(sp,"w",encoding="utf-8"),ensure_ascii=False)
        except Exception: pass
        return parsed

def key_status():
    keys=read_gemini_keys()
    if not keys: return {"ok":True,"set":False,"working":False}
    for k in keys:
        u="https://generativelanguage.googleapis.com/v1beta/models?key="+urllib.parse.quote(k)
        try:
            with urllib.request.urlopen(urllib.request.Request(u),timeout=15) as r:
                if r.status==200: return {"ok":True,"set":True,"working":True}
        except Exception as e: _log("keytest %r"%e)
    return {"ok":True,"set":True,"working":False}

def pdf_list():
    items=[]
    try: names=os.listdir(PDF_DIR)
    except OSError: names=[]
    for fn in sorted(names):
        if not fn.endswith(".pdf"): continue
        r=fn[:-4]; size=0; parsed=False
        try: size=os.path.getsize(os.path.join(PDF_DIR,fn))
        except OSError: pass
        try: parsed=bool(json.load(open(_sched_path(r)))["directions"])
        except Exception: pass
        items.append({"route":r,"bytes":size,"parsed":parsed})
    return {"ok":True,"items":items}

def pdf_delete(route, all_):
    try: names=os.listdir(PDF_DIR)
    except OSError: names=[]
    tg=[n[:-4] for n in names if n.endswith(".pdf")] if all_ else ([_safe(route)] if route else [])
    for r in tg:
        for p in (_pdf_path(r),_sched_path(r)):
            try:
                if os.path.isfile(p): os.remove(p)
            except OSError: pass
    return {"ok":True,"removed":tg}

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code, body, ctype):
        self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body))); self.end_headers()
        self.wfile.write(body)
    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj).encode(), "application/json")
    def do_GET(self):
        r=urllib.parse.urlparse(self.path).path
        if r in ("/","/index.html"): r="/night.html"
        q=urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if r=="/version": return self._json({"version":APP_VERSION,"build":APP_BUILD})
        if r=="/night-sched":
            try: return self._send(200, open(SCHED_JSON,"rb").read(), "application/json")
            except Exception: return self._json({})
        if r=="/night-status":
            m=night_meta(); m["building"]=_BUILDING["on"]; m["stale"]=night_stale()
            return self._json(m)
        if r=="/night-rebuild":
            return self._json(rebuild_night(force=q.get("force",["0"])[0]=="1"))
        if r=="/gmaps-key": return self._json({"key":read_gmaps_key()})
        if r=="/key-status": return self._json(key_status())
        if r=="/pdf-list": return self._json(pdf_list())
        if r=="/pdf-delete":
            return self._json(pdf_delete(q.get("route",[""])[0], q.get("all",["0"])[0]=="1"))
        if r=="/pdf-sched":
            routes=[x for x in (q.get("routes",[""])[0]).split(",") if x]
            force=q.get("force",["0"])[0]=="1"; out={"ok":True,"routes":{}}
            for rr in routes[:4]:
                try: out["routes"][_safe(rr)]=pdf_sched_for(rr,force)
                except Exception as e: out["routes"][_safe(rr)]={"error":repr(e)}
            return self._json(out)
        name=r.lstrip("/")
        if name in ALLOWED:
            path=os.path.join(APPDIR,name)
            if os.path.isfile(path):
                ext=os.path.splitext(name)[1]
                return self._send(200, open(path,"rb").read(), MIME.get(ext,"application/octet-stream"))
        return self._send(404, b"not found", "text/plain")
    def do_POST(self):
        r=urllib.parse.urlparse(self.path).path
        if r=="/gemini-key":
            try:
                ln=int(self.headers.get("Content-Length") or 0)
                body=self.rfile.read(ln).decode("utf-8","replace") if ln else ""
                keys=[x.strip() for x in body.splitlines() if x.strip()]
                write_gemini_keys(keys); return self._json({"ok":True,"keys":keys})
            except Exception as e: return self._json({"ok":False,"reason":repr(e)},500)
        if r=="/gmaps-key":
            try:
                ln=int(self.headers.get("Content-Length") or 0)
                body=self.rfile.read(ln).decode("utf-8","replace") if ln else ""
                key=next((x.strip() for x in body.splitlines() if x.strip()), "")
                write_gmaps_key(key); return self._json({"ok":True})
            except Exception as e: return self._json({"ok":False,"reason":repr(e)},500)
        return self._send(404,b"not found","text/plain")

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads=True; allow_reuse_address=True

def main():
    port=START_PORT
    for _ in range(40):
        try:
            srv=Server(("127.0.0.1",port),H); break
        except OSError: port+=1
    else:
        raise SystemExit("no free port")
    open(PORTFILE,"w").write(str(port))
    threading.Thread(target=_bg_rebuild_if_stale, daemon=True).start()
    url="http://127.0.0.1:%d/night.html"%port
    _log("serving %s"%url)
    print(url)
    try: srv.serve_forever()
    except KeyboardInterrupt: pass

if __name__=="__main__":
    main()
NC_SERVER_PY
done_

step "installing app"
cat > "$APPDIR/night.html" << 'NC_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>Night Commute</title>
<style>
  :root {
    --bg:#0b0f1a; --card:#141a2b; --border:#28304a;
    --text:#e8ecf6; --muted:#8b93ad; --cyan:#7c5cff; --accent:#ffb454;
    --soon:#5ad1ff; --later:#8b93ad; --line31:#ff6b6b; --line32:#ffd166;
    --line33:#06d6a0; --line34:#4d96ff;
  }
  * { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
  html,body { margin:0; background:var(--bg); color:var(--text);
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }
  body { padding:0 14px 40px; max-width:640px; margin:0 auto; }
  .tophud { position:sticky; top:0; z-index:40; background:var(--bg);
    display:flex; align-items:center; gap:10px; padding:10px 4px 6px; }
  .clock { flex:1; text-align:center; font-size:3.5rem; font-weight:800;
    font-variant-numeric:tabular-nums; letter-spacing:2px; line-height:1; }
  .gear { background:none; border:none; color:var(--muted); font-size:1.5rem;
    cursor:pointer; flex:0 0 auto; align-self:flex-start; padding:4px; }
  .updbar { display:none; align-items:center; justify-content:center; gap:2px;
    font-size:.72rem; font-weight:700; letter-spacing:.5px; color:var(--cyan);
    padding:0 0 8px; animation:updblink 1.1s ease-in-out infinite; }
  .updbar.show { display:flex; }
  .updbar .dots i { animation:upddot 1.2s infinite; opacity:.2; }
  .updbar .dots i:nth-child(2){ animation-delay:.2s; }
  .updbar .dots i:nth-child(3){ animation-delay:.4s; }
  @keyframes updblink { 0%,100%{opacity:1} 50%{opacity:.55} }
  @keyframes upddot { 0%,100%{opacity:.2} 40%{opacity:1} }
  .tabs { display:flex; gap:6px; margin:4px 0 12px; }
  .tab { flex:1; background:var(--card); border:1px solid var(--border); color:var(--muted);
    border-radius:11px; padding:9px 0; font-weight:700; font-size:.9rem; text-align:center;
    cursor:pointer; letter-spacing:.4px; }
  .tab.on { border-color:var(--cyan); color:var(--cyan); background:rgba(124,92,255,.12); }
  .night-banner { background:linear-gradient(135deg,rgba(124,92,255,.18),rgba(77,150,255,.1));
    border:1px solid var(--border); border-radius:14px; padding:12px 14px; margin-bottom:14px;
    font-size:.85rem; color:var(--muted); line-height:1.45; }
  .night-banner b { color:var(--text); }
  .pill-legend { display:flex; flex-wrap:wrap; gap:7px; margin-bottom:14px; }
  .lg { display:flex; align-items:center; gap:6px; font-size:.76rem; color:var(--muted); }
  .lgdot { width:12px; height:12px; border-radius:50%; }
  /* station pickers */
  .picker { margin-bottom:12px; }
  .picker label { font-size:.72rem; text-transform:uppercase; letter-spacing:1px;
    color:var(--muted); display:block; margin-bottom:5px; }
  .stationbox { position:relative; }
  .stationbox input { width:100%; background:var(--card); border:1px solid var(--border);
    color:var(--text); border-radius:11px; padding:12px 72px 12px 13px; font-size:1rem; }
  .stationbox .kbdbtn { position:absolute; right:38px; top:50%; transform:translateY(-50%);
    background:none; border:none; color:var(--muted); font-size:1.15rem; cursor:pointer; padding:6px; }
  .stationbox .kbdbtn.on { color:var(--soon); }
  .stationbox input:focus { outline:none; border-color:var(--cyan); }
  .stationbox .clearbtn { position:absolute; right:8px; top:50%; transform:translateY(-50%);
    background:none; border:none; color:var(--muted); font-size:1.1rem; cursor:pointer; padding:6px; }
  .suggest { position:absolute; left:0; right:0; top:calc(100% + 4px); z-index:30;
    background:var(--card); border:1px solid var(--border); border-radius:11px; overflow:hidden;
    max-height:260px; overflow-y:auto; display:none; box-shadow:0 8px 24px rgba(0,0,0,.5); }
  .suggest.show { display:block; }
  .sg-item { padding:11px 13px; font-size:.92rem; cursor:pointer; border-bottom:1px solid rgba(255,255,255,.04); }
  .sg-item:hover, .sg-item.hi { background:rgba(124,92,255,.14); }
  .sg-item .sg-lines { float:right; display:flex; gap:4px; }
  .sg-ln { font-size:.66rem; font-weight:800; color:#0b0f1a; border-radius:7px; padding:1px 6px; }
  .swap { display:flex; justify-content:center; margin:2px 0 8px; }
  .swapbtn { background:var(--card); border:1px solid var(--border); color:var(--accent);
    border-radius:50%; width:38px; height:38px; font-size:1.1rem; cursor:pointer; }
  /* result */
  .result { margin-top:6px; }
  .journey { background:var(--card); border:1px solid var(--border); border-radius:16px;
    padding:16px; margin-bottom:14px; }
  .j-head { display:flex; align-items:center; gap:9px; font-weight:800; font-size:1.02rem; margin-bottom:4px; }
  .j-sub { color:var(--muted); font-size:.82rem; margin-bottom:12px; }
  .leg { display:flex; align-items:flex-start; gap:12px; padding:6px 0; }
  .leg .lnbadge { font-size:.82rem; font-weight:800; color:#0b0f1a; border-radius:10px;
    padding:4px 11px; flex:none; }
  .leg .legbody { flex:1; }
  .leg .legroute { font-weight:700; }
  .leg .legdir { color:var(--muted); font-size:.82rem; margin-top:2px; }
  .leg .legtimes { margin-top:7px; display:flex; flex-wrap:wrap; gap:6px; }
  .legtime { background:rgba(90,209,255,.12); border:1px solid rgba(90,209,255,.35);
    color:var(--soon); border-radius:9px; padding:3px 9px; font-size:.82rem; font-weight:700;
    font-variant-numeric:tabular-nums; }
  .legtime.next { background:var(--soon); color:#04121a; }
  .legtime .arr { font-weight:600; opacity:.72; }
  .transfer-note { display:flex; align-items:center; gap:9px; margin:8px 0; padding:9px 12px;
    background:rgba(255,180,84,.1); border:1px solid rgba(255,180,84,.4); border-radius:12px;
    color:var(--accent); font-size:.84rem; font-weight:600; }
  .no-route { background:var(--card); border:1px dashed var(--border); border-radius:14px;
    padding:18px; text-align:center; color:var(--muted); }
  .hint { color:var(--muted); font-size:.86rem; text-align:center; padding:20px 10px; line-height:1.5; }
  /* line explorer */
  .linecard { background:var(--card); border:1px solid var(--border); border-radius:16px;
    padding:14px; margin-bottom:14px; }
  .lc-head { display:flex; align-items:center; gap:10px; margin-bottom:4px; }
  .lc-badge { font-size:.9rem; font-weight:800; color:#0b0f1a; border-radius:10px; padding:4px 12px; }
  .lc-name { font-weight:700; }
  .lc-stations { margin-top:10px; position:relative; padding-left:6px; }
  .lc-st { display:flex; align-items:center; gap:10px; padding:5px 0; font-size:.88rem; }
  .lc-st .dotline { position:relative; width:14px; flex:none; display:flex; justify-content:center; }
  .lc-st .dotline::before { content:""; position:absolute; top:-14px; bottom:-14px; width:2px;
    background:var(--border); }
  .lc-st:first-child .dotline::before { top:50%; }
  .lc-st:last-child .dotline::before { bottom:50%; }
  .lc-st .stdot { width:11px; height:11px; border-radius:50%; z-index:1; border:2px solid var(--bg); }
  .lc-st.term .stdot { width:15px; height:15px; }
  .lc-st.hub { font-weight:700; }
  .lc-st .hubtag { margin-left:auto; font-size:.64rem; color:var(--accent);
    border:1px solid rgba(255,180,84,.4); border-radius:7px; padding:1px 6px; }
  .mapwrap { position:relative; margin-bottom:12px; }
  #map { width:100%; height:340px; border-radius:16px; border:1px solid var(--border);
    background:var(--card); }
  #map:fullscreen { border-radius:0; height:100vh; }
  /* Fullscreen is requested on .mapwrap so the ⛶ button stays visible; stretch
     the map inside it to fill the screen (otherwise it kept its 340px height
     with a black gap below). */
  .mapwrap:fullscreen, .mapwrap:-webkit-full-screen {
    width:100vw; height:100vh; margin:0; background:var(--bg); }
  .mapwrap:fullscreen #map, .mapwrap:-webkit-full-screen #map {
    height:100%; width:100%; border-radius:0; border:none; }
  .mapwrap:fullscreen .mapfs, .mapwrap:-webkit-full-screen .mapfs { z-index:10; }
  .mapfs { position:absolute; top:10px; left:10px; z-index:5; width:38px; height:38px;
    border-radius:9px; background:rgba(11,15,26,.85); color:#fff; border:1px solid var(--border);
    font-size:1.1rem; cursor:pointer; }
  .map-tip { color:var(--muted); font-size:.8rem; margin-bottom:12px; line-height:1.4; }
  .mappick { display:flex; gap:8px; margin-bottom:10px; }
  .mapslot { flex:1; background:var(--card); border:1px solid var(--border); border-radius:11px;
    text-align:left; cursor:pointer; font:inherit; color:var(--text);
    padding:9px 11px; font-size:.82rem; }
  .mapslot.a.active { border-color:var(--accent); box-shadow:0 0 0 2px rgba(124,92,255,.35); }
  .mapslot.b.active { border-color:#ffb454; box-shadow:0 0 0 2px rgba(255,180,84,.35); }
    
  .mapslot .ms-l { color:var(--muted); font-size:.66rem; text-transform:uppercase; letter-spacing:1px; }
  .mapslot .ms-v { font-weight:700; }
  .linechecks { display:flex; flex-direction:column; gap:6px; margin-bottom:10px; }
  .lchk { display:flex; align-items:center; gap:9px; width:100%; text-align:left;
    background:var(--card); border:1px solid var(--border); border-radius:11px;
    padding:8px 11px; color:var(--text); font:inherit; cursor:pointer; }
  .lchk.on { border-color:var(--cyan); }
  .lchk-box { flex:0 0 20px; width:20px; height:20px; border-radius:6px;
    border:2px solid var(--border); display:flex; align-items:center; justify-content:center;
    font-size:.8rem; font-weight:900; color:#04121a; }
  .lchk.on .lchk-box { background:var(--cyan); border-color:var(--cyan); }
  .lchk .lnbadge { flex:0 0 auto; min-width:30px; text-align:center; padding:2px 8px;
    border-radius:9px; font-weight:800; color:#04121a; }
  .lchk-t { font-weight:600; font-size:.86rem; color:var(--muted); }
  .lchk.on .lchk-t { color:var(--text); }
  .mapslot.a { border-color:rgba(124,92,255,.5); } .mapslot.b { border-color:rgba(255,180,84,.5); }
  /* modals */
  #setupmodal, #colormodal { position:fixed; inset:0; z-index:1200; display:none; }
  #setupmodal { background:rgba(0,0,0,.55); }
  #setupmodal.show, #colormodal.show { display:block; }
  #colormodal.show { display:flex; flex-direction:column; }
  #setupsheet { position:absolute; left:0; right:0; bottom:0; background:var(--bg);
    border-top:1px solid var(--border); border-radius:16px 16px 0 0; padding:14px 16px 26px;
    max-height:88vh; overflow-y:auto; max-width:640px; margin:0 auto; }
  .sh-head { display:flex; align-items:center; justify-content:space-between; margin-bottom:10px; }
  .sh-head h3 { margin:0; font-size:1.05rem; }
  .sh-close { background:var(--cyan); color:#fff; border:none; border-radius:10px;
    padding:7px 15px; font-weight:800; cursor:pointer; }
  .card { background:var(--card); border:1px solid var(--border); border-radius:14px;
    padding:13px; margin-bottom:12px; }
  .card h4 { margin:0 0 8px; font-size:.9rem; }
  .note { font-size:.75rem; color:var(--muted); line-height:1.45; margin-top:8px; }
  .btn { display:inline-block; background:var(--cyan); color:#fff; border:none; border-radius:10px;
    padding:8px 14px; font-weight:700; cursor:pointer; margin:4px 6px 4px 0; }
  .btn.ghost { background:transparent; border:1px solid var(--border); color:var(--muted); }
  .btn.danger { background:rgba(255,107,107,.14); border:1px solid rgba(255,107,107,.5); color:#ff6b6b; }
  .keydot { display:inline-block; width:11px; height:11px; border-radius:50%; background:#5a626c;
    margin-left:6px; vertical-align:middle; }
  .keydot.ok { background:#06d6a0; } .keydot.bad { background:#ff6b6b; }
  .keyfile { position:absolute; width:1px; height:1px; opacity:0; }
  .msg { font-size:.78rem; color:var(--muted); margin-top:6px; min-height:1em; }
  .kv { display:flex; justify-content:space-between; padding:5px 0; font-size:.86rem;
    border-bottom:1px solid rgba(255,255,255,.05); }
  .viewgrid { display:grid; grid-template-columns:repeat(4,1fr); gap:6px; }
  .viewbtn { background:var(--card); border:1px solid var(--border); color:var(--muted);
    border-radius:10px; padding:9px 0; font-size:.78rem; font-weight:700; cursor:pointer; text-align:center; }
  .viewbtn.on { border-color:var(--soon); color:var(--soon); background:rgba(90,209,255,.12); }
  .kv b { color:var(--text); }
  .pmrow { display:flex; align-items:center; gap:10px; padding:7px 8px; border:1px solid var(--border);
    border-radius:10px; margin-bottom:6px; font-size:.84rem; }
  .pmrow .pmdel { margin-left:auto; color:#ff6b6b; border:1px solid rgba(255,107,107,.5);
    border-radius:9px; padding:3px 10px; font-size:.74rem; cursor:pointer; background:transparent; }
  /* colour wheel */
  .cw-head { display:flex; align-items:center; justify-content:space-between; padding:14px 16px; }
  .cw-title { color:#fff; font-weight:800; text-shadow:0 1px 3px #000; }
  .cw-close { background:var(--cyan); color:#fff; border:none; border-radius:11px;
    padding:7px 16px; font-weight:800; cursor:pointer; }
  .cw-stage { flex:1; display:flex; align-items:center; justify-content:center; }
  .cw-wheel { position:relative; width:300px; height:300px; }
  .cw-sw { position:absolute; width:34px; height:34px; border-radius:50%;
    border:2px solid rgba(255,255,255,.55); cursor:pointer; padding:0; box-shadow:0 2px 6px rgba(0,0,0,.5); }
  .cw-center { position:absolute; left:50%; top:50%; transform:translate(-50%,-50%);
    width:152px; height:152px; border-radius:50%; background:rgba(11,15,26,.94);
    border:1px solid var(--border); display:flex; flex-direction:column; align-items:center;
    justify-content:center; gap:8px; padding:10px; }
  .cw-ellist { display:flex; flex-direction:column; gap:3px; width:132px; }
  .cw-elrow { display:flex; align-items:center; gap:7px; padding:3px 5px; border-radius:8px;
    cursor:pointer; font-size:.72rem; color:var(--muted); }
  .cw-elrow.on { background:rgba(255,255,255,.08); color:var(--text); }
  .cw-radio { width:13px; height:13px; border-radius:50%; border:2px solid var(--muted); flex:none; }
  .cw-elrow.on .cw-radio { border-color:var(--soon); background:var(--soon); box-shadow:inset 0 0 0 2px var(--card); }
  .cw-pager { display:flex; align-items:center; gap:8px; margin-top:2px; }
  .cw-pg { background:var(--card); border:1px solid var(--border); color:var(--text);
    border-radius:7px; width:24px; height:22px; font-size:.9rem; cursor:pointer; line-height:1; }
  .cw-pgn { font-size:.66rem; color:var(--muted); }
  .cw-cur { display:flex; align-items:center; gap:7px; }
  .cw-swatch { width:22px; height:22px; border-radius:6px; border:1px solid rgba(255,255,255,.4); }
  .cw-hex { color:#fff; font-size:.78rem; text-shadow:0 1px 2px #000; }
  .cw-tools { padding:12px 18px 24px; background:linear-gradient(to top,rgba(0,0,0,.55),transparent); }
  .cw-llbl { color:#fff; font-size:.7rem; text-transform:uppercase; letter-spacing:1px; text-shadow:0 1px 2px #000; }
  .cw-range { width:100%; margin:6px 0 10px; accent-color:var(--cyan); }
  .cw-neutrals { display:flex; gap:6px; justify-content:center; margin-bottom:10px; }
  .cw-nsw { width:30px; height:30px; border-radius:7px; border:2px solid rgba(255,255,255,.4); cursor:pointer; padding:0; }
  .cw-hint { color:#e8ecf6; font-size:.74rem; text-align:center; opacity:.85; text-shadow:0 1px 2px #000; line-height:1.35; }
</style>
</head>
<body>
  <div class="tophud">
    <div class="clock" id="clock">--:--</div>
    <button class="gear" id="gearBtn" title="Setup">&#9881;</button>
  </div>
  <div class="updbar" id="updbar">updating night schedule<span class="dots"><i>.</i><i>.</i><i>.</i></span></div>

  <div class="tabs">
    <button class="tab on" data-tab="plan">Plan</button>
    <button class="tab" data-tab="lines">Lines</button>
    <button class="tab" data-tab="map">Map</button>
    <button class="tab" data-tab="pdf">PDF</button>
  </div>

  <div id="tab-plan">
    <div class="night-banner">Zagreb runs <b>four night trams</b> from
      <b>23:50 to 04:40</b>, about one every <b>50 minutes</b>. Pick where you
      are and where you are going; night.commute tells you which tram to take,
      and where to change if there is no direct one.</div>
    <div class="picker">
      <label>From station</label>
      <div class="stationbox">
        <input id="fromInput" placeholder="Tap to choose a station…" autocomplete="off" readonly>
        <button class="kbdbtn" id="fromKbd" title="Keyboard">⌨</button>
        <button class="clearbtn" id="fromClear">&times;</button>
        <div class="suggest" id="fromSug"></div>
      </div>
    </div>
    <div class="swap"><button class="swapbtn" id="swapBtn">&#8645;</button></div>
    <div class="picker">
      <label>To station</label>
      <div class="stationbox">
        <input id="toInput" placeholder="Tap to choose a station…" autocomplete="off" readonly>
        <button class="kbdbtn" id="toKbd" title="Keyboard">⌨</button>
        <button class="clearbtn" id="toClear">&times;</button>
        <div class="suggest" id="toSug"></div>
      </div>
    </div>
    <div class="result" id="result">
      <div class="hint">Choose two stations to see your night tram.</div>
    </div>
  </div>

  <div id="tab-lines" style="display:none"></div>
  <div id="tab-map" style="display:none">
    <div class="map-tip">The map starts empty. Check a line below to draw its
      route and stream its stops in. Tap <b>A</b> or <b>B</b> then tap the map to
      pick your ends (snaps to the nearest stop). One finger pans, pinch to zoom.</div>
    <div class="mappick">
      <button class="mapslot a active" id="mapSlotA"><div class="ms-l">A · from</div><div class="ms-v" id="mapA">tap the map</div></button>
      <button class="mapslot b" id="mapSlotB"><div class="ms-l">B · to</div><div class="ms-v" id="mapB">tap the map</div></button>
    </div>
    <div class="linechecks" id="lineChecks"></div>
    <div class="mapwrap">
      <button id="mapFs" class="mapfs" title="Fullscreen">⛶</button>
      <div id="map"></div>
    </div>
    <div class="result" id="mapResult"></div>
  </div>
  <div id="tab-pdf" style="display:none"></div>

  <!-- colour wheel overlay -->
  <div id="colormodal">
    <div class="cw-head"><span class="cw-title">C &middot; colour wheel</span>
      <button id="cwClose" class="cw-close">Done</button></div>
    <div class="cw-stage"><div class="cw-wheel">
      <div id="cwRing"></div>
      <div class="cw-center">
        <div class="cw-ellist" id="cwElList"></div>
        <div class="cw-pager"><button id="cwPrev" class="cw-pg">‹</button>
          <span id="cwPage" class="cw-pgn">1/1</span>
          <button id="cwNext" class="cw-pg">›</button></div>
        <div class="cw-cur"><span class="cw-swatch" id="cwCurrent"></span>
          <span id="cwHex" class="cw-hex">#000000</span></div>
      </div></div></div>
    <div class="cw-tools">
      <label class="cw-llbl">lightness</label>
      <input type="range" id="cwLight" min="15" max="90" value="58" class="cw-range">
      <div class="cw-neutrals" id="cwNeutrals"></div>
      <div class="cw-hint">Opposite colours contrast, neighbours harmonise. Pick a
        UI element, then a colour. The page behind changes live.</div>
    </div>
  </div>

  <!-- setup sheet -->
  <div id="setupmodal"><div id="setupsheet">
    <div class="sh-head"><h3>Setup</h3><button class="sh-close" id="setupClose">Close</button></div>
    <div class="card">
      <h4>Colours <span style="color:var(--muted);font-size:.7rem">color wheel</span></h4>
      <span class="note">Build your own scheme on the <b>C</b> button (top bar).
        Pick a UI element, pick a colour from the wheel, watch the page change.</span><br>
      <button class="btn" id="openColorFromGear">Open colour wheel</button>
      <button class="btn ghost" id="resetColors">Reset colours</button>
    </div>
    <div class="card">
      <h4>Map service</h4>
      <div class="viewgrid" id="engineGrid"></div>
      <h4 style="margin-top:12px">Base style</h4>
      <div class="viewgrid" id="viewGrid"></div>
      <h4 style="margin-top:12px">Google Maps key <span class="keydot" id="gmapsDot"></span></h4>
      <input type="file" id="gmapsFile" accept=".txt,text/plain" class="keyfile">
      <label for="gmapsFile" class="btn">Load key from file</label>
      <div id="gmapsMsg" class="msg"></div>
      <span class="note">OpenStreetMap is free and needs no key. A Google key is
        only needed for the Google Maps service. The key is never shown.</span>
    </div>
    <div class="card">
      <h4>Gemini key <span class="keydot" id="gemDot"></span></h4>
      <input type="file" id="gemFile" accept=".txt,text/plain" class="keyfile">
      <label for="gemFile" class="btn">Load key from file</label>
      <button class="btn ghost" id="gemTest">Test key</button>
      <div id="gemMsg" class="msg"></div>
      <span class="note">Green means the key works. Used only to read the official
        ZET night-tram PDFs on the PDF tab. The key is never shown.</span>
    </div>
    <div class="card">
      <h4>Live schedule <span style="color:var(--muted);font-size:.7rem">ZET GTFS</span></h4>
      <div id="nightSchedInfo" class="note">Checking…</div>
      <button class="btn" id="nightUpdate">Update from ZET now</button>
      <div id="nightSchedMsg" class="msg"></div>
      <span class="note">Real night-tram times come from the ZET GTFS feed and
        refresh automatically each night. The built-in timetable is used if the
        feed can't be reached. PDF below stays as a second source.</span>
    </div>
    <div class="card">
      <h4>PDF manager</h4>
      <div id="pdfMgr"><span class="note">Loading…</span></div>
      <button class="btn danger" id="pdfClearAll">Delete all cached PDFs</button>
      <span class="note">Night-tram PDFs are cached forever and never refetched
        until you delete them here.</span>
    </div>
    <div class="card">
      <h4>The Commute family</h4>
      <div class="kv"><span>&#9728;&#65039; day.commute</span><b>daytime buses &amp; trams</b></div>
      <div class="kv"><span>&#127769; night.commute</span><b>this app · night trams</b></div>
      <span class="note">Two specialised apps for two halves of the day.</span>
    </div>
    <div class="card"><h4>About</h4>
      <div class="kv"><span>Version</span><b id="verLine">…</b></div></div>
  </div></div>

<script>

/* ===== Night Commute front-end ===== */
let NET = null, COORDS = {}, SCHED = null;
const LINE_COLORS = { "31":"#ff6b6b", "32":"#ffd166", "33":"#06d6a0", "34":"#4d96ff" };
let STATIONS = [];       // unique sorted station names
let ST_LINES = {};       // station -> [lines]
let FROM = "", TO = "";
let TAB = "plan";

function normStr(s){ return (s||"").toLowerCase()
  .replace(/[čć]/g,"c").replace(/š/g,"s").replace(/ž/g,"z").replace(/đ/g,"d")
  .replace(/[^a-z0-9 ]/g,"").trim(); }

async function loadNet(){
  const [n,c,s] = await Promise.all([
    fetch("night.json",{cache:"no-store"}).then(r=>r.json()),
    fetch("coords.json",{cache:"no-store"}).then(r=>r.json()).catch(()=>({})),
    fetch("night-sched",{cache:"no-store"}).then(r=>r.json()).catch(()=>null),
  ]);
  NET = n; COORDS = c; SCHED = (s && Object.keys(s).length) ? s : null;
  if (NET && NET.source==="gtfs") window._gtfsLoaded = true;
  const idx = {};
  Object.keys(NET.lines).forEach(ln=>{
    NET.lines[ln].stations.forEach(st=>{ (idx[st]=idx[st]||new Set()).add(ln); });
  });
  ST_LINES = {}; Object.keys(idx).forEach(s=>ST_LINES[s]=[...idx[s]].sort());
  STATIONS = Object.keys(ST_LINES).sort((a,b)=>a.localeCompare(b,"hr"));
}

/* ---- station search ---- */
function searchStations(q){
  const nq = normStr(q);
  if (!nq) return STATIONS.slice();
  const starts=[], contains=[];
  STATIONS.forEach(s=>{ const ns=normStr(s);
    if (ns.startsWith(nq)) starts.push(s);
    else if (ns.includes(nq)) contains.push(s); });
  return starts.concat(contains);
}
function lineBadge(ln){
  return '<span class="sg-ln" style="background:'+LINE_COLORS[ln]+'">'+ln+'</span>';
}
function wireSearch(inputId, sugId, which){
  const inp=document.getElementById(inputId), sug=document.getElementById(sugId);
  let hi=-1, list=[];
  function render(){
    list = searchStations(inp.value).slice(0,40);
    sug.innerHTML = list.map((s,i)=>
      '<div class="sg-item'+(i===hi?" hi":"")+'" data-i="'+i+'">'+s+
      '<span class="sg-lines">'+ST_LINES[s].map(lineBadge).join("")+'</span></div>').join("");
    sug.classList.toggle("show", list.length>0);
    sug.querySelectorAll(".sg-item").forEach(el=>{
      el.addEventListener("mousedown",(e)=>{ e.preventDefault(); choose(list[+el.dataset.i]); });
    });
  }
  function choose(s){
    inp.value=s; sug.classList.remove("show");
    inp.setAttribute("readonly",""); inp.blur();
    const kb=document.getElementById(which==="from"?"fromKbd":"toKbd");
    if (kb) kb.classList.remove("on");
    if (which==="from") FROM=s; else TO=s;
    computeRoute();
  }
  // tapping the (readonly) field just opens the picker, no keyboard
  inp.addEventListener("click",()=>{ render(); });
  inp.addEventListener("focus",render);
  inp.addEventListener("input",()=>{ hi=-1;
    if (which==="from") FROM=""; else TO=""; render(); });
  inp.addEventListener("keydown",(e)=>{
    if (e.key==="ArrowDown"){ hi=Math.min(hi+1,list.length-1); render(); e.preventDefault(); }
    else if (e.key==="ArrowUp"){ hi=Math.max(hi-1,0); render(); e.preventDefault(); }
    else if (e.key==="Enter" && hi>=0){ choose(list[hi]); e.preventDefault(); }
    else if (e.key==="Escape"){ sug.classList.remove("show"); }
  });
  inp.addEventListener("blur",()=>setTimeout(()=>sug.classList.remove("show"),150));
  // manual keyboard control: the ⌨ icon toggles the soft keyboard on/off
  const kbdId = which==="from" ? "fromKbd" : "toKbd";
  const kbd = document.getElementById(kbdId);
  if (kbd){
    kbd.addEventListener("click",(e)=>{
      e.preventDefault(); e.stopPropagation();
      const typing = !inp.hasAttribute("readonly");
      if (typing){ inp.setAttribute("readonly",""); inp.blur(); kbd.classList.remove("on"); }
      else { inp.removeAttribute("readonly"); inp.focus(); kbd.classList.add("on");
             render(); }
    });
  }
}

/* ---- night-tram time helpers (service night wraps past midnight) ---- */
// minutes since 18:00 "service anchor", so 23:50 < 00:10 ordering holds
function nightMins(hhmm){
  const [h,m]=hhmm.split(":").map(Number);
  let x=h*60+m; if (h<12) x+=24*60;   // after-midnight belongs to same night
  return x;
}
function nowNightMins(){
  const d=new Date(); let x=d.getHours()*60+d.getMinutes();
  if (d.getHours()<5) x+=24*60; return x;   // only the after-midnight tail belongs to the previous night
}
// departures for a line from the terminal that starts the given travel order
function lineTimes(ln, fromTerm){
  const L=NET.lines[ln];
  return (fromTerm===L.termA ? L.departA : L.departB) || [];
}
// which terminal a line departs FROM so it passes `a` before `b`
function travelDirection(ln, a, b){
  const sts=NET.lines[ln].stations;
  const ia=sts.indexOf(a), ib=sts.indexOf(b);
  if (ia<0||ib<0) return null;
  // if a comes before b in the A->B listing, the tram from termA serves it
  return ia<ib ? NET.lines[ln].termA : NET.lines[ln].termB;
}
// Next departures. Anything already gone tonight wraps to the next night (+24h),
// so there is always a next tram to show — night always comes.
function upcoming(times, n){
  const now=nowNightMins();
  const up=times.map(t=>{ let m=nightMins(t)-now; if (m< -2) m+=24*60; return {t, m}; })
    .sort((a,b)=>a.m-b.m);
  return up.slice(0,n||4);
}
// ---- real GTFS times at your actual boarding station (dual-source) ----
// Seconds since midnight in the same night anchor GTFS uses (24:xx..30:xx).
function nowNightSecs(){ const d=new Date(); let h=d.getHours();
  if (h<5) h+=24; return h*3600+d.getMinutes()*60+d.getSeconds(); }
function secClk(sec){ sec=((sec%86400)+86400)%86400;
  return String(Math.floor(sec/3600)).padStart(2,"0")+":"+
         String(Math.floor((sec%3600)/60)).padStart(2,"0"); }
// friendly countdown: "now", "42 min", or "6 h" for the far-off next night
function fmtMin(m){ return m<=0 ? "now" : (m<90 ? m+" min" : Math.round(m/60)+" h"); }
// direction index 0/1 for travelling a -> b along a line's dir0 station order
function dirIndex(ln,a,b){ const sts=NET.lines[ln].stations;
  const ia=sts.indexOf(a), ib=sts.indexOf(b);
  if (ia<0||ib<0) return -1; return ia<ib?0:1; }
// real departures at a (toward b) with arrival at b, from tonight's GTFS trips
function realTimes(ln,a,b,n){
  const L=NET.lines[ln];
  if (!SCHED||!L||!L.stopmap||!L.stopmap[a]||!L.stopmap[b]) return null;
  const d=dirIndex(ln,a,b); if (d<0) return null;
  const trips=SCHED[ln]&&SCHED[ln][String(d)]; if (!trips||!trips.length) return null;
  const aId=L.stopmap[a][d], bId=L.stopmap[b][d];
  const now=nowNightSecs(), out=[];
  trips.forEach(m=>{ const da=m[aId], ar=m[bId];
    if (da!=null&&ar!=null&&da<ar){
      let min=Math.round((da-now)/60);
      if (min < -2) min=Math.round((da+86400-now)/60);   // already gone → next night
      out.push({dep:da,arr:ar,min}); } });
  out.sort((x,y)=>x.min-y.min);
  return out.slice(0,n||4);
}

/* ---- routing ---- */
function directLines(a,b){
  return (ST_LINES[a]||[]).filter(ln=>(ST_LINES[b]||[]).includes(ln)
    && NET.lines[ln].stations.indexOf(a)>=0 && NET.lines[ln].stations.indexOf(b)>=0);
}
function transferOptions(a,b){
  // find a hub h reachable from a on lineA and to b on lineB (lineA!=lineB)
  const out=[];
  STATIONS.forEach(h=>{
    if (h===a||h===b) return;
    const la=directLines(a,h), lb=directLines(h,b);
    la.forEach(x=>lb.forEach(y=>{ if (x!==y) out.push({hub:h,l1:x,l2:y}); }));
  });
  // prefer well-known central hubs and fewest total; dedupe by (l1,hub,l2)
  const seen=new Set(), uniq=[];
  out.forEach(o=>{ const k=o.l1+"|"+o.hub+"|"+o.l2;
    if (!seen.has(k)){ seen.add(k); uniq.push(o); } });
  const rank=h=>["Trg bana J. Jelačića","Trg bana Jelačića","Glavni kolodvor","Frankopanska","Draškovićeva"].indexOf(h);
  uniq.sort((p,q)=>{ const rp=rank(p.hub),rq=rank(q.hub);
    return (rp<0?9:rp)-(rq<0?9:rq); });
  return uniq;
}
function legHtml(ln, a, b, markNext){
  const term = travelDirection(ln,a,b);
  const L=NET.lines[ln];
  const dirLabel = term + " → " + (term===L.termA?L.termB:L.termA);
  const rt = realTimes(ln,a,b,4);
  let times;
  if (rt){
    times = rt.length
      ? rt.map((u,i)=>'<span class="legtime'+(markNext&&i===0?" next":"")+'">'+
          secClk(u.dep)+' <small>('+fmtMin(u.min)+')</small>'+
          '<small class="arr"> → '+secClk(u.arr)+'</small></span>').join("")
      : '<span class="legtime">schedule loading&hellip;</span>';
  } else {
    const ups = upcoming(lineTimes(ln, term), 4);
    times = ups.length
      ? ups.map((u,i)=>'<span class="legtime'+(markNext&&i===0?" next":"")+'">'+u.t+
          ' <small>('+fmtMin(u.m)+')</small></span>').join("")
      : '<span class="legtime">schedule loading&hellip;</span>';
  }
  return '<div class="leg"><span class="lnbadge" style="background:'+LINE_COLORS[ln]+'">'+ln+
    '</span><div class="legbody"><div class="legroute">'+a+' → '+b+'</div>'+
    '<div class="legdir">tram towards '+dirLabel+'</div>'+
    '<div class="legtimes">'+times+'</div></div></div>';
}
function computeRoute(target){
  const box = document.getElementById(target||"result");
  if (!FROM || !TO){ box.innerHTML='<div class="hint">Choose two stations to see your night tram.</div>'; return; }
  if (FROM===TO){ box.innerHTML='<div class="no-route">Same station — you are already there.</div>'; return; }
  const direct = directLines(FROM,TO);
  if (direct.length){
    let html='<div class="journey"><div class="j-head">&#128649; Direct night tram</div>'+
      '<div class="j-sub">'+direct.length+' line'+(direct.length>1?"s":"")+' take'+(direct.length>1?"":"s")+' you straight there.</div>';
    direct.forEach(ln=> html+=legHtml(ln,FROM,TO,true));
    html+='</div>';
    box.innerHTML=html; return;
  }
  const opts = transferOptions(FROM,TO);
  if (!opts.length){
    box.innerHTML='<div class="no-route">No night-tram route between these two on '+
      'the 31–34 network. They may be on separate branches; a night bus or taxi '+
      'may be needed for part of the trip.</div>'; return;
  }
  const o=opts[0];
  let html='<div class="journey"><div class="j-head">&#128260; One change</div>'+
    '<div class="j-sub">No direct tram, so change at <b>'+o.hub+'</b>.</div>';
  html+=legHtml(o.l1,FROM,o.hub,true);
  html+='<div class="transfer-note">&#128260; Change at '+o.hub+' to line '+o.l2+'</div>';
  html+=legHtml(o.l2,o.hub,TO,false);
  html+='</div>';
  if (opts.length>1){
    const alt=opts.slice(1,3).map(x=>x.l1+"→"+x.l2+" at "+x.hub).join(",  ");
    html+='<div class="note" style="text-align:center">Other changes: '+alt+'</div>';
  }
  box.innerHTML=html;
}

/* ---- Lines explorer ---- */
function renderLines(){
  const wrap=document.getElementById("tab-lines");
  const hubs={}; STATIONS.forEach(s=>{ if (ST_LINES[s].length>1) hubs[s]=1; });
  let html='<div class="pill-legend">'+Object.keys(NET.lines).map(ln=>
    '<span class="lg"><span class="lgdot" style="background:'+LINE_COLORS[ln]+'"></span>'+
    ln+' '+NET.lines[ln].name+'</span>').join("")+'</div>';
  Object.keys(NET.lines).forEach(ln=>{
    const L=NET.lines[ln];
    html+='<div class="linecard"><div class="lc-head">'+
      '<span class="lc-badge" style="background:'+LINE_COLORS[ln]+'">'+ln+'</span>'+
      '<span class="lc-name">'+L.name+'</span></div>'+
      '<div class="note">'+L.termA+' ⇄ '+L.termB+' · every ~50 min, 23:50–04:40</div>'+
      '<div class="lc-stations">';
    L.stations.forEach((st,i)=>{
      const term=i===0||i===L.stations.length-1;
      const hub=hubs[st];
      html+='<div class="lc-st'+(term?" term":"")+(hub?" hub":"")+'">'+
        '<span class="dotline"><span class="stdot" style="background:'+LINE_COLORS[ln]+'"></span></span>'+
        '<span>'+st+'</span>'+(hub?'<span class="hubtag">change '+ST_LINES[st].filter(x=>x!==ln).join("/")+'</span>':'')+
        '</div>';
    });
    html+='</div></div>';
  });
  wrap.innerHTML=html;
}

/* ---- Map ---- */
let MAP=null, MAP_A=null, MAP_B=null, mapLayer=[], ACTIVE_SLOT="A";
function setActiveSlot(which){
  ACTIVE_SLOT=which;
  const a=document.getElementById("mapSlotA"), b=document.getElementById("mapSlotB");
  if(a) a.classList.toggle("active",which==="A");
  if(b) b.classList.toggle("active",which==="B");
}
function nearestStation(lat,lng){
  let best=null,bd=1e9;
  Object.keys(COORDS).forEach(s=>{ if(!ST_LINES[s])return;
    const c=COORDS[s]; const d=(c[0]-lat)**2+(c[1]-lng)**2;
    if(d<bd){bd=d;best=s;} });
  return best;
}
// Google Maps. View mode is chosen in settings: day (roadmap, the default and
// easiest to read), terrain, satellite, or night (a dark styled roadmap).
// ============================================================================
// Map engines. Two services, freely switchable in the gear:
//   * "osm"    — OpenStreetMap via Leaflet (free, no key, works out of the box)
//   * "google" — Google Maps (best quality; needs an API key + internet)
// The transit lines/markers are drawn by whichever engine is active, so any
// base style works with the overlay. The map opens EMPTY — no markers, no lines.
// The checklist under the map turns each line on/off: checking streams that
// line's stops in one at a time and draws its route; unchecking removes it.
// One finger pans, pinch zooms; there are no +/- buttons.
// ============================================================================
let GKEY="", GMAP_LOADED=false;
let MAP_ENGINE = localStorage.getItem("nc_engine") || "osm";
let LINE_ON = {}; try { LINE_ON = JSON.parse(localStorage.getItem("nc_lines_on")||"{}"); } catch(e){ LINE_ON={}; }
let LINE_LAYERS = {};                 // ln -> {markers:[handle], poly:handle}
let _LTILE = null;
function saveLinesOn(){ try{ localStorage.setItem("nc_lines_on",JSON.stringify(LINE_ON)); }catch(e){} }

const BASES = {
  osm:    [{k:"osm",n:"OSM"},{k:"light",n:"Carto Light"},{k:"dark",n:"Carto Dark"},{k:"topo",n:"OpenTopo"}],
  google: [{k:"day",n:"Day"},{k:"terrain",n:"Terrain"},{k:"satellite",n:"Satellite"},{k:"night",n:"Night"}],
};
function baseStyle(){ return localStorage.getItem("nc_base_"+MAP_ENGINE) || BASES[MAP_ENGINE][0].k; }
function setBaseStyle(k){ try{ localStorage.setItem("nc_base_"+MAP_ENGINE,k); }catch(e){}
  if (MAP) theEng().setBase(k); }

const NIGHT_STYLE=[
  {elementType:"geometry",stylers:[{color:"#1a2032"}]},
  {elementType:"labels.text.stroke",stylers:[{color:"#0b0f1a"}]},
  {elementType:"labels.text.fill",stylers:[{color:"#9aa4be"}]},
  {featureType:"road",elementType:"geometry",stylers:[{color:"#2a3350"}]},
  {featureType:"water",elementType:"geometry",stylers:[{color:"#0e1626"}]},
  {featureType:"poi",elementType:"labels",stylers:[{visibility:"off"}]},
];

// ---- Google engine (paid tier / key) ----
const GEng = {
  ensure(){ return new Promise((res)=>{
    if (window.google && window.google.maps) return res(true);
    fetch("gmaps-key",{cache:"no-store"}).then(r=>r.json()).then(d=>{
      GKEY=(d&&d.key)||""; if(!GKEY) return res(false);
      window._gcb=()=>res(true);
      const sc=document.createElement("script");
      sc.src="https://maps.googleapis.com/maps/api/js?key="+encodeURIComponent(GKEY)+"&callback=_gcb";
      sc.onerror=()=>res(false); document.head.appendChild(sc);
    }).catch(()=>res(false)); }); },
  _type(k){ return k==="terrain"?google.maps.MapTypeId.TERRAIN
    : k==="satellite"?google.maps.MapTypeId.HYBRID : google.maps.MapTypeId.ROADMAP; },
  create(el){ const k=baseStyle();
    MAP=new google.maps.Map(el,{center:{lat:45.812,lng:15.978},zoom:12,mapTypeId:this._type(k),
      disableDefaultUI:true, zoomControl:false, gestureHandling:"greedy",   // 1-finger pan, pinch zoom, no +/-
      styles:k==="night"?NIGHT_STYLE:null}); },
  setBase(k){ MAP.setMapTypeId(this._type(k)); MAP.setOptions({styles:k==="night"?NIGHT_STYLE:null}); },
  _stroke(){ const k=baseStyle(); return (k==="day"||k==="terrain")?"#0b0f1a":"#ffffff"; },
  polyline(pts,color){ return new google.maps.Polyline({map:MAP,
    path:pts.map(c=>({lat:c[0],lng:c[1]})),strokeColor:color,strokeOpacity:.9,strokeWeight:5}); },
  marker(c,color,hub,title,onClick){ const mk=new google.maps.Marker({map:MAP,
    position:{lat:c[0],lng:c[1]},title:title,
    icon:{path:google.maps.SymbolPath.CIRCLE,scale:hub?7:5,fillColor:color,fillOpacity:1,
      strokeColor:this._stroke(),strokeWeight:2}});
    mk.addListener("click",onClick); return mk; },
  remove(h){ h.setMap(null); },
  onClick(cb){ MAP.addListener("click",e=>cb(e.latLng.lat(),e.latLng.lng())); },
  resize(){ if(MAP) google.maps.event.trigger(MAP,"resize"); },
  destroy(){ /* google map needs no explicit teardown */ },
};

// ---- Leaflet / OpenStreetMap engine (free, no key) ----
const OSM_TILES = {
  osm:  {u:"https://tile.openstreetmap.org/{z}/{x}/{y}.png", a:"&copy; OpenStreetMap", max:19, sub:null},
  light:{u:"https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png", a:"&copy; OpenStreetMap &copy; CARTO", max:20, sub:"abcd"},
  dark: {u:"https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", a:"&copy; OpenStreetMap &copy; CARTO", max:20, sub:"abcd"},
  topo: {u:"https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png", a:"&copy; OpenTopoMap", max:17, sub:"abc"},
};
const LEng = {
  ensure(){ return new Promise((res)=>{
    if (window.L) return res(true);
    const css=document.createElement("link"); css.rel="stylesheet";
    css.href="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css";
    document.head.appendChild(css);
    const sc=document.createElement("script");
    sc.src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js";
    sc.onload=()=>res(!!window.L); sc.onerror=()=>res(false);
    document.head.appendChild(sc); }); },
  create(el){ MAP=L.map(el,{zoomControl:false, attributionControl:true, tap:true,
      dragging:true, touchZoom:true, scrollWheelZoom:true}).setView([45.812,15.978],12);
    this.setBase(baseStyle()); },
  setBase(k){ const t=OSM_TILES[k]||OSM_TILES.osm;
    if(_LTILE){ try{MAP.removeLayer(_LTILE);}catch(e){} }
    const opt={maxZoom:t.max, attribution:t.a}; if(t.sub) opt.subdomains=t.sub;
    _LTILE=L.tileLayer(t.u,opt).addTo(MAP); },
  polyline(pts,color){ return L.polyline(pts.map(c=>[c[0],c[1]]),{color:color,weight:5,opacity:.9}).addTo(MAP); },
  marker(c,color,hub,title,onClick){ const mk=L.circleMarker([c[0],c[1]],
    {radius:hub?7:5,fillColor:color,color:"#0b0f1a",weight:2,fillOpacity:1});
    mk.bindTooltip(title); mk.on("click",onClick); mk.addTo(MAP); return mk; },
  remove(h){ try{ MAP.removeLayer(h); }catch(e){} },
  onClick(cb){ MAP.on("click",e=>cb(e.latlng.lat,e.latlng.lng)); },
  resize(){ if(MAP && MAP.invalidateSize) setTimeout(()=>{ try{MAP.invalidateSize();}catch(e){} },60); },
  destroy(){ try{ if(MAP && MAP.remove) MAP.remove(); }catch(e){} },
};
function theEng(){ return MAP_ENGINE==="google" ? GEng : LEng; }

// ---- line drawing (engine-agnostic, streamed) ----
function addLine(ln){
  if (!MAP || LINE_LAYERS[ln]) return;
  const E=theEng(), L=NET.lines[ln];
  const pts=L.stations.map(s=>COORDS[s]).filter(Boolean);
  const lay={markers:[], poly:(pts.length>1 ? E.polyline(pts,LINE_COLORS[ln]) : null)};
  LINE_LAYERS[ln]=lay;
  let i=0;
  (function batch(){
    if (!MAP || LINE_LAYERS[ln]!==lay) return;              // toggled off mid-stream
    for (let k=0;k<5 && i<L.stations.length;k++,i++){
      const s=L.stations[i], c=COORDS[s]; if(!c) continue;
      const hub=ST_LINES[s] && ST_LINES[s].length>1;
      lay.markers.push(E.marker(c,LINE_COLORS[ln],hub,
        s+" ("+((ST_LINES[s]||[ln]).join("/"))+")", ()=>pickMapStation(s)));
    }
    if (i<L.stations.length) setTimeout(batch,20);           // one small batch per frame
  })();
}
function removeLine(ln){
  const lay=LINE_LAYERS[ln]; if(!lay) return;
  const E=theEng();
  lay.markers.forEach(h=>E.remove(h));
  if(lay.poly) E.remove(lay.poly);
  delete LINE_LAYERS[ln];
}
function toggleLine(ln,on){ LINE_ON[ln]=on; saveLinesOn();
  if(!MAP) return; on ? addLine(ln) : removeLine(ln); }
function renderLineChecklist(){
  const el=document.getElementById("lineChecks"); if(!el||!NET) return;
  el.innerHTML=Object.keys(NET.lines).map(ln=>{ const L=NET.lines[ln]; const on=!!LINE_ON[ln];
    return '<button class="lchk'+(on?' on':'')+'" data-ln="'+ln+'">'+
      '<span class="lchk-box">'+(on?'\u2713':'')+'</span>'+
      '<span class="lnbadge" style="background:'+LINE_COLORS[ln]+'">'+ln+'</span>'+
      '<span class="lchk-t">'+L.termA+' \u2192 '+L.termB+'</span></button>';
  }).join("");
  el.querySelectorAll(".lchk").forEach(b=>b.addEventListener("click",()=>{
    toggleLine(b.dataset.ln,!LINE_ON[b.dataset.ln]); renderLineChecklist(); }));
}

async function initMap(){
  const el=document.getElementById("map");
  if (MAP){ theEng().resize(); return; }
  const ok=await theEng().ensure();
  if (!ok){ el.innerHTML='<div class="hint">'+(MAP_ENGINE==="google"
    ? 'Google Maps needs a key and internet. Add your key in the gear, or switch to free OpenStreetMap in the gear.'
    : 'OpenStreetMap needs internet to load its tiles. Reopen the Map tab once you are online.')+'</div>'; return; }
  el.innerHTML="";
  theEng().create(el);
  theEng().onClick((lat,lng)=>{ const s=nearestStation(lat,lng); if(s) pickMapStation(s); });
  renderLineChecklist();
  Object.keys(NET.lines).forEach(ln=>{ if(LINE_ON[ln]) addLine(ln); });   // restore checked lines (default: none)
  theEng().resize();
  GMAP_LOADED=true;
}
function resetMap(){
  Object.keys(LINE_LAYERS).forEach(ln=>removeLine(ln)); LINE_LAYERS={};
  theEng().destroy(); _LTILE=null; MAP=null; GMAP_LOADED=false;
}
function setMapEngine(engine){
  if (engine===MAP_ENGINE) return;
  resetMap();                                   // tear down with the CURRENT engine first
  MAP_ENGINE=engine; try{ localStorage.setItem("nc_engine",engine); }catch(e){}
  if (TAB==="map") initMap();
}

function toggleMapFullscreen(){
  const el=document.getElementById("map");
  const wrap=(el.closest && el.closest(".mapwrap")) || el;
  if (!document.fullscreenElement){
    (wrap.requestFullscreen||wrap.webkitRequestFullscreen||function(){}).call(wrap);
  } else {
    (document.exitFullscreen||document.webkitExitFullscreen||function(){}).call(document);
  }
  setTimeout(()=>{ if(MAP) theEng().resize(); },300);
}
function pickMapStation(s){
  if (ACTIVE_SLOT==="B") MAP_B=s; else MAP_A=s;   // only the chosen end moves
  document.getElementById("mapA").textContent = MAP_A || "tap the map";
  document.getElementById("mapB").textContent = MAP_B || "tap the map";
  if (MAP_A && MAP_B){ FROM=MAP_A; TO=MAP_B; computeRoute("mapResult"); }
  else document.getElementById("mapResult").innerHTML="";
}

/* ---- PDF tab ---- */
let PDFSCHED={};
try{ PDFSCHED=JSON.parse(localStorage.getItem("nc_pdfsched")||"{}")||{}; }catch(e){}
function savePdf(){ try{ localStorage.setItem("nc_pdfsched",JSON.stringify(PDFSCHED)); }catch(e){} }
function renderPdf(){
  const wrap=document.getElementById("tab-pdf");
  const lines=Object.keys(NET.lines);
  fetchPdf(lines);
  let html='<div class="night-banner">Official ZET night-tram timetables (PDF), '+
    'read once by Gemini and cached forever. These are the source of truth for '+
    'the exact departure minutes.</div>';
  lines.forEach(ln=>{
    const L=NET.lines[ln]; const sc=PDFSCHED[ln];
    html+='<div class="linecard"><div class="lc-head">'+
      '<span class="lc-badge" style="background:'+LINE_COLORS[ln]+'">'+ln+'</span>'+
      '<span class="lc-name">'+L.name+'</span></div>';
    html+='<a class="note" style="color:var(--soon)" target="_blank" href="'+
      'https://www.zet.hr/UserDocsImages/Tramvajske%20linije%20-%20vozni%20red/'+ln+'.pdf">official ZET PDF ↗</a>';
    if (!sc){ html+='<div class="note">reading ZET PDF…</div>'; }
    else if (sc.error || !sc.directions){
      // fall back to the built-in embedded times
      html+='<div class="note" style="color:var(--accent)">Using built-in times (add a Gemini key to read the PDF).</div>';
      [ [L.termA,L.departA],[L.termB,L.departB] ].forEach(([t,arr])=>{
        html+='<div class="note"><b>from '+t+':</b> '+arr.join(", ")+'</div>'; });
    } else {
      sc.directions.forEach(d=>{
        html+='<div class="note"><b>from '+(d.terminal||"?")+':</b> '+(d.times||[]).join(", ")+'</div>'; });
    }
    html+='</div>';
  });
  wrap.innerHTML=html;
}
function fetchPdf(lines){
  const need=lines.filter(l=>!PDFSCHED[l]);
  if (!need.length) return;
  fetch("pdf-sched?routes="+need.join(","),{cache:"no-store"}).then(r=>r.json())
    .then(d=>{ if(d&&d.routes){ Object.keys(d.routes).forEach(k=>PDFSCHED[k]=d.routes[k]); savePdf(); if(TAB==="pdf") renderPdf(); } })
    .catch(()=>{});
}

/* ---- tabs ---- */
function switchTab(t){
  TAB=t;
  document.querySelectorAll(".tab").forEach(x=>x.classList.toggle("on",x.dataset.tab===t));
  ["plan","lines","map","pdf"].forEach(x=>
    document.getElementById("tab-"+x).style.display = x===t?"":"none");
  if (t==="lines") renderLines();
  if (t==="map") initMap();
  if (t==="pdf") renderPdf();
}

/* ---- clock ---- */
function tick(){
  const d=new Date();
  document.getElementById("clock").textContent =
    d.toLocaleTimeString([],{hour:"2-digit",minute:"2-digit",second:"2-digit"});
  if (TAB==="plan" && FROM && TO) computeRoute();
}

/* ===== colour wheel (from the Commute family) ===== */
const UI_ELEMENTS=[
  {key:"--bg",name:"Background"},{key:"--card",name:"Cards / rows"},
  {key:"--text",name:"Main text"},{key:"--muted",name:"Muted text"},
  {key:"--border",name:"Borders / lines"},{key:"--cyan",name:"Primary (tabs)"},
  {key:"--accent",name:"Accent (change, A)"},{key:"--soon",name:"Times / soon"},
];
let CUSTOM={}; try{ CUSTOM=JSON.parse(localStorage.getItem("nc_custom")||"{}")||{}; }catch(e){}
function saveCustom(){ try{ localStorage.setItem("nc_custom",JSON.stringify(CUSTOM)); }catch(e){} }
function applyCustom(){ const r=document.documentElement;
  UI_ELEMENTS.forEach(el=>{ if(CUSTOM[el.key]) r.style.setProperty(el.key,CUSTOM[el.key]);
    else r.style.removeProperty(el.key); }); }
function currentVar(k){ return CUSTOM[k] ||
  getComputedStyle(document.documentElement).getPropertyValue(k).trim() || "#000000"; }
function hslToHex(h,s,l){ s/=100;l/=100; const k=n=>(n+h/30)%12,a=s*Math.min(l,1-l);
  const f=n=>l-a*Math.max(-1,Math.min(k(n)-3,Math.min(9-k(n),1)));
  const to=x=>Math.round(255*x).toString(16).padStart(2,"0");
  return "#"+to(f(0))+to(f(8))+to(f(4)); }
let CW_EL=UI_ELEMENTS[0].key, CW_L=58;
function buildWheel(){ const ring=document.getElementById("cwRing"); if(!ring)return;
  ring.innerHTML=""; const R=128,C=150,SW=34;
  for(let i=0;i<18;i++){ const hue=Math.round(i*20); const hex=hslToHex(hue,85,CW_L);
    const ang=(i/18)*2*Math.PI-Math.PI/2; const x=C+R*Math.cos(ang)-SW/2,y=C+R*Math.sin(ang)-SW/2;
    const b=document.createElement("button"); b.className="cw-sw";
    b.style.left=x+"px"; b.style.top=y+"px"; b.style.background=hex; b.title=hex;
    b.addEventListener("click",()=>pickColor(hex)); ring.appendChild(b); }
  const nr=document.getElementById("cwNeutrals");
  if(nr){ nr.innerHTML=""; ["#ffffff","#c9d1d9","#8b93ad","#3a4258","#1a2032","#0b0f1a","#000000"]
    .forEach(hex=>{ const b=document.createElement("button"); b.className="cw-nsw";
      b.style.background=hex; b.title=hex; b.addEventListener("click",()=>pickColor(hex)); nr.appendChild(b); }); }
}

// Flash the element being edited a few times (white, then black) so the user
// sees exactly which part of the UI they are about to recolour, then restore.
let _flashTimer = null;
function flashElement(key){
  const root = document.documentElement;
  if (_flashTimer){ clearInterval(_flashTimer); _flashTimer=null; }
  const restore = CUSTOM[key] || "";
  const seq = ["#ffffff","#000000","#ffffff","#000000"];
  let i=0;
  root.style.setProperty(key, seq[0]);
  _flashTimer = setInterval(()=>{
    i++;
    if (i>=seq.length){
      clearInterval(_flashTimer); _flashTimer=null;
      if (restore) root.style.setProperty(key, restore);
      else root.style.removeProperty(key);
      return;
    }
    root.style.setProperty(key, seq[i]);
  }, 130);
}
// element radio list, paginated to fit inside the wheel centre
let CW_PAGE = 0;
const CW_PER_PAGE = 4;
function cwPages(){ return Math.max(1, Math.ceil(UI_ELEMENTS.length / CW_PER_PAGE)); }
function renderElList(){
  const box = document.getElementById("cwElList"); if(!box) return;
  const start = CW_PAGE*CW_PER_PAGE;
  const slice = UI_ELEMENTS.slice(start, start+CW_PER_PAGE);
  box.innerHTML = slice.map(el =>
    '<div class="cw-elrow'+(el.key===CW_EL?' on':'')+'" data-k="'+el.key+'">'+
    '<span class="cw-radio"></span><span>'+el.name+'</span></div>').join("");
  box.querySelectorAll(".cw-elrow").forEach(row=>{
    row.addEventListener("click", ()=>{
      CW_EL = row.dataset.k; renderElList(); syncColor(); flashElement(CW_EL);
    });
  });
  const pg = document.getElementById("cwPage");
  if (pg) pg.textContent = (CW_PAGE+1)+"/"+cwPages();
}

function pickColor(hex){ CUSTOM[CW_EL]=hex; saveCustom(); applyCustom(); syncColor();
  if (TAB==="map" && MAP) { /* colors are CSS, lines already drawn */ }
  if (TAB==="lines") renderLines(); if (TAB==="pdf") renderPdf(); if (TAB==="plan") computeRoute(); }
function syncColor(){
  const cur=document.getElementById("cwCurrent"); if(cur){ const v=currentVar(CW_EL);
    cur.style.background=v; document.getElementById("cwHex").textContent=v.toUpperCase(); } }
function openWheel(){ const m=document.getElementById("colormodal");
  const prev=document.getElementById("cwPrev"), next=document.getElementById("cwNext");
  if(prev && !prev._w){ prev._w=1;
    prev.addEventListener("click",()=>{ CW_PAGE=(CW_PAGE-1+cwPages())%cwPages(); renderElList(); });
    next.addEventListener("click",()=>{ CW_PAGE=(CW_PAGE+1)%cwPages(); renderElList(); }); }
  const light=document.getElementById("cwLight");
  if(light && !light._w){ light._w=1; light.addEventListener("input",()=>{ CW_L=+light.value; buildWheel(); }); }
  renderElList(); buildWheel(); syncColor(); m.classList.add("show"); }
function closeWheel(){ document.getElementById("colormodal").classList.remove("show"); }
applyCustom();

/* ===== setup: keys, pdf manager, version ===== */
function setDot(id,st){ const d=document.getElementById(id); if(!d)return;
  d.classList.remove("ok","bad"); if(st==="ok")d.classList.add("ok"); else if(st==="bad")d.classList.add("bad"); }
function refreshDots(){ setDot("gemDot","unset"); setDot("gmapsDot","unset");
  fetch("key-status",{cache:"no-store"}).then(r=>r.json())
    .then(d=>setDot("gemDot", d.set?(d.working?"ok":"bad"):"unset")).catch(()=>{});
  fetch("gmaps-key",{cache:"no-store"}).then(r=>r.json())
    .then(d=>setDot("gmapsDot",(d&&d.key)?"ok":"unset")).catch(()=>{}); }
const ENGINES=[{k:"osm",n:"OpenStreetMap · free"},{k:"google",n:"Google Maps · key"}];
function renderViewGrid(){
  const es=document.getElementById("engineGrid");
  if (es){
    es.innerHTML=ENGINES.map(e=>'<button class="viewbtn'+(e.k===MAP_ENGINE?' on':'')+'" data-e="'+e.k+'">'+e.n+'</button>').join("");
    es.querySelectorAll(".viewbtn").forEach(b=>b.addEventListener("click",()=>{
      setMapEngine(b.dataset.e); renderViewGrid(); }));
  }
  const g=document.getElementById("viewGrid"); if(!g)return;
  g.innerHTML=BASES[MAP_ENGINE].map(v=>'<button class="viewbtn'+(v.k===baseStyle()?' on':'')+'" data-v="'+v.k+'">'+v.n+'</button>').join("");
  g.querySelectorAll(".viewbtn").forEach(b=>b.addEventListener("click",()=>{
    setBaseStyle(b.dataset.v); renderViewGrid(); }));
}
function readFile(inp){ return new Promise((res,rej)=>{ const f=inp.files&&inp.files[0];
  if(!f)return rej(); const r=new FileReader(); r.onload=()=>res(String(r.result||"").trim());
  r.onerror=rej; r.readAsText(f); }); }
function renderPdfMgr(){ const box=document.getElementById("pdfMgr"); if(!box)return;
  box.innerHTML='<span class="note">Loading…</span>';
  fetch("pdf-list",{cache:"no-store"}).then(r=>r.json()).then(d=>{
    const items=(d&&d.items)||[]; if(!items.length){ box.innerHTML='<span class="note">Nothing cached yet.</span>'; return; }
    box.innerHTML=""; items.forEach(it=>{ const kb=Math.max(1,Math.round((it.bytes||0)/1024));
      const row=document.createElement("div"); row.className="pmrow";
      row.innerHTML='<b>'+it.route+'</b><span class="note">'+kb+' KB · '+(it.parsed?"parsed":"not parsed")+
        '</span><button class="pmdel" data-r="'+it.route+'">Delete</button>';
      row.querySelector(".pmdel").addEventListener("click",async()=>{
        await fetch("pdf-delete?route="+it.route,{cache:"no-store"});
        delete PDFSCHED[it.route]; savePdf(); renderPdfMgr(); if(TAB==="pdf")renderPdf(); });
      box.appendChild(row); }); }).catch(()=>{ box.innerHTML='<span class="note">Could not read cache.</span>'; }); }
function fmtYmd(y){ return (y&&y.length===8)? (y.slice(6,8)+"."+y.slice(4,6)+"."+y.slice(0,4)) : "\u2014"; }
function renderNightSched(){
  const el=document.getElementById("nightSchedInfo"); if(!el) return;
  fetch("night-status",{cache:"no-store"}).then(r=>r.json()).then(s=>{
    if (s.building){ el.innerHTML="Downloading the ZET GTFS feed\u2026"; return; }
    if (s.source==="gtfs"){
      el.innerHTML="Live ZET GTFS \u00b7 feed <b>"+(s.feed_version||"?")+
        "</b> \u00b7 night of <b>"+fmtYmd(s.service_date)+"</b> \u00b7 "+
        (s.stale?"<span style='color:#ffd166'>update available</span>":"up to date");
    } else {
      el.innerHTML="Built-in curated timetable (GTFS not loaded yet).";
    }
  }).catch(()=>{ el.textContent="status unavailable"; });
}
function openSetup(){ refreshDots(); renderPdfMgr(); renderViewGrid(); renderNightSched();
  fetch("version",{cache:"no-store"}).then(r=>r.json())
    .then(v=>{ document.getElementById("verLine").textContent=(v.version||"v9")+" (a) · "+(v.build||""); })
    .catch(()=>{ document.getElementById("verLine").textContent="v9 (a)"; });
  document.getElementById("setupmodal").classList.add("show"); }
function closeSetup(){ document.getElementById("setupmodal").classList.remove("show"); }

/* ===== wire up ===== */
document.querySelectorAll(".tab").forEach(t=>t.addEventListener("click",()=>switchTab(t.dataset.tab)));
document.getElementById("gearBtn").addEventListener("click",openSetup);
document.getElementById("setupClose").addEventListener("click",closeSetup);
document.getElementById("mapFs").addEventListener("click",toggleMapFullscreen);
["fullscreenchange","webkitfullscreenchange"].forEach(ev=>
  document.addEventListener(ev,()=>{ setTimeout(()=>{ if(MAP) theEng().resize(); },200); }));
document.getElementById("gmapsFile").addEventListener("change",async(e)=>{
  const msg=document.getElementById("gmapsMsg");
  try{ const key=await readFile(e.target); if(!key){ msg.textContent="Empty file."; return; }
    msg.textContent="Saving…"; await fetch("gmaps-key",{method:"POST",body:key}); e.target.value="";
    setDot("gmapsDot","ok"); msg.textContent="Saved. Reopen the Map tab.";
  }catch(err){ msg.textContent="Could not read the file."; } });
document.getElementById("cwClose").addEventListener("click",()=>{ closeWheel(); switchTab("plan"); });
document.getElementById("openColorFromGear").addEventListener("click",()=>{ closeSetup(); switchTab("plan"); openWheel(); });
document.getElementById("mapSlotA").addEventListener("click",()=>setActiveSlot("A"));
document.getElementById("mapSlotB").addEventListener("click",()=>setActiveSlot("B"));
document.getElementById("resetColors").addEventListener("click",()=>{ CUSTOM={}; saveCustom(); applyCustom();
  syncColor(); if(TAB==="lines")renderLines(); if(TAB==="pdf")renderPdf(); if(TAB==="plan")computeRoute(); });
document.getElementById("fromClear").addEventListener("click",()=>{ document.getElementById("fromInput").value=""; FROM=""; computeRoute(); });
document.getElementById("toClear").addEventListener("click",()=>{ document.getElementById("toInput").value=""; TO=""; computeRoute(); });
document.getElementById("swapBtn").addEventListener("click",()=>{
  const fi=document.getElementById("fromInput"), ti=document.getElementById("toInput");
  const t=fi.value; fi.value=ti.value; ti.value=t; const tf=FROM; FROM=TO; TO=tf; computeRoute(); });
document.getElementById("gemFile").addEventListener("change",async(e)=>{
  const msg=document.getElementById("gemMsg");
  try{ const key=await readFile(e.target); if(!key){ msg.textContent="Empty file."; return; }
    msg.textContent="Saving and testing…"; await fetch("gemini-key",{method:"POST",body:key}); e.target.value="";
    PDFSCHED={}; savePdf();
    const st=await fetch("key-status",{cache:"no-store"}).then(r=>r.json());
    setDot("gemDot",st.working?"ok":"bad");
    msg.textContent=st.working?"Key works. Reading PDFs…":"Saved but not working.";
    if(st.working) fetchPdf(Object.keys(NET.lines)); renderPdfMgr();
  }catch(err){ msg.textContent="Could not read the file."; } });
document.getElementById("gemTest").addEventListener("click",async()=>{
  const msg=document.getElementById("gemMsg"); msg.textContent="Testing…";
  try{ const st=await fetch("key-status",{cache:"no-store"}).then(r=>r.json());
    setDot("gemDot",st.set?(st.working?"ok":"bad"):"unset");
    msg.textContent=!st.set?"No key set.":st.working?"Key works.":"Key not working."; }
  catch(e){ msg.textContent="Test unavailable."; } });
document.getElementById("pdfClearAll").addEventListener("click",async()=>{
  await fetch("pdf-delete?all=1",{cache:"no-store"}); PDFSCHED={}; savePdf(); renderPdfMgr(); if(TAB==="pdf")renderPdf(); });

document.getElementById("nightUpdate").addEventListener("click",async()=>{
  const msg=document.getElementById("nightSchedMsg");
  const btn=document.getElementById("nightUpdate");
  btn.disabled=true; msg.textContent="Downloading from ZET\u2026"; showUpd(true);
  try{
    const r=await fetch("night-rebuild?force=1",{cache:"no-store"}).then(x=>x.json());
    if (r.ok){ window._gtfsLoaded=false; await loadNet(); rerenderAll();
      msg.textContent="Updated."; }
    else { msg.textContent="Update failed: "+(r.reason||"unknown"); }
  }catch(e){ msg.textContent="Update unavailable."; }
  finally{ btn.disabled=false; showUpd(false); renderNightSched(); }
});

/* boot */
function showUpd(on){ const b=document.getElementById("updbar"); if(b) b.classList.toggle("show",!!on); }
function rerenderAll(){
  if (TAB==="lines") renderLines();
  computeRoute();
  if (typeof renderPdf==="function" && TAB==="pdf") renderPdf();
  if (typeof resetMap==="function"){ resetMap(); if (TAB==="map") initMap(); }
}
// The background GTFS build may finish a moment after boot; when it does, swap
// the curated data for the real network + times (and rebuild the map) with no
// user action. While it downloads, the blinking "updating" bar is shown.
async function refreshFromGtfs(){
  try{
    const s=await fetch("night-status",{cache:"no-store"}).then(r=>r.json());
    showUpd(!!(s&&s.building));
    if (s && s.source==="gtfs" && !s.stale){
      if (!window._gtfsLoaded){ await loadNet(); rerenderAll(); }
      showUpd(false); return true;
    }
  }catch(e){}
  return false;
}
(async function(){
  try{ await loadNet(); }catch(e){ document.getElementById("result").innerHTML=
    '<div class="no-route">Could not load the night network data.</div>'; return; }
  wireSearch("fromInput","fromSug","from");
  wireSearch("toInput","toSug","to");
  tick(); setInterval(tick,1000);
  (async()=>{ for(let i=0;i<40;i++){ if(await refreshFromGtfs()) break;
    await new Promise(r=>setTimeout(r,2500)); } showUpd(false); })();
})();

</script>
</body>
</html>
NC_HTML
done_

step "installing night.commute command"
mkdir -p "$BIN" 2>/dev/null || true
cat > "$BIN/night.commute" << 'NC_LAUNCH'
#!/usr/bin/env bash
# night.commute launcher. Always restarts the server so you never get a stale
# page, waits until it has actually written its port, then opens that port.
APPDIR="$HOME/.nightcommute"
PORTFILE="$APPDIR/port"
PY="$(command -v python3 || command -v python)"

[ -f "$APPDIR/night_server.py" ] || {
  echo "night.commute is not installed. Run the installer first."; exit 1; }

# 1. stop any previously running night server, remove the old port file
pkill -f night_server.py 2>/dev/null || true
rm -f "$PORTFILE" 2>/dev/null || true
sleep 1

# 2. start the fresh server in the background
( cd "$APPDIR" && nohup "$PY" night_server.py >"$APPDIR/server.out" 2>&1 & )

# 3. wait (up to ~8s) until it writes its port, instead of a blind sleep
PORT=""
for i in $(seq 1 40); do
  [ -f "$PORTFILE" ] && PORT="$(cat "$PORTFILE" 2>/dev/null)" && [ -n "$PORT" ] && break
  sleep 0.2
done
[ -n "$PORT" ] || PORT=8087

URL="http://127.0.0.1:$PORT/night.html"
echo "night.commute -> $URL"
command -v termux-open-url >/dev/null 2>&1 && termux-open-url "$URL" || true
command -v xdg-open >/dev/null 2>&1 && xdg-open "$URL" >/dev/null 2>&1 || true
NC_LAUNCH
sed -i 's/\r$//' "$BIN/night.commute" 2>/dev/null || true
chmod +x "$BIN/night.commute"
done_

printf "\n  ${OK}installed  night.commute v9 (a)${OFF}\n"
printf "  type ${KEY}night.commute${OFF} to start it, or ${KEY}commute${OFF} for the family menu\n"
printf "  ${DIM}four night trams, 23:50–04:40, served locally${OFF}\n"
printf "  ${WARN}if the app looks unchanged: close the old browser tab and open the${OFF}\n"
printf "  ${WARN}fresh link, or pull-to-refresh — the old page was cached.${OFF}\n\n"
case ":$PATH:" in *":$BIN:"*) ;; *)
  printf "  ${DIM}Note: add %s to your PATH to use the night.commute command.${OFF}\n\n" "$BIN" ;;
esac
