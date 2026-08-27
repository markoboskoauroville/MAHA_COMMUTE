#!/data/data/com.termux/files/usr/bin/bash
# 13-install-day-commute-termux-v13.sh  (Commute family — daytime app installer)
# Self-contained installer for DAY COMMUTE ॐ. Writes
# everything into ~/.commute and a `day.commute` command. Type `day.commute` (or
# `ma commute`): it picks the first free port from 8082, binds 0.0.0.0 for
# Wi-Fi, runs in the foreground with the shared banner and the warm Aum
# signature, and opens the app. The schedule is fetched ONCE per day (whole
# day) and cached smartly; tap a bus for a full-screen map with a 5-page
# driver dashboard (Now / Stops / Trip / Status / Live), pin a ride with
# "Keep on list", pick a ride with the green circle, widen the window with
# the "next N h" pill. v7 brings back the COMMUTE PILLS: one summary pill per
# route option in the active direction (next two departures at a glance, tap
# to unfold a vertical schedule), shown on BOTH source tabs, GTFS (live cached
# schedule) and PDF (printed-timetable style vertical listing per route, with
# a link to the official ZET vozni red PDF of each line).
#
# v13 quiets the terminal and frees the screen. A phone drops sockets
# constantly and the server used to print a full traceback each time, which
# looked like a crash; every connection error is now swallowed and real faults
# go to ~/.commute/server.log instead of the screen. On the page the GTFS
# label, the source row and the Om mark are gone, and the line filters start
# folded behind a small triangle at the end of the direction bar, so the
# departures own the top of the screen. The triangle turns cyan on its own
# whenever a filter is actually hiding something.
#
# v12 makes the direction and the source choose themselves. The phone's
# position picks the corridor: near home (Pavlinovicheva) it opens the ride to
# Nova TV, near Nova TV it opens the ride to Glavni kolodvor, near Britanski trg
# it opens the Britanac corridor. A switch is only made when one anchor is the
# clear winner after the GPS error is subtracted, since home and Britanski trg
# are a few hundred metres apart, and tapping a direction by hand holds it for
# twenty minutes. The GTFS and PDF buttons are gone. GTFS is simply the source;
# when a build arrives empty or broken the app falls to the printed timetables
# on its own and climbs back the moment GTFS is healthy again. All that is left
# is a small label on the left saying which one is speaking, with the detected
# place on the right.
#
# v11 changes the first load of the day. The GTFS static schedule downloads by
# itself the moment the server starts, in the background, and the manual
# refresh icon is gone. The app opens instantly on the stored copy of the
# matching day type, so schedule and direction pills are already on screen
# while the new data arrives, and the screen repaints quietly when it lands.
# ZET runs one schedule Monday to Friday and separate ones on Saturday, on
# Sunday and on public holidays, so each type is buffered on its own under
# ~/.commute/daycache, and next Saturday and next Sunday are built ahead from
# the same zip during the week so the weekend also opens with no wait.
#
# Before anything is written the installer draws a dependency table, green OK
# for what is already on the phone and red MISSING for what is not, and only
# then asks whether to install offline with what is there or to fetch the
# missing pieces first.
#
#   bash 13-install-day-commute-termux-v13.sh            Enter = offline, y = install deps
#   bash 13-install-day-commute-termux-v13.sh --online   install the missing deps
#   bash 13-install-day-commute-termux-v13.sh --offline  skip the python check

set -e
COMMUTE_VERSION="v13"
BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
APPDIR="$HOME/.commute"

GOOGLE_KEY="__MAHA_GOOGLE_KEY__"

MODE=""
for a in "$@"; do
  case "$a" in
    --online|--full|--deps) MODE="online" ;;
    --offline) MODE="offline" ;;
    -h|--help) printf "usage: bash 13-install-day-commute-termux-v13.sh [--online] [--offline]\n"; exit 0 ;;
  esac
done

if [ -t 1 ]; then
  A="\033[1;36m"; M="\033[1;35m"; OK="\033[1;32m"; WARN="\033[1;33m"
  KEY="\033[1;37m"; DIM="\033[0;90m"; RED="\033[1;31m"; SAF="\033[38;5;208m"
  OFF="\033[0m"
else
  A=""; M=""; OK=""; WARN=""; KEY=""; DIM=""; RED=""; SAF=""; OFF=""
fi
type_line() { local s="$1"; local i
  for ((i=0; i<${#s}; i++)); do printf "%s" "${s:$i:1}"; sleep 0.004; done; printf "\n"; }
step() { printf "  ${A}▸${OFF} %s" "$1"; local i; for i in 1 2 3; do printf "."; sleep 0.10; done; }
done_() { printf " ${OK}ok${OFF}\n"; }
skip_() { printf " ${DIM}skipped${OFF}\n"; }

clear 2>/dev/null
printf "\n"
printf "  ${A}▌${OFF} "; type_line "$(printf '%bDAY COMMUTE%b  %bॐ%b' "$KEY" "$OFF" "$SAF" "$OFF")"
printf "  ${A}▌${OFF} ${DIM}installer %s${OFF}\n\n" "$COMMUTE_VERSION"

# ---------------------------------------------------------------------------
# Dependency table. Everything the app leans on is looked at first and shown
# in one place, green OK for what is already here, red MISSING for what is
# not, before anything at all is written to the phone. Only then is the
# install mode chosen, so the choice is made with the whole picture in view.
# ---------------------------------------------------------------------------
DEP_REQ_MISSING=0
DEP_OPT_MISSING=0

dep_rule() { printf "  ${DIM}%s${OFF}\n" \
  "──────────────────────────────────────────────────────"; }

# dep_row <name> <what it is for> <have 0|1> <required 0|1>
dep_row() {
  local n="$1" p="$2" have="$3" req="$4"
  if [ "$have" = "1" ]; then
    printf "  ${KEY}%-17s${OFF} ${DIM}%-29s${OFF} ${OK}%s${OFF}\n" "$n" "$p" "OK"
  elif [ "$req" = "1" ]; then
    printf "  ${KEY}%-17s${OFF} ${DIM}%-29s${OFF} ${RED}%s${OFF}\n" "$n" "$p" "MISSING"
    DEP_REQ_MISSING=$((DEP_REQ_MISSING + 1))
  else
    printf "  ${KEY}%-17s${OFF} ${DIM}%-29s${OFF} ${RED}%s${OFF} ${DIM}%s${OFF}\n" \
      "$n" "$p" "MISSING" "(optional)"
    DEP_OPT_MISSING=$((DEP_OPT_MISSING + 1))
  fi
}

have() { command -v "$1" >/dev/null 2>&1 && echo 1 || echo 0; }

HAVE_TERMUX=0
[ -n "${PREFIX:-}" ] && [ -d "$BIN" ] && HAVE_TERMUX=1
HAVE_PY="$(have python)"
HAVE_OPEN="$(have termux-open-url)"
HAVE_AM="$(have am)"
HAVE_GEM=0
[ -s "$APPDIR/gemini-api.txt" ] && HAVE_GEM=1
HAVE_MAPS=0
[ -s "$APPDIR/google-api.txt" ] && HAVE_MAPS=1
for c in "./google-api.txt" "$HOME/storage/downloads/google-api.txt" "$HOME/downloads/google-api.txt"; do
  [ -f "$c" ] && HAVE_MAPS=1
done
[ -n "$GOOGLE_KEY" ] && HAVE_MAPS=1        # the installer writes the built-in key
HAVE_NET=0
if [ "$HAVE_PY" = "1" ]; then
  python - >/dev/null 2>&1 <<'NETCHK' && HAVE_NET=1
import urllib.request
urllib.request.urlopen("https://www.zet.hr", timeout=5)
NETCHK
fi

printf "  ${DIM}%-17s %-29s %s${OFF}\n" "DEPENDENCY" "WHAT IT IS FOR" "STATUS"
dep_rule
dep_row "Termux"          "the shell this installs into"  "$HAVE_TERMUX" 1
dep_row "python"          "the server and the timetable"  "$HAVE_PY"     1
dep_row "ZET reachable"   "downloading today's schedule"  "$HAVE_NET"    0
dep_row "termux-open-url" "opens the app in the browser"  "$HAVE_OPEN"   0
dep_row "am"              "the fallback browser opener"   "$HAVE_AM"     0
dep_row "Google Maps key" "the live bus map"              "$HAVE_MAPS"   0
dep_row "Gemini key"      "reading the printed ZET PDFs"  "$HAVE_GEM"    0
dep_rule
if [ "$DEP_REQ_MISSING" -gt 0 ]; then
  printf "  ${RED}%d required missing${OFF}${DIM}, %d optional missing${OFF}\n\n" \
    "$DEP_REQ_MISSING" "$DEP_OPT_MISSING"
elif [ "$DEP_OPT_MISSING" -gt 0 ]; then
  printf "  ${OK}everything required is here${OFF}${DIM}, %d optional missing${OFF}\n\n" \
    "$DEP_OPT_MISSING"
else
  printf "  ${OK}everything is here${OFF}\n\n"
fi

if [ "$HAVE_TERMUX" != "1" ]; then
  printf "  ${WARN}this installer is for Termux on Android${OFF}\n\n"; exit 1
fi

# The choice, made after the table rather than before it.
if [ -z "$MODE" ]; then
  printf "  install mode:\n"
  printf "    ${KEY}Enter${OFF}  ${DIM}offline, install the app with what is already here${OFF}\n"
  printf "    ${KEY}y${OFF}      ${DIM}install the missing dependencies first, then the app${OFF}\n"
  if [ "$DEP_REQ_MISSING" -gt 0 ]; then
    printf "\n  ${WARN}something required is missing, y is the one to press${OFF}\n"
  fi
  printf "\n  ${A}>${OFF} "
  IFS= read -r ANS || ANS=""
  case "$ANS" in [yY]*) MODE="online" ;; *) MODE="offline" ;; esac
fi
printf "  ${DIM}mode: %s${OFF}\n\n" "$MODE"

if [ "$MODE" = "online" ]; then
  step "python runtime"
  if [ "$HAVE_PY" != "1" ]; then
    printf " ${WARN}installing${OFF}\n"
    pkg install -y python >/dev/null 2>&1 || yes | pkg install python
    step "python runtime"
    done_
  else
    done_
  fi
  step "termux-api tools"
  if [ "$HAVE_OPEN" != "1" ]; then
    printf " ${WARN}installing${OFF}\n"
    pkg install -y termux-api >/dev/null 2>&1 || true
    step "termux-api tools"
    done_
  else
    done_
  fi
else
  step "dependency install"; skip_
fi

step "app folder"
mkdir -p "$APPDIR" 2>/dev/null || true
done_

step "api key"
KEYFILE="$APPDIR/google-api.txt"
DROP=""
for c in "./google-api.txt" "$HOME/storage/downloads/google-api.txt" "$HOME/downloads/google-api.txt"; do
  [ -f "$c" ] && { DROP="$c"; break; }
done
if [ -n "$DROP" ]; then
  grep -v '^[[:space:]]*$' "$DROP" > "$KEYFILE"
  printf " ${DIM}(from %s)${OFF}" "$DROP"
elif [ ! -f "$KEYFILE" ]; then
  printf '%s\n' "$GOOGLE_KEY" > "$KEYFILE"
fi
done_

step "installing server"
cat > "$APPDIR/commute_server.py" << 'CMT_SERVER_PY'
#!/usr/bin/env python3
"""
commute_server.py — minimal local server for the Commute app only.

Serves just the Commute front-end (bus.html) and its data, plus the three
endpoints it needs: refresh timetable, live map position, live arrival times.
Nothing else. No folder listing, no other apps. It picks the first free port
from 8082 upward, writes it to ~/.commute/port, and logs quietly to
~/.commute/server.log, never to the screen. The `commute` command starts it.
"""
import os
import json
import time
import datetime
import subprocess
import urllib.parse
import urllib.request
import http.server

# Version constants for the /version endpoint. These live in Python because the
# server file is written via a quoted heredoc, so the shell COMMUTE_VERSION is
# NOT expanded in here; referencing it raised NameError. Keep in sync manually.
APP_VERSION = "v13"
APP_BUILD = "b41"
import socket
import socketserver
import sys
import threading

APPDIR = os.environ.get("COMMUTE_DIR", os.path.expanduser("~/.commute"))
START_PORT = int(os.environ.get("COMMUTE_PORT", "8082"))
PORT_TRIES = 40
STATE_DIR = APPDIR
PORTFILE = os.path.join(STATE_DIR, "port")
LOGFILE = os.path.join(STATE_DIR, "server.log")
KEYFILE = os.path.join(APPDIR, "google-api.txt")
BUS_UPDATER = os.path.join(APPDIR, "update_bus.py")
ARCH_DIR = os.path.join(APPDIR, "daycache")
TRIPS_PATH = os.path.join(APPDIR, "trips_path.json")
GTFS_RT_URL = "https://zet.hr/gtfs-rt-protobuf"

# Only these files are ever served; anything else returns 404.
ALLOWED_FILES = {"bus.html", "bus.json", "trips_path.json", "favicon.ico"}
CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".ico": "image/x-icon",
}


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


# ---------------------------------------------------------------------------
# v8: PDF route scheduler. Downloads the official ZET vozni red PDF of a
# line, asks Gemini to read the three day columns, caches the parsed JSON
# next to the PDF, and serves it to the front-end so the commute pills work
# even while the GTFS feed is broken. One Gemini call per PDF version.
# ---------------------------------------------------------------------------
import base64
import hashlib
import re as _re
import zlib as _zlib

PDF_DIR = os.path.join(APPDIR, "pdf")
GEMINI_KEYFILE = os.path.join(APPDIR, "gemini-api.txt")
GEMINI_MODELS = ["gemini-2.5-flash", "gemini-2.0-flash"]
ZET_PDF = ("https://www.zet.hr/UserDocsImages/"
           "Autobusne%20linije%20-%20rasporedi/{r}.pdf")
_PDF_LOCK = threading.Lock()


def read_gemini_keys():
    keys = []
    for path in (GEMINI_KEYFILE, KEYFILE):
        try:
            with open(path, encoding="utf-8") as f:
                keys += [ln.strip() for ln in f if ln.strip()]
        except OSError:
            pass
    return keys


def write_gemini_keys(keys):
    os.makedirs(APPDIR, exist_ok=True)
    with open(GEMINI_KEYFILE, "w", encoding="utf-8") as f:
        f.write("\n".join(keys) + ("\n" if keys else ""))


def _safe_route(r):
    return _re.sub(r"[^0-9A-Za-z]", "", r)[:8]


def _pdf_path(r):
    return os.path.join(PDF_DIR, _safe_route(r) + ".pdf")


def _sched_path(r):
    return os.path.join(PDF_DIR, _safe_route(r) + ".json")


def _download_pdf(r):
    """Fetch the line PDF; keep a cached copy for 24 h; keep the old copy
    when ZET is unreachable."""
    path = _pdf_path(r)
    os.makedirs(PDF_DIR, exist_ok=True)
    # Permanent cache: once a line PDF is on disk we never refetch it. The
    # user clears it explicitly from the PDF manager in the gear.
    if os.path.isfile(path):
        return path
    url = ZET_PDF.format(r=urllib.parse.quote(_safe_route(r)))
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "commute-pdf/1"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
        if data[:5] != b"%PDF-":
            raise ValueError("not a PDF")
        with open(path, "wb") as f:
            f.write(data)
        _log("pdf %s downloaded, %d bytes" % (r, len(data)))
    except Exception as e:
        _log("pdf %s download failed: %r" % (r, e))
        if not os.path.isfile(path):
            raise
    return path


_TIME_RX = _re.compile(r"\b([0-2]?\d)[:.]([0-5]\d)\b")


def _regex_times(pdf_bytes):
    """Crude no-Gemini fallback: inflate the content streams and pull every
    HH:MM shaped token. No day columns, marked approximate."""
    found = set()
    for m in _re.finditer(rb"stream(.*?)endstream", pdf_bytes, _re.S):
        raw = m.group(1).strip(b"\r\n")
        candidates = [raw]
        try:
            candidates.append(_zlib.decompress(raw))
        except Exception:
            pass
        try:
            candidates.append(_zlib.decompress(
                base64.a85decode(raw, adobe=True, ignorechars=b" \t\r\n")))
        except Exception:
            pass
        for candidate in candidates:
            txt = candidate.decode("latin-1", "ignore")
            for t in _TIME_RX.finditer(txt):
                h, mn = int(t.group(1)), t.group(2)
                if h <= 27:
                    found.add("%02d:%s" % (h, mn))
    return sorted(found)


def _norm_times(lst):
    out = sorted({t for t in (lst or [])
                  if _re.match(r"^\d{1,2}:\d{2}$", str(t))},
                 key=lambda t: (int(t.split(":")[0]), int(t.split(":")[1])))
    return ["%02d:%s" % (int(t.split(":")[0]), t.split(":")[1]) for t in out]


def _gemini_parse(r, pdf_bytes, key):
    # Ask for EVERY terminal column separately, named by its terminal, so the
    # app can show the times that actually start from the terminal you use in
    # each direction (e.g. 241 from Glavni kolodvor vs from Veliko polje).
    prompt = (
        "This PDF is an official ZET Zagreb bus timetable (vozni red) for "
        "line " + _safe_route(r) + ". It usually lists departures for BOTH "
        "directions, each under its own starting terminal (polazak s ...). "
        "Extract EACH direction separately with the name of the terminal the "
        "times start from. Reply with ONLY minified JSON, no markdown, exactly: "
        '{"name":"line name","directions":['
        '{"terminal":"terminal name","workday":["HH:MM",...],'
        '"saturday":["HH:MM",...],"sunday":["HH:MM",...]}]} '
        "One object per terminal/direction. 24h times sorted ascending; missing "
        "day column = []. If the line is circular with a single terminal, return "
        "just one direction object."
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
    for model in GEMINI_MODELS:
        url = ("https://generativelanguage.googleapis.com/v1beta/models/"
               + model + ":generateContent?key=" + urllib.parse.quote(key))
        try:
            req = urllib.request.Request(
                url, data=body, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=90) as resp:
                out = json.loads(resp.read().decode("utf-8", "replace"))
            txt = out["candidates"][0]["content"]["parts"][0]["text"]
            txt = txt.strip().strip("`")
            if txt.lower().startswith("json"):
                txt = txt[4:].strip()
            j = json.loads(txt[txt.find("{"):txt.rfind("}") + 1])
            dirs = j.get("directions") or []
            for dd in dirs:
                for k in ("workday", "saturday", "sunday"):
                    dd[k] = _norm_times(dd.get(k))
            j["directions"] = dirs
            # flat keys = first terminal, for any old code path
            first = dirs[0] if dirs else {}
            for k in ("workday", "saturday", "sunday"):
                j[k] = first.get(k, [])
            j["source"] = "gemini:" + model
            return j
        except Exception as e:
            last = e
            _log("gemini %s/%s failed: %r" % (model, r, e))
    raise RuntimeError("gemini failed: %r" % (last,))


def pdf_sched_for(r, force=False):
    """Return the parsed schedule for one route, using every cache layer."""
    with _PDF_LOCK:
        path = _download_pdf(r)
        with open(path, "rb") as f:
            pdf_bytes = f.read()
        digest = hashlib.md5(pdf_bytes).hexdigest()
        sp = _sched_path(r)
        if not force:
            try:
                with open(sp, encoding="utf-8") as f:
                    cached = json.load(f)
                if cached.get("md5") == digest and cached.get("directions") is not None:
                    cached["cached"] = True
                    return cached
            except Exception:
                pass
        keys = read_gemini_keys()
        parsed = None
        err = None
        for key in keys:
            try:
                parsed = _gemini_parse(r, pdf_bytes, key)
                break
            except Exception as e:
                err = repr(e)
        if parsed is None:
            times = _regex_times(pdf_bytes)
            parsed = {"name": "", "workday": times, "saturday": times,
                      "sunday": times, "source": "regex-approx",
                      "approx": True,
                      "directions": [{"terminal": "", "workday": times,
                                      "saturday": times, "sunday": times}],
                      "error": err or "no Gemini key, add one in the gear"}
        parsed["md5"] = digest
        parsed["route"] = _safe_route(r)
        parsed["fetched"] = int(time.time())
        try:
            with open(sp, "w", encoding="utf-8") as f:
                json.dump(parsed, f, ensure_ascii=False)
        except Exception:
            pass
        return parsed


def pdf_sched_payload(routes, force=False):
    out = {"ok": True, "routes": {}}
    for r in routes[:12]:
        try:
            out["routes"][_safe_route(r)] = pdf_sched_for(r, force)
        except Exception as e:
            out["routes"][_safe_route(r)] = {"ok": False, "error": repr(e)}
    return out


def pdf_list_payload():
    """Everything cached on disk, for the PDF manager in the gear."""
    items = []
    try:
        names = os.listdir(PDF_DIR)
    except OSError:
        names = []
    for fn in sorted(names):
        if not fn.endswith(".pdf"):
            continue
        r = fn[:-4]
        pdfp = os.path.join(PDF_DIR, fn)
        schedp = _sched_path(r)
        size = 0
        try:
            size = os.path.getsize(pdfp)
        except OSError:
            pass
        src, ok = None, False
        try:
            with open(schedp, encoding="utf-8") as f:
                j = json.load(f)
            src = j.get("source")
            ok = bool(j.get("directions"))
        except Exception:
            pass
        items.append({"route": r, "bytes": size, "parsed": ok, "source": src})
    return {"ok": True, "items": items}


def pdf_delete(route, all_):
    removed = []
    try:
        names = os.listdir(PDF_DIR)
    except OSError:
        names = []
    targets = []
    if all_:
        targets = [n[:-4] for n in names if n.endswith(".pdf")]
    elif route:
        targets = [_safe_route(route)]
    for r in targets:
        for path in (_pdf_path(r), _sched_path(r)):
            try:
                if os.path.isfile(path):
                    os.remove(path)
            except OSError:
                pass
        removed.append(r)
    return {"ok": True, "removed": removed}


def key_status_payload(which):
    """Green/red only: is a working key present? Never returns the key."""
    if which == "gemini":
        keys = read_gemini_keys()
        if not keys:
            return {"ok": True, "set": False, "working": False}
        for key in keys:
            url = ("https://generativelanguage.googleapis.com/v1beta/models?key="
                   + urllib.parse.quote(key))
            try:
                req = urllib.request.Request(url)
                with urllib.request.urlopen(req, timeout=15) as resp:
                    if resp.status == 200:
                        return {"ok": True, "set": True, "working": True}
            except Exception as e:
                _log("gemini key test failed: %r" % (e,))
        return {"ok": True, "set": True, "working": False}
    # maps: we cannot cheaply verify; report presence only
    keys = read_keys()
    return {"ok": True, "set": bool(keys), "working": bool(keys)}


def _read_varint(b, i):
    shift = 0
    result = 0
    while True:
        byte = b[i]
        i += 1
        result |= (byte & 0x7F) << shift
        if not (byte & 0x80):
            break
        shift += 7
    return result, i


def _fields(b, start, end):
    i = start
    while i < end:
        tag, i = _read_varint(b, i)
        fn, wt = tag >> 3, tag & 7
        if wt == 0:
            val, i = _read_varint(b, i)
            yield fn, 0, val
        elif wt == 2:
            ln, i = _read_varint(b, i)
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
    # protobuf int32/int64 negatives are stored as 64-bit two's complement
    return v - (1 << 64) if v >= (1 << 63) else v


def _parse_event(b, s, e):
    delay = None
    t = None
    for fn, wt, val in _fields(b, s, e):
        if fn == 1 and wt == 0:
            delay = _signed(val)
        elif fn == 2 and wt == 0:
            t = val
    return t, delay


def _parse_stu(b, s, e):
    seq = None
    stop_id = None
    t = None
    delay = None
    for fn, wt, val in _fields(b, s, e):
        if fn == 1 and wt == 0:
            seq = val
        elif fn == 4 and wt == 2:
            stop_id = b[val[0]:val[1]].decode("utf-8", "replace")
        elif fn == 3 and wt == 2:          # departure preferred
            t, delay = _parse_event(b, val[0], val[1])
        elif fn == 2 and wt == 2 and t is None:  # arrival fallback
            t, delay = _parse_event(b, val[0], val[1])
    return seq, stop_id, t, delay


def _parse_trip_update(b, s, e):
    trip_id = None
    stus = []
    for fn, wt, val in _fields(b, s, e):
        if fn == 1 and wt == 2:            # TripDescriptor
            for f2, w2, v2 in _fields(b, val[0], val[1]):
                if f2 == 1 and w2 == 2:    # trip_id
                    trip_id = b[v2[0]:v2[1]].decode("utf-8", "replace")
        elif fn == 2 and wt == 2:          # repeated StopTimeUpdate
            stus.append(_parse_stu(b, val[0], val[1]))
    return trip_id, stus


def rt_trip_updates(buf, want_trip):
    """Return the list of (seq, stop_id, time, delay) for want_trip, or None."""
    for fn, wt, val in _fields(buf, 0, len(buf)):
        if fn == 2 and wt == 2:            # FeedEntity
            for f2, w2, v2 in _fields(buf, val[0], val[1]):
                if f2 == 3 and w2 == 2:    # trip_update
                    tid, stus = _parse_trip_update(buf, v2[0], v2[1])
                    if tid == want_trip:
                        return stus
    return None


def rt_updates_for(buf, want_set):
    """Return {trip_id: [(seq, stop_id, time, delay), ...]} for trips in want_set."""
    out = {}
    for fn, wt, val in _fields(buf, 0, len(buf)):
        if fn == 2 and wt == 2:            # FeedEntity
            for f2, w2, v2 in _fields(buf, val[0], val[1]):
                if f2 == 3 and w2 == 2:    # trip_update
                    tid, stus = _parse_trip_update(buf, v2[0], v2[1])
                    if tid in want_set:
                        out[tid] = stus
    return out


def rt_count(buf):
    """Count how many trips are currently present in the live feed."""
    n = 0
    for fn, wt, val in _fields(buf, 0, len(buf)):
        if fn == 2 and wt == 2:            # FeedEntity
            for f2, w2, v2 in _fields(buf, val[0], val[1]):
                if f2 == 3 and w2 == 2:    # trip_update
                    n += 1
    return n


def zet_status_payload():
    """Status of the live feed for the ZET dashboard."""
    out = {"checked": int(time.time())}
    try:
        out["trips"] = rt_count(fetch_rt())
        out["ok"] = True
    except Exception as e:
        out["ok"] = False
        out["reason"] = repr(e)
    return out


# small cache so several map opens in a row reuse one download
_rt_cache = {"t": 0.0, "data": None}
_trips_cache = {"mtime": 0.0, "data": None}


def fetch_rt():
    now = time.time()
    if _rt_cache["data"] is not None and now - _rt_cache["t"] < 8:
        return _rt_cache["data"]
    req = urllib.request.Request(
        GTFS_RT_URL, headers={"User-Agent": "bus-rt/1"})
    with urllib.request.urlopen(req, timeout=12) as r:
        data = r.read()
    _rt_cache["t"] = now
    _rt_cache["data"] = data
    return data


def load_trips():
    try:
        m = os.path.getmtime(TRIPS_PATH)
    except OSError:
        return {}
    if _trips_cache["data"] is None or m != _trips_cache["mtime"]:
        with open(TRIPS_PATH, encoding="utf-8") as f:
            _trips_cache["data"] = json.load(f).get("trips", {})
        _trips_cache["mtime"] = m
    return _trips_cache["data"]


def bus_rt_payload(trip_id):
    stops = load_trips().get(trip_id)
    if not stops:
        return {"ok": False, "reason": "no path for trip (schedule still building)"}

    midnight = int(datetime.datetime.now().replace(
        hour=0, minute=0, second=0, microsecond=0).timestamp())
    sched_by_stop = {}
    for s in stops:
        sched_by_stop.setdefault(s["stop_id"], s["t"])

    delay = 0
    source = "schedule"
    live_list = []        # every StopTimeUpdate the feed has for this trip
    rt_n = 0
    try:
        buf = fetch_rt()
        rt_n = rt_count(buf)
        stus = rt_trip_updates(buf, trip_id)
        if stus:
            now = time.time()
            best = None        # prefer the soonest still-upcoming stop
            for seq, stop_id, t, evdelay in stus:
                d = None
                if evdelay is not None:
                    d = evdelay
                elif t is not None and stop_id in sched_by_stop:
                    d = t - (midnight + sched_by_stop[stop_id])
                live_list.append({
                    "seq": seq,
                    "stop_id": stop_id,
                    "t": (int(t) if t is not None else None),
                    "d": (int(d) if d is not None else None),
                })
                if d is None:
                    continue
                rt_abs = t if t is not None else (
                    midnight + sched_by_stop.get(stop_id, 0) + d)
                future = rt_abs >= now
                cand = (0 if future else 1, abs(rt_abs - now), d)
                if best is None or cand[:2] < best[:2]:
                    best = cand
            if best is not None:
                delay = int(best[2])
                source = "realtime"
    except Exception as e:
        source = "schedule"
        delay = 0
        _ = e

    return {
        "ok": True,
        "trip": trip_id,
        "delay": delay,
        "source": source,
        "now": int(time.time()),
        "midnight": midnight,
        "rt_entities": rt_n,
        "rt_updates": len(live_list),
        "live": live_list,
        "stops": stops,
    }


def bus_live_payload(trip_ids):
    """For a set of trips, return the live predicted time + delay at each stop.

    Shape: {ok, now, trips: {trip_id: {stops: {stop_id: {t, d}}, delay}}}
    where t is a POSIX time (predicted) and d is seconds late (+) / early (-).
    delay is a trip-level fallback (soonest upcoming stop).
    """
    want = {t for t in trip_ids if t}
    out = {"ok": True, "now": int(time.time()), "trips": {}}
    if not want:
        return out
    try:
        updates = rt_updates_for(fetch_rt(), want)
    except Exception as e:
        out["ok"] = False
        out["reason"] = repr(e)
        return out

    now = time.time()
    for tid, stus in updates.items():
        per_stop = {}
        fallback = None
        for seq, stop_id, t, d in stus:
            if stop_id is None:
                continue
            per_stop[stop_id] = {"t": t, "d": d}
            if d is not None:
                rt_abs = t if t is not None else now
                cand = (0 if rt_abs >= now else 1, abs(rt_abs - now), d)
                if fallback is None or cand[:2] < fallback[:2]:
                    fallback = cand
        out["trips"][tid] = {
            "stops": per_stop,
            "delay": int(fallback[2]) if fallback else None,
        }
    return out


# ---------------------------------------------------------------------------
# Instant boot. The app never waits for ZET: it is served whatever the last
# download left on disk for this day type (Monday to Friday share one
# schedule, Saturday, Sunday and holidays each have their own), renders the
# pills at once, and a fresh build runs in the background.
# ---------------------------------------------------------------------------
_upd = {"running": False, "started": 0.0, "ok": None, "reason": ""}
_upd_lock = threading.Lock()


def _easter_srv(y):
    a = y % 19; b = y // 100; c = y % 100
    d = b // 4; e = b % 4; f = (b + 8) // 25; g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i = c // 4; k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    return datetime.date(y, month, day)


def _holidays(y):
    e = _easter_srv(y)
    days = {
        datetime.date(y, 1, 1), datetime.date(y, 1, 6),
        e, e + datetime.timedelta(days=1),
        datetime.date(y, 5, 1), e + datetime.timedelta(days=60),
        datetime.date(y, 5, 30), datetime.date(y, 6, 22),
        datetime.date(y, 8, 5), datetime.date(y, 8, 15),
        datetime.date(y, 11, 1), datetime.date(y, 11, 18),
        datetime.date(y, 12, 25), datetime.date(y, 12, 26),
    }
    return {x.strftime("%Y%m%d") for x in days}


def daytype_for(d):
    if d.strftime("%Y%m%d") in _holidays(d.year):
        return "holiday"
    wd = d.weekday()
    return "sat" if wd == 5 else "sun" if wd == 6 else "weekday"


def _read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _window_from_now(payload, now):
    """A buffered day starts at midnight, so its minute counters are stale.
    Recompute them against the clock and drop what has already gone."""
    if not payload:
        return None
    now_mins = now.hour * 60 + now.minute
    for d in payload.get("directions", []):
        keep = []
        for dep in d.get("departures", []):
            t = str(dep.get("time") or "")
            if len(t) < 4 or ":" not in t:
                continue
            hh, mm = t.split(":")[0:2]
            try:
                mins = int(hh) * 60 + int(mm) - now_mins
            except ValueError:
                continue
            if mins < -3:
                continue
            dep["mins_from_now"] = mins
            keep.append(dep)
        d["departures"] = keep
        if d.get("featured"):
            d["featured"] = [f for f in d["featured"]
                             if str(f.get("time", "")) >= "%02d:%02d"
                             % (now.hour, now.minute)]
    return payload


def schedule_payload():
    """What the app boots on. Fresh copy when today is already built,
    otherwise the stored copy of this day type, rewindowed to the clock and
    flagged stale so the app can quietly refresh behind it."""
    now = datetime.datetime.now()
    ymd = now.strftime("%Y%m%d")
    dt = daytype_for(now.date())
    fresh = _read_json(os.path.join(APPDIR, "bus.json"))
    if fresh and fresh.get("service_date") == ymd and fresh.get("whole_day"):
        fresh["stale"] = False
        fresh["daytype"] = fresh.get("daytype") or dt
        fresh["updating"] = _upd["running"]
        return fresh
    # exact day type first, then the nearest sensible stand in, so the screen
    # is never empty while the real download runs
    order = [dt] + (["sun"] if dt == "holiday" else []) + ["weekday"]
    order += [x for x in ("sat", "sun", "holiday") if x not in order]
    for cand in order:
        buf = _read_json(os.path.join(ARCH_DIR, "bus.%s.json" % cand))
        if buf and buf.get("directions"):
            buf = _window_from_now(buf, now)
            buf["stale"] = True
            buf["buffer_of"] = cand
            buf["daytype"] = dt
            buf["updating"] = True
            return buf
    if fresh:
        fresh["stale"] = True
        fresh["daytype"] = dt
        fresh["updating"] = True
        return fresh
    return {"stale": True, "daytype": dt, "updating": True,
            "directions": [], "service_date": ymd}


def _run_update(force):
    try:
        env = dict(os.environ)
        env["BUS_OUT"] = os.path.join(APPDIR, "bus.json")
        if force:
            env["BUS_FORCE"] = "1"
        r = subprocess.run(["python", BUS_UPDATER], cwd=APPDIR, env=env,
                           capture_output=True, text=True, timeout=600)
        _log(r.stdout + r.stderr)
        with _upd_lock:
            _upd["ok"] = (r.returncode == 0)
            _upd["reason"] = "" if r.returncode == 0 else "builder failed"
    except Exception as e:
        _log("background update error: " + repr(e))
        with _upd_lock:
            _upd["ok"] = False
            _upd["reason"] = repr(e)
    finally:
        with _upd_lock:
            _upd["running"] = False


def start_update(force=False):
    with _upd_lock:
        if _upd["running"]:
            return False
        _upd["running"] = True
        _upd["started"] = time.time()
        _upd["ok"] = None
        _upd["reason"] = ""
    threading.Thread(target=_run_update, args=(force,), daemon=True).start()
    return True


def update_status():
    with _upd_lock:
        return {"running": _upd["running"], "ok": _upd["ok"],
                "reason": _upd["reason"],
                "elapsed": round(time.time() - _upd["started"], 1)
                if _upd["started"] else 0}


def _log(line):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(LOGFILE, "a", encoding="utf-8") as f:
            f.write(str(line).rstrip() + "\n")
    except Exception:
        pass


# v12: a phone drops sockets all the time. The screen sleeps, the browser
# backgrounds the tab, a fetch is aborted mid-flight when the page repaints,
# the Wi-Fi hands over to mobile data. The socket then breaks while a reply is
# being written and Python's default handler prints a whole traceback into the
# terminal, which looks like a crash and is not one. Every error of that family
# is swallowed here, and anything that is a real fault goes to the log file
# instead of the screen.
_CONN_ERRS = (ConnectionError, TimeoutError)


class Handler(http.server.BaseHTTPRequestHandler):
    # Keep all request logging in the file; never write to the screen.
    def log_message(self, fmt, *args):
        _log("%s %s" % (self.log_date_time_string(), fmt % args))

    # The client going away is not an error worth a traceback.
    def handle_one_request(self):
        try:
            http.server.BaseHTTPRequestHandler.handle_one_request(self)
        except _CONN_ERRS:
            self.close_connection = True

    def _send_body(self, body, code, ctype):
        try:
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except _CONN_ERRS:
            self.close_connection = True

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _json(self, payload, code=200):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self._send_body(body, code, "application/json; charset=utf-8")

    def do_GET(self):
        route = urllib.parse.urlparse(self.path).path
        if route in ("/", "/index.html"):
            route = "/bus.html"
        if route == "/update-bus":
            return self._update_bus()
        if route == "/schedule":
            return self._json(schedule_payload())
        if route == "/update-status":
            return self._json(update_status())
        if route == "/bus-rt":
            return self._bus_rt()
        if route == "/bus-live":
            return self._bus_live()
        if route == "/api-keys":
            return self._json({"keys": read_keys()})
        if route == "/zet-status":
            return self._json(zet_status_payload())
        if route == "/pdf-sched":
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            routes = [x for x in (q.get("routes", [""])[0]).split(",") if x]
            force = q.get("force", ["0"])[0] == "1"
            try:
                return self._json(pdf_sched_payload(routes, force))
            except Exception as e:
                return self._json({"ok": False, "reason": repr(e)}, 500)
        if route == "/gemini-key":
            return self._json({"keys": read_gemini_keys()})
        if route == "/pdf-list":
            return self._json(pdf_list_payload())
        if route == "/pdf-delete":
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            return self._json(pdf_delete(q.get("route", [""])[0],
                                         q.get("all", ["0"])[0] == "1"))
        if route == "/key-status":
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            which = q.get("which", ["gemini"])[0]
            return self._json(key_status_payload(which))
        if route == "/version":
            return self._json({"version": APP_VERSION, "build": APP_BUILD})
        name = route.lstrip("/")
        if name in ALLOWED_FILES:
            return self._serve_file(name)
        self.send_error(404, "Not found")

    def do_POST(self):
        route = urllib.parse.urlparse(self.path).path
        if route == "/gemini-key":
            try:
                ln = int(self.headers.get("Content-Length") or 0)
                body = self.rfile.read(ln).decode("utf-8", "replace") if ln else ""
                keys = [x.strip() for x in body.splitlines() if x.strip()]
                write_gemini_keys(keys)
                self._json({"ok": True, "keys": keys})
            except Exception as e:
                self._json({"ok": False, "reason": repr(e)}, 500)
            return
        if route == "/api-keys":
            try:
                ln = int(self.headers.get("Content-Length") or 0)
                body = self.rfile.read(ln).decode("utf-8", "replace") if ln else ""
                keys = [x.strip() for x in body.splitlines() if x.strip()]
                write_keys(keys)
                self._json({"ok": True, "keys": keys})
            except Exception as e:
                _log("api-keys save error: " + repr(e))
                self._json({"ok": False, "reason": repr(e)}, 500)
            return
        self.send_error(404, "Not found")

    def _serve_file(self, name):
        path = os.path.join(APPDIR, name)
        if not os.path.isfile(path):
            return self.send_error(404, "Not found")
        with open(path, "rb") as f:
            body = f.read()
        ext = os.path.splitext(name)[1]
        self._send_body(body, 200,
                        CONTENT_TYPES.get(ext, "application/octet-stream"))

    def _update_bus(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if q.get("bg", ["0"])[0] == "1":
            started = start_update(q.get("force", ["0"])[0] == "1")
            return self._json({"ok": True, "started": started,
                               "running": True})
        try:
            env = dict(os.environ)
            env["BUS_OUT"] = os.path.join(APPDIR, "bus.json")
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if q.get("force", ["0"])[0] == "1":
                env["BUS_FORCE"] = "1"
            r = subprocess.run(["python", BUS_UPDATER], cwd=APPDIR, env=env,
                               capture_output=True, text=True, timeout=300)
            _log(r.stdout + r.stderr)
            self._json({"ok": r.returncode == 0})
        except Exception as e:
            _log("update-bus error: " + repr(e))
            self._json({"ok": False, "reason": repr(e)}, 500)

    def _bus_rt(self):
        trip = urllib.parse.parse_qs(
            urllib.parse.urlparse(self.path).query).get("trip", [""])[0]
        try:
            self._json(bus_rt_payload(trip) if trip
                       else {"ok": False, "reason": "no trip"})
        except Exception as e:
            self._json({"ok": False, "reason": repr(e)}, 500)

    def _bus_live(self):
        raw = urllib.parse.parse_qs(
            urllib.parse.urlparse(self.path).query).get("trips", [""])[0]
        trips = [t for t in raw.split(",") if t]
        try:
            payload = bus_live_payload(trips)
        except Exception as e:
            # The ZET live feed is flaky on mobile data. A failed lookup is a
            # normal answer, not a server error, so the page just shows no
            # live times instead of logging a 500 on every poll.
            _log("bus-live: " + repr(e))
            payload = {"ok": False, "reason": repr(e), "trips": {}}
        self._json(payload)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    # Nothing a broken connection does is ever printed. A genuine fault is
    # written to ~/.commute/commute.log, where it can be read afterwards
    # without the terminal turning into a wall of red.
    def handle_error(self, request, client_address):
        exc = sys.exc_info()[1]
        if isinstance(exc, _CONN_ERRS):
            return
        try:
            import traceback
            _log("handler error: " + traceback.format_exc())
        except Exception:
            pass


def _open_browser(port):
    url = "http://127.0.0.1:%d/bus.html" % port
    for cmd in (["termux-open-url", url],
                ["am", "start", "-a", "android.intent.action.VIEW", "-d", url]):
        try:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
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


def _watch_quit_key():
    """Press q in the terminal to stop the server, gently."""
    if not sys.stdin.isatty():
        return

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
                        if ch in ("q", "Q"):
                            print("\n  stopped, see you", flush=True)
                            termios.tcsetattr(fd, termios.TCSADRAIN, old)
                            os._exit(0)
            finally:
                try:
                    termios.tcsetattr(fd, termios.TCSADRAIN, old)
                except Exception:
                    pass
        except Exception:
            # no raw tty available: fall back to q + Enter
            try:
                for line in sys.stdin:
                    if line.strip().lower() == "q":
                        print("  stopped, see you", flush=True)
                        os._exit(0)
            except Exception:
                pass

    threading.Thread(target=worker, daemon=True).start()


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    # First load of the day: start the GTFS download at once, in the
    # background, so the app opens on the buffered schedule with no wait.
    try:
        start_update(False)
    except Exception as e:
        _log("could not start the boot update: " + repr(e))
    host = os.environ.get("COMMUTE_HOST", "0.0.0.0")
    httpd, port = None, None
    for p in range(START_PORT, START_PORT + PORT_TRIES):
        try:
            httpd = Server((host, p), Handler)
            port = p
            break
        except OSError:
            continue
    if httpd is None:
        _log("no free port found from %d" % START_PORT)
        print("  no free port found from %d" % START_PORT, flush=True)
        raise SystemExit(1)
    try:
        with open(PORTFILE, "w") as f:
            f.write(str(port))
    except Exception:
        pass
    _log("commute server on %s:%d serving %s" % (host, port, APPDIR))
    # Calm address block. Request logs stay in the file, off the screen.
    W = "\033[1;37m"; DIM = "\033[0;90m"; OK = "\033[1;32m"; OFF = "\033[0m"
    ip = _lan_ip()
    print("  %s\u25b8%s on this phone  %shttp://127.0.0.1:%d%s" % (OK, OFF, W, port, OFF), flush=True)
    if ip:
        print("  %s\u25b8%s on Wi-Fi       %shttp://%s:%d%s" % (OK, OFF, W, ip, port, OFF), flush=True)
    print("\n  %sq or Ctrl+C to stop%s" % (DIM, OFF), flush=True)
    _watch_quit_key()
    try:
        import shutil as _sh
        _cols = _sh.get_terminal_size((40, 20)).columns
    except Exception:
        _cols = 40
    print("%s\033[38;5;208m\u0950%s" % (" " * max(_cols - 2, 0), OFF), flush=True)
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
CMT_SERVER_PY
done_

step "installing updater"
cat > "$APPDIR/update_bus.py" << 'CMT_UPDATE_PY'
#!/usr/bin/env python3
"""
update_bus.py

Downloads the ZET (Zagreb) GTFS static schedule, extracts the scheduled
departures for your two commute directions, and writes bus.json into your
web server folder. The HTML viewer then reads bus.json.

Builds the WHOLE service day in one pass, so it only needs to run once per
day: bus.json carries every remaining departure until midnight and the app
windows it locally. The GTFS zip is cached with its ETag/Last-Modified, so a
re-run first asks the server "has it changed?" and reuses the local copy when
it has not. The live realtime feed is separate and always live.

Requirements: Python 3 standard library only.

Run:
  python update_bus.py
"""

import os
import io
import sys
import csv
import json
import zipfile
import hashlib
import datetime
import urllib.request
import urllib.error
from collections import defaultdict

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
GTFS_URLS = [
    "https://www.zet.hr/gtfs-scheduled/latest",
    "https://zet.hr/gtfs-scheduled/latest",
]

DEFAULT_OUT = os.path.expanduser("~/storage/downloads/webserver/bus.json")
OUT_PATH = os.environ.get("BUS_OUT", DEFAULT_OUT)
TRIPS_OUT = os.path.join(os.path.dirname(OUT_PATH), "trips_path.json")
CACHE_ZIP = os.environ.get(
    "GTFS_CACHE", os.path.join(os.path.dirname(OUT_PATH), "zet_gtfs.zip"))




# ---------------------------------------------------------------------------
# Commute geography.
#
# We classify each bus by whether, AT YOUR STOP, it is heading TOWARD Glavni
# kolodvor (you are going home) or AWAY from it (you are going to work), using
# the stop coordinates and a vector toward Glavni kolodvor. This is independent
# of the bus's final destination, so every line on the corridor is included.
# For example line 109 ends at Črnomerec, not Glavni kolodvor, but at Bolšićeva
# it is heading toward the city, so it counts as a "home" option.
#
# When one bus stops at more than one of your stops a minute apart (e.g. 241 at
# Bolšićeva then Oreškovićeva), it is shown ONCE, at the best stop for you,
# following STOP_PREFERENCE. Your exit and your home-entry are both Oreškovićeva,
# so that wins; the Abramovićeva–Hribarov prilaz–Bolšićeva corridor uses
# Bolšićeva.
# ---------------------------------------------------------------------------
# Your commute is A <-> {B1, B2}:
#   A  = Glavni kolodvor      (the single stop you board going to work)
#   B1 = Oreškovićeva         (work-side stop, also a home-bound boarding stop)
#   B2 = Abramovićeva         (work-side stop, also a home-bound boarding stop)
# To work  = a trip that reaches A *before* a B  -> show its time at A.
# To home  = a trip that reaches a B *before* A  -> show its time at that B.
A_NAME = "glavni kolodvor"
B_KEYS = ["oreškovi", "abramovi"]
COMMUTE_STOPS = B_KEYS                                 # pass-1 flags B trips
GK_NAME = A_NAME
GK_FALLBACK = (45.8046, 15.9776)                       # Glavni kolodvor lat,lon
GRACE = {"to-work": 10, "to-home": 5}                  # minutes of past grace

BRITANAC = {
    "id": "britanac", "label": "Britanac",
    "board_key": "britanski trg",      # you board here
    "dest_key": "pavlinovi",           # you get off here (Pavlinovićeva)
}


def log(msg):
    print("[update_bus] " + msg, flush=True)


META_PATH = CACHE_ZIP + ".meta.json"

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

def bus_json_fresh_for(ymd):
    """True when bus.json already holds the whole of today's schedule."""
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            j = json.load(f)
        return j.get("service_date") == ymd and j.get("whole_day") is True
    except Exception:
        return False

def get_gtfs(force=False):
    """Return (zip_bytes, changed). Asks the ZET server whether the zip
    changed (ETag / Last-Modified); on 304 or an identical hash it reuses
    the local copy instead of downloading the whole file again."""
    meta = _load_meta()
    cached = None
    if os.path.isfile(CACHE_ZIP):
        try:
            with open(CACHE_ZIP, "rb") as f:
                cached = f.read()
        except Exception:
            cached = None
    headers = {"User-Agent": "Mozilla/5.0 (Android; bus-updater)"}
    if cached is not None and not force:
        if meta.get("etag"):
            headers["If-None-Match"] = meta["etag"]
        if meta.get("last_modified"):
            headers["If-Modified-Since"] = meta["last_modified"]
    last_err = None
    for url in GTFS_URLS:
        try:
            log("checking " + url)
            req = urllib.request.Request(url, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    data = resp.read()
                    rh = resp.headers
            except urllib.error.HTTPError as he:
                if he.code == 304 and cached is not None:
                    log("  schedule unchanged on the server, using the local copy")
                    return cached, False
                raise
            if data[:2] != b"PK":
                log("  not a zip (starts with %r), trying next" % data[:8])
                continue
            sha = hashlib.sha256(data).hexdigest()
            changed = sha != meta.get("sha256")
            log("  got zip, %d bytes%s" % (
                len(data), "" if changed else " (identical to the local copy)"))
            try:
                with open(CACHE_ZIP, "wb") as f:
                    f.write(data)
                _save_meta({
                    "etag": rh.get("ETag") or "",
                    "last_modified": rh.get("Last-Modified") or "",
                    "sha256": sha,
                    "fetched": datetime.date.today().strftime("%Y%m%d"),
                })
            except Exception:
                pass
            return data, changed
        except Exception as e:
            last_err = e
            log("  failed: " + repr(e))
    if cached is not None:
        log("network unavailable, using the local GTFS copy")
        return cached, False
    raise RuntimeError("could not download GTFS zip: " + repr(last_err))


def read_csv_from_zip(zf, name):
    candidates = [name] + [n for n in zf.namelist() if n.endswith("/" + name)]
    for cand in candidates:
        if cand in zf.namelist():
            raw = zf.read(cand)
            text = raw.decode("utf-8-sig", errors="replace")
            return list(csv.DictReader(io.StringIO(text)))
    raise KeyError(name + " not found in GTFS zip")


def gtfs_time_to_minutes(t):
    parts = t.strip().split(":")
    if len(parts) < 2:
        return None
    try:
        return int(parts[0]) * 60 + int(parts[1])
    except ValueError:
        return None


def gtfs_time_to_seconds(t):
    # Seconds since service-day midnight. Can exceed 86400 for after-midnight
    # trips (e.g. "25:10:00"), which is valid GTFS.
    if not t:
        return None
    parts = t.strip().split(":")
    if len(parts) < 2:
        return None
    try:
        h, m = int(parts[0]), int(parts[1])
        s = int(parts[2]) if len(parts) > 2 else 0
        return h * 3600 + m * 60 + s
    except ValueError:
        return None


ARCH_DIR = os.path.join(os.path.dirname(OUT_PATH), "daycache")


def _easter(y):
    a = y % 19; b = y // 100; c = y % 100
    d = b // 4; e = b % 4; f = (b + 8) // 25; g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i = c // 4; k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    return datetime.date(y, month, day)


def croatian_holidays(y):
    """Public holidays in Croatia, when ZET runs its Sunday style service."""
    e = _easter(y)
    days = {
        datetime.date(y, 1, 1), datetime.date(y, 1, 6),
        e, e + datetime.timedelta(days=1),
        datetime.date(y, 5, 1), e + datetime.timedelta(days=60),
        datetime.date(y, 5, 30), datetime.date(y, 6, 22),
        datetime.date(y, 8, 5), datetime.date(y, 8, 15),
        datetime.date(y, 11, 1), datetime.date(y, 11, 18),
        datetime.date(y, 12, 25), datetime.date(y, 12, 26),
    }
    return {d.strftime("%Y%m%d") for d in days}


def daytype_for(d):
    """weekday | sat | sun | holiday. ZET runs one schedule Monday to Friday,
    a special one on Saturday, another on Sunday, another on holidays."""
    if d.strftime("%Y%m%d") in croatian_holidays(d.year):
        return "holiday"
    wd = d.weekday()
    if wd == 5:
        return "sat"
    if wd == 6:
        return "sun"
    return "weekday"


def archive_path(dt):
    return os.path.join(ARCH_DIR, "bus.%s.json" % dt)


def trips_archive_path(dt):
    return os.path.join(ARCH_DIR, "trips.%s.json" % dt)


def write_json(path, payload, indent=None):
    d = os.path.dirname(path)
    if d and not os.path.isdir(d):
        os.makedirs(d, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=indent)
    os.replace(tmp, path)


def archive_age_days(dt, today):
    """How old the stored copy of this day type is, in days."""
    try:
        with open(archive_path(dt), encoding="utf-8") as f:
            j = json.load(f)
        d = datetime.datetime.strptime(j["service_date"], "%Y%m%d").date()
        return abs((today - d).days)
    except Exception:
        return 10 ** 6


def next_weekday_date(today, wd):
    """The next date with weekday wd, today excluded."""
    ahead = (wd - today.weekday()) % 7
    return today + datetime.timedelta(days=ahead or 7)


def todays_service_ids(zf, today):
    weekday = ["monday", "tuesday", "wednesday", "thursday",
               "friday", "saturday", "sunday"][today.weekday()]
    ymd = today.strftime("%Y%m%d")
    active = set()
    try:
        for row in read_csv_from_zip(zf, "calendar.txt"):
            if row.get(weekday, "0") == "1":
                if row.get("start_date", "0") <= ymd <= row.get("end_date", "9"):
                    active.add(row["service_id"])
    except KeyError:
        pass
    try:
        for row in read_csv_from_zip(zf, "calendar_dates.txt"):
            if row.get("date") == ymd:
                sid = row.get("service_id")
                if row.get("exception_type") == "1":
                    active.add(sid)
                elif row.get("exception_type") == "2":
                    active.discard(sid)
    except KeyError:
        pass
    return active


def build_for(zf, target, now, from_midnight=False):
    """Build one whole service day out of an already open GTFS zip. For a
    future day (the weekend buffer) the window starts at midnight, so the
    stored copy carries every departure of that day type."""
    today = target
    ymd = today.strftime("%Y%m%d")
    now_mins = 0 if from_midnight else now.hour * 60 + now.minute

    routes = read_csv_from_zip(zf, "routes.txt")
    stops = read_csv_from_zip(zf, "stops.txt")
    trips = read_csv_from_zip(zf, "trips.txt")

    route_short = {}
    for r in routes:
        route_short[r["route_id"]] = (r.get("route_short_name")
                                      or r.get("route_long_name") or "?").strip().strip('"')

    stop_name = {}
    stop_ll = {}
    for s in stops:
        sid = s["stop_id"]
        stop_name[sid] = (s.get("stop_name") or "").strip()
        try:
            stop_ll[sid] = (float(s.get("stop_lat")), float(s.get("stop_lon")))
        except (TypeError, ValueError):
            pass

    service_ids = todays_service_ids(zf, today)
    log("active services today: %d" % len(service_ids))

    # trip_id -> (route_short, headsign) for trips running today
    trip_info = {}
    for t in trips:
        sid = t.get("service_id")
        if service_ids and sid not in service_ids:
            continue
        trip_info[t["trip_id"]] = (
            route_short.get(t.get("route_id"), "?"),
            (t.get("trip_headsign") or "").strip(),
            (t.get("direction_id") or "").strip(),
        )
    log("trips running today: %d" % len(trip_info))

    # Precompute stop id sets.
    commute_ids = {}                       # stop_id -> display name (your 3 stops)
    for sid, nm in stop_name.items():
        low = nm.lower()
        for key in COMMUTE_STOPS:
            if key in low:
                commute_ids[sid] = nm
                break
    gk_ids = {sid for sid, nm in stop_name.items() if GK_NAME in nm.lower()}
    gk_lls = [stop_ll[s] for s in gk_ids if s in stop_ll]
    if gk_lls:
        gk_ref = (sum(x[0] for x in gk_lls) / len(gk_lls),
                  sum(x[1] for x in gk_lls) / len(gk_lls))
    else:
        gk_ref = GK_FALLBACK
    log("Glavni kolodvor reference: %.5f, %.5f" % gk_ref)

    BRITANAC["_board_ids"] = {sid for sid, nm in stop_name.items()
                              if BRITANAC["board_key"] in nm.lower()}
    britanac_trips = set()

    gk_221_ids = gk_ids
    featured_221 = []

    # Pass 1: stream stop_times.txt. Gather commute CANDIDATES (any bus at one
    # of your 3 stops), the Britanac departures, and the featured 221s. We do
    # not decide home vs work yet; that needs each trip's full path (pass 2).
    candidates = []
    candidate_trips = set()

    st_name = "stop_times.txt"
    cand = [st_name] + [n for n in zf.namelist() if n.endswith("/" + st_name)]
    st_path = next(c for c in cand if c in zf.namelist())
    with zf.open(st_path) as raw:
        text = io.TextIOWrapper(raw, encoding="utf-8-sig", errors="replace")
        rdr = csv.DictReader(text)
        for row in rdr:
            sid = row.get("stop_id")
            tid = row.get("trip_id")
            ti = trip_info.get(tid)
            if ti is None:
                continue
            rshort, headsign, dir_id = ti

            # featured 221 toward Travno from Glavni kolodvor
            if rshort == "221" and dir_id == "0" and sid in gk_221_ids:
                dep221 = row.get("departure_time") or row.get("arrival_time")
                m221 = gtfs_time_to_minutes(dep221)
                if m221 is not None:      # whole service day, app windows live
                    featured_221.append({
                        "route": "221", "time": dep221[:5],
                        "mins_from_now": m221 - now_mins,
                    })

            # Britanac: flag upcoming trips that board at Britanski trg; the
            # path (pass 2) decides if they head toward Pavlinovićeva.
            if sid in BRITANAC["_board_ids"]:
                depb = row.get("departure_time") or row.get("arrival_time")
                mb = gtfs_time_to_minutes(depb)
                if mb is not None and mb >= now_mins - 2:
                    britanac_trips.add(tid)

            # commute candidate (classified later)
            nm_c = commute_ids.get(sid)
            if nm_c is not None:
                depc = row.get("departure_time") or row.get("arrival_time")
                mc = gtfs_time_to_minutes(depc)
                if mc is None:
                    continue
                rel = mc - now_mins
                if rel < -15:               # bound the past (max grace is 10)
                    continue
                try:
                    seq = int(row.get("stop_sequence") or 0)
                except ValueError:
                    seq = 0
                candidates.append({
                    "trip": tid, "route": rshort, "stop_id": sid,
                    "name": nm_c, "time": depc[:5], "mins": rel, "seq": seq,
                })
                candidate_trips.add(tid)

    # whole day, one entry per clock time (ZET lists the same departure under
    # several service ids, which showed as duplicates in the app)
    seen_f = set()
    featured_221 = [f for f in sorted(featured_221, key=lambda x: x["time"])
                    if not (f["time"] in seen_f or seen_f.add(f["time"]))]
    log("featured 221 from Gl.kolodvor: %d" % len(featured_221))
    log("commute candidate trips: %d" % len(candidate_trips))

    # Pass 2: collect the FULL ordered path for every candidate trip, so we can
    # both classify direction and draw the live map. (Pass 1 only saw your 3
    # stops; here we read each candidate trip's whole route.)
    paths = {}
    path_trips = candidate_trips | britanac_trips
    if path_trips:
        with zf.open(st_path) as raw:
            text = io.TextIOWrapper(raw, encoding="utf-8-sig", errors="replace")
            for row in csv.DictReader(text):
                tid = row.get("trip_id")
                if tid not in path_trips:
                    continue
                sid = row.get("stop_id")
                ll = stop_ll.get(sid)
                if not ll:
                    continue
                secs = gtfs_time_to_seconds(
                    row.get("departure_time") or row.get("arrival_time"))
                if secs is None:
                    continue
                try:
                    seq = int(row.get("stop_sequence") or 0)
                except ValueError:
                    seq = 0
                paths.setdefault(tid, []).append({
                    "seq": seq, "name": stop_name.get(sid, ""),
                    "lat": round(ll[0], 6), "lng": round(ll[1], 6),
                    "t": secs, "stop_id": sid,
                })
    for tid in paths:
        paths[tid].sort(key=lambda x: x["seq"])

    def hhmm(secs):
        s = int(secs) % 86400
        return "%02d:%02d" % (s // 3600, (s % 3600) // 60)

    def name_has(name, key):
        return key in name.lower()

    # Decide direction per trip from its own stop order:
    #   A before B  -> to work, board at A (Glavni kolodvor), get off at that B.
    #   B before A  -> to home, board at that B, ride to A (Glavni kolodvor).
    to_work_deps, to_home_deps = [], []
    work_lines, home_lines = set(), set()
    for tid, path in paths.items():
        rshort = trip_info.get(tid, ("?", "", ""))[0]
        a = next((p for p in path if name_has(p["name"], A_NAME)), None)
        if a is None:
            continue                                   # must connect to Glavni kolodvor
        bs = [p for p in path if any(name_has(p["name"], k) for k in B_KEYS)]
        if not bs:
            continue
        b_after = sorted((b for b in bs if b["seq"] > a["seq"]), key=lambda x: x["seq"])
        b_before = sorted((b for b in bs if b["seq"] < a["seq"]), key=lambda x: x["seq"])
        if b_after:                                    # A -> B : going to work
            b = b_after[0]
            mins = int(a["t"]) // 60 - now_mins
            if mins >= -GRACE["to-work"]:
                to_work_deps.append({
                    "route": rshort, "headsign": "",
                    "from": a["name"], "to": b["name"], "exit": b["name"],
                    "time": hhmm(a["t"]), "arrive": hhmm(b["t"]),
                    "mins_from_now": mins, "trip": tid,
                    "stop_id": a["stop_id"], "dest_stop_id": b["stop_id"],
                })
                work_lines.add(rshort)
        if b_before:                                   # B -> A : going home
            b = b_before[0]
            mins = int(b["t"]) // 60 - now_mins
            if mins >= -GRACE["to-home"]:
                to_home_deps.append({
                    "route": rshort, "headsign": "",
                    "from": b["name"], "to": a["name"], "exit": a["name"],
                    "time": hhmm(b["t"]), "arrive": hhmm(a["t"]),
                    "mins_from_now": mins, "trip": tid,
                    "stop_id": b["stop_id"], "dest_stop_id": a["stop_id"],
                })
                home_lines.add(rshort)

    def dedupe_deps(deps):
        """One row per (route, time, from, exit): ZET repeats the same
        departure under several service ids."""
        seen = set()
        out = []
        for dd in deps:
            k = (dd.get("route"), dd.get("time"), dd.get("from"), dd.get("exit"))
            if k in seen:
                continue
            seen.add(k)
            out.append(dd)
        return out

    # whole remaining service day, deduplicated, the app windows it locally
    to_work_deps = dedupe_deps(sorted(to_work_deps, key=lambda x: x["mins_from_now"]))
    to_home_deps = dedupe_deps(sorted(to_home_deps, key=lambda x: x["mins_from_now"]))

    # Britanac: Britanski trg -> Pavlinovićeva, schedule only (no live, no map).
    brit = []
    for tid in britanac_trips:
        path = paths.get(tid)
        if not path:
            continue
        rshort = trip_info.get(tid, ("?", "", ""))[0]
        board = next((p for p in path
                      if BRITANAC["board_key"] in p["name"].lower()), None)
        dest = next((p for p in path
                     if BRITANAC["dest_key"] in p["name"].lower()), None)
        if not board or not dest or board["seq"] >= dest["seq"]:
            continue                                   # must head to Pavlinovićeva
        mins = int(board["t"]) // 60 - now_mins
        if mins < -2:
            continue
        brit.append({                                  # no trip/stop_id -> no map, no live
            "route": rshort, "headsign": "",
            "from": board["name"], "to": dest["name"], "exit": dest["name"],
            "time": hhmm(board["t"]), "arrive": hhmm(dest["t"]),
            "mins_from_now": mins,
        })
    brit = dedupe_deps(sorted(brit, key=lambda x: x["mins_from_now"]))
    log("britanac: %d deps toward Pavlinovićeva" % len(brit))

    log("to-work: %d deps  lines: %s" % (len(to_work_deps),
        ",".join(sorted(work_lines))))
    log("to-home: %d deps  lines: %s" % (len(to_home_deps),
        ",".join(sorted(home_lines))))

    out_dirs = [
        {"id": "to-work", "label": "Nova TV", "stops": COMMUTE_STOPS,
         "departures": to_work_deps, "featured": featured_221},
        {"id": "to-home", "label": "Gl.kolodvor", "stops": COMMUTE_STOPS,
         "departures": to_home_deps},
        {"id": "britanac", "label": "Britanac", "stops": ["pavlinovićeva"],
         "departures": brit},
    ]

    feed_version = ""
    try:
        fi = read_csv_from_zip(zf, "feed_info.txt")
        if fi:
            feed_version = fi[0].get("feed_version", "") or ""
    except Exception:
        feed_version = ""

    payload = {
        "updated": now.astimezone().isoformat(timespec="minutes"),
        "generated": int(now.timestamp()),
        "service_date": ymd,
        "daytype": daytype_for(today),
        "whole_day": True,
        "from_midnight": bool(from_midnight),
        "feed_version": feed_version,
        "source": "ZET GTFS scheduled",
        "directions": out_dirs,
    }

    # trips_path.json: keep the full path only for trips actually on screen.
    kept = {d["trip"] for d in to_work_deps + to_home_deps if d.get("trip")}
    trips_out = {tid: paths[tid] for tid in kept if tid in paths}
    log("paths kept for %d on-screen trips" % len(trips_out))

    trips_payload = {
        "updated": now.astimezone().isoformat(timespec="minutes"),
        "service_date": ymd,
        "daytype": daytype_for(today),
        "trips": trips_out,
    }
    return payload, trips_payload


def prefetch_weekend(zf, now, today):
    """Keep next Saturday and next Sunday on disk so the weekend opens with a
    full schedule already on screen while the fresh one downloads. Holidays
    reuse the Sunday copy until a real holiday build replaces it."""
    for wd, dt in ((5, "sat"), (6, "sun")):
        if archive_age_days(dt, today) <= 7:
            continue
        target = next_weekday_date(today, wd)
        try:
            pay, trp = build_for(zf, target, now, from_midnight=True)
            write_json(archive_path(dt), pay)
            write_json(trips_archive_path(dt), trp)
            log("buffered %s from %s" % (dt, target.strftime("%Y-%m-%d")))
        except Exception as e:
            log("could not buffer %s: %s" % (dt, repr(e)))


def main():
    now = datetime.datetime.now()
    today = now.date()
    force = os.environ.get("BUS_FORCE") == "1"
    ymd = today.strftime("%Y%m%d")
    dt_today = daytype_for(today)

    if not force and bus_json_fresh_for(ymd):
        log("bus.json already holds the whole of today, nothing to fetch")
        return

    data, _changed = get_gtfs(force)
    zf = zipfile.ZipFile(io.BytesIO(data))
    log("zip contains: " + ", ".join(zf.namelist()[:20]))
    log("day type today: " + dt_today)

    payload, trips_payload = build_for(zf, today, now)

    out_dir = os.path.dirname(OUT_PATH)
    if out_dir and not os.path.isdir(out_dir):
        log("output folder missing: " + out_dir)
        sys.exit(1)

    write_json(OUT_PATH, payload, indent=2)
    log("wrote " + OUT_PATH)
    try:
        write_json(TRIPS_OUT, trips_payload)
        log("wrote " + TRIPS_OUT)
    except Exception as e:
        log("could not write trips_path.json: " + repr(e))

    # today becomes the buffer for the next day of the same type
    try:
        full, full_trips = build_for(zf, today, now, from_midnight=True)
        write_json(archive_path(dt_today), full)
        write_json(trips_archive_path(dt_today), full_trips)
        log("stored the %s buffer" % dt_today)
    except Exception as e:
        log("could not store the %s buffer: %s" % (dt_today, repr(e)))

    if os.environ.get("BUS_NO_PREFETCH") != "1":
        prefetch_weekend(zf, now, today)


if __name__ == "__main__":
    main()
CMT_UPDATE_PY
done_

step "installing app"
cat > "$APPDIR/bus.html" << 'CMT_BUS_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Commute</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='7' fill='%230d1117'/%3E%3Cg fill='%23d4a017'%3E%3Crect x='7' y='6' width='18' height='15' rx='2.5'/%3E%3Crect x='9' y='9' width='14' height='5' rx='1' fill='%230d1117'/%3E%3Ccircle cx='11' cy='23' r='2.3'/%3E%3Ccircle cx='21' cy='23' r='2.3'/%3E%3C/g%3E%3C/svg%3E">
<style>
  :root {
    --bg:#0d1117; --card:#161b22; --border:#30363d;
    --text:#e6edf3; --muted:#8b949e; --cyan:#d4a017; --accent:#a371f7;
    --soon:#d4a017; --later:#8b949e;
  }
  /* v9: nine high-contrast colour schemes, chosen in the gear */
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--text);
    font-family:-apple-system,system-ui,Roboto,sans-serif; padding:60px 16px 92px; }
  .tophud { position:fixed; top:0; left:0; right:0; z-index:950; background:var(--bg);
    display:flex; align-items:center; justify-content:center; padding:4px 10px 6px;
    border-bottom:1px solid var(--border); }
  .fs { position:absolute; left:8px; top:9px; background:none; border:none;
    color:var(--muted); font-size:1.25rem; cursor:pointer; padding:4px 6px; line-height:1; }
  .gear { position:absolute; right:8px; top:8px; background:none; border:none;
    color:var(--muted); font-size:1.4rem; cursor:pointer; padding:4px 6px; line-height:1; }
  .clock { text-align:center; font-size:2.4rem; font-weight:800; color:var(--text);
    font-variant-numeric:tabular-nums; letter-spacing:1px; margin:0; line-height:1.05; }
  .fab { position:fixed; left:50%; transform:translateX(-50%); bottom:18px;
    width:56px; height:56px; border-radius:50%; background:var(--card);
    color:var(--cyan); border:1px solid var(--cyan); font-size:1.5rem;
    cursor:pointer; box-shadow:0 4px 16px rgba(0,0,0,.55); z-index:900; }
  .fab:disabled { opacity:.6; }
  .pills { display:flex; gap:8px; flex-wrap:wrap; margin-bottom:14px; }
  .pill { border:1px solid var(--border); background:var(--card); color:var(--muted);
    padding:8px 16px; border-radius:20px; font-size:.92rem; font-weight:600; cursor:pointer; }
  .pill.active { border-color:var(--cyan); color:var(--cyan); background:rgba(212,160,23,.10); }
  .dep { display:flex; align-items:center; gap:12px; padding:12px 2px;
    border-bottom:1px solid var(--border); }
  .route { background:var(--card); border:2px solid var(--border); color:var(--text);
    font-weight:700; font-size:.95rem; border-radius:14px; padding:3px 12px;
    min-width:54px; text-align:center; }
  /* route priority, dark-mode pill style matching the top pills */
  .route.r241 { border-color:#d4a017; color:#d4a017;
    background:rgba(212,160,23,.10); }                    /* 241 most important, gold */
  .route.r268 { border-color:#1f9bd1; color:#1f9bd1;
    background:rgba(31,155,209,.12); }                    /* 268 second, sea blue */
  .route.dim  { border-color:var(--border); color:var(--muted);
    background:transparent; }
  .dep.dimrow { opacity:.7; }
  .dep.dimrow .time, .dep.dimrow .exit { color:#6e7681; }
  .pills { display:flex; align-items:center; gap:7px; }
  .timepill { border:2px solid rgba(63,185,80,.45); color:#3fb950;
    background:rgba(63,185,80,.10); font-weight:700; font-size:.95rem;
    border-radius:14px; padding:3px 12px; min-width:54px; text-align:center; }
  /* v2 display: in the departure list the route sits on top and the live
     arrival at your stop is the headline right under it. Scoped to .dep so the
     top direction bar (also class "pills") keeps its horizontal layout. */
  .dep .pills { flex-direction:column; align-items:flex-start; gap:6px; }
  .bigt { font-size:1.3rem; font-weight:800; color:#8b949e; line-height:1.05;
    font-variant-numeric:tabular-nums; letter-spacing:.3px; padding-left:2px; }
  .bigt .le-t { color:#e3b341; }        /* live arrival time at your stop */
  .bigt .le-d { color:#f85149; }        /* running late  (+n) */
  .bigt .le-ok { color:#8b949e; }       /* dead on time (±0) */
  .bigt .wifi { vertical-align:0; margin-left:6px; }
  .schedstop { color:#8b949e; font-weight:600; font-size:.9rem;
    font-variant-numeric:tabular-nums; }              /* scheduled stop time */
  .arrgray { color:#5a626c; font-weight:600; font-size:.85rem; margin-left:6px;
    font-variant-numeric:tabular-nums; }              /* arrival at destination */
  .depinfo { display:flex; flex-direction:column; gap:1px; }
  .time { font-size:1.05rem; font-weight:700; color:#3fb950; }   /* schedule = truth */
  .exit { font-size:.78rem; color:var(--muted); }
  .journey { font-size:.95rem; font-weight:600; color:var(--text); }
  .journey .jto { color:var(--muted); font-weight:500; }
  .times { display:block; margin-top:2px; }
  .sched { color:#3fb950; font-weight:700; font-size:.9rem; }   /* board → arrive */
  .liveest { color:#6e7681; font-weight:600; font-size:.8rem; margin-left:6px; }
  .le-t { color:#e3b341; }                       /* live estimate, experimental */
  .le-d { color:#f85149; }                        /* live delay estimate */
  .le-ok { color:#8b949e; }
  .wifi { vertical-align:-1px; margin-left:5px; }
  .mins { margin-left:auto; font-size:1.2rem; font-weight:700; text-align:right; }
  .mins .u { font-size:.7rem; font-weight:400; color:var(--muted); }
  .mins.soon { color:var(--soon); }
  .mins.later { color:var(--text); }   /* >15 min: white, calm */
  .mins.over { color:#f85149; }   /* past scheduled, within grace window */
  .liveT { font-weight:600; font-size:.82rem; margin-left:7px; }
  .liveT.late { color:#f85149; }
  .liveT.early { color:#3fb950; }
  .liveT.ontime { color:#3fb950; }
  .dly { display:block; font-size:.66rem; font-weight:700; margin-top:1px; }
  .dly.late { color:#f85149; }
  .dly.ontime { color:#3fb950; }
  .dly.sched { color:#5a626c; font-weight:600; }
  /* filter pills under the direction row */
  .filters { display:flex; gap:8px; flex-wrap:wrap; margin:-4px 0 14px; }
  .pill.filt { padding:5px 12px; font-size:.82rem; }
  .pill.filt.on { border-color:var(--cyan); color:var(--cyan);
    background:rgba(212,160,23,.10); }
  .pill.filt.on.f268 { border-color:#1f9bd1; color:#1f9bd1;
    background:rgba(31,155,209,.12); }
  .pill.filt.muted { color:#5a626c; border-color:var(--border);
    background:transparent; text-decoration:line-through; }
  .empty { color:var(--muted); font-size:.9rem; padding:10px 0; }
  /* 221 gateway: subtle, frameless status line at the very top, to-work only.
     Ride 221 two stops to the hub where every Glavni-kolodvor bus passes,
     then take the first one. */
  .gw221 { display:flex; align-items:baseline; gap:8px; margin:0 2px 12px;
    font-size:.82rem; color:var(--muted); font-weight:600; letter-spacing:.2px; }
  .gw221 .g-lbl { color:var(--accent); font-weight:800; font-size:.8rem; }
  .gw221 .g-t { color:var(--soon); font-weight:700; font-variant-numeric:tabular-nums; }
  .gw221 .g-sep { opacity:.5; padding:0 2px; }
  .gw221 .g-hint { opacity:.7; font-weight:500; }
  .gw221 .g-none { opacity:.7; font-weight:500; }
  /* v7: GTFS / PDF source tabs */
  /* v12: no source buttons and no source row. The right-hand end of the
     direction bar carries everything: the recognised place, a PDF mark that
     only appears when GTFS has failed, and the triangle that unfolds the line
     filters. Nothing of it costs a row of its own. */
  #pills { display:flex; align-items:center; gap:7px; flex-wrap:nowrap;
    margin-bottom:12px; }
  .pillmeta { margin-left:auto; display:flex; align-items:center; gap:8px;
    flex:none; }
  .srcbadge { display:none; font-size:.58rem; font-weight:800; letter-spacing:.10em;
    padding:2px 7px; border-radius:8px; color:#e3b341;
    border:1px solid rgba(227,179,65,.55); background:rgba(227,179,65,.08); }
  .filttog { background:none; border:none; padding:2px 2px 2px 0; cursor:pointer;
    color:var(--muted); font-size:.80rem; line-height:1; }
  .filttog.open, .filttog.act { color:var(--cyan); }
  .pdfnote { color:var(--muted); font-size:.74rem; margin:-6px 0 12px 2px; line-height:1.4; }
  .pdfnote .warn { color:#d4a017; }
  .corrsec { margin-bottom:12px; }
  .corrsec h4 { margin:2px 0 7px; font-size:.86rem; color:var(--text); font-weight:700; }
  .corrline { display:flex; align-items:center; gap:10px; padding:7px 8px; border-radius:10px;
    border:1px solid var(--border); background:var(--card); margin-bottom:6px; cursor:pointer; }
  .corrline .cbx { width:20px; height:20px; border-radius:6px; border:2px solid var(--muted);
    display:flex; align-items:center; justify-content:center; font-size:13px; font-weight:800;
    color:var(--bg); flex:0 0 auto; }
  .corrline.on .cbx { background:var(--cyan); border-color:var(--cyan); }
  .corrline.off { opacity:.55; }
  .corrline .cln { font-weight:700; min-width:38px; }
  .corrline .cds { color:var(--muted); font-size:.82rem; }
  .cwheel-btn { background:var(--card); color:var(--text); border:1px solid var(--border);
      width:34px; height:34px; border-radius:50%; font-weight:800; font-size:.9rem; cursor:pointer;
      margin-right:8px; }
  #colormodal { position:fixed; inset:0; z-index:1200; display:none; }
  #colormodal.show { display:flex; flex-direction:column; }
  .cw-head { display:flex; align-items:center; justify-content:space-between;
    padding:14px 16px; }
  .cw-title { color:#fff; font-weight:800; letter-spacing:.5px; text-shadow:0 1px 3px #000; }
  .cw-close { background:var(--cyan); color:var(--bg); border:none; border-radius:11px;
    padding:7px 16px; font-weight:800; cursor:pointer; }
  .cw-stage { flex:1; display:flex; align-items:center; justify-content:center; }
  .cw-wheel { position:relative; width:300px; height:300px; }
  .cw-ring { position:absolute; inset:0; }
  .cw-sw { position:absolute; width:34px; height:34px; border-radius:50%;
    border:2px solid rgba(255,255,255,.55); cursor:pointer; padding:0;
    box-shadow:0 2px 6px rgba(0,0,0,.5); }
  .cw-sw:active { transform:scale(1.25); }
  .cw-center { position:absolute; left:50%; top:50%; transform:translate(-50%,-50%);
    width:150px; height:150px; border-radius:50%; background:rgba(13,17,23,.92);
    border:1px solid var(--border); display:flex; flex-direction:column;
    align-items:center; justify-content:center; gap:8px; padding:10px; }
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
  .cw-hex { color:#fff; font-size:.78rem; font-variant-numeric:tabular-nums; text-shadow:0 1px 2px #000; }
  .cw-tools { padding:12px 18px 22px; background:linear-gradient(to top,rgba(0,0,0,.55),transparent); }
  .cw-llbl { color:#fff; font-size:.72rem; text-transform:uppercase; letter-spacing:1px;
    text-shadow:0 1px 2px #000; }
  .cw-range { width:100%; margin:6px 0 10px; accent-color:var(--cyan); }
  .cw-neutrals { display:flex; gap:6px; justify-content:center; margin-bottom:10px; }
  .cw-nsw { width:30px; height:30px; border-radius:7px; border:2px solid rgba(255,255,255,.4);
    cursor:pointer; padding:0; }
  .cw-hint { color:#e6edf3; font-size:.74rem; text-align:center; opacity:.85;
    text-shadow:0 1px 2px #000; line-height:1.35; }
  .themegrid { display:grid; grid-template-columns:repeat(3,1fr); gap:8px; margin-top:4px; }
  .themecard { border:2px solid var(--border); border-radius:12px; overflow:hidden;
    cursor:pointer; background:var(--card); padding:0; }
  .themecard.on { border-color:var(--cyan); }
  .themeprev { padding:8px; font-size:9px; line-height:1.25; }
  .themeprev .tp-clock { font-weight:800; font-size:14px; letter-spacing:.5px; }
  .themeprev .tp-pill { display:inline-block; border-radius:8px; padding:1px 7px;
    font-weight:700; font-size:9px; margin:4px 0 3px; }
  .themeprev .tp-row { display:flex; justify-content:space-between; }
  .themeprev .tp-t { font-weight:700; }
  .themename { text-align:center; font-size:.72rem; padding:5px 2px; color:var(--muted);
    border-top:1px solid var(--border); }
  .themecard.on .themename { color:var(--cyan); }
  /* v7: commute pills, one per route option, tap to unfold vertical schedule */
  .cpill { border:1px solid var(--border); background:var(--card); border-radius:12px;
    padding:10px 13px; margin-bottom:10px; font-size:.95rem; font-weight:600;
    color:var(--muted); cursor:pointer; }
  .cpill .cph { display:flex; align-items:center; gap:9px; }
  .cpill .cpr { background:#8b949e; color:#0d1117; font-weight:700; border-radius:12px;
    padding:2px 10px; font-size:.9rem; }
  .cpill.c241 { border-color:rgba(212,160,23,.45); color:#d4a017; background:rgba(212,160,23,.08); }
  .cpill.c241 .cpr { background:#d4a017; }
  .cpill.c268 { border-color:rgba(31,155,209,.5); color:#39a8db; background:rgba(31,155,209,.08); }
  .cpill.c268 .cpr { background:#1f9bd1; color:#eaf6fc; }
  .cpill.cdef { border-color:rgba(57,208,216,.35); color:#7ee1e6; background:rgba(57,208,216,.06); }
  .cpill.cdef .cpr { background:#39d0d8; }
  .cpill .cpstop { font-size:.78rem; font-weight:600; opacity:.8; margin-right:2px; }
  .cpill .cpx { margin-left:auto; color:#3a4048; font-size:1.05rem; }
  .cpill .cpnone { font-weight:500; opacity:.75; }
  .cpsched { display:none; margin-top:9px; border-top:1px dashed var(--border); padding-top:7px; }
  .cpill.open .cpsched { display:block; }
  .cprow { display:flex; align-items:baseline; gap:10px; padding:4px 2px;
    font-variant-numeric:tabular-nums; font-weight:600; }
  .cprow .t { color:#3fb950; min-width:52px; }
  .cprow .a { color:var(--muted); font-weight:500; font-size:.86rem; }
  .cprow .m { margin-left:auto; color:var(--muted); font-size:.85rem; font-weight:500; }
  .cprow .m.soon { color:#3fb950; }
  /* v7: PDF tab, printed-timetable style vertical cards */
  .pdfcard { background:var(--card); border:1px solid var(--border); border-radius:14px;
    padding:13px 15px; margin-bottom:14px; }
  .pdfhead { display:flex; align-items:center; gap:10px; margin-bottom:4px; }
  .pdfhead .cpr { background:#8b949e; color:#0d1117; font-weight:700; border-radius:12px;
    padding:2px 10px; font-size:.9rem; }
  .pdfcard.c241 .cpr { background:#d4a017; } .pdfcard.c268 .cpr { background:#1f9bd1; color:#eaf6fc; }
  .pdfhead .jto { color:var(--muted); font-size:.88rem; font-weight:600; }
  .pdflink { display:inline-block; margin:2px 0 8px 0; color:#39d0d8; font-size:.8rem;
    text-decoration:none; border-bottom:1px dotted rgba(57,208,216,.5); }
  .pdfrows { border-top:1px solid var(--border); }
  .pdfrows .cprow { border-bottom:1px dashed rgba(48,54,61,.6); padding:6px 2px; }
  .pdfempty { color:var(--muted); font-size:.88rem; padding:6px 0; }
  .status { color:var(--muted); font-size:.82rem; margin:8px 0; }
  #ver { position:fixed; bottom:6px; right:8px; font-size:10px; color:#3a4048; }
  /* live bus map */
  .dep { cursor:pointer; }
  .dep .chev { color:#3a4048; font-size:1.2rem; margin-left:2px; }
  .pickbtn { color:#3a4048; font-size:1.1rem; margin-left:2px; padding:2px 5px; }
  .dep.picked { outline:2px solid #3fb950; outline-offset:-2px; border-radius:14px; }
  .dep.picked .pickbtn { color:#3fb950; }
  #busmodal { position:fixed; inset:0; background:#000;
    display:none; z-index:1000; }
  #busmodal.show { display:block; }
  /* v8: the live view docked straight onto the main screen. Same markup,
     same dashboard, only smaller and in the flow of the page. */
  #livedock { margin:0 0 12px 0; }
  #busmodal.inline { position:static; inset:auto; display:block; z-index:1;
    background:transparent; }
  #busmodal.inline #bussheet { position:static; inset:auto; height:auto;
    border:1px solid var(--cyan); border-radius:14px; overflow:hidden; }
  #busmodal.inline #busmapCanvas { flex:0 0 150px; height:150px; }
  #busmodal.inline .bm-dash { position:static; height:auto; min-height:0;
    max-height:none; flex:0 0 auto; }
  #busmodal.inline .bm-page { max-height:200px; }
  #busmodal.inline .bm-exit { top:8px; left:8px; width:32px; height:32px; }
  /* v8: full screen means big and readable at arm’s length */
  #busmodal.show .bm-dash { font-size:1.12rem; }
  #busmodal.show .bm-route { font-size:1.15rem; padding:3px 13px; }
  #busmodal.show .bm-dest { font-size:1.15rem; }
  #busmodal.show .bm-tab { font-size:.95rem; padding:9px 0; }
  #busmodal.show .nx-name { font-size:1.75rem; }
  #busmodal.show .nx-eta { font-size:2.5rem; }
  #busmodal.show .nx-clock, #busmodal.show .nx-paren { font-size:1.1rem; }
  #busmodal.show .nx-sub { font-size:1rem; }
  #busmodal.show .st-row, #busmodal.show .lv-row,
  #busmodal.show .lv-head-row { font-size:1rem; }
  #busmodal.show .kv { font-size:1.05rem; }
  #busmodal.show .stbig { font-size:2.1rem; }
  #bussheet { position:absolute; inset:0; background:var(--bg);
    padding:0; display:flex; flex-direction:column; }
  .bm-exit { position:absolute; top:12px; left:12px; z-index:5;
    width:38px; height:38px; display:flex; align-items:center; justify-content:center;
    background:rgba(13,17,23,.82); border:1px solid var(--border); border-radius:8px;
    color:var(--text); font-size:1.1rem; cursor:pointer; }
  #busmapCanvas { flex:1; width:100%; border-radius:0; background:var(--card); }
  .bm-info { position:absolute; left:0; right:0; bottom:0; z-index:5;
    background:rgba(13,17,23,.82); padding:8px 14px; font-size:.85rem;
    color:var(--text); line-height:1.5; }
  .bm-info b { color:var(--cyan); }
  .bm-delay.late { color:#f85149; font-weight:700; }
  .bm-delay.ontime { color:#3fb950; font-weight:700; }
  .bm-delay.est { color:var(--muted); font-weight:600; }
  #setupmodal { position:fixed; inset:0; background:rgba(0,0,0,.55);
    display:none; z-index:1001; }
  #setupmodal.show { display:block; }
  #setupsheet { position:absolute; left:0; right:0; bottom:0; background:var(--bg);
    border-top:1px solid var(--border); border-radius:16px 16px 0 0;
    padding:12px 14px 20px; max-height:88vh; overflow-y:auto; }
  .zet-card { background:var(--card); border:1px solid var(--border);
    border-radius:12px; padding:12px; margin-bottom:12px; }
  .zet-h { font-weight:700; font-size:.98rem; margin-bottom:8px;
    display:flex; align-items:center; gap:8px; }
  .zet-tag { font-size:.66rem; font-weight:700; padding:2px 8px; border-radius:10px; }
  .zet-tag.rule { color:#3fb950; border:1px solid #3fb950; }
  .zet-tag.exp { color:#e3b341; border:1px solid #e3b341; }
  .zet-body { font-size:.86rem; color:var(--text); line-height:1.6; }
  .zet-body b { color:var(--cyan); }
  .zet-note { display:block; color:var(--muted); font-size:.76rem; margin-top:6px; line-height:1.4; }
  .zet-legend { font-size:.74rem; color:var(--muted); margin-top:10px; line-height:1.45; }
  .mapstyle-row { display:flex; flex-wrap:wrap; gap:8px; }
  .mapstyle-btn { border:1px solid var(--border); background:var(--bg); color:var(--muted);
    border-radius:14px; padding:7px 14px; font-size:.86rem; font-weight:600; cursor:pointer; }
  .mapstyle-btn.on { border-color:var(--cyan); color:var(--cyan); }
  .bm-legend { font-size:.74rem; color:var(--muted); }
  .setup-label { font-size:.9rem; color:var(--text); margin:4px 0 8px; }
  #keysArea { width:100%; box-sizing:border-box; background:var(--card);
    border:1px solid var(--border); color:var(--text); border-radius:10px;
    padding:10px; font-family:monospace; font-size:.85rem; resize:vertical; }
  .setup-save { margin-top:10px; background:rgba(212,160,23,.12); color:var(--cyan);
    border:1px solid var(--cyan); border-radius:16px; padding:8px 18px;
    font-size:.95rem; font-weight:700; cursor:pointer; }
  .setup-msg { font-size:.85rem; color:var(--soon); margin-top:8px; min-height:1em; }
  .setup-note { font-size:.74rem; color:var(--muted); margin-top:10px; line-height:1.4; }
  .keydot { display:inline-block; width:11px; height:11px; border-radius:50%;
    background:#5a626c; margin-left:6px; vertical-align:middle; box-shadow:0 0 0 2px rgba(0,0,0,.25) inset; }
  .keydot.ok { background:#3fb950; } .keydot.bad { background:#f85149; }
  .keyfile { position:absolute; width:1px; height:1px; opacity:0; overflow:hidden; }
  .keybtn { display:inline-block; margin:4px 6px 4px 0; cursor:pointer; }
  .keybtn.ghost { background:transparent; border:1px solid var(--border); color:var(--muted); }
  .keybtn.danger { background:rgba(248,81,73,.12); border:1px solid rgba(248,81,73,.5); color:#f85149; }
  .pmrow { display:flex; align-items:center; gap:10px; padding:7px 8px; border:1px solid var(--border);
    border-radius:10px; background:var(--card); margin-bottom:6px; font-size:.86rem; }
  .pmrow .pmr { font-weight:700; min-width:40px; }
  .pmrow .pmmeta { color:var(--muted); font-size:.78rem; }
  .pmrow .pmok { color:#3fb950; } .pmrow .pmno { color:#d4a017; }
  .pmrow .pmdel { margin-left:auto; color:#f85149; border:1px solid rgba(248,81,73,.5);
    border-radius:9px; padding:3px 10px; font-size:.76rem; font-weight:700; cursor:pointer; background:transparent; }

  /* ---- driver-style trip dashboard over the map ---- */
  .bm-dash { position:absolute; left:0; right:0; bottom:0; z-index:5;
    height:calc(100dvh - 100vw); min-height:42dvh; max-height:78dvh;
    display:flex; flex-direction:column;
    background:#000;
    border-top:1px solid var(--border); padding:9px 14px 12px; color:var(--text); }
  .bm-top { display:flex; align-items:center; gap:8px; margin-bottom:8px; }
  .bm-route { font-weight:800; color:#08121a; border-radius:8px; padding:2px 10px; font-size:.95rem; background:var(--cyan); }
  .bm-dest { font-weight:700; color:var(--text); font-size:.95rem; flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .bm-src { font-size:.64rem; font-weight:700; padding:2px 8px; border-radius:10px; white-space:nowrap; }
  .bm-src.live { color:#3fb950; border:1px solid #3fb950; }
  .bm-src.est { color:var(--muted); border:1px solid var(--border); }
  .bm-tabs { display:flex; gap:6px; margin-bottom:9px; }
  .bm-tab { flex:1; background:var(--card); border:1px solid var(--border); color:var(--muted);
    border-radius:13px; padding:6px 0; font-size:.78rem; font-weight:700; cursor:pointer; }
  .bm-tab.on { border-color:var(--cyan); color:var(--cyan); background:rgba(57,208,216,.10); }
  .bm-page { flex:1 1 auto; min-height:0; overflow-y:auto; }
  .lv-stats { margin-top:12px; padding-top:8px; border-top:1px solid var(--border); }
  .nx-label { font-size:.70rem; color:var(--muted); letter-spacing:.09em; text-transform:uppercase; }
  .nx-name { font-size:1.35rem; font-weight:800; line-height:1.15; margin:1px 0 6px; }
  .nx-row { display:flex; align-items:baseline; gap:10px; flex-wrap:wrap; }
  .nx-eta { font-size:1.9rem; font-weight:800; color:var(--cyan); line-height:1; }
  .nx-clock { font-size:.9rem; color:var(--muted); }
  .nx-paren { font-size:.95rem; font-weight:700; }
  .nx-paren.late { color:#f85149; } .nx-paren.ok { color:#3fb950; } .nx-paren.est { color:var(--muted); }
  .nx-sub { font-size:.8rem; color:var(--muted); margin-top:7px; }
  .bm-prog { height:5px; background:var(--card); border-radius:3px; margin-top:9px; overflow:hidden; }
  .bm-prog > i { display:block; height:100%; background:var(--cyan); border-radius:3px; transition:width .5s linear; }
  .st-list { }
  .st-row { display:flex; align-items:center; gap:8px; padding:5px 0; border-bottom:1px solid rgba(255,255,255,.05); font-size:.86rem; }
  .st-row .st-eta { width:52px; color:var(--cyan); font-weight:700; flex:none; }
  .st-row .st-name { flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .st-row .st-clock { color:var(--muted); font-size:.8rem; flex:none; }
  .st-row.mine { color:#3fb950; font-weight:700; }
  .st-row.mine .st-eta { color:#3fb950; }
  .kv { display:flex; justify-content:space-between; gap:10px; padding:5px 0; font-size:.88rem; border-bottom:1px solid rgba(255,255,255,.05); }
  .kv > span { color:var(--muted); } .kv > b { color:var(--text); font-weight:700; text-align:right; }
  .stbig { font-size:1.55rem; font-weight:800; }
  .stbig.late { color:#f85149; } .stbig.ok { color:#3fb950; }
  .lv-head-row, .lv-row { display:flex; gap:6px; align-items:center; font-size:.78rem; padding:3px 0; border-bottom:1px solid rgba(255,255,255,.05); }
  .lv-head-row { color:var(--muted); font-weight:700; }
  .lv-seq { width:20px; flex:none; color:var(--muted); }
  .lv-name { flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .lv-sched { width:42px; flex:none; color:var(--muted); }
  .lv-pred { width:42px; flex:none; color:var(--cyan); font-weight:700; }
  .lv-d { width:56px; flex:none; text-align:right; }
  .lv-d.late { color:#f85149; } .lv-d.ok { color:#3fb950; }
  .lv-row.past { opacity:.45; }
  .bm-watch { flex:none; font-size:.66rem; font-weight:700; padding:3px 9px; border-radius:11px; cursor:pointer;
    background:var(--card); border:1px solid var(--border); color:var(--muted); }
  .bm-watch.on { border-color:#3fb950; color:#3fb950; background:rgba(63,185,80,.10); }
  .watchrow { display:flex; align-items:center; gap:10px; padding:10px 12px; margin-bottom:8px; cursor:pointer;
    background:rgba(63,185,80,.08); border:1px solid #2b6e3a; border-radius:14px; }
  .watchrow .wstop { margin-left:auto; color:var(--muted); font-weight:700; padding:0 4px; }
</style>
</head>
<body>
  <div class="tophud">
    <button class="fs" id="fsBtn" title="Fullscreen">⛶</button>
    <div class="clock" id="clock">--:--</div>
    <button class="gear" id="gearBtn" title="Setup">⚙</button>
  </div>
  <div class="pills" id="pills"></div>
  <div class="filters" id="filters" style="display:none"></div>
  <div id="livedock"></div>
  <div class="status" id="status"></div>
  <div id="deps"></div>
  <div id="pdfview" style="display:none"></div>

  <!-- C tab: colour wheel. The live schedule shows THROUGH this overlay and
       updates instantly as colours change. -->
  <div id="colormodal">
    <div class="cw-head">
      <span class="cw-title">C · colour wheel</span>
      <button id="cwClose" class="cw-close">Done</button>
    </div>
    <div class="cw-stage">
      <div class="cw-wheel">
        <div class="cw-ring" id="cwRing"></div>
        <div class="cw-center">
          <div class="cw-ellist" id="cwElList"></div>
          <div class="cw-pager"><button id="cwPrev" class="cw-pg">‹</button>
            <span id="cwPage" class="cw-pgn">1/1</span>
            <button id="cwNext" class="cw-pg">›</button></div>
          <div class="cw-cur"><span class="cw-swatch" id="cwCurrent"></span>
            <span id="cwHex" class="cw-hex">#000000</span></div>
        </div>
      </div>
    </div>
    <div class="cw-tools">
      <label class="cw-llbl">lightness</label>
      <input type="range" id="cwLight" min="15" max="90" value="55" class="cw-range">
      <div class="cw-neutrals" id="cwNeutrals"></div>
      <div class="cw-hint">Opposite colours contrast, neighbours harmonise.
        Pick an element in the middle, then a colour. The page behind changes live.</div>
    </div>
  </div>

  <div id="busmodal"><div id="bussheet">
    <button class="bm-exit" id="bmClose" title="Exit full screen">⛶</button>
    <div id="busmapCanvas"></div>
    <div class="bm-dash" id="bmDash">
      <div class="bm-top">
        <span class="bm-route" id="bmRoute">—</span>
        <span class="bm-dest" id="bmDest"></span>
        <span class="bm-src" id="bmSrc"></span>
        <button class="bm-watch" id="bmWatch">Keep on list</button>
      </div>
      <div class="bm-tabs" id="bmTabs">
        <button class="bm-tab on" data-pg="4">Live</button>
        <button class="bm-tab" data-pg="0">Now</button>
        <button class="bm-tab" data-pg="1">Stops</button>
        <button class="bm-tab" data-pg="2">Trip</button>
        <button class="bm-tab" data-pg="3">Status</button>
      </div>
      <div class="bm-page" id="bmPage"></div>
    </div>
  </div></div>

  <div id="setupmodal"><div id="setupsheet">
    <div class="bm-head">
      <span class="bm-title">ZET feeds</span>
      <button class="bm-close" id="setupClose">Close</button>
    </div>

    <div class="zet-card">
      <div class="zet-h">Schedule <span class="zet-tag rule">the rule</span></div>
      <div class="zet-body" id="zetStatic">…</div>
      <button id="zetRebuild" class="setup-save">Rebuild schedule</button>
    </div>

    <div class="zet-card">
      <div class="zet-h">Live feed <span class="zet-tag exp">experimental</span></div>
      <div class="zet-body" id="zetLive">…</div>
      <div class="zet-legend">Green wifi marks a bus broadcasting its position
        now. Times in <span class="le-t">(yellow)</span> and delays in
        <span class="le-d">red</span> are live estimates, trusted only as far as
        they prove themselves over time.</div>
    </div>

    <div class="zet-card">
      <div class="zet-h">Map appearance</div>
      <div class="mapstyle-row" id="mapStyleRow">
        <button class="mapstyle-btn" data-style="dark">Dark</button>
        <button class="mapstyle-btn" data-style="light">Light</button>
        <button class="mapstyle-btn" data-style="satellite">Satellite</button>
        <button class="mapstyle-btn" data-style="terrain">Terrain</button>
        <button class="mapstyle-btn" data-style="hybrid">Hybrid</button>
      </div>
      <span class="zet-note">Applies the next time you open a bus on the map.</span>
    </div>

    <div class="zet-card">
      <div class="zet-h">Google Maps key
        <span class="keydot" id="mapsDot" title="key status"></span></div>
      <input type="file" id="mapsFile" accept=".txt,text/plain" class="keyfile">
      <label for="mapsFile" class="setup-save keybtn">Load key from file</label>
      <div id="setupMsg" class="setup-msg"></div>
      <p class="setup-note">The key itself is never shown. Stored on your phone
        in ~/.commute/google-api.txt.</p>
    </div>

    <div class="zet-card">
      <div class="zet-h">Direction <span class="zet-tag rule">automatic</span></div>
      <div class="mapstyle-row" id="autoDirRow">
        <button class="mapstyle-btn" data-auto="1">Automatic</button>
        <button class="mapstyle-btn" data-auto="0">Manual</button>
      </div>
      <div class="zet-body" id="autoDirBody">…</div>
      <span class="zet-note">Near home the app opens the ride to Nova TV, near
        Nova TV the ride to Glavni kolodvor, near Britanski trg the Britanac
        corridor. Choosing a direction by hand holds it for twenty minutes.
        The phone only reports its position when the app is opened on
        127.0.0.1, not over Wi‑Fi.</span>
    </div>

    <div class="zet-card">
      <div class="zet-h">Lines shown <span class="zet-tag rule">per corridor</span></div>
      <div id="corrLines"></div>
      <span class="zet-note">Untick a line to hide it from that direction,
        whichever source is speaking. Saved on your phone.</span>
    </div>

    <div class="zet-card">
      <div class="zet-h">Colours <span class="zet-tag rule">color wheel</span></div>
      <span class="zet-note">Build your own scheme with <b>Open colour wheel</b> below.
        Pick a UI element, pick a colour from the wheel, watch the live page
        change behind it.</span>
      <button id="openColorFromGear" class="setup-save keybtn">Open colour wheel</button>
      <button id="resetColors" class="setup-save keybtn ghost">Reset colours</button>
    </div>

    <div class="zet-card">
      <div class="zet-h">Gemini key <span class="zet-tag exp">PDF reader</span>
        <span class="keydot" id="gemDot" title="key status"></span></div>
      <input type="file" id="gemFile" accept=".txt,text/plain" class="keyfile">
      <label for="gemFile" class="setup-save keybtn">Load key from file</label>
      <button id="gemTest" class="setup-save keybtn ghost">Test key</button>
      <div id="gemMsg" class="setup-msg"></div>
      <p class="setup-note">Green means the key works, red means it does not.
        The key is never shown. Reads the official ZET PDFs once each. Stored in
        ~/.commute/gemini-api.txt.</p>
    </div>

    <div class="zet-card">
      <div class="zet-h">PDF manager <span class="zet-tag rule">cache</span></div>
      <div id="pdfMgr"><span class="zet-note">Loading…</span></div>
      <button id="pdfClearAll" class="setup-save keybtn danger">Delete all cached PDFs</button>
      <p class="setup-note">Line PDFs and their parsed timetables are cached
        forever and never refetched until you delete them here.</p>
    </div>

    <div class="zet-card">
      <div class="zet-h">About</div>
      <div class="kv"><span>Version</span><b id="verLine">…</b></div>
    </div>
  </div></div>

<script>
let DATA = null;
let active = localStorage.getItem("bus_dir") || "to-work";
let LIVE = {};            // trip_id -> {stops:{stop_id:{t,d}}, delay}  from realtime
// Green wifi: shown next to a bus that is broadcasting its position live.
const WIFI = '<svg class="wifi" width="14" height="11" viewBox="0 0 16 12" ' +
  'xmlns="http://www.w3.org/2000/svg">' +
  '<circle cx="8" cy="10" r="1.2" fill="#3fb950"/>' +
  '<path d="M4.8 7.2a4.5 4.5 0 0 1 6.4 0" fill="none" stroke="#3fb950" ' +
  'stroke-width="1.5" stroke-linecap="round"/>' +
  '<path d="M2.6 4.8a7.6 7.6 0 0 1 10.8 0" fill="none" stroke="#3fb950" ' +
  'stroke-width="1.5" stroke-linecap="round"/></svg>';
let LIVE_AT = 0;          // last successful live fetch (ms)
let LIVE_PENDING = false;
let MUTED = {};
try { MUTED = JSON.parse(localStorage.getItem("bus_muted") || "{}") || {}; }
catch (e) { MUTED = {}; }
function saveMuted() { localStorage.setItem("bus_muted", JSON.stringify(MUTED)); }

function tickClock() {
  const d = new Date();
  document.getElementById("clock").textContent =
    d.toLocaleTimeString([], {hour:"2-digit", minute:"2-digit", second:"2-digit"});
  if (DATA) renderDeps();   // keep minutes live and drop departed buses
}
setInterval(tickClock, 1000); tickClock();

let SCOPE_H = parseInt(localStorage.getItem("commute_scope_h") || "2", 10) || 2;
function saveScope(){ try { localStorage.setItem("commute_scope_h", String(SCOPE_H)); } catch(e){} }

let PICKED = null; try { PICKED = JSON.parse(localStorage.getItem("commute_pick") || "null"); } catch(e){}
function savePick(){ try { localStorage.setItem("commute_pick", JSON.stringify(PICKED)); } catch(e){} }
function pickKey(dep){ return dep.trip || (dep.route + "@" + (dep.time || "")); }
function isPicked(dep){ return !!(PICKED && dep && PICKED.key === pickKey(dep)); }
function togglePick(dep){ PICKED = isPicked(dep) ? null : { key: pickKey(dep), dir: active }; savePick(); renderDeps(); }

let WATCHING = null; try { WATCHING = JSON.parse(localStorage.getItem("commute_watch") || "null"); } catch(e){}
function saveWatch(){ try { localStorage.setItem("commute_watch", JSON.stringify(WATCHING)); } catch(e){} }
function setWatch(dep){
  WATCHING = dep ? { trip: dep.trip, route: dep.route, time: dep.time, from: dep.from, to: dep.to,
    exit: dep.exit, headsign: dep.headsign, stop_id: dep.stop_id, dir: active } : null;
  saveWatch(); try { renderDeps(); } catch(e){}
}
function isWatching(dep){ return !!(WATCHING && dep && WATCHING.trip && WATCHING.trip === dep.trip); }

/* ===== v7: GTFS / PDF source tabs + commute pills ===== */
// v12: the source is no longer a choice. GTFS is the source; the printed ZET
// timetables take over by themselves when a build lands empty or broken, and
// hand back the moment GTFS is healthy again. SRC_TAB is derived, never stored.
let SRC_TAB = "gtfs";
let CP_OPEN = {};   // "dir|route" -> true when a commute pill is unfolded
// PDF scheduler state. PDFSCHED[route] = parsed schedule. Persisted to
// localStorage so it is instant on next open and survives offline; the server
// also keeps the PDF and the Gemini result on disk permanently.
let PDFSCHED = {};
try { PDFSCHED = JSON.parse(localStorage.getItem("commute_pdfsched") || "{}") || {}; }
catch (e) { PDFSCHED = {}; }
function savePdfSched() {
  try { localStorage.setItem("commute_pdfsched", JSON.stringify(PDFSCHED)); } catch (e) {}
}
let PDF_PENDING = {};
let GTFS_FETCH_FAILED = false;
// Sanity check: the GTFS build is healthy only when at least one direction
// actually produced departures. A broken/corrupt ZET zip yields nothing.
function gtfsHealthy() {
  if (GTFS_FETCH_FAILED) return false;
  if (!DATA || !DATA.directions) return false;
  return DATA.directions.some(d => d.departures && d.departures.length);
}
// A fresh static download is only worth offering when the local feed can't
// serve today: it never arrived, it's broken, or bus.json holds another day.
// When bus.json already holds a healthy copy of today's schedule the download
// arrow would do nothing, so it is hidden and can't be dead-tapped. (Forcing a
// rebuild anyway still lives in Settings → Rebuild schedule.)
function refreshNeeded() {
  if (GTFS_FETCH_FAILED || !DATA) return true;
  if (!gtfsHealthy()) return true;
  const tn = new Date();
  const ymd = tn.getFullYear() + String(tn.getMonth() + 1).padStart(2, "0") +
              String(tn.getDate()).padStart(2, "0");
  if (DATA.service_date && DATA.service_date !== ymd) return true;
  return false;
}
// -----------------------------------------------------------------------
// COMMUTE CORRIDOR (the v1 idea, made explicit and editable).
// Every alternative line that gets you there, and the stop you use for it.
//   to-work : you board Glavni kolodvor, ride to a stop near Nova TV
//   to-home : you board a stop near Nova TV, ride to Glavni kolodvor
// Each entry is { r: line, stop: your boarding/alighting stop for that line }.
// Edit freely; both the GTFS and PDF tabs read from this same list.
// -----------------------------------------------------------------------
// origin = the terminal the PDF times start from, in this direction.
// myStop  = the stop you actually board/alight at (used on the GTFS tab).
const CORRIDOR = {
  "to-work": {                       // you board Glavni kolodvor
    routes: [
      { r: "268", origin: "Glavni kolodvor", myStop: "Oreškovićeva" },
      { r: "241", origin: "Glavni kolodvor", myStop: "Oreškovićeva" },
      { r: "220", origin: "Glavni kolodvor", myStop: "Abramovićeva" },
    ],
  },
  "to-home": {                       // you ride to Glavni kolodvor
    dest: "Glavni kolodvor",
    routes: [
      { r: "268", origin: "Velika Gorica", myStop: "Oreškovićeva" },
      { r: "241", origin: "Veliko polje",  myStop: "Oreškovićeva" },
      { r: "220", origin: "Dugave",        myStop: "Abramovićeva" },
      { r: "109", origin: "Dugave",        myStop: "Oreškovićeva" },
    ],
  },
  "britanac": {
    dest: "Pavlinovićeva",
    routes: [
      { r: "101", origin: "Britanski trg", myStop: "Britanski trg" },
      { r: "138", origin: "Britanski trg", myStop: "Britanski trg" },
    ],
  },
};
// -----------------------------------------------------------------------
// v12: AUTO DIRECTION. Three places on the map decide which corridor is on
// screen, so the app is already showing the right ride when it opens.
//   home, Pavlinovićeva 7  ->  to-work   (the ride to Nova TV)
//   Nova TV, Buzinski krči ->  to-home   (the ride to Glavni kolodvor)
//   Britanski trg          ->  britanac  (the Britanac corridor)
// Home and Britanski trg are only about 370 m apart, so a switch is made only
// when the nearest anchor stays nearest even after the reported GPS error is
// added to its distance. Anywhere else, or with a vague fix, nothing moves and
// the last direction stays. Editing an anchor is just editing a number here.
// -----------------------------------------------------------------------
const ANCHORS = [
  { dir: "to-work",  name: "home",          lat: 45.815180, lon: 15.961046, radius: 500  },
  { dir: "to-home",  name: "Nova TV",       lat: 45.755020, lon: 15.991475, radius: 1800 },
  { dir: "britanac", name: "Britanski trg", lat: 45.812982, lon: 15.964504, radius: 500  },
];
const AUTO_HOLD_MS = 20 * 60 * 1000;   // a manual tap wins for this long
let AUTO_DIR = localStorage.getItem("commute_autodir") !== "0";
function saveAutoDir(){ try { localStorage.setItem("commute_autodir", AUTO_DIR ? "1" : "0"); } catch(e){} }
let AUTO_HOLD = 0;         // ms timestamp until which the manual pick holds
let LOC_LABEL = "";        // name of the recognised place, "" when unknown
let LOC_STATE = "waiting"; // waiting | ok | far | vague | denied | off
let LOC_ACC = 0;
function metres(aLat, aLon, bLat, bLon) {
  const R = 6371000, rad = Math.PI / 180;
  const dLat = (bLat - aLat) * rad, dLon = (bLon - aLon) * rad;
  const la = aLat * rad, lb = bLat * rad;
  const h = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(la) * Math.cos(lb) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}
function applyPosition(p) {
  const lat = p.coords.latitude, lon = p.coords.longitude;
  const acc = Math.max(0, p.coords.accuracy || 0);
  LOC_ACC = Math.round(acc);
  const ranked = ANCHORS
    .map(a => ({ dir: a.dir, name: a.name, radius: a.radius,
                 d: metres(lat, lon, a.lat, a.lon) }))
    .sort((x, y) => x.d - y.d);
  const near = ranked[0], next = ranked[1];
  if (!near || near.d > near.radius) {
    LOC_LABEL = ""; LOC_STATE = "far"; paintBadges(); return;
  }
  if (next && near.d + acc >= next.d) {         // too vague to tell them apart
    LOC_LABEL = ""; LOC_STATE = "vague"; paintBadges(); return;
  }
  LOC_LABEL = near.name; LOC_STATE = "ok";
  if (!AUTO_DIR || Date.now() < AUTO_HOLD || active === near.dir) {
    paintBadges(); return;
  }
  active = near.dir;
  try { localStorage.setItem("bus_dir", active); } catch (e) {}
  try { renderPills(); renderFilters(); renderDeps(); } catch (e) { paintBadges(); }
}
function locFail(err) {
  LOC_LABEL = "";
  LOC_STATE = (err && err.code === 1) ? "denied" : "off";
  paintBadges();
}
function pollLocation() {
  if (!navigator.geolocation) { LOC_STATE = "off"; LOC_LABEL = ""; paintBadges(); return; }
  navigator.geolocation.getCurrentPosition(applyPosition, locFail,
    { enableHighAccuracy: true, timeout: 12000, maximumAge: 60000 });
}
setInterval(pollLocation, 120000);
document.addEventListener("visibilitychange", () => { if (!document.hidden) pollLocation(); });

function corridorRoutes() { return (CORRIDOR[active] || { routes: [] }).routes; }
function corridorEntry(r) { return corridorRoutes().find(x => x.r === r) || {}; }
function corridorStop(r) { return corridorEntry(r).myStop || ""; }
function corridorOrigin(r) { return corridorEntry(r).origin || ""; }
// Per-corridor line exclusions, ticked off in the gear, saved on the phone.
let EXCLUDED = {};
try { EXCLUDED = JSON.parse(localStorage.getItem("commute_excluded") || "{}") || {}; }
catch (e) { EXCLUDED = {}; }
function saveExcluded(){ try { localStorage.setItem("commute_excluded", JSON.stringify(EXCLUDED)); } catch(e){} }
function isExcluded(dir, r){ return (EXCLUDED[dir] || []).includes(r); }
function toggleExcluded(dir, r){
  const cur = (EXCLUDED[dir] || []).slice();
  const i = cur.indexOf(r);
  if (i >= 0) cur.splice(i, 1); else cur.push(r);
  EXCLUDED[dir] = cur; saveExcluded();
}
function notExcluded(r){ return !isExcluded(active, r); }
// Route list for the active direction. GTFS uses its own geometry-derived
// departures, but if a corridor line is missing from that feed we still add
// it so both tabs offer the same set of alternatives.
function pdfRoutesFor(d) {
  const corr = corridorRoutes().map(x => x.r);
  const fromData = d && d.departures && d.departures.length
    ? [...new Set(d.departures.map(x => x.route))] : [];
  const merged = [...new Set([...corr, ...fromData])];
  return merged.filter(notExcluded).sort(routeOrder);
}
// Routes to show as filter chips and to build rows for, for the active tab.
function activeRoutes(d) {
  if (SRC_TAB === "pdf") return pdfRoutesFor(d);
  const fromData = d && d.departures ? [...new Set(d.departures.map(x => x.route))] : [];
  // even on GTFS, surface corridor lines the feed omitted, so the options match
  const corr = corridorRoutes().map(x => x.r);
  return [...new Set([...fromData, ...corr])].filter(notExcluded).sort(routeOrder);
}
function dayKey() {
  const wd = new Date().getDay();
  return wd === 0 ? "sunday" : wd === 6 ? "saturday" : "workday";
}
// Fetch (and cache) the PDF-derived schedule for the routes on screen.
// The server downloads each ZET vozni red PDF and lets Gemini read it once,
// then serves it from disk, so this is instant after the first call.
function fetchPdfSched(routes) {
  const need = routes.filter(r => !PDFSCHED[r] && !PDF_PENDING[r]);
  if (!need.length) return;
  need.forEach(r => PDF_PENDING[r] = true);
  fetch("pdf-sched?routes=" + encodeURIComponent(need.join(",")),
        { cache: "no-store" })
    .then(r => r.json())
    .then(d => {
      need.forEach(r => delete PDF_PENDING[r]);
      if (d && d.ok && d.routes) {
        Object.keys(d.routes).forEach(r => { if (d.routes[r] && d.routes[r].directions) PDFSCHED[r] = d.routes[r]; });
        savePdfSched();
        renderDeps();
      }
    })
    .catch(() => { need.forEach(r => delete PDF_PENDING[r]); });
}
function normTerm(x){ return (x||"").toLowerCase().replace(/[^a-zšđčćž]/g,""); }
// Times for a route from the terminal that matches this direction's origin.
function pdfTimesFor(r) {
  const sc = PDFSCHED[r];
  if (!sc) return null;
  const day = dayKey();
  const dirs = sc.directions || [];
  const want = normTerm(corridorOrigin(r));
  if (want && dirs.length) {
    let hit = dirs.find(d => normTerm(d.terminal).includes(want) ||
                             want.includes(normTerm(d.terminal)));
    if (hit) return hit[day] || [];
  }
  if (dirs.length === 1) return dirs[0][day] || [];   // circular line
  // no terminal match: fall back to flat (first terminal) times
  return sc[day] || (dirs[0] ? dirs[0][day] : []) || [];
}
function pdfUpcoming(r, grace) {
  const times = pdfTimesFor(r);
  if (times === null) return null;            // still loading
  return times.map(t => ({ route: r, time: t, _m: minsUntil(t) }))
              .filter(x => x._m >= -(grace || 0))
              .sort((a, b) => a._m - b._m);
}
// v9: board / exit names for a direction, taken from the GTFS deps when we
// have them so the PDF rows read the same, else from a small static map.
// v9 CORE: one departures array per direction, GTFS-shaped, from either
// source. This is what makes both tabs show the SAME data; only the origin
// differs. PDF rows carry no trip id, so they simply have no live map.
function depsForDir(d) {
  if (SRC_TAB === "pdf") {
    const routes = pdfRoutesFor(d);
    fetchPdfSched(routes);
    const cfg = CORRIDOR[active] || {};
    const out = [];
    routes.forEach(r => {
      const times = pdfTimesFor(r);
      if (!times) return;
      const origin = corridorOrigin(r);
      // PDF times are terminal departures. Show the terminal they start from,
      // honestly, instead of pretending they are your-stop times.
      const from = origin || "terminal";
      const exit = active === "to-home" ? (cfg.dest || "Glavni kolodvor") : "";
      times.forEach(t => {
        out.push({ route: r, time: t, from: from, exit: exit, to: exit,
                   pdf: true });
      });
    });
    return out;
  }
  // GTFS: drop excluded lines too (watched/picked rides survive so a pinned
  // ride is never lost)
  return ((d && d.departures) ? d.departures : [])
    .filter(x => notExcluded(x.route) || isWatching(x) || isPicked(x));
}
// The right-hand end of the direction bar. GTFS is silent because it is the
// normal state; only the fallback speaks, and only while it lasts.
function paintBadges() {
  const b = document.getElementById("srcbadge");
  if (b) {
    b.textContent = "PDF";
    b.style.display = SRC_TAB === "pdf" ? "" : "none";
    b.title = "The GTFS feed came back empty or broken, so the printed ZET timetables are speaking.";
  }
  const t = document.getElementById("filtTog");
  if (t) {
    t.textContent = FILT_OPEN ? "\u25be" : "\u25b8";
    t.className = "filttog" + (FILT_OPEN ? " open" : (filtersActive() ? " act" : ""));
    t.title = FILT_OPEN ? "Hide the line filters" : "Filter the lines";
  }
}
// Called at the top of every repaint: decide the source from the health of the
// GTFS build, then show the badges and the matching pane.
function renderSrcTabs() {
  SRC_TAB = gtfsHealthy() ? "gtfs" : "pdf";
  paintBadges();
  document.getElementById("deps").style.display = SRC_TAB === "gtfs" ? "" : "none";
  document.getElementById("pdfview").style.display = SRC_TAB === "pdf" ? "" : "none";
}
function cpillClass(r) {
  return r === "241" || r === "221" ? "c241" : r === "268" ? "c268" : "cdef";
}
function routeOrder(a, b) {
  const rank = r => (r === "241" ? 0 : r === "268" ? 1 : 2);
  return rank(a) !== rank(b) ? rank(a) - rank(b)
       : (parseInt(a, 10) || 999) - (parseInt(b, 10) || 999);
}
// Commute pills: one per route option toward the active destination.
// Head shows the next two departures; tapping unfolds a vertical schedule
// of every upcoming bus of that route today (time, arrival, minutes).
function renderCommutePills(d, wrap, vertMax, srcPdf) {
  const muted = MUTED[active] || [];
  const routes = activeRoutes(d).filter(r => !muted.includes(r));
  if (srcPdf) fetchPdfSched(routes);
  routes.forEach(r => {
    let ups;
    if (srcPdf) {
      ups = pdfUpcoming(r, 0);
      if (ups === null) ups = [];   // still loading, pill says loading below
    } else {
      ups = ((d && d.departures) || [])
        .filter(x => x.route === r)
        .map(x => ({ ...x, _m: minsUntil(x.time) }))
        .filter(x => x._m >= 0)
        .sort((a, b) => a._m - b._m);
    }
    // honour the scope window in the pill head, exactly like the list below,
    // so a line that is done for today does not advertise tomorrow's first bus
    const inScope = ups.filter(x => SCOPE_H >= 24 || x._m <= SCOPE_H * 60);
    const headUps = inScope.length ? inScope : [];
    const loading = srcPdf && !PDFSCHED[r];
    const key = active + "|" + r;
    const p = document.createElement("div");
    p.className = "cpill " + cpillClass(r) + (CP_OPEN[key] ? " open" : "");
    const head = headUps.slice(0, 2)
      .map(x => x.time + " (" + x._m + " min)").join("  ·  ");
    let rows = "";
    ups.slice(0, vertMax || 12).forEach(x => {
      rows += '<div class="cprow"><span class="t">' + x.time + '</span>' +
        (x.arrive ? '<span class="a">→ ' + x.arrive + '</span>' : '') +
        '<span class="m' + (x._m <= 15 ? " soon" : "") + '">' + x._m + ' min</span></div>';
    });
    const tag = srcPdf ? corridorOrigin(r) : corridorStop(r);
    const stopTag = tag ? '<span class="cpstop">' +
      (srcPdf ? 'from ' : '@ ') + escHtml(tag) + '</span>' : "";
    p.innerHTML =
      '<div class="cph"><span class="cpr">' + r + '</span>' + stopTag +
      (headUps.length ? 'next: ' + head
                  : '<span class="cpnone">' +
                    (loading ? 'reading ZET PDF…' : 'no more today') +
                    '</span>') +
      '<span class="cpx">' + (CP_OPEN[key] ? "▴" : "▾") + '</span></div>' +
      '<div class="cpsched">' + (rows || '<div class="pdfempty">nothing upcoming</div>') + '</div>';
    p.addEventListener("click", () => {
      CP_OPEN[key] = !CP_OPEN[key]; renderDeps();
    });
    wrap.appendChild(p);
  });
}
// PDF tab: commute pills on top, then a printed-timetable style vertical
// card per route with a link to the official ZET vozni red PDF of the line.
function zetPdfUrl(r) {
  return "https://www.zet.hr/UserDocsImages/Autobusne%20linije%20-%20rasporedi/" +
    encodeURIComponent(r) + ".pdf";
}
// v12: the filter row starts folded away so the lines get the whole screen.
// The triangle at the end of the direction bar unfolds it, and turns cyan on
// its own when a filter is actually hiding something, so a muted line can
// never be forgotten behind a closed fold.
let FILT_OPEN = localStorage.getItem("commute_filtopen") === "1";
function saveFiltOpen(){ try { localStorage.setItem("commute_filtopen", FILT_OPEN ? "1" : "0"); } catch(e){} }
function filtersActive() {
  return (MUTED[active] || []).length > 0 || SCOPE_H !== 2;
}
function renderPills() {
  const wrap = document.getElementById("pills");
  wrap.innerHTML = "";
  (DATA ? DATA.directions : []).forEach(d => {
    const p = document.createElement("div");
    p.className = "pill" + (d.id === active ? " active" : "");
    p.textContent = d.label;
    p.addEventListener("click", () => {
      active = d.id; localStorage.setItem("bus_dir", active);
      // A direction chosen by hand outranks the position for twenty minutes,
      // so the app never yanks the screen back while it is being read.
      AUTO_HOLD = Date.now() + AUTO_HOLD_MS;
      renderPills(); renderFilters(); renderDeps();
    });
    wrap.appendChild(p);
  });
  // Everything else lives at the right-hand end of this same row.
  const meta = document.createElement("div");
  meta.className = "pillmeta";
  meta.innerHTML = '<span class="srcbadge" id="srcbadge">PDF</span>' +
    '<button class="filttog" id="filtTog">\u25b8</button>';
  meta.querySelector("#filtTog").addEventListener("click", () => {
    FILT_OPEN = !FILT_OPEN; saveFiltOpen();
    renderFilters(); paintBadges();
  });
  wrap.appendChild(meta);
  paintBadges();
}

// Filter pills, folded away until the triangle is tapped. One chip per route
// in this direction; tapping a chip mutes or unmutes it, "All" clears them.
function renderFilters() {
  const wrap = document.getElementById("filters");
  wrap.innerHTML = "";
  wrap.style.display = FILT_OPEN ? "" : "none";
  if (!FILT_OPEN) { paintBadges(); return; }
  if (!DATA) return;
  const d = DATA.directions.find(x => x.id === active) || DATA.directions[0];
  if (!d) return;
  const routes = activeRoutes(d);
  if (!routes.length) return;
  const muted = MUTED[active] || [];

  const all = document.createElement("div");
  all.className = "pill filt " + (muted.length === 0 ? "on" : "muted");
  all.textContent = "All";
  all.addEventListener("click", () => {
    MUTED[active] = []; saveMuted(); renderFilters(); renderDeps();
  });
  wrap.appendChild(all);

  // schedule scope: next 2 h by default, +2 h per tap, then all day, then back
  const sc = document.createElement("div");
  sc.className = "pill filt on";
  sc.style.borderColor = "var(--cyan)"; sc.style.color = "var(--cyan)";
  sc.textContent = SCOPE_H >= 24 ? "all day" : "next " + SCOPE_H + " h";
  sc.title = "Tap to widen the schedule window by 2 hours";
  sc.addEventListener("click", () => {
    SCOPE_H = SCOPE_H >= 24 ? 2 : (SCOPE_H >= 12 ? 24 : SCOPE_H + 2);
    saveScope(); renderFilters(); renderDeps();
  });
  wrap.appendChild(sc);

  routes.forEach(r => {
    const isMuted = muted.includes(r);
    const p = document.createElement("div");
    p.className = "pill filt " + (isMuted ? "muted" : "on") +
                  (r === "268" ? " f268" : "");
    p.textContent = r;
    p.addEventListener("click", () => {
      let m = (MUTED[active] || []).slice();
      if (m.includes(r)) m = m.filter(x => x !== r); else m.push(r);
      MUTED[active] = m; saveMuted(); renderFilters(); renderDeps();
    });
    wrap.appendChild(p);
  });
}

// minutes from now until a HH:MM departure today (handles after-midnight times)
function minsUntil(hhmm) {
  const now = new Date();
  const nowMins = now.getHours() * 60 + now.getMinutes();
  const parts = hhmm.split(":");
  let depMins = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
  let diff = depMins - nowMins;
  // GTFS can list 24:xx+ as past midnight; if a time looks far in the past
  // by more than 3h, treat it as tomorrow so it isn't wrongly shown.
  if (diff < -180) diff += 1440;
  return diff;
}

// Past-grace window so a late or just-missed bus still shows as a negative
// (red) pill: 10 min on the Nova TV view (from Glavni kolodvor), 5 min home.
function graceMins() {
  return active === "to-work" ? 10 : active === "to-home" ? 5 : 0;
}

// The 221 gateway: two stops from Glavni kolodvor to the hub where all the
// corridor buses pass. Only meaningful heading to work. Shown as a subtle,
// frameless status line at the very top, next two departures pipe-separated.
function gateway221Times() {
  const d = DATA && DATA.directions.find(x => x.id === "to-work");
  const now = new Date();
  const nowM = now.getHours() * 60 + now.getMinutes();
  let times = [];
  if (SRC_TAB === "pdf") {
    fetchPdfSched(["221"]);
    const sc = PDFSCHED["221"];
    if (sc) {
      const dirs = sc.directions || [];
      const gk = dirs.find(x => normTerm(x.terminal).includes(normTerm("Glavni kolodvor")));
      times = (gk ? gk[dayKey()] : (sc[dayKey()] || [])) || [];
    } else {
      return null;          // still reading the PDF
    }
  } else {
    times = ((d && d.featured) || []).map(f => f.time);
  }
  return times
    .map(t => { const pp = t.split(":");
      return { time: t, _m: parseInt(pp[0], 10) * 60 + parseInt(pp[1], 10) - nowM }; })
    .filter(x => x._m >= -1)
    .filter((x, i, a) => a.findIndex(y => y.time === x.time) === i)
    .sort((a, b) => a._m - b._m);
}
function render221Gateway(d, wrap) {
  if (active !== "to-work") return;        // gateway only makes sense to work
  const ups = gateway221Times();
  const row = document.createElement("div");
  row.className = "gw221";
  if (ups === null) {
    row.innerHTML = '<span class="g-lbl">221</span>' +
      '<span class="g-hint">reading ZET PDF…</span>';
  } else if (!ups.length) {
    row.innerHTML = '<span class="g-lbl">221</span>' +
      '<span class="g-none">no more today</span>';
  } else {
    const two = ups.slice(0, 2)
      .map(x => '<span class="g-t">' + x.time + '</span> <span class="g-hint">(' +
        x._m + ' min)</span>').join('<span class="g-sep">|</span>');
    row.innerHTML = '<span class="g-lbl">221</span>' + two +
      '<span class="g-hint">· gateway, 2 stops then take the first bus</span>';
  }
  wrap.appendChild(row);
}

function renderDeps() {
  renderSrcTabs();
  document.getElementById("pdfview").style.display = "none";
  const wrap = document.getElementById("deps");
  wrap.style.display = "";
  wrap.innerHTML = "";
  if (!DATA) return;
  const d = DATA.directions.find(x => x.id === active) || DATA.directions[0];
  render221Gateway(d, wrap);
  // v8: the corridor summary and the commute pills are gone from the GTFS
  // screen. Their place is taken by the live view, docked below. The pills
  // still carry the PDF tab, which has no live map to show.
  if (SRC_TAB === "pdf") {
    renderCommutePills(d, wrap, 12, true);
    const day = dayKey() === "workday" ? "Mon to Fri"
              : dayKey() === "saturday" ? "Saturday" : "Sunday";
    const srcLine = document.createElement("div");
    srcLine.className = "pdfnote";
    srcLine.innerHTML = day + " times read from the official ZET vozni red PDFs. " +
      "Each line shows the time it LEAVES its starting terminal (named on the " +
      "row); your stop is a few minutes later. As soon as the GTFS feed is " +
      "healthy again the app goes back to the exact time at your stop.";
    wrap.appendChild(srcLine);
  }
  const muted = MUTED[active] || [];
  const g = graceMins();

  // watched ride: resume banner, shown in every direction
  if (WATCHING) {
    const w = document.createElement("div");
    w.className = "watchrow";
    w.innerHTML = '<span class="route">' + WATCHING.route + '</span>' +
      '<span>watching ' + (WATCHING.time || "") + ' → ' + escHtml(WATCHING.exit || "") +
      ' · tap to reopen</span><span class="wstop" title="Stop watching">✕</span>';
    w.addEventListener("click", (e) => {
      if (e.target.classList.contains("wstop")) { setWatch(null); return; }
      openBusMap(WATCHING, "full");
    });
    wrap.appendChild(w);
  }

  // recompute minutes live; keep grace buses to -g (watched rides always stay),
  // drop muted routes, and window to the scope unless picked or watched
  let upcoming = depsForDir(d)
    .map(dep => ({ ...dep, _mins: minsUntil(dep.time) }))
    .filter(dep => dep._mins >= -g || isWatching(dep))
    .filter(dep => !muted.includes(dep.route) || isWatching(dep) || isPicked(dep))
    .filter(dep => SCOPE_H >= 24 || dep._mins <= SCOPE_H * 60 || isWatching(dep) || isPicked(dep))
    .sort((a, b) => a._mins - b._mins);

  // one row per (route, time, from, exit): the feed can list the same
  // departure under several service ids; keep the watched or picked copy
  const seenK = new Map();
  for (const dep of upcoming) {
    const k = dep.route + "|" + dep.time + "|" + (dep.from || "") + "|" + (dep.exit || "");
    const prev = seenK.get(k);
    if (!prev) { seenK.set(k, dep); continue; }
    if ((isWatching(dep) || isPicked(dep)) && !(isWatching(prev) || isPicked(prev))) seenK.set(k, dep);
  }
  upcoming = [...seenK.values()].sort((a, b) => a._mins - b._mins);

  if (PICKED && PICKED.dir === active && !upcoming.some(dep => isPicked(dep))) {
    PICKED = null; savePick();       // the picked ride has departed
  }

  if (!upcoming.length) {
    const e = document.createElement("div");
    e.className = "empty";
    e.textContent = STALE
      ? "No more departures in the buffered schedule, the fresh one is loading…"
      : "No more departures today.";
    wrap.appendChild(e);
    syncLiveDock([]);
    return;
  }
  const liveTrips = [];
  upcoming.forEach(dep => {
    let routeCls = "route";
    if (dep.dim) routeCls += " dim";
    else if (dep.route === "241") routeCls += " r241";
    else if (dep.route === "268") routeCls += " r268";

    // The schedule is the rule. Live is an experimental overlay only.
    if (dep.trip) liveTrips.push(dep.trip);
    let liveSecs = null, delaySec = null, isLive = false;
    const lv = dep.trip ? LIVE[dep.trip] : null;
    if (lv) {
      const ps = lv.stops ? lv.stops[dep.stop_id] : null;
      if (ps && ps.t != null) { liveSecs = ps.t; delaySec = ps.d; isLive = true; }
      else if (ps && ps.d != null) { delaySec = ps.d; isLive = true; }
      else if (lv.delay != null) { delaySec = lv.delay; isLive = true; }
    }
    const schedSecs = hhmmToTodaySecs(dep.time);
    if (liveSecs == null && delaySec != null && schedSecs != null)
      liveSecs = schedSecs + delaySec;

    // right-side countdown: with a live feed it follows the LIVE predicted
    // arrival, so it counts down to exactly when the bus reaches your stop; with
    // no feed it falls back to the printed schedule.
    const schedMins = dep._mins;
    const showMins = (isLive && liveSecs != null)
      ? Math.round((liveSecs * 1000 - Date.now()) / 60000)
      : schedMins;
    const minsCls = showMins < 0 ? "over" : (showMins <= 15 ? "soon" : "later");

    // v2 display: the live arrival at YOUR stop is the headline, big under the
    // route.  Yellow live time + red/green delay + green wifi when a bus is
    // broadcasting.  With no live feed the wifi is gone and the scheduled stop
    // time stands in its place.  Same numbers, same colours, only relocated.
    let bigHtml;
    if (isLive) {
      const t = liveSecs != null ? secsToHHMM(liveSecs) : dep.time;
      const dmin = delaySec != null ? Math.round(delaySec / 60) : null;
      let dtxt = "";
      if (dmin != null && dmin !== 0)
        dtxt = ' <span class="le-d">' + (dmin > 0 ? "+" + dmin : dmin) + "</span>";
      else if (dmin === 0) dtxt = ' <span class="le-ok">\u00b10</span>';
      bigHtml = '<span class="bigt live"><span class="le-t">' + t + '</span>' +
        dtxt + WIFI + '</span>';
    } else {
      bigHtml = '<span class="bigt">' + dep.time + '</span>';
    }

    const fromName = dep.from || "";
    const toName = dep.to || dep.exit || dep.headsign || "";
    const arrTxt = dep.arrive ? "→ " + dep.arrive : "";
    // destination arrival, now secondary: gray, in parentheses, after the sched time
    const arrGray = dep.arrive ? ' <span class="arrgray">(→ ' + dep.arrive + ')</span>' : "";

    const el = document.createElement("div");
    el.className = "dep" + (dep.dim ? " dimrow" : "") + (isPicked(dep) ? " picked" : "");
    el.innerHTML =
      '<span class="pills"><span class="' + routeCls + '">' + dep.route + '</span>' +
        bigHtml + '</span>' +
      '<span class="depinfo">' +
        '<span class="journey">' + fromName +
          (toName ? ' <span class="jto">→ ' + toName + '</span>' : '') + '</span>' +
        '<span class="times"><span class="schedstop">' + dep.time + '</span>' +
          arrGray + '</span>' +
      '</span>' +
      '<span class="mins ' + minsCls + '">' + showMins +
        '<span class="u"> min</span></span>' +
      '<span class="pickbtn" title="Pick this ride">' + (isPicked(dep) ? "◉" : "◯") + '</span>' +
      '<span class="chev">›</span>';
    el.querySelector(".pickbtn").addEventListener("click", (e) => {
      e.stopPropagation(); togglePick(dep);
    });
    if (dep.trip) el.addEventListener("click", () => openBusMap(dep, "full"));
    else el.querySelector(".chev").style.visibility = "hidden";
    wrap.appendChild(el);
  });
  maybeRefreshLive(liveTrips);
  syncLiveDock(upcoming);
}

function hhmmToTodaySecs(hhmm) {
  const m = /^(\d{1,2}):(\d{2})/.exec(hhmm || "");
  if (!m) return null;
  const d = new Date();
  d.setHours(+m[1], +m[2], 0, 0);
  return Math.floor(d.getTime() / 1000);
}
function secsToHHMM(secs) {
  const d = new Date(secs * 1000);
  return String(d.getHours()).padStart(2, "0") + ":" +
         String(d.getMinutes()).padStart(2, "0");
}

// Fetch live delays for the visible trips, at most every 15 s, then re-render.
function maybeRefreshLive(trips) {
  if (!trips.length || LIVE_PENDING) return;
  if (Date.now() - LIVE_AT < 15000) return;
  LIVE_PENDING = true;
  fetch("bus-live?trips=" + encodeURIComponent([...new Set(trips)].join(",")),
        { cache: "no-store" })
    .then(r => r.json())
    .then(d => {
      LIVE_PENDING = false;
      if (d && d.ok) { LIVE = d.trips || {}; LIVE_AT = Date.now(); renderDeps(); }
    })
    .catch(() => { LIVE_PENDING = false; });
}

/* ====================== Live bus map ====================== */
// The Google Maps key is NOT in this page. It is fetched from the local
// server (which reads ~/.commute/google-api.txt) and editable via the gear.
let API_KEY = "";
let API_KEYS = [];
async function fetchKeys() {
  try {
    const r = await fetch("api-keys", { cache: "no-store" });
    const d = await r.json();
    API_KEYS = (d && d.keys) ? d.keys : [];
  } catch (e) { API_KEYS = []; }
  API_KEY = API_KEYS[0] || "";
}
let _mapsPromise = null, busMap = null, busMarker = null;
let busPath = null, stopMarkers = [], boardMarker = null;
let busTimer = null, busRefresh = null, busState = null;

function loadMaps() {
  if (window.google && window.google.maps && window.google.maps.Map)
    return Promise.resolve();
  if (!API_KEY) return Promise.reject(new Error("no-key"));
  if (_mapsPromise) return _mapsPromise;
  _mapsPromise = new Promise((resolve, reject) => {
    window.__busMapsReady = () => resolve();
    const s = document.createElement("script");
    s.src = "https://maps.googleapis.com/maps/api/js?key=" + API_KEY +
            "&v=weekly&callback=__busMapsReady";
    s.async = true;
    s.onerror = () => { _mapsPromise = null; reject(new Error("Maps failed to load")); };
    document.head.appendChild(s);
  });
  return _mapsPromise;
}

function routeColor(r) {
  return r === "241" ? "#d4a017" : r === "268" ? "#1f9bd1" : "#e6edf3";
}
function xIcon(color) {
  const svg =
    "<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18'>" +
    "<line x1='4' y1='4' x2='14' y2='14' stroke='" + color + "' stroke-width='3' stroke-linecap='round'/>" +
    "<line x1='14' y1='4' x2='4' y2='14' stroke='" + color + "' stroke-width='3' stroke-linecap='round'/></svg>";
  return {
    url: "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(svg),
    scaledSize: new google.maps.Size(18, 18),
    anchor: new google.maps.Point(9, 9),
  };
}
function busXIcon() { return xIcon("#ff3b30"); }       // red cross = the bus

// Google map look, chosen in the gear panel and saved on the phone.
function mapStyleOptions() {
  const dark = [
    { elementType: "geometry", stylers: [{ color: "#1b1f27" }] },
    { elementType: "labels.text.fill", stylers: [{ color: "#8b949e" }] },
    { elementType: "labels.text.stroke", stylers: [{ color: "#0d1117" }] },
    { featureType: "road", elementType: "geometry", stylers: [{ color: "#2a2f3a" }] },
    { featureType: "water", elementType: "geometry", stylers: [{ color: "#0d1117" }] },
    { featureType: "poi", stylers: [{ visibility: "off" }] },
  ];
  const s = localStorage.getItem("commuteMapStyle") || "dark";
  if (s === "light")     return { mapTypeId: "roadmap", styles: [] };
  if (s === "satellite") return { mapTypeId: "satellite", styles: [] };
  if (s === "terrain")   return { mapTypeId: "terrain", styles: [] };
  if (s === "hybrid")    return { mapTypeId: "hybrid", styles: [] };
  return { mapTypeId: "roadmap", styles: dark };
}

// service-seconds now, accounting for after-midnight (>24h) trips
function nowServiceSecs(stops) {
  const d = new Date();
  let s = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds();
  const maxT = stops.reduce((m, x) => Math.max(m, x.t), 0);
  if (maxT > 86400 && s < 14400) s += 86400;
  return s;
}
function interp(stops, schedSecs) {
  if (schedSecs <= stops[0].t)
    return { lat: stops[0].lat, lng: stops[0].lng, before: true };
  for (let i = 0; i < stops.length - 1; i++) {
    const a = stops[i], b = stops[i + 1];
    if (schedSecs >= a.t && schedSecs <= b.t) {
      const f = b.t === a.t ? 0 : (schedSecs - a.t) / (b.t - a.t);
      return { lat: a.lat + (b.lat - a.lat) * f, lng: a.lng + (b.lng - a.lng) * f };
    }
  }
  const last = stops[stops.length - 1];
  return { lat: last.lat, lng: last.lng, after: true };
}

function tickBus() {
  if (!busState || !busMarker) return;
  const { stops, delay } = busState;
  const schedSecs = nowServiceSecs(stops) - delay;
  const p = interp(stops, schedSecs);
  busMarker.setPosition(new google.maps.LatLng(p.lat, p.lng));
  busState.pos = p;
  renderDash();
}

/* ---------- trip dashboard ---------- */
let dashPage = 4;                 // v9: Live is the page you land on
let _lvAnchored = false;          // scroll the stop table into view once per open
function dashMsg(html){ const pg = document.getElementById("bmPage"); if (pg) pg.innerHTML = '<div class="nx-sub">' + html + '</div>'; }
function escHtml(x){ return (x || "").replace(/[&<>]/g, c => ({ "&":"&amp;","<":"&lt;",">":"&gt;" }[c])); }
function bsEta(st){ return (st.t + busState.delay) - nowServiceSecs(busState.stops); }
function fmtMin(sec){ const m = Math.round(sec / 60); return m <= 0 ? "due" : m + " min"; }
function clockIn(sec){ const d = new Date(Date.now() + sec * 1000); return String(d.getHours()).padStart(2,"0") + ":" + String(d.getMinutes()).padStart(2,"0"); }
function clockAt(sec){ sec = ((sec % 86400) + 86400) % 86400; return String(Math.floor(sec/3600)).padStart(2,"0") + ":" + String(Math.floor((sec%3600)/60)).padStart(2,"0"); }
function havM(a, b){ const R=6371000, t=Math.PI/180; const dLa=(b.lat-a.lat)*t, dLn=(b.lng-a.lng)*t; const h=Math.sin(dLa/2)**2 + Math.cos(a.lat*t)*Math.cos(b.lat*t)*Math.sin(dLn/2)**2; return 2*R*Math.asin(Math.sqrt(h)); }
function fmtDist(m){ return m >= 1000 ? (m/1000).toFixed(1) + " km" : Math.round(m/10)*10 + " m"; }
function delayParen(){
  const d = busState.delay, src = busState.source;
  if (src !== "realtime") return { t:"(estimated)", c:"est" };
  if (d >= 60)  return { t:"(" + Math.round(d/60) + " min late)", c:"late" };
  if (d <= -60) return { t:"(" + Math.round(-d/60) + " min ahead)", c:"ok" };
  return { t:"(on time)", c:"ok" };
}
function nextIdx(){ const st = busState.stops; for (let i=0;i<st.length;i++){ if (bsEta(st[i]) > -20) return i; } return -1; }
function kv(k,v){ return '<div class="kv"><span>'+k+'</span><b>'+v+'</b></div>'; }

function renderDash(){
  if (!busState) return;
  const dep = busState.dep, stops = busState.stops;
  const rb = document.getElementById("bmRoute");
  if (rb){ rb.textContent = dep.route; try { rb.style.background = routeColor(dep.route); } catch(e){} }
  const dd = document.getElementById("bmDest"); if (dd) dd.textContent = "→ " + (dep.exit || dep.headsign || "");
  const sc = document.getElementById("bmSrc");
  if (sc){ const live = busState.source === "realtime"; sc.textContent = live ? "live" : "schedule"; sc.className = "bm-src " + (live ? "live" : "est"); }
  const wb = document.getElementById("bmWatch");
  if (wb){ const on = isWatching(dep); wb.textContent = on ? "Watching ✓" : "Keep on list"; wb.classList.toggle("on", on); }
  document.querySelectorAll("#bmTabs .bm-tab").forEach(t => t.classList.toggle("on", +t.dataset.pg === dashPage));
  const page = document.getElementById("bmPage"); if (!page) return;
  const ni = nextIdx();
  if (ni < 0){
    if (isWatching(dep)) setWatch(null);   // final stop reached, release the pin
    page.innerHTML = '<div class="nx-label">trip</div><div class="nx-name">finished</div>'; return;
  }
  let saved = 0; const oldList = page.querySelector(".st-list"); if (oldList) saved = oldList.scrollTop;
  const pageScroll = page.scrollTop;
  page.innerHTML = dashPage === 0 ? pageNow(ni)
                 : dashPage === 1 ? pageStops(ni)
                 : dashPage === 2 ? pageTrip(ni)
                 : dashPage === 3 ? pageStatus(ni)
                 : pageLive(ni);
  const newList = page.querySelector(".st-list"); if (newList) newList.scrollTop = saved;
  // v9: the Live page opens on the stop table, its header pinned at the top.
  // The feed statistics sit above it, one flick of the thumb away.
  if (dashPage === 4) {
    if (!_lvAnchored) { _lvAnchored = true; page.scrollTop = 0; }
    else page.scrollTop = pageScroll;
  }
}
function pageNow(ni){
  const stops = busState.stops, s = stops[ni], eta = bsEta(s), par = delayParen();
  const before = busState.pos && busState.pos.before;
  const dist = busState.pos ? fmtDist(havM(busState.pos, s)) : "";
  const prog = Math.round((ni / Math.max(stops.length - 1, 1)) * 100);
  return '<div class="nx-label">' + (before ? "departs from" : "next stop") + '</div>' +
    '<div class="nx-name">' + escHtml(s.name) + '</div>' +
    '<div class="nx-row"><span class="nx-eta">' + fmtMin(eta) + '</span>' +
      '<span class="nx-clock">at ' + clockIn(eta) + '</span>' +
      '<span class="nx-paren ' + par.c + '">' + par.t + '</span></div>' +
    '<div class="nx-sub">' + (dist ? "≈ " + dist + " away  ·  " : "") + "stop " + (ni + 1) + " of " + stops.length + '</div>' +
    '<div class="bm-prog"><i style="width:' + prog + '%"></i></div>';
}
function pageStops(ni){
  const stops = busState.stops, dep = busState.dep;
  const key = dep.exit ? dep.exit.toLowerCase().slice(0,6) : null;
  let rows = "";
  for (let i = ni; i < stops.length && i < ni + 14; i++){
    const s = stops[i], eta = bsEta(s);
    const mine = key && s.name.toLowerCase().includes(key);
    rows += '<div class="st-row' + (mine ? " mine" : "") + '">' +
      '<span class="st-eta">' + fmtMin(eta) + '</span>' +
      '<span class="st-name">' + escHtml(s.name) + (mine ? "  ◂ your stop" : "") + '</span>' +
      '<span class="st-clock">' + clockIn(eta) + '</span></div>';
  }
  return '<div class="st-list">' + rows + '</div>';
}
function pageTrip(ni){
  const stops = busState.stops, dep = busState.dep;
  const first = stops[0], last = stops[stops.length - 1];
  return kv("Route", escHtml(dep.route + " → " + (dep.exit || dep.headsign || ""))) +
    kv("Boarding", escHtml((dep.from || "—") + " → " + (dep.exit || "—"))) +
    kv("Stops left", (stops.length - ni) + " of " + stops.length) +
    kv("Started", clockAt(first.t)) +
    kv("Ends", clockAt(last.t + busState.delay)) +
    kv("Data", busState.source === "realtime" ? "live delay feed" : "schedule estimate");
}
function pageStatus(ni){
  const stops = busState.stops, dep = busState.dep, d = busState.delay, par = delayParen();
  const big = busState.source !== "realtime" ? "estimated"
            : d >= 60 ? Math.round(d/60) + " min late"
            : d <= -60 ? Math.round(-d/60) + " min ahead"
            : "on time";
  const cls = par.c === "late" ? "late" : (par.c === "ok" ? "ok" : "");
  const key = dep.exit ? dep.exit.toLowerCase().slice(0,6) : null;
  const mine = key ? stops.find(s => s.name.toLowerCase().includes(key)) : null;
  let yb = "";
  if (mine){
    const em = Math.round(bsEta(mine) / 60);
    yb = kv("Your stop", escHtml(dep.exit)) +
         kv("Scheduled", clockAt(mine.t)) +
         kv("Projected", clockAt(mine.t + d)) +
         kv("Arriving in", em >= 0 ? em + " min" : "passed");
  }
  return '<div class="stbig ' + cls + '">' + big + '</div>' +
    '<div class="nx-sub" style="margin:2px 0 9px">on this drive right now</div>' + yb;
}
function fmtDelay(sec){
  if (sec == null) return "—";
  if (Math.abs(sec) < 30) return "on time";
  const m = Math.round(Math.abs(sec) / 60);
  return (sec > 0 ? "+" : "−") + (m < 1 ? "<1" : m) + " min";
}
function pageLive(ni){
  const bs = busState, stops = bs.stops;
  const byId = {}; (bs.live || []).forEach(u => { if (u.stop_id != null) byId[u.stop_id] = u; });
  const age = bs.now ? Math.max(0, Math.round(Date.now() / 1000 - bs.now)) : null;
  const head =
    kv("Feed", bs.source === "realtime" ? "GTFS-realtime, TripUpdates" : "no live data (schedule)") +
    kv("Buses in feed", bs.rt_entities != null ? bs.rt_entities : "—") +
    kv("Updates this bus", bs.rt_updates != null ? bs.rt_updates : "0") +
    kv("Trip id", escHtml(bs.dep.trip || "—")) +
    (age != null ? kv("Fetched", age + " s ago") : "") +
    kv("Trip delay", fmtDelay(bs.delay));
  let rows = '<div class="lv-head-row"><span class="lv-seq">#</span><span class="lv-name">stop</span>' +
    '<span class="lv-sched">sched</span><span class="lv-pred">live</span><span class="lv-d">delay</span></div>';
  stops.forEach((s, i) => {
    const lv = byId[s.stop_id];
    const pred = lv ? (lv.t != null ? clockAt(lv.t - bs.midnight)
                    : (lv.d != null ? clockAt(s.t + lv.d) : "—")) : "—";
    const dcls = lv && lv.d != null ? (lv.d >= 60 ? " late" : " ok") : "";
    rows += '<div class="lv-row' + (i < ni ? " past" : "") + '"><span class="lv-seq">' + (i + 1) + '</span>' +
      '<span class="lv-name">' + escHtml(s.name) + '</span>' +
      '<span class="lv-sched">' + clockAt(s.t) + '</span>' +
      '<span class="lv-pred">' + pred + '</span>' +
      '<span class="lv-d' + dcls + '">' + (lv ? fmtDelay(lv.d) : "—") + '</span></div>';
  });
  // v10: the stop table leads, the feed statistics close the page
  return '<div class="lv-list">' + rows + '</div>' +
    '<div class="lv-stats">' + head + '</div>';
}

async function fetchRt(trip) {
  const r = await fetch("bus-rt?trip=" + encodeURIComponent(trip), { cache: "no-store" });
  return r.json();
}

/* ---------- v8: one live view, two sizes ----------
   The same bus sheet is either docked on the main screen (inline) or blown up
   to full screen with big type. The ⛶ button walks between the two, and the
   ride you collapse becomes the picked ride, so the main screen always shows
   the drive you are actually on. */
let LIVE_MODE = "off";           // off | inline | full
let _liveOpening = false;
function liveModal(){ return document.getElementById("busmodal"); }
function resizeBusMap(){
  if (!busMap || !window.google) return;
  setTimeout(() => {
    google.maps.event.trigger(busMap, "resize");
    if (busState && busState.bounds) busMap.fitBounds(busState.bounds, 40);
  }, 60);
}
function dockLive(){
  const m = liveModal();
  m.classList.remove("show"); m.classList.add("inline");
  document.getElementById("livedock").appendChild(m);
  LIVE_MODE = "inline"; resizeBusMap();
}
function expandLive(){
  const m = liveModal();
  m.classList.remove("inline"); m.classList.add("show");
  document.body.appendChild(m);
  LIVE_MODE = "full"; resizeBusMap();
}
function hideLive(){
  const m = liveModal();
  m.classList.remove("show", "inline");
  LIVE_MODE = "off";
}
// Keep the docked live view pointed at the picked ride, without rebuilding the
// map on every one-second tick.
function syncLiveDock(list){
  if (LIVE_MODE === "full" || _liveOpening) return;
  const dep = (list || []).find(x => isPicked(x) && x.trip);
  if (!dep) {
    if (LIVE_MODE === "inline") { closeBusMap(); }
    return;
  }
  if (LIVE_MODE === "inline" && busState && busState.dep &&
      busState.dep.trip === dep.trip) return;
  _liveOpening = true;
  openBusMap(dep, "inline").finally(() => { _liveOpening = false; });
}

async function openBusMap(dep, mode) {
  if (mode === "inline") dockLive(); else expandLive();
  dashPage = 4; _lvAnchored = false; dashMsg("Loading live position…");
  let data;
  try {
    await loadMaps();
    data = await fetchRt(dep.trip);
  } catch (e) {
    dashMsg((e && e.message === "no-key")
      ? "No Google Maps key set. Tap the ⚙ gear icon (top right) to add one."
      : "Map unavailable. Open the app with the commute command, not as a file.");
    return;
  }
  if (!data || !data.ok || !data.stops || !data.stops.length) {
    dashMsg("No route path for this bus yet, the schedule is still downloading.");
    return;
  }
  const stops = data.stops;
  busState = { stops, delay: data.delay || 0, source: data.source, dep,
    now: data.now, midnight: data.midnight, live: data.live || [],
    rt_entities: data.rt_entities, rt_updates: data.rt_updates };

  if (!busMap) {
    busMap = new google.maps.Map(document.getElementById("busmapCanvas"), Object.assign({
      center: { lat: stops[0].lat, lng: stops[0].lng }, zoom: 13,
      disableDefaultUI: true, zoomControl: true,
      gestureHandling: "greedy",   // one-finger drag/pan, pinch zoom, two-finger pan
      rotateControl: true, isFractionalZoomEnabled: true,
      headingInteractionEnabled: true, tiltInteractionEnabled: true,
    }, mapStyleOptions()));
  } else {
    busMap.setOptions(mapStyleOptions());
  }
  // clear previous overlays
  if (busPath) busPath.setMap(null);
  stopMarkers.forEach(m => m.setMap(null)); stopMarkers = [];
  if (boardMarker) boardMarker.setMap(null);
  if (busMarker) busMarker.setMap(null);

  const color = routeColor(dep.route);
  busPath = new google.maps.Polyline({
    path: stops.map(s => ({ lat: s.lat, lng: s.lng })),
    strokeColor: color, strokeOpacity: 0.85, strokeWeight: 4, map: busMap,
  });
  const bounds = new google.maps.LatLngBounds();
  stops.forEach(s => {
    bounds.extend({ lat: s.lat, lng: s.lng });
    stopMarkers.push(new google.maps.Marker({
      position: { lat: s.lat, lng: s.lng }, map: busMap,
      icon: { path: google.maps.SymbolPath.CIRCLE, scale: 3,
        fillColor: "#8b949e", fillOpacity: 1, strokeColor: "#0d1117", strokeWeight: 1 },
    }));
  });
  const boardStop = stops.find(s =>
    dep.from && s.name.toLowerCase().includes(dep.from.toLowerCase().slice(0, 6)));
  if (boardStop) {
    boardMarker = new google.maps.Marker({
      position: { lat: boardStop.lat, lng: boardStop.lng }, map: busMap,
      title: "Board: " + boardStop.name, icon: xIcon("#3fb950"), zIndex: 998,
    });
  }
  busMarker = new google.maps.Marker({ map: busMap, icon: busXIcon(), zIndex: 999 });
  busState.bounds = bounds;
  busMap.fitBounds(bounds, 40);

  tickBus();
  clearInterval(busTimer); busTimer = setInterval(tickBus, 1000);
  clearInterval(busRefresh);
  busRefresh = setInterval(async () => {                 // resync delay
    try {
      const d2 = await fetchRt(dep.trip);
      if (d2 && d2.ok) { busState.delay = d2.delay || 0; busState.source = d2.source;
        busState.live = d2.live || []; busState.now = d2.now; busState.midnight = d2.midnight;
        busState.rt_entities = d2.rt_entities; busState.rt_updates = d2.rt_updates; }
    } catch (e) {}
  }, 20000);
}

function closeBusMap() {
  hideLive();
  clearInterval(busTimer); busTimer = null;
  clearInterval(busRefresh); busRefresh = null;
  busState = null;
}
// ⛶ : docked → full screen, full screen → back to the main screen, and the ride
// you were watching becomes the picked one, green frame and filled radio.
function toggleLiveSize() {
  if (LIVE_MODE === "inline") { expandLive(); return; }
  if (busState && busState.dep && busState.dep.trip) {
    PICKED = { key: pickKey(busState.dep), dir: active }; savePick();
    dockLive(); renderDeps();
  } else { closeBusMap(); }
}
document.getElementById("bmClose").addEventListener("click", toggleLiveSize);
const DASH_PAGES = 5;
document.getElementById("bmTabs").addEventListener("click", (e) => {
  const b = e.target.closest(".bm-tab"); if (!b) return;
  if (+b.dataset.pg === 4 && dashPage !== 4) _lvAnchored = false;
  dashPage = +b.dataset.pg; renderDash();
});
document.getElementById("bmPage").addEventListener("click", () => {   // tap flips to the next page
  if (window._dashSwiped) { window._dashSwiped = false; return; }
  dashPage = (dashPage + 1) % DASH_PAGES; renderDash();
});
document.getElementById("bmWatch").addEventListener("click", () => {
  if (!busState) return;
  setWatch(isWatching(busState.dep) ? null : busState.dep);
  renderDash();
});
(function(){
  const dash = document.getElementById("bmDash"); if (!dash) return; let x0 = null, y0 = null;
  dash.addEventListener("touchstart", e => { x0 = e.touches[0].clientX; y0 = e.touches[0].clientY; }, { passive:true });
  dash.addEventListener("touchend", e => {
    if (x0 == null) return; const dx = e.changedTouches[0].clientX - x0, dy = e.changedTouches[0].clientY - y0; x0 = null;
    if (Math.abs(dx) < 45 || Math.abs(dx) < Math.abs(dy)) return;
    window._dashSwiped = true;
    dashPage = Math.max(0, Math.min(DASH_PAGES - 1, dashPage + (dx < 0 ? 1 : -1))); renderDash();
  }, { passive:true });
})();
document.getElementById("busmodal").addEventListener("click", (e) => {
  if (e.target.id !== "busmodal") return;
  if (LIVE_MODE === "inline") expandLive(); else toggleLiveSize();
});
// tapping the small map on the main screen blows the live view up
document.getElementById("busmapCanvas").addEventListener("click", () => {
  if (LIVE_MODE === "inline") expandLive();
});
/* ================== end live bus map ================== */

// v11: the app never waits for ZET. /schedule answers instantly, with today's
// fresh build when it exists and otherwise with the stored copy of this day
// type (Monday to Friday share one, Saturday, Sunday and holidays each have
// their own), already rewindowed to the clock. Pills and direction tabs paint
// from that copy while the real download runs in the background, and the
// screen is repainted quietly the moment the fresh build lands.
let STALE = false, _pollT = null;

async function load(silent) {
  try {
    const r = await fetch("schedule", { cache:"no-store" });
    if (!r.ok) throw new Error("no schedule");
    DATA = await r.json();
    STALE = !!DATA.stale;
    if (!DATA.directions || !DATA.directions.length) throw new Error("empty schedule");
    if (!DATA.directions.find(x => x.id === active)) active = DATA.directions[0].id;
    GTFS_FETCH_FAILED = false;
    // v12: nothing to switch by hand. renderSrcTabs() reads the health of this
    // build on every repaint and speaks GTFS or PDF accordingly.
    renderPills(); renderFilters(); renderDeps();
    const st = document.getElementById("status");
    if (!gtfsHealthy()) st.textContent = "The GTFS schedule came back empty, so the printed ZET timetables are speaking.";
    else if (STALE) st.textContent = "Buffered " + dayTypeLabel(DATA.buffer_of || DATA.daytype) + " schedule, downloading today's…";
    else st.textContent = "";
    if (STALE) startBackgroundUpdate(); else stopPolling();
  } catch(e) {
    GTFS_FETCH_FAILED = true;
    renderDeps();
    document.getElementById("status").textContent =
      "No GTFS schedule right now, the printed ZET timetables are speaking.";
  }
}

function dayTypeLabel(dt) {
  return dt === "sat" ? "Saturday" : dt === "sun" ? "Sunday"
       : dt === "holiday" ? "holiday" : "weekday";
}
function stopPolling() { if (_pollT) { clearInterval(_pollT); _pollT = null; } }

// Ask the server to build today, then watch for it and repaint in place. The
// user sees no spinner and loses no scroll position, only fresher numbers.
async function startBackgroundUpdate(force) {
  try { await fetch("update-bus?bg=1" + (force ? "&force=1" : ""), { cache:"no-store" }); }
  catch (e) {}
  if (_pollT) return;
  _pollT = setInterval(async () => {
    try {
      const r = await fetch("update-status", { cache:"no-store" });
      const st = await r.json();
      if (st.running) return;
      stopPolling();
      await load(true);
    } catch (e) { stopPolling(); }
  }, 2000);
}

document.getElementById("fsBtn").addEventListener("click", () => {
  if (!document.fullscreenElement) {
    (document.documentElement.requestFullscreen || (()=>{})).call(document.documentElement);
  } else { document.exitFullscreen(); }
});

// ---- Setup (gear): edit API keys, saved to ~/.commute/google-api.txt ----
const setupModal = document.getElementById("setupmodal");
function fmtTime(sec) {
  return sec ? new Date(sec * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : "—";
}
function renderZetStatic() {
  const el = document.getElementById("zetStatic");
  if (!DATA) { el.innerHTML = "No schedule loaded yet, the download is running."; return; }
  const n = (DATA.directions || []).reduce(
    (a, d) => a + (d.departures ? d.departures.length : 0), 0);
  const built = DATA.generated
    ? new Date(DATA.generated * 1000).toLocaleString() : (DATA.updated || "unknown");
  el.innerHTML =
    "feed version <b>" + (DATA.feed_version || "—") + "</b><br>" +
    "built " + built + "<br>" +
    n + " departures loaded<br>" +
    "<span class='zet-note'>The official ZET timetable. This is the source of " +
    "truth; the green times follow it exactly.</span>";
}
function renderZetLive(d) {
  const el = document.getElementById("zetLive");
  if (!d || !d.ok) {
    el.innerHTML = "Live feed unreachable right now.<br>" +
      "<span class='zet-note'>No problem: the schedule works without it.</span>";
    return;
  }
  el.innerHTML =
    "reachable<br><b>" + (d.trips != null ? d.trips : "?") +
    "</b> trips broadcasting now<br>checked " + fmtTime(d.checked) + "<br>" +
    "<span class='zet-note'>ZET marks this feed experimental, so the app does " +
    "too. Compare the yellow estimate against the green schedule over the days " +
    "to learn how much to trust it.</span>";
}
// v12: the Automatic / Manual pair, and a plain sentence about what the phone
// currently sees.
function syncAutoDirButtons() {
  document.querySelectorAll("#autoDirRow .mapstyle-btn").forEach(b =>
    b.classList.toggle("on", (b.dataset.auto === "1") === AUTO_DIR));
  const el = document.getElementById("autoDirBody");
  if (!el) return;
  const names = { "to-work": "the ride to Nova TV",
                  "to-home": "the ride to Glavni kolodvor",
                  "britanac": "the Britanac corridor" };
  let line;
  if (!AUTO_DIR) line = "Off. The direction stays where you put it.";
  else if (LOC_STATE === "denied") line =
    "The browser is refusing the position. Allow location for this page, " +
    "or open the app on 127.0.0.1 rather than over Wi\u2011Fi.";
  else if (LOC_STATE === "off") line = "No position available on this device.";
  else if (LOC_STATE === "waiting") line = "Asking the phone where it is\u2026";
  else if (LOC_STATE === "far") line =
    "None of the three places is nearby, so the direction stays where it is.";
  else if (LOC_STATE === "vague") line =
    "The fix is too rough to tell home from Britanski trg (\u00b1" + LOC_ACC +
    " m), so nothing is switched.";
  else line = "At <b>" + escHtml(LOC_LABEL) + "</b> (\u00b1" + LOC_ACC +
    " m), showing " + (names[active] || active) + ".";
  if (AUTO_DIR && Date.now() < AUTO_HOLD) {
    line += "<br>Your own choice is held for another " +
      Math.max(1, Math.round((AUTO_HOLD - Date.now()) / 60000)) + " min.";
  }
  el.innerHTML = line;
}
document.querySelectorAll("#autoDirRow .mapstyle-btn").forEach(b =>
  b.addEventListener("click", () => {
    AUTO_DIR = b.dataset.auto === "1";
    saveAutoDir();
    if (AUTO_DIR) { AUTO_HOLD = 0; pollLocation(); }
    syncAutoDirButtons();
    try { paintBadges(); } catch (e) {}
  }));

function syncMapStyleButtons() {
  const cur = localStorage.getItem("commuteMapStyle") || "dark";
  document.querySelectorAll("#mapStyleRow .mapstyle-btn").forEach(b =>
    b.classList.toggle("on", b.dataset.style === cur));
}
document.querySelectorAll("#mapStyleRow .mapstyle-btn").forEach(b =>
  b.addEventListener("click", () => {
    localStorage.setItem("commuteMapStyle", b.dataset.style);
    syncMapStyleButtons();
    if (busMap) busMap.setOptions(mapStyleOptions());
  }));
// Three corridors, each line with a checkmark. Unticking hides that line in
// that direction on both tabs.
const CORRIDOR_TITLES = {
  "to-work": "Nova TV  (to work)",
  "to-home": "Glavni kolodvor  (home)",
  "britanac": "Britanski trg",
};
function renderCorrLines() {
  const box = document.getElementById("corrLines");
  if (!box) return;
  box.innerHTML = "";
  Object.keys(CORRIDOR).forEach(dir => {
    const sec = document.createElement("div");
    sec.className = "corrsec";
    sec.innerHTML = "<h4>" + escHtml(CORRIDOR_TITLES[dir] || dir) + "</h4>";
    (CORRIDOR[dir].routes || []).forEach(x => {
      const on = !(EXCLUDED[dir] || []).includes(x.r);
      const desc = dir === "britanac" ? (x.origin || "")
        : (dir === "to-home" ? "from " + (x.origin || "") : "@ " + (x.myStop || ""));
      const row = document.createElement("div");
      row.className = "corrline " + (on ? "on" : "off");
      row.innerHTML = '<span class="cbx">' + (on ? "\u2713" : "") + '</span>' +
        '<span class="cln">' + x.r + '</span>' +
        '<span class="cds">' + escHtml(desc) + '</span>';
      row.addEventListener("click", () => {
        toggleExcluded(dir, x.r);
        renderCorrLines();
        try { renderFilters(); renderDeps(); } catch (e) {}
      });
      sec.appendChild(row);
    });
    box.appendChild(sec);
  });
}

function openSetup() {
  try { renderCorrLines(); } catch (e) {}
  document.getElementById("setupMsg").textContent = "";
  refreshKeyDots();
  renderPdfManager();
  fetch("version", { cache: "no-store" }).then(r => r.json())
    .then(v => { const el = document.getElementById("verLine");
      if (el) el.textContent = (v.version || "v13") + " (a) · " + (v.build || ""); })
    .catch(() => { const el = document.getElementById("verLine");
      if (el) el.textContent = "v13 (a)"; });
  renderZetStatic();
  syncAutoDirButtons();
  syncMapStyleButtons();
  document.getElementById("zetLive").textContent = "checking…";
  setupModal.classList.add("show");
  fetch("zet-status", { cache: "no-store" })
    .then(r => r.json()).then(renderZetLive)
    .catch(() => { document.getElementById("zetLive").textContent =
      "could not reach the live feed"; });
}
document.getElementById("gearBtn").addEventListener("click", openSetup);
document.getElementById("cwClose").addEventListener("click", closeColorWheel);
document.getElementById("openColorFromGear").addEventListener("click", () => {
  setupModal.classList.remove("show"); openColorWheel();
});
document.getElementById("resetColors").addEventListener("click", () => {
  CUSTOM = {}; saveCustom(); applyCustom();
  try { renderDeps(); renderFilters(); } catch (e) {}
  try { syncColorUI(); } catch (e) {}
});
document.getElementById("setupClose").addEventListener("click",
  () => setupModal.classList.remove("show"));
setupModal.addEventListener("click", (e) => {
  if (e.target.id === "setupmodal") setupModal.classList.remove("show");
});
document.getElementById("zetRebuild").addEventListener("click", async () => {
  const el = document.getElementById("zetStatic");
  el.textContent = "rebuilding from ZET…";
  try { await startBackgroundUpdate(true); await load(true); renderZetStatic(); }
  catch (e) { el.textContent = "rebuild failed — reopen and try again"; }
});
/* ---- Custom colour system: the C tab. The user paints each UI element by
   picking a hue from an 18-colour wheel, with the live page visible behind so
   every change is immediate. No more preset schemes. ---- */
// The editable interface elements map to these CSS variables.
const UI_ELEMENTS = [
  { key: "--bg",     name: "Background" },
  { key: "--card",   name: "Cards / rows" },
  { key: "--text",   name: "Main text" },
  { key: "--muted",  name: "Muted text" },
  { key: "--border", name: "Borders / lines" },
  { key: "--cyan",   name: "Primary (pills, tabs)" },
  { key: "--accent", name: "Accent (221, links)" },
  { key: "--soon",   name: "Highlight (times, soon)" },
];
// Defaults, so "reset" and unset elements have a known value.
const UI_DEFAULTS = {
  "--bg": "#0d1117", "--card": "#161b22", "--text": "#e6edf3",
  "--muted": "#8b949e", "--border": "#30363d", "--cyan": "#d4a017",
  "--accent": "#a371f7", "--soon": "#d4a017",
};
let CUSTOM = {};
try { CUSTOM = JSON.parse(localStorage.getItem("commute_custom") || "{}") || {}; }
catch (e) { CUSTOM = {}; }
function saveCustom(){ try { localStorage.setItem("commute_custom", JSON.stringify(CUSTOM)); } catch(e){} }
function applyCustom(){
  const root = document.documentElement;
  UI_ELEMENTS.forEach(el => {
    if (CUSTOM[el.key]) root.style.setProperty(el.key, CUSTOM[el.key]);
    else root.style.removeProperty(el.key);
  });
}
function currentVar(key){
  return (CUSTOM[key] ||
    getComputedStyle(document.documentElement).getPropertyValue(key).trim() ||
    UI_DEFAULTS[key] || "#000000");
}
// --- colour maths so the wheel can teach harmony ---
function hslToHex(h, s, l){
  s/=100; l/=100;
  const k=n=>(n+h/30)%12, a=s*Math.min(l,1-l);
  const f=n=>l-a*Math.max(-1,Math.min(k(n)-3,Math.min(9-k(n),1)));
  const to=x=>Math.round(255*x).toString(16).padStart(2,"0");
  return "#"+to(f(0))+to(f(8))+to(f(4));
}
const WHEEL_N = 18;                 // 18 hues around the circle
let CW_ELEMENT = UI_ELEMENTS[0].key;
let CW_LIGHT = 55;                  // lightness the wheel swatches use

function buildColorWheel(){
  const ring = document.getElementById("cwRing");
  if (!ring) return;
  ring.innerHTML = "";
  const R = 128, C = 150, SW = 34;   // ring radius, container centre, swatch
  for (let i=0;i<WHEEL_N;i++){
    const hue = Math.round(i*360/WHEEL_N);
    const hex = hslToHex(hue, 85, CW_LIGHT);
    const ang = (i/WHEEL_N)*2*Math.PI - Math.PI/2;
    const x = C + R*Math.cos(ang) - SW/2;
    const y = C + R*Math.sin(ang) - SW/2;
    const sw = document.createElement("button");
    sw.className = "cw-sw";
    sw.style.left = x+"px"; sw.style.top = y+"px";
    sw.style.background = hex;
    sw.title = hex;
    sw.addEventListener("click", () => pickColor(hex));
    ring.appendChild(sw);
  }
  // a neutral strip (white → black) for backgrounds/text
  const neutrals = ["#ffffff","#c9d1d9","#8b949e","#484f58","#21262d","#0d1117","#000000"];
  const nrow = document.getElementById("cwNeutrals");
  if (nrow){ nrow.innerHTML="";
    neutrals.forEach(hex=>{ const b=document.createElement("button");
      b.className="cw-nsw"; b.style.background=hex; b.title=hex;
      b.addEventListener("click",()=>pickColor(hex)); nrow.appendChild(b); }); }
}

let _flashTimer=null;
function flashElement(key){
  const root=document.documentElement;
  if(_flashTimer){ clearInterval(_flashTimer); _flashTimer=null; }
  const restore=CUSTOM[key]||"";
  const seq=["#ffffff","#000000","#ffffff","#000000"]; let i=0;
  root.style.setProperty(key,seq[0]);
  _flashTimer=setInterval(()=>{ i++;
    if(i>=seq.length){ clearInterval(_flashTimer); _flashTimer=null;
      if(restore) root.style.setProperty(key,restore); else root.style.removeProperty(key); return; }
    root.style.setProperty(key,seq[i]);
  },130);
}
let CW_PAGE=0; const CW_PER_PAGE=4;
function cwPages(){ return Math.max(1,Math.ceil(UI_ELEMENTS.length/CW_PER_PAGE)); }
function renderElList(){
  const box=document.getElementById("cwElList"); if(!box)return;
  const start=CW_PAGE*CW_PER_PAGE, slice=UI_ELEMENTS.slice(start,start+CW_PER_PAGE);
  box.innerHTML=slice.map(el=>'<div class="cw-elrow'+(el.key===CW_ELEMENT?' on':'')+'" data-k="'+el.key+'">'+
    '<span class="cw-radio"></span><span>'+el.name+'</span></div>').join("");
  box.querySelectorAll(".cw-elrow").forEach(row=>row.addEventListener("click",()=>{
    CW_ELEMENT=row.dataset.k; renderElList(); syncColorUI(); flashElement(CW_ELEMENT); }));
  const pg=document.getElementById("cwPage"); if(pg) pg.textContent=(CW_PAGE+1)+"/"+cwPages();
}

function pickColor(hex){
  CUSTOM[CW_ELEMENT] = hex; saveCustom(); applyCustom();
  syncColorUI();
  try { renderDeps(); renderFilters(); } catch(e){}
}
function syncColorUI(){
  const cur = document.getElementById("cwCurrent");
  if (cur){ const v=currentVar(CW_ELEMENT); cur.style.background=v;
    document.getElementById("cwHex").textContent = v.toUpperCase(); }
}
function openColorWheel(){
  const m = document.getElementById("colormodal");
  const prev=document.getElementById("cwPrev"), next=document.getElementById("cwNext");
  if (prev && !prev._wired){ prev._wired=true;
    prev.addEventListener("click",()=>{ CW_PAGE=(CW_PAGE-1+cwPages())%cwPages(); renderElList(); });
    next.addEventListener("click",()=>{ CW_PAGE=(CW_PAGE+1)%cwPages(); renderElList(); }); }
  const light = document.getElementById("cwLight");
  if (light && !light._wired){ light._wired=true;
    light.addEventListener("input",()=>{ CW_LIGHT=+light.value; buildColorWheel(); }); }
  renderElList(); buildColorWheel(); syncColorUI();
  m.classList.add("show");
}
function closeColorWheel(){ document.getElementById("colormodal").classList.remove("show"); }
applyCustom();

// ---- key status lights + file pickers (the key is never shown) ----
function setDot(id, state) {           // state: "ok" | "bad" | "unset"
  const d = document.getElementById(id); if (!d) return;
  d.classList.remove("ok", "bad");
  if (state === "ok") d.classList.add("ok");
  else if (state === "bad") d.classList.add("bad");
}
function refreshKeyDots() {
  setDot("gemDot", "unset"); setDot("mapsDot", "unset");
  fetch("key-status?which=gemini", { cache: "no-store" }).then(r => r.json())
    .then(d => setDot("gemDot", d.set ? (d.working ? "ok" : "bad") : "unset"))
    .catch(() => setDot("gemDot", "unset"));
  fetch("key-status?which=maps", { cache: "no-store" }).then(r => r.json())
    .then(d => setDot("mapsDot", d.set ? "ok" : "unset"))
    .catch(() => setDot("mapsDot", "unset"));
}
function readFileText(input) {
  return new Promise((res, rej) => {
    const f = input.files && input.files[0];
    if (!f) return rej();
    const rd = new FileReader();
    rd.onload = () => res(String(rd.result || "").trim());
    rd.onerror = rej; rd.readAsText(f);
  });
}
document.getElementById("gemFile").addEventListener("change", async (e) => {
  const msg = document.getElementById("gemMsg");
  try {
    const key = await readFileText(e.target);
    if (!key) { msg.textContent = "Empty file."; return; }
    msg.textContent = "Saving and testing…";
    await fetch("gemini-key", { method: "POST", body: key });
    e.target.value = "";
    PDFSCHED = {}; savePdfSched();       // re-read PDFs with the new key
    const st = await fetch("key-status?which=gemini", { cache: "no-store" }).then(r => r.json());
    setDot("gemDot", st.working ? "ok" : "bad");
    msg.textContent = st.working ? "Key works. Re-reading PDFs…" : "Key saved but not working.";
    if (st.working) fetchPdfSched(pdfRoutesFor(DATA ? (DATA.directions.find(x => x.id === active) || DATA.directions[0]) : null));
    renderPdfManager();
  } catch (err) { msg.textContent = "Could not read the file."; }
});
document.getElementById("gemTest").addEventListener("click", async () => {
  const msg = document.getElementById("gemMsg"); msg.textContent = "Testing…";
  try {
    const st = await fetch("key-status?which=gemini", { cache: "no-store" }).then(r => r.json());
    setDot("gemDot", st.set ? (st.working ? "ok" : "bad") : "unset");
    msg.textContent = !st.set ? "No key set." : st.working ? "Key works." : "Key not working.";
  } catch (e) { msg.textContent = "Test unavailable."; }
});
document.getElementById("mapsFile").addEventListener("change", async (e) => {
  const msg = document.getElementById("setupMsg");
  try {
    const key = await readFileText(e.target);
    if (!key) { msg.textContent = "Empty file."; return; }
    msg.textContent = "Saving…";
    const r = await fetch("api-keys", { method: "POST", body: key });
    const d = await r.json(); e.target.value = "";
    if (d && d.ok) { API_KEYS = d.keys || []; API_KEY = API_KEYS[0] || "";
      if (!(window.google && window.google.maps)) _mapsPromise = null;
      setDot("mapsDot", "ok"); msg.textContent = "Saved."; }
    else msg.textContent = "Could not save the key.";
  } catch (err) { msg.textContent = "Could not read the file."; }
});

// ---- PDF manager: list cached PDFs, delete one or all ----
function renderPdfManager() {
  const box = document.getElementById("pdfMgr"); if (!box) return;
  box.innerHTML = '<span class="zet-note">Loading…</span>';
  fetch("pdf-list", { cache: "no-store" }).then(r => r.json()).then(d => {
    const items = (d && d.items) || [];
    if (!items.length) { box.innerHTML = '<span class="zet-note">Nothing cached yet.</span>'; return; }
    box.innerHTML = "";
    items.forEach(it => {
      const kb = Math.max(1, Math.round((it.bytes || 0) / 1024));
      const row = document.createElement("div");
      row.className = "pmrow";
      row.innerHTML = '<span class="pmr">' + it.route + '</span>' +
        '<span class="pmmeta">' + kb + ' KB · ' +
        (it.parsed ? '<span class="pmok">parsed</span>' : '<span class="pmno">not parsed</span>') +
        '</span>' +
        '<button class="pmdel" data-r="' + it.route + '">Delete</button>';
      row.querySelector(".pmdel").addEventListener("click", async () => {
        await fetch("pdf-delete?route=" + encodeURIComponent(it.route), { cache: "no-store" });
        delete PDFSCHED[it.route]; savePdfSched();
        renderPdfManager(); renderDeps();
      });
      box.appendChild(row);
    });
  }).catch(() => { box.innerHTML = '<span class="zet-note">Could not read the cache.</span>'; });
}
document.getElementById("pdfClearAll").addEventListener("click", async () => {
  await fetch("pdf-delete?all=1", { cache: "no-store" });
  PDFSCHED = {}; savePdfSched();
  renderPdfManager(); renderDeps();
});

fetchKeys();
load();
setInterval(load, 60000);
// Ask once at boot so the right corridor is already on screen, then keep an
// eye on it every two minutes and whenever the app comes back to the front.
pollLocation();
</script>
</body>
</html>
CMT_BUS_HTML
done_

step "installing day.commute command"
cat > "$BIN/day.commute" << 'CMT_LAUNCH'
#!/data/data/com.termux/files/usr/bin/bash
# commute — run the Commute server in the foreground in this terminal (with a
# Commute banner) and open the app in the browser. Serves only Commute.
#   commute          start in the foreground and open the app (Ctrl+C to stop)
#   commute stop     stop a running server
#   commute status   show whether it is running and on which port
#   commute update   refresh the timetable now

APPDIR="$HOME/.commute"
SERVER="$APPDIR/commute_server.py"
STATE="$APPDIR"
PORTFILE="$STATE/port"
LOG="$STATE/server.log"
mkdir -p "$STATE"

if [ -t 1 ]; then
  A="\033[1;36m"; OK="\033[1;32m"; WARN="\033[1;33m"; KEY="\033[1;37m"; DIM="\033[0;90m"; OFF="\033[0m"
  WARM="\033[38;5;208m"
else
  A=""; OK=""; WARN=""; KEY=""; DIM=""; OFF=""; WARM=""
fi

case "$1" in
  stop)
    if pkill -f commute_server.py 2>/dev/null; then
      printf "  ${OK}commute stopped${OFF}\n"
    else
      printf "  ${DIM}not running${OFF}\n"
    fi
    rm -f "$PORTFILE"; exit 0 ;;
  status)
    if pgrep -f commute_server.py >/dev/null 2>&1; then
      printf "  ${OK}running${OFF} on ${KEY}http://127.0.0.1:%s${OFF}\n" \
        "$(cat "$PORTFILE" 2>/dev/null)"
    else
      printf "  ${DIM}stopped${OFF}\n"
    fi
    exit 0 ;;
  update)
    if [ -f "$APPDIR/update_bus.py" ]; then
      BUS_OUT="$APPDIR/bus.json" python "$APPDIR/update_bus.py"
    else
      printf "  ${WARN}update_bus.py not found in %s${OFF}\n" "$APPDIR"
    fi
    exit 0 ;;
esac

[ -f "$SERVER" ] || {
  printf "  ${WARN}commute server missing; run the installer again${OFF}\n"; exit 1; }

# Use the shared MA banner when it is present so every app looks like one
# family, otherwise print the name on its own with the Om.
if [ -f "$HOME/.ma/banner.sh" ]; then
  . "$HOME/.ma/banner.sh"
  [ -z "$MA_NESTED" ] && ma_name "DAY COMMUTE" "$MA_WATER" ""
else
  printf "\n  ${KEY}\xe0\xa5\x90 DAY COMMUTE \xe0\xa5\x90${OFF}\n\n"
fi

# Run in the foreground, right here in this terminal. Ctrl+C stops it.
# The server prints its address (local + Wi-Fi) and opens the app itself.
rm -f "$PORTFILE"
exec python "$SERVER"

CMT_LAUNCH
sed -i 's/\r$//' "$BIN/day.commute"
chmod +x "$BIN/day.commute"
done_

printf "\n  ${OK}installed${OFF}  type ${KEY}day.commute${OFF} to start it, or ${KEY}commute${OFF} for the family menu\n"
if ! command -v python >/dev/null 2>&1; then
  printf "  ${WARN}note:${OFF} ${DIM}python not found; re-run and choose y${OFF}\n"
fi
printf "  ${DIM}serves on port 8082, reachable across your Wi-Fi${OFF}\n\n"
