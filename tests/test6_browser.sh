#!/usr/bin/env bash
# TEST 6  all.commute's page, in a real browser, against its real server.
#
# The server is taken out of the artefact and fed a four stop feed; Chromium is
# driven by playwright-core with Leaflet served from disk. Skips (and says so)
# when playwright-core, a Chromium or leaflet is not on this machine. See
# test6_browser.js for what it proves and why.
cd "$(dirname "$0")/.."
ROOT=$(pwd)
ART=${ART:-$ROOT/$(cat VERSION)-maha_commute_v$(cat VERSION).sh}
pass=0; fail=0
printf '\nTEST 6  the page in a browser\n\n'
NODE=$(command -v node) || { printf '  skipped: no node\n'; exit 0; }
CHROME=${CHROME:-$(ls /opt/pw-browsers/chromium-*/chrome-linux/chrome 2>/dev/null | head -1)}
[ -x "${CHROME:-/nonexistent}" ] || { printf '  skipped: no chromium (set CHROME)\n'; exit 0; }
NM=${NODE_MODULES:-}
for c in "$NM" "$ROOT/node_modules" "$HOME/node_modules" "$ROOT/tests/node_modules"; do
  [ -n "$c" ] && [ -d "$c/playwright-core" ] && [ -f "$c/leaflet/dist/leaflet.js" ] && { NM="$c"; break; }
done
[ -d "${NM:-/nonexistent}/playwright-core" ] || { printf '  skipped: no playwright-core + leaflet@1.9.4 (npm i playwright-core leaflet@1.9.4, or set NODE_MODULES)\n'; exit 0; }

T=$(mktemp -d); PORT=18190
trap 'kill $SRV $MOCK 2>/dev/null; [ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
# a stand-in for Overpass, so scrolling beyond ZET's network can be tested without the network
MPORT=18194; : > "$T/mock.count"
python3 tests/fixtures/mock_overpass.py $MPORT "$T/mock.count" & MOCK=$!
python3 - "$ART" "$T" <<'PYEOF'
import re, sys
s = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()
pay = s.split("MAHA_PAY_all_7c1a'")[1].split("\nMAHA_PAY_all_7c1a\n")[0]
for name, tag in (("all_commute_server.py", "ALLC_SERVER_PY"), ("update_all.py", "ALLC_UPDATE_PY"), ("all.html", "ALLC_STAR_HTML")):
    m = re.search(r"cat > \"\$APPDIR/%s\" << '%s'\n(.*?)\n%s\n" % (re.escape(name), tag, tag), pay, re.S)
    open(sys.argv[2] + "/" + name, "w").write(m.group(1) + "\n")
PYEOF
python3 tests/fixtures/mkgtfs.py "$T/zet_gtfs.zip" 1
MAHA_COMMON="$T" ALLC_DIR="$T" python3 "$T/update_all.py" >/dev/null 2>&1
( cd "$T" && MAHA_COMMON="$T" MAHA_OVERPASS_URL="http://127.0.0.1:$MPORT/api" MAHA_OVERPASS_GAP=0 ALLC_DIR="$T" ALLC_PORT=$PORT ALLC_NO_OPEN=1 ALLC_TAKEOVER=1 exec python3 all_commute_server.py >/dev/null 2>&1 ) &
SRV=$!
# the server walks forward when its port is busy, and writes the one it got
for i in $(seq 1 40); do
  [ -s "$T/port" ] && PORT=$(tr -d ' \n' < "$T/port") && curl -s "http://127.0.0.1:$PORT/status" >/dev/null 2>&1 && break
  sleep 0.3
done
for speed in fast slow; do
  out=$(NODE_PATH="$NM" node tests/test6_browser.js "http://127.0.0.1:$PORT" "$NM/leaflet/dist" "$speed" "$CHROME" "$T/mock.count" 2>&1)
  printf '%s\n' "$out" | grep -v '^PASS'
  pass=$((pass + $(printf '%s\n' "$out" | grep -c '^PASS')))
  fail=$((fail + $(printf '%s\n' "$out" | grep -c '^FAIL')))
done
printf '\n  %s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" = "0" ]
