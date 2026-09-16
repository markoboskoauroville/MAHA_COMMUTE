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

# ---- the two python tools, mechanism only ------------------------
# The protobuf reader is fed bytes assembled by hand from the wire
# format, so a reader that only agrees with itself cannot pass.
py_out=$(python3 - <<'PYEOF'
import importlib.util, struct, time, sys
spec = importlib.util.spec_from_file_location("stream", "src/50_stream.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def vi(n):
    o=b""
    while True:
        b=n&0x7F; n>>=7
        o+=bytes([b|0x80]) if n else bytes([b])
        if not n: return o
ld=lambda f,p: vi(f<<3|2)+vi(len(p))+p
vf=lambda f,v: vi(f<<3|0)+vi(v)
f32=lambda f,v: vi(f<<3|5)+struct.pack("<f",v)
now=int(time.time())
feed=(ld(1, ld(1,b"2.0")+vf(3,now))
      + ld(2, ld(1,b"e1")+ld(4, ld(1,ld(1,b"T-1"))+ld(2,f32(1,45.81)+f32(2,15.98))+vf(5,now)))
      + ld(2, ld(1,b"e2")+ld(3, ld(1,ld(1,b"T-2"))+vf(4,now))))
p=m.parse_feed(feed)
ok=[]
ok.append(("header timestamp read", p["header_ts"]==now))
ok.append(("entities counted", p["entities"]==2))
ok.append(("trip ids read", sorted(p["trip_ids"])==["T-1","T-2"]))
ok.append(("position read", len(p["positions"])==1 and abs(p["positions"][0][0]-45.81)<0.01))
for label, cut in (("truncated raises", feed[:len(feed)//2]), ("html raises", b"<html>x</html>")):
    try:
        m.parse_feed(cut); ok.append((label, False))
    except Exception: ok.append((label, True))
# the key namer must never contain the key
import importlib.util as iu
spec2 = iu.spec_from_file_location("kt","src/55_keytest.py")
k = iu.module_from_spec(spec2); spec2.loader.exec_module(k)
# Built from pieces so no key shaped literal exists in this repository.
# A fixture that looks like a key is indistinguishable from one, both to
# the secret scanner and to anybody reading the file in a hurry.
secret = "AIza" + "Sy" + "NotARealKey_ForTest_" + "0123456789abc"
nm=k.name_of(secret)
ok.append(("the namer hides the key", secret not in nm and secret[4:] not in nm))
ok.append(("the namer still tells two apart", k.name_of(secret)!=k.name_of(secret[:-1]+"2")))
note="account marko 2026\nCANCELLED old one\nkey: "+secret+"\nsee https://x.y?srsltid=AbCdEfGhIjKlMnOpQrStUvWxYz012345\n"
found=k.find_keys(note)
ok.append(("the parser takes the key out of a note", found==[secret]))
ok.append(("and leaves the tracking token alone", all("srsltid" not in f for f in found)))
aq = "AQ." + "Ab8RN6Jm" + "NotARealKey" + "ForTestsOnly" + "1234567890ab"
ok.append(("the newer AQ. format is found too", aq in k.find_keys("gemini "+aq)))
for label, good in ok:
    print(("PASS" if good else "FAIL")+" "+label)
PYEOF
)
while IFS= read -r l; do
  case "$l" in
    PASS*) ok ;;
    FAIL*) bad "${l#FAIL }" ;;
  esac
done <<< "$py_out"

# ---- the midnight countdown, in a real javascript engine ----------
# The bug that showed minus 1405 minutes at 23:27 for a 00:02 bus. The
# patched function is pulled out of the ARTEFACT, not out of a copy typed
# into this test, so what is measured is what ships.
if command -v node >/dev/null 2>&1; then
  V=$(cat VERSION); ART="$V-maha_commute_v$V.sh"
  JS=$(mktemp); trap 'rm -f "$JS"' EXIT
  {
    printf 'const NOW = new Date("2026-08-31T23:27:13+02:00").getTime();\n'
    printf 'const R = Date;\n'
    printf 'global.Date = class extends R { constructor(...a){ return a.length ? new R(...a) : new R(NOW); } static now(){ return NOW; } };\n'
    sed -n '/^function hhmmToTodaySecs/,/^}/p' "$ART"
    printf 'const mins = s => Math.round((s*1000 - Date.now())/60000);\n'
    printf 'const out = {};\n'
    printf 'for (const t of ["23:21","23:32","23:47","00:02","00:12","00:24","24:02"]) out[t] = mins(hhmmToTodaySecs(t));\n'
    printf 'console.log(JSON.stringify(out));\n'
  } > "$JS"
  R=$(TZ=Europe/Zagreb node "$JS" 2>/dev/null)
  eq "00:02 is 35 minutes away, not -1405" '"00:02":35' "$(printf '%s' "$R" | grep -o '"00:02":[-0-9]*')"
  eq "00:12 agrees with the schedule row"  '"00:12":45' "$(printf '%s' "$R" | grep -o '"00:12":[-0-9]*')"
  eq "00:24 agrees with the schedule row"  '"00:24":57' "$(printf '%s' "$R" | grep -o '"00:24":[-0-9]*')"
  eq "a just missed bus stays negative"    '"23:21":-6' "$(printf '%s' "$R" | grep -o '"23:21":[-0-9]*')"
  eq "a bus in five minutes is unchanged"  '"23:32":5'  "$(printf '%s' "$R" | grep -o '"23:32":[-0-9]*')"
  eq "the GTFS 24:xx form also works"      '"24:02":35' "$(printf '%s' "$R" | grep -o '"24:02":[-0-9]*')"
else
  printf '  node is not here, so the 6 midnight countdown checks did not run\n'
fi

# ---- the pin is the number and nothing else ------------------------
# pinHTML is pulled out of the ARTEFACT and run for real. The star is gone
# and so is the name: three labels per station, six stations in view, and
# the map was a pile of text. The name comes back in the popup, which is
# the only place it is needed.
if command -v node >/dev/null 2>&1; then
  V=$(cat VERSION); ART="$V-maha_commute_v$V.sh"
  JS2=$(mktemp)
  {
    printf 'const STAR_PTS="0,0"; const COLOUR={A:"#d4a017",B:"#39d0d8"};\n'
    printf 'let WATCHED="A";\n'
    printf 'const esc = t => String(t); const dirAbbr = () => "N";\n'
    printf 'const isWatched = id => id === WATCHED;\n'
    sed -n "/^function starHTML/,/^}/p" "$ART"
    sed -n "/^function pinHTML/,/^}/p" "$ART"
    printf 'const A = pinHTML({stop_id:"A",name:"Trg",bearing:0});\n'
    printf 'const B = pinHTML({stop_id:"B",name:"Ilica",bearing:0});\n'
    printf 'console.log(JSON.stringify({watchedHasStar:/class="star/.test(A), otherHasStar:/class="star/.test(B), watchedHasId:/pinid/.test(A), otherHasId:/pinid/.test(B), otherHasName:/pinchip/.test(B)}));\n'
  } > "$JS2"
  R2=$(node "$JS2" 2>/dev/null); rm -f "$JS2"
  eq "no station wears a star, watched or not" "false" "$(printf '%s' "$R2" | grep -o '"watchedHasStar":[a-z]*' | cut -d: -f2)"
  eq "and none of the others either"     "false" "$(printf '%s' "$R2" | grep -o '"otherHasStar":[a-z]*' | cut -d: -f2)"
  eq "the number is what is left"        "true"  "$(printf '%s' "$R2" | grep -o '"otherHasId":[a-z]*' | cut -d: -f2)"
  eq "the name is off the map"           "false" "$(printf '%s' "$R2" | grep -o '"otherHasName":[a-z]*' | cut -d: -f2)"
else
  printf '  node is not here, so the 4 star checks did not run\n'
fi

# ---- three taps in a row fetch once ---------------------------------
# armStation is pulled out of the ARTEFACT and driven at real timings: a tap,
# another 80ms later, a third at 160ms. Only the last one may reach the
# network, and every tap must have moved the outline before it.
if command -v node >/dev/null 2>&1; then
  V=$(cat VERSION); ART="$V-maha_commute_v$V.sh"
  J3=$(mktemp)
  {
    printf 'const calls=[]; let hudLog=[];\n'
    printf 'global.document={querySelectorAll:()=>[],getElementById:()=>({set innerHTML(v){}})};\n'
    printf 'const esc=t=>String(t); const MARKS={};\n'
    printf 'function hud(h,b){hudLog.push((b?"spin ":"still ")+h.replace(/<[^>]+>/g,""));}\n'
    printf 'function openPop(s,g){calls.push(s.stop_id+"@"+g);}\n'
    sed -n "/^let ARM_T = null, SELGEN = 0;/,/^}/p" "$ART"
    printf 'armStation({stop_id:"A"});\n'
    printf 'setTimeout(()=>armStation({stop_id:"B"}),80);\n'
    printf 'setTimeout(()=>armStation({stop_id:"C"}),160);\n'
    printf 'setTimeout(()=>console.log(JSON.stringify({n:calls.length,last:calls[0]||"",taps:hudLog.filter(x=>/selected/.test(x)).length})),700);\n'
  } > "$J3"
  R3=$(node "$J3" 2>/dev/null); rm -f "$J3"
  eq "three quick taps fetch once"        '"n":1'     "$(printf '%s' "$R3" | grep -o '"n":[0-9]*')"
  eq "and it is the last one tapped"      '"last":"C@3"' "$(printf '%s' "$R3" | grep -o '"last":"[^"]*"')"
  eq "every tap moved the outline first"  '"taps":3'  "$(printf '%s' "$R3" | grep -o '"taps":[0-9]*')"
else
  printf '  node is not here, so the 3 arming checks did not run\n'
fi

# ---- the live feed, reader and placing, alone ---------------------
# night.commute v10 reads the ZET realtime protobuf. Nothing here touches
# the network: the feed is assembled byte by byte from the wire format, so
# a reader that merely agrees with itself cannot pass.
live_out=$(python3 - <<'PYEOF'
import struct, sys, threading, time, json, urllib.request, datetime

# What live.py inherits from night_server.py when it is spliced into it.
NIGHT_ROUTES = ("31", "32", "33", "34")
NIGHT_JSON = "/nonexistent/night.json"
COORDS_JSON = "/nonexistent/coords.json"
SCHED_JSON = "/nonexistent/night_sched.json"
def _log(m): pass

g = dict(globals())
exec(compile(open("src/payloads/night/live.py", encoding="utf-8").read(),
             "live.py", "exec"), g)

ok = []
def check(label, cond): ok.append((label, bool(cond)))

# ---- the wire ----
def vi(n):
    o = b""
    while True:
        b = n & 0x7F; n >>= 7
        o += bytes([b | 0x80]) if n else bytes([b])
        if not n: return o
ld  = lambda f, p: vi(f << 3 | 2) + vi(len(p)) + p
vf  = lambda f, v: vi(f << 3 | 0) + vi(v)
f32 = lambda f, v: vi(f << 3 | 5) + struct.pack("<f", v)
# A negative int64 goes on the wire as its two's complement, which is how an
# early tram arrives looking like 18446744073709551526.
neg = lambda v: v & ((1 << 64) - 1)

NOW = int(time.time())
TRIP = b"0_23_3302_33_10017"
desc = ld(1, TRIP) + ld(5, b"33")
def stu(stop, t, d):
    ev = (vf(1, neg(d)) if d is not None else b"") + (vf(2, t) if t else b"")
    return ld(4, stop) + ld(3, ev)

# The shape ZET actually publishes: the delay and the position for ONE tram
# arrive as TWO entities that never appear together. 31 carried a TripUpdate,
# 35 carried a VehiclePosition, 0 carried both.
feed = (ld(1, ld(1, b"2.0") + vf(3, NOW))
        + ld(2, ld(1, b"X8HIDLT03R")
               + ld(3, ld(1, desc) + ld(2, stu(b"314_1", NOW + 60, -160))))
        + ld(2, ld(1, b"X8HIDLT03R_460")
               + ld(4, ld(1, desc) + ld(2, f32(1, 45.8004) + f32(2, 15.9850))
                      + vf(5, NOW - 5) + ld(8, ld(1, b"460")))))
p = g["parse_rt"](feed)
check("the feed header timestamp is read", p["ts"] == NOW)
check("both entities are counted", p["entities"] == 2)
check("two entities become ONE tram", len(p["trips"]) == 1)
t = p["trips"][TRIP.decode()]
check("the merged tram has its position", t["lat"] is not None)
check("and its stop updates", len(t["stops"]) == 1)
check("the route comes off the descriptor", t["route_id"] == "33")
check("the car number is read", t["veh"] == "460")
check("an early tram is early, not 18 quintillion seconds late",
      t["stops"]["314_1"]["d"] == -160)

# ---- a coordinate that is not in Zagreb is not a Zagreb tram ----
for label, lat, lon in (("0,0 is a missing coordinate, not the Atlantic", 0.0, 0.0),
                        ("a tram in the Adriatic is refused", 43.50, 16.44),
                        ("and one in the next country", 47.50, 19.04)):
    bad = (ld(1, vf(3, NOW))
           + ld(2, ld(1, b"e") + ld(4, ld(1, desc) + ld(2, f32(1, lat) + f32(2, lon)))))
    check(label, g["parse_rt"](bad)["trips"][TRIP.decode()]["lat"] is None)

# ---- malformed ----
for label, cut in (("a feed truncated mid field raises", feed[:len(feed) - 3]),
                   ("a web page is not a feed", b"<html><body>portal</body></html>")):
    try:
        g["parse_rt"](cut); check(label, False)
    except Exception: check(label, True)
check("an empty feed is empty, not an error", g["parse_rt"](b"")["entities"] == 0)

# ---- the delay rule, which is where the feed lies ----
BD = g["_best_delay"]
check("a delay with no time beside it is not a delay",
      BD({"a": {"t": None, "d": 0}}, NOW) is None)
check("thirty of those in a row still say nothing",
      BD({str(i): {"t": None, "d": 0} for i in range(30)}, NOW) is None)
check("a delay of 24000 seconds is not a delay",
      BD({"a": {"t": NOW + 10, "d": 24000}}, NOW) is None)
check("nor is 3605, which is a clock an hour out",
      BD({"a": {"t": NOW + 10, "d": 3605}}, NOW) is None)
check("a real one is taken", BD({"a": {"t": NOW + 10, "d": 120}}, NOW) == 120)
check("a genuinely late tram survives", BD({"a": {"t": NOW + 10, "d": 900}}, NOW) == 900)
check("an early one does too", BD({"a": {"t": NOW + 10, "d": -420}}, NOW) == -420)
check("the boundary itself is allowed",
      BD({"a": {"t": NOW + 10, "d": 1800}}, NOW) == 1800)
check("and one second past it is not",
      BD({"a": {"t": NOW + 10, "d": 1801}}, NOW) is None)
check("a stop still ahead beats one already passed",
      BD({"past": {"t": NOW - 30, "d": 60}, "next": {"t": NOW + 30, "d": 90}}, NOW) == 90)
check("with nothing ahead, the most recent past one is used",
      BD({"old": {"t": NOW - 900, "d": 60}, "recent": {"t": NOW - 30, "d": 90}}, NOW) == 90)
check("no updates at all is no delay", BD({}, NOW) is None)

# ---- placing a tram on a line ----
NAMES = ["A", "B", "C", "D", "E", "F"]
NET = {"lines": {"33": {"termA": "A", "termB": "F", "stations": NAMES,
                        "stopmap": {n: [n + "_0", n + "_1"] for n in NAMES}},
                 "31": {"termA": "X", "termB": "Y", "stations": ["X", "Y"],
                        "stopmap": {"X": ["X_0", "X_1"], "Y": ["Y_0", "Y_1"]}}}}
# A straight line east, about 780 m a step, and X sits right on top of C.
COORDS = {n: [45.80, 15.90 + 0.01 * i] for i, n in enumerate(NAMES)}
COORDS["X"] = [45.80, 15.92]
COORDS["Y"] = [45.90, 16.20]

idx = g["_stop_index"](NET)
check("a stop id knows its line", idx["C_0"][0] == "33")
check("and its direction", idx["C_1"][1] == 1)
check("and its place in the order", idx["D_0"][3] == 3)
check("a stop id nobody has is not invented", "Z_0" not in idx)

DO = g["_direction_of"]
check("the stops it still has ahead say which way it is going",
      DO({"trip_id": "x", "stops": {"C_1": {}, "D_1": {}}}, "33", idx) == (1, "stops"))
check("and the other way", DO({"trip_id": "x", "stops": {"C_0": {}}}, "33", idx) == (0, "stops"))
check("another line's stops do not vote",
      DO({"trip_id": "0_23_3301_33_1", "stops": {"X_1": {}}}, "33", idx)[1] == "pattern")
check("with no stops, pattern 01 is direction 0",
      DO({"trip_id": "0_23_3301_33_10032", "stops": {}}, "33", idx) == (0, "pattern"))
check("and pattern 02 is direction 1",
      DO({"trip_id": "0_23_3302_33_10017", "stops": {}}, "33", idx) == (1, "pattern"))
check("a trip id that says nothing admits it",
      DO({"trip_id": "rubbish", "stops": {}}, "33", idx) == (None, "unknown"))

NS = g["_nearest_station"]
check("a tram is at the station it is standing on", NS(NET, COORDS, "33", 45.80, 15.92)[0] == "C")
check("and that station's index comes with it", NS(NET, COORDS, "33", 45.80, 15.92)[1] == 2)
check("the distance is in metres, and small", NS(NET, COORDS, "33", 45.80, 15.9201)[2] < 30)
# X is a 31's stop at the same coordinate as C. A 33 standing there is at C.
check("a 33 is never at a 31's stop", NS(NET, COORDS, "33", 45.80, 15.92)[0] != "X")
check("a line with no coordinates places nothing",
      NS({"lines": {"33": {"stations": ["Q"]}}}, {}, "33", 45.8, 15.9)[0] is None)

# ---- how long it takes, out of the app's own timetable ----
# Two minutes a stop out, and the same back. One trip dawdles at D to prove
# the median is taken and not the worst.
def trip0(base, slow=0):
    return {NAMES[i] + "_0": base + i * 120 + (slow if i >= 3 else 0) for i in range(6)}
def trip1(base):
    return {NAMES[i] + "_1": base + (5 - i) * 120 for i in range(6)}
SCHED = {"33": {"0": [trip0(0), trip0(3000), trip0(6000, slow=600)],
                "1": [trip1(0), trip1(3000)]}}
run = g["_running_times"](NET, SCHED)
r0, r1 = run["33"]["0"], run["33"]["1"]
check("direction 0 counts up from its first station", r0[0] == 0 and r0[5] == 600)
# Both directions are measured from the same end of the same listed order, so
# direction 1, which travels the other way along it, counts downhill into
# negative numbers. That is not a bug to be corrected into looking tidy: it is
# what makes the one subtraction below come out positive in both directions.
check("direction 1 runs downhill along the same order", r1[0] == 0 and r1[5] == -600)
check("the median ignores the one trip that dawdled", r0[3] == 360)
# The property everything downstream leans on, in both directions.
check("dir 0: from the tram to me comes out positive", r0[4] - r0[1] == 360)
check("dir 1: the same subtraction is still positive", r1[1] - r1[4] == 360)
check("a line no trip runs has no times",
      all(x is None for x in g["_running_times"](NET, {})["33"]["0"]))

# ---- the service window ----
W = g["_in_night_window"]
D = datetime.datetime
check("23:49 is too early", W(D(2026, 9, 16, 23, 49)) is False)
check("23:50 is the first minute", W(D(2026, 9, 16, 23, 50)) is True)
check("midnight is the middle of it", W(D(2026, 9, 16, 0, 30)) is True)
check("04:40 is the last minute", W(D(2026, 9, 16, 4, 40)) is True)
check("04:41 is over", W(D(2026, 9, 16, 4, 41)) is False)
check("the afternoon is not the night", W(D(2026, 9, 16, 15, 0)) is False)

# ---- it answers even when it cannot answer ----
# NIGHT_JSON above points at nothing, so this is the un-built app. It must
# come back with a reason rather than raise into a 500.
p = g["live_payload"]()
check("a live payload is always a payload", isinstance(p, dict) and "trams" in p)
check("and says why it is empty", p["trams"] == [])

for label, good in ok:
    print(("PASS" if good else "FAIL") + " " + label)
PYEOF
)
while IFS= read -r l; do
  case "$l" in
    PASS*) ok ;;
    FAIL*) bad "${l#FAIL }" ;;
  esac
done <<< "$live_out"

# ---- the live feed, in the page, out of the ARTEFACT ---------------
# page.js pulls night.html out of the artefact, stubs a browser round
# it and drives the shipped code. The direction comparison is the one worth
# the trouble: get it backwards and the app confidently lists the trams that
# have already gone past you.
if command -v node >/dev/null 2>&1; then
  V=$(cat VERSION); ART="$V-maha_commute_v$V.sh"
  page_out=$(node tests/page.js "$ART" 2>&1)
  while IFS= read -r l; do
    case "$l" in
      PASS*) ok ;;
      FAIL*) bad "${l#FAIL }" ;;
    esac
  done <<< "$page_out"
  case "$page_out" in
    *COUNT*) ;;
    *) bad "page.js did not finish, so its checks did not run" ;;
  esac
else
  printf '  node is not here, so the 45 live page checks did not run\n'
fi

printf '\n  %s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" = "0" ]
