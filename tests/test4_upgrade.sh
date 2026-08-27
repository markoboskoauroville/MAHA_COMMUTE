#!/usr/bin/env bash
# TEST 4  the upgrade, from what is already there.
#
# Closes "it works on a machine that has never run the old version".
# Nobody installs this fresh. Baba's phone already has day.commute v13
# and night.commute v9 installed the old way, each with its own data,
# its own key file, and quite possibly a server still running.
#
# So: install the old ones for real, use them, leave one running, then
# put the umbrella on top and check every one of those things.

cd "$(dirname "$0")/.."
ROOT=$(pwd)
V=$(cat VERSION)
ART="$ROOT/$V-maha_commute_v$V.sh"
UP=/mnt/user-data/uploads

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
yes_() { if eval "$2"; then ok; else bad "$1"; fi; }
no_()  { if eval "$2"; then bad "$1"; else ok; fi; }

printf '\nTEST 4  the upgrade\n\n'

TSHEBANG=/data/data/com.termux/files/usr/bin/bash
[ -e "$TSHEBANG" ] || { mkdir -p "$(dirname "$TSHEBANG")" 2>/dev/null && \
  ln -sf "$(command -v bash)" "$TSHEBANG" 2>/dev/null; }

T=$(mktemp -d)
OLDHOME="$HOME"; OLDPATH="$PATH"
cleanup() { pkill -f "$T/" 2>/dev/null; export HOME="$OLDHOME"; rm -rf "$T"; }
trap cleanup EXIT
export HOME="$T/home"; export PREFIX="$T/usr"
mkdir -p "$HOME" "$PREFIX/bin"
export PATH="$PREFIX/bin:$OLDPATH"

# ---- 1. the PREVIOUS version, for real ----------------------------
# The originals as they were handed over, key and all. Not the stripped
# copies in src/, because the phone has the originals.
printf '\n' | bash "$UP/13-install-day-commute-termux-v13.sh" --offline >"$T/old_day.log" 2>&1
printf '\n' | bash "$UP/9-night_commute_v9.sh" --offline >"$T/old_night.log" 2>&1
yes_ "the old day.commute installed"   "[ -x '$PREFIX/bin/day.commute' ]"
yes_ "the old night.commute installed" "[ -x '$PREFIX/bin/night.commute' ]"
no_  "and there is no umbrella yet"    "[ -e '$PREFIX/bin/commute' ]"

# Assert the old is really old, or the test proves nothing at all.
yes_ "the old day carries a key"       "[ -s '$HOME/.commute/google-api.txt' ]"
OLDKEYSUM=$(sha256sum "$HOME/.commute/google-api.txt" | cut -d' ' -f1)

# ---- 2. USE it. Make data, change settings ------------------------
printf 'a ride I pinned\n' > "$HOME/.commute/pinned.txt"
printf '{"widen":4,"dir":"nova"}\n' > "$HOME/.commute/settings.json"
mkdir -p "$HOME/.commute/daycache"
printf 'monday schedule\n' > "$HOME/.commute/daycache/weekday.json"
printf 'my night note\n' > "$HOME/.nightcommute/note.txt"
DATA1=$(sha256sum "$HOME/.commute/settings.json" | cut -d' ' -f1)

# ---- 3. leave it RUNNING ------------------------------------------
( day.commute >"$T/oldsrv.log" 2>&1 & )
up=0
for i in $(seq 1 40); do
  if (exec 3<>/dev/tcp/127.0.0.1/8082) 2>/dev/null; then exec 3<&-; up=1; break; fi
  sleep 0.5
done
yes_ "the old server is up before the upgrade" "[ $up = 1 ]"
OLDPID=$(pgrep -f "$HOME/.commute/commute_server.py" | head -1)
yes_ "and it has a process"            "[ -n '$OLDPID' ]"

# ---- 4. install the new version on top -----------------------------
printf '\n' | bash "$ART" --offline --apps 12 >"$T/upgrade.log" 2>&1
rc=$?
yes_ "the upgrade exits clean"         "[ $rc = 0 ]"

# ---- 5. check everything -------------------------------------------
# the data
yes_ "a pinned ride survives"          "[ -f '$HOME/.commute/pinned.txt' ]"
yes_ "settings keep their VALUE"       "[ \"\$(sha256sum '$HOME/.commute/settings.json' | cut -d' ' -f1)\" = '$DATA1' ]"
yes_ "the day cache survives"          "[ -f '$HOME/.commute/daycache/weekday.json' ]"
# Measured, not assumed. night.commute v9 clears its own folder on
# every install, so a file kept there does NOT survive in place. The
# umbrella cannot overrule an app about its own data, so it takes a
# copy first and this asserts the copy, not a wish.
no_  "night v9 clears its folder, as it always has" \
     "[ -f '$HOME/.nightcommute/note.txt' ]"
yes_ "but the note is recoverable"     "[ -f '$HOME/.maha.commute/backup/night.prev/note.txt' ]"
yes_ "and the install said where"      "grep -q 'clears its folder on install' '$T/upgrade.log'"

# the credential
yes_ "the key survives in the app"     "[ \"\$(sha256sum '$HOME/.commute/google-api.txt' | cut -d' ' -f1)\" = '$OLDKEYSUM' ]"
yes_ "and was harvested into the shared store" "[ -s '$HOME/.maha.commute/keys/google-api.txt' ]"
yes_ "the two agree" \
     "[ \"\$(tr -d ' \\n' < '$HOME/.maha.commute/keys/google-api.txt')\" = \"\$(tr -d ' \\n' < '$HOME/.commute/google-api.txt')\" ]"
yes_ "the shared key is readable by nobody else" \
     "[ \"\$(stat -c %a '$HOME/.maha.commute/keys/google-api.txt')\" = 600 ]"
yes_ "the upgrade log never printed the key" \
     "! grep -qE 'AIza[A-Za-z0-9_-]{30,}' '$T/upgrade.log'"

# the running process
sleep 1
if [ -n "$OLDPID" ] && kill -0 "$OLDPID" 2>/dev/null; then
  bad "the old server is still alive, serving the old code from memory"
else ok; fi

# every executable replaced
yes_ "the umbrella command is there"   "[ -x '$PREFIX/bin/commute' ]"
yes_ "day.commute is still there"      "[ -x '$PREFIX/bin/day.commute' ]"
yes_ "night.commute is still there"    "[ -x '$PREFIX/bin/night.commute' ]"
no_  "no half written command left"    "ls '$PREFIX/bin'/*.new >/dev/null 2>&1"

# the umbrella now knows what it inherited
st=$(commute status 2>&1 </dev/null || true)
yes_ "status finds the inherited day"  "printf '%s' \"\$st\" | grep -q 'day.commute'"
yes_ "status finds the inherited data" "printf '%s' \"\$st\" | grep -q '.commute,'"
yes_ "status reports the key present"  "printf '%s' \"\$st\" | grep -q 'key      present'"
no_  "status never prints the key"     "printf '%s' \"\$st\" | grep -qE 'AIza[A-Za-z0-9_-]{30,}'"

# ---- 6. and again, which must change nothing -----------------------
SUM1=$(sha256sum "$PREFIX/bin/commute" | cut -d' ' -f1)
printf '\n' | bash "$ART" --offline --apps 12 >"$T/upgrade2.log" 2>&1
yes_ "a second upgrade exits clean"    "[ \$? = 0 ]"
yes_ "and the menu is unchanged"       "[ \"\$(sha256sum '$PREFIX/bin/commute' | cut -d' ' -f1)\" = '$SUM1' ]"
yes_ "and my data is still mine"       "[ -f '$HOME/.commute/pinned.txt' ]"

# ---- 7. the app the upgrade did not include ------------------------
no_  "all.commute was not installed behind his back" "command -v all.commute >/dev/null"
yes_ "but its payload is waiting"      "[ -s '$HOME/.maha.commute/payloads/all.payload.sh' ]"

printf '\n  %s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" = "0" ]
