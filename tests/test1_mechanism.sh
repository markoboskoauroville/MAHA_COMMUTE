#!/usr/bin/env bash
# TEST 1  the mechanism, alone.
#
# Closes "the logic is wrong". Nothing starts, nothing installs, no
# payload is touched. It sources src/05_lib.sh, which has no side
# effects on load, and attacks the rules it claims to follow.
#
# What it cannot catch: whether any of these functions is ever called.
# That is Test 2.

cd "$(dirname "$0")/.."
. src/05_lib.sh
. src/naming.sh

pass=0; fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

eq() { # eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok; else bad "$1: wanted [$2] got [$3]"; fi
}
rc_is() { # rc_is <label> <expected rc> <actual rc>
  if [ "$2" = "$3" ]; then ok; else bad "$1: wanted rc $2 got $3"; fi
}

printf '\nTEST 1  the mechanism, alone\n\n'

# ---- the picker: the case it is FOR -------------------------------
eq "empty means all"      "day night all" "$(maha_parse_pick '')"
eq "a means all"          "day night all" "$(maha_parse_pick 'a')"
eq "A means all"          "day night all" "$(maha_parse_pick 'A')"
eq "all means all"        "day night all" "$(maha_parse_pick 'all')"
eq "one"                  "day"           "$(maha_parse_pick '1')"
eq "two"                  "night"         "$(maha_parse_pick '2')"
eq "three"                "all"           "$(maha_parse_pick '3')"
eq "two of them"          "day all"       "$(maha_parse_pick '13')"

# ---- the case it must REFUSE --------------------------------------
maha_parse_pick '4'  >/dev/null 2>&1; rc_is "4 is not an app"      2 $?
maha_parse_pick '9'  >/dev/null 2>&1; rc_is "9 is not an app"      2 $?
maha_parse_pick 'x'  >/dev/null 2>&1; rc_is "a letter is refused"  2 $?
maha_parse_pick '1x' >/dev/null 2>&1; rc_is "half valid is refused" 2 $?
maha_parse_pick '-1' >/dev/null 2>&1; rc_is "a minus is refused"   2 $?

# ---- the boundary, both sides -------------------------------------
eq "0 means none"         ""              "$(maha_parse_pick '0')"
eq "n means none"         ""              "$(maha_parse_pick 'n')"
eq "none means none"      ""              "$(maha_parse_pick 'none')"
eq "q means none"         ""              "$(maha_parse_pick 'q')"
eq "1 is the low end"     "day"           "$(maha_parse_pick '1')"
eq "3 is the high end"    "all"           "$(maha_parse_pick '3')"

# ---- two rules colliding, and order -------------------------------
# The answer is in the order the family is listed, never the order the
# fingers arrived in, so 31 and 13 are the same install.
eq "31 reads as 13"       "day all"       "$(maha_parse_pick '31')"
eq "321 sorts itself"     "day night all" "$(maha_parse_pick '321')"
eq "separators allowed"   "day all"       "$(maha_parse_pick '1,3')"
eq "spaces stripped"      "day all"       "$(maha_parse_pick ' 1 3 ')"

# ---- the same input twice -----------------------------------------
eq "11 installs day once"  "day"          "$(maha_parse_pick '11')"
eq "113 collapses"         "day all"      "$(maha_parse_pick '113')"
eq "idempotent"  "$(maha_parse_pick '13')" "$(maha_parse_pick '13')"

# ---- the filename: both ends carry the same number ----------------
for n in 1 2 9 10 99 100 103; do
  name=$(maha_artefact_name "$n")
  lead=${name%%-*}
  tailn=$(printf '%s' "$name" | sed -E 's/.*_v([0-9]+)\.sh/\1/')
  eq "v$n leads"  "$n" "$lead"
  eq "v$n closes" "$n" "$tailn"
done
eq "no zero padding" "1-maha_commute_v1.sh" "$(maha_artefact_name 1)"

# ---- installed is about the command, not the claim ----------------
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
BIN="$T/bin"; STAMPDIR="$T/stamps"; mkdir -p "$BIN" "$STAMPDIR"
MAHA_APPS="day|day.commute|.commute|v13|8082|the daytime ride
night|night.commute|.nightcommute|v9|8087|the four night trams
all|all.commute|.all.commute|v39|8084|every station around you"

is_installed day && bad "empty bin reported an install" || ok
printf 'v13\n' > "$STAMPDIR/day"
if is_installed day; then bad "a stamp with no command behind it was believed"; else ok; fi
printf '#!/bin/sh\n' > "$BIN/day.commute"
if is_installed day; then bad "a file with no execute bit counted"; else ok; fi
chmod +x "$BIN/day.commute"
if is_installed day; then ok; else bad "a real command was not seen"; fi
eq "version comes from the stamp" "v13" "$(stamped_version day)"
rm -f "$STAMPDIR/day"
eq "no stamp is a question mark" "?" "$(stamped_version day)"

eq "field reads the command" "night.commute" "$(field "$(app_row night)" 2)"
eq "field reads the port"    "8087"          "$(field "$(app_row night)" 5)"
eq "a description with spaces survives" "the four night trams" \
   "$(field "$(app_row night)" 6)"
eq "an unknown id is empty"  ""              "$(app_row nosuchapp)"

# ---- rename, never truncate ---------------------------------------
# The proof is an open file descriptor: after install_command, a reader
# that opened the old file still reads the old bytes, which is only
# true if the directory entry was swapped rather than the file rewritten.
target="$T/bin/commute"
printf 'old contents\n' > "$target"; chmod +x "$target"
exec 9< "$target"
printf 'new contents\n' | install_command "$target"
held=$(cat <&9); exec 9<&-
eq "the running shell keeps its file" "old contents" "$held"
eq "the name now holds the new one"   "new contents" "$(cat "$target")"
if [ -x "$target" ]; then ok; else bad "the replacement lost its execute bit"; fi
if [ -e "$target.new" ]; then bad "a .new file was left behind"; else ok; fi

# ---- the port test ------------------------------------------------
if port_live 1; then bad "port 1 answered, which cannot be"; else ok; fi
python3 -c "
import socket,threading,time
s=socket.socket(); s.bind(('127.0.0.1',18299)); s.listen(1)
threading.Thread(target=lambda:(time.sleep(3)),daemon=True).start()
open('$T/port.pid','w').write('up')
time.sleep(3)
" &
srv=$!
sleep 0.7
if port_live 18299; then ok; else bad "a bound port was not seen"; fi
kill $srv 2>/dev/null; wait $srv 2>/dev/null

printf '\n  %s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" = "0" ]
