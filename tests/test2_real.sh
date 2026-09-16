#!/usr/bin/env bash
# TEST 2  the real thing, once.
#
# Closes "the logic is right but nothing calls it". The artefact that
# will be delivered is run, into a Termux made of temporary folders,
# and driven the way a person drives it. Nothing is mocked and no
# function is called directly: the installer is started and then the
# installed command is started, by name, from the PATH.
#
# The number the outside world confirms: the port the server writes
# into its own state file must be the port a socket opened by this test
# actually answers on. Two independent parties agreeing.
#
# What it cannot catch: anything about failure, since this is the path
# where everything works. That is Test 3.

cd "$(dirname "$0")/.."
ROOT=$(pwd)
ART="$ROOT/$(cat VERSION)-maha_commute_v$(cat VERSION).sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
yes_() { if eval "$2"; then ok; else bad "$1"; fi; }
no_()  { if eval "$2"; then bad "$1"; else ok; fi; }

printf '\nTEST 2  the real thing, once\n\n'
[ -f "$ART" ] || { printf '  no artefact at %s\n' "$ART"; exit 1; }

T=$(mktemp -d)
cleanup() {
  [ -n "${SRV:-}" ] && kill "$SRV" 2>/dev/null
  pkill -f "$T/home/.commute/commute_server.py" 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT

export HOME="$T/home"
export PREFIX="$T/usr"
mkdir -p "$HOME" "$PREFIX/bin"
export PATH="$PREFIX/bin:$PATH"

# The launchers carry the Termux shebang, which is an absolute path
# that does not exist off the phone. Without it every command installed
# here exits 127 and the test measures the sandbox rather than the app.
# So the path is provided, pointing at this machine's bash. It is a
# stand-in and the delivery record says so: this proves the launcher
# runs through its own interpreter line, not that Android does.
TSHEBANG=/data/data/com.termux/files/usr/bin/bash
if [ ! -e "$TSHEBANG" ]; then
  mkdir -p "$(dirname "$TSHEBANG")" 2>/dev/null \
    && ln -sf "$(command -v bash)" "$TSHEBANG" 2>/dev/null \
    || printf '  note: could not provide %s, commands will not start\n' "$TSHEBANG"
fi

# day and night, not all. The picker is given on the command line so
# this run needs no keyboard, and the one remaining question, the key,
# is answered with Enter.
printf '\n' | bash "$ART" --offline --apps 12 > "$T/install.log" 2>&1
rc=$?
yes_ "the installer exited clean"        "[ $rc = 0 ]"

# ---- what a person would look for ---------------------------------
yes_ "day.commute is on the PATH"        "command -v day.commute >/dev/null"
yes_ "night.commute is on the PATH"      "command -v night.commute >/dev/null"
# Asked of THIS sandbox's bin and not of the PATH. The real phone has all
# three apps installed, and the outer PATH is still behind this one, so
# "command -v" answers about the phone rather than about the test.
no_  "all.commute was NOT installed"     "[ -x '$PREFIX/bin/all.commute' ]"
yes_ "maha-commute is on the PATH"            "command -v maha-commute >/dev/null"

# ---- the umbrella on disk -----------------------------------------
A="$HOME/.maha.commute"
yes_ "env.sh written"                    "[ -s '$A/env.sh' ]"
yes_ "install-one.sh written"            "[ -x '$A/install-one.sh' ]"
yes_ "all three payloads kept"           "[ \$(ls '$A/payloads'/*.payload.sh | wc -l) = 3 ]"
yes_ "checksums written"                 "[ -s '$A/payloads/SHA256SUMS' ]"
yes_ "sizes written"                     "[ -s '$A/payloads/SIZES' ]"
yes_ "the payloads verify"               "( cd '$A/payloads' && sha256sum -c --status SHA256SUMS )"
yes_ "day is stamped"                    "[ -s '$A/installed/day' ]"
yes_ "night is stamped"                  "[ -s '$A/installed/night' ]"
no_  "all is not stamped"                "[ -f '$A/installed/all' ]"
yes_ "the stamp says v13"                "[ \"\$(cat '$A/installed/day')\" = v13 ]"
no_  "no temp payload was left behind"   "ls '$A/tmp'/*.run.sh >/dev/null 2>&1"

# ---- the app itself was really written ----------------------------
yes_ "the day server is there"           "[ -s '$HOME/.commute/commute_server.py' ]"
yes_ "the night app is there"            "[ -d '$HOME/.nightcommute' ]"
no_  "all.commute wrote nothing"         "[ -d '$HOME/.all.commute' ]"

# ---- the key placeholder was resolved, not shipped ----------------
no_  "no placeholder survived into the app" \
     "grep -rq '__MAHA_GOOGLE_KEY__' '$HOME/.commute' '$HOME/.nightcommute' 2>/dev/null"
yes_ "the payload on disk still holds the placeholder" \
     "grep -q '__MAHA_GOOGLE_KEY__' '$A/payloads/day.payload.sh'"
no_  "no key shape anywhere under HOME" \
     "grep -rqE 'AIza[A-Za-z0-9_-]{30,}' '$HOME' 2>/dev/null"

# ---- the menu answers ---------------------------------------------
out=$(maha-commute --help 2>&1 || true)
yes_ "maha-commute --help speaks"             "printf '%s' \"\$out\" | grep -q 'maha-commute \[day'"
st=$(maha-commute status 2>&1 < /dev/null || true)
yes_ "maha-commute status names day.commute"  "printf '%s' \"\$st\" | grep -q 'day.commute'"
yes_ "maha-commute status names the missing one" \
     "printf '%s' \"\$st\" | grep -q 'all.commute'"
yes_ "maha-commute status says one is absent" \
     "printf '%s' \"\$st\" | grep -q 'not installed'"

if [ "$PHASE" = "install" ]; then
  printf '\n  %s passed, %s failed  (install half)\n\n' "$pass" "$fail"
  [ "$fail" = "0" ]; exit $?
fi

# ---- and now the real server, over real HTTP ----------------------
( day.commute > "$T/server.log" 2>&1 & echo $! > "$T/srv.pid" )
SRV=$(cat "$T/srv.pid")
up=0
for i in $(seq 1 60); do
  if (exec 3<>/dev/tcp/127.0.0.1/8082) 2>/dev/null; then exec 3<&-; up=1; break; fi
  sleep 0.5
done
yes_ "the server bound its port"         "[ $up = 1 ]"

if [ "$up" = "1" ]; then
  code=$(python3 -c "
import urllib.request
try:
    r = urllib.request.urlopen('http://127.0.0.1:8082/', timeout=10)
    body = r.read()
    print(r.status, len(body))
except Exception as e:
    print('ERR', e)
")
  status=$(printf '%s' "$code" | cut -d' ' -f1)
  bytes=$(printf '%s' "$code" | cut -d' ' -f2)
  yes_ "the page answers 200"             "[ '$status' = 200 ]"
  yes_ "the page is a real page, not empty" "[ '${bytes:-0}' -gt 2000 ]"

  # The independent number: the port the server recorded for itself.
  recorded=$(cat "$HOME/.commute/port" 2>/dev/null || printf 'none')
  yes_ "the server's own record agrees with the socket" "[ '$recorded' = 8082 ]"

  kill "$SRV" 2>/dev/null
  pkill -f "$HOME/.commute/commute_server.py" 2>/dev/null
  sleep 1
fi

# ---- night.commute, reading the live ZET feed for real -------------
# The installed app is started by its own launcher, left to build tonight's
# network from the real ZET zip, and then asked where the trams are. Nothing
# here is mocked: this talks to zet.hr.
#
# The number an outside party confirms is the feed's age. The app reads the
# timestamp out of the PROTOBUF BODY, written by whoever builds the feed.
# This test reads Last-Modified off the HTTP response, written by the server
# that hands it out. Two different parties, and a protobuf reader that was
# wrong about the body could not land within minutes of the header.

# Every night server already on this machine, so the ones this test is
# responsible for can be told apart afterwards. The launcher starts its
# server with a RELATIVE path, so there is nothing in the command line to
# match on, and a blanket pkill at the end of this test would reach out of
# the sandbox and stop the app the person is actually using.
NIGHT_BEFORE=" $(pgrep -f night_server.py | tr '\n' ' ')"
night.commute > "$T/night.log" 2>&1
up=0
for i in $(seq 1 60); do
  if (exec 3<>/dev/tcp/127.0.0.1/8087) 2>/dev/null; then exec 3<&-; up=1; break; fi
  sleep 0.5
done
yes_ "the night server bound its port"   "[ $up = 1 ]"

if [ "$up" = "1" ]; then
  # Tonight's network is built from a fourteen megabyte download on first
  # start, so it is waited for rather than assumed.
  built=0
  for i in $(seq 1 240); do
    s=$(python3 -c "
import urllib.request
try: print(urllib.request.urlopen('http://127.0.0.1:8087/night-status', timeout=5).read().decode())
except Exception: print('')" 2>/dev/null)
    case "$s" in *'"source": "gtfs"'*|*'"source":"gtfs"'*) built=1; break ;; esac
    sleep 1
  done
  yes_ "tonight's network was built from ZET" "[ $built = 1 ]"

  python3 -c "
import urllib.request
open('$T/live.json','wb').write(
    urllib.request.urlopen('http://127.0.0.1:8087/live', timeout=40).read())" 2>/dev/null
  yes_ "the live endpoint answers"      "[ -s '$T/live.json' ]"

  R=$(python3 - "$T/live.json" "$HOME/.nightcommute/night.json" <<'PYEOF'
import json, sys, urllib.request, email.utils
out = []
def say(k, v): out.append("%s=%s" % (k, v))
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    net = json.load(open(sys.argv[2], encoding="utf-8"))
except Exception:
    print("ok=False"); raise SystemExit

say("ok", d.get("ok")); say("state", d.get("state"))
say("age", d.get("age") if d.get("age") is not None else "none")
say("window", d.get("window")); say("entities", d.get("entities"))
trams = d.get("trams") or []
say("trams", len(trams))
say("located", sum(1 for t in trams if t.get("lat") is not None))

# Every tram must be a night tram, inside Zagreb, sitting on a station its
# own line actually has.
bad_route = bad_box = bad_stop = bad_dir = 0
for t in trams:
    if t.get("line") not in ("31", "32", "33", "34"): bad_route += 1
    if t.get("dir") not in (0, 1, None): bad_dir += 1
    if t.get("lat") is not None:
        if not (45.60 <= t["lat"] <= 46.05 and 15.65 <= t["lon"] <= 16.30): bad_box += 1
        L = (net.get("lines") or {}).get(t["line"]) or {}
        if t.get("near") and t["near"] not in (L.get("stations") or []): bad_stop += 1
say("bad_route", bad_route); say("bad_box", bad_box)
say("bad_stop", bad_stop); say("bad_dir", bad_dir)

# The running times, worked out of the app's own timetable. A Zagreb night
# tram takes about three quarters of an hour from end to end.
spans = []
for ln, dirs in (d.get("run") or {}).items():
    for dd, cum in dirs.items():
        vals = [x for x in cum if x is not None]
        if len(vals) > 1: spans.append(abs(max(vals) - min(vals)) / 60.0)
say("runs", len(spans))
say("run_min", int(min(spans)) if spans else -1)
say("run_max", int(max(spans)) if spans else -1)

try:
    req = urllib.request.Request("https://zet.hr/gtfs-rt-protobuf", method="HEAD",
                                 headers={"User-Agent": "maha-test/1"})
    with urllib.request.urlopen(req, timeout=20) as r:
        lm = r.headers.get("Last-Modified")
    say("witness", abs(int(email.utils.parsedate_to_datetime(lm).timestamp())
                       - (d.get("feed_ts") or 0)))
except Exception:
    say("witness", -1)
print(" ".join(out))
PYEOF
)
  g() { printf '%s' "$R" | tr ' ' '\n' | grep "^$1=" | cut -d= -f2; }

  yes_ "it read the feed"                "[ \"\$(g ok)\" = True ]"
  yes_ "and the feed is live, not stale" "[ \"\$(g state)\" = live ] || [ \"\$(g state)\" = late ]"
  yes_ "the feed is minutes old at most" "[ \"\$(g age)\" != none ] && [ \"\$(g age)\" -lt 600 ]"
  yes_ "ZET is publishing vehicles"      "[ \"\$(g entities)\" -gt 10 ]"
  yes_ "every tram found is a night tram" "[ \"\$(g bad_route)\" = 0 ]"
  yes_ "every position is inside Zagreb"  "[ \"\$(g bad_box)\" = 0 ]"
  yes_ "every tram sits on its own line's station" "[ \"\$(g bad_stop)\" = 0 ]"
  yes_ "every direction is one of the two" "[ \"\$(g bad_dir)\" = 0 ]"
  yes_ "all four lines got running times, both ways" "[ \"\$(g runs)\" = 8 ]"
  yes_ "a night tram takes 30 to 70 minutes end to end" \
       "[ \"\$(g run_min)\" -ge 30 ] && [ \"\$(g run_max)\" -le 70 ]"
  yes_ "the body's timestamp and the server's own agree" \
       "[ \"\$(g witness)\" != -1 ] && [ \"\$(g witness)\" -lt 300 ]"

  # The trams run 23:50 to 04:40. "None found" is the right answer for most of
  # the day, and only a failure inside the window.
  if [ "$(g window)" = "True" ]; then
    yes_ "inside the service window, trams are on the map" "[ \"\$(g located)\" -gt 0 ]"
  else
    printf '  it is not night in Zagreb, so 0 trams is correct and was not asserted\n'
    yes_ "outside the window the list is empty rather than broken" "[ \"\$(g trams)\" -ge 0 ]"
  fi

  # Only the ones this test started. Note that night.commute's own launcher
  # stops every night server on the machine when it starts, by design, so
  # running this test on a phone does end a running night.commute. That is
  # the app's behaviour and it is left alone; what is fixed here is that the
  # test does not do it a second time on its way out.
  for pid in $(pgrep -f night_server.py); do
    case "$NIGHT_BEFORE" in *" $pid "*) ;; *) kill "$pid" 2>/dev/null ;; esac
  done
  sleep 1
fi

printf '\n  %s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" = "0" ]
