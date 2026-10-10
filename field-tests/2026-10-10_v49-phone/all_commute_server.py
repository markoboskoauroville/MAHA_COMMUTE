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
import calendar
import subprocess
import threading
import socket
import socketserver
import sys
import urllib.error
import urllib.parse
import urllib.request
import http.server

APP_VERSION = "v47"
APP_BUILD = "b47"

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


SHARED_KEYFILE = os.path.expanduser("~/.maha.commute/keys/google-api.txt")


def _keys_from(path):
    """Lines that are long enough to be a key: an empty file or a lone newline is none."""
    try:
        with open(path, encoding="utf-8") as f:
            return [ln.strip() for ln in f if len(ln.strip()) >= 20]
    except OSError:
        return []


def read_keys():
    # v22: this app's own file first, then the one store every app shares
    return _keys_from(KEYFILE) or _keys_from(SHARED_KEYFILE)


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


STATIONS_PATH = os.path.join(APPDIR, "stations.json")
_stations_mem = {"mtime": None, "rows": []}


def station_rows():
    """Every station there has ever been, from stations.json. [] if none."""
    try:
        mt = os.path.getmtime(STATIONS_PATH)
    except OSError:
        return []
    if _stations_mem["mtime"] != mt:
        try:
            with open(STATIONS_PATH, encoding="utf-8") as f:
                st = json.load(f).get("stops", {})
            _stations_mem["rows"] = [
                {"stop_id": k, "name": v[0], "lat": v[1], "lon": v[2], "bearing": v[3]}
                for k, v in st.items()]
            _stations_mem["mtime"] = mt
        except Exception:
            return _stations_mem["rows"]
    return _stations_mem["rows"]


_meta_mem = {"key": None, "meta": {}}


def stations_meta():
    """The revision of the stations (a hash of the list itself, so a rebuild that
    changed nothing does not make every page download it again), how many there
    are, and what the last comparison with the feed found."""
    try:
        stt = os.stat(STATIONS_PATH)
    except OSError:
        return {}
    key = (stt.st_mtime, stt.st_size)
    if _meta_mem["key"] != key:
        try:
            import hashlib as _hl
            with open(STATIONS_PATH, encoding="utf-8") as f:
                d = json.load(f)
            st = d.get("stops", {})
            rev = _hl.sha1(json.dumps(st, sort_keys=True, separators=(",", ":")).encode()).hexdigest()[:12]
            _meta_mem["meta"] = {"stations_rev": rev, "stations_count": len(st),
                                 "stations_changes": d.get("changes")}
            _meta_mem["key"] = key
        except Exception:
            return _meta_mem["meta"]
    return _meta_mem["meta"]


def stations_ready():
    """Stations are there if the file has them or the index does."""
    return bool(station_rows()) or index_ready()


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
    if st == "waiting_for_network":
        return "waiting for the network to build the timetable"
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
    rows = [r for r in station_rows()
            if lat - dlat <= r["lat"] <= lat + dlat and lon - dlon <= r["lon"] <= lon + dlon]
    if not rows and index_ready():
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


def index_is_stale(con, now):
    """Which service day the index describes, and whether that day is today.

    The index holds one day of timetable, the day named in meta, and every `t`
    in `dep` counts its seconds from that day's midnight -- past midnight and
    on, so a ride that crosses midnight is filed as 24:15, not as 00:15 of the
    morning after. Between midnight and the morning's rebuild the two days part
    company, and anything reading `dep` has to know which one it is holding."""
    try:
        row = con.execute("select v from meta where k='service_date'").fetchone()
        sdate = row["v"] if row else ""
    except Exception:
        return False, ""
    return sdate != datetime.date.fromtimestamp(now).strftime("%Y%m%d"), sdate


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
    stale, sdate = index_is_stale(con, now)
    q = ("select t, trip_id, route, head from dep"
         " where stop_id=? and t between ? and ? order by t limit 400")
    rows = [(r, 0) for r in con.execute(q, (stop_id, lo, hi))]
    # Trips that run past midnight are stored as 24:xx and later, so look there
    # too -- but only while the index is yesterday's, because only then do
    # those rows mean tonight. They stand a day ahead on the index's clock, and
    # the shift carried beside each one takes that day back off before it
    # becomes a real time. Leaving the shift out is what made the 00:15 tram
    # read as 1445 minutes away at ten past midnight.
    if stale:
        rows += [(r, -86400)
                 for r in con.execute(q, (stop_id, lo + 86400, hi + 86400))]
    con.close()

    want = {r["trip_id"] for r, _ in rows}
    live, feed_n, feed_ok, feed_err = {}, 0, False, ""
    try:
        live, feed_n = rt_updates_for(fetch_rt(), want)
        feed_ok = True
    except Exception as e:
        feed_err = repr(e)
        _log("rt failed: %r" % (e,))

    deps = []
    for r, shift in rows:
        sched_abs = mid + shift + r["t"]
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
    # still know what is meant to run today. Whether the index is yesterday's
    # was already settled above, because the board had to query it knowing.
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

    # Which day's clock this ride keeps. One that crosses midnight is filed
    # under the day it set out on, as 24:15 rather than 00:15, so the hour we
    # are living in can sit a day to either side of the hour it is running to.
    # Settle the offset once, against the run's own span, and every time below
    # is a real time rather than one a day out.
    t0, tN = seq[0]["t"], seq[-1]["t"]
    te = now_s - (overall or 0)
    teN = None
    for c in (te, te + 86400, te - 86400):
        if t0 <= c <= tN:
            teN = c
            break
    anchor = mid - (teN - te if teN is not None else 0)

    stops = []
    for i, r in enumerate(seq):
        sched_at = anchor + r["t"]
        t_abs, dl = per.get(r["stop_id"], (None, None))
        if dl is None:
            dl = overall
        live_at = t_abs if t_abs is not None else (sched_at + dl if dl is not None else None)
        stops.append({"seq": i + 1, "name": r["name"], "stop_id": r["stop_id"],
                      "sched": hhmm(r["t"]), "sched_at": sched_at,
                      "live_at": int(live_at) if live_at else None,
                      "delay": int(dl) if dl is not None else None,
                      "lat": r["lat"], "lon": r["lon"]})

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
           "state_reason": BUILD_STATE["reason"],
           "stations": bool(station_rows())}
    out.update(stations_meta())
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


# v48: the dropout. termux-location does not fail by failing. When Android
# cannot produce a fix it exits 0 and prints {"API_ERROR": "Failed to get
# location"}, which is valid JSON, so the old code parsed it happily, found no
# latitude to copy, and returned {"ok": True, "provider": "gps"} -- a failure
# wearing a success, with Android's own reason thrown away. The chip then said
# "no provider answered" and the rows said "+/-? m", which is the dropout as it
# looks from the outside. Three rules now: API_ERROR is a failure, a reading
# with no coordinates is not a reading, and the last good fix is kept per
# provider so a dropout shows the last known position with its age instead of
# nothing at all.
_LAST_FIX = {}
_LAST_FIX_AT = {}
_LAST_FIX_LOCK = threading.Lock()


def _fix_failed(provider, reason):
    """A failure, plus the last good fix from this provider if we have one."""
    out = {"ok": False, "provider": provider, "reason": reason}
    with _LAST_FIX_LOCK:
        last = _LAST_FIX.get(provider)
        at = _LAST_FIX_AT.get(provider)
    if last:
        out["last"] = dict(last)
        if at is not None:
            out["last_age_s"] = int(max(0, time.time() - at))
    return out


def termux_fix(provider="gps", request="last", timeout=14):
    """One reading from one Android provider. 'last' is whatever is already
    cached and returns at once; 'once' waits for a fresh one."""
    from shutil import which
    exe = which("termux-location")
    if not exe:
        return _fix_failed(provider, "Termux:API not installed")
    try:
        p = subprocess.run([exe, "-p", provider, "-r", request],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=timeout)
    except subprocess.TimeoutExpired:
        return _fix_failed(provider, "no fix within %ds" % timeout)
    except Exception as e:
        return _fix_failed(provider, repr(e))
    raw = (p.stdout or b"").decode("utf-8", "replace").strip()
    if not raw:
        err = (p.stderr or b"").decode("utf-8", "replace").strip()
        return _fix_failed(provider, err[:160] or "nothing came back")
    try:
        d = json.loads(raw)
    except Exception:
        return _fix_failed(provider, raw[:160])
    if not isinstance(d, dict):
        return _fix_failed(provider, "unexpected reply: %s" % raw[:120])
    # Exit 0 with an error in the body. This is the one that cost us.
    if d.get("API_ERROR"):
        return _fix_failed(provider, str(d["API_ERROR"])[:160])
    if d.get("latitude") is None or d.get("longitude") is None:
        return _fix_failed(provider, "reply carried no coordinates")
    out = {"ok": True, "provider": d.get("provider", provider)}
    for k in ("latitude", "longitude", "altitude", "accuracy",
              "vertical_accuracy", "bearing", "speed", "elapsedMs"):
        if d.get(k) is not None:
            out[k] = d[k]
    with _LAST_FIX_LOCK:
        _LAST_FIX[provider] = dict(out)
        _LAST_FIX_AT[provider] = time.time()
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


# ---------------------------------------------------------------------------
# RIJEKA  (v52)
#
# Autotrolej publishes no GTFS and no GTFS-Realtime, so none of the ZET
# machinery applies. What it publishes instead suits this app better:
#
#   ATvoznired.json   today's whole timetable, 20 788 departures over 936
#                     stops, as TIMES OF DAY with no date in them at all.
#                     That is the board.
#   ATstanice.json    the stops, with GpsX = LONGITUDE and GpsY = LATITUDE.
#                     Swapping those puts Rijeka in the sea off Pula and
#                     nothing in the data will tell you.
#   api.autotrolej.hr /voznired/autobusi   live buses, no token needed.
#
# The API also has polasciStanica, which looks like the obvious board and is
# not: it returns the same 55 departures stamped with four different dates
# (2026-09-28 to 10-01, identical timetables), so the date is a placeholder
# and only the time means anything. ATvoznired.json is the daily file and has
# no date to misread, so the board is built from that.
# ---------------------------------------------------------------------------
RJ_BASE = "http://e-usluge2.rijeka.hr/OpenData"
RJ_API = "https://api.autotrolej.hr/api/open/v1"
RJ_CACHE = os.path.join(APPDIR, "rijeka_voznired.json")
RJ_STOPS_CACHE = os.path.join(APPDIR, "rijeka_stanice.json")
_rj_mem = {"day": None, "rows": None, "stops": None, "bearings": None}
_rj_lock = threading.Lock()


def _rj_fetch(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": "all.commute"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def _rj_cached(path, url, max_age_s):
    """The file if it is young enough, otherwise a fresh one. A download that
    fails falls back to the stale copy rather than to nothing: an old timetable
    is wrong by a few minutes, no timetable is wrong by all of them."""
    try:
        age = time.time() - os.path.getmtime(path)
    except OSError:
        age = None
    if age is not None and age < max_age_s:
        try:
            with open(path, encoding="utf-8") as f:
                return json.load(f), "cache"
        except Exception:
            pass
    try:
        data = _rj_fetch(url)
        tmp = path + ".part"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, path)
        return data, "fresh"
    except Exception:
        try:
            with open(path, encoding="utf-8") as f:
                return json.load(f), "stale"
        except Exception:
            return None, "none"


def _rj_load():
    """Today's timetable and the stop table, built once per service day."""
    today = time.strftime("%Y-%m-%d")
    with _rj_lock:
        if _rj_mem["day"] == today and _rj_mem["rows"] is not None:
            return _rj_mem
        rows, _src = _rj_cached(RJ_CACHE, RJ_BASE + "/ATvoznired.json", 6 * 3600)
        if rows is None:
            return _rj_mem
        stops = {}
        # the stop table comes out of the timetable itself: every departure
        # carries its stop's name and position, so there is nothing to join
        for r in rows:
            sid = str(r.get("StanicaId"))
            if sid not in stops:
                stops[sid] = {"stop_id": sid, "name": r.get("Naziv") or sid,
                              "lat": r.get("GpsY"), "lon": r.get("GpsX"),
                              "bearing": None}
        # a bearing per stop, from where its line goes next. Rijeka does not
        # publish one, and without it two stops facing each other across a road
        # are one place with two numbers.
        seq = {}
        for r in rows:
            key = r.get("LinVarId")
            if key is None:
                continue
            seq.setdefault(key, {})[r.get("RedniBrojStanice")] = r
        bearings = {}
        for key, byn in seq.items():
            ns = sorted(x for x in byn if isinstance(x, int))
            for i in range(len(ns) - 1):
                a, b = byn[ns[i]], byn[ns[i + 1]]
                try:
                    brg = _bearing_deg(a["GpsY"], a["GpsX"], b["GpsY"], b["GpsX"])
                except Exception:
                    continue
                bearings.setdefault(str(a["StanicaId"]), []).append(brg)
        for sid, lst in bearings.items():
            if sid in stops and lst:
                stops[sid]["bearing"] = round(sum(lst) / float(len(lst)), 2)
        _rj_mem.update(day=today, rows=rows, stops=stops)
        return _rj_mem


def _bearing_deg(aLat, aLon, bLat, bLon):
    p = math.pi / 180
    y = math.sin((bLon - aLon) * p) * math.cos(bLat * p)
    x = (math.cos(aLat * p) * math.sin(bLat * p) -
         math.sin(aLat * p) * math.cos(bLat * p) * math.cos((bLon - aLon) * p))
    return (math.atan2(y, x) / p + 360.0) % 360.0


def rj_ready():
    m = _rj_load()
    return bool(m.get("rows"))


def rj_stations():
    m = _rj_load()
    return list((m.get("stops") or {}).values())


def rj_stations_json():
    m = _rj_load()
    stops = m.get("stops") or {}
    if not stops:
        return {"ok": False, "reason": "Rijeka timetable not loaded yet"}
    return {"updated": int(time.time()), "count": len(stops),
            "stops": {k: [v["name"], v["lat"], v["lon"], v["bearing"]]
                      for k, v in stops.items()},
            "changes": {"at": int(time.time()), "feed": len(stops),
                        "n_added": 0, "added": [], "renamed": 0, "moved": 0,
                        "not_in_feed": 0}}


def rj_stops_near(lat, lon, radius_m, want_min=6):
    rows = rj_stations()
    used = float(radius_m)
    for r in (radius_m, radius_m * 2, radius_m * 4, 1500.0, 3000.0, 6000.0):
        out = []
        for st in rows:
            try:
                d = _metres(lat, lon, st["lat"], st["lon"])
            except Exception:
                continue
            if d <= r:
                o = dict(st)
                o["dist"] = int(round(d))
                out.append(o)
        used = float(r)
        if len(out) >= want_min or not want_min:
            break
    out.sort(key=lambda x: x["dist"])
    return out[:60], used


def _rj_secs(t):
    """'20:00:00.0000000' -> seconds since midnight."""
    try:
        h, m, rest = str(t).split(":")[:3]
        return int(h) * 3600 + int(m) * 60 + int(float(rest))
    except Exception:
        return None


def rj_board(sid, mins=30, back=15):
    m = _rj_load()
    rows = m.get("rows")
    if not rows:
        return {"ok": False, "reason": "Rijeka timetable not loaded yet"}
    sid = str(sid)
    stop = (m.get("stops") or {}).get(sid)
    if not stop:
        return {"ok": False, "reason": "no such stop"}
    now = time.localtime()
    now_s = now.tm_hour * 3600 + now.tm_min * 60 + now.tm_sec
    midnight = time.time() - now_s
    deps = []
    for r in rows:
        if str(r.get("StanicaId")) != sid:
            continue
        sec = _rj_secs(r.get("Polazak"))
        if sec is None:
            continue
        delta = (sec - now_s) / 60.0
        # a departure just after midnight belongs to the night ahead, not the
        # one that has gone
        if delta < -back and sec < 4 * 3600:
            delta += 1440.0
            sec += 86400
        if delta < -back or delta > mins:
            continue
        deps.append({
            "route": str(r.get("BrojLinije") or ""),
            "head": r.get("NazivVarijanteLinije") or "",
            "trip": str(r.get("PolazakId") or ""),
            "sched": time.strftime("%H:%M", time.localtime(midnight + (sec % 86400))),
            "sched_at": int(midnight + sec),
            "at": int(midnight + sec),
            "live_at": None, "delay": None, "live": False,
            "passed": delta < 0, "mins": int(round(delta)),
            "dir": r.get("Smjer") or "",
        })
    deps.sort(key=lambda x: x["sched_at"])
    lines = sorted({d["route"] for d in deps}, key=lambda x: (len(x), x))
    return {"ok": True, "now": int(time.time()), "window": mins, "back": back,
            "feed_ok": True, "feed_trips": 0, "feed_error": "",
            "index_stale": False, "service_date": time.strftime("%Y%m%d"),
            "printed": 0, "printed_lines": [], "printed_needs_key": [],
            "lines": lines, "stop": stop, "departures": deps, "city": "rijeka"}


def rj_vehicles(lat=None, lon=None, radius_m=3000):
    """Live buses. No token: every endpoint declares one and none enforces it."""
    try:
        d = _rj_fetch(RJ_API + "/voznired/autobusi", timeout=20)
    except Exception as e:
        return {"ok": False, "reason": repr(e), "vehicles": []}
    res = d.get("res") if isinstance(d, dict) else d
    items = res if isinstance(res, list) else list((res or {}).values())
    out = []
    for v in items:
        try:
            la, lo = float(v.get("lat")), float(v.get("lon"))
        except Exception:
            continue
        o = {"id": str(v.get("gbr") or ""), "lat": la, "lon": lo,
             "trip": str(v.get("voznjaId") or ""), "src": "gps", "route": ""}
        if lat is not None and lon is not None:
            o["dist"] = int(round(_metres(lat, lon, la, lo)))
            if o["dist"] > radius_m:
                continue
        out.append(o)
    out.sort(key=lambda x: x.get("dist", 0))
    return {"ok": True, "count": len(out), "gps": len(out), "calc": 0,
            "radius": int(radius_m), "vehicles": out, "city": "rijeka"}


# ---------------------------------------------------------------------------
# TRACKS  (v51)
# A recorded journey is written as GPX, into Documents, where a file browser
# can see it and rename it. GPX rather than our own JSON because the point of
# putting it in Documents is that it is not ours alone: it opens in any map
# app, and renaming it in a file browser is then a rename that means something.
# The page never touches the filesystem -- it cannot -- so every one of these
# is a round trip to here.
# ---------------------------------------------------------------------------
TRACK_DIR = os.environ.get(
    "ALLC_TRACKS", "/storage/emulated/0/Documents/All Commute/Tracks")
# Read as well as write. Documents/Track_Records is where Mantra Trail has been
# putting its GPX since September, and those journeys are as much a track as
# ours: the picker lists them, and opening one draws it on this map. Only the
# first directory is written to.
TRACK_DIRS = [TRACK_DIR, "/storage/emulated/0/Documents/Track_Records"]


def _track_dir():
    try:
        os.makedirs(TRACK_DIR, exist_ok=True)
    except Exception:
        pass
    return TRACK_DIR


def _safe_track_name(name):
    """A file name the user typed, reduced to one that cannot leave the folder."""
    name = (name or "").strip()
    # Not basename(): a name the user typed with a slash in it is a name, not a
    # path, and basename threw away everything before it -- "test drive / probe"
    # was saved as "probe". Separators become a dash, so the whole name lives.
    for sep in ("/", "\\"):
        name = name.replace(sep, "-")
    if name.lower().endswith(".gpx"):
        name = name[:-4]
    out = []
    for ch in name:
        out.append(ch if (ch.isalnum() or ch in " -_.,()") else "-")
    name = "".join(out).strip(" .-")
    return (name or time.strftime("%Y-%m-%d %H-%M Track"))[:80]


def _iso(ms):
    try:
        return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(float(ms) / 1000.0))
    except Exception:
        return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _xml_escape(t):
    return (str(t).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


def _nearest_station(lat, lon, within_m=400.0):
    """The station you were next to, or None. 'Close by' has to mean close:
    past four hundred metres the nearest station is not where you were, it is
    just the least far away, and a name built from it would mislead."""
    best, bd = None, within_m
    for r in station_rows():
        try:
            d = _metres(lat, lon, r["lat"], r["lon"])
        except Exception:
            continue
        if d < bd:
            best, bd = r, d
    return best["stop_id"] if best else None


def _default_track_name(pts):
    """Date, time, then where it started and where it ended.

    Marko's rule: the date and time first, because that is what sorts a folder
    into an order you can read, then the two station numbers, and if there is
    no station near either end that part is simply left out rather than filled
    with a placeholder.
    """
    try:
        t0 = float(pts[0][2]) / 1000.0
    except Exception:
        t0 = time.time()
    stamp = time.strftime("%Y-%m-%d %H-%M", time.localtime(t0))
    a = _nearest_station(pts[0][0], pts[0][1])
    b = _nearest_station(pts[-1][0], pts[-1][1]) if len(pts) > 1 else None
    if a and b and a != b:
        return "%s %s %s" % (stamp, a, b)
    if a or b:
        return "%s %s" % (stamp, a or b)
    return "%s Track" % stamp


def track_save(name, points):
    pts = []
    for p in (points or []):
        try:
            la, lo = float(p.get("lat")), float(p.get("lng"))
        except Exception:
            continue
        if not (-90 <= la <= 90 and -180 <= lo <= 180):
            continue
        try:
            ele = float(p.get("ele")) if p.get("ele") is not None else None
        except Exception:
            ele = None
        pts.append((la, lo, p.get("t"), ele))
    if not pts:
        return {"ok": False, "reason": "nothing recorded"}
    base = _safe_track_name(name) if (name or "").strip() else _safe_track_name(_default_track_name(pts))
    d = _track_dir()
    fn = base + ".gpx"
    n = 2
    while os.path.exists(os.path.join(d, fn)):
        fn = "%s (%d).gpx" % (base, n)
        n += 1
        if n > 999:
            return {"ok": False, "reason": "too many files of that name"}
    # Mantra Trail's dialect, element for element, so that every map app on
    # this phone reads our files and we read theirs.
    t0 = _iso(pts[0][2] or time.time() * 1000)
    body = ['<?xml version="1.0" encoding="UTF-8"?>',
            '<gpx version="1.1" creator="all.commute"',
            '     xmlns="http://www.topografix.com/GPX/1/1"',
            '     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"',
            '     xsi:schemaLocation="http://www.topografix.com/GPX/1/1 '
            'http://www.topografix.com/GPX/1/1/gpx.xsd">',
            "  <metadata>",
            "    <name>%s</name>" % _xml_escape(base),
            "    <time>%s</time>" % t0,
            "  </metadata>",
            "  <trk>",
            "    <name>%s</name>" % _xml_escape(base),
            "    <trkseg>"]
    for la, lo, t, ele in pts:
        body.append('      <trkpt lat="%.6f" lon="%.6f">' % (la, lo))
        if ele is not None:
            body.append("        <ele>%.1f</ele>" % ele)
        if t:
            body.append("        <time>%s</time>" % _iso(t))
        body.append("      </trkpt>")
    # <sat> and <hdop> are Mantra Trail's and stay its own: this app cannot
    # read a satellite count, and turning the browser's accuracy in metres into
    # a dimensionless hdop would be inventing a number.
    body.append("    </trkseg>")
    body.append("  </trk>")
    body.append("</gpx>")
    path = os.path.join(d, fn)
    tmp = path + ".part"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(body) + "\n")
        os.replace(tmp, path)
    except Exception as e:
        try:
            os.remove(tmp)
        except Exception:
            pass
        return {"ok": False, "reason": repr(e)}
    return {"ok": True, "file": fn, "points": len(pts),
            "metres": int(round(_track_metres(pts))), "dir": d}


def _track_metres(pts):
    d = 0.0
    for i in range(1, len(pts)):
        d += _metres(pts[i-1][0], pts[i-1][1], pts[i][0], pts[i][1])
    return d


def _read_gpx(path):
    """Every trkpt in the file, in order. Namespace-agnostic: GPX in the wild
    is written by everything and half of it disagrees about the namespace."""
    import xml.etree.ElementTree as ET
    pts = []
    try:
        root = ET.parse(path).getroot()
    except Exception:
        return pts
    for el in root.iter():
        tag = el.tag.rsplit("}", 1)[-1]
        if tag != "trkpt" and tag != "wpt":
            continue
        try:
            la = float(el.get("lat")); lo = float(el.get("lon"))
        except Exception:
            continue
        t, ele = None, None
        for ch in el:
            tg = ch.tag.rsplit("}", 1)[-1]
            if tg == "time" and ch.text:
                try:
                    t = int(calendar.timegm(time.strptime(
                        ch.text.strip()[:19], "%Y-%m-%dT%H:%M:%S")) * 1000)
                except Exception:
                    t = None
            elif tg == "ele" and ch.text:
                try:
                    ele = float(ch.text.strip())
                except Exception:
                    ele = None
        pts.append((la, lo, t, ele))
    return pts


def _find_track(fn):
    """A file name, resolved across the folders we read. Nothing outside them."""
    name = os.path.basename(fn or "")
    if not name.lower().endswith(".gpx"):
        return None, None
    for d in TRACK_DIRS:
        path = os.path.join(d, name)
        if os.path.isfile(path):
            return path, d
    return None, None


def track_list():
    _track_dir()
    out = []
    seen = set()
    for d in TRACK_DIRS:
        try:
            names = sorted(os.listdir(d))
        except Exception:
            continue
        for fn in names:
            if not fn.lower().endswith(".gpx") or fn in seen:
                continue
            path = os.path.join(d, fn)
            try:
                st = os.stat(path)
            except Exception:
                continue
            seen.add(fn)
            pts = _read_gpx(path)
            out.append({"file": fn, "name": fn[:-4], "bytes": st.st_size,
                        "modified": int(st.st_mtime), "points": len(pts),
                        "metres": int(round(_track_metres(pts))) if pts else 0,
                        "folder": os.path.basename(d.rstrip("/")),
                        "ours": d == TRACK_DIR})
    out.sort(key=lambda r: r["modified"], reverse=True)
    return {"ok": True, "dir": TRACK_DIR, "dirs": TRACK_DIRS, "tracks": out}


def track_get(fn):
    path, d = _find_track(fn)
    if not path:
        return {"ok": False, "reason": "no such track"}
    name = os.path.basename(path)
    pts = _read_gpx(path)
    if not pts:
        return {"ok": False, "reason": "no points in that file"}
    return {"ok": True, "file": name, "name": name[:-4],
            "points": [{"lat": a, "lng": b, "t": c, "ele": e} for a, b, c, e in pts],
            "metres": int(round(_track_metres(pts)))}


def track_delete(fn):
    path, d = _find_track(fn)
    if not path:
        return {"ok": False, "reason": "no such track"}
    name = os.path.basename(path)
    if d != TRACK_DIR:
        # Mantra Trail's folder is read, never written. Deleting another app's
        # journey from inside this one is not ours to do.
        return {"ok": False, "reason": "that track belongs to %s, delete it there"
                                       % os.path.basename(d.rstrip("/"))}
    try:
        os.remove(path)
    except Exception as e:
        return {"ok": False, "reason": repr(e)}
    return {"ok": True, "file": name}


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

    def _raw(self, body, ctype, etag, code=200):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("ETag", '"%s"' % etag)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, payload, code=200):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # Credentials, spend and housekeeping answer the phone and nobody else
    # on the wifi. The page and the timetable stay open to the room.
    _PHONE_ONLY = ("/api-keys", "/gemini-key", "/gemini-test", "/key-test", "/gemini-model", "/gemini-models", "/gemini-models-old", "/rebuild", "/cache/clear", "/sched-delete", "/gps", "/tracks", "/track", "/track/save", "/track/delete")
    # v22: a request that a web page on another site made on the phone's behalf
    # is refused, for every POST and for every GET that changes something.
    _STATE_CHANGING = ("/rebuild", "/cache/clear", "/sched-delete", "/track/save", "/track/delete")
    def _cross_site(self):
        sf = (self.headers.get("Sec-Fetch-Site") or "").lower()
        if sf in ("cross-site", "same-site"):
            return True
        org = self.headers.get("Origin") or ""
        if org and org != "null":
            return urllib.parse.urlparse(org).netloc.lower() != (self.headers.get("Host") or "").lower()
        return bool(org)
    def _phone_only(self, path):
        if (self.command == "POST" or path in self._STATE_CHANGING) and self._cross_site():
            return True
        if path not in self._PHONE_ONLY:
            return False
        peer = self.client_address[0]
        host = (self.headers.get("Host") or "").rsplit(":", 1)[0].strip("[]").lower()
        return not (peer in ("127.0.0.1", "::1", "::ffff:127.0.0.1")
                    and host in ("127.0.0.1", "localhost", "::1"))

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        route = u.path
        if route in ("/", "/index.html"):
            route = "/all.html"
        if self._phone_only(route):
            return self._json({"ok": False, "reason": "this answers on the phone only, from its own pages"}, 403)
        try:
            # v52: one query parameter switches city. Zagreb stays the
            # default, so every existing caller is untouched.
            city = (q.get("city", ["zagreb"])[0] or "zagreb").lower()
            if city in ("rj", "rijeka"):
                if route == "/stations.json":
                    return self._json(rj_stations_json())
                if route == "/board":
                    return self._json(rj_board(
                        q.get("stop", [""])[0],
                        max(5, min(int(q.get("mins", ["30"])[0]), 1440)),
                        max(0, min(int(q.get("back", ["15"])[0]), 120))))
                if route == "/stops":
                    found, used = rj_stops_near(
                        float(q.get("lat", ["0"])[0]), float(q.get("lon", ["0"])[0]),
                        min(float(q.get("r", ["350"])[0]), 8000.0),
                        want_min=(6 if q.get("widen", ["1"])[0] != "0" else 0))
                    return self._json({"ok": True, "radius": used,
                                       "asked": int(float(q.get("r", ["350"])[0])),
                                       "widened": used > float(q.get("r", ["350"])[0]),
                                       "stops": found, "city": "rijeka"})
                if route == "/vehicles":
                    return self._json(rj_vehicles(
                        float(q.get("lat", ["0"])[0]) or None,
                        float(q.get("lon", ["0"])[0]) or None,
                        min(float(q.get("r", ["3000"])[0]), 20000.0)))
                if route == "/status":
                    m = _rj_load()
                    st = m.get("stops") or {}
                    return self._json({"ok": bool(st), "state": "idle",
                                       "city": "rijeka", "stations": bool(st),
                                       "stations_count": len(st),
                                       "service_date": time.strftime("%Y%m%d"),
                                       "stops": str(len(st)),
                                       "deps": str(len(m.get("rows") or [])),
                                       "feed_ok": True,
                                       "source": "Autotrolej open data"})

            if route == "/stations.json":
                meta = stations_meta()
                if not meta:
                    return self._json({"ok": False, "reason": "no stations yet"}, 404)
                if (self.headers.get("If-None-Match") or "").strip('"') == meta["stations_rev"]:
                    self.send_response(304)
                    self.send_header("ETag", '"%s"' % meta["stations_rev"])
                    self.end_headers()
                    return
                with open(STATIONS_PATH, "rb") as f:
                    body = f.read()
                return self._raw(body, "application/json; charset=utf-8", meta["stations_rev"])
            if route == "/stops":
                lat = float(q.get("lat", ["0"])[0])
                lon = float(q.get("lon", ["0"])[0])
                r = min(float(q.get("r", ["350"])[0]), 8000.0)
                widen = q.get("widen", ["1"])[0] != "0"
                if not stations_ready():
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
                if not stations_ready():
                    return self._json({"ok": False, "reason": not_ready(), "stops": []})
                if len(term) < 2:
                    return self._json({"ok": True, "stops": []})
                tl = term.lower()
                rows = sorted((r for r in station_rows()
                               if tl in (r["name"] or "").lower() or r["stop_id"].startswith(term)),
                              key=lambda r: r["name"] or "")[:80]
                if not rows and index_ready():
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
            if route in ("/sched-delete", "/rebuild", "/cache/clear"):
                return self._json({"ok": False, "reason": "use POST"}, 405)
            if route == "/api-keys":
                return self._json({"keys": read_keys()})
            if route == "/tracks":
                return self._json(track_list())
            if route == "/track":
                return self._json(track_get(q.get("f", [""])[0]))
            if route == "/status":
                return self._json(index_status())
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
            if route == "/lan-ip":
                return self._json({"ip": _lan_ip()})
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
        if self._phone_only(u.path):
            return self._json({"ok": False, "reason": "this answers on the phone only, from its own pages"}, 403)
        if u.path in ("/rebuild", "/cache/clear", "/sched-delete"):
            q = urllib.parse.parse_qs(u.query)
            if u.path == "/rebuild":
                return self._json(rebuild(q.get("force", ["0"])[0] == "1"))
            if u.path == "/cache/clear":
                return self._json(clear_index())
            return self._json(sched_delete(q.get("route", [""])[0], q.get("all", ["0"])[0] == "1"))
        if u.path in ("/track/save", "/track/delete"):
            try:
                data = json.loads(body or "{}")
            except Exception:
                data = {}
            if u.path == "/track/save":
                return self._json(track_save(data.get("name"), data.get("points")))
            return self._json(track_delete(data.get("file")))
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
        # v22: an offline start used to try once and never again. Now it keeps
        # trying, 30 s then 1, 2, 5 minutes and every 5 minutes after, until the
        # day is built, and /status says it is waiting rather than idle.
        delay = int(os.environ.get("ALLC_RETRY_FIRST", "30"))   # a test sets it small
        while True:
            _log("building the station index in the background")
            r = rebuild(False)
            if r.get("ok"):
                BUILD_STATE.update(state="idle", reason="")
                return
            if "already running" not in (r.get("reason") or ""):
                BUILD_STATE.update(state="waiting_for_network", reason=(r.get("reason") or "")[:120])
            time.sleep(delay)
            delay = min(delay * 2, 300)
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
