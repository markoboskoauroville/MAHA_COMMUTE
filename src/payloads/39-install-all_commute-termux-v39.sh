#!/data/data/com.termux/files/usr/bin/bash
# 39-install-all.commute-termux-v39.sh
#
# all.commute v39 -- complete. Carries every payload in full, so it can be run
# over any earlier version, or over a phone with nothing on it, without running
# anything in between.
#
# The map holds nothing but the stations you can walk to, each one a coloured
# star wearing its GTFS stop id on the left and its name on the right. Every
# line has its own colour, the same on every board. The dashboard shows what is
# coming to every station around you, framed in that station's colour, with the
# stop itself in Street View that you can turn all the way round.
#
# Behind it sits the printed timetable: ZET's official vozni red PDF for each
# line, read once, kept as times, the PDF thrown away in the same breath. When
# the GTFS feed breaks or the index is a day behind, those fill the holes.
#
# New in v39: a locate button, and the app now says out loud how well it knows
# where you are. A small readout sits under the status line at all times --
# the accuracy in metres, and whether the fix came from satellites or from wifi
# and cell towers. Tap it for the full picture.
#
# That second part needs Termux:API. The browser is told how accurate its
# position is and nothing else; Android knows which provider answered but never
# passes it on. With Termux:API installed the app asks Android directly and
# gives you a straight answer, and can show how far the satellite fix and the
# network fix disagree. Without it, the app says "likely" and means it.
#
# Satellite count is in neither. It lives in GnssStatus, a native Android API
# that Termux:API does not wrap, so the panel says "not available" rather than
# showing a number nobody can actually read.
#
# From v38: the position ring is a fixed 22 px and hollow, and position is
# gathered in bursts and weighted, not taken from a single reading.
#
# The station index, both keys and the stored timetables all stay where they are.
#
# This replaces the interface only. The server, the station index, the Google
# key and the Gemini key are all left exactly where they are.
#
#   bash 39-install-all.commute-termux-v39.sh            Enter = interface only
#   bash 39-install-all.commute-termux-v39.sh --online   also refresh the station cache
#   bash 39-install-all.commute-termux-v39.sh --offline  interface only

set -e
ALLC_UI_VERSION="v39"
BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
APPDIR="$HOME/.all.commute"

MODE=""
for a in "$@"; do
  case "$a" in
    --online|--full|--deps) MODE="online" ;;
    --offline) MODE="offline" ;;
    -h|--help) printf "usage: bash 39-install-all.commute-termux-v39.sh [--online] [--offline]\n"; exit 0 ;;
  esac
done

if [ -t 1 ]; then
  A="\033[1;36m"; OK="\033[1;32m"; BAD="\033[1;31m"; WARN="\033[1;33m"
  KEY="\033[1;37m"; DIM="\033[0;90m"; OFF="\033[0m"
else
  A=""; OK=""; BAD=""; WARN=""; KEY=""; DIM=""; OFF=""
fi
type_line() { local s="$1"; local i
  for ((i=0; i<${#s}; i++)); do printf "%s" "${s:$i:1}"; sleep 0.004; done; printf "\n"; }
step() { printf "  ${A}>${OFF} %s" "$1"; local i; for i in 1 2 3; do printf "."; sleep 0.08; done; }
done_() { printf " ${OK}ok${OFF}\n"; }
skip_() { printf " ${DIM}skipped${OFF}\n"; }

clear 2>/dev/null
printf "\n"
printf "  ${A}|${OFF} "; type_line "$(printf '%bALL.COMMUTE%b  stars %s' "$KEY" "$OFF" "$ALLC_UI_VERSION")"
printf "  ${A}|${OFF} ${DIM}Water | show me where I am, and tell me how well you know${OFF}\n\n"

# ---------------------------------------------------------------------------
# What has to be here before anything is written. Green all the way down means
# Enter is enough.
# ---------------------------------------------------------------------------
MISSING=0
row() {  # row <name> <ok?> <note-when-missing>
  local name="$1" good="$2" note="$3"
  printf "    %-26s" "$name"
  if [ "$good" = "1" ]; then printf "${OK}ok${OFF}\n"
  else printf "${BAD}missing${OFF}"; [ -n "$note" ] && printf " ${DIM}%s${OFF}" "$note"; printf "\n"
       MISSING=$((MISSING + 1)); fi
}
opt_row() {  # same, but a miss is not fatal
  local name="$1" good="$2" note="$3"
  printf "    %-26s" "$name"
  if [ "$good" = "1" ]; then printf "${OK}ok${OFF}\n"
  else printf "${WARN}missing${OFF}"; [ -n "$note" ] && printf " ${DIM}%s${OFF}" "$note"; printf "\n"; fi
}

printf "  ${KEY}dependencies${OFF}\n"
[ -n "${PREFIX:-}" ] && [ -d "$BIN" ] && T=1 || T=0
row "Termux"                "$T" "run this inside Termux"
command -v python >/dev/null 2>&1 && P=1 || P=0
row "python"                "$P" "run with --online to install it"
command -v base64 >/dev/null 2>&1 && B=1 || B=0
opt_row "base64"            "$B" "only for the home-screen icon"
command -v fuser >/dev/null 2>&1 && F=1 || F=0
opt_row "fuser"             "$F" "pkg install psmisc, frees stuck ports"
[ -f "$APPDIR/network.db" ] && D=1 || D=0
opt_row "station index"     "$D" "built on first run"
[ -f "$APPDIR/google-api.txt" ] && G=1 || G=0
opt_row "google key"        "$G" "photos, 360 view, detailed map"
[ -f "$APPDIR/gemini-api.txt" ] && M=1 || M=0
opt_row "gemini key"        "$M" "reads the printed timetable PDFs"
command -v termux-notification >/dev/null 2>&1 && N=1 || N=0
opt_row "Termux:API"        "$N" "optional, for notifications"
printf "\n"

if [ "$MISSING" -gt 0 ]; then
  printf "  ${BAD}%d required item(s) missing.${OFF} ${DIM}Fix those and run this again.${OFF}\n\n" "$MISSING"
  exit 1
fi

if [ -z "$MODE" ]; then
  printf "  install mode:\n"
  printf "    ${KEY}Enter${OFF}  ${DIM}interface only, nothing downloaded (fast)${OFF}\n"
  printf "    ${KEY}y${OFF}      ${DIM}also refresh the station cache from ZET${OFF}\n"
  printf "\n  ${A}>${OFF} "
  IFS= read -r ANS || ANS=""
  case "$ANS" in [yY]*) MODE="online" ;; *) MODE="offline" ;; esac
fi
printf "  ${DIM}mode: %s${OFF}\n\n" "$MODE"

step "stopping the commute server"
for sig in TERM TERM KILL; do
  pkill -$sig -f all_commute_server.py >/dev/null 2>&1 || true
  sleep 0.25
done
done_

step "making room"
mkdir -p "$APPDIR" "$BIN"
done_

step "keeping a copy of the old app"
for f in all.html all_commute_server.py update_all.py; do
  [ -f "$APPDIR/$f" ] && cp "$APPDIR/$f" "$APPDIR/$f.prev.bak"
done
printf " ${DIM}(.prev.bak)${OFF}"
done_

step "installing the server"
cat > "$APPDIR/all_commute_server.py" << 'ALLC_SERVER_PY'
#!/usr/bin/env python3
"""
all_commute_server.py — local server for all.commute.

One job: tell you what is coming to the stop you are standing at, anywhere on
the ZET network. Static GTFS gives the printed schedule (SQLite index built by
update_all.py), GTFS-realtime gives the live times, and the two are merged so
a vehicle the feed knows about carries a wifi mark and a real delay.

Endpoints
  /all.html           the app
  /stops?lat&lon&r    stops inside a radius, nearest first
  /board?stop=&mins=  departures at one stop in the next N minutes
  /api-keys           read / write the Google Maps key
  /rebuild            rebuild the station index
  /status             index + live feed health
"""
import os
import json
import struct
import time
import math
import sqlite3
import datetime
import subprocess
import threading
import socket
import socketserver
import sys
import urllib.error
import urllib.parse
import urllib.request
import http.server

APP_VERSION = "v39"
APP_BUILD = "b39"

APPDIR = os.environ.get("ALLC_DIR", os.path.expanduser("~/.all.commute"))
START_PORT = int(os.environ.get("ALLC_PORT", "8084"))
PORT_TRIES = 40
DB_PATH = os.path.join(APPDIR, "network.db")
PORTFILE = os.path.join(APPDIR, "port")
LOGFILE = os.path.join(APPDIR, "server.log")
KEYFILE = os.path.join(APPDIR, "google-api.txt")
GEMINI_KEYFILE = os.path.join(APPDIR, "gemini-api.txt")
UPDATER = os.path.join(APPDIR, "update_all.py")
GTFS_RT_URL = "https://zet.hr/gtfs-rt-protobuf"

ALLOWED_FILES = {"all.html", "favicon.ico"}
CONTENT_TYPES = {".html": "text/html; charset=utf-8",
                 ".json": "application/json; charset=utf-8",
                 ".ico": "image/x-icon"}


def _log(line):
    try:
        os.makedirs(APPDIR, exist_ok=True)
        with open(LOGFILE, "a", encoding="utf-8") as f:
            f.write(str(line).rstrip() + "\n")
    except Exception:
        pass


def read_keys():
    try:
        with open(KEYFILE, encoding="utf-8") as f:
            return [ln.strip() for ln in f if ln.strip()]
    except OSError:
        return []


def write_keys(keys):
    os.makedirs(APPDIR, exist_ok=True)
    with open(KEYFILE, "w", encoding="utf-8") as f:
        f.write("\n".join(keys) + ("\n" if keys else ""))


def read_gemini_key():
    try:
        with open(GEMINI_KEYFILE, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def write_gemini_key(k):
    os.makedirs(APPDIR, exist_ok=True)
    with open(GEMINI_KEYFILE, "w", encoding="utf-8") as f:
        f.write((k or "").strip() + "\n")


# ---------------------------------------------------------------------------
# ZET info: pull the public notice pages (works, diversions, line changes) and,
# when a Google AI Studio key is present, have Gemini reorganise them into a
# short, clear summary. Keys are accepted in whatever format the user pastes;
# the current AI Studio keys are long strings, so no old-style pattern is
# enforced.
# ---------------------------------------------------------------------------
ZET_SOURCES = [
    ("Izmjene u prometu", "https://www.zet.hr/aktualnosti/izmjene-u-prometu/31"),
    ("SADA ZGH - ZET status", "https://www.zgh.hr/sada-zgh", [
        "https://www.zgh.hr/sada-zgh",
        "https://www.zgh.hr/sada", "https://www.zgh.hr/sadazgh",
        "https://www.zgh.hr/zet-status", "https://www.zgh.hr/statusi",
        "http://sada.zgh.hr/", "https://holdingcentar.zgh.hr/",
    ]),
]
DEFAULT_GEMINI_MODEL = "gemini-2.5-flash"
_zet_cache = {"t": 0.0, "items": None}


def _news_candidates(page_url):
    """ZET's notice pages are server-rendered HTML, so the page URL itself is
    the source. (Kept as a list so the fetch logic can stay unchanged.)"""
    return [page_url]


def _fetch_text(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (all-commute)",
                                               "Accept": "application/json, text/html, */*"})
    with urllib.request.urlopen(req, timeout=15) as r:
        ctype = (r.headers.get("Content-Type") or "").lower()
        raw = r.read().decode("utf-8", "replace")
    if "json" in ctype or raw.lstrip()[:1] in "[{":
        try:
            return json.dumps(json.loads(raw), ensure_ascii=False, indent=2)
        except Exception:
            return raw
    return _strip_html(raw)


def _strip_html(html):
    import re
    html = re.sub(r"(?is)<script.*?</script>", " ", html)
    html = re.sub(r"(?is)<style.*?</style>", " ", html)
    html = re.sub(r"(?is)<br\s*/?>", "\n", html)
    html = re.sub(r"(?is)</(p|div|li|h[1-6]|tr)>", "\n", html)
    text = re.sub(r"(?s)<[^>]+>", " ", html)
    import html as _h
    text = _h.unescape(text)
    lines = [ln.strip() for ln in text.splitlines()]
    out, blank = [], 0
    for ln in lines:
        if not ln:
            blank += 1
            if blank <= 1 and out:
                out.append("")
            continue
        blank = 0
        out.append(" ".join(ln.split()))
    return "\n".join(out).strip()


def _zet_article_links(page_url, html):
    import re
    base = urllib.parse.urlsplit(page_url)
    root = base.scheme + "://" + base.netloc
    links = []
    for m in re.finditer(r'href="([^"]+)"', html):
        href = m.group(1)
        if "/aktualnosti/" in href and not href.rstrip("/").endswith(("izmjene-u-prometu/31", "/aktualnosti")):
            full = href if href.startswith("http") else root + href
            if full not in links:
                links.append(full)
    return links[:6]


def fetch_zet_notices(force=False):
    now = time.time()
    if not force and _zet_cache["items"] is not None and now - _zet_cache["t"] < 900:
        return _zet_cache["items"]
    items = []
    for entry in ZET_SOURCES:
        name, url = entry[0], entry[1]
        candidates = entry[2] if len(entry) > 2 else [url]
        best_text, best_from, err = "", url, None
        for cand in candidates:
            try:
                req = urllib.request.Request(cand, headers={"User-Agent": "Mozilla/5.0 (all-commute)"})
                with urllib.request.urlopen(req, timeout=18) as r:
                    raw = r.read().decode("utf-8", "replace")
                text = _strip_html(raw)
                for link in _zet_article_links(cand, raw):
                    try:
                        art = _fetch_text(link)
                        if len(art) > 150:
                            text += "\n\n--- " + link + " ---\n" + art[:2500]
                    except Exception:
                        pass
                    if len(text) > 9000:
                        break
                if len(text.strip()) > len(best_text.strip()):
                    best_text, best_from = text, cand
                if len(best_text.strip()) >= 400:
                    break
            except Exception as e:
                err = repr(e)
        if len(best_text) > 9000:
            best_text = best_text[:9000]
        ok = len(best_text.strip()) >= 200
        items.append({"source": name, "url": best_from, "from": best_from, "text": best_text,
                      "ok": ok, "error": None if ok else (err or "no text read")})
    _zet_cache.update(t=now, items=items)
    return items


def gemini_summarize(notices, key, model=None):
    joined = "\n\n".join("### %s (%s)\n%s" % (n["source"], n["url"], n["text"])
                          for n in notices if n.get("ok") and n.get("text"))
    if not joined.strip():
        return {"ok": False, "reason": "no notice text could be read from ZET"}
    prompt = (
        "You are a Zagreb public transport assistant. Below is raw text scraped "
        "from ZET's official notice pages (in Croatian) about public works, "
        "diversions, line changes and service disruptions. Reorganise it into a "
        "clear, well-structured briefing in Croatian. Group by line number where "
        "possible. For each item give: the affected lines, what is changing, and "
        "the dates if present. Be concise, drop menus and navigation text, and "
        "put the most operationally important disruptions first. Use short "
        "headings and bullet points.\n\nRAW NOTICES:\n" + joined)
    body = json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode()
    model = (model or DEFAULT_GEMINI_MODEL).replace("models/", "")
    url = ("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s"
           % (urllib.parse.quote(model), urllib.parse.quote(key)))
    try:
        req = urllib.request.Request(url, data=body, method="POST",
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.loads(r.read().decode("utf-8", "replace"))
        cands = data.get("candidates") or []
        if not cands:
            return {"ok": False, "reason": "the model returned no text",
                    "detail": json.dumps(data)[:400]}
        parts = cands[0].get("content", {}).get("parts", [])
        text = "".join(p.get("text", "") for p in parts).strip()
        return {"ok": bool(text), "text": text, "model": model}
    except urllib.error.HTTPError as he:
        detail = ""
        try:
            detail = he.read().decode("utf-8", "replace")[:400]
        except Exception:
            pass
        return {"ok": False, "reason": "Gemini HTTP %d" % he.code, "detail": detail}
    except Exception as e:
        return {"ok": False, "reason": repr(e)}


# ---------------------------------------------------------------------------
# GTFS-realtime: a tiny protobuf reader, no dependencies. Same shape as the
# one in day.commute, only here we index the updates by stop instead of by trip.
# ---------------------------------------------------------------------------
def _varint(b, i):
    shift = 0
    out = 0
    while True:
        byte = b[i]
        i += 1
        out |= (byte & 0x7F) << shift
        if not byte & 0x80:
            break
        shift += 7
    return out, i


def _fields(b, start, end):
    i = start
    while i < end:
        tag, i = _varint(b, i)
        fn, wt = tag >> 3, tag & 7
        if wt == 0:
            v, i = _varint(b, i)
            yield fn, 0, v
        elif wt == 2:
            ln, i = _varint(b, i)
            yield fn, 2, (i, i + ln)
            i += ln
        elif wt == 1:
            yield fn, 1, (i, i + 8)
            i += 8
        elif wt == 5:
            yield fn, 5, (i, i + 4)
            i += 4
        else:
            raise ValueError("bad wire type %d" % wt)


def _signed(v):
    return v - (1 << 64) if v >= (1 << 63) else v


def _event(b, s, e):
    delay = t = None
    for fn, wt, v in _fields(b, s, e):
        if fn == 1 and wt == 0:
            delay = _signed(v)
        elif fn == 2 and wt == 0:
            t = v
    return t, delay


def _stu(b, s, e):
    seq = stop_id = t = delay = None
    for fn, wt, v in _fields(b, s, e):
        if fn == 1 and wt == 0:
            seq = v
        elif fn == 4 and wt == 2:
            stop_id = b[v[0]:v[1]].decode("utf-8", "replace")
        elif fn == 3 and wt == 2:
            t, delay = _event(b, v[0], v[1])
        elif fn == 2 and wt == 2 and t is None:
            t, delay = _event(b, v[0], v[1])
    return seq, stop_id, t, delay


def _trip_update(b, s, e):
    trip_id = None
    stus = []
    for fn, wt, v in _fields(b, s, e):
        if fn == 1 and wt == 2:
            for f2, w2, v2 in _fields(b, v[0], v[1]):
                if f2 == 1 and w2 == 2:
                    trip_id = b[v2[0]:v2[1]].decode("utf-8", "replace")
        elif fn == 2 and wt == 2:
            stus.append(_stu(b, v[0], v[1]))
    return trip_id, stus


def rt_updates_for(buf, want):
    out = {}
    n = 0
    for fn, wt, v in _fields(buf, 0, len(buf)):
        if fn == 2 and wt == 2:
            for f2, w2, v2 in _fields(buf, v[0], v[1]):
                if f2 == 3 and w2 == 2:
                    n += 1
                    tid, stus = _trip_update(buf, v2[0], v2[1])
                    if tid in want:
                        out[tid] = stus
    return out, n


def _f32(b, s, e):
    return struct.unpack("<f", bytes(b[s:e]))[0]


def _f64(b, s, e):
    return struct.unpack("<d", bytes(b[s:e]))[0]


def _position(b, s, e):
    lat = lon = brg = None
    for fn, wt, v in _fields(b, s, e):
        if fn == 1:
            lat = _f32(b, v[0], v[1]) if wt == 5 else (_f64(b, v[0], v[1]) if wt == 1 else lat)
        elif fn == 2:
            lon = _f32(b, v[0], v[1]) if wt == 5 else (_f64(b, v[0], v[1]) if wt == 1 else lon)
        elif fn == 3:
            brg = _f32(b, v[0], v[1]) if wt == 5 else (_f64(b, v[0], v[1]) if wt == 1 else brg)
    return lat, lon, brg


def _trip_desc(b, s, e):
    tid = rid = None
    for fn, wt, v in _fields(b, s, e):
        if fn == 1 and wt == 2:
            tid = b[v[0]:v[1]].decode("utf-8", "replace")
        elif fn == 5 and wt == 2:
            rid = b[v[0]:v[1]].decode("utf-8", "replace")
    return tid, rid


def _vehicle(b, s, e):
    lat = lon = brg = tid = rid = None
    for fn, wt, v in _fields(b, s, e):
        if fn == 1 and wt == 2:
            tid, rid = _trip_desc(b, v[0], v[1])
        elif fn == 2 and wt == 2:
            lat, lon, brg = _position(b, v[0], v[1])
    return lat, lon, brg, tid, rid


def rt_vehicles(buf):
    """Every VehiclePosition in the feed: where it is, which way it points,
    and which trip and route it is running."""
    out = []
    for fn, wt, v in _fields(buf, 0, len(buf)):
        if fn == 2 and wt == 2:
            for f2, w2, v2 in _fields(buf, v[0], v[1]):
                if f2 == 4 and w2 == 2:
                    lat, lon, brg, tid, rid = _vehicle(buf, v2[0], v2[1])
                    if lat is not None and lon is not None:
                        out.append((lat, lon, brg, tid, rid))
    return out


def trips_meta_for(con, ids):
    if not ids:
        return {}
    qm = ",".join("?" * len(ids))
    out = {}
    for r in con.execute("select trip_id, route, head, origin, dest from trips"
                         " where trip_id in (%s)" % qm, tuple(ids)):
        out[r["trip_id"] if hasattr(r, "keys") else r[0]] = r
    return out


def trip_delay_from(stus):
    """One representative delay for a trip. ZET usually propagates a single
    figure across its stop_time_updates, so the first real number will do."""
    if not stus:
        return None
    for seq, sid, t, dl in stus:
        if dl is not None:
            return dl
    return None


def synth_vehicles(clat, clon, radius, buf):
    """Where every nearby trip *should* be right now.

    The feed carries arrival predictions, not positions, so we rebuild the
    positions ourselves: take each trip's timetabled stops, shift its clock by
    the live delay, find the two stops it is currently between, and slide it
    along that leg by how far through the leg its time has run. Straight lines
    between stops, which is approximate, but it puts a moving triangle on the
    road where the tram actually is."""
    con = db()
    R = max(radius, 900.0)
    nearby = stops_near_radius(clat, clon, R, limit=70)
    if not nearby:
        con.close()
        return []
    ids = [s["stop_id"] for s in nearby]
    now = time.time()
    mid = midnight_epoch()
    now_s = int(now - mid)
    lo, hi = now_s - 5400, now_s + 5400
    qm = ",".join("?" * len(ids))
    trips = set()
    for band in (0, 86400):
        for r in con.execute(
                "select distinct trip_id from dep where stop_id in (%s)"
                " and t between ? and ?" % qm, (*ids, lo + band, hi + band)):
            trips.add(r[0])
        if len(trips) > 500:
            break
    trips = list(trips)[:500]

    try:
        live, _ = rt_updates_for(buf, set(trips))
    except Exception:
        live = {}

    out = []
    for tid in trips:
        seq = con.execute(
            "select d.t as t, d.route as route, s.lat as lat, s.lon as lon"
            " from dep d join stops s on s.stop_id = d.stop_id"
            " where d.trip_id = ? order by d.t", (tid,)).fetchall()
        if len(seq) < 2:
            continue
        t0, tN = seq[0]["t"], seq[-1]["t"]
        dl = trip_delay_from(live.get(tid))
        has_live = dl is not None
        te = now_s - (dl or 0)
        teN = None
        for c in (te, te + 86400, te - 86400):
            if t0 <= c <= tN:
                teN = c
                break
        if teN is None:
            continue
        placed = None
        for i in range(len(seq) - 1):
            ta, tb = seq[i]["t"], seq[i + 1]["t"]
            if ta <= teN <= tb and tb > ta:
                f = (teN - ta) / (tb - ta)
                la, lo_ = seq[i]["lat"], seq[i]["lon"]
                lb, lob = seq[i + 1]["lat"], seq[i + 1]["lon"]
                placed = (la + (lb - la) * f, lo_ + (lob - lo_) * f,
                          bearing(la, lo_, lb, lob))
                break
        if not placed:
            continue
        d = hav(clat, clon, placed[0], placed[1])
        if d > radius:
            continue
        out.append({"lat": round(placed[0], 6), "lon": round(placed[1], 6),
                    "bearing": round(placed[2], 1), "route": seq[0]["route"],
                    "trip": tid, "dist": round(d),
                    "src": "live" if has_live else "sched"})
    meta = trips_meta_for(con, [v["trip"] for v in out])
    for v in out:
        m = meta.get(v["trip"])
        if m is not None:
            v["head"] = m["head"]; v["origin"] = m["origin"]
    con.close()
    out.sort(key=lambda x: x["dist"])
    return out[:250]


_route_cache = {"t": 0.0, "map": {}}


def route_short_map():
    now = time.time()
    if _route_cache["map"] and now - _route_cache["t"] < 300:
        return _route_cache["map"]
    m = {}
    try:
        con = db()
        for rid, short in con.execute("select route_id, short from routes"):
            m[rid] = short
        con.close()
    except Exception:
        pass
    _route_cache.update(t=now, map=m)
    return m


_rt_cache = {"t": 0.0, "data": None}


def fetch_rt():
    now = time.time()
    if _rt_cache["data"] is not None and now - _rt_cache["t"] < 8:
        return _rt_cache["data"]
    req = urllib.request.Request(GTFS_RT_URL, headers={"User-Agent": "all-commute/1"})
    with urllib.request.urlopen(req, timeout=12) as r:
        data = r.read()
    _rt_cache.update(t=now, data=data)
    return data


# ---------------------------------------------------------------------------
# The station index
# ---------------------------------------------------------------------------
BUILD_STATE = {"state": "idle", "reason": ""}


def index_ready():
    """sqlite3.connect happily creates an empty file, so the file existing
    proves nothing. Ask the tables instead."""
    if not os.path.isfile(DB_PATH):
        return False
    try:
        con = sqlite3.connect(DB_PATH, timeout=5)
        n = con.execute("select count(*) from stops").fetchone()[0]
        con.close()
        return n > 0
    except Exception:
        return False


def not_ready():
    st = BUILD_STATE["state"]
    if st == "building":
        return "the station index is building"
    if st == "failed":
        return "the index build failed: " + BUILD_STATE["reason"]
    return "no station index yet"


def db():
    con = sqlite3.connect(DB_PATH, timeout=5)
    con.row_factory = sqlite3.Row
    return con


def bearing(a_lat, a_lon, b_lat, b_lon):
    p = math.pi / 180
    dl = (b_lon - a_lon) * p
    y = math.sin(dl) * math.cos(b_lat * p)
    x = (math.cos(a_lat * p) * math.sin(b_lat * p) -
         math.sin(a_lat * p) * math.cos(b_lat * p) * math.cos(dl))
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


def hav(a_lat, a_lon, b_lat, b_lon):
    R = 6371000.0
    p = math.pi / 180
    dla = (b_lat - a_lat) * p
    dlo = (b_lon - a_lon) * p
    h = (math.sin(dla / 2) ** 2 +
         math.cos(a_lat * p) * math.cos(b_lat * p) * math.sin(dlo / 2) ** 2)
    return 2 * R * math.asin(math.sqrt(h))


def stops_near_radius(lat, lon, radius_m, limit=60):
    dlat = radius_m / 111320.0
    dlon = radius_m / (111320.0 * max(math.cos(lat * math.pi / 180), 0.2))
    con = db()
    rows = con.execute(
        "select stop_id, name, lat, lon, bearing from stops"
        " where lat between ? and ? and lon between ? and ?",
        (lat - dlat, lat + dlat, lon - dlon, lon + dlon)).fetchall()
    con.close()
    out = []
    for r in rows:
        d = hav(lat, lon, r["lat"], r["lon"])
        if d <= radius_m:
            out.append({"stop_id": r["stop_id"], "name": r["name"],
                        "lat": r["lat"], "lon": r["lon"], "dist": round(d),
                        "bearing": (round(r["bearing"], 1)
                                    if r["bearing"] is not None else None)})
    out.sort(key=lambda x: x["dist"])
    return out[:limit]


def stops_near(lat, lon, radius_m, limit=60, want_min=6):
    """Widen the net until a useful handful is caught, not just the single
    nearest one. On the edge of the network that may mean reaching a couple of
    kilometres, which is fine; better a real list than one lonely stop."""
    found, used = [], int(radius_m)
    for r in (radius_m, radius_m * 2, radius_m * 4, 1500.0, 2500.0, 4000.0, 6000.0):
        if r < radius_m:
            continue
        used = int(r)
        found = stops_near_radius(lat, lon, r, limit)
        if len(found) >= want_min:
            break
    return found, used


def midnight_epoch():
    return int(datetime.datetime.now().replace(
        hour=0, minute=0, second=0, microsecond=0).timestamp())


def hhmm(t):
    t %= 86400
    return "%02d:%02d" % (t // 3600, (t % 3600) // 60)


# ---------------------------------------------------------------------------
# Printed timetables.
#
# ZET publishes the official vozni red of every line as a PDF. When the GTFS
# feed breaks -- and it does -- those PDFs are the only schedule left, and once
# they are on the phone they need no network at all.
#
# We keep the times, never the PDF. Each PDF is fetched, read once, and thrown
# away in the same breath; what stays behind is a small JSON file per line in
# ~/.all.commute/schedules. Refetching is one tap and starts over from ZET.
#
# The tram PDFs are not named after their line -- 2 is "2LJV.pdf", 7 is
# "7LJS.pdf", 13 is "13 ne vozi.pdf" -- so the address of each one is scraped
# from ZET's own line pages and cached. Buses do follow their number.
# ---------------------------------------------------------------------------
import base64
import hashlib
import re
import unicodedata
import zlib as _zlib

SCHED_DIR = os.path.join(APPDIR, "schedules")
LINKS_FILE = os.path.join(SCHED_DIR, "_links.json")
LINKS_TTL = 7 * 86400
ZET_BUS_PDF = ("https://www.zet.hr/UserDocsImages/"
               "Autobusne%20linije%20-%20rasporedi/{r}.pdf")
ZET_LINE_PAGES = [
    "https://www.zet.hr/tramvajski-prijevoz/dnevne-linije/249",
    "https://www.zet.hr/tramvajski-prijevoz/nocne-linije/250",
    "https://www.zet.hr/autobusni-prijevoz/nocne-linije/252",
]
SCHED_MODELS = ["gemini-2.5-flash", "gemini-2.0-flash"]
GEMINI_MODEL_FILE = os.path.join(APPDIR, "gemini-model.txt")
GEMINI_LIST_FILE = os.path.join(APPDIR, "gemini-models.json")


def read_model():
    """The model the user picked for reading timetable PDFs."""
    try:
        with open(GEMINI_MODEL_FILE, encoding="utf-8") as f:
            return f.read().strip().replace("models/", "")
    except OSError:
        return ""


def write_model(m):
    """Only a name that could plausibly be a model, and once we know what this
    key can actually call, only one of those. An empty string clears the choice
    and hands the job back to the built-in order."""
    m = re.sub(r"[^0-9A-Za-z._-]", "", (m or "").replace("models/", "").strip())[:80]
    if m:
        known = read_model_list().get("models") or []
        if known:
            if m not in known:
                return None
        elif not re.match(r"^(gemini|gemma|learnlm)[0-9a-z.\-]*$", m):
            return None
    os.makedirs(APPDIR, exist_ok=True)
    with open(GEMINI_MODEL_FILE, "w", encoding="utf-8") as f:
        f.write(m + "\n")
    return m


def sched_models():
    """Whatever was picked first, then the built-in order as a safety net."""
    out, seen = [], set()
    for m in [read_model()] + SCHED_MODELS:
        if m and m not in seen:
            seen.add(m)
            out.append(m)
    return out


def read_model_list():
    try:
        with open(GEMINI_LIST_FILE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"models": [], "checked": 0}


def gemini_model_list(force=False):
    """Every model this key can actually call generateContent on."""
    cached = read_model_list()
    if not force and cached.get("models") and time.time() - cached.get("checked", 0) < 86400:
        cached["ok"] = True
        cached["cached"] = True
        return cached
    key = read_gemini_key()
    if not key:
        return {"ok": False, "reason": "no Gemini key set", "models": cached.get("models", [])}
    try:
        u = ("https://generativelanguage.googleapis.com/v1beta/models?key=%s&pageSize=200"
             % urllib.parse.quote(key))
        req = urllib.request.Request(u, headers={"User-Agent": "all-commute"})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read().decode("utf-8", "replace"))
    except Exception as e:
        return {"ok": False, "reason": repr(e), "models": cached.get("models", [])}
    models = []
    for m in data.get("models", []):
        if "generateContent" in (m.get("supportedGenerationMethods") or []):
            n = (m.get("name") or "").replace("models/", "")
            if n:
                models.append(n)
    models = sorted(set(models))
    out = {"models": models, "checked": int(time.time())}
    try:
        with open(GEMINI_LIST_FILE, "w", encoding="utf-8") as f:
            json.dump(out, f)
    except Exception:
        pass
    out["ok"] = True
    return out


def gemini_test():
    """A one-token question, to prove the key and the chosen model work."""
    key = read_gemini_key()
    if not key:
        return {"ok": False, "reason": "no Gemini key set"}
    body = json.dumps({
        "contents": [{"parts": [{"text": "Reply with the single word: ready"}]}],
        "generationConfig": {"temperature": 0, "maxOutputTokens": 8},
    }).encode()
    last = ""
    for model in sched_models():
        u = ("https://generativelanguage.googleapis.com/v1beta/models/"
             + urllib.parse.quote(model) + ":generateContent?key="
             + urllib.parse.quote(key))
        t0 = time.time()
        try:
            req = urllib.request.Request(
                u, data=body, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=45) as r:
                out = json.loads(r.read().decode("utf-8", "replace"))
            txt = out["candidates"][0]["content"]["parts"][0]["text"].strip()
            return {"ok": True, "model": model, "ms": int((time.time() - t0) * 1000),
                    "reply": txt[:40], "picked": read_model() or ""}
        except urllib.error.HTTPError as he:
            detail = ""
            try:
                detail = json.loads(he.read().decode("utf-8", "replace"))\
                    .get("error", {}).get("message", "")
            except Exception:
                pass
            last = "HTTP %s %s" % (he.code, detail[:160])
        except Exception as e:
            last = repr(e)
        _log("gemini test %s failed: %s" % (model, last))
    return {"ok": False, "reason": last or "no model answered",
            "tried": sched_models()}


def google_key_test():
    """Street View Static is the one part of the Google key we can prove from
    here. Maps JavaScript can only be proved in the browser, so the front end
    tests that half itself."""
    keys = read_keys()
    if not keys:
        return {"ok": False, "reason": "no Google key set"}
    u = ("https://maps.googleapis.com/maps/api/streetview/metadata"
         "?location=45.8131,15.9775&key=" + urllib.parse.quote(keys[0]))
    try:
        with urllib.request.urlopen(
                urllib.request.Request(u, headers={"User-Agent": "all-commute"}),
                timeout=25) as r:
            d = json.loads(r.read().decode("utf-8", "replace"))
    except Exception as e:
        return {"ok": False, "reason": repr(e)}
    st = d.get("status", "")
    if st in ("OK", "ZERO_RESULTS"):
        return {"ok": True, "streetview": True, "status": st}
    return {"ok": False, "streetview": False, "status": st,
            "reason": d.get("error_message") or st}
DAY_KEYS = ("workday", "saturday", "sunday")
_SCHED_LOCK = threading.Lock()

# Croatian public holidays run the Sunday timetable. The PDFs say so in their
# own footer: "BLAGDANIMA I NERADNIM DANIMA U PRIMJENI JE NEDJELJNI VOZNI RED".
FIXED_HOLIDAYS = {(1, 1), (1, 6), (5, 1), (5, 30), (6, 22), (8, 5),
                  (8, 15), (11, 1), (11, 18), (12, 25), (12, 26)}


def _safe_route(r):
    return re.sub(r"[^0-9A-Za-z]", "", str(r or ""))[:8]


def _sched_path(r):
    return os.path.join(SCHED_DIR, _safe_route(r) + ".json")


def _norm(s):
    """Fold a Croatian place name down to something comparable."""
    s = unicodedata.normalize("NFKD", str(s or ""))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]", " ", s.lower()).strip()


def _name_score(a, b):
    ta, tb = set(_norm(a).split()), set(_norm(b).split())
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / float(len(ta | tb))


def _fetch(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": "all.commute/1"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def link_index(force=False):
    """route -> PDF address, scraped from ZET's own line pages."""
    os.makedirs(SCHED_DIR, exist_ok=True)
    if not force:
        try:
            with open(LINKS_FILE, encoding="utf-8") as f:
                j = json.load(f)
            if time.time() - j.get("built", 0) < LINKS_TTL and j.get("links"):
                return j["links"]
        except Exception:
            pass
    links = {}
    for page in ZET_LINE_PAGES:
        try:
            html_txt = _fetch(page, 25).decode("utf-8", "replace")
        except Exception as e:
            _log("sched: line page %s failed: %r" % (page, e))
            continue
        for href in re.findall(r'UserDocsImages/[^"\'<>\s]*?\.pdf', html_txt, re.I):
            name = urllib.parse.unquote(href.rsplit("/", 1)[-1])
            m = re.match(r"\s*(\d{1,3})", name)
            if not m:
                continue                      # network maps, not a line
            links.setdefault(m.group(1), "https://www.zet.hr/" + href)
    if links:
        try:
            with open(LINKS_FILE, "w", encoding="utf-8") as f:
                json.dump({"built": int(time.time()), "links": links}, f)
        except Exception:
            pass
        _log("sched: link index has %d lines" % len(links))
    return links


def _pdf_url(route):
    r = _safe_route(route)
    got = link_index().get(r)
    if got:
        return got
    return ZET_BUS_PDF.format(r=urllib.parse.quote(r))


def _get_pdf(route):
    """Straight into memory. Nothing lands on disk."""
    url = _pdf_url(route)
    data = _fetch(url, 40)
    if data[:5] != b"%PDF-":
        # the bus guess can land on a 404 page; try the scraped address once
        alt = link_index(force=True).get(_safe_route(route))
        if alt and alt != url:
            data = _fetch(alt, 40)
    if data[:5] != b"%PDF-":
        raise ValueError("no timetable PDF published for line %s" % _safe_route(route))
    return data


_TIME_RX = re.compile(r"\b([0-2]?\d)[:.]([0-5]\d)\b")


def _regex_times(pdf_bytes):
    """The no-key fallback: inflate the content streams and take every HH:MM
    shaped token. It cannot tell weekday from Sunday and it cannot tell the two
    directions apart, so anything built from it is flagged approximate."""
    found = set()
    for m in re.finditer(rb"stream(.*?)endstream", pdf_bytes, re.S):
        raw = m.group(1).strip(b"\r\n")
        for cand in (raw, _try_inflate(raw)):
            if not cand:
                continue
            txt = cand.decode("latin-1", "ignore")
            for t in _TIME_RX.finditer(txt):
                h = int(t.group(1))
                if h <= 27:
                    found.add("%02d:%s" % (h, t.group(2)))
    return _norm_times(found)


def _try_inflate(raw):
    try:
        return _zlib.decompress(raw)
    except Exception:
        return None


def _norm_times(lst):
    out = set()
    for t in (lst or []):
        m = re.match(r"^(\d{1,2}):(\d{2})$", str(t).strip())
        if m and int(m.group(2)) < 60 and int(m.group(1)) <= 27:
            out.add("%02d:%s" % (int(m.group(1)), m.group(2)))
    return sorted(out, key=lambda t: (int(t[:2]), int(t[3:])))


def _gemini_read(route, pdf_bytes, key):
    """One call, one line, once. The PDF carries both directions, each under
    the terminal its times start from, and three day columns."""
    prompt = (
        "This PDF is the official ZET Zagreb timetable (vozni red) for line "
        + _safe_route(route) + ". It lists departures for BOTH directions, each "
        "under the terminal the times start from, in three day columns: "
        "'Radni dan' (workday), 'Subota' (saturday), 'Nedjelja' (sunday). "
        "The times are printed as an hour column with the minutes of that hour "
        "beside it, so 07 followed by 03 10 16 means 07:03, 07:10, 07:16. "
        "Extract EVERY direction separately. Reply with ONLY minified JSON, no "
        "markdown, exactly: "
        '{"name":"line name","directions":[{"terminal":"terminal name",'
        '"towards":"other end of the line",'
        '"workday":["HH:MM"],"saturday":["HH:MM"],"sunday":["HH:MM"]}]} '
        "24-hour times sorted ascending. A missing day column is []. Ignore "
        "letter marks next to individual times. If the line is not running, "
        "return empty arrays."
    )
    body = json.dumps({
        "contents": [{"parts": [
            {"inline_data": {"mime_type": "application/pdf",
                             "data": base64.b64encode(pdf_bytes).decode()}},
            {"text": prompt},
        ]}],
        "generationConfig": {"temperature": 0},
    }).encode()
    last = None
    for model in sched_models():
        url = ("https://generativelanguage.googleapis.com/v1beta/models/"
               + model + ":generateContent?key=" + urllib.parse.quote(key))
        try:
            req = urllib.request.Request(
                url, data=body, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=120) as resp:
                out = json.loads(resp.read().decode("utf-8", "replace"))
            txt = out["candidates"][0]["content"]["parts"][0]["text"].strip().strip("`")
            if txt.lower().startswith("json"):
                txt = txt[4:].strip()
            j = json.loads(txt[txt.find("{"):txt.rfind("}") + 1])
            dirs = []
            for dd in (j.get("directions") or []):
                clean = {"terminal": str(dd.get("terminal") or "")[:60],
                         "towards": str(dd.get("towards") or "")[:60]}
                for k in DAY_KEYS:
                    clean[k] = _norm_times(dd.get(k))
                if any(clean[k] for k in DAY_KEYS):
                    dirs.append(clean)
            if not dirs:
                raise ValueError("no directions came back")
            return {"name": str(j.get("name") or "")[:80], "directions": dirs,
                    "source": "gemini:" + model, "approx": False}
        except Exception as e:
            last = e
            _log("sched: gemini %s line %s failed: %r" % (model, route, e))
    raise RuntimeError("gemini could not read the PDF: %r" % (last,))


def sched_for(route, force=False):
    """The stored timetable for one line, fetching and parsing it if we have
    never seen it. The PDF is deleted the moment it has been read."""
    r = _safe_route(route)
    if not r:
        return {"ok": False, "route": r, "error": "no line given"}
    with _SCHED_LOCK:
        path = _sched_path(r)
        if not force:
            try:
                with open(path, encoding="utf-8") as f:
                    cached = json.load(f)
                if cached.get("directions"):
                    cached["cached"] = True
                    return cached
            except Exception:
                pass
        os.makedirs(SCHED_DIR, exist_ok=True)
        try:
            pdf_bytes = _get_pdf(r)
        except Exception as e:
            return {"ok": False, "route": r, "error": repr(e)}
        digest = hashlib.md5(pdf_bytes).hexdigest()
        parsed, err = None, None
        key = read_gemini_key()
        if key:
            try:
                parsed = _gemini_read(r, pdf_bytes, key)
            except Exception as e:
                err = repr(e)
        if parsed is None:
            times = _regex_times(pdf_bytes)
            parsed = {
                "name": "", "source": "regex-approx", "approx": True,
                "directions": [{"terminal": "", "towards": "",
                                "workday": times, "saturday": times,
                                "sunday": times}],
                "error": err or "no Gemini key; add one in settings for exact times",
            }
        parsed["ok"] = True
        parsed["route"] = r
        parsed["md5"] = digest
        parsed["bytes"] = len(pdf_bytes)
        parsed["fetched"] = int(time.time())
        del pdf_bytes                      # the PDF never touches the disk
        try:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(parsed, f, ensure_ascii=False)
        except Exception as e:
            _log("sched: could not store line %s: %r" % (r, e))
        _log("sched: line %s stored (%s)" % (r, parsed.get("source")))
        return parsed


def sched_read(route):
    """Stored timetable only. Never goes to the network."""
    try:
        with open(_sched_path(route), encoding="utf-8") as f:
            j = json.load(f)
        return j if j.get("directions") else None
    except Exception:
        return None


def sched_list():
    items = []
    try:
        names = sorted(os.listdir(SCHED_DIR))
    except OSError:
        names = []
    for fn in names:
        if not fn.endswith(".json") or fn.startswith("_"):
            continue
        try:
            with open(os.path.join(SCHED_DIR, fn), encoding="utf-8") as f:
                j = json.load(f)
        except Exception:
            continue
        dirs = j.get("directions") or []
        items.append({
            "route": j.get("route", fn[:-5]),
            "name": j.get("name", ""),
            "source": j.get("source", ""),
            "approx": bool(j.get("approx")),
            "fetched": j.get("fetched", 0),
            "directions": [d.get("terminal", "") for d in dirs],
            "times": sum(len(d.get(k) or []) for d in dirs for k in DAY_KEYS),
        })
    items.sort(key=lambda x: (len(x["route"]), x["route"]))
    return {"ok": True, "items": items, "dir": SCHED_DIR}


def sched_delete(route, all_=False):
    removed = []
    try:
        names = os.listdir(SCHED_DIR)
    except OSError:
        names = []
    if all_:
        targets = [n[:-5] for n in names if n.endswith(".json") and not n.startswith("_")]
    else:
        targets = [_safe_route(route)] if route else []
    for r in targets:
        try:
            os.remove(_sched_path(r))
            removed.append(r)
        except OSError:
            pass
    return {"ok": True, "removed": removed}


def day_type(ts=None):
    d = datetime.date.fromtimestamp(ts or time.time())
    if (d.month, d.day) in FIXED_HOLIDAYS:
        return "sunday"
    wd = d.weekday()
    return "sunday" if wd == 6 else ("saturday" if wd == 5 else "workday")


def stop_shape(stop_id, route):
    """What the index knows about this line at this stop: how long after
    leaving each terminal it gets here, and what the sign on the front says.

    The printed PDF gives times at the terminal. This is the bridge from there
    to the pole you are standing at. Route geometry barely changes between
    timetable versions, which is exactly why a stale index is still useful for
    it even when its departure times are wrong."""
    out = {}
    try:
        con = db()
        rows = list(con.execute(
            "select t.origin as origin, t.dest as dest, d.head as head,"
            " d.t - t.start_t as off from dep d join trips t on t.trip_id=d.trip_id"
            " where d.stop_id=? and d.route=? limit 600", (stop_id, route)))
        con.close()
    except Exception:
        return out
    for r in rows:
        off = r["off"]
        if off is None or off < 0 or off > 7200:
            continue
        k = r["origin"] or ""
        e = out.setdefault(k, {"offs": [], "head": r["head"] or "", "dest": r["dest"] or ""})
        e["offs"].append(off)
    for k, e in out.items():
        s = sorted(e["offs"])
        e["off"] = s[len(s) // 2]          # median: immune to one odd short run
        e["n"] = len(s)
        del e["offs"]
    return out


def stop_routes(stop_id):
    try:
        con = db()
        rows = [r["route"] for r in con.execute(
            "select distinct route from dep where stop_id=? limit 40", (stop_id,))]
        con.close()
        return rows
    except Exception:
        return []


def printed_rows(stop_id, now, mid, lo, hi, have):
    """Departures rebuilt from the stored printed timetables.

    For each line at this stop we take today's column from the PDF, add the
    time the index says it takes to get here from that terminal, and keep
    whatever lands inside the window. Anything the live index already knows
    about wins; these only fill the holes."""
    made, used, needs_key = [], [], []
    dk = day_type(now)
    for route in stop_routes(stop_id):
        js = sched_read(route)
        if not js:
            continue
        # An approximate parse is never allowed near the board. Without a
        # Gemini key all we have is every HH:MM shaped token scraped out of the
        # PDF, with no idea which direction or which day it belongs to. A wrong
        # departure time is worse than no departure time, so these are listed
        # in settings and go no further.
        if js.get("approx"):
            needs_key.append(route)
            continue
        shape = stop_shape(stop_id, route)
        if not shape:
            continue
        used.append(route)
        allofs = [e["off"] for e in shape.values()]
        fallback_off = sorted(allofs)[len(allofs) // 2] if allofs else 0
        for d in (js.get("directions") or []):
            term = d.get("terminal") or ""
            best, score = None, 0.0
            for origin, e in shape.items():
                sc = _name_score(term, origin)
                if sc > score:
                    best, score = e, sc
            if best is None or score < 0.34:
                # a direction we cannot place: use the typical run to this stop
                best = {"off": fallback_off, "head": d.get("towards") or "",
                        "dest": d.get("towards") or ""}
            head = best.get("head") or best.get("dest") or d.get("towards") or ""
            off = best.get("off", 0)
            for t in (d.get(dk) or []):
                hh, mm = int(t[:2]), int(t[3:])
                base = hh * 3600 + mm * 60 + off
                for band in (base, base + 86400, base - 86400):
                    if not (lo <= band <= hi):
                        continue
                    at = mid + band
                    if any(x["route"] == route and abs(x["at"] - at) < 180
                           for x in have):
                        continue            # the index already has this one
                    if any(x["route"] == route and abs(x["at"] - at) < 180
                           for x in made):
                        continue
                    secs_out = at - now
                    made.append({
                        "route": route, "head": head, "trip": "",
                        "sched": hhmm(band), "sched_at": at, "at": int(at),
                        "live_at": None, "delay": None, "live": False,
                        "passed": secs_out < -20,
                        "mins": int(round(secs_out / 60.0)),
                        "origin": term or best.get("dest", ""),
                        "printed": True,
                    })
    return made, used, needs_key


def board(stop_id, mins, back=15, fill="auto"):
    """Everything at this stop from `back` minutes ago to `mins` minutes ahead.

    The window looks backwards on purpose. A tram scheduled three minutes ago
    that is running eight minutes late has not gone anywhere, and a tram that
    truly left two minutes ago is worth knowing about, because the next one
    behind it is the one you will actually catch. The printed schedule sets the
    candidates, the live feed decides where each of them really is."""
    now = time.time()
    mid = midnight_epoch()
    now_s = int(now - mid)
    lo, hi = now_s - back * 60, now_s + mins * 60
    con = db()
    st = con.execute("select stop_id, name, lat, lon, bearing from stops where stop_id=?",
                     (stop_id,)).fetchone()
    if st is None:
        con.close()
        return {"ok": False, "reason": "unknown stop"}
    q = ("select t, trip_id, route, head from dep"
         " where stop_id=? and t between ? and ? order by t limit 400")
    rows = list(con.execute(q, (stop_id, lo, hi)))
    # trips that run past midnight are stored as 24:xx and later, so look there too
    rows += list(con.execute(q, (stop_id, lo + 86400, hi + 86400)))
    con.close()

    want = {r["trip_id"] for r in rows}
    live, feed_n, feed_ok, feed_err = {}, 0, False, ""
    try:
        live, feed_n = rt_updates_for(fetch_rt(), want)
        feed_ok = True
    except Exception as e:
        feed_err = repr(e)
        _log("rt failed: %r" % (e,))

    deps = []
    for r in rows:
        sched_abs = mid + r["t"]
        lt = d = None
        stus = live.get(r["trip_id"])
        if stus:
            for seq, sid, t, dl in stus:
                if sid == stop_id:
                    lt, d = t, dl
                    break
            if lt is None and d is None:
                for seq, sid, t, dl in stus:
                    if dl is not None:
                        d = dl
                        break
        if lt is None and d is not None:
            lt = sched_abs + d
        if d is None and lt is not None:
            d = int(lt - sched_abs)
        is_live = stus is not None and (lt is not None or d is not None)
        eta = float(lt) if (is_live and lt) else float(sched_abs)
        secs_out = eta - now
        if secs_out < -back * 60:
            continue                      # gone long enough to be forgotten
        deps.append({
            "route": r["route"], "head": r["head"], "trip": r["trip_id"],
            "sched": hhmm(r["t"]), "sched_at": sched_abs,
            "at": int(eta),
            "live_at": int(lt) if (is_live and lt) else None,
            "delay": int(d) if (is_live and d is not None) else None,
            "live": bool(is_live),
            "passed": secs_out < -20,
            "mins": int(round(secs_out / 60.0)),
        })
    con2 = db()
    origins = {}
    tids = list({d["trip"] for d in deps})
    if tids:
        qm = ",".join("?" * len(tids))
        for r in con2.execute("select trip_id, origin from trips where trip_id in (%s)" % qm, tuple(tids)):
            origins[r["trip_id"]] = r["origin"]
    con2.close()
    for d in deps:
        d["origin"] = origins.get(d["trip"], "")

    # ---- the printed timetables fill whatever the index could not ----
    # Two things send us here: an index built for a different service day, and
    # a stop that came back with nothing at all. Either way the stored PDFs
    # still know what is meant to run today.
    stale, sdate = False, ""
    try:
        c3 = db()
        row = c3.execute("select v from meta where k='service_date'").fetchone()
        c3.close()
        sdate = row["v"] if row else ""
        stale = sdate != datetime.date.fromtimestamp(now).strftime("%Y%m%d")
    except Exception:
        pass
    filled, fill_routes, fill_needs = [], [], []
    if fill == "always" or (fill == "auto" and (stale or not deps)):
        try:
            filled, fill_routes, fill_needs = printed_rows(
                stop_id, now, mid, lo, hi, deps)
        except Exception as e:
            _log("sched: filling %s failed: %r" % (stop_id, e))
    for d in filled:
        if d["at"] - now >= -back * 60:
            deps.append(d)

    deps.sort(key=lambda x: x["at"])
    lines = sorted({d["route"] for d in deps if not d["passed"]})
    return {"ok": True, "now": int(now), "window": mins, "back": back,
            "feed_ok": feed_ok, "feed_trips": feed_n, "feed_error": feed_err,
            "index_stale": bool(stale), "service_date": sdate,
            "printed": len(filled), "printed_lines": fill_routes,
            "printed_needs_key": fill_needs,
            "lines": lines,
            "stop": {"stop_id": st["stop_id"], "name": st["name"],
                     "lat": st["lat"], "lon": st["lon"],
                     "bearing": st["bearing"]},
            "departures": deps}


def clear_index():
    """Wipe the cached station index. The app will report "no station index"
    until it is cached again; the daily bootstrap or the Cache button rebuilds
    it. The Google key and everything else are untouched."""
    removed = []
    for path in (DB_PATH, DB_PATH + ".tmp"):
        try:
            if os.path.isfile(path):
                os.remove(path)
                removed.append(os.path.basename(path))
        except Exception as e:
            return {"ok": False, "reason": repr(e)}
    BUILD_STATE.update(state="idle", reason="")
    _log("station cache cleared: " + (", ".join(removed) or "nothing to remove"))
    return {"ok": True, "removed": removed}


def trip_detail(trip_id):
    """Everything about one ride: its stop sequence with printed and live times,
    the delay, the path it follows, and where it is right now. This is what the
    ride dashboard draws, the same idea as day.commute's live view."""
    con = db()
    seq = con.execute(
        "select d.t as t, d.route as route, d.head as head, d.stop_id as stop_id,"
        " s.name as name, s.lat as lat, s.lon as lon"
        " from dep d join stops s on s.stop_id = d.stop_id"
        " where d.trip_id = ? order by d.t", (trip_id,)).fetchall()
    con.close()
    if not seq:
        return {"ok": False, "reason": "unknown trip"}
    now = time.time()
    mid = midnight_epoch()
    now_s = int(now - mid)
    live, feed_ok = {}, False
    try:
        live, _ = rt_updates_for(fetch_rt(), {trip_id})
        feed_ok = True
    except Exception as e:
        _log("trip rt failed: %r" % (e,))
    stus = live.get(trip_id)
    per = {}
    if stus:
        for sq, sid, t, dl in stus:
            per[sid] = (t, dl)
    overall = trip_delay_from(stus)

    stops = []
    for i, r in enumerate(seq):
        sched_at = mid + r["t"]
        t_abs, dl = per.get(r["stop_id"], (None, None))
        if dl is None:
            dl = overall
        live_at = t_abs if t_abs is not None else (sched_at + dl if dl is not None else None)
        stops.append({"seq": i + 1, "name": r["name"], "stop_id": r["stop_id"],
                      "sched": hhmm(r["t"]), "sched_at": sched_at,
                      "live_at": int(live_at) if live_at else None,
                      "delay": int(dl) if dl is not None else None,
                      "lat": r["lat"], "lon": r["lon"]})

    t0, tN = seq[0]["t"], seq[-1]["t"]
    te = now_s - (overall or 0)
    teN = None
    for c in (te, te + 86400, te - 86400):
        if t0 <= c <= tN:
            teN = c
            break
    pos, next_seq = None, None
    if teN is not None:
        for i in range(len(seq) - 1):
            ta, tb = seq[i]["t"], seq[i + 1]["t"]
            if ta <= teN <= tb and tb > ta:
                f = (teN - ta) / (tb - ta)
                la, lo_ = seq[i]["lat"], seq[i]["lon"]
                lb, lob = seq[i + 1]["lat"], seq[i + 1]["lon"]
                pos = {"lat": round(la + (lb - la) * f, 6),
                       "lon": round(lo_ + (lob - lo_) * f, 6),
                       "bearing": round(bearing(la, lo_, lb, lob), 1)}
                next_seq = i + 2
                break
    return {"ok": True, "now": int(now), "feed_ok": feed_ok,
            "has_live": stus is not None,
            "route": seq[0]["route"], "head": seq[-1]["head"] or seq[0]["head"],
            "delay": (int(overall) if overall is not None else None),
            "trip": trip_id,
            "path": [[r["lat"], r["lon"]] for r in seq],
            "position": pos, "next_seq": next_seq,
            "started": teN is not None and teN >= t0,
            "finished": teN is not None and teN >= tN,
            "stops": stops}


def index_status():
    out = {"ok": index_ready(), "state": BUILD_STATE["state"],
           "state_reason": BUILD_STATE["reason"]}
    if out["ok"]:
        try:
            con = db()
            for k, v in con.execute("select k, v from meta"):
                out[k] = v
            con.close()
        except Exception as e:
            out["ok"] = False
            out["reason"] = repr(e)
    try:
        buf = fetch_rt()
        _, n = rt_updates_for(buf, set())
        out["feed_ok"] = True
        out["feed_trips"] = n
    except Exception as e:
        out["feed_ok"] = False
        out["feed_reason"] = repr(e)
    return out


_rebuild_lock = threading.Lock()


def rebuild(force=False):
    if not _rebuild_lock.acquire(blocking=False):
        return {"ok": False, "reason": "a rebuild is already running"}
    try:
        env = dict(os.environ, ALLC_DIR=APPDIR)
        if force:
            env["ALLC_FORCE"] = "1"
        p = subprocess.run([sys.executable, UPDATER], capture_output=True,
                           text=True, timeout=900, env=env)
        _log(p.stdout[-4000:] + p.stderr[-2000:])
        return {"ok": p.returncode == 0, "log": (p.stdout or "")[-1500:]}
    except Exception as e:
        return {"ok": False, "reason": repr(e)}
    finally:
        _rebuild_lock.release()



# ---------------------------------------------------------------------------
# Where the fix is coming from.
#
# A web page is told how accurate its position is and nothing else -- the
# Geolocation API has no field for satellite count and no field for which
# provider answered. Android knows both; it just never tells the browser.
#
# What we can do from here is ask Android directly through Termux:API.
# termux-location reports the provider that produced each fix, so we can say
# plainly whether you are on satellites or on wifi and cell towers, and how far
# apart the two answers are. Satellite count stays out of reach: it lives in
# GnssStatus, a native Android API that Termux:API does not wrap, so anything
# claiming to show it here would be inventing it.
# ---------------------------------------------------------------------------
def _have_termux_location():
    from shutil import which
    return which("termux-location") is not None


def termux_fix(provider="gps", request="last", timeout=14):
    """One reading from one Android provider. 'last' is whatever is already
    cached and returns at once; 'once' waits for a fresh one."""
    from shutil import which
    exe = which("termux-location")
    if not exe:
        return {"ok": False, "provider": provider, "reason": "Termux:API not installed"}
    try:
        p = subprocess.run([exe, "-p", provider, "-r", request],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"ok": False, "provider": provider, "reason": "no fix within %ds" % timeout}
    except Exception as e:
        return {"ok": False, "provider": provider, "reason": repr(e)}
    raw = (p.stdout or b"").decode("utf-8", "replace").strip()
    if not raw:
        err = (p.stderr or b"").decode("utf-8", "replace").strip()
        return {"ok": False, "provider": provider,
                "reason": err[:160] or "nothing came back"}
    try:
        d = json.loads(raw)
    except Exception:
        return {"ok": False, "provider": provider, "reason": raw[:160]}
    out = {"ok": True, "provider": d.get("provider", provider)}
    for k in ("latitude", "longitude", "altitude", "accuracy",
              "vertical_accuracy", "bearing", "speed", "elapsedMs"):
        if d.get(k) is not None:
            out[k] = d[k]
    return out


def gps_state(fresh=False):
    """Both providers side by side, so the interface can stop guessing."""
    if not _have_termux_location():
        return {"ok": False, "termux": False,
                "reason": "Termux:API is not installed, so Android will not say "
                          "which provider answered",
                "satellites": None}
    req = "once" if fresh else "last"
    sat = termux_fix("gps", req, 20 if fresh else 8)
    net = termux_fix("network", req, 12 if fresh else 6)
    best = None
    if sat.get("ok") and sat.get("accuracy") is not None:
        best = "gps"
    if net.get("ok") and net.get("accuracy") is not None:
        if best is None or net["accuracy"] < sat.get("accuracy", 1e9):
            best = "network"
    gap = None
    if sat.get("ok") and net.get("ok"):
        try:
            gap = int(round(_metres(sat["latitude"], sat["longitude"],
                                    net["latitude"], net["longitude"])))
        except Exception:
            gap = None
    return {"ok": True, "termux": True, "fresh": bool(fresh),
            "gps": sat, "network": net, "better": best, "gap_m": gap,
            "satellites": None,
            "satellites_note": "Android keeps satellite count in GnssStatus, a "
                               "native API Termux:API does not expose. No app "
                               "outside Java can read it, so we do not pretend to."}


def _metres(aLat, aLon, bLat, bLon):
    R, p = 6371000.0, math.pi / 180
    dla, dlo = (bLat - aLat) * p, (bLon - aLon) * p
    h = math.sin(dla / 2) ** 2 + math.cos(aLat * p) * math.cos(bLat * p) * math.sin(dlo / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))

# ---------------------------------------------------------------------------
# Android notification countdown. When the app tells us the chosen ride (and,
# if set, the destination stop), a background thread recomputes the ETA every
# half minute and updates a persistent Termux notification. Needs the
# Termux:API app (termux-notification); without it we simply do nothing.
# ---------------------------------------------------------------------------
NOTIFY = {"trip": None, "dest": None, "route": "", "head": ""}
NOTIFY_ID = "allcommute-ride"
_notify_started = False
_notify_lock = threading.Lock()


def _have_termux_notification():
    from shutil import which
    return which("termux-notification") is not None and which("termux-notification-remove") is not None


def _eta_for(trip, dest):
    try:
        d = trip_detail(trip)
    except Exception:
        return None
    if not d.get("ok"):
        return None
    now = d["now"]
    stops = d["stops"]
    nx = d.get("next_seq") or 1
    target = None
    if dest:
        for s in stops:
            if s["stop_id"] == dest and s["seq"] >= nx:
                target = s
                break
    if target is None:
        target = next((s for s in stops if s["seq"] == nx), None)
    if target is None:
        return {"done": True, "route": d["route"], "head": d["head"], "stop": "", "mins": None}
    at = target["live_at"] or target["sched_at"]
    mins = int(round((at - now) / 60.0))
    return {"done": d.get("finished"), "route": d["route"], "head": d["head"],
            "stop": target["name"], "mins": mins,
            "dest": bool(dest and target["stop_id"] == dest)}


def _notify_loop():
    last = ""
    while True:
        trip = NOTIFY["trip"]
        if not trip:
            time.sleep(2)
            continue
        info = _eta_for(trip, NOTIFY["dest"])
        try:
            if info is None:
                title = "%s \u2192 %s" % (NOTIFY["route"] or "?", NOTIFY["head"] or "?")
                content = "waiting for live data\u2026"
            elif info.get("done") and info.get("mins") is None:
                title = "%s \u2192 %s" % (info["route"], info["head"])
                content = "arrived"
            else:
                m = info["mins"]
                when = "now" if (m is not None and m <= 0) else ("%d min" % m if m is not None else "?")
                arrow = "\u25ce " if info.get("dest") else ""
                title = "%s \u2192 %s \u00b7 %s" % (info["route"], info["head"], when)
                content = "%sto %s" % (arrow, info["stop"] or info["head"])
            key = title + "|" + content
            if key != last and _have_termux_notification():
                subprocess.run(["termux-notification", "--id", NOTIFY_ID,
                                "--title", title, "--content", content,
                                "--ongoing", "--alert-once",
                                "--priority", "low", "--group", "all.commute"],
                               timeout=10)
                last = key
        except Exception as e:
            _log("notify failed: %r" % (e,))
        time.sleep(30)


def start_notify_thread():
    global _notify_started
    with _notify_lock:
        if _notify_started:
            return
        _notify_started = True
        threading.Thread(target=_notify_loop, daemon=True).start()


def clear_notification():
    try:
        if _have_termux_notification():
            subprocess.run(["termux-notification-remove", NOTIFY_ID], timeout=10)
    except Exception:
        pass


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        _log("%s %s" % (self.log_date_time_string(), fmt % args))

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _json(self, payload, code=200):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        route = u.path
        if route in ("/", "/index.html"):
            route = "/all.html"
        try:
            if route == "/stops":
                lat = float(q.get("lat", ["0"])[0])
                lon = float(q.get("lon", ["0"])[0])
                r = min(float(q.get("r", ["350"])[0]), 8000.0)
                widen = q.get("widen", ["1"])[0] != "0"
                if not index_ready():
                    return self._json({"ok": False, "reason": not_ready()})
                found, used = stops_near(lat, lon, r, want_min=(6 if widen else 0))
                return self._json({"ok": True, "radius": used,
                                   "asked": int(r), "widened": used > int(r),
                                   "stops": found})
            if route == "/vehicles":
                lat = float(q.get("lat", ["0"])[0])
                lon = float(q.get("lon", ["0"])[0])
                r = min(float(q.get("r", ["500"])[0]), 8000.0)
                if not index_ready():
                    return self._json({"ok": False, "reason": not_ready(), "vehicles": []})
                try:
                    buf = fetch_rt()
                except Exception as e:
                    return self._json({"ok": False, "reason": repr(e), "vehicles": []})
                rmap = route_short_map()
                real, real_trips = [], set()
                for vlat, vlon, brg, tid, rid in rt_vehicles(buf):
                    if tid:
                        real_trips.add(tid)
                    d = hav(lat, lon, vlat, vlon)
                    if d <= r:
                        real.append({"lat": round(vlat, 6), "lon": round(vlon, 6),
                                     "bearing": (round(brg, 1) if brg is not None else None),
                                     "route": rmap.get(rid, rid or "?"),
                                     "trip": tid, "dist": round(d), "src": "gps"})
                if real:
                    con = db()
                    gm = trips_meta_for(con, [v["trip"] for v in real if v["trip"]])
                    con.close()
                    for v in real:
                        m = gm.get(v["trip"])
                        if m is not None:
                            v["head"] = m["head"]; v["origin"] = m["origin"]
                            if not v.get("route") or v["route"] == "?":
                                v["route"] = m["route"]
                synth = [v for v in synth_vehicles(lat, lon, r, buf)
                         if v["trip"] not in real_trips]
                veh = real + synth
                veh.sort(key=lambda x: x["dist"])
                veh = veh[:250]
                n_gps = sum(1 for v in veh if v["src"] == "gps")
                return self._json({"ok": True, "count": len(veh), "gps": n_gps,
                                   "calc": len(veh) - n_gps, "radius": int(r),
                                   "vehicles": veh})
            if route == "/find-stops":
                term = (q.get("q", [""])[0] or "").strip()
                if not index_ready():
                    return self._json({"ok": False, "reason": not_ready(), "stops": []})
                if len(term) < 2:
                    return self._json({"ok": True, "stops": []})
                con = db()
                rows = con.execute(
                    "select stop_id, name, lat, lon, bearing from stops"
                    " where name like ? or stop_id like ? order by name limit 80",
                    ("%" + term + "%", term + "%")).fetchall()
                con.close()
                have = "lat" in q and "lon" in q
                la = float(q.get("lat", ["0"])[0]); lo = float(q.get("lon", ["0"])[0])
                out = []
                for r in rows:
                    d = round(hav(la, lo, r["lat"], r["lon"])) if have else None
                    out.append({"stop_id": r["stop_id"], "name": r["name"],
                                "lat": r["lat"], "lon": r["lon"],
                                "bearing": (round(r["bearing"], 1) if r["bearing"] is not None else None),
                                "dist": d})
                return self._json({"ok": True, "stops": out})
            if route == "/lines":
                term = (q.get("q", [""])[0] or "").strip().lower()
                if not index_ready():
                    return self._json({"ok": False, "reason": not_ready(), "lines": []})
                con = db()
                rows = con.execute(
                    "select route, count(*) c, max(head) h from trips group by route").fetchall()
                con.close()
                lines = []
                for r in rows:
                    if term and term not in (r["route"] or "").lower() and term not in (r["h"] or "").lower():
                        continue
                    lines.append({"route": r["route"], "trips": r["c"], "sample": r["h"] or ""})

                def rkey(x):
                    s0 = x["route"] or ""
                    num = "".join(ch for ch in s0 if ch.isdigit())
                    return (int(num) if num else 9999, s0)
                lines.sort(key=rkey)
                return self._json({"ok": True, "lines": lines})
            if route == "/line":
                short = q.get("route", [""])[0]
                if not index_ready():
                    return self._json({"ok": False, "reason": not_ready(), "trips": []})
                con = db()
                rows = con.execute(
                    "select trip_id, origin, dest, start_t, end_t from trips"
                    " where route=? order by start_t", (short,)).fetchall()
                con.close()
                trips = [{"trip": r["trip_id"], "origin": r["origin"], "dest": r["dest"],
                          "start": hhmm(r["start_t"]), "end": hhmm(r["end_t"]),
                          "route": short} for r in rows]
                return self._json({"ok": True, "route": short, "count": len(trips), "trips": trips})
            if route == "/trip":
                tid = q.get("trip", [""])[0]
                if not index_ready():
                    return self._json({"ok": False, "reason": not_ready()})
                return self._json(trip_detail(tid))
            if route == "/board":
                sid = q.get("stop", [""])[0]
                mins = max(5, min(int(q.get("mins", ["30"])[0]), 1440))
                back = max(0, min(int(q.get("back", ["15"])[0]), 120))
                if not index_ready():
                    return self._json({"ok": False, "reason": not_ready()})
                fill = q.get("fill", ["auto"])[0]
                if fill not in ("auto", "always", "never"):
                    fill = "auto"
                return self._json(board(sid, mins, back, fill))

            # ---- printed timetables ----
            if route == "/sched":
                force = q.get("force", ["0"])[0] == "1"
                names = [x for x in
                         re.split(r"[,\s]+", q.get("routes", [""])[0]) if x][:14]
                out = {"ok": True, "routes": {}}
                for r in names:
                    out["routes"][_safe_route(r)] = sched_for(r, force)
                return self._json(out)
            if route == "/sched-near":
                lat = float(q.get("lat", ["0"])[0])
                lon = float(q.get("lon", ["0"])[0])
                rad = max(50, min(int(float(q.get("r", ["300"])[0])), 2000))
                force = q.get("force", ["0"])[0] == "1"
                if not index_ready():
                    return self._json({"ok": False, "reason": not_ready()})
                seen = []
                for st in stops_near(lat, lon, rad, limit=12, want_min=0)[0]:
                    for r in stop_routes(st["stop_id"]):
                        if r not in seen:
                            seen.append(r)
                out = {"ok": True, "found": seen, "routes": {}}
                for r in seen[:14]:
                    out["routes"][_safe_route(r)] = sched_for(r, force)
                return self._json(out)
            if route == "/sched-list":
                return self._json(sched_list())
            if route == "/sched-delete":
                return self._json(sched_delete(q.get("route", [""])[0],
                                               q.get("all", ["0"])[0] == "1"))
            if route == "/api-keys":
                return self._json({"keys": read_keys()})
            if route == "/status":
                return self._json(index_status())
            if route == "/rebuild":
                return self._json(rebuild(q.get("force", ["0"])[0] == "1"))
            if route == "/cache/clear":
                return self._json(clear_index())
            if route == "/gemini-key":
                return self._json({"ok": True, "set": bool(read_gemini_key()),
                                   "default_model": DEFAULT_GEMINI_MODEL})
            if route == "/gps":
                return self._json(gps_state(q.get("fresh", ["0"])[0] == "1"))
            if route == "/gemini-test":
                return self._json(gemini_test())
            if route == "/key-test":
                return self._json(google_key_test())
            if route == "/gemini-model":
                lst = read_model_list()
                return self._json({"ok": True, "model": read_model(),
                                   "order": sched_models(),
                                   "models": lst.get("models", []),
                                   "checked": lst.get("checked", 0),
                                   "default": DEFAULT_GEMINI_MODEL})
            if route == "/gemini-models":
                return self._json(gemini_model_list(
                    q.get("force", ["1"])[0] == "1"))
            if route == "/gemini-models-old":
                key = read_gemini_key()
                if not key:
                    return self._json({"ok": False, "reason": "no key set"})
                try:
                    u = ("https://generativelanguage.googleapis.com/v1beta/models?key=%s&pageSize=200"
                         % urllib.parse.quote(key))
                    req = urllib.request.Request(u, headers={"User-Agent": "all-commute"})
                    with urllib.request.urlopen(req, timeout=30) as r:
                        data = json.loads(r.read().decode("utf-8", "replace"))
                    models = []
                    for m in data.get("models", []):
                        methods = m.get("supportedGenerationMethods", [])
                        if "generateContent" in methods:
                            models.append(m.get("name", "").replace("models/", ""))
                    models = [x for x in models if x]
                    return self._json({"ok": True, "models": sorted(models),
                                       "recommended": DEFAULT_GEMINI_MODEL})
                except urllib.error.HTTPError as he:
                    d = ""
                    try:
                        d = he.read().decode("utf-8", "replace")[:300]
                    except Exception:
                        pass
                    return self._json({"ok": False, "reason": "HTTP %d" % he.code, "detail": d})
                except Exception as e:
                    return self._json({"ok": False, "reason": repr(e)})
            if route == "/zet-info":
                force = q.get("force", ["0"])[0] == "1"
                summarize = q.get("summarize", ["1"])[0] != "0"
                model = q.get("model", [DEFAULT_GEMINI_MODEL])[0]
                notices = fetch_zet_notices(force)
                key = read_gemini_key()
                out = {"ok": True, "sources": [{"source": n["source"], "url": n["url"],
                                                "ok": n["ok"],
                                                "chars": len(n.get("text", ""))} for n in notices],
                       "have_key": bool(key)}
                if summarize and key:
                    out["summary"] = gemini_summarize(notices, key, model)
                else:
                    out["raw"] = [{"source": n["source"], "url": n["url"],
                                   "text": n.get("text", "")} for n in notices if n.get("ok")]
                return self._json(out)
            if route == "/notify-status":
                return self._json({"ok": True, "available": _have_termux_notification(),
                                   "watching": bool(NOTIFY["trip"]), "route": NOTIFY["route"]})
            if route == "/version":
                return self._json({"version": APP_VERSION, "build": APP_BUILD})
        except Exception as e:
            return self._json({"ok": False, "reason": repr(e)}, 500)

        name = os.path.basename(route)
        if name not in ALLOWED_FILES:
            return self._json({"ok": False, "reason": "not found"}, 404)
        path = os.path.join(APPDIR, name)
        if not os.path.isfile(path):
            return self._json({"ok": False, "reason": "not found"}, 404)
        ext = os.path.splitext(name)[1]
        with open(path, "rb") as f:
            body = f.read()
        self.send_response(200)
        self.send_header("Content-Type", CONTENT_TYPES.get(ext, "application/octet-stream"))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace")
        if u.path == "/api-keys":
            keys = [ln.strip() for ln in body.splitlines() if ln.strip()]
            if not keys:
                return self._json({"ok": False, "reason": "empty"})
            write_keys(keys)
            return self._json({"ok": True, "keys": keys})
        if u.path == "/watch":
            try:
                data = json.loads(body or "{}")
            except Exception:
                data = {}
            trip = data.get("trip")
            if not trip:
                NOTIFY.update(trip=None, dest=None, route="", head="")
                clear_notification()
                return self._json({"ok": True, "watching": False,
                                   "available": _have_termux_notification()})
            NOTIFY.update(trip=trip, dest=data.get("dest"),
                          route=data.get("route", ""), head=data.get("head", ""))
            start_notify_thread()
            return self._json({"ok": True, "watching": True,
                               "available": _have_termux_notification()})
        if u.path == "/gemini-model":
            m = write_model(body)
            if m is None:
                return self._json({"ok": False, "model": read_model(),
                                   "reason": "not a model this key can call"})
            return self._json({"ok": True, "model": m, "order": sched_models()})
        if u.path == "/gemini-key":
            k = (body or "").strip()
            if not k:
                return self._json({"ok": False, "reason": "empty"})
            write_gemini_key(k)
            _zet_cache["items"] = None
            return self._json({"ok": True, "set": True})
        if u.path == "/unwatch":
            NOTIFY.update(trip=None, dest=None, route="", head="")
            clear_notification()
            return self._json({"ok": True, "watching": False})
        return self._json({"ok": False}, 404)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def _open_browser(port):
    url = "http://127.0.0.1:%d/all.html?v=%s.%s" % (port, APP_VERSION, APP_BUILD)
    for cmd in (["termux-open-url", url],
                ["am", "start", "-a", "android.intent.action.VIEW", "-d", url]):
        try:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        except Exception:
            continue


def _lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return ""


def _bootstrap_index():
    """First run, or a new day: build the index quietly in the background."""
    def worker():
        ymd = datetime.date.today().strftime("%Y%m%d")
        if index_ready():
            try:
                con = db()
                row = con.execute("select v from meta where k='service_date'").fetchone()
                con.close()
                if row and row[0] == ymd:
                    return
            except Exception:
                pass
        _log("building the station index in the background")
        rebuild(False)
    threading.Thread(target=worker, daemon=True).start()


def _go_background(port):
    """Relaunch ourselves detached from this terminal, on the same port, then
    let the foreground exit so the shell prompt comes back and Termux is free."""
    env = dict(os.environ, ALLC_PORT=str(port), ALLC_TAKEOVER="1", ALLC_NO_OPEN="1")
    try:
        subprocess.Popen([sys.executable, os.path.abspath(__file__)], env=env,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return True
    except Exception as e:
        print("  could not background: %r" % e, flush=True)
        return False


def _watch_quit_key(port):
    """One key, no Enter: q stops the server, b sends it to the background.
    If the tty will not go raw we fall back to typing q or b then Enter."""
    if not sys.stdin.isatty():
        return

    def act(ch):
        if ch in ("q", "Q"):
            print("\n  stopped, see you", flush=True)
            os._exit(0)
        if ch in ("b", "B"):
            print("\n  all.commute is now running in the background on port %d." % port, flush=True)
            print("  keep using Termux. stop it later with:  all.commute stop", flush=True)
            _go_background(port)
            os._exit(0)

    def worker():
        try:
            import termios
            import tty
            import select
            fd = sys.stdin.fileno()
            old = termios.tcgetattr(fd)
            try:
                tty.setcbreak(fd)
                while True:
                    r, _, _ = select.select([sys.stdin], [], [], 0.5)
                    if r:
                        ch = sys.stdin.read(1)
                        if ch in ("q", "Q", "b", "B"):
                            try:
                                termios.tcsetattr(fd, termios.TCSADRAIN, old)
                            except Exception:
                                pass
                            act(ch)
            finally:
                try:
                    termios.tcsetattr(fd, termios.TCSADRAIN, old)
                except Exception:
                    pass
        except Exception:
            try:
                for line in sys.stdin:
                    act(line.strip()[:1].lower())
            except Exception:
                pass

    threading.Thread(target=worker, daemon=True).start()


def main():
    os.makedirs(APPDIR, exist_ok=True)
    host = os.environ.get("ALLC_HOST", "0.0.0.0")
    takeover = os.environ.get("ALLC_TAKEOVER") == "1"
    httpd = port = None
    # when relaunching into the background, wait briefly for the foreground copy
    # to release its port so we can keep the very same address
    if takeover:
        for _ in range(30):
            try:
                httpd = Server((host, START_PORT), Handler)
                port = START_PORT
                break
            except OSError:
                time.sleep(0.2)
    if httpd is None:
        for p in range(START_PORT, START_PORT + PORT_TRIES):
            try:
                httpd = Server((host, p), Handler)
                port = p
                break
            except OSError:
                continue
    if httpd is None:
        print("  no free port found from %d" % START_PORT, flush=True)
        raise SystemExit(1)
    try:
        with open(PORTFILE, "w") as f:
            f.write(str(port))
    except Exception:
        pass
    W = "\033[1;37m"; DIM = "\033[0;90m"; OK = "\033[1;32m"; OFF = "\033[0m"
    ip = _lan_ip()
    print("  %s\u25b8%s on this phone  %shttp://127.0.0.1:%d%s" % (OK, OFF, W, port, OFF), flush=True)
    if ip:
        print("  %s\u25b8%s on Wi-Fi       %shttp://%s:%d%s" % (OK, OFF, W, ip, port, OFF), flush=True)
    print("  %sall.commute %s (%s)%s" % (DIM, APP_VERSION, APP_BUILD, OFF), flush=True)
    print("\n  %sq stop \u00b7 b background \u00b7 Ctrl+C stop%s" % (DIM, OFF), flush=True)
    _watch_quit_key(port)
    print("%s\033[38;5;208m\u0950%s" % (" " * 38, OFF), flush=True)
    _bootstrap_index()
    if os.environ.get("ALLC_NO_OPEN") != "1":
        _open_browser(port)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("  stopped", flush=True)
    finally:
        try:
            os.remove(PORTFILE)
        except OSError:
            pass


if __name__ == "__main__":
    main()
ALLC_SERVER_PY
done_

step "installing the station indexer"
cat > "$APPDIR/update_all.py" << 'ALLC_UPDATE_PY'
#!/usr/bin/env python3
"""
update_all.py — builds the whole-network station index for all.commute.

Downloads the ZET static GTFS zip once a day (ETag / Last-Modified aware),
keeps only the trips that actually run today, and writes a small SQLite file:

    stops(stop_id, name, lat, lon, bearing)   bearing = where its vehicles go
    dep(stop_id, t, trip_id, route, head)      t = seconds after midnight

Only stops that actually see a departure today survive, which quietly throws
out the parent stations that carry a name and a pin but never a tram.
The bearing is the mean heading of everything leaving that stop, so the app can
tell the eastbound platform from the westbound one across the street.

That is everything the app needs to answer "what is coming to the stop I am
standing at". The live GTFS-realtime feed is fetched separately, always fresh.
"""
import os
import io
import csv
import json
import time
import zipfile
import sqlite3
import hashlib
import math
import datetime
import urllib.request
import urllib.error

APPDIR = os.environ.get("ALLC_DIR", os.path.expanduser("~/.all.commute"))
DB_PATH = os.path.join(APPDIR, "network.db")
CACHE_ZIP = os.path.join(APPDIR, "zet_gtfs.zip")
META_PATH = CACHE_ZIP + ".meta.json"
GTFS_URLS = [
    "https://www.zet.hr/gtfs-scheduled/latest",
    "https://zet.hr/gtfs-scheduled/latest",
]


def log(m):
    print("[all.commute] " + m, flush=True)


def _load_meta():
    try:
        with open(META_PATH, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _save_meta(m):
    try:
        with open(META_PATH, "w", encoding="utf-8") as f:
            json.dump(m, f)
    except Exception:
        pass


def db_fresh_for(ymd):
    try:
        con = sqlite3.connect(DB_PATH)
        row = con.execute("select v from meta where k='service_date'").fetchone()
        n = con.execute("select count(*) from dep").fetchone()[0]
        con.close()
        return bool(row) and row[0] == ymd and n > 0
    except Exception:
        return False


def get_gtfs(force=False):
    meta = _load_meta()
    cached = None
    if os.path.isfile(CACHE_ZIP):
        try:
            with open(CACHE_ZIP, "rb") as f:
                cached = f.read()
        except Exception:
            cached = None
    headers = {"User-Agent": "Mozilla/5.0 (Android; all-commute)"}
    if cached is not None and not force:
        if meta.get("etag"):
            headers["If-None-Match"] = meta["etag"]
        if meta.get("last_modified"):
            headers["If-Modified-Since"] = meta["last_modified"]
    last = None
    for url in GTFS_URLS:
        try:
            log("checking " + url)
            req = urllib.request.Request(url, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=180) as r:
                    data = r.read()
                    rh = r.headers
            except urllib.error.HTTPError as he:
                if he.code == 304 and cached is not None:
                    log("  unchanged on the server, using the local zip")
                    return cached
                raise
            if data[:2] != b"PK":
                log("  not a zip, trying the next mirror")
                continue
            log("  got zip, %d bytes" % len(data))
            try:
                with open(CACHE_ZIP, "wb") as f:
                    f.write(data)
                _save_meta({"etag": rh.get("ETag") or "",
                            "last_modified": rh.get("Last-Modified") or "",
                            "sha256": hashlib.sha256(data).hexdigest()})
            except Exception:
                pass
            return data
        except Exception as e:
            last = e
            log("  failed: " + repr(e))
    if cached is not None:
        log("network unavailable, using the local GTFS copy")
        return cached
    raise RuntimeError("could not download GTFS zip: %r" % (last,))


def _member(zf, name):
    for n in zf.namelist():
        if n == name or n.endswith("/" + name):
            return n
    raise KeyError(name)


def rows(zf, name):
    with zf.open(_member(zf, name)) as fh:
        txt = io.TextIOWrapper(fh, encoding="utf-8-sig", errors="replace")
        for row in csv.DictReader(txt):
            yield row


def secs(t):
    p = (t or "").strip().split(":")
    if len(p) < 3:
        return None
    try:
        return int(p[0]) * 3600 + int(p[1]) * 60 + int(p[2])
    except ValueError:
        return None


def bearing(a_lat, a_lon, b_lat, b_lon):
    """Compass heading from one stop to the next, 0 is north."""
    p = math.pi / 180
    dl = (b_lon - a_lon) * p
    y = math.sin(dl) * math.cos(b_lat * p)
    x = (math.cos(a_lat * p) * math.sin(b_lat * p) -
         math.sin(a_lat * p) * math.cos(b_lat * p) * math.cos(dl))
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


def todays_services(zf, today):
    wd = ["monday", "tuesday", "wednesday", "thursday",
          "friday", "saturday", "sunday"][today.weekday()]
    ymd = today.strftime("%Y%m%d")
    active = set()
    try:
        for r in rows(zf, "calendar.txt"):
            if r.get(wd) == "1" and r.get("start_date", "0") <= ymd <= r.get("end_date", "9"):
                active.add(r["service_id"])
    except KeyError:
        pass
    try:
        for r in rows(zf, "calendar_dates.txt"):
            if r.get("date") == ymd:
                if r.get("exception_type") == "1":
                    active.add(r["service_id"])
                elif r.get("exception_type") == "2":
                    active.discard(r["service_id"])
    except KeyError:
        pass
    return active


def main():
    os.makedirs(APPDIR, exist_ok=True)
    today = datetime.date.today()
    ymd = today.strftime("%Y%m%d")
    force = os.environ.get("ALLC_FORCE") == "1"
    if not force and db_fresh_for(ymd):
        log("station index already holds today, nothing to rebuild")
        return

    data = get_gtfs(force)
    zf = zipfile.ZipFile(io.BytesIO(data))

    name = {}
    route_name = {}
    for r in rows(zf, "routes.txt"):
        route_name[r["route_id"]] = (r.get("route_short_name")
                                     or r.get("route_long_name") or "?").strip()

    services = todays_services(zf, today)
    log("%d service ids run today" % len(services))

    trip_info = {}
    for r in rows(zf, "trips.txt"):
        if r.get("service_id") in services:
            trip_info[r["trip_id"]] = (
                route_name.get(r.get("route_id"), "?"),
                (r.get("trip_headsign") or "").strip())
    log("%d trips run today" % len(trip_info))

    tmp = DB_PATH + ".tmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    con = sqlite3.connect(tmp)
    con.execute("pragma journal_mode=off")
    con.execute("pragma synchronous=off")
    con.execute("create table meta(k text primary key, v text)")
    con.execute("create table stops(stop_id text primary key, name text,"
                " lat real, lon real, bearing real)")
    con.execute("create table dep(stop_id text, t int, trip_id text,"
                " route text, head text)")
    con.execute("create table routes(route_id text primary key, short text)")
    con.executemany("insert or replace into routes values(?,?)",
                    list(route_name.items()))

    coord = {}
    for r in rows(zf, "stops.txt"):
        try:
            coord[r["stop_id"]] = (float(r["stop_lat"]), float(r["stop_lon"]))
        except (KeyError, ValueError):
            continue
        name[r["stop_id"]] = (r.get("stop_name") or "").strip()
    log("%d stops in the feed" % len(coord))

    # Every stop collects the headings of the vehicles that leave it, so a
    # platform knows whether it sends you east or west.
    sin_sum = {}
    cos_sum = {}
    ndep = 0
    batch = []
    trips_meta = []

    def flush_trip(cur_trip, seq_rows):
        nonlocal ndep
        if not cur_trip or not seq_rows:
            return
        ti = trip_info[cur_trip]
        seq_rows.sort(key=lambda x: x[0])
        first_id, last_id = seq_rows[0][1], seq_rows[-1][1]
        trips_meta.append((cur_trip, ti[0], ti[1],
                           name.get(first_id, ""), name.get(last_id, ""),
                           seq_rows[0][2], seq_rows[-1][2]))
        for i, (sq, sid, t) in enumerate(seq_rows):
            batch.append((sid, t, cur_trip, ti[0], ti[1]))
            here = coord.get(sid)
            nxt = coord.get(seq_rows[i + 1][1]) if i + 1 < len(seq_rows) else None
            if here and nxt:
                b = bearing(here[0], here[1], nxt[0], nxt[1])
                rad = math.radians(b)
                sin_sum[sid] = sin_sum.get(sid, 0.0) + math.sin(rad)
                cos_sum[sid] = cos_sum.get(sid, 0.0) + math.cos(rad)
        ndep += len(seq_rows)

    cur, buf = None, []
    for r in rows(zf, "stop_times.txt"):
        tid = r.get("trip_id")
        if tid != cur:
            flush_trip(cur, buf)
            cur, buf = tid, []
            if len(batch) >= 5000:
                con.executemany("insert into dep values(?,?,?,?,?)", batch)
                batch.clear()
        if tid not in trip_info:
            continue
        t = secs(r.get("departure_time") or r.get("arrival_time"))
        if t is None or r["stop_id"] not in coord:
            continue
        try:
            sq = int(r.get("stop_sequence") or 0)
        except ValueError:
            sq = 0
        buf.append((sq, r["stop_id"], t))
    flush_trip(cur, buf)
    if batch:
        con.executemany("insert into dep values(?,?,?,?,?)", batch)
        batch.clear()
    log("%d departures today" % ndep)

    served = {r[0] for r in con.execute("select distinct stop_id from dep")}
    log("%d stops actually see a departure today" % len(served))
    srows = []
    for sid in served:
        la, lo = coord[sid]
        s_, c_ = sin_sum.get(sid), cos_sum.get(sid)
        brg = None
        if s_ is not None and (abs(s_) > 1e-9 or abs(c_) > 1e-9):
            brg = (math.degrees(math.atan2(s_, c_)) + 360.0) % 360.0
        srows.append((sid, name.get(sid, ""), la, lo, brg))
    con.executemany("insert or replace into stops values(?,?,?,?,?)", srows)
    nstops = len(srows)

    con.execute("create table trips(trip_id text primary key, route text, head text,"
                " origin text, dest text, start_t int, end_t int)")
    con.executemany("insert or replace into trips values(?,?,?,?,?,?,?)", trips_meta)
    log("%d trips indexed" % len(trips_meta))
    con.execute("create index dep_stop_t on dep(stop_id, t)")
    con.execute("create index dep_trip on dep(trip_id, t)")
    con.execute("create index stops_ll on stops(lat, lon)")
    con.execute("create index trips_route on trips(route)")
    con.execute("insert or replace into meta values('service_date', ?)", (ymd,))
    con.execute("insert or replace into meta values('built', ?)", (str(int(time.time())),))
    con.execute("insert or replace into meta values('stops', ?)", (str(nstops),))
    con.execute("insert or replace into meta values('deps', ?)", (str(ndep),))
    con.commit()
    con.close()
    os.replace(tmp, DB_PATH)
    log("station index written to " + DB_PATH)


if __name__ == "__main__":
    main()
ALLC_UPDATE_PY
done_

step "installing the star interface"
cat > "$APPDIR/all.html" << 'ALLC_STAR_HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>all.commute</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<style>
  :root{
    --bg:#0d1117; --card:#141a22; --border:#2a323d; --text:#e6edf3;
    --muted:#8b949e; --cyan:#39d0d8; --gold:#d4a017; --green:#3fb950; --red:#f85149;
  }
  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent;}
  html,body{margin:0;height:100%;background:var(--bg);color:var(--text);
    font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
    overscroll-behavior:none;}
  #map,#gmap{position:absolute;inset:0;background:var(--bg);}
  #gmap{display:none;}
  body.gengine #map{display:none;} body.gengine #gmap{display:block;}

  /* ---- the status line. it never lies about what the app is doing ---- */
  #hud{position:absolute;top:calc(12px + env(safe-area-inset-top));left:14px;right:206px;
    z-index:600;font-size:.86rem;font-weight:600;line-height:1.35;color:#fff;
    pointer-events:none;text-shadow:0 0 5px #000,0 1px 2px #000,0 0 12px rgba(0,0,0,.85);}
  #hud b{color:var(--cyan);}
  #hud .spin{color:var(--cyan);animation:pulse .9s infinite;}
  @keyframes pulse{0%,100%{opacity:1}50%{opacity:.25}}

  #tools{position:absolute;top:calc(10px + env(safe-area-inset-top));right:12px;z-index:601;
    display:flex;gap:8px;}
  .tool{width:42px;height:42px;border-radius:12px;background:rgba(13,17,23,.35);
    border:1px solid var(--border);color:var(--text);font-size:1.1rem;cursor:pointer;
    display:flex;align-items:center;justify-content:center;backdrop-filter:blur(4px);}
  .tool.on{border-color:var(--cyan);color:var(--cyan);}
  /* one or the other: our stars, or Google's own transit icons */
  .viewseg{display:flex;border:1px solid var(--border);border-radius:12px;overflow:hidden;
    background:rgba(13,17,23,.35);backdrop-filter:blur(4px);}
  .viewseg button{width:44px;height:42px;border:0;background:transparent;cursor:pointer;
    display:flex;align-items:center;justify-content:center;color:var(--muted);padding:0;}
  .viewseg button+button{border-left:1px solid var(--border);}
  .viewseg button.on{background:rgba(57,208,216,.16);color:var(--cyan);}
  .viewseg svg{width:21px;height:21px;display:block;}

  /* the live fix readout, always on screen under the status line */
  #gpsChip{position:absolute;left:14px;z-index:600;
    top:calc(64px + env(safe-area-inset-top));display:flex;align-items:center;gap:7px;
    padding:6px 10px;border-radius:999px;cursor:pointer;
    background:rgba(13,17,23,.62);border:1px solid var(--border);
    backdrop-filter:blur(5px);font:700 .72rem/1 system-ui,sans-serif;color:var(--text);}
  #gpsChip .gdot{width:8px;height:8px;border-radius:50%;background:var(--muted);flex:none;}
  #gpsChip.good .gdot{background:var(--green);box-shadow:0 0 7px var(--green);}
  #gpsChip.ok   .gdot{background:var(--cyan);box-shadow:0 0 7px var(--cyan);}
  #gpsChip.weak .gdot{background:var(--gold);box-shadow:0 0 7px var(--gold);}
  #gpsChip.live .gdot{animation:pulse .9s infinite;}
  #gpsChip b{font-weight:800;}
  #gpsChip span{color:var(--muted);font-weight:700;}
  .tool.locate.busy{border-color:var(--cyan);color:var(--cyan);}

  /* where you are: a ring, not a blob. Fixed pixel size so it stays the same
     next to Google's own station icons at every zoom, and hollow so the map
     underneath it stays readable. */
  .medot{position:relative;width:22px;height:22px;}
  .medot i{position:absolute;inset:0;border-radius:50%;border:2.5px solid #39d0d8;
    box-shadow:0 0 0 1.5px rgba(0,0,0,.65),0 0 9px rgba(57,208,216,.75),
      inset 0 0 0 1.5px rgba(0,0,0,.5);}
  .medot b{position:absolute;left:50%;top:50%;width:4px;height:4px;margin:-2px 0 0 -2px;
    border-radius:50%;background:#39d0d8;box-shadow:0 0 4px #000;}
  .medot.weak i{border-color:#d4a017;box-shadow:0 0 0 1.5px rgba(0,0,0,.65),
      0 0 9px rgba(212,160,23,.7),inset 0 0 0 1.5px rgba(0,0,0,.5);}
  .medot.weak b{background:#d4a017;}
  .medot.pin i{border-style:dashed;border-color:#fff;}
  .medot.pin b{background:#fff;}

  /* the ring that says: this one. Hollow, so Google's icon shows through it. */
  .selring{position:relative;width:46px;height:46px;pointer-events:none;}
  .selring i{position:absolute;inset:0;border-radius:50%;border:2px solid var(--c);
    opacity:.95;}
  .selring i.w1{animation:wave 1.8s ease-out infinite;}
  .selring i.w2{animation:wave 1.8s ease-out infinite .6s;}
  .selring i.w3{animation:wave 1.8s ease-out infinite 1.2s;}
  .selring i.core{border-width:2.5px;box-shadow:0 0 14px var(--c),inset 0 0 12px var(--c);
    opacity:.55;animation:none;}
  @keyframes wave{0%{transform:scale(.55);opacity:.85}100%{transform:scale(1.6);opacity:0}}

  /* the station window */
  #popwrap{position:fixed;inset:0;z-index:820;display:none;align-items:center;
    justify-content:center;padding:18px;background:rgba(5,8,12,.55);}
  #popwrap.show{display:flex;}
  #pop{width:100%;max-width:400px;max-height:74vh;display:flex;flex-direction:column;
    background:var(--card);border:2px solid var(--c,var(--border));border-radius:18px;
    overflow:hidden;box-shadow:0 18px 50px rgba(0,0,0,.7);}
  .pophead{display:flex;align-items:flex-start;gap:9px;padding:12px 13px;
    background:color-mix(in srgb,var(--c) 15%,transparent);}
  .pophead .pid{flex:none;padding:4px 7px;border-radius:7px;color:var(--c);
    border:1px solid var(--c);background:rgba(13,17,23,.5);
    font:800 .72rem/1 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;}
  .pophead .pnm{flex:1;min-width:0;font-weight:800;font-size:.98rem;line-height:1.2;}
  .pophead .pnm i{display:block;font-style:normal;font-weight:600;font-size:.72rem;
    color:var(--muted);margin-top:3px;}
  .pophead .px{flex:none;width:30px;height:30px;border-radius:9px;border:1px solid var(--border);
    background:transparent;color:var(--text);cursor:pointer;font-size:.9rem;line-height:1;}
  .popbody{overflow-y:auto;-webkit-overflow-scrolling:touch;}
  .popsec{padding:6px 13px 2px;font:800 .66rem/1 system-ui,sans-serif;letter-spacing:.09em;
    color:var(--muted);text-transform:uppercase;}
  .arow.gone{opacity:.5;}
  .arow.gone .tm b{color:var(--muted);}
  .popfoot{padding:9px 13px;border-top:1px solid var(--border);display:flex;gap:8px;}
  .popfoot button{flex:1;border:1px solid var(--border);background:#1d242e;color:var(--text);
    border-radius:10px;padding:9px;font:700 .78rem/1 system-ui,sans-serif;cursor:pointer;}

  /* ---- the stars ---- */
  .starwrap{background:none;border:0;}
  .pin{position:relative;width:34px;height:34px;}
  .pinchip{position:absolute;left:37px;top:50%;transform:translateY(-50%);
    pointer-events:none;}
  .pinid{position:absolute;right:37px;top:50%;transform:translateY(-50%);
    pointer-events:none;}
  .pinid span{display:inline-block;padding:4px 6px;border-radius:7px;
    font:800 .71rem/1 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
    color:var(--c,#fff);background:rgba(13,17,23,.72);
    border:1px solid var(--c,#30363d);white-space:nowrap;text-shadow:0 1px 2px #000;}
  .pinchip span{display:inline-block;font:700 .74rem/1 system-ui,sans-serif;color:#fff;
    padding:4px 7px;border-radius:7px;background:rgba(13,17,23,.72);
    border:1px solid var(--c,#30363d);white-space:nowrap;text-shadow:0 1px 2px #000;}
  .pinchip i{font-style:normal;color:var(--muted);font-weight:600;}
  .star{position:relative;width:34px;height:34px;display:flex;align-items:center;justify-content:center;}
  .star svg{width:30px;height:30px;filter:drop-shadow(0 1px 3px rgba(0,0,0,.95));}
  .star polygon{fill:var(--c);stroke:#0d1117;stroke-width:1.1;stroke-linejoin:round;}
  .star.on::after{content:"";position:absolute;inset:-4px;border-radius:50%;
    border:2.5px solid var(--c);}
  .star.on::before{content:"";position:absolute;inset:-4px;border-radius:50%;
    border:2.5px solid var(--c);animation:ring 1.9s ease-out infinite;}
  @keyframes ring{0%{transform:scale(.8);opacity:.9}100%{transform:scale(1.45);opacity:0}}
  .star.mini{width:26px;height:26px;} .star.mini svg{width:24px;height:24px;}
  .star.mini::before,.star.mini::after{display:none;}

  /* ---- the dashboard button ---- */
  #dashBtn{position:fixed;left:50%;transform:translateX(-50%);z-index:650;
    bottom:calc(22px + env(safe-area-inset-bottom));
    padding:15px 34px;border-radius:999px;border:1px solid #6b5410;cursor:pointer;
    background:linear-gradient(180deg,#e2ae1e,#b8860b);color:#1a1206;
    font:800 1.02rem/1 system-ui,sans-serif;letter-spacing:.09em;
    box-shadow:0 6px 20px rgba(0,0,0,.6);}
  #dashBtn:active{transform:translateX(-50%) scale(.97);}
  #dashBtn.hasbar{bottom:calc(88px + env(safe-area-inset-bottom));}

  #watchbar{position:fixed;left:12px;right:12px;z-index:640;display:none;
    bottom:calc(22px + env(safe-area-inset-bottom));
    align-items:center;gap:10px;padding:10px 12px;border-radius:14px;
    background:rgba(20,26,34,.94);border:2px solid var(--c,var(--border));cursor:pointer;
    backdrop-filter:blur(6px);}
  body.watching #watchbar{display:flex;}
  #watchbar .wname{font-weight:800;font-size:.92rem;flex:1;min-width:0;
    overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
  #watchbar .weta{display:flex;align-items:center;gap:7px;font-weight:800;color:var(--cyan);
    font-size:.92rem;white-space:nowrap;flex:none;}
  #watchbar .wx{width:30px;height:30px;border-radius:9px;border:1px solid var(--border);
    background:transparent;color:var(--muted);cursor:pointer;flex:none;}

  /* ---- the dashboard ---- */
  #dash{position:fixed;inset:0;z-index:800;background:var(--bg);
    transform:translateY(100%);transition:transform .22s ease;
    display:flex;flex-direction:column;}
  #dash.show{transform:translateY(0);}
  .dhead{display:flex;align-items:center;gap:10px;padding:14px 14px 10px;
    padding-top:calc(14px + env(safe-area-inset-top));border-bottom:1px solid var(--border);}
  .dhead b{font-size:1.05rem;letter-spacing:.02em;}
  .dhead .sub{color:var(--muted);font-size:.78rem;font-weight:600;}
  .dhead .close{margin-left:auto;width:38px;height:38px;border-radius:11px;
    border:1px solid var(--border);background:transparent;color:var(--text);
    font-size:1.05rem;cursor:pointer;}
  .dbody{flex:1;overflow-y:auto;padding:12px 12px calc(28px + env(safe-area-inset-bottom));
    -webkit-overflow-scrolling:touch;}

  .card{border:2px solid var(--c);border-radius:16px;margin-bottom:14px;overflow:hidden;
    background:var(--card);}
  .card.on{box-shadow:0 0 0 3px color-mix(in srgb,var(--c) 30%,transparent);}
  .chead{display:flex;align-items:center;gap:9px;padding:10px 12px;
    background:color-mix(in srgb,var(--c) 14%,transparent);}
  .chead .nm{font-weight:800;font-size:.98rem;line-height:1.2;flex:1;min-width:0;}
  .chead .nm i{display:block;font-style:normal;font-weight:600;font-size:.74rem;color:var(--muted);
    margin-top:2px;}
  .wbtn{flex:none;border:1.5px solid var(--c);background:transparent;color:var(--c);
    border-radius:999px;padding:7px 13px;font:800 .74rem/1 system-ui,sans-serif;cursor:pointer;
    letter-spacing:.04em;}
  .wbtn.on{background:var(--c);color:#0d1117;}
  .svwrap{position:relative;display:block;cursor:pointer;}
  .sv{display:block;width:100%;height:132px;object-fit:cover;background:#0a0e14;
    border-top:1px solid color-mix(in srgb,var(--c) 30%,transparent);
    border-bottom:1px solid color-mix(in srgb,var(--c) 30%,transparent);}
  .sv360{position:absolute;right:10px;bottom:10px;display:flex;align-items:center;gap:5px;
    padding:6px 11px;border-radius:999px;background:rgba(13,17,23,.82);
    border:1px solid rgba(255,255,255,.28);color:#fff;
    font:800 .72rem/1 system-ui,sans-serif;letter-spacing:.06em;backdrop-filter:blur(4px);}
  .svnone{padding:9px 12px;color:var(--muted);font-size:.74rem;font-weight:600;
    border-top:1px solid var(--border);border-bottom:1px solid var(--border);}
  .arr{padding:4px 0;}
  .arow{display:grid;grid-template-columns:auto 1fr auto;gap:10px;align-items:center;
    padding:9px 12px;border-bottom:1px solid rgba(255,255,255,.045);}
  .arow:last-child{border-bottom:0;}
  .rt{display:inline-flex;align-items:center;justify-content:center;min-width:34px;height:28px;
    padding:0 7px;border-radius:8px;background:var(--r);color:#0d1117;
    font:800 .92rem/1 system-ui,sans-serif;border:1.5px solid var(--r);}
  .rt.sched{background:transparent;color:var(--r);}
  .rt.sm{min-width:26px;height:22px;font-size:.78rem;border-radius:6px;}
  .od{min-width:0;font-size:.82rem;font-weight:700;line-height:1.25;}
  .od i{display:block;font-style:normal;font-weight:600;font-size:.72rem;color:var(--muted);
    margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
  .od .from{color:var(--muted);font-weight:600;}
  .tm{text-align:right;white-space:nowrap;}
  .tm b{display:block;font-size:1.02rem;font-weight:800;}
  .tm b.soon{color:var(--green);} .tm b.now{color:var(--gold);}
  .tm small{display:block;color:var(--muted);font-size:.7rem;font-weight:700;margin-top:1px;}
  .wifi{vertical-align:-1px;margin-left:3px;}
  .ptag{display:inline-block;margin-left:5px;padding:1px 5px;border-radius:4px;
    border:1px solid var(--border);color:var(--muted);font-size:.62rem;font-weight:800;
    letter-spacing:.05em;vertical-align:1px;}
  .arow.printed .rt{border-style:dashed;}
  .warnbox{margin:0 0 12px;padding:9px 11px;border-radius:10px;
    border:1px solid rgba(212,160,23,.45);background:rgba(212,160,23,.09);
    color:var(--gold);font-size:.76rem;font-weight:700;line-height:1.4;}
  .srow{display:flex;align-items:center;gap:9px;padding:8px 2px;
    border-bottom:1px solid rgba(255,255,255,.05);}
  .srow:last-child{border-bottom:0;}
  .srow .sr{flex:none;min-width:32px;height:24px;padding:0 7px;border-radius:7px;
    display:inline-flex;align-items:center;justify-content:center;
    background:var(--r);color:#0d1117;font:800 .78rem/1 system-ui,sans-serif;}
  .srow .sn{flex:1;min-width:0;font-size:.78rem;font-weight:700;}
  .srow .sn i{display:block;font-style:normal;font-weight:600;font-size:.7rem;
    color:var(--muted);margin-top:2px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
  .srow .sn i.bad{color:var(--gold);}
  .srow .sx{flex:none;width:28px;height:28px;border-radius:8px;border:1px solid var(--border);
    background:transparent;color:var(--muted);cursor:pointer;font-size:.8rem;}
  .btnrow{display:flex;gap:8px;flex-wrap:wrap;}
  .msg.good{color:var(--green);} .msg.bad{color:var(--red);}
  .msg.busy{color:var(--cyan);}
  select.pick{width:100%;margin-top:10px;padding:11px 12px;border-radius:10px;
    background:#1d242e;color:var(--text);border:1px solid var(--border);
    font:700 .82rem/1 system-ui,sans-serif;-webkit-appearance:none;appearance:none;}
  select.pick:disabled{opacity:.5;}
  .picklbl{display:block;margin-top:11px;font-size:.74rem;font-weight:700;
    color:var(--muted);letter-spacing:.02em;}
  .d.late{color:var(--red);font-weight:800;} .d.ok{color:var(--green);font-weight:800;}
  .empty{padding:16px 12px;color:var(--muted);font-size:.82rem;font-weight:600;text-align:center;}

  /* ---- the 360 viewer ---- */
  #pano{position:fixed;inset:0;z-index:950;background:#000;display:none;}
  #pano.show{display:block;}
  #panoView{position:absolute;inset:0;}
  .panomsg{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;
    color:var(--muted);font-size:.86rem;font-weight:600;text-align:center;padding:24px;}
  .panobar{position:absolute;left:0;right:0;top:0;z-index:5;display:flex;align-items:center;
    gap:10px;padding:12px 14px;padding-top:calc(12px + env(safe-area-inset-top));
    background:linear-gradient(180deg,rgba(0,0,0,.78),transparent);pointer-events:none;}
  .panobar b{font-size:.95rem;flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;
    white-space:nowrap;text-shadow:0 1px 3px #000;}
  .panobar button{pointer-events:auto;flex:none;height:38px;padding:0 13px;border-radius:11px;
    border:1px solid rgba(255,255,255,.3);background:rgba(13,17,23,.65);color:#fff;
    font:700 .78rem/1 system-ui,sans-serif;cursor:pointer;backdrop-filter:blur(4px);}
  .panobar button.on{border-color:var(--cyan);color:var(--cyan);}
  .panohint{position:absolute;left:0;right:0;bottom:calc(22px + env(safe-area-inset-bottom));
    text-align:center;color:rgba(255,255,255,.66);font:600 .76rem/1 system-ui,sans-serif;
    text-shadow:0 1px 3px #000;pointer-events:none;transition:opacity .5s;}

  /* ---- settings ---- */
  #setup{position:fixed;inset:0;z-index:900;background:var(--bg);display:none;
    overflow-y:auto;padding:0 14px calc(30px + env(safe-area-inset-bottom));}
  #setup.show{display:block;}
  .sh{display:flex;align-items:center;gap:10px;padding:16px 0 12px;
    padding-top:calc(16px + env(safe-area-inset-top));position:sticky;top:0;background:var(--bg);
    border-bottom:1px solid var(--border);margin-bottom:14px;z-index:2;}
  .sh b{font-size:1.05rem;} .sh .close{margin-left:auto;}
  .box{background:var(--card);border:1px solid var(--border);border-radius:14px;
    padding:14px;margin-bottom:14px;}
  .box h3{margin:0 0 9px;font-size:.9rem;letter-spacing:.02em;}
  .note{display:block;color:var(--muted);font-size:.76rem;line-height:1.45;margin-top:9px;}
  .btn{display:inline-block;border:1px solid var(--border);background:#1d242e;color:var(--text);
    border-radius:10px;padding:10px 14px;font:700 .82rem/1 system-ui,sans-serif;cursor:pointer;}
  .btn.ghost{background:transparent;}
  .keyfile{position:absolute;width:1px;height:1px;opacity:0;pointer-events:none;}
  .msg{margin-top:9px;font-size:.78rem;color:var(--cyan);font-weight:600;min-height:1em;}
  .dot{display:inline-block;width:9px;height:9px;border-radius:50%;background:var(--red);
    vertical-align:middle;margin-left:5px;}
  .dot.ok{background:var(--green);}
  .kv{display:flex;justify-content:space-between;gap:12px;font-size:.8rem;padding:3px 0;}
  .kv span{color:var(--muted);font-weight:600;} .kv b{font-weight:700;}

  /* the layer stack, heaviest at the top */
  .eng{display:flex;gap:8px;margin-bottom:4px;}
  .eng button{flex:1;border:1px solid var(--border);background:transparent;color:var(--muted);
    border-radius:10px;padding:9px 6px;font:700 .78rem/1.3 system-ui,sans-serif;cursor:pointer;}
  .eng button i{display:block;font-style:normal;font-weight:600;font-size:.68rem;
    margin-top:3px;opacity:.75;}
  .eng button.on{border-color:var(--cyan);color:var(--cyan);background:rgba(57,208,216,.08);}
  .lrow{display:flex;align-items:center;gap:11px;padding:10px 2px;
    border-bottom:1px solid rgba(255,255,255,.05);cursor:pointer;}
  .lrow:last-child{border-bottom:0;}
  .lnum{flex:none;width:21px;height:21px;border-radius:6px;background:#1d242e;
    color:var(--muted);font:800 .7rem/21px system-ui,sans-serif;text-align:center;}
  .lname{flex:1;min-width:0;font-size:.84rem;font-weight:700;line-height:1.2;}
  .lname i{display:block;font-style:normal;font-weight:600;font-size:.72rem;
    color:var(--muted);margin-top:2px;}
  .lsw{flex:none;width:42px;height:24px;border-radius:999px;background:#1d242e;
    border:1px solid var(--border);position:relative;transition:background .15s;}
  .lsw::after{content:"";position:absolute;top:2px;left:2px;width:18px;height:18px;
    border-radius:50%;background:var(--muted);transition:transform .15s,background .15s;}
  .lsw.on{background:rgba(57,208,216,.22);border-color:var(--cyan);}
  .lsw.on::after{transform:translateX(18px);background:var(--cyan);}
  .llock{flex:none;font:700 .68rem/1 system-ui,sans-serif;color:var(--muted);
    border:1px solid var(--border);border-radius:999px;padding:6px 9px;}
  .lrow.off{opacity:.42;} .lrow.off .lsw{opacity:.5;}
  .lrow.heavy .lnum{background:rgba(212,160,23,.2);color:var(--gold);}

  .leaflet-control-attribution{font-size:9px;background:rgba(13,17,23,.55);color:#6e7681;}
  .leaflet-control-attribution a{color:#8b949e;}
</style>
</head>
<body>
  <div id="map"></div>
  <div id="gmap"></div>
  <div id="hud">Finding you…</div>
  <div id="tools">
    <div class="viewseg">
      <button id="viewStars" title="Star view">
        <svg viewBox="0 0 24 24"><polygon id="segStar" points=""/></svg></button>
      <button id="viewGoogle" title="Google station view">
        <svg viewBox="0 0 24 24">
          <rect x="3" y="3" width="18" height="18" rx="5" fill="currentColor" opacity=".22"/>
          <rect x="8" y="6.4" width="8" height="8.2" rx="2.4" fill="none"
                stroke="currentColor" stroke-width="1.7"/>
          <path d="M8.6 11.4h6.8" stroke="currentColor" stroke-width="1.5"/>
          <path d="M9.6 14.8 8.4 17.2M14.4 14.8l1.2 2.4" stroke="currentColor"
                stroke-width="1.5" stroke-linecap="round"/>
        </svg></button>
    </div>
    <button class="tool locate" id="btnLocate" title="Show my location">
      <svg viewBox="0 0 24 24" width="20" height="20" fill="none"
           stroke="currentColor" stroke-width="1.9">
        <circle cx="12" cy="12" r="4.2"/><circle cx="12" cy="12" r="8" opacity=".45"/>
        <path d="M12 1.6v3M12 19.4v3M1.6 12h3M19.4 12h3" stroke-linecap="round"/>
      </svg></button>
    <button class="tool" id="btnLabels" title="Street names">A</button>
    <button class="tool" id="btnSetup" title="Settings">⚙</button>
  </div>

  <div id="gpsChip" title="Tap for the whole picture">
    <span class="gdot"></span><b id="gpsAcc">—</b><span id="gpsSrc">looking…</span>
  </div>

  <div id="watchbar">
    <span class="star mini" id="wbStar"></span>
    <span class="wname" id="wbName">—</span>
    <span class="weta" id="wbEta">—</span>
    <button class="wx" id="wbX" title="Stop watching">✕</button>
  </div>
  <button id="dashBtn">DASHBOARD</button>

  <div id="dash">
    <div class="dhead">
      <div><b>Arrivals around you</b><div class="sub" id="dSub">—</div></div>
      <button class="close" id="dClose">✕</button>
    </div>
    <div class="dbody" id="dBody"></div>
  </div>

  <div id="popwrap">
    <div id="pop">
      <div class="pophead">
        <span class="pid" id="popId">—</span>
        <span class="pnm" id="popNm">—<i id="popSub"></i></span>
        <button class="px" id="popX">✕</button>
      </div>
      <div class="popbody" id="popBody"></div>
      <div class="popfoot">
        <button id="popWatch">WATCH THIS STOP</button>
        <button id="popAll">ALL NEARBY</button>
      </div>
    </div>
  </div>

  <div id="pano">
    <div id="panoView"></div>
    <div class="panobar">
      <b id="panoName">—</b>
      <button id="panoMotion" title="Move the phone to look around">gyro</button>
      <button id="panoClose">✕</button>
    </div>
    <div class="panohint" id="panoHint">drag to look around</div>
  </div>

  <div id="setup">
    <div class="sh"><b>all.commute</b><button class="btn ghost close" id="sClose">Done</button></div>

    <div class="box">
      <h3>Map layers</h3>
      <div class="eng">
        <button id="engFree">Free map<i>roads and names</i></button>
        <button id="engDetail">Detailed map<i>every layer, needs key</i></button>
      </div>
      <div id="layerBox"></div>
      <span class="note" id="layerNote"></span>
    </div>

    <div class="box">
      <h3>Position <span class="dot" id="posDot"></span></h3>
      <div id="posBox"><span class="note">Waiting for a fix…</span></div>
      <div class="btnrow" style="margin-top:11px">
        <button class="btn" id="posSharpen">Sharpen — hold still</button>
        <button class="btn ghost" id="posPin">Pin by tapping the map</button>
        <button class="btn ghost" id="posProv">Ask Android now</button>
      </div>
      <div class="msg" id="posMsg"></div>
      <span class="note">A phone gives its first answer from cell towers and
        wifi, then tightens as the satellites lock. This listens for 30 seconds
        and weights each fix by how sure it claims to be, which cancels the
        random half of the error. It cannot cancel the other half: signal
        bouncing off the buildings along a street like Ilica arrives late and
        pushes the fix sideways, confidently. That is why the ring is drawn —
        it is the phone's own estimate, and standing where two streets open up
        will do more than any setting here.</span>
    </div>

    <div class="box">
      <h3>Printed timetables <span class="dot" id="schedDot"></span></h3>
      <div id="schedWarn"></div>
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <button class="btn" id="schedNear">Store the lines around me</button>
        <button class="btn ghost" id="schedAll">Delete all</button>
      </div>
      <div class="msg" id="schedMsg"></div>
      <div id="schedList" style="margin-top:8px"></div>
      <span class="note">ZET publishes the official vozni red of every line as a
        PDF. This reads one per line, keeps the times, and throws the PDF away in
        the same breath — nothing but a small file of times stays on the phone,
        and it works with no signal at all. When the GTFS feed breaks or the
        index is a day behind, these fill the holes in the board.</span>
    </div>

    <div class="box">
      <h3>Gemini key <span class="dot" id="gemDot"></span></h3>
      <input type="file" id="gemFile" accept=".txt,text/plain" class="keyfile">
      <div class="btnrow">
        <label for="gemFile" class="btn">Load key from file</label>
        <button class="btn ghost" id="gemTest">Test key</button>
        <button class="btn ghost" id="gemRefresh">Check available models</button>
      </div>
      <div class="msg" id="gemMsg"></div>
      <span class="picklbl">Model for reading timetable PDFs</span>
      <select class="pick" id="gemPick"><option value="">Automatic</option></select>
      <div class="msg" id="gemPickMsg"></div>
      <span class="note">Needed to read the timetable PDFs. The printed grids are
        an hour column with loose minutes beside it, in two directions and three
        day columns — without a key all this can do is scrape stray times it
        cannot place, and those are never allowed near the board. One call per
        line, once, then never again.</span>
    </div>

    <div class="box">
      <h3>Google key <span class="dot" id="keyDot"></span></h3>
      <input type="file" id="keyFile" accept=".txt,text/plain" class="keyfile">
      <div class="btnrow">
        <label for="keyFile" class="btn">Load key from file</label>
        <button class="btn ghost" id="keyTest">Test key</button>
      </div>
      <div class="msg" id="keyMsg"></div>
      <span class="note">Three things use it: the station photograph, the 360° view,
        and the detailed map. Kept on the phone in ~/.all.commute/google-api.txt and
        never shown. Needs <b>Street View Static API</b> for the photograph and
        <b>Maps JavaScript API</b> for the other two.</span>
    </div>

    <div class="box">
      <h3>Station cache</h3>
      <div id="statBox"><span class="note">Loading…</span></div>
      <div style="margin-top:11px"><button class="btn" id="cacheBtn">Cache all stations</button></div>
      <div class="msg" id="cacheMsg"></div>
      <span class="note">Every stop in the ZET network, kept on the phone. Built once a day.</span>
    </div>

    <div class="box">
      <h3>Search radius</h3>
      <div style="display:flex;gap:8px;align-items:center">
        <button class="btn" id="rMinus">−</button>
        <b id="rLbl" style="min-width:78px;text-align:center">150 m</b>
        <button class="btn" id="rPlus">+</button>
      </div>
      <span class="note">How far around you the dashboard looks. 150 m is walking
        distance to the platform. If nothing is that close, the app reaches further
        on its own and says so.</span>
    </div>

    <div class="box">
      <h3>About</h3>
      <div class="kv"><span>Interface</span><b>stars · v39</b></div>
      <div class="kv"><span>Engine</span><b id="verLine">…</b></div>
    </div>
  </div>

<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
/* =========================================================================
   all.commute — star interface
   Open it, it finds you, it puts a coloured star on every tram and bus stop
   you can walk to. Every line carries its own colour, the same colour on
   every board. The dashboard shows what is coming to each station, framed in
   that station's colour, with the stop itself in Street View — tap the photo
   and you can turn all the way round.
   ========================================================================= */

/* ---------------- small helpers ---------------- */
function esc(x){
  return String(x == null ? "" : x).replace(/[&<>"']/g, c =>
    ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
}
function fmtDist(m){
  if (m == null) return "";
  return m < 1000 ? m + " m" : (m / 1000).toFixed(m < 10000 ? 1 : 0) + " km";
}
function metres(aLat, aLon, bLat, bLon){
  const R = 6371000, p = Math.PI / 180;
  const dla = (bLat - aLat) * p, dlo = (bLon - aLon) * p;
  const h = Math.sin(dla / 2) ** 2 +
    Math.cos(aLat * p) * Math.cos(bLat * p) * Math.sin(dlo / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(h)));
}
function dirAbbr(b){
  if (b == null) return null;
  return ["N","NE","E","SE","S","SW","W","NW"][Math.round((((b % 360) + 360) % 360) / 45) % 8];
}
function hud(html, busy){
  document.getElementById("hud").innerHTML =
    (busy ? '<span class="spin">●</span> ' : "") + html;
}
const WIFI = '<svg class="wifi" width="13" height="10" viewBox="0 0 16 12">' +
  '<circle cx="8" cy="10" r="1.2" fill="#3fb950"/>' +
  '<path d="M4.8 7.2a4.5 4.5 0 0 1 6.4 0" fill="none" stroke="#3fb950" stroke-width="1.6" stroke-linecap="round"/>' +
  '<path d="M2.6 4.8a7.6 7.6 0 0 1 10.8 0" fill="none" stroke="#3fb950" stroke-width="1.6" stroke-linecap="round"/></svg>';

const STAR_PTS = (() => {
  const p = [];
  for (let i = 0; i < 10; i++) {
    const a = (-90 + i * 36) * Math.PI / 180;
    const r = i % 2 ? 4.6 : 11;
    p.push((12 + r * Math.cos(a)).toFixed(2) + "," + (12 + r * Math.sin(a)).toFixed(2));
  }
  return p.join(" ");
})();
function starHTML(colour, on, mini){
  return '<div class="star' + (on ? " on" : "") + (mini ? " mini" : "") +
    '" style="--c:' + colour + '">' +
    '<svg viewBox="0 0 24 24"><polygon points="' + STAR_PTS + '"/></svg></div>';
}

/* eight hues that stay apart on a dark map, and none of them is the green or
   the red we use for early and late */
const PALETTE = ["#d4a017", "#39d0d8", "#c77dff", "#ff9f1c",
                 "#5ee1a0", "#ff6b9d", "#60a5fa", "#f4e04d"];

/* ---------------- one colour per line, forever ----------------
   Line 6 is the same colour on every board, every day, on every stop. The
   colour is worked out from the number itself, so nothing has to be stored
   and nothing drifts between sessions. The hue walks the wheel in golden-angle
   steps, because the lines you see together are nearly always numerically
   close, and consecutive numbers land opposite each other. Brightness and
   saturation come from a separate hash so two distant numbers that happen to
   share a hue still pull apart. */
const TINT = {};
function routeColour(route){
  const k = String(route == null ? "" : route).trim().toUpperCase();
  if (TINT[k]) return TINT[k];
  let n = parseInt(k, 10);
  if (!isFinite(n) || String(n) !== k.replace(/^0+/, "")) {
    n = 0;
    for (let i = 0; i < k.length; i++) n = (n * 33 + k.charCodeAt(i)) >>> 0;
  }
  const h = (n * 137.508) % 360;
  const mix = Math.imul(n + 1, 2654435761) >>> 0;
  let l = 62 + (((mix >>> 3) % 4) - 1.5) * 11;
  const s = 62 + ((mix >>> 11) % 2) * 20;
  if (h > 195 && h < 285) l += 7;
  else if (h > 40 && h < 80) l -= 6;
  l = Math.max(45, Math.min(82, l));
  TINT[k] = "hsl(" + h.toFixed(1) + " " + s + "% " + l.toFixed(0) + "%)";
  return TINT[k];
}

/* ---------------- state ---------------- */
const LS = {
  get(k, d){ try { const v = localStorage.getItem("ac2_" + k); return v == null ? d : JSON.parse(v); }
             catch (e) { return d; } },
  set(k, v){ try { localStorage.setItem("ac2_" + k, JSON.stringify(v)); } catch (e) {} },
  del(k){ try { localStorage.removeItem("ac2_" + k); } catch (e) {} },
};

/* The layer stack, heaviest first. Row one is the map itself and cannot be
   turned off. Everything below it is optional, and the further down you go the
   less it has to do with catching a tram. */
const LAYER_DEFS = [
  { id:"base",      name:"Roads & water",         note:"the map itself",              lock:true },
  { id:"streets",   name:"Street names",          note:"Ilica, Savska, Vukovarska" },
  { id:"places",    name:"District & place names", note:"Trešnjevka, Črnomerec",      google:true },
  { id:"parks",     name:"Parks & green space",   note:"Maksimir, Bundek, Sava banks", google:true },
  { id:"buildings", name:"Buildings",             note:"footprints once you zoom in",  google:true },
  { id:"transit",   name:"Transit lines",         note:"tram and rail drawn on the map", google:true },
  { id:"shops",     name:"Shops, cafés & food",   note:"McDonald's and everything like it", google:true },
];
let LAYERS = Object.assign(
  { base:true, streets:true, places:false, parks:false, buildings:false, transit:false, shops:false },
  LS.get("layers", {}));
let ENGINE = LS.get("engine", "free");     // "free" (Leaflet) or "detail" (Google)
/* "stars"  — our own coloured stars, either basemap
   "google" — Google's own transit icons are the thing you tap. We draw nothing
              but the ring around whichever one you picked. */
let MODE = LS.get("mode", "stars");

let API_KEY = "";
let map = null, tiles = null, names = null;      // free engine
let gmap = null, HtmlMarker = null;              // detailed engine
let gPins = [], gMe = null, gRing = null;
let ME = null, meMk = null, meRing = null;
let STOPS = [];                       // the stations around you, nearest first
let COLOUR = {};                      // stop_id -> colour, kept steady as you walk
let MARKS = {};                       // stop_id -> leaflet marker
let BOARDS = {};                      // stop_id -> board payload
let WATCH = LS.get("watch", null);    // the station you said you are waiting at
let RADIUS = LS.get("radius", 150);
let INDEX_OK = false;
let lastFix = 0, lastStopFetch = null, boardTimer = null, indexTimer = null;
const RSTEPS = [100, 150, 200, 300, 400, 600, 900];
const SV_CACHE = {};                  // stop_id -> street view url, or null

/* =========================================================================
   THE FREE ENGINE — Leaflet on CARTO raster tiles
   The base carries roads, water and parks and no writing at all. The names
   ride on a transparent layer above it, in their own pane so they sit over the
   radius ring but under the stars. Raster tiles cannot separate street names
   from district names, and carry no shops at all — that is what the detailed
   engine is for.
   ========================================================================= */
const TILE_BASE  = "https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png";
const TILE_NAMES = "https://{s}.basemaps.cartocdn.com/dark_only_labels/{z}/{x}/{y}{r}.png";

function initFreeMap(){
  const v = LS.get("view", { lat: 45.8131, lng: 15.9775, zoom: 17 });
  map = L.map("map", { zoomControl: false, attributionControl: true })
    .setView([v.lat, v.lng], v.zoom);
  tiles = L.tileLayer(TILE_BASE,
    { maxZoom: 20, attribution: "© OpenStreetMap, © CARTO" }).addTo(map);
  map.createPane("names");
  map.getPane("names").style.zIndex = 450;
  map.getPane("names").style.pointerEvents = "none";
  names = L.tileLayer(TILE_NAMES, { maxZoom: 20, opacity: .95, pane: "names" });
  map.on("moveend", saveView);
  map.on("click", (e) => { if (PINMODE) pinAt(e.latlng.lat, e.latlng.lng); });
}

/* =========================================================================
   THE DETAILED ENGINE — Google Maps JavaScript API
   The only thing that can actually take the map apart feature by feature. It
   is also what the 360° view runs on, so once a key is in, both arrive
   together. Loaded lazily: nothing is fetched from Google until you ask.
   ========================================================================= */
let gPromise = null;
function loadGoogle(){
  if (gPromise) return gPromise;
  if (!API_KEY) return Promise.reject(new Error("no Google key loaded"));
  gPromise = new Promise((resolve, reject) => {
    const cb = "__gmapcb" + Math.random().toString(36).slice(2);
    let settled = false;
    window.gm_authFailure = () => {
      if (settled) return; settled = true; gPromise = null;
      reject(new Error("the key was refused, check Maps JavaScript API"));
    };
    window[cb] = () => { if (settled) return; settled = true; resolve(window.google); };
    const s = document.createElement("script");
    s.async = true;
    s.src = "https://maps.googleapis.com/maps/api/js?v=weekly&loading=async&key=" +
      encodeURIComponent(API_KEY) + "&callback=" + cb;
    s.onerror = () => {
      if (settled) return; settled = true; gPromise = null;
      reject(new Error("could not reach Google"));
    };
    document.head.appendChild(s);
    setTimeout(() => {
      if (settled) return; settled = true; gPromise = null;
      reject(new Error("timed out"));
    }, 15000);
  });
  return gPromise;
}

/* Later rules win, so everything optional is switched off first and only the
   layers you asked for are switched back on. */
function gStyles(){
  const on = [{ visibility: "on" }], off = [{ visibility: "off" }];
  const s = [
    { elementType:"geometry", stylers:[{ color:"#161b23" }] },
    { elementType:"labels.text.fill", stylers:[{ color:"#98a3b0" }] },
    { elementType:"labels.text.stroke", stylers:[{ color:"#0d1117" }, { weight:3 }] },
    { elementType:"labels.icon", stylers:off },
    { featureType:"landscape", elementType:"geometry", stylers:[{ color:"#161b23" }] },
    { featureType:"water", elementType:"geometry", stylers:[{ color:"#0a141d" }] },
    { featureType:"road", elementType:"geometry", stylers:[{ color:"#2b333f" }] },
    { featureType:"road.arterial", elementType:"geometry", stylers:[{ color:"#333c4a" }] },
    { featureType:"road.highway", elementType:"geometry", stylers:[{ color:"#414c5c" }] },
    { featureType:"road", elementType:"labels", stylers:off },
    { featureType:"administrative", elementType:"labels", stylers:off },
    { featureType:"poi", stylers:off },
    { featureType:"transit", stylers:off },
  ];
  if (LAYERS.streets) s.push({ featureType:"road", elementType:"labels.text", stylers:on });
  if (LAYERS.places)  s.push({ featureType:"administrative", elementType:"labels.text", stylers:on });
  if (LAYERS.parks)   s.push(
    { featureType:"poi.park", stylers:on },
    { featureType:"poi.park", elementType:"geometry", stylers:[{ color:"#16261c" }] },
    { featureType:"poi.park", elementType:"labels.text.fill", stylers:[{ color:"#6f9a7c" }] });
  if (LAYERS.buildings) s.push(
    { featureType:"landscape.man_made", elementType:"geometry.fill", stylers:[{ color:"#1d232d" }] },
    { featureType:"landscape.man_made", elementType:"geometry.stroke", stylers:[{ color:"#2c3542" }] });
  if (LAYERS.transit) s.push(
    { featureType:"transit", stylers:on },
    { featureType:"transit.line", elementType:"geometry", stylers:[{ color:"#3f4d5f" }] },
    { featureType:"transit", elementType:"labels.icon", stylers:on });
  if (MODE === "google") s.push(
    /* the icons are the interface here, so they come back on no matter what
       the layer stack says */
    { featureType:"transit.station", stylers:on },
    { featureType:"transit.station", elementType:"labels.icon", stylers:on },
    { featureType:"transit.station", elementType:"labels.text", stylers:on });
  if (LAYERS.shops) s.push(
    { featureType:"poi.business", stylers:on },
    { featureType:"poi.business", elementType:"labels.icon", stylers:on },
    { featureType:"poi.business", elementType:"labels.text.fill", stylers:[{ color:"#8b949e" }] });
  return s;
}

/* one HTML element pinned to one coordinate, so the stars look identical on
   both engines instead of being redrawn as flat images for Google */
function makeMarkerClass(g){
  if (HtmlMarker) return HtmlMarker;
  HtmlMarker = class extends g.maps.OverlayView {
    constructor(pos, html, onClick, z){ super(); this.p = pos; this.h = html; this.c = onClick; this.z = z || 0; }
    onAdd(){
      this.div = document.createElement("div");
      /* fixed to the star's own box: the name chip is absolutely positioned
         inside it, so it cannot widen this and shift the star off-centre */
      this.div.style.cssText = "position:absolute;width:34px;height:34px;" +
        "transform:translate(-50%,-50%);cursor:pointer;z-index:" + this.z;
      this.div.innerHTML = this.h;
      if (this.c) this.div.addEventListener("click", this.c);
      this.getPanes().overlayMouseTarget.appendChild(this.div);
    }
    draw(){
      if (!this.div) return;
      const pt = this.getProjection()
        .fromLatLngToDivPixel(new google.maps.LatLng(this.p.lat, this.p.lng));
      if (pt) { this.div.style.left = pt.x + "px"; this.div.style.top = pt.y + "px"; }
    }
    onRemove(){ if (this.div) { this.div.remove(); this.div = null; } }
  };
  return HtmlMarker;
}

function buildGoogleMap(g){
  if (gmap) return;
  const v = LS.get("view", { lat: 45.8131, lng: 15.9775, zoom: 17 });
  gmap = new g.maps.Map(document.getElementById("gmap"), {
    center: { lat: v.lat, lng: v.lng }, zoom: v.zoom,
    disableDefaultUI: true, gestureHandling: "greedy", clickableIcons: true,
    backgroundColor: "#0d1117", styles: gStyles(),
  });
  makeMarkerClass(g);
  gmap.addListener("idle", saveView);
  gmap.addListener("click", onMapClick);
}

/* ---------------- one view, whichever engine is showing ---------------- */
function usingGoogle(){ return ENGINE === "detail" && !!gmap; }
function currentView(){
  if (usingGoogle()) {
    const c = gmap.getCenter();
    return c ? { lat:c.lat(), lng:c.lng(), zoom:gmap.getZoom() } : LS.get("view", null);
  }
  const c = map.getCenter();
  return { lat:c.lat, lng:c.lng, zoom:map.getZoom() };
}
function setView(v, zoom){
  const z = zoom == null ? (v.zoom == null ? 17 : v.zoom) : zoom;
  if (usingGoogle()) { gmap.setCenter({ lat:v.lat, lng:v.lng }); gmap.setZoom(z); }
  else map.setView([v.lat, v.lng], z);
}
function saveView(){ const v = currentView(); if (v) LS.set("view", v); }
function inView(lat, lng){
  try {
    if (usingGoogle()) { const b = gmap.getBounds(); return b ? b.contains({ lat, lng }) : true; }
    return map.getBounds().contains([lat, lng]);
  } catch (e) { return true; }
}

async function setEngine(mode, quiet){
  if (mode === ENGINE && (mode === "free" || gmap)) { applyLayers(); return true; }
  const keep = currentView();
  if (mode === "detail") {
    if (!API_KEY) {
      hud("The detailed map needs a Google key. ⚙ → Load key from file.");
      renderLayers(); return false;
    }
    if (!quiet) hud("Loading the detailed map…", true);
    try {
      const g = await loadGoogle();
      /* the container has to be on screen first — Google measures the div when
         the map is created, and a hidden one measures zero */
      document.body.classList.add("gengine");
      buildGoogleMap(g);
      ENGINE = "detail"; LS.set("engine", ENGINE);
      if (keep) setView(keep, keep.zoom);
      applyLayers(); redrawAll();
      if (!quiet) hud("Detailed map on. Every layer is yours in ⚙.");
    } catch (e) {
      ENGINE = "free"; LS.set("engine", "free");
      document.body.classList.remove("gengine");
      hud("Detailed map unavailable: " + esc(e.message) + ".");
      applyLayers(); renderLayers(); redrawAll();
      return false;
    }
  } else {
    ENGINE = "free"; LS.set("engine", "free");
    document.body.classList.remove("gengine");
    if (keep) setView(keep, keep.zoom);
    setTimeout(() => map.invalidateSize(), 60);
    applyLayers(); redrawAll();
    if (!quiet) hud("Free map on.");
  }
  renderLayers();
  return true;
}

function applyLayers(){
  LS.set("layers", LAYERS);
  if (usingGoogle()) { gmap.setOptions({ styles: gStyles() }); }
  else if (names) { if (LAYERS.streets) names.addTo(map); else map.removeLayer(names); }
  document.getElementById("btnLabels").classList.toggle("on", !!LAYERS.streets);
}
document.getElementById("btnLabels").addEventListener("click", () => {
  LAYERS.streets = !LAYERS.streets; applyLayers(); renderLayers();
  hud(LAYERS.streets ? "Street names on." : "Street names off. Only the stations remain.");
});

/* ---------------- drawing, on whichever engine ---------------- */
/* [id] ★ Name DIR — the GTFS stop id rides on the left of the star, in the
   station's own colour. Both chips are absolutely positioned inside the pin,
   so neither of them can shift the star off its coordinate. */
function pinHTML(s){
  const c = COLOUR[s.stop_id], on = isWatched(s.stop_id), ab = dirAbbr(s.bearing);
  return '<div class="pin">' +
    '<span class="pinid"><span style="--c:' + c + '">' + esc(s.stop_id) +
    '</span></span>' + starHTML(c, on) +
    '<span class="pinchip"><span style="--c:' + c + '">' + esc(s.name) +
    (ab ? ' <i>' + ab + '</i>' : "") + '</span></span></div>';
}
function clearStars(){
  Object.values(MARKS).forEach(m => { try { map.removeLayer(m); } catch (e) {} });
  MARKS = {};
  gPins.forEach(p => { try { p.setMap(null); } catch (e) {} });
  gPins = [];
}
function drawStars(){
  clearStars();
  if (MODE === "google") return;   // Google draws the stations in that view
  if (!STOPS.length) return;
  STOPS.forEach(s => {
    const on = isWatched(s.stop_id);
    if (usingGoogle()) {
      const p = new HtmlMarker({ lat:s.lat, lng:s.lon }, pinHTML(s),
        () => openPop(s), on ? 1000 : 500);
      p.setMap(gmap); gPins.push(p);
    } else {
      const icon = L.divIcon({ html: pinHTML(s), className: "starwrap",
        iconSize: [34, 34], iconAnchor: [17, 17] });
      const m = L.marker([s.lat, s.lon], { icon, zIndexOffset: on ? 1000 : 500 }).addTo(map);
      m.on("click", () => openPop(s));
      MARKS[s.stop_id] = m;
    }
  });
}
let gAcc = null, meAcc = null;
function meHTML(){
  const cls = ME && ME.pinned ? " pin" : ((ME && ME.acc > 25) ? " weak" : "");
  return '<div class="medot' + cls + '"><i></i><b></b></div>';
}
function drawMe(){
  if (meMk) { try { map.removeLayer(meMk); } catch (e) {} meMk = null; }
  if (meRing) { try { map.removeLayer(meRing); } catch (e) {} meRing = null; }
  if (meAcc) { try { map.removeLayer(meAcc); } catch (e) {} meAcc = null; }
  if (gMe) { gMe.setMap(null); gMe = null; }
  if (gRing) { gRing.setMap(null); gRing = null; }
  if (gAcc) { gAcc.setMap(null); gAcc = null; }
  if (!ME) return;
  const acc = ME.pinned ? 0 : (ME.acc || 0);
  if (usingGoogle()) {
    gRing = new google.maps.Circle({ map:gmap, center:{ lat:ME.lat, lng:ME.lng },
      radius:RADIUS, strokeColor:"#39d0d8", strokeOpacity:.32, strokeWeight:1,
      fillColor:"#39d0d8", fillOpacity:.04, clickable:false });
    if (acc > 4) gAcc = new google.maps.Circle({ map:gmap,
      center:{ lat:ME.lat, lng:ME.lng }, radius:acc, strokeColor:"#39d0d8",
      strokeOpacity:.5, strokeWeight:1, fillOpacity:0, clickable:false, zIndex:40 });
    /* fixed 22 px, the size of Google's own station icon. The old version was a
       Circle with radius 9 METRES, which is why it swelled as you zoomed in. */
    gMe = new HtmlMarker({ lat:ME.lat, lng:ME.lng }, meHTML(), null, 60);
    gMe.setMap(gmap);
  } else {
    meRing = L.circle([ME.lat, ME.lng], { radius:RADIUS, color:"#39d0d8", weight:1,
      opacity:.32, fill:false, interactive:false }).addTo(map);
    if (acc > 4) meAcc = L.circle([ME.lat, ME.lng], { radius:acc, color:"#39d0d8",
      weight:1, opacity:.5, fill:false, interactive:false }).addTo(map);
    meMk = L.marker([ME.lat, ME.lng], { interactive:false, zIndexOffset:60,
      icon: L.divIcon({ html: meHTML(), className:"starwrap",
                        iconSize:[22,22], iconAnchor:[11,11] }) }).addTo(map);
  }
}
function redrawAll(){ drawMe(); drawStars(); }

/* ---------------- where you are ---------------- */
/* =========================================================================
   POSITION
   A single getCurrentPosition returns whatever the phone has to hand, which is
   usually the coarse network fix -- cell towers and wifi -- because the GNSS
   chip has not finished converging. That is the loose position you were
   seeing, and no option fixes it because the problem is that we stopped
   listening too early.

   So we listen in bursts instead. watchPosition keeps delivering fixes as more
   satellites lock and the estimate tightens, and we keep the good ones and
   average them. Averaging cancels the random half of the error. It does NOT
   cancel multipath -- signal bouncing off the buildings along Ilica -- which
   is a bias, not noise, and is the reason a phone in a street canyon can sit
   confidently thirty metres from where you stand.
   ========================================================================= */
let FIXES = [];            // recent accepted fixes
let watchId = null, burstEnd = 0, burstTick = null;
const FIX_TTL = 90000;     // a fix older than this is stale

function fuse(){
  /* inverse-variance weighting: a fix claiming 5 m counts for far more than
     one claiming 40 m, which is exactly how you should treat them */
  const now = Date.now();
  const live = FIXES.filter(f => now - f.t < FIX_TTL);
  if (!live.length) return null;
  const best = Math.min.apply(null, live.map(f => f.acc));
  const use = live.filter(f => f.acc <= Math.max(best * 2.5, best + 8));
  let wsum = 0, la = 0, lo = 0;
  use.forEach(f => { const w = 1 / (f.acc * f.acc); wsum += w; la += f.lat * w; lo += f.lng * w; });
  if (!wsum) return null;
  /* honest error estimate: averaging n independent samples would give
     best/sqrt(n), but GNSS errors are correlated over short spans, so we never
     claim better than 60% of the best single fix */
  const acc = Math.max(best * 0.6, best / Math.sqrt(use.length));
  return { lat: la / wsum, lng: lo / wsum, acc: Math.round(acc * 10) / 10, n: use.length };
}

function applyFix(quiet){
  if (ME && ME.pinned) return;
  const f = fuse();
  if (!f) return;
  const first = !ME;
  const moved = ME ? metres(ME.lat, ME.lng, f.lat, f.lng) : 1e9;
  ME = { lat: f.lat, lng: f.lng, acc: f.acc, n: f.n };
  drawMe();
  updateAccBox(); paintChip();
  if (first || !inView(ME.lat, ME.lng)) setView(ME, Math.max(17, curZoom()));
  const need = lastStopFetch
    ? metres(lastStopFetch.lat, lastStopFetch.lng, ME.lat, ME.lng) : 1e9;
  if (need > 35 || !STOPS.length) loadStops();
  else if (!quiet) hud(stopsLine());
}
function curZoom(){ const v = currentView(); return v && v.zoom ? v.zoom : 17; }

function startBurst(ms){
  if (!navigator.geolocation) { hud("This browser has no location service."); return; }
  burstEnd = Math.max(burstEnd, Date.now() + ms);
  if (watchId !== null) return;
  hud("Finding you…", true);
  watchId = navigator.geolocation.watchPosition(p => {
    const acc = p.coords.accuracy == null ? 999 : p.coords.accuracy;
    if (acc > 300) return;                       // a cell-tower guess, not a fix
    FIXES.push({ lat: p.coords.latitude, lng: p.coords.longitude, acc: acc, t: Date.now() });
    if (FIXES.length > 40) FIXES.shift();
    applyFix(true);
    const f = fuse();
    if (f) hud("Within <b>±" + Math.round(f.acc) + " m</b>" +
      (STOPS.length ? " · " + STOPS.length + " stations near you" : "") +
      ". Tap <b>DASHBOARD</b>.");
    /* good enough, and settled: stop burning the GNSS chip */
    if (f && f.acc <= 8 && f.n >= 4 && Date.now() > burstEnd - ms + 6000) stopBurst();
  }, err => {
    stopBurst();
    if (err && err.code === 1)
      hud("Location refused. Pan the map to where you are, or pin yourself in ⚙.");
    else hud("No position yet. ⚙ → Position has ways to help.");
    if (!STOPS.length) loadStops();
  }, { enableHighAccuracy: true, maximumAge: 0, timeout: ms });
  /* a repeating check, not a one-shot: a burst can be extended by another
     foreground event, and a single timer would fire early and leave the GNSS
     chip running for the rest of the day */
  if (burstTick === null) burstTick = setInterval(() => {
    if (watchId === null || Date.now() >= burstEnd) {
      clearInterval(burstTick); burstTick = null; stopBurst();
    }
  }, 1000);
}
function stopBurst(){
  if (watchId !== null) { try { navigator.geolocation.clearWatch(watchId); } catch (e) {} }
  watchId = null;
  if (burstTick !== null) { clearInterval(burstTick); burstTick = null; }
  paintChip(); loadGps(false);
  updateAccBox();
}
function autoLocate(force){
  if (ME && ME.pinned) return;
  const now = Date.now();
  if (!force && now - lastFix < 8000) return;
  lastFix = now;
  startBurst(force ? 30000 : 18000);
}
function sharpen(){
  if (ME && ME.pinned) { hud("You are pinned by hand. Unpin in ⚙ first."); return; }
  FIXES = [];
  hud("Hold still — collecting satellites for 30 seconds…", true);
  startBurst(30000);
}

/* ---------------- the stations ---------------- */
function anchor(){
  if (ME) return { lat: ME.lat, lng: ME.lng };
  const v = currentView();
  return { lat: v.lat, lng: v.lng };
}
function assignColours(list){
  /* nearest first gets first pick, but a station keeps the colour it already
     had if that colour is still free. Walking past a stop must not repaint the
     whole map. */
  const taken = new Set(), next = {};
  list.forEach(s => {
    const had = COLOUR[s.stop_id];
    if (had && !taken.has(had)) { next[s.stop_id] = had; taken.add(had); }
  });
  list.forEach(s => {
    if (next[s.stop_id]) return;
    const free = PALETTE.find(c => !taken.has(c)) ||
      PALETTE[Object.keys(next).length % PALETTE.length];
    next[s.stop_id] = free; taken.add(free);
  });
  COLOUR = next;
}
function stopsLine(){
  const n = STOPS.length;
  if (!n) return "No station within <b>" + fmtDist(RADIUS) + "</b>.";
  return "<b>" + n + "</b> station" + (n === 1 ? "" : "s") + " within <b>" +
    fmtDist(STOPS[STOPS.length - 1].dist) + "</b>. Tap <b>DASHBOARD</b>, or tap a star.";
}
async function loadStops(){
  if (!INDEX_OK) return;
  const at = anchor();
  lastStopFetch = at;
  hud("Reading the stations around you…", true);
  try {
    let d = await fetch("stops?lat=" + at.lat + "&lon=" + at.lng + "&r=" + RADIUS + "&widen=0",
      { cache: "no-store" }).then(r => r.json());
    let widened = false;
    if (d.ok && !(d.stops || []).length) {
      d = await fetch("stops?lat=" + at.lat + "&lon=" + at.lng + "&r=" + RADIUS + "&widen=1",
        { cache: "no-store" }).then(r => r.json());
      widened = true;
    }
    if (!d.ok) { hud("Server said: " + esc(d.reason || "no reason given")); return; }
    STOPS = (d.stops || []).slice(0, 8);
    assignColours(STOPS);
    drawStars();
    if (!STOPS.length) hud("No station anywhere near. Try the radius in ⚙.");
    else if (widened) hud("Nothing within <b>" + fmtDist(RADIUS) +
      "</b>, so this reaches out to <b>" + fmtDist(STOPS[STOPS.length - 1].dist) + "</b>.");
    else hud(stopsLine());
    refreshBoards();
  } catch (e) {
    hud("Could not reach the server: " + esc(e.message || e));
  }
}

/* ---------------- the boards ---------------- */
function isWatched(id){ return !!(WATCH && WATCH.stop_id === id); }
async function fetchBoard(s){
  try {
    const d = await fetch("board?stop=" + encodeURIComponent(s.stop_id) +
      "&mins=60&back=10", { cache: "no-store" }).then(r => r.json());
    if (d.ok) BOARDS[s.stop_id] = d;
  } catch (e) { /* keep whatever we had */ }
}
async function refreshBoards(){
  if (!STOPS.length) return;
  /* the first warms the server's realtime cache, the rest ride behind it
     instead of all reaching for the feed at the same moment */
  await fetchBoard(STOPS[0]);
  await Promise.all(STOPS.slice(1).map(fetchBoard));
  if (document.getElementById("dash").classList.contains("show")) renderDash();
  updateWatchBar();
}
function comingAt(id){
  const b = BOARDS[id];
  return b ? (b.departures || []).filter(x => !x.passed) : [];
}

/* ---------------- the still photograph ---------------- */
async function streetView(s){
  if (s.stop_id in SV_CACHE) return SV_CACHE[s.stop_id];
  if (!API_KEY) { SV_CACHE[s.stop_id] = null; return null; }
  const loc = s.lat + "," + s.lon;
  const head = s.bearing == null ? "" : "&heading=" + Math.round(s.bearing);
  const url = "https://maps.googleapis.com/maps/api/streetview?size=640x260&location=" +
    loc + "&fov=80&pitch=2" + head + "&return_error_code=true&key=" + encodeURIComponent(API_KEY);
  try {
    const meta = await fetch("https://maps.googleapis.com/maps/api/streetview/metadata?location=" +
      loc + "&key=" + encodeURIComponent(API_KEY)).then(r => r.json());
    SV_CACHE[s.stop_id] = meta && meta.status === "OK" ? url : null;
  } catch (e) {
    SV_CACHE[s.stop_id] = url;      // metadata blocked; show it and let it try
  }
  return SV_CACHE[s.stop_id];
}

/* ---------------- the 360 view ----------------
   The card photo is a still because four live panoramas in a scrolling list
   would fight your finger and cost four panorama loads. Tap it and you get
   the real thing, full screen, turning under your thumb. */
let pano = null, panoGyro = false;
async function openPano(id){
  const s = STOPS.find(x => x.stop_id === id);
  if (!s) return;
  const box = document.getElementById("pano");
  const el = document.getElementById("panoView");
  document.getElementById("panoName").textContent = s.name;
  const hint = document.getElementById("panoHint");
  hint.textContent = "drag to look around";
  hint.style.opacity = "1";
  box.classList.add("show");
  if (!API_KEY) {
    el.innerHTML = '<div class="panomsg">The 360° view needs a Google key.<br>' +
      '⚙ → Load key from file.</div>';
    return;
  }
  el.innerHTML = '<div class="panomsg">Opening the street…</div>';
  let g;
  try { g = await loadGoogle(); }
  catch (e) {
    el.innerHTML = '<div class="panomsg">Could not open the 360° view:<br>' +
      esc(e.message) + '</div>';
    return;
  }
  new g.maps.StreetViewService().getPanorama(
    { location: { lat: s.lat, lng: s.lon }, radius: 70 },
    (data, status) => {
      if (status !== "OK" || !data || !data.location) {
        el.innerHTML = '<div class="panomsg">No Street View imagery at this stop.</div>';
        return;
      }
      el.innerHTML = "";
      panoGyro = false;
      document.getElementById("panoMotion").classList.remove("on");
      pano = new g.maps.StreetViewPanorama(el, {
        pano: data.location.pano,
        pov: { heading: s.bearing == null ? 0 : s.bearing, pitch: 0 },
        zoom: 0,
        addressControl: false, fullscreenControl: false, zoomControl: false,
        panControl: false, motionTracking: false, motionTrackingControl: false,
        linksControl: true, enableCloseButton: false, showRoadLabels: true,
      });
      setTimeout(() => { document.getElementById("panoHint").style.opacity = "0"; }, 4000);
    });
}
function closePano(){
  document.getElementById("pano").classList.remove("show");
  /* let go of the panorama so it is not left running behind the map */
  if (pano) { try { pano.setVisible(false); } catch (e) {} pano = null; }
  document.getElementById("panoView").innerHTML = "";
}
document.getElementById("panoClose").addEventListener("click", closePano);
document.getElementById("panoMotion").addEventListener("click", () => {
  if (!pano) return;
  panoGyro = !panoGyro;
  try { pano.setOptions({ motionTracking: panoGyro }); }
  catch (e) { panoGyro = false; }
  document.getElementById("panoMotion").classList.toggle("on", panoGyro);
  document.getElementById("panoHint").style.opacity = "1";
  document.getElementById("panoHint").textContent = panoGyro
    ? "turn the phone to look around" : "drag to look around";
  setTimeout(() => { document.getElementById("panoHint").style.opacity = "0"; }, 3500);
});

/* ---------------- the dashboard ---------------- */
function delayBit(x){
  if (!x.live || x.delay == null) return "";
  if (Math.abs(x.delay) < 30) return ' · <span class="d ok">on time</span>';
  const m = Math.round(Math.abs(x.delay) / 60);
  return ' · <span class="d ' + (x.delay > 0 ? "late" : "ok") + '">' +
    (x.delay > 0 ? "+" : "−") + (m < 1 ? "<1" : m) + " min</span>";
}
const PTAG = '<span class="ptag">printed</span>';
function arrivalRow(x){
  const t = x.live && x.live_at
    ? new Date(x.live_at * 1000).toTimeString().slice(0, 5) : x.sched;
  const cls = x.passed ? "" : (x.mins <= 0 ? "now" : (x.mins <= 5 ? "soon" : ""));
  /* one that has already gone counts backwards: 6 left three minutes ago */
  const big = x.passed ? "−" + Math.abs(x.mins) : (x.mins <= 0 ? "now" : x.mins);
  const unit = x.passed ? "min ago" : (x.mins <= 0 ? "" : "min");
  const from = x.origin ? '<span class="from">' + esc(x.origin) + "</span> → " : "";
  const mark = x.printed ? PTAG : (x.live ? WIFI : "");
  return '<div class="arow' + (x.printed ? " printed" : "") + '">' +
    '<span class="rt' + (x.live ? "" : " sched") + '" style="--r:' +
      routeColour(x.route) + '">' + esc(x.route) + '</span>' +
    '<span class="od">' + from + esc(x.head || "—") +
      '<i>' + t + mark + delayBit(x) + '</i></span>' +
    '<span class="tm"><b class="' + cls + '">' + big + '</b>' +
      '<small>' + unit + '</small></span>' +
    '</div>';
}
function subLine(s, b){
  const ab = dirAbbr(s.bearing);
  let extra = "";
  if (b && b.printed) extra += " · " + b.printed + " from the printed timetable";
  else if (b && b.index_stale) extra += " · index is from " + (b.service_date || "another day");
  if (b && !b.feed_ok) extra += " · live feed down";
  return fmtDist(s.dist) + " away" + (ab ? " · vehicles head " + ab : "") + extra;
}
function arrHTML(s){
  const rows = comingAt(s.stop_id).slice(0, 6);
  const b = BOARDS[s.stop_id];
  return rows.length ? rows.map(arrivalRow).join("")
    : '<div class="empty">' + (b ? "Nothing in the next hour." : "Reading the feeds…") + '</div>';
}
function photoHTML(s){
  const sv = SV_CACHE[s.stop_id];
  if (sv === undefined) return '<div class="svnone">Loading the photograph…</div>';
  if (!sv) return '<div class="svnone">' + (API_KEY
    ? "No Street View photograph here."
    : "Add a Google key in ⚙ to see the stop.") + '</div>';
  return '<span class="svwrap" data-pano="' + esc(s.stop_id) + '">' +
    '<img class="sv" src="' + esc(sv) + '" alt="' + esc(s.name) + '" loading="lazy"' +
    ' onerror="this.style.display=\'none\'">' +
    '<span class="sv360">◉ 360°</span></span>';
}
function cardHTML(s){
  const c = COLOUR[s.stop_id], on = isWatched(s.stop_id), b = BOARDS[s.stop_id];
  return '<div class="card' + (on ? " on" : "") + '" style="--c:' + c + '" id="card-' +
      esc(s.stop_id) + '">' +
    '<div class="chead">' + starHTML(c, false, true) +
      '<span class="nm">' + esc(s.name) + '<i>' + esc(subLine(s, b)) + '</i></span>' +
      '<button class="wbtn' + (on ? " on" : "") + '" data-watch="' + esc(s.stop_id) + '">' +
        (on ? "WATCHING" : "WATCH") + '</button>' +
    '</div>' + photoHTML(s) +
    '<div class="arr">' + arrHTML(s) + '</div></div>';
}
let DASH_SIG = "";
function renderDash(){
  const body = document.getElementById("dBody");
  const sub = document.getElementById("dSub");
  if (!STOPS.length) {
    DASH_SIG = "";
    sub.textContent = "—";
    body.innerHTML = '<div class="empty">' + (INDEX_OK
      ? "No station within reach yet. Give it a moment, or widen the radius in ⚙."
      : "The station index is still building.") + '</div>';
    return;
  }
  const feedOk = STOPS.some(s => BOARDS[s.stop_id] && BOARDS[s.stop_id].feed_ok);
  sub.innerHTML = STOPS.length + " station" + (STOPS.length === 1 ? "" : "s") +
    " within " + fmtDist(STOPS[STOPS.length - 1].dist) +
    (feedOk ? " · live" : " · schedule only");
  /* rebuilt only when the stations, their photographs or the watched one
     change — a twenty-second refresh must not reload the pictures or throw
     your scroll back to the top */
  const sig = STOPS.map(s => s.stop_id + ":" + COLOUR[s.stop_id] +
      (s.stop_id in SV_CACHE ? (SV_CACHE[s.stop_id] ? "p" : "n") : "?")).join("|") +
    "#" + (WATCH ? WATCH.stop_id : "");
  if (sig !== DASH_SIG) {
    DASH_SIG = sig;
    const keep = body.scrollTop;
    body.innerHTML = STOPS.map(cardHTML).join("");
    body.scrollTop = keep;
    return;
  }
  STOPS.forEach(s => {
    const card = document.getElementById("card-" + s.stop_id);
    if (!card) return;
    const arr = card.querySelector(".arr");
    if (arr) arr.innerHTML = arrHTML(s);
    const i = card.querySelector(".chead .nm i");
    if (i) i.textContent = subLine(s, BOARDS[s.stop_id]);
  });
}
async function loadPhotos(){
  const todo = STOPS.filter(s => !(s.stop_id in SV_CACHE));
  if (!todo.length) return;
  await Promise.all(todo.map(streetView));
  if (document.getElementById("dash").classList.contains("show")) renderDash();
}
function openDash(focusId){
  document.getElementById("dash").classList.add("show");
  renderDash(); loadPhotos(); refreshBoards();
  if (!boardTimer) boardTimer = setInterval(refreshBoards, 20000);
  if (focusId) requestAnimationFrame(() => {
    const el = document.getElementById("card-" + focusId);
    if (el) el.scrollIntoView({ block: "start", behavior: "smooth" });
  });
}
function closeDash(){
  document.getElementById("dash").classList.remove("show");
  if (boardTimer && !WATCH) { clearInterval(boardTimer); boardTimer = null; }
}
document.getElementById("dashBtn").addEventListener("click", () => openDash(WATCH ? WATCH.stop_id : null));
document.getElementById("dClose").addEventListener("click", closeDash);
document.getElementById("dBody").addEventListener("click", (e) => {
  const w = e.target.closest("[data-watch]");
  if (w) { toggleWatch(w.dataset.watch); return; }
  const p = e.target.closest("[data-pano]");
  if (p) { openPano(p.dataset.pano); return; }
});

/* ---------------- watching one station ---------------- */
function toggleWatch(id){
  if (isWatched(id)) { clearWatch(); return; }
  const s = STOPS.find(x => x.stop_id === id);
  if (!s) return;
  WATCH = { stop_id: s.stop_id, name: s.name, lat: s.lat, lon: s.lon };
  LS.set("watch", WATCH);
  document.body.classList.add("watching");
  document.getElementById("dashBtn").classList.add("hasbar");
  drawStars(); updateWatchBar(); renderDash();
  if (!boardTimer) boardTimer = setInterval(refreshBoards, 20000);
  hud("Watching <b>" + esc(s.name) + "</b>. Its star is ringed on the map.");
}
function clearWatch(){
  WATCH = null; LS.del("watch");
  document.body.classList.remove("watching");
  document.getElementById("dashBtn").classList.remove("hasbar");
  drawStars(); renderDash();
}
function updateWatchBar(){
  if (!WATCH) return;
  const c = COLOUR[WATCH.stop_id] || PALETTE[0];
  const bar = document.getElementById("watchbar");
  bar.style.setProperty("--c", c);
  const st = document.getElementById("wbStar");
  if (st) st.outerHTML = starHTML(c, false, true)
    .replace('class="star mini"', 'class="star mini" id="wbStar"');
  document.getElementById("wbName").textContent = WATCH.name;
  const next = comingAt(WATCH.stop_id)[0];
  document.getElementById("wbEta").innerHTML = next
    ? '<span class="rt sm' + (next.live ? "" : " sched") + '" style="--r:' +
      routeColour(next.route) + '">' + esc(next.route) + '</span> ' +
      (next.mins <= 0 ? "now" : next.mins + " min") + (next.live ? WIFI : "")
    : "—";
}
document.getElementById("watchbar").addEventListener("click", (e) => {
  if (e.target.closest("#wbX")) { clearWatch(); return; }
  openDash(WATCH ? WATCH.stop_id : null);
});

/* ---------------- settings ---------------- */
function setDot(ok){ document.getElementById("keyDot").className = "dot " + (ok ? "ok" : ""); }
function renderLayers(){
  const detail = ENGINE === "detail";
  document.getElementById("engFree").classList.toggle("on", !detail);
  document.getElementById("engDetail").classList.toggle("on", detail);
  document.getElementById("layerBox").innerHTML = LAYER_DEFS.map((d, i) => {
    const avail = d.lock || !d.google || detail;
    let note = d.note, on = d.lock ? true : !!LAYERS[d.id];
    if (!avail) {
      note = "detailed map only";
      if (d.id === "places") { note = "comes with street names on the free map"; on = !!LAYERS.streets; }
    }
    return '<div class="lrow' + (avail ? "" : " off") + (i < 2 ? " heavy" : "") +
      '" data-layer="' + d.id + '">' +
      '<span class="lnum">' + (i + 1) + '</span>' +
      '<span class="lname">' + esc(d.name) + '<i>' + esc(note) + '</i></span>' +
      (d.lock ? '<span class="llock">always</span>'
              : '<span class="lsw' + (on ? " on" : "") + '"></span>') +
      '</div>';
  }).join("");
  document.getElementById("layerNote").innerHTML = detail
    ? "Google's map, taken apart layer by layer. Turn off what you do not need — " +
      "the fewer layers, the faster it is to read a stop at a glance."
    : "Free tiles are pre-drawn pictures, so street names and district names come " +
      "as one layer and there are no shops in them at all. For real control over " +
      "every layer, switch to the detailed map.";
}
document.getElementById("layerBox").addEventListener("click", (e) => {
  const row = e.target.closest("[data-layer]");
  if (!row) return;
  const id = row.dataset.layer;
  const def = LAYER_DEFS.find(d => d.id === id);
  if (!def || def.lock) return;
  if (def.google && ENGINE !== "detail") {
    hud("That layer lives on the detailed map.");
    document.getElementById("layerNote").textContent =
      "“" + def.name + "” needs the detailed map. Switch it on above.";
    return;
  }
  LAYERS[id] = !LAYERS[id];
  applyLayers(); renderLayers();
});
document.getElementById("engFree").addEventListener("click", () => setEngine("free"));
document.getElementById("engDetail").addEventListener("click", () => setEngine("detail"));

document.getElementById("btnSetup").addEventListener("click", () => {
  document.getElementById("setup").classList.add("show");
  document.getElementById("rLbl").textContent = fmtDist(RADIUS);
  renderLayers(); loadStatus(); updateAccBox();
  loadGemStatus().then(() => { loadSched(); loadModelState(); });
});
document.getElementById("sClose").addEventListener("click", () =>
  document.getElementById("setup").classList.remove("show"));
document.getElementById("keyFile").addEventListener("change", async (e) => {
  const msg = document.getElementById("keyMsg");
  const f = e.target.files && e.target.files[0]; if (!f) return;
  const text = (await f.text()).trim(); e.target.value = "";
  if (!text) { msg.textContent = "Empty file."; return; }
  msg.textContent = "Saving…";
  try {
    const d = await fetch("api-keys", { method: "POST", body: text }).then(r => r.json());
    if (d.ok) {
      API_KEY = d.keys[0]; setDot(true);
      msg.textContent = "Saved. The 360° view and the detailed map are open to you now.";
      Object.keys(SV_CACHE).forEach(k => delete SV_CACHE[k]);
      gPromise = null;
      loadPhotos(); renderLayers();
    } else msg.textContent = "Could not save the key.";
  } catch (err) { msg.textContent = "Could not save the key."; }
});
function stepRadius(dir){
  let i = RSTEPS.indexOf(RADIUS); if (i < 0) i = 1;
  i = Math.max(0, Math.min(RSTEPS.length - 1, i + dir));
  RADIUS = RSTEPS[i]; LS.set("radius", RADIUS);
  document.getElementById("rLbl").textContent = fmtDist(RADIUS);
  drawMe(); loadStops();
}
document.getElementById("rPlus").addEventListener("click", () => stepRadius(1));
document.getElementById("rMinus").addEventListener("click", () => stepRadius(-1));

async function loadStatus(){
  try {
    const d = await fetch("status", { cache: "no-store" }).then(r => r.json());
    document.getElementById("statBox").innerHTML =
      '<div class="kv"><span>Stations</span><b>' + (d.ok ? "cached" : "not cached") + '</b></div>' +
      '<div class="kv"><span>Schedule day</span><b>' + (d.service_date || "—") + '</b></div>' +
      '<div class="kv"><span>Stops</span><b>' + (d.stops || "—") + '</b></div>' +
      '<div class="kv"><span>Live feed</span><b>' +
        (d.feed_ok ? d.feed_trips + " vehicles" : "unreachable") + '</b></div>';
  } catch (e) {
    document.getElementById("statBox").innerHTML =
      '<span class="note">Could not read the status.</span>';
  }
}
document.getElementById("cacheBtn").addEventListener("click", () => {
  const msg = document.getElementById("cacheMsg");
  msg.textContent = "Caching the whole network from ZET, this runs once…";
  fetch("rebuild?force=1", { cache: "no-store" }).catch(() => {});
  const poll = setInterval(async () => {
    let d = {};
    try { d = await fetch("status", { cache: "no-store" }).then(r => r.json()); } catch (e) { return; }
    loadStatus();
    if (d.ok) {
      clearInterval(poll);
      msg.textContent = "Cached " + (d.stops || "?") + " stations.";
      INDEX_OK = true; loadStops();
    }
  }, 3000);
});



/* =========================================================================
   GOOGLE STATION VIEW
   Google already draws every tram and bus stop, and draws them better than we
   would. In this view we add nothing to the map at all -- we just listen for a
   tap on one of its icons, work out which GTFS stop it is, and put a ring
   round it. The ring is hollow so the icon still shows through.
   ========================================================================= */
let SEL = null;          // the stop whose window is open
let selMk = null, lSel = null;   // the ring, one per engine
let popTimer = null;

function stationColour(id){
  if (COLOUR[id]) return COLOUR[id];
  let n = 0;
  for (let i = 0; i < String(id).length; i++) n = (n * 33 + String(id).charCodeAt(i)) >>> 0;
  return PALETTE[n % PALETTE.length];
}
function clearSel(){
  if (selMk) { try { selMk.setMap(null); } catch (e) {} selMk = null; }
  if (lSel) { try { map.removeLayer(lSel); } catch (e) {} lSel = null; }
}
function markSel(s){
  clearSel();
  if (!s) return;
  const c = stationColour(s.stop_id);
  const html = '<div class="selring" style="--c:' + c + '">' +
    '<i class="core"></i><i class="w1"></i><i class="w2"></i><i class="w3"></i></div>';
  if (usingGoogle()) {
    selMk = new HtmlMarker({ lat: s.lat, lng: s.lon }, html, null, 400);
    selMk.setMap(gmap);
  } else {
    lSel = L.marker([s.lat, s.lon], {
      icon: L.divIcon({ html, className: "starwrap", iconSize: [46, 46], iconAnchor: [23, 23] }),
      interactive: false, zIndexOffset: 400 }).addTo(map);
  }
}

/* A tap on one of Google's icons gives a place id and a point, never a GTFS
   id, so we ask our own index what is standing there. A tap on bare map is
   allowed too but has to be much closer, otherwise panning around would keep
   opening stations you did not mean. */
async function onMapClick(e){
  const onIcon = !!(e && e.placeId);
  if (onIcon && e.stop) e.stop();          // no Google info window, this is ours
  const ll = e && e.latLng;
  if (!ll) return;
  if (PINMODE) { pinAt(ll.lat(), ll.lng()); return; }
  if (MODE !== "google") return;
  const lat = ll.lat(), lng = ll.lng();
  const r = onIcon ? 90 : 40;
  try {
    const d = await fetch("stops?lat=" + lat + "&lon=" + lng + "&r=" + r + "&widen=0",
      { cache: "no-store" }).then(x => x.json());
    const st = (d.stops || [])[0];
    if (!st) { if (!onIcon) closePop(); else hud("No ZET stop registered at that icon."); return; }
    openPop(st);
  } catch (err) { hud("Could not reach the server: " + esc(err.message || err)); }
}

/* ---------------- the station window ---------------- */
async function openPop(stop){
  SEL = stop;
  const c = stationColour(stop.stop_id);
  const wrap = document.getElementById("popwrap");
  document.getElementById("pop").style.setProperty("--c", c);
  document.getElementById("popId").textContent = stop.stop_id;
  const ab = dirAbbr(stop.bearing);
  const bits = [];
  if (stop.dist != null) bits.push(fmtDist(stop.dist) + " away");
  if (ab) bits.push("vehicles head " + ab);
  document.getElementById("popNm").innerHTML =
    esc(stop.name) + '<i id="popSub">' + esc(bits.join(" · ")) + '</i>';
  document.getElementById("popBody").innerHTML =
    '<div class="empty">Reading the board…</div>';
  document.getElementById("popWatch").textContent =
    isWatched(stop.stop_id) ? "WATCHING" : "WATCH THIS STOP";
  wrap.classList.add("show");
  markSel(stop);
  await refreshPop();
  if (popTimer) clearInterval(popTimer);
  popTimer = setInterval(refreshPop, 20000);
}
async function refreshPop(){
  if (!SEL) return;
  let b = null;
  try {
    b = await fetch("board?stop=" + encodeURIComponent(SEL.stop_id) +
      "&mins=60&back=10", { cache: "no-store" }).then(r => r.json());
  } catch (e) { return; }
  if (!SEL || !b || !b.ok) return;
  BOARDS[SEL.stop_id] = b;
  const all = b.departures || [];
  const gone = all.filter(x => x.passed).slice(-4);
  const coming = all.filter(x => !x.passed).slice(0, 8);
  let html = "";
  if (gone.length) html += '<div class="popsec">just left</div>' +
    gone.map(x => arrivalRow(x).replace('class="arow', 'class="arow gone')).join("");
  html += '<div class="popsec">coming</div>' + (coming.length
    ? coming.map(arrivalRow).join("")
    : '<div class="empty">Nothing in the next hour.</div>');
  const notes = [];
  if (b.printed) notes.push(b.printed + " from the printed timetable");
  else if (b.index_stale) notes.push("index is from " + (b.service_date || "another day"));
  if (!b.feed_ok) notes.push("live feed down");
  if (notes.length) html += '<div class="empty">' + esc(notes.join(" · ")) + '</div>';
  document.getElementById("popBody").innerHTML = html;
}
function closePop(){
  SEL = null;
  document.getElementById("popwrap").classList.remove("show");
  if (popTimer) { clearInterval(popTimer); popTimer = null; }
  clearSel();
}
document.getElementById("popX").addEventListener("click", closePop);
document.getElementById("popwrap").addEventListener("click", (e) => {
  if (e.target.id === "popwrap") closePop();
});
document.getElementById("popAll").addEventListener("click", () => { closePop(); openDash(); });
document.getElementById("popWatch").addEventListener("click", () => {
  if (!SEL) return;
  const s = SEL;
  if (isWatched(s.stop_id)) { clearWatch(); }
  else {
    WATCH = { stop_id: s.stop_id, name: s.name, lat: s.lat, lon: s.lon };
    LS.set("watch", WATCH);
    document.body.classList.add("watching");
    document.getElementById("dashBtn").classList.add("hasbar");
    if (!COLOUR[s.stop_id]) COLOUR[s.stop_id] = stationColour(s.stop_id);
    drawStars(); updateWatchBar();
    if (!boardTimer) boardTimer = setInterval(refreshBoards, 20000);
  }
  document.getElementById("popWatch").textContent =
    isWatched(s.stop_id) ? "WATCHING" : "WATCH THIS STOP";
});

/* ---------------- the view switch ---------------- */
async function setMode(m, quiet){
  if (m === "google") {
    if (!API_KEY) {
      hud("Google station view needs a Google key. ⚙ → Load key from file.");
      paintMode(); return;
    }
    const ok = await setEngine("detail", true);
    if (!ok) { MODE = "stars"; LS.set("mode", MODE); paintMode(); return; }
    MODE = "google"; LS.set("mode", MODE);
    applyLayers(); drawStars(); paintMode();
    if (!quiet) hud("Tap any station Google draws to see what is coming.");
  } else {
    MODE = "stars"; LS.set("mode", MODE);
    closePop();
    applyLayers(); drawStars(); paintMode();
    if (!quiet) hud(stopsLine());
  }
}
function paintMode(){
  document.getElementById("viewStars").classList.toggle("on", MODE !== "google");
  document.getElementById("viewGoogle").classList.toggle("on", MODE === "google");
}
document.getElementById("viewStars").addEventListener("click", () => setMode("stars"));
document.getElementById("viewGoogle").addEventListener("click", () => setMode("google"));
document.getElementById("segStar").setAttribute("points", STAR_PTS);


/* ---------------- position readout, sharpening, and pinning ---------------- */
let PINMODE = false;
function updateAccBox(){
  const box = document.getElementById("posBox");
  if (!box) return;
  const dot = document.getElementById("posDot");
  if (!ME) {
    box.innerHTML = '<span class="note">No fix yet.</span>';
    dot.className = "dot"; return;
  }
  if (ME.pinned) {
    box.innerHTML = '<div class="kv"><span>Source</span><b>pinned by hand</b></div>' +
      '<div class="kv"><span>Position</span><b>' + ME.lat.toFixed(5) + ", " +
      ME.lng.toFixed(5) + '</b></div>' + providerRows();
    dot.className = "dot ok"; return;
  }
  const a = ME.acc || 0;
  const grade = a <= 8 ? "good" : (a <= 20 ? "usable" : "loose");
  box.innerHTML =
    '<div class="kv"><span>Accuracy</span><b>±' + Math.round(a) + " m · " + grade + '</b></div>' +
    '<div class="kv"><span>Fixes averaged</span><b>' + (ME.n || 1) + '</b></div>' +
    '<div class="kv"><span>Listening</span><b>' + (watchId !== null ? "yes" : "idle") + '</b></div>' +
    '<div class="kv"><span>Position</span><b>' + ME.lat.toFixed(5) + ", " + ME.lng.toFixed(5) + '</b></div>';
  dot.className = "dot " + (a <= 20 ? "ok" : "");
  box.innerHTML += providerRows();
}
document.getElementById("posProv").addEventListener("click", async () => {
  document.getElementById("posMsg").textContent = "Asking Android for a fresh fix from each provider…";
  await loadGps(true);
  document.getElementById("posMsg").textContent = GPSINFO && GPSINFO.termux
    ? "Android answered." : "Termux:API is not installed.";
});
document.getElementById("posSharpen").addEventListener("click", () => {
  document.getElementById("setup").classList.remove("show");
  sharpen();
});
document.getElementById("posPin").addEventListener("click", () => {
  if (ME && ME.pinned) {
    ME.pinned = false; FIXES = [];
    document.getElementById("posMsg").textContent = "Back to the satellites.";
    drawMe(); updateAccBox(); autoLocate(true);
    return;
  }
  PINMODE = true;
  document.getElementById("setup").classList.remove("show");
  hud("Tap the map where you actually are.");
});
function pinAt(lat, lng){
  PINMODE = false;
  stopBurst();
  ME = { lat: lat, lng: lng, acc: 0, n: 0, pinned: true };
  drawMe(); updateAccBox(); paintChip();
  const el = document.getElementById("posMsg");
  if (el) el.textContent = "Pinned. Tap the same button again to go back to the satellites.";
  hud("Pinned by hand. Nothing is guessing any more.");
  lastStopFetch = null;
  loadStops();
}


/* ---------------- the live fix readout ----------------
   Accuracy comes from the browser and is always there. Which provider answered
   comes from Android through Termux:API, because the Geolocation API simply
   does not carry that field. Satellite count is in neither: it lives in
   GnssStatus, a native API no web page and no Termux tool can reach, so the
   panel says so rather than showing an invented number. */
let GPSINFO = null, gpsPoll = null;

function accGrade(a){
  if (a == null) return "";
  return a <= 8 ? "good" : (a <= 20 ? "ok" : "weak");
}
function srcLabel(){
  if (ME && ME.pinned) return "pinned by hand";
  if (!GPSINFO || !GPSINFO.termux) {
    /* no Termux:API, so infer from the accuracy. A phone that says 8 m is on
       satellites; one that says 60 m is triangulating masts and wifi. */
    if (!ME) return "looking…";
    return ME.acc <= 20 ? "satellites (likely)" : "wifi / cell (likely)";
  }
  if (GPSINFO.better === "gps") return "satellites";
  if (GPSINFO.better === "network") return "wifi / cell";
  return "no provider answered";
}
function paintChip(){
  const chip = document.getElementById("gpsChip");
  const a = ME && !ME.pinned ? ME.acc : null;
  chip.className = (ME && ME.pinned ? "" : accGrade(a)) + (watchId !== null ? " live" : "");
  document.getElementById("gpsAcc").textContent =
    ME ? (ME.pinned ? "pinned" : "±" + Math.round(a) + " m") : "—";
  document.getElementById("gpsSrc").textContent = srcLabel();
}
document.getElementById("gpsChip").addEventListener("click", () => {
  document.getElementById("setup").classList.add("show");
  document.getElementById("rLbl").textContent = fmtDist(RADIUS);
  renderLayers(); loadStatus(); updateAccBox(); loadGps(true);
  document.getElementById("posBox").scrollIntoView({ block: "center", behavior: "smooth" });
});
document.getElementById("btnLocate").addEventListener("click", () => {
  const b = document.getElementById("btnLocate");
  if (ME && ME.pinned) {
    setView(ME, Math.max(17, curZoom()));
    hud("You are pinned by hand. Unpin in ⚙ to use the satellites again.");
    return;
  }
  b.classList.add("busy");
  if (ME) setView(ME, Math.max(17, curZoom()));
  sharpen();
  setTimeout(() => b.classList.remove("busy"), 30000);
});

async function loadGps(fresh){
  try {
    GPSINFO = await fetch("gps" + (fresh ? "?fresh=1" : ""), { cache: "no-store" })
      .then(r => r.json());
  } catch (e) { GPSINFO = null; }
  paintChip(); updateAccBox();
}
function providerRows(){
  if (!GPSINFO) return '<div class="kv"><span>Provider</span><b>not read yet</b></div>';
  if (!GPSINFO.termux) return '<div class="kv"><span>Provider</span><b>' +
    esc(srcLabel()) + '</b></div>' +
    '<span class="note">Android will not tell a web page which provider answered. ' +
    'Install the <b>Termux:API</b> app and this becomes a straight answer instead ' +
    'of a guess from the accuracy figure.</span>';
  const one = (o, name) => {
    if (!o || !o.ok) return '<div class="kv"><span>' + name + '</span><b>' +
      esc((o && o.reason) || "no fix") + '</b></div>';
    const age = o.elapsedMs != null ? " · " + Math.round(o.elapsedMs / 1000) + " s old" : "";
    return '<div class="kv"><span>' + name + '</span><b>±' +
      (o.accuracy == null ? "?" : Math.round(o.accuracy)) + " m" + esc(age) + '</b></div>';
  };
  return one(GPSINFO.gps, "Satellites (GPS)") + one(GPSINFO.network, "Wifi / cell") +
    (GPSINFO.gap_m != null
      ? '<div class="kv"><span>They disagree by</span><b>' + GPSINFO.gap_m + ' m</b></div>'
      : "") +
    '<div class="kv"><span>Satellites in view</span><b>not available</b></div>';
}

/* ---------------- printed timetables ---------------- */
let GEM_OK = false;
function fmtAgo(ts){
  if (!ts) return "";
  const d = Math.floor((Date.now() / 1000 - ts) / 86400);
  return d <= 0 ? "today" : (d === 1 ? "yesterday" : d + " days ago");
}
async function loadSched(){
  let d = { items: [] };
  try { d = await fetch("sched-list", { cache: "no-store" }).then(r => r.json()); } catch (e) {}
  const items = d.items || [];
  const bad = items.filter(x => x.approx);
  document.getElementById("schedDot").className = "dot " + (items.length && !bad.length ? "ok" : "");
  document.getElementById("schedWarn").innerHTML = !GEM_OK
    ? '<div class="warnbox">No Gemini key, so the PDFs cannot be read properly. ' +
      'Anything stored without one is marked below and is never used on the board.</div>'
    : (bad.length
      ? '<div class="warnbox">' + bad.length + ' line' + (bad.length === 1 ? "" : "s") +
        ' stored before the key was added. Tap “Store the lines around me” to read ' +
        'them again properly.</div>'
      : "");
  document.getElementById("schedList").innerHTML = items.length
    ? items.map(x =>
        '<div class="srow"><span class="sr" style="--r:' + routeColour(x.route) + '">' +
        esc(x.route) + '</span><span class="sn">' +
        esc(x.name || (x.directions || []).filter(Boolean).join(" ⇄ ") || "line " + x.route) +
        '<i class="' + (x.approx ? "bad" : "") + '">' +
        (x.approx ? "unreadable without a key, not used"
                  : x.times + " times · " + (x.directions || []).length + " direction" +
                    ((x.directions || []).length === 1 ? "" : "s")) +
        " · stored " + fmtAgo(x.fetched) + '</i></span>' +
        '<button class="sx" data-sdel="' + esc(x.route) + '">✕</button></div>').join("")
    : '<span class="note">Nothing stored yet.</span>';
}
document.getElementById("schedList").addEventListener("click", async (e) => {
  const b = e.target.closest("[data-sdel]");
  if (!b) return;
  await fetch("sched-delete?route=" + encodeURIComponent(b.dataset.sdel)).catch(() => {});
  loadSched();
});
document.getElementById("schedAll").addEventListener("click", async () => {
  await fetch("sched-delete?all=1").catch(() => {});
  document.getElementById("schedMsg").textContent = "Cleared.";
  loadSched();
});
document.getElementById("schedNear").addEventListener("click", async () => {
  const msg = document.getElementById("schedMsg");
  const at = anchor();
  msg.textContent = "Reading the official timetables from ZET. One PDF per line, " +
    "then each one is thrown away…";
  try {
    const d = await fetch("sched-near?lat=" + at.lat + "&lon=" + at.lng +
      "&r=" + Math.max(RADIUS, 400) + "&force=1", { cache: "no-store" })
      .then(r => r.json());
    if (!d.ok) { msg.textContent = "Could not do it: " + esc(d.reason || "no reason given"); return; }
    const got = Object.values(d.routes || {});
    const good = got.filter(x => x.ok && !x.approx).length;
    const failed = got.filter(x => !x.ok).length;
    msg.textContent = good + " of " + got.length + " line" + (got.length === 1 ? "" : "s") +
      " stored properly" + (failed ? ", " + failed + " had no PDF published" : "") + ".";
  } catch (e) {
    msg.textContent = "Could not reach ZET: " + esc(e.message || e);
  }
  loadSched();
});
document.getElementById("gemFile").addEventListener("change", async (e) => {
  const msg = document.getElementById("gemMsg");
  const f = e.target.files && e.target.files[0]; if (!f) return;
  const text = (await f.text()).trim(); e.target.value = "";
  if (!text) { msg.textContent = "Empty file."; return; }
  msg.textContent = "Saving…";
  try {
    const d = await fetch("gemini-key", { method: "POST", body: text }).then(r => r.json());
    if (d.ok) { msg.textContent = "Saved."; GEM_OK = true;
                document.getElementById("gemDot").className = "dot ok"; loadSched(); }
    else msg.textContent = "Could not save the key.";
  } catch (err) { msg.textContent = "Could not save the key."; }
});
async function loadGemStatus(){
  try {
    const d = await fetch("gemini-key", { cache: "no-store" }).then(r => r.json());
    GEM_OK = !!d.set;
  } catch (e) { GEM_OK = false; }
  document.getElementById("gemDot").className = "dot " + (GEM_OK ? "ok" : "");
}


/* ---------------- key manager ----------------
   Three questions a key can answer: does it work, what can it call, and which
   of those should read the timetable PDFs. The choice is stored on the server,
   not here, because the PDFs are parsed server-side with no browser involved. */
function say(id, text, cls){
  const el = document.getElementById(id);
  el.className = "msg" + (cls ? " " + cls : "");
  el.innerHTML = text;
}
function fmtWhen(ts){
  if (!ts) return "never checked";
  const m = Math.floor((Date.now() / 1000 - ts) / 60);
  if (m < 1) return "just now";
  if (m < 60) return m + " min ago";
  const hrs = Math.floor(m / 60);
  return hrs < 24 ? hrs + " h ago" : Math.floor(hrs / 24) + " d ago";
}
function fillPicker(models, chosen, checked){
  const sel = document.getElementById("gemPick");
  sel.innerHTML = '<option value="">Automatic (' + esc(GEM_DEFAULT) + ')</option>' +
    (models || []).map(m =>
      '<option value="' + esc(m) + '"' + (m === chosen ? " selected" : "") + '>' +
      esc(m) + '</option>').join("");
  if (chosen && !(models || []).includes(chosen))
    sel.insertAdjacentHTML("beforeend",
      '<option value="' + esc(chosen) + '" selected>' + esc(chosen) + '</option>');
  sel.disabled = !GEM_OK;
  say("gemPickMsg", (models || []).length
    ? (models.length + " models this key can call · list " + fmtWhen(checked))
    : (GEM_OK ? "Tap “Check available models” to see what this key can call."
              : "Load a key first."));
}
let GEM_DEFAULT = "gemini-2.5-flash";
async function loadModelState(){
  try {
    const d = await fetch("gemini-model", { cache: "no-store" }).then(r => r.json());
    GEM_DEFAULT = d.default || GEM_DEFAULT;
    fillPicker(d.models, d.model, d.checked);
  } catch (e) { fillPicker([], "", 0); }
}
document.getElementById("gemPick").addEventListener("change", async (e) => {
  const v = e.target.value;
  say("gemPickMsg", "Saving…", "busy");
  try {
    const d = await fetch("gemini-model", { method: "POST", body: v }).then(r => r.json());
    if (d.ok) say("gemPickMsg", v ? "Timetable PDFs will be read by " + esc(v) + "."
                                  : "Back to automatic.", "good");
    else { say("gemPickMsg", esc(d.reason || "Could not save that."), "bad"); loadModelState(); }
  } catch (err) { say("gemPickMsg", "Could not save that.", "bad"); }
});
document.getElementById("gemRefresh").addEventListener("click", async () => {
  say("gemMsg", "Asking Google what this key can call…", "busy");
  try {
    const d = await fetch("gemini-models?force=1", { cache: "no-store" }).then(r => r.json());
    if (!d.ok) { say("gemMsg", esc(d.reason || "Could not read the list."), "bad"); return; }
    say("gemMsg", d.models.length + " models available to this key.", "good");
    loadModelState();
  } catch (e) { say("gemMsg", "Could not reach Google.", "bad"); }
});
document.getElementById("gemTest").addEventListener("click", async () => {
  say("gemMsg", "Asking the model a one-word question…", "busy");
  try {
    const d = await fetch("gemini-test", { cache: "no-store" }).then(r => r.json());
    if (d.ok) {
      GEM_OK = true;
      document.getElementById("gemDot").className = "dot ok";
      say("gemMsg", "Working — " + esc(d.model) + " answered in " + d.ms + " ms.", "good");
      loadSched();
    } else say("gemMsg", esc(d.reason || "No answer."), "bad");
  } catch (e) { say("gemMsg", "Could not reach Google.", "bad"); }
});
document.getElementById("keyTest").addEventListener("click", async () => {
  say("keyMsg", "Testing Street View and the Maps library…", "busy");
  let sv = null, maps = null, why = "";
  try {
    const d = await fetch("key-test", { cache: "no-store" }).then(r => r.json());
    sv = !!d.ok; if (!d.ok) why = d.reason || d.status || "";
  } catch (e) { sv = false; why = "could not reach Google"; }
  try { gPromise = null; await loadGoogle(); maps = true; }
  catch (e) { maps = false; if (!why) why = e.message || ""; }
  const line = (sv ? "✓" : "✕") + " Street View Static &nbsp; " +
               (maps ? "✓" : "✕") + " Maps JavaScript";
  say("keyMsg", line + (sv && maps ? "" : "<br>" + esc(why)),
      sv && maps ? "good" : "bad");
  document.getElementById("keyDot").className = "dot " + (sv || maps ? "ok" : "");
});

/* ---------------- the index has to exist before anything works ---------------- */
async function watchIndex(){
  try {
    const d = await fetch("status", { cache: "no-store" }).then(r => r.json());
    if (d.ok) {
      INDEX_OK = true;
      if (indexTimer) { clearInterval(indexTimer); indexTimer = null; }
      if (!STOPS.length) loadStops();
      return;
    }
    hud("Building the station index. This runs once a day…", true);
    if (!indexTimer) indexTimer = setInterval(watchIndex, 4000);
  } catch (e) { /* leave the status line alone */ }
}

/* ---------------- boot ---------------- */
(async function(){
  try {
    const d = await fetch("api-keys", { cache: "no-store" }).then(r => r.json());
    API_KEY = (d.keys || [])[0] || "";
  } catch (e) { API_KEY = ""; }
  setDot(!!API_KEY);
  initFreeMap();
  applyLayers();
  if (WATCH) {
    document.body.classList.add("watching");
    document.getElementById("dashBtn").classList.add("hasbar");
    document.getElementById("wbName").textContent = WATCH.name;
  }
  if (MODE === "google" && !API_KEY) MODE = "stars";
  if ((ENGINE === "detail" || MODE === "google") && API_KEY) {
    ENGINE = "free";
    await setEngine("detail", true);
  } else { ENGINE = "free"; MODE = "stars"; }
  paintMode();
  await watchIndex();
  autoLocate(true);
  loadGps(false);
  if (!gpsPoll) gpsPoll = setInterval(() => { if (!document.hidden) paintChip(); }, 3000);
  fetch("version").then(r => r.json())
    .then(v => { document.getElementById("verLine").textContent = v.version + " · " + v.build; })
    .catch(() => { document.getElementById("verLine").textContent = "—"; });
})();

/* the foreground is the trigger. coming back to the app re-finds you. */
document.addEventListener("visibilitychange", () => {
  if (document.hidden) stopBurst(); else autoLocate();
});
window.addEventListener("focus", () => autoLocate());
window.addEventListener("pageshow", () => autoLocate());
setInterval(() => { if (!document.hidden) autoLocate(); }, 90000);
if (WATCH && !boardTimer) boardTimer = setInterval(refreshBoards, 20000);
window.addEventListener("resize", () => {
  if (map && !usingGoogle()) setTimeout(() => map.invalidateSize(), 90);
});
</script>
</body>
</html>
ALLC_STAR_HTML
done_

step "installing the all.commute command"
cat > "$BIN/all.commute" << 'ALLC_LAUNCH'
#!/data/data/com.termux/files/usr/bin/bash
# all.commute — what is coming to the stop I am standing at, anywhere on ZET.
#   all.commute          start in the foreground and open the app
#   all.commute stop     stop a running server
#   all.commute status   running? on which port?
#   all.commute update   rebuild the station index now

APPDIR="$HOME/.all.commute"
SERVER="$APPDIR/all_commute_server.py"
PORTFILE="$APPDIR/port"
mkdir -p "$APPDIR"

if [ -t 1 ]; then
  OK="\033[1;32m"; WARN="\033[1;33m"; KEY="\033[1;37m"; DIM="\033[0;90m"; OFF="\033[0m"
else
  OK=""; WARN=""; KEY=""; DIM=""; OFF=""
fi

case "$1" in
  stop)
    if pkill -f all_commute_server.py 2>/dev/null; then
      printf "  ${OK}all.commute stopped${OFF}\n"
    else
      printf "  ${DIM}not running${OFF}\n"
    fi
    rm -f "$PORTFILE"; exit 0 ;;
  status)
    if pgrep -f all_commute_server.py >/dev/null 2>&1; then
      printf "  ${OK}running${OFF} on ${KEY}http://127.0.0.1:%s${OFF}\n" "$(cat "$PORTFILE" 2>/dev/null)"
    else
      printf "  ${DIM}stopped${OFF}\n"
    fi
    exit 0 ;;
  update)
    ALLC_DIR="$APPDIR" ALLC_FORCE=1 python "$APPDIR/update_all.py"; exit 0 ;;
esac

[ -f "$SERVER" ] || { printf "  ${WARN}server missing; run the installer again${OFF}\n"; exit 1; }

if [ -f "$HOME/.ma/banner.sh" ]; then
  . "$HOME/.ma/banner.sh"
  [ -z "$MA_NESTED" ] && ma_name "ALL.COMMUTE" "$MA_WATER" "Water | every stop"
else
  printf "\n  ${KEY}\xe0\xa5\x90 ALL.COMMUTE \xe0\xa5\x90${OFF}\n  ${DIM}Water | every stop${OFF}\n\n"
fi

# never let an older instance keep the port; the newest one must win
for sig in TERM TERM KILL; do
  pkill -$sig -f all_commute_server.py >/dev/null 2>&1 || true
  sleep 0.2
done
if command -v fuser >/dev/null 2>&1; then
  for port in $(seq 8084 8123); do fuser -k -n tcp "$port" >/dev/null 2>&1 || true; done
fi
rm -f "$PORTFILE"
exec python "$SERVER"
ALLC_LAUNCH
chmod +x "$BIN/all.commute"
done_

step "Termux:Widget desktop shortcut"
mkdir -p "$HOME/.shortcuts" "$HOME/.shortcuts/icons"
cat > "$HOME/.shortcuts/all.commute" << 'SHORTCUT'
#!/data/data/com.termux/files/usr/bin/bash
# Tap-to-start shortcut for Termux:Widget. Launches all.commute and opens the app.
export PATH="$PREFIX/bin:$PATH"
exec all.commute
SHORTCUT
sed -i 's/\r$//' "$HOME/.shortcuts/all.commute"
chmod +x "$HOME/.shortcuts/all.commute"
if command -v base64 >/dev/null 2>&1; then
  base64 -d > "$HOME/.shortcuts/icons/all.commute.png" << 'ICONB64'
iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAYAAABS3GwHAAAHZElEQVR4nO3dvY7WRhiG4ZcoZ4JIRUGFlAKtOKQcSQ4JrSgiUVFsBeJYSBE5a7wee/7n/bmvKiFkP6/9PDNje2BFAAAAAETyavUBHL17/+Hn6mPAWF+/fFaTu+UHQuCxshBLPpjQI2V2GaZ+WG7wf3z/NvpQsMjrN39k/b5ZRZjyIVfBJ+y4KsXoIgz94qngE3qkpMowqghDvijBR6tZRehegLPwE3zUOitCzxJ0LcAx/AQfvRyL0KsEXb4Ioz5mGDEb/NbyP4sQfsxzlqvWd0pN7WHJg1V6LYmqZwDCj5WOeaudCaoKQPihQY8SNN8DEH6s1Jq/4gLsW0b4ocE+h6WzQFEB2MUJC0pyml0A1v3QrPZ+oOoegPBDo5pcZhWAdT+sKL0faH4KBFh2WwBGf1hTMgswAyC0ywIw+sOq3FmAGQChJQvA6A/rcmYBZgCERgEQ2mkBWP7Ai7tlEDMAQqMACI0CILQXBWDPPzw75vtyBuAGGB5c5fj3iceBDG8/Pf7y708fHxYdSQwUoKNjeDctIR7xNfGMAjRKBXTm51KGehSgwqrQp1CGehQgk7bQp1CGMhTgxszg9/wswp+HAiSsGPHPQmtl5rGKAiQ8fXyoCl/vkbemFIz++ShAoxVhO34ms0Q99gJduAr308cHNSOtpmOxhhmggPaQ1RzfNnto/95GoQA3PAdjv3R6++nR9feawhII/4t4LxFqBuAl0bNU2KMticLMABFHt5SccxHlfIUowNnFjHKBz+Q+NYpwjtwX4OoiRrjAVyiB8wJ4v3g9RC+B2wLkbBfQcKOnIVw550LDcY7gsgDslakTsQTuCmAp/NuxagpWtBK4KoCl8GsWqQSuCnCF8JeJcr7cFOBqVIpyMXuLcN5cFMBi+I/HrHVZcTx/Wp6e9WK+AFqD45Gn4G9cb4bzeMFW8Hwezc8AqSnZ80VDP+YLsNkHXnv477YiYx5XSyDtwYc+bmYAoAYFmIxlji4UQBkKMhcFQDdvPz2aKzAFQLNj8C2VgAJMZCkYuax/TxRAIeuhErHzPZgpwDbNWjmxUVh/92KmAHsWi2DteKMwUQC2Dthk4fqYKECK9en3ioXwbCxfB9MFAFqpL4CHHxRtaTSvlboe2r939QUARqIAimkfPT1QXQAC4IPm66i6ACms/3WydF02JgsA9EIBlIs0g6xAAQYivPpRAISm9m+F8PACrBdLP8PXynFumAEQGgUYhPW/DWoLYG0qhU1q7wFEKMGepfsAS9TOAMAMFGAA1v92UACERgEMYWbpjwJ0RkhtoQAITfVjUNh0NgtqfYTLDGCM1SWW1uOmAB1pvchIowAITfU9AFui7bF2zZgBOpm5/GGp1Q8FQGgUAKFRAIRmsgDa1sArjkfbORDReUx3VBdA65MDlNF8HVUXABiNAiA09QXQ/oMXVh6HlnMgYu8F2EZ9AYCRVG+FuKPhb0pY/fkaaJqJSpmYAQiZTRaum+kZADrsg25tNjBfAA3LIDyzdi1MLIFE7J1Y2GCmACkUAy1MLYGePj6w5EFX5mYAwo+ezBUA6IkCIDQKgNAoAIpYe9F1hwIg2xb+t58e3RSBAiDLWeA9lMBtATyNUqtdnUfr59jUi7Ac1i+INdbfy7iaAbxO0ytdnT/r4RdxVoAUSlDHe/hFghRAhBKUinK+XBXgblSKclFb3Z0nL6O/iLMCiFCCVpHCL+KwACKUoFa08Is4LYBIXgkown9yzoXH8Is4LoBI3kWjBPe8hl/EeQFEKEErz+EXCVAAEUpwJ3V+vIdfJEgBRO4vZoSLfeX4/Uc5H+72Al3ZLmrk0f5KlNDvhZkB9qKOdngpZAFEnkPvNfw85s0Tagl0VBP+LVQai5PaDavxWLUIXYAWmorASF+PAhTI+fMGMwpRGnhmgTQK0NlZOFvCx+g+FgXI1BLE2lmiV/gZ/dMogGME/x4FyGTlp6AQ+jIUoEJLGUoCuv118D2/Jn5FARrllqF3SAl9HxSgo5JQ/vP3y1/786+2r4lyFGCys+Af/9tZETDG5V6g12/+mHUcIVyFv+b3Ic9Vjl8U4OuXz6+GHg2w0DHfYXeDzlY6qjMLzEEBEBoFQGinBdivk7gRhmX7/J7d3zIDIDQKMEnps33eBcyRLADLIFh3t/wRYQaYKndUZ/Sf5/al17v3H35u//zj+7exRxNI7l4g1MkZ/UXYC7QMYdfhdgnEvQCsyR39RbgHQHBZBWAWgBUlo79I5QxACaBRTS6zC3BsEyWAJsc85m7rL5oB+LMCsKAkp8VLIO4HoE3pun+v+SkQJcBKrfmrKgD3A9Cgdt2/Vz0DUAKs1CP8Ihl7ge7s9wpt2DOEUc4G2paHM833AGcfzmyAEXqHX6TDDLB3nA2YCdBLryXPUffn+iyJ0NOIUX9vyIutsxKIUATkSy2je7+MHfpmlyKg1Kzgb6ZsbUgVQYQy4PqhyejtN1P39lwVYY9S+JX7hHDWvrMlm9tyi4B4Zm+4XL67kzJg5S7j5QU4ohD+sa0eAABgqX8BrFMIWjNBUKYAAAAASUVORK5CYII=
ICONB64
fi
done_
if [ "$MODE" = "online" ]; then
  step "refreshing the station cache"
  printf "\n"
  ALLC_DIR="$APPDIR" ALLC_FORCE=1 python "$APPDIR/update_all.py" || \
    printf "  ${WARN}the cache refresh failed; the app will try again on its own${OFF}\n"
  step "refreshing the station cache"; done_
else
  step "station cache"; skip_
fi

printf "\n  ${OK}installed the star interface %s${OFF}  type ${KEY}all.commute${OFF} to start it\n" "$ALLC_UI_VERSION"
printf "  ${DIM}open it, let it find you, tap DASHBOARD${OFF}\n"
printf "  ${DIM}in settings: load a Gemini key, then Store the lines around me${OFF}\n"
printf "  ${DIM}on the Google key: Street View Static API draws the photograph,${OFF}\n"
printf "  ${DIM}Maps JavaScript API draws the 360 view and the detailed map layers${OFF}\n"
printf "  ${DIM}to go back: cp ~/.all.commute/NAME.prev.bak ~/.all.commute/NAME${OFF}\n"
printf "  ${DIM}            for NAME = all.html and all_commute_server.py${OFF}\n\n"
