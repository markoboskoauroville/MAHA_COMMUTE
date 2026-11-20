#!/usr/bin/env python3
"""gtfs.py, written by the MAHA COMMUTE installer into ~/.maha.commute/gtfs/.

ONE ZET SCHEDULE FOR THE WHOLE FAMILY. Marko, 7.10.2026: "Add central GTFS
system so all apps share the same folder and same data of GTFS. And number 4
... when I press 4, first download the GTFS latest file, checks its sanity if
the data is corrupted, and in the terminal shows the data ... open also the
Flask web user interface to monitor the data health and data itself."

Until v21 each of the three apps downloaded the same twelve megabyte zip from
the same address into its own folder, three copies of one file that could be
three different days old. Now there is one folder and one copy:

    ~/.maha.commute/gtfs/zet_gtfs.zip    the schedule, only ever a checked one
    ~/.maha.commute/gtfs/meta.json       where it came from, its hash, who saw it
    ~/.maha.commute/gtfs/health.json     the full check of that exact file
    ~/.maha.commute/gtfs/history.jsonl   every fetch, kept or refused
    ~/.maha.commute/gtfs/status.txt      one line for the launcher's quadrant 4

THREE PROMISES

  1. A download that is not a sound GTFS never replaces one that is. It is
     written beside the real file, opened, CRC checked, its tables and columns
     looked for, and only then renamed over the top. A phone that walks out of
     signal half way leaves the old schedule exactly as it was.
  2. Two apps asking at once download once. The second waits on a lock and
     then finds the file the first one just fetched.
  3. Each app learns separately that the schedule changed. "changed" is
     measured against what THAT app last saw, so day.commute rebuilds even
     when all.commute was the one that fetched.

THE COMMANDS

    python gtfs.py update     ask ZET for the newest, check it, show it (key 4)
    python gtfs.py fetch      download if ZET has a newer one
    python gtfs.py check      the full health check of the file that is here
    python gtfs.py show       print the last check in the terminal
    python gtfs.py serve      the web monitor (Flask, waitress when present)
    python gtfs.py status     one line, for scripts

The apps import this file and call fetch(). Nothing else of theirs changes.
"""

import csv
import datetime
import hashlib
import io
import json
import os
import socket
import sys
import textwrap
import threading
import time
import urllib.error
import urllib.request
import zipfile

try:
    import fcntl
except Exception:            # not on this platform: one process at a time is then a hope
    fcntl = None

VERSION = "v21"
GDIR = os.environ.get("MAHA_GTFS_DIR",
                      os.path.join(os.path.expanduser("~"), ".maha.commute", "gtfs"))
ZIP = os.path.join(GDIR, "zet_gtfs.zip")
META = os.path.join(GDIR, "meta.json")
HEALTH = os.path.join(GDIR, "health.json")
HISTORY = os.path.join(GDIR, "history.jsonl")
STATUS = os.path.join(GDIR, "status.txt")
PORTFILE = os.path.join(GDIR, "port")
LOCK = os.path.join(GDIR, ".lock")
URLS = ["https://www.zet.hr/gtfs-scheduled/latest",
        "https://zet.hr/gtfs-scheduled/latest"]
UA = "Mozilla/5.0 (Android; maha.commute-gtfs)"
PORT_FIRST = int(os.environ.get("MAHA_GTFS_PORT", "8090"))

# Every table a ZET app reads, and the columns it reads from it. Missing one of
# these is not a warning: an app built on it shows nothing, or the wrong thing.
REQUIRED = {
    "agency.txt":     ["agency_name", "agency_timezone"],
    "stops.txt":      ["stop_id", "stop_name", "stop_lat", "stop_lon"],
    "routes.txt":     ["route_id", "route_short_name", "route_type"],
    "trips.txt":      ["route_id", "service_id", "trip_id"],
    "stop_times.txt": ["trip_id", "arrival_time", "departure_time", "stop_id", "stop_sequence"],
}
OPTIONAL = ["calendar.txt", "calendar_dates.txt", "shapes.txt", "feed_info.txt"]
ROUTE_TYPES = {"0": "tram", "1": "metro", "2": "rail", "3": "bus", "4": "ferry",
               "5": "cable tram", "6": "aerial lift", "7": "funicular"}
# Zagreb and everything ZET reaches, generously (Velika Gorica, Samobor side).
LAT_MIN, LAT_MAX, LON_MIN, LON_MAX = 45.55, 46.10, 15.60, 16.40


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------
def _now():
    return time.time()


def _load(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def _save(path, obj):
    os.makedirs(GDIR, exist_ok=True)
    tmp = path + ".new"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def _history(event, **kw):
    os.makedirs(GDIR, exist_ok=True)
    kw.update({"t": int(_now()), "event": event})
    try:
        with open(HISTORY, "a", encoding="utf-8") as f:
            f.write(json.dumps(kw, ensure_ascii=False) + "\n")
    except Exception:
        pass


def history(n=40):
    try:
        with open(HISTORY, encoding="utf-8") as f:
            lines = f.readlines()[-n:]
        return [json.loads(x) for x in lines if x.strip()][::-1]
    except Exception:
        return []


class _Lock:
    """One fetch at a time across every app on the phone."""
    def __enter__(self):
        os.makedirs(GDIR, exist_ok=True)
        self.f = open(LOCK, "a+")
        if fcntl:
            fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *a):
        try:
            if fcntl:
                fcntl.flock(self.f, fcntl.LOCK_UN)
        finally:
            self.f.close()


def _member(zf, name):
    for n in zf.namelist():
        if n == name or n.endswith("/" + name):
            return n
    return None


def _rows(zf, name):
    """csv.DictReader over one table, BOM and quoting handled."""
    m = _member(zf, name)
    if not m:
        return None
    return csv.DictReader(io.TextIOWrapper(zf.open(m), encoding="utf-8-sig", newline=""))


def _ymd(d):
    return d.strftime("%Y%m%d")


def _fmt_ymd(s):
    s = str(s or "")
    return "%s.%s.%s" % (int(s[6:8]), int(s[4:6]), s[0:4]) if len(s) == 8 and s.isdigit() else s


def _secs(hms):
    try:
        h, m, s = hms.strip().split(":")
        return int(h) * 3600 + int(m) * 60 + int(s)
    except Exception:
        return None


# ---------------------------------------------------------------------------
# the quick check: is this a GTFS at all. Runs on every download, before the
# file is allowed anywhere near the real name.
# ---------------------------------------------------------------------------
def quick_check(path_or_bytes):
    """Returns (ok, reason, feed_version)."""
    try:
        src = io.BytesIO(path_or_bytes) if isinstance(path_or_bytes, bytes) else path_or_bytes
        with zipfile.ZipFile(src) as zf:
            bad = zf.testzip()
            if bad:
                return False, "%s is damaged inside the zip (CRC)" % bad, ""
            for name, cols in REQUIRED.items():
                m = _member(zf, name)
                if not m:
                    return False, "%s is missing" % name, ""
                r = _rows(zf, name)
                head = r.fieldnames or []
                miss = [c for c in cols if c not in head]
                if miss:
                    return False, "%s has no %s column" % (name, ", ".join(miss)), ""
                if next(r, None) is None:
                    return False, "%s is empty" % name, ""
            if not (_member(zf, "calendar.txt") or _member(zf, "calendar_dates.txt")):
                return False, "neither calendar.txt nor calendar_dates.txt", ""
            ver = ""
            fi = _rows(zf, "feed_info.txt")
            if fi:
                row = next(fi, None) or {}
                ver = row.get("feed_version", "")
            return True, "", ver
    except zipfile.BadZipFile:
        return False, "not a zip file", ""
    except Exception as e:
        return False, "unreadable: %r" % (e,), ""


# ---------------------------------------------------------------------------
# fetch: what the apps call
# ---------------------------------------------------------------------------
def _seen(meta, who, sha):
    if not who:
        return True
    seen = meta.setdefault("seen", {})
    changed = seen.get(who) != sha
    seen[who] = sha
    return changed


def fetch(force=False, who=None, log=None, max_age=600, progress=None):
    """Return (zip_bytes, changed_for_who).

    max_age: seconds within which the server is not asked again, so three apps
    starting together make one request and not three. force asks regardless
    and downloads the whole file even if ZET says it has not changed."""
    log = log or (lambda m: None)
    with _Lock():
        meta = _load(META, {})
        have = os.path.isfile(ZIP)
        if have and not force and _now() - meta.get("checked", 0) < max_age:
            with open(ZIP, "rb") as f:
                data = f.read()
            changed = _seen(meta, who, meta.get("sha256"))
            _save(META, meta)
            return data, changed

        headers = {"User-Agent": UA}
        if have and not force:
            if meta.get("etag"):
                headers["If-None-Match"] = meta["etag"]
            if meta.get("last_modified"):
                headers["If-Modified-Since"] = meta["last_modified"]
        last = None
        for url in URLS:
            try:
                log("asking " + url)
                req = urllib.request.Request(url, headers=headers)
                try:
                    resp = urllib.request.urlopen(req, timeout=180)
                except urllib.error.HTTPError as he:
                    if he.code == 304 and have:
                        log("  unchanged on the server, the shared copy stays")
                        meta["checked"] = int(_now())
                        with open(ZIP, "rb") as f:
                            data = f.read()
                        changed = _seen(meta, who, meta.get("sha256"))
                        _save(META, meta)
                        _history("unchanged", who=who or "", url=url)
                        write_status()
                        return data, changed
                    raise
                total = int(resp.headers.get("Content-Length") or 0)
                buf, got = io.BytesIO(), 0
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    buf.write(chunk)
                    got += len(chunk)
                    if progress:
                        progress(got, total)
                rh = resp.headers
                resp.close()
                data = buf.getvalue()
                if total and got != total:
                    last = "cut short: %d of %d bytes" % (got, total)
                    log("  " + last)
                    _history("refused", who=who or "", url=url, reason=last)
                    continue
                ok, why, ver = quick_check(data)
                if not ok:
                    last = "not a sound GTFS: " + why
                    log("  " + last + ", the shared copy stays")
                    _history("refused", who=who or "", url=url, reason=why, bytes=len(data))
                    continue
                sha = hashlib.sha256(data).hexdigest()
                os.makedirs(GDIR, exist_ok=True)
                part = ZIP + ".part"
                with open(part, "wb") as f:
                    f.write(data)
                    f.flush()
                    os.fsync(f.fileno())
                os.replace(part, ZIP)
                new = sha != meta.get("sha256")
                meta.update({
                    "etag": rh.get("ETag") or "", "last_modified": rh.get("Last-Modified") or "",
                    "sha256": sha, "bytes": len(data), "url": url, "feed_version": ver,
                    "checked": int(_now()),
                })
                if new:
                    meta["fetched"] = int(_now())
                changed = _seen(meta, who, sha)
                _save(META, meta)
                _history("new" if new else "same", who=who or "", url=url, bytes=len(data),
                         sha=sha[:12], version=ver)
                log("  got %d bytes, version %s%s" % (len(data), ver or "?",
                                                      "" if new else " (the same file)"))
                write_status()
                return data, changed
            except Exception as e:
                last = repr(e)
                log("  failed: " + last)
        _history("failed", who=who or "", reason=str(last))
        if have:
            log("  ZET did not answer, the shared copy stays")
            with open(ZIP, "rb") as f:
                data = f.read()
            changed = _seen(meta, who, meta.get("sha256"))
            _save(META, meta)
            return data, changed
        raise RuntimeError("could not fetch the GTFS: %s" % last)


# ---------------------------------------------------------------------------
# the deep check: every table, every reference, every date
# ---------------------------------------------------------------------------
def deep_check(path=ZIP, say=None):
    say = say or (lambda m: None)
    t0 = _now()
    checks = []

    def add(level, name, detail):
        checks.append({"level": level, "name": name, "detail": detail})

    rep = {"checked_at": int(t0), "checks": checks, "files": [], "counts": {},
           "feed": {}, "service": {}, "routes_by_type": {}, "top_stops": [], "level": "ok"}
    if not os.path.isfile(path):
        add("bad", "the file", "there is no GTFS here yet. Press 4 in the launcher to fetch it")
        rep["level"] = "bad"
        return rep
    with open(path, "rb") as f:
        rep["sha256"] = hashlib.sha256(f.read()).hexdigest()
    rep["bytes"] = os.path.getsize(path)

    try:
        zf = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        add("bad", "zip", "the file is not a zip")
        rep["level"] = "bad"
        return rep
    with zf:
        say("checking the zip, every file's CRC")
        bad = zf.testzip()
        if bad:
            add("bad", "zip integrity", "%s is damaged (CRC mismatch)" % bad)
        else:
            add("ok", "zip integrity", "%d files, every CRC matches" % len(zf.namelist()))
        for i in zf.infolist():
            rep["files"].append({"name": i.filename, "bytes": i.file_size,
                                 "packed": i.compress_size})

        # tables and columns
        for name, cols in REQUIRED.items():
            r = _rows(zf, name)
            if r is None:
                add("bad", name, "missing")
                continue
            miss = [c for c in cols if c not in (r.fieldnames or [])]
            if miss:
                add("bad", name, "no %s column" % ", ".join(miss))
        # One of the two calendars is enough; the others are extras.
        if not (_member(zf, "calendar.txt") or _member(zf, "calendar_dates.txt")):
            add("bad", "calendar", "neither calendar.txt nor calendar_dates.txt")

        # agency and feed_info
        ag = list(_rows(zf, "agency.txt") or [])
        rep["feed"]["agency"] = ag[0].get("agency_name", "") if ag else ""
        rep["feed"]["timezone"] = ag[0].get("agency_timezone", "") if ag else ""
        fi = list(_rows(zf, "feed_info.txt") or [])
        if fi:
            rep["feed"].update({k: fi[0].get(k, "") for k in
                                ("feed_version", "feed_start_date", "feed_end_date", "feed_publisher_name")})

        # stops
        say("reading stops")
        stops, outside, nocoord, dup, far = {}, 0, 0, 0, []
        for row in _rows(zf, "stops.txt") or []:
            sid = row.get("stop_id", "")
            if sid in stops:
                dup += 1
            try:
                lat, lon = float(row.get("stop_lat") or "x"), float(row.get("stop_lon") or "x")
                if not (LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX):
                    outside += 1
                    far.append("%s %s (%s, %s)" % (sid, row.get("stop_name", ""), row.get("stop_lat"), row.get("stop_lon")))
            except ValueError:
                nocoord += 1
                lat = lon = None
            stops[sid] = row.get("stop_name", "")
        rep["counts"]["stops"] = len(stops)
        if dup:
            add("bad", "stops", "%d stop ids appear twice" % dup)
        if nocoord:
            add("bad", "stop positions", "%d stops have no usable position" % nocoord)
        elif outside:
            add("warn", "stop positions", "%d of %d stops lie outside the Zagreb area: %s" % (
                outside, len(stops), ", ".join(far[:4]) + (" …" if len(far) > 4 else "")))
        else:
            add("ok", "stop positions", "all %d stops inside the Zagreb area" % len(stops))

        # routes
        routes, rtype = {}, {}
        for row in _rows(zf, "routes.txt") or []:
            routes[row.get("route_id", "")] = row
            t = ROUTE_TYPES.get(row.get("route_type", ""), "type " + row.get("route_type", "?"))
            rtype[t] = rtype.get(t, 0) + 1
        rep["counts"]["routes"] = len(routes)
        rep["routes_by_type"] = rtype
        noname = sum(1 for r in routes.values() if not r.get("route_short_name"))
        add("warn" if noname else "ok", "routes",
            "%d lines: %s%s" % (len(routes), ", ".join("%d %s" % (n, t) for t, n in sorted(rtype.items())),
                                ", %d without a number" % noname if noname else ""))

        # calendar: which services run on which date
        say("reading the calendar")
        services = {}
        wd = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for row in _rows(zf, "calendar.txt") or []:
            services.setdefault(row.get("service_id", ""), {"cal": row, "add": set(), "del": set()})
        for row in _rows(zf, "calendar_dates.txt") or []:
            s = services.setdefault(row.get("service_id", ""), {"cal": None, "add": set(), "del": set()})
            (s["add"] if row.get("exception_type") == "1" else s["del"]).add(row.get("date", ""))

        def runs(sid, day):
            s = services.get(sid)
            if not s:
                return False
            y = _ymd(day)
            if y in s["del"]:
                return False
            if y in s["add"]:
                return True
            c = s["cal"]
            return bool(c) and c.get("start_date", "9") <= y <= c.get("end_date", "0") \
                and c.get(wd[day.weekday()]) == "1"

        # trips
        say("reading trips")
        trips, trips_by_service, routes_trips = {}, {}, {}
        no_route = no_service = no_shape = dup = 0
        shapes_present = set()
        sh = _rows(zf, "shapes.txt")
        if sh is not None:
            for row in sh:
                shapes_present.add(row.get("shape_id", ""))
        for row in _rows(zf, "trips.txt") or []:
            tid = row.get("trip_id", "")
            if tid in trips:
                dup += 1
            trips[tid] = (row.get("route_id", ""), row.get("service_id", ""))
            if row.get("route_id") not in routes:
                no_route += 1
            if row.get("service_id") not in services:
                no_service += 1
            if shapes_present and row.get("shape_id") and row["shape_id"] not in shapes_present:
                no_shape += 1
            trips_by_service[row.get("service_id", "")] = trips_by_service.get(row.get("service_id", ""), 0) + 1
            routes_trips[row.get("route_id", "")] = routes_trips.get(row.get("route_id", ""), 0) + 1
        rep["counts"]["trips"] = len(trips)
        rep["counts"]["shape_ids"] = len(shapes_present)
        probs = []
        if dup:
            probs.append("%d trip ids twice" % dup)
        if no_route:
            probs.append("%d name a line that does not exist" % no_route)
        if no_service:
            probs.append("%d name a service with no calendar" % no_service)
        if no_shape:
            probs.append("%d name a shape that is not there" % no_shape)
        add("bad" if (dup or no_route or no_service) else ("warn" if no_shape else "ok"),
            "trips", "; ".join(probs) if probs else "%d trips, every one tied to a line and a calendar" % len(trips))
        unused = [r for r in routes if not routes_trips.get(r)]
        if unused:
            add("warn", "lines without trips", "%d lines have no trips: %s" % (
                len(unused), ", ".join(routes[r].get("route_short_name") or r for r in unused[:8])))

        # stop_times, the big one
        say("reading stop_times, all of it (the long part)")
        n = bad_time = backwards = no_trip = no_stop = seq_bad = 0
        last = {}
        per_stop = {}
        has_times = set()
        for row in _rows(zf, "stop_times.txt") or []:
            n += 1
            if n % 250000 == 0:
                say("  %d rows" % n)
            tid, sid = row.get("trip_id", ""), row.get("stop_id", "")
            if tid not in trips:
                no_trip += 1
            if sid not in stops:
                no_stop += 1
            a, d = _secs(row.get("arrival_time", "")), _secs(row.get("departure_time", ""))
            if a is None or d is None:
                bad_time += 1
            elif d < a:
                backwards += 1
            try:
                q = int(row.get("stop_sequence") or -1)
            except ValueError:
                q = -1
            p = last.get(tid)
            if p is not None and (q <= p[0] or (d is not None and p[1] is not None and d < p[1])):
                seq_bad += 1
            last[tid] = (q, d)
            has_times.add(tid)
            per_stop[sid] = per_stop.get(sid, 0) + 1
        rep["counts"]["stop_times"] = n
        probs = []
        if no_trip:
            probs.append("%d rows name a trip that does not exist" % no_trip)
        if no_stop:
            probs.append("%d rows name a stop that does not exist" % no_stop)
        if bad_time:
            probs.append("%d times cannot be read" % bad_time)
        if backwards:
            probs.append("%d leave before they arrive" % backwards)
        if seq_bad:
            probs.append("%d go back in order or in time within their trip" % seq_bad)
        add("bad" if (no_trip or no_stop or bad_time) else ("warn" if (backwards or seq_bad) else "ok"),
            "stop_times", "; ".join(probs) if probs else
            "%d rows, every one on a real trip and a real stop, times in order" % n)
        empty = len(trips) - len(has_times & set(trips))
        if empty:
            add("warn", "trips without times", "%d trips have no stop_times at all" % empty)
        rep["top_stops"] = [{"stop_id": s, "name": stops.get(s, "?"), "departures": c}
                            for s, c in sorted(per_stop.items(), key=lambda x: -x[1])[:10]]

        # service: today and the days ahead
        today = datetime.date.today()
        days = []
        for i in range(0, 15):
            day = today + datetime.timedelta(days=i)
            live = [s for s in services if runs(s, day)]
            days.append({"date": _ymd(day), "trips": sum(trips_by_service.get(s, 0) for s in live)})
        rep["service"]["days"] = days
        all_dates = set()
        for s in services.values():
            all_dates |= s["add"]
            c = s["cal"]
            if c:
                all_dates.add(c.get("end_date", ""))
        end = max([d for d in all_dates if d] or [""]) or rep["feed"].get("feed_end_date", "")
        rep["service"]["last_date"] = end
        if days[0]["trips"] == 0:
            add("bad", "today", "no trip runs today in this schedule: it is expired or not yet valid")
        else:
            add("ok", "today", "%d trips run today" % days[0]["trips"])
        dead = [d["date"] for d in days[1:8] if d["trips"] == 0]
        if dead:
            add("warn", "the week ahead", "no service at all on %s" % ", ".join(_fmt_ymd(d) for d in dead))
        else:
            add("ok", "the week ahead", "service on every one of the next seven days")
        start = rep["feed"].get("feed_start_date", "")
        if start and start > _ymd(today):
            add("warn", "feed start", "this feed only starts on %s" % _fmt_ymd(start))

        # freshness of what is on the phone
        meta = _load(META, {})
        if meta.get("checked"):
            age = (_now() - meta["checked"]) / 3600.0
            add("ok" if age < 48 else "warn", "asked ZET",
                "%s ago" % (("%d hours" % age) if age < 48 else ("%d days" % (age / 24))))

    order = {"ok": 0, "warn": 1, "bad": 2}
    rep["level"] = max((c["level"] for c in checks), key=lambda l: order[l]) if checks else "ok"
    rep["seconds"] = round(_now() - t0, 1)
    return rep


def check(force=False, say=None):
    """The deep check of the file that is here, kept per file hash so it runs
    once per schedule and not every time somebody looks."""
    old = _load(HEALTH, {})
    sha = ""
    if os.path.isfile(ZIP):
        with open(ZIP, "rb") as f:
            sha = hashlib.sha256(f.read()).hexdigest()
    if not force and sha and old.get("sha256") == sha and \
            old.get("checked_at", 0) > _now() - 6 * 3600:
        return old
    rep = deep_check(ZIP, say=say)
    if rep.get("sha256"):
        _save(HEALTH, rep)
        _history("checked", level=rep["level"], seconds=rep.get("seconds"), sha=rep["sha256"][:12])
    write_status(rep)
    return rep


def write_status(rep=None):
    """One line the launcher can read without starting python: version|level|date|port."""
    rep = rep or _load(HEALTH, {})
    meta = _load(META, {})
    port = ""
    try:
        with open(PORTFILE) as f:
            port = f.read().strip()
    except Exception:
        pass
    line = "%s|%s|%s|%s\n" % (meta.get("feed_version") or rep.get("feed", {}).get("feed_version", ""),
                              rep.get("level", "?") if rep.get("sha256") == meta.get("sha256") else "?",
                              time.strftime("%-d.%-m.", time.localtime(meta.get("fetched") or meta.get("checked") or 0))
                              if meta else "", port)
    try:
        os.makedirs(GDIR, exist_ok=True)
        with open(STATUS, "w") as f:
            f.write(line)
    except Exception:
        pass


# ---------------------------------------------------------------------------
# the terminal
# ---------------------------------------------------------------------------
TTY = sys.stdout.isatty()


def _c(code, text):
    return "\033[%sm%s\033[0m" % (code, text) if TTY else text


C_OK, C_WARN, C_BAD = "1;32", "38;5;214", "1;31"
C_KEY, C_DIM, C_SAND, C_AM = "1;37", "0;90", "38;5;223", "38;5;214"
MARK = {"ok": _c(C_OK, "ok  "), "warn": _c(C_WARN, "look"), "bad": _c(C_BAD, "FAIL")}


def show(rep=None):
    rep = rep or _load(HEALTH, {})
    meta = _load(META, {})
    W = 46

    def head(t):
        print("\n  " + _c(C_AM, t))

    def kv(k, v):
        print("    " + _c(C_DIM, "%-11s" % k) + str(v))

    print("\n  " + _c(C_KEY, "ZET GTFS") + "  " + _c(C_DIM, "the schedule all three apps share"))
    if not rep.get("sha256"):
        print("\n  " + _c(C_DIM, "no schedule here yet"))
        return
    lvl = rep.get("level", "?")
    word = {"ok": _c(C_OK, "HEALTHY"), "warn": _c(C_WARN, "USABLE, LOOK BELOW"),
            "bad": _c(C_BAD, "BROKEN")}.get(lvl, lvl)
    print("  " + word)

    head("SOURCE")
    kv("from", (meta.get("url") or URLS[0]).replace("https://", ""))
    kv("size", "%.1f MB packed, %.0f MB of tables" % (
        rep.get("bytes", 0) / 1048576.0, sum(f["bytes"] for f in rep.get("files", [])) / 1048576.0))
    if meta.get("last_modified"):
        kv("published", meta["last_modified"].replace(" GMT", "")[5:22])
    if meta.get("fetched"):
        kv("downloaded", time.strftime("%-d.%-m.%Y %H:%M", time.localtime(meta["fetched"])))
    if meta.get("checked"):
        kv("asked ZET", time.strftime("%-d.%-m.%Y %H:%M", time.localtime(meta["checked"])))
    kv("sha256", rep.get("sha256", "")[:16])

    f = rep.get("feed", {})
    head("FEED")
    kv("agency", f.get("agency", "?")[:W - 15])
    kv("version", f.get("feed_version") or "?")
    if f.get("feed_start_date"):
        kv("valid", "%s to %s" % (_fmt_ymd(f.get("feed_start_date")), _fmt_ymd(f.get("feed_end_date"))))
    last = rep.get("service", {}).get("last_date")
    if last:
        try:
            left = (datetime.datetime.strptime(last, "%Y%m%d").date() - datetime.date.today()).days
            kv("last day", "%s, %d days from now" % (_fmt_ymd(last), left))
        except Exception:
            pass

    head("TABLES")
    cnt = rep.get("counts", {})
    for fi in rep.get("files", []):
        key = fi["name"].replace(".txt", "")
        rows = cnt.get(key)
        print("    " + _c(C_SAND, "%-19s" % fi["name"]) + _c(C_DIM, "%7.1f MB" % (fi["bytes"] / 1048576.0)) +
              ("   %9d rows" % rows if rows is not None else ""))
    rt = rep.get("routes_by_type", {})
    if rt:
        kv("lines", ", ".join("%d %s" % (n, t) for t, n in sorted(rt.items())))
    if cnt.get("shape_ids"):
        kv("shapes", "%d drawn routes" % cnt["shape_ids"])

    days = rep.get("service", {}).get("days", [])
    if days:
        head("TRIPS PER DAY, THE NEXT TWO WEEKS")
        top = max(d["trips"] for d in days) or 1
        for d in days:
            dt = datetime.datetime.strptime(d["date"], "%Y%m%d")
            bar = "#" * int(round(22.0 * d["trips"] / top))
            print("    " + _c(C_DIM, dt.strftime("%a %d.%m.")) + " " +
                  _c(C_OK if d["trips"] else C_BAD, "%-22s" % bar) + " %5d" % d["trips"])

    head("HEALTH")
    for ch in rep.get("checks", []):
        print("    %s %s" % (MARK.get(ch["level"], ch["level"]), _c(C_SAND, ch["name"])))
        for line in textwrap.wrap(ch["detail"], W - 6) or [""]:
            print("         " + _c(C_DIM, line))

    ts = rep.get("top_stops", [])[:5]
    if ts:
        head("BUSIEST STOPS")
        for s in ts:
            print("    " + _c(C_SAND, "%-8s" % s["stop_id"]) + "%-26s" % s["name"][:26] +
                  _c(C_DIM, "%6d" % s["departures"]))
    print("\n  " + _c(C_DIM, "checked in %ss" % rep.get("seconds", "?")))


def update():
    """Key 4: ask ZET for the newest file, check it, show it."""
    print("\n  " + _c(C_KEY, "1  DOWNLOAD") + "  " + _c(C_DIM, "the newest ZET schedule"))

    def prog(got, total):
        if TTY:
            if total:
                pct = 100.0 * got / total
                bar = "#" * int(pct / 4)
                sys.stdout.write("\r    %-25s %5.1f%% %5.1f MB" % (bar, pct, got / 1048576.0))
            else:
                sys.stdout.write("\r    %5.1f MB" % (got / 1048576.0))
            sys.stdout.flush()

    try:
        _, _ = fetch(force=False, who=None, max_age=0, progress=prog,
                     log=lambda m: print(("\n" if TTY else "") + "    " + _c(C_DIM, m.strip())))
    except Exception as e:
        print("\n    " + _c(C_BAD, str(e)))
    print("\n  " + _c(C_KEY, "2  CHECK") + "  " + _c(C_DIM, "every table, every reference, every date"))
    rep = check(force=False, say=lambda m: print("    " + _c(C_DIM, m)))
    print("  " + _c(C_KEY, "3  THE DATA"))
    show(rep)
    return rep


# ---------------------------------------------------------------------------
# reading the data, for the web page
# ---------------------------------------------------------------------------
_cache = {}
_cache_lock = threading.Lock()


def _zip():
    return zipfile.ZipFile(ZIP)


def _cached(key, build):
    sha = _load(META, {}).get("sha256", "")
    with _cache_lock:
        if _cache.get("_sha") != sha:
            _cache.clear()
            _cache["_sha"] = sha
        if key in _cache:
            return _cache[key]
    val = build()
    with _cache_lock:
        _cache[key] = val
    return val


def data_routes():
    def build():
        with _zip() as zf:
            trips, heads = {}, {}
            for r in _rows(zf, "trips.txt"):
                rid = r["route_id"]
                trips[rid] = trips.get(rid, 0) + 1
                h = heads.setdefault(rid, {})
                h[r.get("trip_headsign", "")] = h.get(r.get("trip_headsign", ""), 0) + 1
            out = []
            for r in _rows(zf, "routes.txt"):
                rid = r["route_id"]
                out.append({"id": rid, "short": r.get("route_short_name", ""), "long": r.get("route_long_name", ""),
                            "type": ROUTE_TYPES.get(r.get("route_type", ""), r.get("route_type", "")),
                            "color": r.get("route_color", ""), "trips": trips.get(rid, 0),
                            "heads": sorted(heads.get(rid, {}).items(), key=lambda x: -x[1])[:4]})

            def k(x):
                s = x["short"]
                return (x["type"], int(s) if s.isdigit() else 9999, s)
            return sorted(out, key=k)
    return _cached("routes", build)


def data_stops():
    def build():
        with _zip() as zf:
            return [{"id": r["stop_id"], "code": r.get("stop_code", ""), "name": r.get("stop_name", ""),
                     "lat": r.get("stop_lat", ""), "lon": r.get("stop_lon", ""),
                     "parent": r.get("parent_station", "")} for r in _rows(zf, "stops.txt")]
    return _cached("stops", build)


def _services_on(zf, day):
    wd = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"][day.weekday()]
    y = _ymd(day)
    on = set()
    for r in _rows(zf, "calendar.txt") or []:
        if r.get("start_date", "9") <= y <= r.get("end_date", "0") and r.get(wd) == "1":
            on.add(r["service_id"])
    for r in _rows(zf, "calendar_dates.txt") or []:
        if r.get("date") == y:
            (on.add if r.get("exception_type") == "1" else on.discard)(r["service_id"])
    return on


def data_departures(stop_id, day=None):
    day = day or datetime.date.today()

    def build():
        with _zip() as zf:
            on = _services_on(zf, day)
            routes = {r["route_id"]: r for r in _rows(zf, "routes.txt")}
            trips = {}
            for r in _rows(zf, "trips.txt"):
                if r["service_id"] in on:
                    trips[r["trip_id"]] = r
            out = []
            for r in _rows(zf, "stop_times.txt"):
                if r["stop_id"] == stop_id and r["trip_id"] in trips:
                    t = trips[r["trip_id"]]
                    rt = routes.get(t["route_id"], {})
                    out.append({"time": r["departure_time"], "route": rt.get("route_short_name", t["route_id"]),
                                "type": ROUTE_TYPES.get(rt.get("route_type", ""), ""),
                                "head": t.get("trip_headsign", ""), "trip": r["trip_id"]})
            return sorted(out, key=lambda x: _secs(x["time"]) or 0)
    return _cached("dep:%s:%s" % (stop_id, _ymd(day)), build)


def data_file(name, q="", offset=0, limit=100):
    """Raw rows of one table, filtered by a substring, streamed so stop_times
    never has to sit in memory."""
    q = (q or "").lower()
    with _zip() as zf:
        m = _member(zf, name)
        if not m:
            return {"header": [], "rows": [], "more": False}
        rd = csv.reader(io.TextIOWrapper(zf.open(m), encoding="utf-8-sig", newline=""))
        header = next(rd, [])
        rows, seen, more = [], 0, False
        for row in rd:
            if q and q not in ",".join(row).lower():
                continue
            if seen >= offset:
                if len(rows) >= limit:
                    more = True
                    break
                rows.append(row)
            seen += 1
        return {"header": header, "rows": rows, "more": more, "offset": offset}


# ---------------------------------------------------------------------------
# the web monitor
# ---------------------------------------------------------------------------
JOB = {"running": False, "what": "", "lines": [], "done": 0}


def _job(what, fn):
    if JOB["running"]:
        return False

    def run():
        JOB.update({"running": True, "what": what, "lines": [], "done": 0})
        try:
            fn(lambda m: JOB["lines"].append(m.strip()))
        except Exception as e:
            JOB["lines"].append("failed: %r" % (e,))
        finally:
            JOB.update({"running": False, "done": int(_now())})
    threading.Thread(target=run, daemon=True).start()
    return True


def _port_free(p):
    """Only a port that ANSWERS is taken (MANTRA_MANIFEST modules/ports.md):
    a refused connection is free, and a port in TIME_WAIT is free too."""
    s = socket.socket()
    s.settimeout(0.3)
    try:
        return s.connect_ex(("127.0.0.1", p)) != 0
    finally:
        s.close()


def pick_port():
    for p in range(PORT_FIRST, PORT_FIRST + 16):
        if _port_free(p):
            return p
    s = socket.socket()
    s.bind(("0.0.0.0", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def make_app():
    from flask import Flask, jsonify, request, Response
    app = Flask("maha-gtfs")

    @app.get("/")
    def page():
        return Response(PAGE.replace("@@VERSION@@", VERSION), mimetype="text/html")

    @app.get("/api/health")
    def api_health():
        h = _load(HEALTH, {})
        m = _load(META, {})
        return jsonify({"health": h, "meta": {k: v for k, v in m.items() if k != "seen"},
                        "seen": m.get("seen", {}), "current": h.get("sha256") == m.get("sha256"),
                        "history": history(30), "job": JOB, "dir": GDIR, "version": VERSION})

    @app.post("/api/fetch")
    def api_fetch():
        force = request.args.get("force") == "1"
        ok = _job("download", lambda say: (fetch(force=force, max_age=0, log=say), check(say=say)))
        return jsonify({"ok": ok})

    @app.post("/api/check")
    def api_check():
        return jsonify({"ok": _job("check", lambda say: check(force=True, say=say))})

    @app.get("/api/job")
    def api_job():
        return jsonify(JOB)

    @app.get("/api/routes")
    def api_routes():
        return jsonify(data_routes() if os.path.isfile(ZIP) else [])

    @app.get("/api/stops")
    def api_stops():
        q = (request.args.get("q") or "").lower().strip()
        st = data_stops() if os.path.isfile(ZIP) else []
        if q:
            st = [s for s in st if q in s["name"].lower() or q == s["id"].lower() or q == s["code"]]
        return jsonify(st[:200])

    @app.get("/api/departures")
    def api_dep():
        sid = request.args.get("stop", "")
        d = request.args.get("date", "")
        day = datetime.datetime.strptime(d, "%Y%m%d").date() if d else None
        return jsonify(data_departures(sid, day))

    @app.get("/api/file")
    def api_file():
        return jsonify(data_file(request.args.get("name", ""), request.args.get("q", ""),
                                 int(request.args.get("offset", 0)), min(int(request.args.get("limit", 100)), 500)))

    return app


def serve(open_page=True):
    try:
        app = make_app()
    except ImportError:
        print("  the web monitor needs Flask:  pip install flask waitress")
        return 2
    port = pick_port()
    os.makedirs(GDIR, exist_ok=True)
    with open(PORTFILE, "w") as f:
        f.write(str(port))
    write_status()
    url = "http://127.0.0.1:%d/" % port
    print("  GTFS monitor on %s" % url, flush=True)
    if open_page:
        threading.Timer(0.8, _open, args=(url,)).start()
    try:
        try:
            from waitress import serve as wserve
            wserve(app, host="0.0.0.0", port=port, threads=6)
        except ImportError:
            print("  (waitress is not here, so this is Flask's own server)", flush=True)
            app.run(host="0.0.0.0", port=port, threaded=True)
    finally:
        try:
            with open(PORTFILE) as f:
                mine = f.read().strip() == str(port)
            if mine:
                os.remove(PORTFILE)
            write_status()
        except OSError:
            pass
    return 0


def _open(url):
    import subprocess
    for cmd in (["am", "start", "-a", "android.intent.action.VIEW", "-d", url],
                ["termux-open-url", url], ["xdg-open", url], ["open", url]):
        try:
            r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=8)
            if r.returncode == 0:
                return
        except Exception:
            continue


PAGE = r'''<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>ZET GTFS</title>
<style>
:root{--bg:#0d1117;--card:#141a22;--border:#2a323d;--text:#e6edf3;--muted:#8b949e;
  --cyan:#39d0d8;--gold:#d4a017;--green:#3fb950;--red:#f85149;--amber:#ff9f1c;}
@media (prefers-color-scheme: light){:root:not([data-theme="dark"]){--bg:#f6f8fa;--card:#fff;
  --border:#d0d7de;--text:#1f2328;--muted:#656d76;--cyan:#0a7f86;--gold:#9a6700;--green:#1a7f37;--red:#cf222e;--amber:#bc4c00;}}
*{box-sizing:border-box}
html,body{margin:0;background:var(--bg);color:var(--text);font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
header{position:sticky;top:0;z-index:5;background:var(--bg);border-bottom:1px solid var(--border);
  padding:12px 16px 0;padding-top:calc(12px + env(safe-area-inset-top))}
.top{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.top h1{margin:0;font-size:1.05rem;letter-spacing:.04em}
.top .sub{color:var(--muted);font-size:.78rem;font-weight:600}
.badge{padding:4px 10px;border-radius:999px;font:800 .72rem/1 system-ui;letter-spacing:.06em;border:1.5px solid}
.badge.ok{color:var(--green);border-color:var(--green)} .badge.warn{color:var(--amber);border-color:var(--amber)}
.badge.bad{color:var(--red);border-color:var(--red)} .badge.unk{color:var(--muted);border-color:var(--border)}
nav{display:flex;gap:2px;overflow-x:auto;margin-top:10px}
nav button{flex:none;border:0;background:transparent;color:var(--muted);padding:10px 12px;font:700 .82rem/1 system-ui;
  border-bottom:2px solid transparent;cursor:pointer}
nav button.on{color:var(--cyan);border-bottom-color:var(--cyan)}
main{padding:14px 16px 40px;max-width:980px;margin:0 auto}
.card{background:var(--card);border:1px solid var(--border);border-radius:14px;padding:14px;margin-bottom:14px}
.card h2{margin:0 0 10px;font-size:.78rem;letter-spacing:.09em;text-transform:uppercase;color:var(--muted)}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px}
.stat b{display:block;font-size:1.35rem;font-variant-numeric:tabular-nums}
.stat span{color:var(--muted);font-size:.74rem;font-weight:600}
.kv{display:flex;justify-content:space-between;gap:12px;padding:5px 0;border-bottom:1px solid var(--border);font-size:.84rem}
.kv:last-child{border-bottom:0} .kv span{color:var(--muted)} .kv b{text-align:right;word-break:break-all}
.chk{display:grid;grid-template-columns:auto 1fr;gap:4px 10px;padding:8px 0;border-bottom:1px solid var(--border)}
.chk:last-child{border-bottom:0}
.lv{font:800 .66rem/1 system-ui;letter-spacing:.06em;padding:4px 6px;border-radius:6px;align-self:start;margin-top:2px}
.lv.ok{background:color-mix(in srgb,var(--green) 18%,transparent);color:var(--green)}
.lv.warn{background:color-mix(in srgb,var(--amber) 18%,transparent);color:var(--amber)}
.lv.bad{background:color-mix(in srgb,var(--red) 18%,transparent);color:var(--red)}
.chk b{font-size:.88rem} .chk i{grid-column:2;font-style:normal;color:var(--muted);font-size:.8rem;line-height:1.4}
.bars{display:grid;grid-template-columns:auto 1fr auto;gap:5px 10px;align-items:center;font-size:.78rem}
.bars .bar{height:10px;border-radius:5px;background:var(--cyan)} .bars .zero{background:var(--red);width:4px}
.bars span{color:var(--muted);font-variant-numeric:tabular-nums} .bars em{font-style:normal;text-align:right;font-variant-numeric:tabular-nums}
.btns{display:flex;gap:8px;flex-wrap:wrap}
.btn{border:1px solid var(--border);background:var(--card);color:var(--text);border-radius:10px;padding:10px 14px;
  font:700 .82rem/1 system-ui;cursor:pointer} .btn.main{border-color:var(--cyan);color:var(--cyan)}
.btn:disabled{opacity:.5}
.log{font:600 .74rem/1.5 ui-monospace,Menlo,monospace;color:var(--muted);white-space:pre-wrap;margin-top:10px;max-height:180px;overflow:auto}
input.q{width:100%;padding:11px 12px;border-radius:10px;border:1px solid var(--border);background:var(--card);color:var(--text);
  font:600 .9rem system-ui;margin-bottom:12px}
table{width:100%;border-collapse:collapse;font-size:.8rem}
th,td{text-align:left;padding:7px 8px;border-bottom:1px solid var(--border);vertical-align:top}
th{color:var(--muted);font-size:.7rem;letter-spacing:.05em;text-transform:uppercase;position:sticky;top:0;background:var(--card)}
.tw{overflow:auto;max-height:65vh;border:1px solid var(--border);border-radius:10px;background:var(--card)}
.rt{display:inline-flex;min-width:34px;justify-content:center;padding:4px 7px;border-radius:7px;font-weight:800;
  background:var(--cyan);color:#0d1117} .rt.bus{background:var(--gold)}
tr.click{cursor:pointer} tr.click:hover td{background:color-mix(in srgb,var(--cyan) 7%,transparent)}
.muted{color:var(--muted)} .pill{display:inline-block;padding:3px 8px;border-radius:999px;border:1px solid var(--border);
  font-size:.72rem;margin:2px 4px 2px 0;color:var(--muted)}
.files{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:12px}
.files button{border:1px solid var(--border);background:transparent;color:var(--muted);border-radius:8px;padding:7px 10px;
  font:700 .76rem system-ui;cursor:pointer} .files button.on{border-color:var(--cyan);color:var(--cyan)}
.hide{display:none}
</style></head><body>
<header>
  <div class="top"><h1>ZET GTFS</h1><span id="lvl" class="badge unk">…</span>
    <span class="sub" id="topsub">the schedule all three apps share · @@VERSION@@</span></div>
  <nav id="tabs">
    <button data-t="health" class="on">Health</button><button data-t="routes">Lines</button>
    <button data-t="stops">Stops</button><button data-t="files">Tables</button><button data-t="history">History</button>
  </nav>
</header>
<main>
  <section id="t-health">
    <div class="card"><div class="btns">
      <button class="btn main" id="bFetch">Download the newest</button>
      <button class="btn" id="bForce">Download again, whole</button>
      <button class="btn" id="bCheck">Check again</button></div>
      <div class="log" id="log"></div></div>
    <div class="card"><h2>At a glance</h2><div class="grid" id="stats"></div></div>
    <div class="card"><h2>Health</h2><div id="checks"></div></div>
    <div class="card"><h2>Trips per day, the next two weeks</h2><div class="bars" id="days"></div></div>
    <div class="card"><h2>Feed and source</h2><div id="feed"></div></div>
    <div class="card"><h2>Busiest stops</h2><div id="top"></div></div>
  </section>
  <section id="t-routes" class="hide"><input class="q" id="rq" placeholder="Filter lines: 6, Dubec, tram…"><div class="tw"><table id="rtab"></table></div></section>
  <section id="t-stops" class="hide"><input class="q" id="sq" placeholder="Find a stop: Jelačić, Črnomerec, 104_1…">
    <div id="slist"></div><div id="sdep"></div></section>
  <section id="t-files" class="hide"><div class="files" id="flist"></div><input class="q" id="fq" placeholder="Filter rows in this table">
    <div class="tw"><table id="ftab"></table></div><div class="btns" style="margin-top:10px"><button class="btn" id="fmore">More rows</button></div></section>
  <section id="t-history" class="hide"><div class="card"><h2>Every fetch and check</h2><div id="hist"></div></div>
    <div class="card"><h2>What each app last saw</h2><div id="seen"></div></div></section>
</main>
<script>
const $ = id => document.getElementById(id);
const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const ymd = s => s && s.length === 8 ? (+s.slice(6)) + "." + (+s.slice(4,6)) + "." + s.slice(0,4) : (s || "—");
const when = t => t ? new Date(t * 1000).toLocaleString("hr-HR", {day:"numeric",month:"numeric",year:"numeric",hour:"2-digit",minute:"2-digit"}) : "—";
const mb = b => (b / 1048576).toFixed(1) + " MB";
let H = null, FILE = "routes.txt", FOFF = 0, polling = null;
const WORD = {ok:"HEALTHY", warn:"LOOK", bad:"BROKEN"};

document.querySelectorAll("#tabs button").forEach(b => b.onclick = () => tab(b.dataset.t));
function tab(t){
  document.querySelectorAll("#tabs button").forEach(b => b.classList.toggle("on", b.dataset.t === t));
  document.querySelectorAll("main > section").forEach(s => s.classList.toggle("hide", s.id !== "t-" + t));
  if (t === "routes") loadRoutes(); if (t === "files") loadFile(); if (t === "history") paintHistory();
  try { localStorage.setItem("gtfs_tab", t); } catch (e) {}
}

async function loadHealth(){
  H = await fetch("api/health").then(r => r.json());
  const h = H.health || {}, m = H.meta || {};
  const lv = H.current && h.level ? h.level : "unk";
  $("lvl").className = "badge " + lv; $("lvl").textContent = WORD[lv] || (m.sha256 ? "NOT CHECKED" : "NO DATA");
  const c = h.counts || {}, f = h.feed || {};
  const left = h.service && h.service.last_date ? Math.round((new Date(h.service.last_date.slice(0,4)+"-"+h.service.last_date.slice(4,6)+"-"+h.service.last_date.slice(6)) - new Date()) / 864e5) : null;
  $("stats").innerHTML = [["version", f.feed_version || m.feed_version || "—"], ["lines", c.routes], ["stops", c.stops],
    ["trips", c.trips], ["stop times", c.stop_times], ["today", h.service && h.service.days ? h.service.days[0].trips + " trips" : "—"],
    ["days left", left == null ? "—" : left], ["downloaded", m.fetched ? new Date(m.fetched*1000).toLocaleDateString("hr-HR") : "—"]]
    .map(([k, v]) => '<div class="stat"><b>' + esc(v == null ? "—" : (typeof v === "number" ? v.toLocaleString("hr-HR") : v)) + '</b><span>' + k + '</span></div>').join("");
  $("checks").innerHTML = (h.checks || []).map(x => '<div class="chk"><span class="lv ' + x.level + '">' +
    (x.level === "ok" ? "OK" : x.level === "warn" ? "LOOK" : "FAIL") + '</span><b>' + esc(x.name) + '</b><i>' + esc(x.detail) + '</i></div>').join("")
    || '<span class="muted">Not checked yet. Download, or Check again.</span>';
  const days = (h.service && h.service.days) || [], top = Math.max(1, ...days.map(d => d.trips));
  $("days").innerHTML = days.map(d => { const dt = new Date(d.date.slice(0,4)+"-"+d.date.slice(4,6)+"-"+d.date.slice(6));
    return '<span>' + dt.toLocaleDateString("hr-HR",{weekday:"short",day:"numeric",month:"numeric"}) + '</span><div><div class="bar' + (d.trips ? "" : " zero") +
      '" style="width:' + (d.trips ? Math.max(2, 100 * d.trips / top) : 1) + '%"></div></div><em>' + d.trips.toLocaleString("hr-HR") + '</em>'; }).join("");
  const kv = (k, v) => '<div class="kv"><span>' + k + '</span><b>' + esc(v || "—") + '</b></div>';
  $("feed").innerHTML = kv("agency", f.agency) + kv("valid", f.feed_start_date ? ymd(f.feed_start_date) + " – " + ymd(f.feed_end_date) : "") +
    kv("last service day", ymd(h.service && h.service.last_date)) + kv("published by ZET", m.last_modified) +
    kv("downloaded", when(m.fetched)) + kv("last asked ZET", when(m.checked)) + kv("size", m.bytes ? mb(m.bytes) : "") +
    kv("sha256", (m.sha256 || "").slice(0, 16)) + kv("from", m.url) + kv("folder", H.dir) + kv("checked in", h.seconds ? h.seconds + " s" : "");
  $("top").innerHTML = '<table><tr><th>stop</th><th>name</th><th>departures</th></tr>' + (h.top_stops || []).map(s =>
    '<tr class="click" data-stop="' + esc(s.stop_id) + '"><td>' + esc(s.stop_id) + '</td><td>' + esc(s.name) + '</td><td>' + s.departures.toLocaleString("hr-HR") + '</td></tr>').join("") + '</table>';
  paintJob(H.job);
}
$("top").onclick = e => { const r = e.target.closest("[data-stop]"); if (r) { tab("stops"); showStop(r.dataset.stop); } };

function paintJob(j){
  const busy = j && j.running;
  ["bFetch","bForce","bCheck"].forEach(id => $(id).disabled = busy);
  $("log").textContent = j && j.lines && j.lines.length ? (busy ? "working: " + j.what + "\n" : "") + j.lines.join("\n") : "";
  if (busy && !polling) polling = setInterval(async () => {
    const jj = await fetch("api/job").then(r => r.json()); paintJob(jj);
    if (!jj.running) { clearInterval(polling); polling = null; loadHealth(); }
  }, 800);
}
async function start(url){ await fetch(url, {method:"POST"}); const j = await fetch("api/job").then(r => r.json()); paintJob(j); }
$("bFetch").onclick = () => start("api/fetch");
$("bForce").onclick = () => start("api/fetch?force=1");
$("bCheck").onclick = () => start("api/check");

let ROUTES = [];
async function loadRoutes(){
  if (!ROUTES.length) ROUTES = await fetch("api/routes").then(r => r.json());
  const q = $("rq").value.toLowerCase();
  const rows = ROUTES.filter(r => !q || (r.short + " " + r.long + " " + r.type + " " + r.heads.map(h => h[0]).join(" ")).toLowerCase().includes(q));
  $("rtab").innerHTML = '<tr><th>line</th><th>name</th><th>type</th><th>trips</th><th>headsigns</th></tr>' + rows.map(r =>
    '<tr><td><span class="rt ' + (r.type === "bus" ? "bus" : "") + '">' + esc(r.short || r.id) + '</span></td><td>' + esc(r.long) + '</td><td class="muted">' + esc(r.type) +
    '</td><td>' + r.trips.toLocaleString("hr-HR") + '</td><td>' + r.heads.map(h => '<span class="pill">' + esc(h[0] || "—") + ' ' + h[1] + '</span>').join("") + '</td></tr>').join("");
}
$("rq").oninput = loadRoutes;

let sT = null;
$("sq").oninput = () => { clearTimeout(sT); sT = setTimeout(findStops, 250); };
async function findStops(){
  const q = $("sq").value.trim(); $("sdep").innerHTML = "";
  if (q.length < 2) { $("slist").innerHTML = ""; return; }
  const st = await fetch("api/stops?q=" + encodeURIComponent(q)).then(r => r.json());
  $("slist").innerHTML = '<div class="tw"><table><tr><th>stop</th><th>code</th><th>name</th><th>position</th></tr>' + st.map(s =>
    '<tr class="click" data-stop="' + esc(s.id) + '"><td>' + esc(s.id) + '</td><td>' + esc(s.code) + '</td><td>' + esc(s.name) + '</td><td class="muted">' + esc(s.lat) + ", " + esc(s.lon) + '</td></tr>').join("") + '</table></div>';
}
$("slist").onclick = e => { const r = e.target.closest("[data-stop]"); if (r) showStop(r.dataset.stop); };
async function showStop(id){
  $("sdep").innerHTML = '<div class="card"><span class="muted">Reading every departure of ' + esc(id) + ' today… the whole stop_times table is read, a few seconds.</span></div>';
  const d = await fetch("api/departures?stop=" + encodeURIComponent(id)).then(r => r.json());
  const now = new Date(), secs = now.getHours()*3600 + now.getMinutes()*60;
  const toS = t => { const p = t.split(":"); return +p[0]*3600 + +p[1]*60 + +p[2]; };
  const next = d.findIndex(x => toS(x.time) >= secs);
  $("sdep").innerHTML = '<div class="card"><h2>' + esc(id) + ' · ' + d.length + ' departures today in the schedule</h2><div class="tw"><table><tr><th>time</th><th>line</th><th>to</th></tr>' +
    d.map((x, i) => '<tr' + (i === next ? ' id="nextdep" style="outline:2px solid var(--cyan)"' : "") + (i < next ? ' class="muted"' : "") + '><td>' + esc(x.time.slice(0,5)) +
      '</td><td><span class="rt ' + (x.type === "bus" ? "bus" : "") + '">' + esc(x.route) + '</span></td><td>' + esc(x.head) + '</td></tr>').join("") + '</table></div></div>';
  const n = $("nextdep"); if (n) n.scrollIntoView({block:"center"});
}

async function loadFile(more){
  if (!more) FOFF = 0;
  const files = ((H && H.health && H.health.files) || []).map(f => f.name);
  $("flist").innerHTML = files.map(f => '<button class="' + (f === FILE ? "on" : "") + '" data-f="' + esc(f) + '">' + esc(f) + '</button>').join("");
  const d = await fetch("api/file?name=" + encodeURIComponent(FILE) + "&q=" + encodeURIComponent($("fq").value) + "&offset=" + FOFF + "&limit=100").then(r => r.json());
  const body = d.rows.map(r => '<tr>' + r.map(c => '<td>' + esc(c) + '</td>').join("") + '</tr>').join("");
  if (more) $("ftab").insertAdjacentHTML("beforeend", body);
  else $("ftab").innerHTML = '<tr>' + d.header.map(h => '<th>' + esc(h) + '</th>').join("") + '</tr>' + body;
  FOFF += d.rows.length; $("fmore").classList.toggle("hide", !d.more);
}
$("flist").onclick = e => { const b = e.target.closest("[data-f]"); if (b) { FILE = b.dataset.f; loadFile(); } };
let fT = null; $("fq").oninput = () => { clearTimeout(fT); fT = setTimeout(() => loadFile(), 300); };
$("fmore").onclick = () => loadFile(true);

function paintHistory(){
  if (!H) return;
  $("hist").innerHTML = (H.history || []).map(x => '<div class="kv"><span>' + when(x.t) + '</span><b>' + esc(x.event) +
    (x.who ? " · " + esc(x.who) : "") + (x.version ? " · v" + esc(x.version) : "") + (x.level ? " · " + esc(x.level) : "") +
    (x.reason ? " · " + esc(x.reason) : "") + (x.bytes ? " · " + mb(x.bytes) : "") + '</b></div>').join("") || '<span class="muted">nothing yet</span>';
  const cur = (H.meta || {}).sha256;
  $("seen").innerHTML = ["day", "night", "all"].map(a => { const s = (H.seen || {})[a];
    return '<div class="kv"><span>' + a + '.commute</span><b>' + (!s ? "has not asked yet" : s === cur ? "the current schedule" : "an older schedule, until it next asks") + '</b></div>'; }).join("");
}

loadHealth().then(() => { try { const t = localStorage.getItem("gtfs_tab"); if (t) tab(t); } catch (e) {} });
setInterval(() => { if (!polling) loadHealth(); }, 60000);
</script></body></html>'''


# ---------------------------------------------------------------------------
def main(argv):
    cmd = argv[1] if len(argv) > 1 else "update"
    if cmd == "update":
        rep = update()
        return 0 if rep.get("level") != "bad" else 1
    if cmd == "fetch":
        fetch(force="--force" in argv, max_age=0, log=print)
        return 0
    if cmd == "check":
        rep = check(force=True, say=print)
        show(rep)
        return 0 if rep.get("level") != "bad" else 1
    if cmd == "show":
        show()
        return 0
    if cmd == "serve":
        return serve(open_page="--no-open" not in argv)
    if cmd == "status":
        write_status()
        with open(STATUS) as f:
            print(f.read().strip())
        return 0
    print(__doc__.split("THE COMMANDS")[1].split("The apps")[0])
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
