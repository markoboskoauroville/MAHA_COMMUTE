#!/usr/bin/env bash
# TEST 8  v25: what the three apps share, and the station server.
#
#   - the umbrella makes ~/.maha.commute/common and moves an older install's timetable
#     and stations into it (newest zip first, and only a file that is a zip)
#   - day, night and all read and write ONE timetable, whole file or nothing
#   - all.commute's server discovers stops beyond ZET's network one tile at a time,
#     keeps them for good, never asks twice, and says nothing of ZET's own area
# Overpass is a stand-in here (tests/fixtures/mock_overpass.py); nothing leaves the machine.
cd "$(dirname "$0")/.."
ROOT=$(pwd)
ART="$ROOT/$(cat VERSION)-maha_commute_v$(cat VERSION).sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok; else bad "$1: wanted [$2] got [$3]"; fi; }
printf '\nTEST 8  v25, the common layer\n\n'
[ -f "$ART" ] || { printf '  no artefact at %s\n' "$ART"; exit 1; }
TSHEBANG=/data/data/com.termux/files/usr/bin/bash
[ -e "$TSHEBANG" ] || { mkdir -p "$(dirname "$TSHEBANG")" 2>/dev/null && ln -sf "$(command -v bash)" "$TSHEBANG" 2>/dev/null; }

T=$(mktemp -d)
cleanup() { [ -n "${SRV:-}" ] && kill "$SRV" 2>/dev/null; [ -n "${MOCK:-}" ] && kill "$MOCK" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
export HOME="$T/home" PREFIX="$T/usr"
mkdir -p "$HOME" "$PREFIX/bin"; export PATH="$PREFIX/bin:$PATH"
C="$HOME/.maha.commute/common"

# ---- the umbrella adopts what an older install already holds ----------------
mkdir -p "$HOME/.commute" "$HOME/.nightcommute" "$HOME/.all.commute"
printf 'PK-old-day'   > "$HOME/.commute/zet_gtfs.zip";      touch -d '3 days ago' "$HOME/.commute/zet_gtfs.zip"
printf 'PK-new-night' > "$HOME/.nightcommute/zet_gtfs.zip"; touch -d '1 hour ago' "$HOME/.nightcommute/zet_gtfs.zip"
printf 'NOT A ZIP'    > "$HOME/.all.commute/zet_gtfs.zip"   # the newest file, but not a zip
printf '{"stops":{"1_1":["Old",45.8,15.98,null]}}' > "$HOME/.all.commute/stations.json"
( cd "$T" && bash "$ART" --offline --apps 123 </dev/null >/dev/null 2>&1 )
eq "the umbrella made the common folder"                        "yes" "$([ -d "$C" ] && echo yes || echo no)"
eq "it adopted the newest file that is a zip (not the junk)"    "PK-new-night" "$(cat "$C/zet_gtfs.zip" 2>/dev/null)"
eq "a stations list that was beside an app moved in, kept"      "Old" "$(python3 -c "import json;print(json.load(open('$C/stations.json'))['stops']['1_1'][0])" 2>/dev/null)"
eq "and nothing is left beside the app to be read instead"      "no" "$([ -e "$HOME/.all.commute/stations.json" ] && echo yes || echo no)"
# an install with nothing before it gets the stations shipped inside the installer
rm -rf "$HOME/.maha.commute" "$HOME/.all.commute" "$HOME/.commute" "$HOME/.nightcommute"
( cd "$T" && bash "$ART" --offline --apps 3 </dev/null >/dev/null 2>&1 )
eq "a fresh install puts every station in the common folder" "yes" "$(python3 -c "import json;print('yes' if len(json.load(open('$C/stations.json'))['stops'])>2400 else 'no')" 2>/dev/null)"
eq "and none beside the app"  "no" "$([ -e "$HOME/.all.commute/stations.json" ] && echo yes || echo no)"
bash "$HOME/.maha.commute/install-one.sh" --sync-key >/dev/null 2>&1
case "$(bash "$PREFIX/bin/maha-commute" info </dev/null 2>&1)" in *"shared by the three apps"*) ok ;; *) bad "info shows the common folder" ;; esac

# ---- all three apps point at the one timetable, and write it whole ----------
for a in day night all; do
  case "$a" in day) pf=13-install-day-commute-termux-v13.sh ;; night) pf=9-night_commute_v9.sh ;; all) pf=39-install-all_commute-termux-v39.sh ;; esac
  pay=$(python3 tools/patch_payload.py "src/payloads/$pf" $a)
  printf '%s' "$pay" | grep -qE 'CACHE_ZIP = (os.environ.get\("GTFS_CACHE", )?os.path.join\(COMMON_DIR, "zet_gtfs.zip"\)' && ok || bad "$a: its timetable is the common one"
  printf '%s' "$pay" | grep -qE 'os.replace\((tmp_zip|CACHE_ZIP \+ ".tmp"), CACHE_ZIP\)' && ok || bad "$a: the timetable is written whole or not at all"
  printf '%s' "$pay" | grep -qE 'MAHA_COMMON' && ok || bad "$a: the common folder can be moved by a test"
done

# ---- the station server, against a stand-in Overpass ------------------------
python3 - "$ART" "$T" <<'PYEOF'
import re, sys
s = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()
pay = s.split("MAHA_PAY_all_7c1a'")[1].split("\nMAHA_PAY_all_7c1a\n")[0]
for name, tag in (("all_commute_server.py", "ALLC_SERVER_PY"), ("update_all.py", "ALLC_UPDATE_PY")):
    m = re.search(r"cat > \"\$APPDIR/%s\" << '%s'\n(.*?)\n%s\n" % (re.escape(name), tag, tag), pay, re.S)
    open(sys.argv[2] + "/" + name, "w").write(m.group(1) + "\n")
PYEOF
SD="$T/srv"; CM="$T/common2"; mkdir -p "$SD" "$CM"; cp "$T/all_commute_server.py" "$T/update_all.py" "$SD/"
python3 tests/fixtures/mkgtfs.py "$CM/zet_gtfs.zip" 1
MAHA_COMMON="$CM" ALLC_DIR="$SD" python3 "$SD/update_all.py" >/dev/null 2>&1
eq "the rebuild used the common timetable and wrote the common stations" "yes" "$([ -s "$CM/stations.json" ] && [ ! -e "$SD/zet_gtfs.zip" ] && [ ! -e "$SD/stations.json" ] && echo yes || echo no)"

CNT="$T/mock.count"; : > "$CNT"; MPORT=18193
python3 tests/fixtures/mock_overpass.py $MPORT "$CNT" & MOCK=$!
start_server() {
  rm -f "$SD/port"
  ( cd "$SD" && MAHA_COMMON="$CM" ALLC_DIR="$SD" ALLC_PORT=18192 ALLC_NO_OPEN=1 ALLC_TAKEOVER=1 \
      MAHA_OVERPASS_URL="http://127.0.0.1:$MPORT/api" MAHA_OVERPASS_GAP=0 exec python3 all_commute_server.py >/dev/null 2>&1 ) &
  SRV=$!
  for i in $(seq 1 40); do [ -s "$SD/port" ] && curl -s "http://127.0.0.1:$(tr -d ' \n' < "$SD/port")/version" >/dev/null 2>&1 && break; sleep 0.3; done
  PORT=$(tr -d ' \n' < "$SD/port")
}
view() { curl -s "http://127.0.0.1:$PORT/stations/view?s=$1&w=$2&n=$3&e=$4&zoom=$5"; }
jq_() { python3 -c "import json,sys;d=json.load(sys.stdin);print($1)"; }
calls() { wc -l < "$CNT" | tr -d ' '; }
start_server

BOX="45.8800 16.0800 45.9200 16.1200"       # nowhere near a ZET station
r=$(view $BOX 16)
eq "a view beyond ZET's network is pending at first"        "True" "$(printf '%s' "$r" | jq_ "d['pending']>0")"
for i in $(seq 1 20); do r=$(view $BOX 16); [ "$(printf '%s' "$r" | jq_ "d['pending']")" = 0 ] && break; sleep 0.5; done
eq "then the stops are in the answer (named by OpenStreetMap)" "True" "$(printf '%s' "$r" | jq_ "any(x[1].startswith('Testna') for x in d['osm'])")"
n1=$(calls); [ "$n1" -ge 1 ] && ok || bad "Overpass was asked at least once"
view $BOX 16 >/dev/null; view $BOX 16 >/dev/null; sleep 1
eq "a tile already done is never asked again"               "$n1" "$(calls)"
eq "the answer is kept in the common folder, for good"      "yes" "$([ -s "$CM/osm_stops.json" ] && grep -q '"tiles"' "$CM/osm_stops.json" && echo yes || echo no)"
eq "zoomed out (14) nothing is asked"                       "0" "$(view 45.90 16.10 45.95 16.20 14 | jq_ "d['pending']")"
c0=$(calls)
eq "ZET's own area is never asked about"                    "0" "$(view 45.8040 15.9790 45.8075 15.9830 17 | jq_ "d['pending']")"
eq "...and Overpass was not called for it"                  "$c0" "$(calls)"
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
eq "a cross-site page cannot make the server ask Overpass"  "403" "$(code -H 'Sec-Fetch-Site: cross-site' "http://127.0.0.1:$PORT/stations/view?s=45.9&w=16.1&n=45.91&e=16.11&zoom=16")"
eq "a view that is not a view is refused"                   "400" "$(code "http://127.0.0.1:$PORT/stations/view?s=1&w=1&n=80&e=90&zoom=16")"
eq "so is a request with no box"                            "400" "$(code "http://127.0.0.1:$PORT/stations/view")"
kill $SRV 2>/dev/null; sleep 1; SRV=""
start_server
eq "after a restart the discovered stops come back at once" "True" "$(view $BOX 16 | jq_ "any(x[1].startswith('Testna') for x in d['osm'])")"
eq "...with no new request to Overpass"                     "$c0" "$(calls)"
kill $SRV 2>/dev/null; SRV=""

printf '\n  %s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" = "0" ]
