#!/usr/bin/env bash
# TEST 3  the ugly cases.
#
# Closes "it works when the world behaves". Empty, enormous, malformed,
# hostile, twice, out of order, absent, and never answers.
#
# Two of these were written because the first version of this repo got
# them wrong: a pasted key carrying a vertical bar broke the sed that
# injects it, and a running server went on serving the old code out of
# memory after its files had been replaced.

cd "$(dirname "$0")/.."
ROOT=$(pwd)
V=$(cat VERSION)
ART="$ROOT/$V-maha_commute_v$V.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
yes_() { if eval "$2"; then ok; else bad "$1"; fi; }
no_()  { if eval "$2"; then bad "$1"; else ok; fi; }

printf '\nTEST 3  the ugly cases\n\n'

TSHEBANG=/data/data/com.termux/files/usr/bin/bash
[ -e "$TSHEBANG" ] || { mkdir -p "$(dirname "$TSHEBANG")" 2>/dev/null && \
  ln -sf "$(command -v bash)" "$TSHEBANG" 2>/dev/null; }

T=$(mktemp -d)
cleanup() { pkill -f "$T/" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
OLDHOME="$HOME"

fresh() { # fresh <name>  -> a clean phone in $T/<name>
  export HOME="$T/$1/home"; export PREFIX="$T/$1/usr"
  mkdir -p "$HOME" "$PREFIX/bin"
  export PATH="$PREFIX/bin:$OLDPATH"
}
OLDPATH="$PATH"

# ---- ABSENT: not a phone at all -----------------------------------
# The one place where refusing is the correct behaviour, and it has to
# refuse before it writes anything, not halfway through.
( unset PREFIX; export HOME="$T/nophone"; mkdir -p "$HOME"
  printf '\n' | bash "$ART" --offline --apps 1 >"$T/nophone.log" 2>&1 )
rc=$?
yes_ "off a phone it refuses"          "[ $rc = 1 ]"
yes_ "and says why"                    "grep -q 'for Termux on Android' '$T/nophone.log'"
no_  "and writes nothing"              "[ -d '$T/nophone/.maha.commute' ]"

# ---- EMPTY: no apps chosen ----------------------------------------
fresh empty
printf '\n' | bash "$ART" --offline --apps n >"$T/empty.log" 2>&1
yes_ "n installs no apps"              "! command -v day.commute >/dev/null"
yes_ "but the menu still arrives"      "command -v maha-commute >/dev/null"
yes_ "and all three payloads are kept" "[ \$(ls '$HOME/.maha.commute/payloads'/*.payload.sh | wc -l) = 3 ]"
# and the app can then be added from the menu with no download at all
bash "$HOME/.maha.commute/install-one.sh" day --offline >"$T/add.log" 2>&1
yes_ "an app added later works"        "command -v day.commute >/dev/null"
yes_ "and is stamped"                  "[ -s '$HOME/.maha.commute/installed/day' ]"

# ---- HOSTILE: a key full of characters that mean something --------
fresh hostile
mkdir -p "$HOME/.maha.commute/keys"
printf '%s\n' 'AIza|&\;`$(touch '"$T"'/PWNED)x-_9' > "$HOME/.maha.commute/keys/google-api.txt"
printf '\n' | bash "$ART" --offline --apps 1 >"$T/hostile.log" 2>&1
yes_ "a hostile key does not stop the install" "command -v day.commute >/dev/null"
no_  "and nothing was executed"                "[ -e '$T/PWNED' ]"
no_  "and no placeholder survived"             "grep -rq '__MAHA_GOOGLE_KEY__' '$HOME/.commute' 2>/dev/null"
yes_ "the stored key was cleaned to its shape" \
     "grep -qE '^[A-Za-z0-9_-]+\$' '$HOME/.commute/google-api.txt'"

# ---- EMPTY: no key anywhere ---------------------------------------
fresh nokey
printf '\n' | bash "$ART" --offline --apps 1 >"$T/nokey.log" 2>&1
yes_ "with no key it still installs"   "command -v day.commute >/dev/null"
yes_ "and says the key is optional"    "grep -q 'work without one' '$T/nokey.log'"
yes_ "and asked nothing to do it"      "! grep -q 'paste one now' '$T/nokey.log'"

# ---- TWICE: the same install, twice in a row ----------------------
fresh twice
printf '\n' | bash "$ART" --offline --apps 1 >"$T/twice1.log" 2>&1
printf 'marker\n' > "$HOME/.commute/my-own-file.txt"
sum1=$(sha256sum "$PREFIX/bin/day.commute" | cut -d' ' -f1)
printf '\n' | bash "$ART" --offline --apps 1 >"$T/twice2.log" 2>&1
rc=$?
sum2=$(sha256sum "$PREFIX/bin/day.commute" | cut -d' ' -f1)
yes_ "the second run exits clean"      "[ $rc = 0 ]"
yes_ "and changes nothing in the command" "[ '$sum1' = '$sum2' ]"
yes_ "and leaves a file of mine alone"    "[ -f '$HOME/.commute/my-own-file.txt' ]"
no_  "and leaves no temp behind"          "ls '$HOME/.maha.commute/tmp'/*.run.sh >/dev/null 2>&1"
no_  "and no half written .new files"     "ls '$HOME/.maha.commute'/*.new '$PREFIX/bin'/*.new >/dev/null 2>&1"

# ---- OUT OF ORDER: the menu with no umbrella under it -------------
fresh order
printf '\n' | bash "$ART" --offline --apps n >/dev/null 2>&1
rm -f "$HOME/.maha.commute/env.sh"
out=$(maha-commute status 2>&1 </dev/null || true)
yes_ "a menu with no env says so plainly" "printf '%s' \"\$out\" | grep -q 'env.sh is missing'"
no_  "and does not pretend to work"       "printf '%s' \"\$out\" | grep -q 'day.commute'"

# ---- ABSENT: the payload is gone ----------------------------------
fresh gone
printf '\n' | bash "$ART" --offline --apps n >/dev/null 2>&1
rm -f "$HOME/.maha.commute/payloads/night.payload.sh"
out=$(bash "$HOME/.maha.commute/install-one.sh" night --offline 2>&1 || true)
yes_ "a missing payload is named"      "printf '%s' \"\$out\" | grep -q 'not on this phone'"
no_  "and nothing was installed"       "command -v night.commute >/dev/null"

# ---- MALFORMED: a payload that lost bytes -------------------------
fresh cut
printf '\n' | bash "$ART" --offline --apps n >/dev/null 2>&1
P="$HOME/.maha.commute/payloads/day.payload.sh"
head -c 40000 "$P" > "$P.tmp" && mv "$P.tmp" "$P"
out=$(bash "$HOME/.maha.commute/install-one.sh" day --offline 2>&1 || true)
yes_ "a damaged payload is refused"    "printf '%s' \"\$out\" | grep -q 'does not match its checksum'"
yes_ "and it says nothing was changed" "printf '%s' \"\$out\" | grep -q 'nothing was changed'"
no_  "and it did not install"          "command -v day.commute >/dev/null"

# ---- MALFORMED: the artefact itself, and the two checks apart -----
cp "$ART" "$T/whole.sh"
bash tools/verify_installer.sh "$T/whole.sh" >/dev/null 2>&1
yes_ "a whole file verifies"           "[ \$? = 0 ]"

# cut in the middle of a heredoc, which bash -n warns about and then
# exits zero on. Only the no-output check sees this one.
head -c 200000 "$ART" > "$T/half.sh"
out=$(bash tools/verify_installer.sh "$T/half.sh" 2>&1 || true)
yes_ "a truncated file fails"          "printf '%s' \"\$out\" | grep -q 'FAIL'"
# Measured, not assumed. This artefact's heredocs sit inside a function
# and a case, so a cut through one of them also leaves those unclosed
# and bash -n exits 2. The hole the no-output rule exists for is the
# one where nothing else is unbalanced, so it is built here on purpose:
# a heredoc at the top level, cut. bash -n warns and exits ZERO on it,
# and the exit status alone would wave it through.
printf 'cat <<XEOF\nsome payload\n' > "$T/hole.sh"
bash -n "$T/hole.sh" >/dev/null 2>&1
yes_ "the exit status alone would pass a cut heredoc" "[ \$? = 0 ]"
yes_ "and its output is not empty, which is the check" \
     "[ -n \"\$(bash -n '$T/hole.sh' 2>&1)\" ]"

# the same truncation wearing a sentinel, to prove the parse check is
# doing its own work rather than riding on the sentinel check
cp "$T/half.sh" "$T/half_wearing_sentinel.sh"
printf '\n# MAHA_COMMUTE_SENTINEL v%s faked\n' "$V" >> "$T/half_wearing_sentinel.sh"
out=$(bash tools/verify_installer.sh "$T/half_wearing_sentinel.sh" 2>&1 || true)
yes_ "a truncation wearing a sentinel is still caught" \
     "printf '%s' \"\$out\" | grep -q 'FAIL  parse'"
yes_ "and its sentinel check passes, so the two are separate" \
     "printf '%s' \"\$out\" | grep -q 'ok    sentinel'"

# a whole file with its last line removed: only the sentinel sees this
head -n -1 "$ART" > "$T/nosentinel.sh"
out=$(bash tools/verify_installer.sh "$T/nosentinel.sh" 2>&1 || true)
yes_ "a missing last line is caught"   "printf '%s' \"\$out\" | grep -q 'FAIL  sentinel'"
yes_ "and its parse check passes, so the two are separate" \
     "printf '%s' \"\$out\" | grep -q 'ok    parse'"

# ---- ENORMOUS and MALFORMED input to the picker -------------------
fresh big
long=$(python3 -c "print('1'*20000)")
printf '\n' | bash "$ART" --offline --apps "$long" >"$T/big.log" 2>&1
yes_ "twenty thousand ones is still just day" "command -v day.commute >/dev/null"
no_  "and nothing else came with it"          "command -v all.commute >/dev/null"
out=$(printf '\n' | bash "$ART" --offline --apps 'nonsense' 2>&1 || true)
yes_ "nonsense is refused with a reason" "printf '%s' \"\$out\" | grep -q 'not something I can read'"

# ---- NEVER ANSWERS: a socket that accepts and then goes quiet -----
python3 -c "
import socket
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(('127.0.0.1',18477)); s.listen(5)
import time; time.sleep(20)
" & QUIET=$!
sleep 0.7
start=$(date +%s)
( . src/05_lib.sh; port_live 18477 ) >/dev/null 2>&1
took=$(( $(date +%s) - start ))
yes_ "a silent socket does not hang the check" "[ $took -le 3 ]"
kill $QUIET 2>/dev/null

# ---- the live feed, when the feed misbehaves ----------------------
# Every one of these is a real way a transit feed goes wrong, and most of
# them arrive at the app looking exactly like success. The app's own reader
# is pointed at a local server that tells each lie in turn.
ugly_out=$(python3 - <<'PYEOF'
import http.server, json, os, socket, socketserver, struct, sys
import tempfile, threading, time, urllib.request, datetime

NIGHT_ROUTES = ("31", "32", "33", "34")
TMP = tempfile.mkdtemp()
NIGHT_JSON = os.path.join(TMP, "night.json")
COORDS_JSON = os.path.join(TMP, "coords.json")
SCHED_JSON = os.path.join(TMP, "night_sched.json")
def _log(m): pass

SRC = open("src/payloads/night-v10/live.py", encoding="utf-8").read()
ok = []
def check(label, cond): ok.append((label, bool(cond)))

def fresh():
    """A new copy of the module, so one case's cache cannot feed the next."""
    g = {"threading": threading, "time": time, "json": json, "os": os,
         "urllib": urllib, "datetime": datetime, "NIGHT_ROUTES": NIGHT_ROUTES,
         "NIGHT_JSON": NIGHT_JSON, "COORDS_JSON": COORDS_JSON,
         "SCHED_JSON": SCHED_JSON, "_log": _log, "__name__": "live"}
    exec(compile(SRC, "live.py", "exec"), g)
    return g

NAMES = ["A", "B", "C"]
json.dump({"lines": {"33": {"termA": "A", "termB": "C", "stations": NAMES,
           "stopmap": {n: [n + "_0", n + "_1"] for n in NAMES}}}},
          open(NIGHT_JSON, "w"))
json.dump({n: [45.80, 15.90 + i * 0.01] for i, n in enumerate(NAMES)},
          open(COORDS_JSON, "w"))
json.dump({"33": {"0": [{"A_0": 0, "B_0": 120, "C_0": 240}],
                  "1": [{"A_1": 240, "B_1": 120, "C_1": 0}]}}, open(SCHED_JSON, "w"))

def vi(n):
    o = b""
    while True:
        b = n & 0x7F; n >>= 7
        o += bytes([b | 0x80]) if n else bytes([b])
        if not n: return o
ld  = lambda f, p: vi(f << 3 | 2) + vi(len(p)) + p
vf  = lambda f, v: vi(f << 3 | 0) + vi(v)
f32 = lambda f, v: vi(f << 3 | 5) + struct.pack("<f", v)

def build(ts, n=1, route=b"33"):
    body = ld(1, ld(1, b"2.0") + (vf(3, ts) if ts is not None else b""))
    for i in range(n):
        desc = ld(1, b"0_23_3301_" + route + b"_" + str(i).encode()) + ld(5, route)
        body += ld(2, ld(1, b"e%d" % i)
                   + ld(4, ld(1, desc) + ld(2, f32(1, 45.80) + f32(2, 15.91))))
    return body

LIE = {"body": b"", "ctype": "application/x-protobuf", "quiet": False}
class Liar(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if LIE["quiet"]:
            time.sleep(40)          # accepts the connection, then says nothing
            return
        self.send_response(200)
        self.send_header("Content-Type", LIE["ctype"])
        self.send_header("Content-Length", str(len(LIE["body"])))
        self.end_headers()
        self.wfile.write(LIE["body"])
class Srv(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True; allow_reuse_address = True
srv = Srv(("127.0.0.1", 0), Liar)
URL = "http://127.0.0.1:%d/feed" % srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()

def payload(url=URL, timeout=None):
    g = fresh()
    g["GTFS_RT_URL"] = url
    if timeout: g["RT_TIMEOUT"] = timeout
    return g["live_payload"]()

NOW = int(time.time())

# ABSENT: nothing is listening at all.
s = socket.socket(); s.bind(("127.0.0.1", 0)); dead = s.getsockname()[1]; s.close()
p = payload("http://127.0.0.1:%d/feed" % dead)
check("a feed that is not there is reported, not raised", p["ok"] is False)
check("and it is named unreachable", p["state"] == "unreachable")
check("and no tram is invented from it", p["trams"] == [])

# HOSTILE: a captive portal answers 200 with a web page.
LIE["body"] = b"<html><head><title>Sign in</title></head><body>wifi</body></html>"
LIE["ctype"] = "text/html"
check("a captive portal is not a feed", payload()["ok"] is False)
LIE["ctype"] = "application/x-protobuf"

# EMPTY, and nearly empty.
LIE["body"] = b""
check("an empty answer is refused", payload()["ok"] is False)
LIE["body"] = b"\x00" * 12
check("a page of zeroes says neither the time nor what is moving, and is refused",
      payload()["ok"] is False)

# SMALL, BUT TRUE. At 04:30 there may be two trams left in the whole city,
# and at about a hundred bytes a vehicle that is a very small feed. It is
# still a feed, and refusing it would break the app at exactly the hour it
# exists for.
LIE["body"] = build(NOW, n=2)
p = payload()
check("a feed of two trams at half past four is accepted", p["ok"] is True)
check("and both of them are on it", len(p["trams"]) == 2)
check("even though it is under two hundred bytes", len(LIE["body"]) < 200)

# MALFORMED: a real feed cut off in the middle of a field.
whole = build(NOW, n=3)
LIE["body"] = whole[:len(whole) - 4]
p = payload()
check("a feed truncated mid field is refused", p["ok"] is False)
check("and none of it is half drawn", p["trams"] == [])

# ENORMOUS.
LIE["body"] = build(NOW, n=600)
p = payload()
check("six hundred vehicles parse", p["ok"] is True)
check("and all of them are placed", len(p["trams"]) == 600)

# The same feed, five different clocks.
LIE["body"] = build(NOW - 2400)
p = payload()
check("a feed forty minutes old is stale", p["state"] == "stale")
check("and its age travels with the answer", p["age"] >= 2400)
LIE["body"] = build(NOW - 300)
check("five minutes old is late, not stale", payload()["state"] == "late")
LIE["body"] = build(NOW - 30)
check("thirty seconds old is live", payload()["state"] == "live")
LIE["body"] = build(NOW + 1200)
check("a feed from the future is not called fresh", payload()["state"] == "ahead")
LIE["body"] = build(None)
check("a feed with no timestamp says undated", payload()["state"] == "undated")

# The city asleep, and the city awake but not at night.
LIE["body"] = build(NOW, n=0)
p = payload()
check("an empty but valid feed is not an error", p["ok"] is True)
check("and holds no trams", p["trams"] == [])
LIE["body"] = build(NOW, n=5, route=b"7")
p = payload()
check("a feed of daytime trams yields no night trams", p["trams"] == [])
check("but it is still a working feed", p["ok"] is True)

# ABSENT: the app's own network has not been built yet.
LIE["body"] = build(NOW, n=2)
os.rename(NIGHT_JSON, NIGHT_JSON + ".away")
p = payload()
check("with no network built, it still answers", p["ok"] is True)
check("and says why it has nothing", "reason" in p)
check("rather than raising", p["trams"] == [])
os.rename(NIGHT_JSON + ".away", NIGHT_JSON)

# MALFORMED: the app's own data is corrupt.
good = open(NIGHT_JSON).read()
open(NIGHT_JSON, "w").write("{not json at all")
p = payload()
check("a corrupt night.json does not take the endpoint down", p["ok"] is True)
check("and is reported", "reason" in p)
open(NIGHT_JSON, "w").write(good)

# TWICE, AND AT THE SAME MOMENT.
LIE["body"] = build(NOW, n=2)
g = fresh()
g["GTFS_RT_URL"] = URL
hits = {"n": 0}
_open = urllib.request.urlopen
def counting(*a, **k):
    hits["n"] += 1
    return _open(*a, **k)
g["urllib"] = type("U", (), {"request": type("R", (), {
    "Request": staticmethod(urllib.request.Request),
    "urlopen": staticmethod(counting)})})
g["fetch_rt"](); g["fetch_rt"](); g["fetch_rt"]()
check("three fetches inside the cache window are one download", hits["n"] == 1)

errs = []
def hammer():
    try: g["live_payload"]()
    except Exception as e: errs.append(repr(e))
ths = [threading.Thread(target=hammer) for _ in range(8)]
[t.start() for t in ths]; [t.join() for t in ths]
check("eight callers at once and none of them raised", errs == [])

# NEVER ANSWERS. A socket that accepts and then says nothing has no error for
# a catch block to catch, and without a deadline this waits for ever.
LIE["quiet"] = True
t0 = time.time()
p = payload(timeout=3)
took = time.time() - t0
LIE["quiet"] = False
check("a feed that never answers is given up on", p["ok"] is False)
check("and it is given up on quickly", took < 25)

for label, good in ok:
    print(("PASS" if good else "FAIL") + " " + label)
PYEOF
)
while IFS= read -r l; do
  case "$l" in
    PASS*) ok ;;
    FAIL*) bad "${l#FAIL }" ;;
  esac
done <<< "$ugly_out"
case "$ugly_out" in
  *PASS*) ;;
  *) bad "the live feed ugly cases did not run at all" ;;
esac

export HOME="$OLDHOME"; export PATH="$OLDPATH"
printf '\n  %s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" = "0" ]
