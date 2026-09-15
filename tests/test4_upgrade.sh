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
no_  "and there is no umbrella yet"    "[ -e '$PREFIX/bin/maha-commute' ]"

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
yes_ "the umbrella command is there"   "[ -x '$PREFIX/bin/maha-commute' ]"
yes_ "day.commute is still there"      "[ -x '$PREFIX/bin/day.commute' ]"
yes_ "night.commute is still there"    "[ -x '$PREFIX/bin/night.commute' ]"
no_  "no half written command left"    "ls '$PREFIX/bin'/*.new >/dev/null 2>&1"

# the umbrella now knows what it inherited
st=$(maha-commute status 2>&1 </dev/null || true)
inf=$(maha-commute info 2>&1 </dev/null || true)
yes_ "status finds the inherited day"  "printf '%s' \"\$st\" | grep -q 'day.commute'"
yes_ "info finds the inherited data"   "printf '%s' \"\$inf\" | grep -q '.commute,'"
yes_ "info reports the key present"    "printf '%s' \"\$inf\" | grep -q 'key      present'"
no_  "info never prints the key"       "printf '%s' \"\$inf\" | grep -qE 'AIza[A-Za-z0-9_-]{30,}'"

# ---- 6. and again, which must change nothing -----------------------
SUM1=$(sha256sum "$PREFIX/bin/maha-commute" | cut -d' ' -f1)
printf '\n' | bash "$ART" --offline --apps 12 >"$T/upgrade2.log" 2>&1
yes_ "a second upgrade exits clean"    "[ \$? = 0 ]"
yes_ "and the menu is unchanged"       "[ \"\$(sha256sum '$PREFIX/bin/maha-commute' | cut -d' ' -f1)\" = '$SUM1' ]"
yes_ "and my data is still mine"       "[ -f '$HOME/.commute/pinned.txt' ]"

# ---- 7. the app the upgrade did not include ------------------------
no_  "all.commute was not installed behind his back" "command -v all.commute >/dev/null"
yes_ "but its payload is waiting"      "[ -s '$HOME/.maha.commute/payloads/all.payload.sh' ]"

# ---- 8. v9 of the umbrella, upgraded to v10 ------------------------
# The upgrade Baba will actually do. The previous artefact is in this repo,
# so this is the real previous version and not a simulation of one.
#
# night.commute v10 changes the MEANING of what is already on the disk: the
# same night_server.py now reads a live feed, and the same night.html now
# keeps a list of starred stations. A change of meaning is the trigger that
# four-tests.md names as making this test mandatory.
PREV="$ROOT/9-maha_commute_v9.sh"
if [ ! -f "$PREV" ]; then
  printf '  the previous artefact is not here, so the v9 to v10 checks did not run\n'
else
  export HOME="$T/prev/home"; export PREFIX="$T/prev/usr"
  mkdir -p "$HOME" "$PREFIX/bin"
  export PATH="$PREFIX/bin:$OLDPATH"

  printf '\n' | bash "$PREV" --offline --apps 2 >"$T/v9.log" 2>&1
  yes_ "the v9 umbrella installed"      "[ -x '$PREFIX/bin/night.commute' ]"

  NS="$HOME/.nightcommute/night_server.py"
  NH="$HOME/.nightcommute/night.html"
  # VERIFY THE OLD VERSION IS REALLY OLD. Without this the whole section
  # can be v10 installed twice, which proves nothing whatsoever.
  yes_ "and it really is v9"            "grep -q 'APP_VERSION = \"v9\"' '$NS'"
  no_  "the old one has no live feed"   "grep -q 'gtfs-rt-protobuf' '$NS'"
  no_  "and serves no /live"            "grep -q 'r==\"/live\"' '$NS'"
  no_  "and has no star"                "grep -q 'nc_fav' '$NH'"

  # USE IT, the way a person does, and leave it running.
  mkdir -p "$HOME/.nightcommute/pdf"
  printf 'not-a-real-gemini-key-for-tests-only\n' > "$HOME/.nightcommute/gemini-api.txt"
  printf '%%PDF-1.4 pretend\n' > "$HOME/.nightcommute/pdf/33.pdf"
  printf 'my own note\n' > "$HOME/.nightcommute/my-own-note.txt"
  KEYSUM=$(sha256sum "$HOME/.nightcommute/gemini-api.txt" | cut -d' ' -f1)
  # Started exactly as the real launcher starts it: cd into the folder, then
  # a RELATIVE night_server.py. That matters more than it looks. Matching the
  # process by its absolute path finds nothing, and the test then reports a
  # server that is plainly running as stopped, which is four-tests.md's own
  # example of a test lying about the code.
  ( cd "$HOME/.nightcommute" && nohup python3 night_server.py >"$T/v9srv.log" 2>&1 &
    echo $! > "$T/v9srv.pid" )
  sleep 2
  OLDPID=$(cat "$T/v9srv.pid" 2>/dev/null)
  if [ -n "$OLDPID" ] && kill -0 "$OLDPID" 2>/dev/null; then ok
  else bad "the v9 night server did not start, so the upgrade proves nothing"; fi

  # UPGRADE, over the top, with the old one still serving.
  printf '\n' | bash "$ART" --offline --apps 2 >"$T/v10.log" 2>&1
  rc=$?
  yes_ "the upgrade exits clean"        "[ $rc = 0 ]"

  # A running process is STOPPED, not left serving the old code from memory.
  if [ -n "$OLDPID" ] && kill -0 "$OLDPID" 2>/dev/null; then
    bad "the v9 night server is still alive, serving the old code from memory"
  else ok; fi

  # The new meaning is really there.
  yes_ "night.commute is now v10"       "grep -q 'APP_VERSION = \"v10\"' '$NS'"
  yes_ "it reads the live feed"         "grep -q 'gtfs-rt-protobuf' '$NS'"
  yes_ "and serves it"                  "grep -q 'r==\"/live\"' '$NS'"
  yes_ "the star is in the page"        "grep -q 'nc_fav' '$NH'"
  yes_ "and in the picker, not only in the code" "grep -q 'sg-star' '$NH'"
  yes_ "the menu reports the new version" \
       "[ \"\$(cat '$HOME/.maha.commute/installed/night')\" = v10 ]"

  # THE PERSON'S OWN THINGS. night.commute's own installer clears its folder
  # on every install. That is its decision about its own folder and it is
  # left alone, so the umbrella reads the payload, sees the wipe coming, and
  # copies the folder aside first. The test is therefore not "it survived in
  # place", it is "it is recoverable, and the person was told where".
  B="$HOME/.maha.commute/backup/night.prev"
  yes_ "the old folder was copied aside"  "[ -d '$B' ]"
  yes_ "the gemini key is recoverable"    "[ -f '$B/gemini-api.txt' ]"
  yes_ "and it is the same key, byte for byte" \
       "[ \"\$(sha256sum '$B/gemini-api.txt' | cut -d' ' -f1)\" = '$KEYSUM' ]"
  yes_ "a note of my own is recoverable"  "[ -f '$B/my-own-note.txt' ]"
  yes_ "a cached PDF is recoverable"      "[ -f '$B/pdf/33.pdf' ]"
  yes_ "and the install said where"       "grep -q 'night.prev' '$T/v10.log'"

  # THE FAVOURITES. They live in the browser's own storage and not on the
  # filesystem, so no installer can reach them. What CAN reach them is the
  # run reset, which clears chosen things at the start of a new run, and a
  # list somebody built by hand is not a chosen thing. So the check is that
  # night's reset list stays empty.
  yes_ "night resets nothing on a new run" \
       "python3 -c \"import sys;sys.path.insert(0,'tools');import patch_payload as p;sys.exit(0 if p.RESET['night']==[] else 1)\""
  no_  "and nothing in the page clears the favourites" \
       "grep -q 'removeItem(\"nc_fav\")' '$NH'"

  # AND AGAIN, which must change nothing.
  SUM=$(sha256sum "$NS" | cut -d' ' -f1)
  printf '\n' | bash "$ART" --offline --apps 2 >"$T/v10again.log" 2>&1
  yes_ "a second v10 install leaves the server identical" \
       "[ \"\$(sha256sum '$NS' | cut -d' ' -f1)\" = '$SUM' ]"
  yes_ "and says it was already current" \
       "grep -qi 'already current' '$T/v10again.log'"

  [ -n "$OLDPID" ] && kill "$OLDPID" 2>/dev/null
  export HOME="$OLDHOME"; export PATH="$OLDPATH"
fi

printf '\n  %s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" = "0" ]
