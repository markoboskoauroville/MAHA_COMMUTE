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
no_  "all.commute was NOT installed"     "command -v all.commute >/dev/null"
yes_ "commute is on the PATH"            "command -v commute >/dev/null"

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
out=$(commute --help 2>&1 || true)
yes_ "commute --help speaks"             "printf '%s' \"\$out\" | grep -q 'commute \[day'"
st=$(commute status 2>&1 < /dev/null || true)
yes_ "commute status names day.commute"  "printf '%s' \"\$st\" | grep -q 'day.commute'"
yes_ "commute status names the missing one" \
     "printf '%s' \"\$st\" | grep -q 'all.commute'"
yes_ "commute status says one is absent" \
     "printf '%s' \"\$st\" | grep -q 'not installed'"

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

printf '\n  %s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" = "0" ]
