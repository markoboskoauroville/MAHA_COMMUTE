#!/usr/bin/env bash
# TEST 7  v22: what the first field test (field-tests/2026-10-08_v21) found.
#
# Each block names the finding it answers. All of it runs in temporary folders
# against the artefact, with a few lines of python standing in for the apps'
# servers where only the launcher is being tested. Prints PASS or FAIL per
# check and a count; skips what this machine cannot do, and says so.
cd "$(dirname "$0")/.."
ROOT=$(pwd)
ART="$ROOT/$(cat VERSION)-maha_commute_v$(cat VERSION).sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok; else bad "$1: wanted [$2] got [$3]"; fi; }
printf '\nTEST 7  v22, the field test findings\n\n'
[ -f "$ART" ] || { printf '  no artefact at %s\n' "$ART"; exit 1; }

TSHEBANG=/data/data/com.termux/files/usr/bin/bash
if [ ! -e "$TSHEBANG" ]; then
  mkdir -p "$(dirname "$TSHEBANG")" 2>/dev/null && ln -sf "$(command -v bash)" "$TSHEBANG" 2>/dev/null
fi

T=$(mktemp -d)
cleanup() { [ -n "${SRV:-}" ] && kill "$SRV" 2>/dev/null; pkill -f "$T" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
export HOME="$T/home" PREFIX="$T/usr"
mkdir -p "$HOME" "$PREFIX/bin"
export PATH="$PREFIX/bin:$PATH"
printf '#!/bin/sh\necho "$@" >> %s/opens.log\n' "$T" > "$PREFIX/bin/am"; chmod +x "$PREFIX/bin/am"
A="$HOME/.maha.commute"

# a fake day server, so only the launcher is under test; DELAY seconds before it
# binds, like a first start that has to build its schedule
fake_day() { # fake_day DELAY
  mkdir -p "$HOME/.commute"
  cat > "$HOME/.commute/commute_server.py" <<PYEOF
import http.server, os, socketserver, time
time.sleep($1)
d = os.path.expanduser("~/.commute"); port = 18082
open(d + "/port", "w").write(str(port))
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s): s.send_response(200); s.end_headers(); s.wfile.write(b"ok")
    def log_message(*a): pass
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("127.0.0.1", port), H).serve_forever()
PYEOF
  mkdir -p "$A/orig"
  printf '#!/bin/sh\nexec python3 %s/.commute/commute_server.py\n' "$HOME" > "$A/orig/day.commute"
  chmod +x "$A/orig/day.commute"
}

# ---- F2, F3: the key reaches every app, and an empty file is not a key ----
P="AI""za"                      # split, so no key shape sits in this file
KEY="${P}TESTTESTTESTTESTTESTTESTTESTTEST123"      # 39 characters, made up
mkdir -p "$HOME/.commute" "$HOME/.all.commute" "$T/cwd"
printf '\n' > "$HOME/.commute/google-api.txt"                   # one byte, a newline
printf '%s\n' "$KEY" > "$HOME/.all.commute/google-api.txt"       # the real one
( cd "$T/cwd" && bash "$ART" --offline --apps 123 </dev/null >/dev/null 2>&1 )
eq "F3: the store is filled from the file that holds a key, not the empty one" "$KEY" "$(tr -d ' \n' < "$A/keys/google-api.txt" 2>/dev/null)"
eq "F2: all.commute has its own key file"   "$KEY" "$(tr -d ' \n' < "$HOME/.all.commute/google-api.txt" 2>/dev/null)"
eq "F3: day.commute's empty file was replaced" "$KEY" "$(tr -d ' \n' < "$HOME/.commute/google-api.txt" 2>/dev/null)"
eq "F2: night.commute has it too"           "$KEY" "$(tr -d ' \n' < "$HOME/.nightcommute/gmaps-api.txt" 2>/dev/null)"
# a fresh phone: only a Google-maps-api.txt in the folder the installer runs in
rm -rf "$HOME/.commute" "$HOME/.nightcommute" "$HOME/.all.commute" "$A"
printf '%s\n' "$KEY" > "$T/cwd/Google-maps-api.txt"
( cd "$T/cwd" && bash "$ART" --offline --apps 3 </dev/null >/dev/null 2>&1 )
eq "F2: a fresh install gives all.commute the key" "$KEY" "$(tr -d ' \n' < "$HOME/.all.commute/google-api.txt" 2>/dev/null)"
# a key pasted later in the launcher reaches the apps
NEWKEY="${P}NEWNEWNEWNEWNEWNEWNEWNEWNEWNEW12345"; printf '%s\n' "$NEWKEY" > "$A/keys/google-api.txt"
bash "$A/install-one.sh" --sync-key force
eq "F2: --sync-key force replaces an app's key" "$NEWKEY" "$(tr -d ' \n' < "$HOME/.all.commute/google-api.txt")"
case "$(bash "$A/install-one.sh" --sync-key force 2>&1)" in *"${P}"*) bad "the key was printed" ;; *) ok ;; esac

# ---- F4: an app whose folder is gone is not installed -------------------
rm -rf "$HOME/.all.commute"
out=$(cd "$T/cwd" && bash "$ART" --offline --apps 3 </dev/null 2>&1)
case "$out" in *"already current"*all.commute*) bad "F4: an app with no folder was called already current" ;; *) ok ;; esac
[ -s "$HOME/.all.commute/all_commute_server.py" ] && ok || bad "F4: the installer put the deleted app back"

# ---- F5, F10: the launcher returns, and waits for a slow first start ------
rm -rf "$HOME/.commute" "$A"
( cd "$T/cwd" && bash "$ART" --offline --apps 1 </dev/null >/dev/null 2>&1 )
fake_day 5
s0=$(date +%s)
timeout 60 maha-commute day </dev/null 2>&1 | cat > "$T/cli.out"
took=$(( $(date +%s) - s0 ))
[ "$took" -le 40 ] && ok || bad "F5: maha-commute day | cat did not return (took ${took}s)"
[ "$took" -ge 5 ] && ok || bad "F10: it did not wait for a server that binds after 5 s (took ${took}s)"
grep -q "up" "$T/cli.out" && ok || bad "F10: it did not say the app came up"
python3 - <<'PYEOF' && ok || bad "F5: the server is not left running"
import urllib.request
assert urllib.request.urlopen("http://127.0.0.1:18082/", timeout=5).status == 200
PYEOF
leftover=$(ps -eo ppid,args | grep -E "maha-commute day" | grep -v grep | wc -l | tr -d ' ')
eq "F5: no copy of the launcher is left holding the terminal" "0" "$leftover"
pkill -f "$HOME/.commute/commute_server.py" 2>/dev/null

# ---- F11: update --check only describes ----------------------------------
out=$(bash "$PREFIX/bin/maha-commute-update" --check "$ART" </dev/null 2>&1); rc=$?
eq "F11: --check <file> exits 0" "0" "$rc"
case "$out" in *"install it"*) bad "F11: --check <file> offered to install" ;; *) ok ;; esac
out=$(bash "$PREFIX/bin/maha-commute-update" --check "$T/no-such-file.sh" </dev/null 2>&1); rc=$?
eq "F11: a missing file is an error" "2" "$rc"

# ---- F6, F7, F1 need the app's server: take it out of the artefact --------
python3 - "$ART" "$T" <<'PYEOF'
import re, sys
s = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()
pay = s.split("MAHA_PAY_all_7c1a'")[1].split("\nMAHA_PAY_all_7c1a\n")[0]
for name, tag in (("all_commute_server.py", "ALLC_SERVER_PY"), ("update_all.py", "ALLC_UPDATE_PY"), ("all.html", "ALLC_STAR_HTML")):
    m = re.search(r"cat > \"\$APPDIR/%s\" << '%s'\n(.*?)\n%s\n" % (re.escape(name), tag, tag), pay, re.S)
    open(sys.argv[2] + "/" + name, "w").write(m.group(1) + "\n")
PYEOF
SD="$T/srv"; mkdir -p "$SD"; cp "$T/all_commute_server.py" "$T/update_all.py" "$T/all.html" "$SD/"
# F7: no feed and no network: the index waits, and builds when the feed arrives
( cd "$SD" && ALLC_DIR="$SD" ALLC_PORT=18191 ALLC_RETRY_FIRST=2 ALLC_NO_OPEN=1 ALLC_TAKEOVER=1 exec python3 all_commute_server.py >/dev/null 2>&1 ) &
SRV=$!
for i in $(seq 1 40); do [ -s "$SD/port" ] && curl -s "http://127.0.0.1:$(tr -d ' \n' < "$SD/port")/status" >/dev/null 2>&1 && break; sleep 0.3; done
PORT=$(tr -d ' \n' < "$SD/port" 2>/dev/null)
st=""
for i in $(seq 1 30); do
  st=$(curl -s "http://127.0.0.1:$PORT/status" | python3 -c "import json,sys;print(json.load(sys.stdin).get('state'))" 2>/dev/null)
  [ "$st" = "waiting_for_network" ] && break; sleep 1
done
eq "F7: with no feed the status says it is waiting for the network" "waiting_for_network" "$st"
python3 tests/fixtures/mkgtfs.py "$SD/zet_gtfs.zip" 1
got=""
for i in $(seq 1 40); do
  got=$(curl -s "http://127.0.0.1:$PORT/status" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('ok'),d.get('state'))" 2>/dev/null)
  [ "$got" = "True idle" ] && break; sleep 1
done
eq "F7: the index is built by itself once the feed is there" "True idle" "$got"

# F6: state changes need POST and the same origin
code() { # code METHOD PATH [header...]
  local m="$1" p="$2"; shift 2
  curl -s -o /dev/null -w '%{http_code}' -X "$m" "$@" "http://127.0.0.1:$PORT$p"
}
eq "F6: GET /cache/clear is refused (405)"        "405" "$(code GET /cache/clear)"
eq "F6: GET /rebuild is refused (405)"            "405" "$(code GET /rebuild)"
eq "F6: GET /sched-delete is refused (405)"       "405" "$(code GET '/sched-delete?all=1')"
eq "F6: a cross-site <img> GET is refused"        "403" "$(code GET /cache/clear -H 'Sec-Fetch-Site: cross-site')"
eq "F6: a cross-site POST is refused"             "403" "$(code POST /cache/clear -H 'Sec-Fetch-Site: cross-site')"
eq "F6: a POST from another origin is refused"    "403" "$(code POST /cache/clear -H 'Origin: http://evil.example')"
eq "F6: a POST from the page's own origin works"  "200" "$(code POST /cache/clear -H "Origin: http://127.0.0.1:$PORT" -H 'Sec-Fetch-Site: same-origin')"
eq "F6: the stations survive the clear"           "True" "$(curl -s "http://127.0.0.1:$PORT/stops?lat=45.8052&lon=15.9805&r=300&widen=0" | python3 -c "import json,sys;print(json.load(sys.stdin)['ok'])")"
eq "F6: a cross-site POST of a key is refused"    "403" "$(code POST /api-keys -H 'Origin: http://evil.example' -d x)"
for app in day night; do
  case "$app" in day) pf=13-install-day-commute-termux-v13.sh ;; night) pf=9-night_commute_v9.sh ;; esac
  python3 tools/patch_payload.py "src/payloads/$pf" $app | grep -qF 'def _cross_site(self):' && ok || bad "F6: $app refuses cross-site requests"
done
kill $SRV 2>/dev/null; SRV=""

printf '\n  %s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" = "0" ]
