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
yes_ "but the menu still arrives"      "command -v commute >/dev/null"
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
out=$(commute status 2>&1 </dev/null || true)
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

export HOME="$OLDHOME"; export PATH="$OLDPATH"
printf '\n  %s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" = "0" ]
