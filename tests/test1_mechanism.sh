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
MAHA_APPS="day|day.commute|.commute|v13|8082|the daytime ride|/.commute/commute_server.py|the daytime ride
night|night.commute|.nightcommute|v9|8087|the four night trams|night_server.py|four night trams
all|all.commute|.all.commute|v39|8084|every station around you|all_commute_server.py|stations around you"
HOME_REAL="$HOME"; HOME="$T/home"; mkdir -p "$HOME"

is_installed day && bad "empty bin reported an install" || ok
printf 'v13\n' > "$STAMPDIR/day"
if is_installed day; then bad "a stamp with no command behind it was believed"; else ok; fi
printf '#!/bin/sh\n' > "$BIN/day.commute"
if is_installed day; then bad "a file with no execute bit counted"; else ok; fi
chmod +x "$BIN/day.commute"
# v22: the command alone is not an install; its folder has to be there too
if is_installed day; then bad "a command whose app folder is gone counted as installed"; else ok; fi
mkdir -p "$HOME/.commute"; : > "$HOME/.commute/commute_server.py"
if is_installed day; then ok; else bad "a real command was not seen"; fi
HOME="$HOME_REAL"
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

# ---- the board's own midnight, ten past it ------------------------
# The bug that showed 1445 min at 00:10 for the 00:15 tram. A ride that
# crosses midnight stays filed under the day it set out on, as 24:15, and
# the index on the phone at that hour is still yesterday's. Read against
# today's midnight, every one of those rows lands a day out. The server is
# pulled out of the ARTEFACT and driven against a three row index, with the
# clock pinned and nothing allowed near the network.
V=$(cat VERSION); ART="$V-maha_commute_v$V.sh"
ALLC_SRC=$(mktemp); ALLC_DIR_T=$(mktemp -d)
awk '
  /cat > .*all_commute_server.py.* <<.?.ALLC_SERVER_PY/ { grab=1; next }
  grab && $0 == "ALLC_SERVER_PY" { grab=0; next }
  grab { print }
' "$ART" > "$ALLC_SRC"
board_out=$(ALLC_DIR="$ALLC_DIR_T" python3 - "$ALLC_SRC" <<'ALLC_BOARD_PY'
import datetime, os, sqlite3, sys, time

SRC = sys.argv[1]
DB = os.path.join(os.environ["ALLC_DIR"], "network.db")


def index(service_date, rows):
    """One day of timetable, the way the phone keeps it: seconds counted from
    the service day's own midnight, past 24:00 and on for a ride that crosses
    it."""
    try:
        os.remove(DB)
    except OSError:
        pass
    con = sqlite3.connect(DB)
    con.execute("create table meta(k text primary key, v text)")
    con.execute("create table stops(stop_id text primary key, name text,"
                " lat real, lon real, bearing real)")
    con.execute("create table dep(stop_id text, t int, trip_id text,"
                " route text, head text)")
    con.execute("create table trips(trip_id text primary key, route text,"
                " head text, origin text, dest text, start_t int, end_t int)")
    con.execute("insert into meta values('service_date', ?)", (service_date,))
    con.execute("insert into stops values('S1','Bolsiceva',45.74,16.0,0.0)")
    for t, route, head in rows:
        tid = "trip_%s_%d" % (route, t)
        con.execute("insert into dep values('S1',?,?,?,?)", (t, tid, route, head))
        con.execute("insert into trips values(?,?,?,?,?,?,?)",
                    (tid, route, head, "Galijska", head, t, t + 1200))
    con.commit()
    con.close()


def server_at(when):
    """The shipped server, with its clock stopped at `when` and its feed cut."""
    real_time, real_dt = time, datetime
    stamp = when.timestamp()

    class Clock(object):
        def __getattr__(self, k):
            return getattr(real_time, k)

        def time(self):
            return stamp

    class Datetime(real_dt.datetime):
        @classmethod
        def now(cls, tz=None):
            return when

    class DatetimeModule(object):
        date = real_dt.date
        datetime = Datetime
        timedelta = real_dt.timedelta

    g = {"__name__": "allc_under_test", "__file__": SRC}
    exec(compile(open(SRC, encoding="utf-8").read(), "all_commute_server.py",
                 "exec"), g)
    g["time"] = Clock()
    g["datetime"] = DatetimeModule()
    g["DB_PATH"] = DB
    g["_log"] = lambda *a: None

    def no_feed():
        raise RuntimeError("the test never touches the network")

    g["fetch_rt"] = no_feed
    return g


ok = []


def check(label, cond):
    ok.append((label, bool(cond)))


def board_at(g, window=90):
    return g["board"]("S1", window, back=15, fill="never")


def mins_for(g, route, window=90):
    for d in board_at(g, window)["departures"]:
        if d["route"] == route:
            return d["mins"], d["sched"]
    return None, None


# 00:15 and 00:18 tonight, filed by the index as 24:15 and 24:18, and one row
# from the small hours of the day the index was actually built for.
NIGHT = [(24 * 3600 + 15 * 60, "241", "Gl.kolodvor"),
         (24 * 3600 + 18 * 60, "166", "Lisinski"),
         (40 * 60, "268", "V. Gorica")]

TEN_PAST = datetime.datetime(2026, 9, 18, 0, 10, 0)

# ---- the case it is FOR: ten past midnight, yesterday's index ----
index("20260917", NIGHT)
g = server_at(TEN_PAST)
m, sched = mins_for(g, "241")
check("the 00:15 tram is 5 minutes away, not 1445", m == 5)
check("and it is still called 00:15", sched == "00:15")
check("the 00:18 one is 8 minutes away", mins_for(g, "166")[0] == 8)
check("a row from the small hours keeps its own count",
      mins_for(g, "268")[0] == 30)
check("the board says whose day it is reading",
      board_at(g)["service_date"] == "20260917")
check("and that it is not today's", board_at(g)["index_stale"] is True)

# ---- the same index in daylight: no phantom out of the far band ----
g = server_at(datetime.datetime(2026, 9, 18, 14, 0, 0))
check("at two in the afternoon the 24:15 row is not on the board",
      mins_for(g, "241")[0] is None)

# ---- a fresh index at the same hour: 24:15 is TOMORROW night ----
index("20260918", NIGHT)
g = server_at(TEN_PAST)
check("on today's index the 24:15 row is not tonight's tram",
      mins_for(g, "241")[0] is None)
check("and the 00:40 row still is", mins_for(g, "268")[0] == 30)

for label, good in ok:
    print("%s\t%s" % ("ok" if good else "FAIL", label))
ALLC_BOARD_PY
)
rm -rf "$ALLC_SRC" "$ALLC_DIR_T"
while IFS="$(printf '\t')" read -r verdict label; do
  [ -z "$label" ] && continue
  if [ "$verdict" = "ok" ]; then ok; else bad "$label"; fi
done <<BOARD_OUT
$board_out
BOARD_OUT
if [ -z "$board_out" ]; then
  bad "the board never ran: the server did not come out of the artefact"
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

# ---- env.sh follows the shell that READS it ------------------------
# /root and /data/data/com.termux/files/home are one directory wearing two
# names, and env.sh sits in it and is sourced from both sides. A path
# expanded when the file was WRITTEN is correct on the side that wrote it
# and missing on the other. v11 shipped that way: installed from inside the
# proot, env.sh said /root, and a plain Termux shell then failed to make
# $RUNDIR, failed to redirect into it, and never started the app at all.
#
# So the writer block is run here with one home, and the file it produces is
# sourced under two others. The paths must follow whoever sources it, and
# the writer's own home must appear nowhere in the file.
endl=$(grep -n '^} > "\$APPHOME/env.sh.new"$' src/40_main.sh | cut -d: -f1)
startl=$(awk -v e="$endl" 'NR<e && /^\{$/ {l=NR} END {print l}' src/40_main.sh)
if [ -n "$endl" ] && [ -n "$startl" ]; then
  envgen=$(sed -n "$((startl+1)),$((endl-1))p" src/40_main.sh)
  envout=$(MAHA_VERSION=vT BIN=/prefix/bin MAHA_APPS="id|cmd|dir|v1|8080|one|s.py|one" \
    APPHOME=/WRITERHOME/.maha.commute PAYDIR=/WRITERHOME/.maha.commute/payloads \
    KEYDIR=/WRITERHOME/.maha.commute/keys \
    KEYFILE=/WRITERHOME/.maha.commute/keys/google-api.txt \
    STAMPDIR=/WRITERHOME/.maha.commute/installed \
    bash -c "$envgen")
  tf=$(mktemp)
  printf '%s\n' "$envout" > "$tf"
  read_as() { HOME="$1" bash -c ". '$tf'; printf '%s %s %s %s' \
      \"\$APPHOME\" \"\$PAYDIR\" \"\$KEYFILE\" \"\$STAMPDIR\""; }
  eq "env.sh read from the proot side" \
     "/root/.maha.commute /root/.maha.commute/payloads /root/.maha.commute/keys/google-api.txt /root/.maha.commute/installed" \
     "$(read_as /root)"
  eq "env.sh read from the Termux side" \
     "/data/data/com.termux/files/home/.maha.commute /data/data/com.termux/files/home/.maha.commute/payloads /data/data/com.termux/files/home/.maha.commute/keys/google-api.txt /data/data/com.termux/files/home/.maha.commute/installed" \
     "$(read_as /data/data/com.termux/files/home)"
  case "$envout" in
    *WRITERHOME*) bad "env.sh carries the home of the shell that wrote it" ;;
    *) ok ;;
  esac
  rm -f "$tf"
else
  bad "the env.sh writer block was not found in src/40_main.sh"
fi

# =====================================================================
# v17
# =====================================================================

# ---- the phone-only guard, as a truth table -------------------------
# The method that goes into every handler is run against stand-in
# requests. The rule: a credential route answers only when the PEER is the
# phone AND the Host header names the phone. They catch different things:
# the peer stops a device on the wifi, the Host stops a web page in another
# tab that has pointed a name at 127.0.0.1 (binding to loopback does not).
gt=$(python3 - <<'PYEOF'
import sys
sys.path.insert(0, "tools")
import payload_v17 as V
ns = {}
exec("class H:\n" + V._guard_method(("/api-keys", "/gps")), ns)
H = ns["H"]
cases = [
  ("127.0.0.1",    "127.0.0.1:8082",   "/api-keys", False, "the phone itself, by number"),
  ("127.0.0.1",    "localhost:8082",   "/api-keys", False, "the phone itself, by name"),
  ("::1",          "[::1]:8082",       "/gps",      False, "the phone over IPv6"),
  ("192.168.1.20", "192.168.1.5:8082", "/api-keys", True,  "a laptop on the wifi"),
  ("192.168.1.20", "127.0.0.1:8082",   "/api-keys", True,  "a laptop that lies in the Host header"),
  ("127.0.0.1",    "evil.example:8082","/api-keys", True,  "a web page rebinding a name to the phone"),
  ("127.0.0.1",    "",                 "/api-keys", True,  "no Host header fails closed"),
  ("192.168.1.20", "192.168.1.5:8082", "/gps",      True,  "the phone's location is not the wifi's"),
  ("192.168.1.20", "192.168.1.5:8082", "/",         False, "the page stays open to the room"),
  ("192.168.1.20", "192.168.1.5:8082", "/lan-ip",   False, "so does the address line"),
  ("192.168.1.20", "192.168.1.5:8082", "/api-keys/",False, "a different path is another route, not this one"),
]
for peer, host, path, want, label in cases:
    h = H(); h.client_address = (peer, 5555); h.headers = {"Host": host}
    got = h._phone_only(path)
    print(("ok" if got == want else "BAD"), label, "(blocked=%s)" % got)
PYEOF
)
while IFS= read -r l; do case "$l" in ok*) ok ;; *) bad "guard: ${l#BAD }" ;; esac; done <<< "$gt"
eq "the guard truth table ran every case" 11 "$(printf '%s\n' "$gt" | grep -c .)"

# ---- no blur, counted -----------------------------------------------
ALLPAY="src/payloads/39-install-all_commute-termux-v39.sh"
eq "the patched all.commute carries no backdrop-filter" 0 \
   "$(python3 tools/patch_payload.py "$ALLPAY" all | grep -c 'backdrop-filter')"
gd=$(mktemp -d)
cp "$ALLPAY" "$gd/eight.sh"; printf '/* backdrop-filter:blur(3px); */\n' >> "$gd/eight.sh"
python3 tools/patch_payload.py "$gd/eight.sh" all >/dev/null 2>"$gd/eight.err"; rc_is "an eighth blur upstream fails the build" 1 $?
grep -q 'expected 7' "$gd/eight.err" && ok || bad "and says what it expected"
sed '0,/backdrop-filter:blur(4px);/s///' "$ALLPAY" > "$gd/six.sh"
python3 tools/patch_payload.py "$gd/six.sh" all >/dev/null 2>&1; rc_is "a payload with fewer blurs than the count fails too" 1 $?
rm -rf "$gd"

# ---- what each payload says inside is what the menu claims -----------
# A number the menu shows and the app does not answer to is the failure
# versioning.md names: a number that has meant two things cannot be talked about.
claimed() { grep -E "^(APPS=\")?$1:" tools/build_installer.sh | sed 's/^APPS="//' | cut -d: -f3; }
inside_day=$(python3 tools/patch_payload.py src/payloads/13-install-day-commute-termux-v13.sh day | grep -m1 '^COMMUTE_VERSION=' | cut -d'"' -f2)
inside_night=$(python3 tools/patch_payload.py src/payloads/9-night_commute_v9.sh night | grep -m1 '^APP_VERSION = ' | cut -d'"' -f2)
inside_all=$(python3 tools/patch_payload.py "$ALLPAY" all | grep -m1 '^APP_VERSION = ' | cut -d'"' -f2)
eq "day says the number the menu claims"   "$(claimed day)"   "$inside_day"
eq "night says the number the menu claims" "$(claimed night)" "$inside_night"
eq "all says the number the menu claims"   "$(claimed all)"   "$inside_all"

# ---- night keeps what the person owns, and not the Maps key ------------
npay=$(python3 tools/patch_payload.py src/payloads/9-night_commute_v9.sh night)
keepline=$(printf '%s\n' "$npay" | grep -m1 'for _k in ')
for k in gemini-api.txt pdf zet_gtfs.zip zet_gtfs.zip.meta.json; do
  case "$keepline" in *"$k"*) ok ;; *) bad "night does not keep $k" ;; esac
done
case "$keepline" in *gmaps-api.txt*) bad "night must not keep the Maps key: the umbrella store is its source" ;; *) ok ;; esac
eq "the keep happens before the wipe, the restore after" "1 1" \
   "$(printf '%s\n' "$npay" | awk '/KEEP_TMP="\$\(mktemp/{a=NR} /rm -rf "\$HOME\/.nightcommute"/{w=NR} /cp -a "\$KEEP_TMP"/{r=NR} END{print (a<w?1:0), (w<r?1:0)}')"

# ---- the command shim ---------------------------------------------------
# Typing day.commute opens the screen with day focused. The shim must never
# look like the app's own stop verb (the menu greps for "  stop)" and would
# call it), must never overwrite the real launcher with itself, and must fall
# back to the real launcher when the launcher is not there.
sh=$(mktemp -d)
sed -n '/^# BEGIN SHIM/,/^# END SHIM/p' src/30_install_one.sh > "$sh/fn.sh"
[ -s "$sh/fn.sh" ] && ok || bad "the shim writer was not found in src/30_install_one.sh"
(
  BIN="$sh/bin"; APPHOME="$sh/home/.maha.commute"; mkdir -p "$BIN" "$sh/fake"
  printf '#!/bin/sh\necho ORIGINAL "$@"\n' > "$BIN/day.commute"; chmod +x "$BIN/day.commute"
  . "$sh/fn.sh"; write_shim day day.commute
  printf '#!/bin/sh\necho MC "$@"\n' > "$sh/fake/maha-commute"; chmod +x "$sh/fake/maha-commute"
)
S="$sh/bin/day.commute"; O="$sh/home/.maha.commute/orig/day.commute"
run() { HOME="$sh/home" PATH="$sh/fake:$PATH" bash "$S" "$@" 2>&1; }
grep -q '^# MAHA_SHIM day' "$S" && ok || bad "the command is a shim"
eq "the real launcher was kept" "ORIGINAL x" "$(bash "$O" x)"
eq "the shim has no '  stop)' line for the menu to mistake" 0 "$(grep -c '^  stop)' "$S")"
eq "no arguments opens the screen on this app" "MC focus day"   "$(run)"
eq "stop goes to the menu"                      "MC stop day"    "$(run stop)"
eq "status goes to the menu"                    "MC status"      "$(run status)"
eq "restart goes to the menu"                   "MC restart day" "$(run restart)"
eq "open goes to the menu"                      "MC open day"    "$(run open)"
eq "log goes to the menu"                       "MC log day"     "$(run log)"
eq "anything else goes to the real launcher"    "ORIGINAL --odd" "$(run --odd)"
eq "with no launcher screen installed it runs the app itself" "ORIGINAL" "$(HOME="$sh/home" bash "$S" 2>&1)"
mv "$O" "$O.gone"
case "$(HOME="$sh/home" bash "$S" 2>&1)" in *"missing"*) ok ;; *) bad "a missing real launcher is said out loud" ;; esac
mv "$O.gone" "$O"
( BIN="$sh/bin"; APPHOME="$sh/home/.maha.commute"; . "$sh/fn.sh"; write_shim day day.commute )
eq "writing the shim again does not turn the real launcher into the shim" "ORIGINAL y" "$(bash "$O" y)"
printf '#!/bin/sh\necho SECOND "$@"\n' > "$sh/bin/day.commute"; chmod +x "$sh/bin/day.commute"
( BIN="$sh/bin"; APPHOME="$sh/home/.maha.commute"; . "$sh/fn.sh"; write_shim day day.commute )
eq "a reinstalled app becomes the new real launcher" "SECOND z" "$(bash "$O" z)"
grep -q '^# MAHA_SHIM day' "$sh/bin/day.commute" && ok || bad "and the shim is put back over it"
rm -rf "$sh"

# ---- the REAL phone-only lists, read out of the patched payloads --------
# The truth table above proves the rule. This proves the lists the rule is
# given: that every route that hands out a key, spends money or deletes
# something is on the list of each app, and that the open ones are not.
# The second half is the one that matters later: a route added upstream whose
# name says key, gemini, gps, delete or rebuild must be on the list or this
# fails, so a new credential route cannot be open to the wifi by default.
for spec in "day:13-install-day-commute-termux-v13.sh:/update-bus /api-keys /gemini-key /key-status /pdf-sched /pdf-delete" \
            "night:9-night_commute_v9.sh:/gmaps-key /key-status /gemini-key /pdf-delete /pdf-sched /night-rebuild" \
            "all:39-install-all_commute-termux-v39.sh:/api-keys /gemini-key /gemini-test /key-test /gemini-model /gemini-models /gemini-models-old /rebuild /cache/clear /sched-delete /gps"; do
  id=${spec%%:*}; rest=${spec#*:}; file=${rest%%:*}; want=${rest#*:}
  pp=$(python3 tools/patch_payload.py "src/payloads/$file" "$id")
  list=$(printf '%s\n' "$pp" | grep -m1 '_PHONE_ONLY = (')
  [ -n "$list" ] && ok || bad "$id has no phone-only list"
  for r in $want; do case "$list" in *"\"$r\""*) ok ;; *) bad "$id: $r is not phone-only" ;; esac; done
  for r in /version /lan-ip; do case "$list" in *"\"$r\""*) bad "$id: $r must stay open" ;; *) ok ;; esac; done
  routes=$(printf '%s\n' "$pp" | grep -oE '(route|r|u\.path) *== *"/[A-Za-z/_-]+"' | grep -oE '"/[A-Za-z/_-]+"' | tr -d '"' | sort -u)
  for r in $routes; do
    case "$r" in
      *key*|*gemini*|*gps*|*rebuild*|*delete*|*cache*|/pdf-sched|/update-bus)
        case "$list" in *"\"$r\""*) ok ;; *) bad "$id: $r looks like a credential or spend route and is open to the wifi" ;; esac ;;
    esac
  done
done

# ---- v17: the copy page, for the app that has no copy button ------------
# The GitHub website puts a button on every code block. The GitHub APP does
# not, and cuts a long line off at the screen edge. So each README command has
# a card on a generated page with a real button, and a link under the block.
# What could be true while this test passes and the feature is broken: the page
# could hold a DIFFERENT command from the README (a stale copy), a card could
# carry the wrong app's command, or the README could link to a card that is not
# there. Each of those is a failure of its own below.
cp_out=$(python3 - <<'PYEOF'
import html, re, sys
sys.path.insert(0, "tools")
import build_copy_page as B
text = open("README.md", encoding="utf-8").read()
page = open("docs/index.html", encoding="utf-8").read()
want = B.blocks(text)
cards = re.findall(r'<section class="card" id="cmd-(\d+)"><h2>(.*?)</h2><pre>(.*?)</pre>', page, re.S)
def say(ok, what): print(("ok " if ok else "BAD ") + what)
say(len(cards) == len(want) and len(want) >= 5, "one card per command (%d cards, %d commands)" % (len(cards), len(want)))
say([int(c[0]) for c in cards] == list(range(1, len(cards) + 1)), "the cards are numbered 1 to n with no gaps")
for (n, label, body), (wl, wc, _e) in zip(cards, want):
    say(html.unescape(body) == wc, "card %s is the README command, byte for byte" % n)
    say(html.unescape(label) == wl, "card %s carries the README's own label" % n)
by = {html.unescape(l): html.unescape(b) for _n, l, b in cards}
say(by.get("day.commute only", "").endswith("--apps 1"),   "the day card holds the day command")
say(by.get("night.commute only", "").endswith("--apps 2"), "the night card holds the night command")
say(by.get("all.commute only", "").endswith("--apps 3"),   "the all card holds the all command")
say(B.readme_links_ok(text) == [], "every command has a link to its own card under it")
say("navigator.clipboard.writeText" in page and "execCommand('copy')" in page, "the page copies, with an older fallback behind it")
say(re.search(r'<script src=|https?://[^"\']*\.(js|css)', page) is None, "the page loads nothing from anywhere else")
PYEOF
)
while IFS= read -r l; do case "$l" in ok*) ok ;; *) bad "copy page: ${l#BAD }" ;; esac; done <<< "$cp_out"
python3 tools/build_copy_page.py --check >/dev/null 2>&1; rc_is "the copy page is fresh against the README" 0 $?

# Each failure on its own: a stale page, a changed command, a missing link.
cpd=$(mktemp -d); mkdir -p "$cpd/tools" "$cpd/docs"
cp tools/build_copy_page.py "$cpd/tools/"; cp README.md "$cpd/"; cp docs/index.html docs/.nojekyll "$cpd/docs/"
sed -i '0,/--apps 3$/s//--apps 9/' "$cpd/README.md"
python3 "$cpd/tools/build_copy_page.py" --check >/dev/null 2>&1; rc_is "a README command changed and the page not rebuilt is stale" 1 $?
cp README.md "$cpd/README.md"; sed -i '0,/#cmd-3)/s//#cmd-99)/' "$cpd/README.md"
python3 "$cpd/tools/build_copy_page.py" --check >/dev/null 2>&1; rc_is "a link that points at no card fails" 1 $?
cp README.md "$cpd/README.md"; sed -i '/#cmd-4)/d' "$cpd/README.md"
python3 "$cpd/tools/build_copy_page.py" --check >/dev/null 2>&1; rc_is "a command with no link under it fails" 1 $?
rm -rf "$cpd"

# =====================================================================
# v18: the free map, and the key at the top of Settings
# =====================================================================
# CARTO began answering every tile with one picture, "API KEY REQUIRED". What
# could be true while this passes and the map is still blank: a CARTO address
# left in some other style, a default that is not OpenStreetMap, or the picker
# moved but a second copy left behind. Each is checked on its own.
v18=$(python3 - <<'PYEOF'
import re, subprocess
P = {"day": "src/payloads/13-install-day-commute-termux-v13.sh",
     "night": "src/payloads/9-night_commute_v9.sh",
     "all": "src/payloads/39-install-all_commute-termux-v39.sh"}
picker = {"day": "mapsFile", "night": "gmapsFile", "all": "keyFile"}
def say(ok, what): print(("ok " if ok else "BAD ") + what)
for app, f in P.items():
    s = subprocess.run(["python3", "tools/patch_payload.py", f, app], capture_output=True, text=True).stdout
    say("cartocdn" not in s, "%s: no CARTO address anywhere" % app)
    say(s.count('id="%s"' % picker[app]) == 1, "%s: the key picker exists exactly once" % app)
    i = s.find('id="ipLine"'); seg = s[i:i + 5000]
    first = re.search(r'type="file" id="([a-zA-Z]+)"', seg)
    say(bool(first) and first.group(1) == picker[app], "%s: the map key picker is the first one in Settings" % app)
    say("How to get a Google Maps key" in s and "Maps JavaScript API" in s, "%s: the guide to a key is in Settings" % app)
    say("console.cloud.google.com" in s, "%s: the guide says where to go" % app)
a = subprocess.run(["python3", "tools/patch_payload.py", P["all"], "all"], capture_output=True, text=True).stdout
say('const TILE_BASE  = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";' in a, "all: the free map is OpenStreetMap")
say("names = L.layerGroup();" in a, "all: the separate names layer is an empty group, not a CARTO layer")
say("Street View Static API" in a, "all: its guide names the Street View API it also needs")
n = subprocess.run(["python3", "tools/patch_payload.py", P["night"], "night"], capture_output=True, text=True).stdout
say('let MAP_ENGINE = localStorage.getItem("nc_engine") || "osm";' in n, "night: OpenStreetMap is the default engine")
say('osm:  {u:"https://tile.openstreetmap.org/' in n, "night: the default style is OpenStreetMap's own tiles")
say('classList.toggle("osm-dark", k==="dark")' in n and ".osm-dark .leaflet-tile-pane" in n, "night: the dark style is OpenStreetMap darkened, not a second server")
PYEOF
)
while IFS= read -r l; do case "$l" in ok*) ok ;; *) bad "v18: ${l#BAD }" ;; esac; done <<< "$v18"
eq "every v18 map check ran" 21 "$(printf '%s\n' "$v18" | grep -c .)"

# ---- the names Marko types ---------------------------------------------
grep -q 'install_command "$BIN/maha.commute"' src/40_main.sh && ok || bad "the installer writes maha.commute"
grep -q 'install_command "$BIN/maha.commute-update"' src/40_main.sh && ok || bad "the installer writes maha.commute-update"
grep -q 'exec "%s/maha-commute"' src/40_main.sh && ok || bad "maha.commute is the launcher, not a copy of it"
grep -qE '^  update\|-update\|--update\)' src/20_menu.sh && ok || bad "maha.commute -update runs the updater"
grep -q 'maha.commute-update' src/70_uninstall.sh && ok || bad "the uninstaller knows the new names"

# ---- v19: the first day button is called Buzin --------------------------
dp=$(python3 tools/patch_payload.py src/payloads/13-install-day-commute-termux-v13.sh day)
printf '%s' "$dp" | grep -qF '{"id": "to-work", "label": "Buzin",' && ok || bad "day: the to-work direction is labelled Buzin"
printf '%s' "$dp" | grep -qF '"label": "Nova TV"' && bad "day: no direction is labelled Nova TV any more" || ok
printf '%s' "$dp" | grep -qF 'd.label === "Nova TV") ? "Buzin"' && ok || bad "day: an older bus.json still shows Buzin"
printf '%s' "$dp" | grep -qF 'name: "Nova TV",' && ok || bad "day: the corridor near the building keeps its place name"

# ---- v20: one station, one dashboard; day.commute is found by its path ----
ap=$(python3 tools/patch_payload.py src/payloads/39-install-all_commute-termux-v39.sh all)
printf '%s' "$ap" | grep -q 'id="dashBtn"' && bad "all: the DASHBOARD button is gone" || ok
printf '%s' "$ap" | grep -q 'popwrap' && bad "all: the small station window is gone" || ok
printf '%s' "$ap" | grep -qF '.pinid{position:relative;display:block;pointer-events:auto;z-index:1;}' && ok || bad "all: the station label answers a tap"
printf '%s' "$ap" | grep -qF 'clickTolerance: 10' && ok || bad "all: a tap that wobbles is still a tap"
printf '%s' "$ap" | grep -qF '() => armStation(s), on ? 1000 : 500);' && ok || bad "all: a Google-engine pin arms like a Leaflet one"
printf '%s' "$ap" | grep -qF 'preventMapHitsAndGesturesFrom(this.div)' && ok || bad "all: a Google-engine pin does not leak its tap to the map"
printf '%s' "$ap" | grep -qF 'history.pushState({ dash: 1 }' && ok || bad "all: back closes the dashboard"
printf '%s' "$ap" | grep -qF 'APP_VERSION = "v46"' && ok || bad "all: answers v46"
printf '%s' "$ap" | grep -q 'Tap <b>DASHBOARD</b>' && bad "all: nothing tells you to tap a button that is gone" || ok
# the dashboard renders the station that was opened, and only that one
if command -v node >/dev/null 2>&1; then
  J4=$(mktemp)
  {
    printf 'const els={};function el(id){return els[id]||(els[id]={id,textContent:"",innerHTML:"",scrollTop:0,style:{setProperty(){}},classList:{_s:new Set(),add(c){this._s.add(c)},remove(c){this._s.delete(c)},contains(c){return this._s.has(c)}},querySelector(){return null},addEventListener(){}});}\n'
    printf 'global.document={getElementById:el,querySelectorAll:()=>[]};global.window={addEventListener(){}};\n'
    printf 'let SEL=null,WATCH=null,ME=null,API_KEY="",STOPS=[{stop_id:"A",name:"Alpha",dist:50},{stop_id:"B",name:"Beta",dist:90}];\n'
    printf 'const BOARDS={},SV_CACHE={};function esc(x){return String(x)}function fmtDist(m){return m+" m"}function dirAbbr(){return null}\n'
    printf 'function stationColour(){return "#fff"}function starHTML(){return ""}function isWatched(){return false}function arrivalRow(x){return "<row "+x.route+">"}function metres(){return 0}\n'
    printf 'const PALETTE=["#fff"];\n'
    sed -n '/^function subLine(s, b){/,/^}/p' <<<"$ap"
    sed -n '/^function arrHTML(b){/,/^document.getElementById("dClose")/p' <<<"$ap" | sed '$d'
    printf 'SEL=STOPS[1];BOARDS.B={ok:true,feed_ok:true,departures:[{route:"6",passed:false}]};renderDash();\n'
    printf 'console.log(JSON.stringify({id:els.dId.textContent,name:els.dName.textContent,cards:(els.dBody.innerHTML.match(/class="card/g)||[]).length,row:/<row 6>/.test(els.dBody.innerHTML),other:/Alpha/.test(els.dBody.innerHTML)}));\n'
  } > "$J4"
  R4=$(node "$J4" 2>&1); rm -f "$J4"
  eq "the dashboard is the tapped station"     '"id":"B"'    "$(printf '%s' "$R4" | grep -o '"id":"[^"]*"')"
  eq "it carries that station's name"          '"name":"Beta"' "$(printf '%s' "$R4" | grep -o '"name":"[^"]*"')"
  eq "and one card, not one per station"       '"cards":1'   "$(printf '%s' "$R4" | grep -o '"cards":[0-9]*')"
  eq "its arrivals are in it"                  '"row":true'  "$(printf '%s' "$R4" | grep -o '"row":[a-z]*')"
  eq "no other station is in it"               '"other":false' "$(printf '%s' "$R4" | grep -o '"other":[a-z]*')"
else
  printf '  node is not here, so the 5 dashboard checks did not run\n'
fi
dp=$(python3 tools/patch_payload.py src/payloads/13-install-day-commute-termux-v13.sh day)
grep -qF '|/.commute/commute_server.py|' src/00_head.sh && ok || bad "day is found by its path, not a name all.commute shares"
printf '%s' "$dp" | grep -qF 'pkill -f commute_server.py' && bad "day.commute stop cannot kill all.commute" || ok
printf '%s' "$dp" | grep -qF 'if pgrep -f "$SERVER" >/dev/null 2>&1; then' && ok || bad "day.commute status asks about its own server"
printf '%s' "$dp" | grep -qF 'already running${OFF}' && ok || bad "a second day.commute opens the first instead of doubling it"
printf '%s' "$dp" | grep -qF '_mine = _pf.read().strip() == str(port)' && ok || bad "a day server only deletes its own port file"
printf '%s' "$dp" | grep -qF 'COMMUTE_VERSION="v18"' && ok || bad "day answers v18"
# the menu: up is the process AND the port it wrote down
(
  T=$(mktemp -d); HOME="$T"; mkdir -p "$T/.commute"
  app_row(){ printf 'day|day.commute|.commute|v17|8082|x|/.commute/commute_server.py|x'; }
  field(){ printf '%s' "$1" | cut -d'|' -f"$2"; }
  eval "$(sed -n '/^port_live() {/,/^}/p;/^proc_alive() {/,/^}/p;/^running() {/,/^}/p' src/20_menu.sh)"
  # a process called all_commute_server.py is NOT day.commute
  proc_alive(){ [ "$1" = "all_commute_server.py" ]; }
  running day && echo UP1 || echo DOWN1
  # day's process alive but no port written yet: not up
  proc_alive(){ [ "$1" = "/.commute/commute_server.py" ]; }
  running day && echo UP2 || echo DOWN2
  # alive, port written, nothing answering: not up
  echo 1 > "$T/.commute/port"; running day && echo UP3 || echo DOWN3
  rm -rf "$T"
) > /tmp/.mc_run.$$ 2>&1
R5=$(tr '\n' ' ' < /tmp/.mc_run.$$); rm -f /tmp/.mc_run.$$
eq "all.commute running is not day.commute running"  "DOWN1 DOWN2 DOWN3 " "$R5"

# ---- v21: the stations are permanent; the launcher lights one app -------
# The rebuild is the REAL update_all.py, taken out of the patched payload, fed
# a four stop feed. Stop 200 has a departure only on the day of the special
# service, stop 300 only on a ride filed under yesterday (24:10). Before v21
# the index held three stops, then two, and 300 never.
T21=$(mktemp -d)
printf '%s' "$ap" | python3 -c '
import re,sys
s=sys.stdin.read()
for name,tag in (("update_all.py","ALLC_UPDATE_PY"),("all_commute_server.py","ALLC_SERVER_PY")):
    m=re.search(r"cat > \"\$APPDIR/%s\" << \x27%s\x27\n(.*?)\n%s\n"%(re.escape(name),tag,tag),s,re.S)
    open(sys.argv[1]+"/"+name,"w").write(m.group(1)+"\n")' "$T21"
cat > "$T21/mkgtfs.py" <<'PYEOF'
import zipfile, sys, datetime
path, special = sys.argv[1], sys.argv[2] == "1"
t = datetime.date.today(); y = t - datetime.timedelta(days=1)
f = lambda d: d.strftime("%Y%m%d")
files = {
 "stops.txt": "stop_id,stop_name,stop_lat,stop_lon,location_type\n100,Glavni kolodvor,45.8050,15.9800,0\n101,Branimirova,45.8055,15.9810,0\n200,Samo radnim danom,45.8060,15.9790,0\n300,Nocna linija,45.8070,15.9820,\n900,Parent station,45.8052,15.9805,1\n",
 "routes.txt": "route_id,route_short_name,route_long_name\n6,6,Sljeme\n31,31,Nocna\n",
 "trips.txt": "route_id,service_id,trip_id,trip_headsign\n6,DAILY,t1,Sljeme\n6,SPECIAL,t2,Sljeme\n31,NIGHT,t3,Nocna\n",
 "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence\nt1,08:00:00,08:00:00,100,1\nt1,08:05:00,08:05:00,101,2\nt2,09:00:00,09:00:00,200,1\nt2,09:05:00,09:05:00,100,2\nt3,24:10:00,24:10:00,300,1\nt3,24:15:00,24:15:00,100,2\n",
 "calendar_dates.txt": "service_id,date,exception_type\nDAILY,%s,1\n%sNIGHT,%s,1\n" % (f(t), ("SPECIAL,%s,1\n" % f(t)) if special else "", f(y)),
}
with zipfile.ZipFile(path, "w") as z:
    for k, v in files.items(): z.writestr(k, v)
PYEOF
ids21() { python3 -c "import sqlite3,sys;print(' '.join(sorted(r[0] for r in sqlite3.connect(sys.argv[1]).execute('select stop_id from stops'))))" "$T21/network.db"; }
python3 "$T21/mkgtfs.py" "$T21/zet_gtfs.zip" 1
ALLC_FORCE=1 ALLC_DIR="$T21" python3 "$T21/update_all.py" >/dev/null 2>&1
eq "a day with the special service: all four stations" "100 101 200 300" "$(ids21)"
python3 "$T21/mkgtfs.py" "$T21/zet_gtfs.zip" 0
ALLC_FORCE=1 ALLC_DIR="$T21" python3 "$T21/update_all.py" >/dev/null 2>&1
eq "a day without it: the same four, none dropped"     "100 101 200 300" "$(ids21)"
eq "a parent station (location_type 1) is not a station you stand at" "no" "$(ids21 | grep -qw 900 && echo yes || echo no)"
eq "the permanent file holds them too" "4" "$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['stops']))" "$T21/stations.json")"
eq "a quiet stop keeps the way it faces" "yes" "$(python3 -c "import json,sys;b=json.load(open(sys.argv[1]))['stops']['200'][3];print('yes' if b is not None else 'no')" "$T21/stations.json")"
rm -f "$T21/network.db"
eq "the stations survive the index being deleted" "4" "$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['stops']))" "$T21/stations.json")"
# the first rebuild after the update keeps what an OLD index (served stops only) knew
rm -f "$T21/stations.json"
python3 - "$T21" <<'PYEOF'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1] + "/network.db")
c.execute("create table stops(stop_id text primary key, name text, lat real, lon real, bearing real)")
c.execute("create table dep(stop_id text, t int, trip_id text, route text, head text)")
c.execute("insert into stops values('999','Old and gone',45.0,15.0,90.0)")
c.commit()
PYEOF
ALLC_FORCE=1 ALLC_DIR="$T21" python3 "$T21/update_all.py" >/dev/null 2>&1
eq "an old index's stops are taken in, not lost" "100 101 200 300 999" "$(ids21)"
# every station ships inside the app, so the first screen needs no download
eq "the stations seed carries every platform" "yes" "$(python3 -c "
import json;d=json.load(open('src/payloads/stations_seed.json'))['stops']
ok=len(d)>2400 and all(45.3<v[1]<46.3 and 15.3<v[2]<16.7 for v in d.values()) and '236_10' not in d
print('yes' if ok else 'no')")"
printf '%s' "$ap" | grep -qF "putting every station on the phone" && ok || bad "all: the installer puts the seed on the phone"
printf '%s' "$ap" | grep -qF 'raise ValueError("outside the Zagreb area")' && ok || bad "all: a stop with coordinates far from Zagreb is dropped"
printf '%s' "$ap" | grep -qF 'def stations_ready():' && ok || bad "all: /stops works from the file when the index is gone"
rm -rf "$T21"

# the launcher: a number lights an app, 0 is the launcher, u follows what runs
if command -v python3 >/dev/null 2>&1; then
  R21=$(python3 -u tests/test5_launcher.py 2>&1)
  np=$(printf '%s\n' "$R21" | grep -c '^PASS'); nf=$(printf '%s\n' "$R21" | grep -c '^FAIL')
  pass=$((pass+np)); fail=$((fail+nf))
  printf '%s\n' "$R21" | grep '^FAIL' || true
  [ "$np" -ge 11 ] && ok || bad "the launcher screen test ran (only $np checks)"
fi
grep -q '^  --app)' src/60_update.sh 2>/dev/null; grep -q -- '--app)' src/60_update.sh && ok || bad "the updater can aim at one app"

printf '\n  %s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" = "0" ]
