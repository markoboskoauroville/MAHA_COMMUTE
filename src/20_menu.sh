#!/data/data/com.termux/files/usr/bin/bash
# maha-commute, the launcher. Written by the installer.
#
# Midnight Commander, and the debt is deliberate. What is lifted is not the
# look, it is the way mc lets a pair of panels share one set of keys.
#
# FOUR QUADRANTS, one app each. A quadrant is empty when its app is not
# running and empty when there is no app for it at all: the fourth is free
# and stays drawn, because a slot that appears when a fourth app arrives is
# a screen that moves under the hand. Nothing appears, nothing disappears.
#
#   +-----------------+-----------------+
#   | 1 day.commute   | 2 night.commute |
#   +-----------------+-----------------+
#   | 3 all.commute   | 4 free          |
#   +-----------------+-----------------+
#
# 1 2 3 4 FILL a quadrant. An empty quadrant is an app that is not running,
# so pressing its number starts that server and the quadrant fills in front
# of you. Pressing the number of a quadrant that is already filled opens its
# page again. The number means one thing in both cases: put me in this app.
#
# The label is drawn whether the quadrant is filled or not, so the number
# never has to be looked up. 1 is always day.commute, on this phone and on
# every other one.
#
# THE VERBS ARE THE SAME FOR EVERY QUADRANT and they act on the focused one.
# That is the whole point: one set of keys, learned once, and the only thing
# that changes is which app is listening.
#
#   Enter  open it, starting it first if it is not running
#   o      open the page again, for when the tab was closed
#   s      stop it
#   R      restart it
#   l      its log, the last twenty lines in its own words
#   i      install it, or remove it if it is here
#
# SERVERS STACK. Starting one does not take the terminal and does not stop
# another. All three can run at once: they hold 8082, 8087 and 8084.
#
# The bottom row is the things that belong to no single app, and it is
# always the same ten slots in the same order, dim when they do not apply.

. "$HOME/.maha.commute/env.sh" 2>/dev/null || {
  printf 'maha-commute: ~/.maha.commute/env.sh is missing.\n'
  printf 'Run the installer again.\n'; exit 1; }

if [ -t 1 ]; then
  AM="\033[38;5;214m"; SAND="\033[38;5;223m"; OK="\033[1;32m"
  BAD="\033[1;31m"; KEY="\033[1;37m"; DIM="\033[0;90m"
  BAR="\033[48;5;24m\033[1;37m"; OFF="\033[0m"
else
  AM=""; SAND=""; OK=""; BAD=""; KEY=""; DIM=""; BAR=""; OFF=""
fi

RUNDIR="$APPHOME/running"; mkdir -p "$RUNDIR"
# One id per launcher session. The page compares it with the one it stored
# and clears what you picked when they differ, which is what makes a new
# run start clean instead of where you left off.
RUN=$(date +%s)
PY="$(command -v python3 || command -v python)"
SEL=1
LAST=""

STTY_SAVED=""
restore_tty() { [ -n "$STTY_SAVED" ] && stty "$STTY_SAVED" 2>/dev/null || true; }
trap 'restore_tty' EXIT INT TERM HUP
STTY_SAVED=$(stty -g 2>/dev/null || true)

field()   { printf '%s' "$1" | cut -d'|' -f"$2"; }
app_row() { printf '%s\n' "$MAHA_APPS" | grep "^$1|" || true; }
app_ids() { printf '%s\n' "$MAHA_APPS" | cut -d'|' -f1; }
app_at()  { app_ids | sed -n "${1}p"; }
n_apps()  { app_ids | wc -l | tr -d ' '; }

is_installed() { local c; c=$(field "$(app_row "$1")" 2); [ -n "$c" ] && [ -x "$BIN/$c" ]; }
stamped()      { if [ -f "$STAMPDIR/$1" ]; then tr -d ' \n' < "$STAMPDIR/$1"; else printf '?'; fi; }
# A plain connect in a subshell, which is what v1 shipped and what Test 1
# exercises. The "hardened" version wrapped this in `timeout 1 bash -c` and
# that is what hung the panel: the wrapper child inherits the terminal, and
# killing the wrapper does not always close what it left open. A deadline
# that introduces a process is not a deadline, it is another thing to wait
# for. Connect only, never read, so there is nothing to wait on.
port_live() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && exec 3<&- && return 0
  return 1
}

# The process first, the socket second, because asking the process table is
# local and cannot block on anything. pgrep is not everywhere, so ps is the
# fallback rather than an assumption: without this the socket probe is on
# the hot path of every redraw.
proc_alive() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f "$1" >/dev/null 2>&1
  else
    ps -eo args 2>/dev/null | grep -v grep | grep -qF "$1"
  fi
}

# The port an app actually bound, which is not always the one it wanted:
# each of the three walks forward when its first choice is busy. The file
# the server writes is the truth; the table is only the fallback.
app_port() {
  local row dir p
  row=$(app_row "$1"); dir="$HOME/$(field "$row" 3)"
  # The file is tested before it is read. A redirection from a file that is
  # not there is bash's error to print, not the command's to swallow, so
  # 2>/dev/null on the read does not stop it landing in the middle of the
  # frame. Checking first is the only thing that does.
  p=""
  [ -f "$dir/port" ] && p=$(tr -d ' \n' < "$dir/port" 2>/dev/null)
  if [ -n "$p" ]; then printf '%s' "$p"; else field "$row" 5; fi
}

running() {
  local proc; proc=$(field "$(app_row "$1")" 7)
  proc_alive "$proc" && return 0
  port_live "$(app_port "$1")"
}

# am first, and its OUTPUT read rather than its exit code, because asking
# for a package that is not installed prints an error and still exits zero.
open_url() {
  local url="$1" out pkg
  for pkg in com.android.chrome com.chrome.beta com.chrome.dev; do
    out=$(am start -a android.intent.action.VIEW -d "$url" -p "$pkg" 2>&1)
    case "$out" in
      *rror*|*xception*|*"not found"*|*"unable to resolve"*) : ;;
      *) return 0 ;;
    esac
  done
  command -v termux-open-url >/dev/null 2>&1 && { termux-open-url "$url"; return 0; }
  command -v xdg-open >/dev/null 2>&1 && { xdg-open "$url" >/dev/null 2>&1; return 0; }
  command -v open >/dev/null 2>&1 && { open "$url" >/dev/null 2>&1; return 0; }
  printf "  %s\n" "$url"
}

anykey() {
  printf "\n  ${DIM}%s${OFF} " "${1:-any key}"
  read -rsn1 _x 2>/dev/null || read -r _x
  printf "\n"
}

offer_install() {
  local id="$1" cmd a; cmd=$(field "$(app_row "$id")" 2)
  printf "\n  ${SAND}%s is not installed.${OFF}\n" "$cmd"
  printf "  ${DIM}its payload is already here, so this needs no download${OFF}\n"
  printf "\n  ${KEY}Enter${OFF} ${DIM}install${OFF}   ${KEY}n${OFF} ${DIM}leave it${OFF}\n\n  ${AM}>${OFF} "
  IFS= read -r a || a="n"
  case "$a" in [nN]*) return 0 ;; esac
  bash "$APPHOME/install-one.sh" "$id" --offline || true
  anykey
}

start_app() {
  local id="$1" cmd port i last shown=""
  cmd=$(field "$(app_row "$id")" 2)
  if ! is_installed "$id"; then offer_install "$id"; return; fi
  if running "$id"; then LAST="$id"; open_url "http://127.0.0.1:$(app_port "$id")/?run=$RUN"; return; fi

  printf "\n  ${DIM}starting %s${OFF}\n" "$cmd"

  # setsid and </dev/null. The app gets its own session and no terminal, so
  # it cannot compete with this menu for a keypress and it does not die when
  # the menu is quit. Inheriting the terminal is how a backgrounded server
  # ends up eating the key you pressed for something else.
  ( cd "$HOME" && setsid nohup "$BIN/$cmd" </dev/null > "$RUNDIR/$id.log" 2>&1 &
    echo $! > "$RUNDIR/$id.pid" ) 2>/dev/null ||
  ( cd "$HOME" && nohup "$BIN/$cmd" </dev/null > "$RUNDIR/$id.log" 2>&1 &
    echo $! > "$RUNDIR/$id.pid" )

  # A FIRST start is not a restart. day.commute fetches an eleven megabyte
  # schedule from ZET and builds its caches before it binds anything, which
  # on a phone on mobile data is minutes. The old wait here was sixteen
  # seconds, so it announced failure while the app was still working, and
  # the app opened its own browser tab in the meantime. That is the whole
  # bug: a tab with nothing behind it yet, and a menu saying it did not
  # come up.
  #
  # So the wait is long, it says how long it has been, it shows the app's
  # own last line, and a keypress leaves it running rather than killing it.
  printf "  ${DIM}first start builds the schedule, this can take minutes${OFF}\n"
  printf "  ${DIM}any key to leave it working and go back${OFF}\n\n"
  for i in $(seq 1 450); do
    running "$id" && break
    if [ $((i % 5)) = 0 ]; then
      last=$(tail -1 "$RUNDIR/$id.log" 2>/dev/null | tr -d '\r' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' | cut -c1-40)
      [ -n "$last" ] && [ "$last" != "$shown" ] && { printf "  ${DIM}%s${OFF}\n" "$last"; shown="$last"; }
      printf "\r  ${AM}%ss${OFF}${DIM} waiting for port %s${OFF}   " "$((i * 2 / 5))" "$(app_port "$id")"
    fi
    # A key means stop waiting, not stop the app.
    if read -rsn1 -t 0.4 _k 2>/dev/null; then
      printf "\n\n  ${SAND}left working in the background.${OFF}\n"
      printf "  ${DIM}the quadrant fills when it answers${OFF}\n"
      sleep 1; return
    fi
  done
  printf "\r                                                  \r"

  if running "$id"; then
    port=$(app_port "$id"); LAST="$id"
    printf "  ${OK}up${OFF} ${DIM}on %s${OFF}\n" "$port"
    open_url "http://127.0.0.1:$port/?run=$RUN"
    sleep 1
  else
    printf "  ${BAD}%s has not answered in three minutes${OFF}\n" "$cmd"
    printf "  ${DIM}it may still be working. Its own words:${OFF}\n\n"
    tail -6 "$RUNDIR/$id.log" 2>/dev/null | sed 's/^/    /'
    printf "\n  ${DIM}%s${OFF}\n" "$RUNDIR/$id.log"
    anykey
  fi
}

stop_app() {
  local id="$1" cmd proc
  cmd=$(field "$(app_row "$id")" 2); proc=$(field "$(app_row "$id")" 7)
  if ! running "$id"; then printf "  ${DIM}%s is not running${OFF}\n" "$cmd"; return; fi
  # Its own launcher first where it has a stop verb, because it knows what
  # else it started. Then the process name, for the ones that do not.
  grep -q '^  stop)' "$BIN/$cmd" 2>/dev/null && "$BIN/$cmd" stop >/dev/null 2>&1
  pkill -f "$proc" 2>/dev/null
  [ -f "$RUNDIR/$id.pid" ] && kill "$(cat "$RUNDIR/$id.pid")" 2>/dev/null
  rm -f "$RUNDIR/$id.pid"
  sleep 1
  if running "$id"; then
    printf "  ${BAD}%s would not stop${OFF}\n" "$cmd"
  else
    printf "  ${OK}%s stopped${OFF}\n" "$cmd"
    [ "$LAST" = "$id" ] && LAST=""
  fi
}

stop_all() {
  printf "\n"
  local id any=0
  for id in $(app_ids); do running "$id" && { stop_app "$id"; any=1; }; done
  [ "$any" = 0 ] && printf "  ${DIM}nothing was running${OFF}\n"
  anykey
}

# ---------------------------------------------------------------
# the grid
#
# Four quadrants, two by two, one app each. A quadrant that holds no app
# is drawn empty rather than left out, because the grid is the map: the
# fourth is where the next app goes, and its frame being there already is
# what makes that true rather than a plan.
#
# 1 2 3 4 move the focus. The focused quadrant is lit and EVERY command
# below acts on it. The commands do not change from one app to the next,
# on purpose: the same key does the same thing whichever quadrant is lit,
# so the fingers learn it once. That is worth more than giving each app
# its own clever key.
#
# Colour is padded AFTER the string is sized. printf counts an escape
# sequence as characters, so colouring first and padding second makes
# every coloured cell nine columns narrower than its neighbour, and the
# frame stops being a frame.
# ---------------------------------------------------------------
CW=22

pad() { printf '%-*.*s' "$CW" "$CW" "$1"; }

cell_lines() {
  # Three lines for one quadrant, plain text, into L1 L2 L3.
  local n="$1" id row cmd ver
  id=$(app_at "$n")
  if [ -z "$id" ]; then
    L1=" $n  free"; L2="   for the next app"; L3=""; CQ="dim"; return
  fi
  row=$(app_row "$id"); cmd=$(field "$row" 2)
  if ! is_installed "$id"; then
    L1=" $n $cmd"; L2="   not installed"; L3="   i puts it here"; CQ="dim"
  elif running "$id"; then
    ver=$(stamped "$id")
    L1=" $n $cmd"
    L2="   running  $(app_port "$id")"
    if [ "$LAST" = "$id" ]; then L3="   $ver  last opened"; else L3="   $ver"; fi
    CQ="ok"
  else
    L1=" $n $cmd"; L2="   ready"; L3="   $(stamped "$id")"; CQ="sand"
  fi
}

paint() {
  case "$1" in
    ok)   printf '%b%s%b' "$OK" "$2" "$OFF" ;;
    sand) printf '%b%s%b' "$SAND" "$2" "$OFF" ;;
    dim)  printf '%b%s%b' "$DIM" "$2" "$OFF" ;;
    bar)  printf '%b%s%b' "$BAR" "$2" "$OFF" ;;
    *)    printf '%s' "$2" ;;
  esac
}

row_pair() {
  # Two quadrants side by side. Left is $1, right is $2.
  local a="$1" b="$2" al1 al2 al3 ac bl1 bl2 bl3 bc
  cell_lines "$a"; al1=$(pad "$L1"); al2=$(pad "$L2"); al3=$(pad "$L3"); ac="$CQ"
  cell_lines "$b"; bl1=$(pad "$L1"); bl2=$(pad "$L2"); bl3=$(pad "$L3"); bc="$CQ"
  local at="$ac" bt="$bc"
  [ "$FOCUS" = "$a" ] && at="bar"
  [ "$FOCUS" = "$b" ] && bt="bar"
  printf "  ${AM}|${OFF}%s${AM}|${OFF}%s${AM}|${OFF}\n" "$(paint "$at" "$al1")" "$(paint "$bt" "$bl1")"
  printf "  ${AM}|${OFF}%s${AM}|${OFF}%s${AM}|${OFF}\n" "$(paint "$ac" "$al2")" "$(paint "$bc" "$bl2")"
  printf "  ${AM}|${OFF}%s${AM}|${OFF}%s${AM}|${OFF}\n" "$(paint "$ac" "$al3")" "$(paint "$bc" "$bl3")"
}

rule() { printf "  ${AM}+----------------------+----------------------+${OFF}\n"; }

fkey() {
  if [ "$4" = 1 ]; then
    printf "${DIM}%s${OFF}${KEY}%s${OFF}${SAND}%-7s${OFF}" "$1" "$2" "$3"
  else
    printf "${DIM}%s%s%-7s${OFF}" "$1" "$2" "$3"
  fi
}

W=21   # inner width of one quadrant, so two of them plus the rules fit a
       # phone terminal at about fifty columns. Measured, not guessed.

# Padding is done on the PLAIN text and the colour wrapped around it
# afterwards. printf counts the bytes of an escape sequence as width, so a
# coloured string handed to %-21s comes out short by exactly the length of
# the escapes, and every rule on the right hand side walks left.
pad() { printf "%-${W}.${W}s" "$1"; }

uptime_of() {
  local id="$1" pidf="$RUNDIR/$1.pid" s
  [ -f "$pidf" ] || { printf ''; return; }
  s=$(( $(date +%s) - $(date -r "$pidf" +%s 2>/dev/null || date +%s) ))
  if   [ "$s" -lt 60 ];   then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%dm' "$((s/60))"
  else printf '%dh' "$((s/3600))"; fi
}

# One quadrant's three lines, as plain text, into q1 q2 q3.
cell() {
  local slot="$1" id cmd
  id=$(app_at "$slot")
  if [ -z "$id" ]; then
    q1=$(printf '%d free' "$slot"); q2=''; q3='room for a fourth'
    qstate='empty'; return
  fi
  cmd=$(field "$(app_row "$id")" 2)
  q1=$(printf '%d %s' "$slot" "$cmd")
  q3=$(field "$(app_row "$id")" 8)
  if ! is_installed "$id"; then
    q2='not installed'; qstate='absent'
  elif running "$id"; then
    q2=$(printf '%s  %s  %s' "$(stamped "$id")" "$(app_port "$id")" "$(uptime_of "$id")")
    qstate='running'
  else
    q2=$(printf '%s  ready' "$(stamped "$id")")
    qstate='ready'
  fi
}

# A quadrant is drawn by its state and by whether it has the focus. Colour
# carries the state and nothing else: green is running, sand is installed
# and idle, grey is not here. The focus is a bar, which is a different
# channel, so the two can be read at once.
paint() {
  local text="$1" state="$2" focused="$3"
  if [ "$focused" = 1 ]; then printf "${BAR}%s${OFF}" "$(pad "$text")"; return; fi
  case "$state" in
    running) printf "${OK}%s${OFF}" "$(pad "$text")" ;;
    ready)   printf "${SAND}%s${OFF}" "$(pad "$text")" ;;
    *)       printf "${DIM}%s${OFF}" "$(pad "$text")" ;;
  esac
}

rule() { printf "  ${AM}+"; printf -- '-%.0s' $(seq 1 $W); printf "+"; printf -- '-%.0s' $(seq 1 $W); printf "+${OFF}\n"; }

quad_row() {
  local left="$1" right="$2" l1 l2 l3 r1 r2 r3 ls rs lf rf
  cell "$left";  l1="$q1"; l2="$q2"; l3="$q3"; ls="$qstate"
  cell "$right"; r1="$q1"; r2="$q2"; r3="$q3"; rs="$qstate"
  lf=0; rf=0
  [ "$SEL" = "$left" ] && lf=1
  [ "$SEL" = "$right" ] && rf=1
  printf "  ${AM}|${OFF}%b${AM}|${OFF}%b${AM}|${OFF}\n" \
    "$(paint "$l1" "$ls" "$lf")" "$(paint "$r1" "$rs" "$rf")"
  printf "  ${AM}|${OFF}${DIM}%s${OFF}${AM}|${OFF}${DIM}%s${OFF}${AM}|${OFF}\n" \
    "$(pad "  $l2")" "$(pad "  $r2")"
  printf "  ${AM}|${OFF}${DIM}%s${OFF}${AM}|${OFF}${DIM}%s${OFF}${AM}|${OFF}\n" \
    "$(pad "  $l3")" "$(pad "  $r3")"
}

draw() {
  clear 2>/dev/null || true
  local id any_run=0 sel_id sel_run=0 sel_inst=0
  printf "\n  ${KEY}MAHA COMMUTE${OFF} ${DIM}%s${OFF}\n" "$MAHA_VERSION"
  rule; quad_row 1 2; rule; quad_row 3 4; rule

  sel_id=$(app_at "$SEL")
  [ -n "$sel_id" ] && { running "$sel_id" && sel_run=1; is_installed "$sel_id" && sel_inst=1; }
  for id in $(app_ids); do running "$id" && any_run=1; done

  # The verbs, which act on whichever quadrant has the focus.
  if [ -z "$sel_id" ]; then
    printf "  ${DIM}quadrant 4 is free. The verbs wait for an app.${OFF}\n\n"
  else
    printf "  ${DIM}on ${OFF}${KEY}%s${OFF}${DIM}:${OFF}  " "$(field "$(app_row "$sel_id")" 2)"
    if [ "$sel_inst" != 1 ]; then
      printf "${KEY}Enter${OFF}${SAND}=install${OFF}${DIM}  open stop restart log${OFF}"
    elif [ "$sel_run" = 1 ]; then
      printf "${KEY}Enter${OFF}${SAND}=open${OFF}  ${KEY}s${OFF}${SAND}top${OFF}  ${KEY}R${OFF}${SAND}estart${OFF}  ${KEY}l${OFF}${SAND}og${OFF}"
    else
      printf "${KEY}Enter${OFF}${SAND}=start${OFF}${DIM}  stop restart${OFF}  ${KEY}l${OFF}${SAND}og${OFF}"
    fi
    printf "\n\n"
  fi
  # Every label is spelled by its own key: r efresh, c heck, w ipe. A key
  # whose letter does not begin its word has to be read rather than
  # recognised, and this row is meant to be recognised.
  printf "  "; fkey 1 h "elp" 1; fkey 2 r "efresh" 1; fkey 3 c "heck" 1
  fkey 4 t "est" 1; fkey 5 i "nstall" 1; printf "\n  "
  fkey 6 u "pdate" 1; fkey 7 k "ey" 1; fkey 8 S "topAll" "$any_run"
  fkey 9 w "ipe" 1; fkey 0 q "uit" 1; printf "\n"
  printf "\n  ${DIM}1 2 3 4 fill a quadrant, arrows move without starting${OFF}\n"
  printf "  ${AM}>${OFF} "
}

screen_log() {
  local id="$1" f="$RUNDIR/$1.log"
  clear 2>/dev/null || true
  printf "\n  ${KEY}%s${OFF} ${DIM}in its own words${OFF}\n\n" "$(field "$(app_row "$id")" 2)"
  if [ -s "$f" ]; then
    tail -20 "$f" | cut -c1-46 | sed 's/^/  /'
  else
    printf "  ${DIM}nothing yet. It writes here when it is started from${OFF}\n"
    printf "  ${DIM}this launcher.${OFF}\n"
  fi
  anykey
}

# The panel says what is running. This says what is HERE: where each app
# keeps its data, how big it has grown, whether the payloads still match
# their checksums and whether a key is stored. It reads the disk and the
# local ports and nothing else.
screen_info() {
  local id row cmd dir port
  printf "\n  ${KEY}WHAT IS ON THIS PHONE${OFF}\n\n"
  for id in $(app_ids); do
    row=$(app_row "$id"); cmd=$(field "$row" 2)
    dir="$HOME/$(field "$row" 3)"; port=$(app_port "$id")
    printf "  ${SAND}%s${OFF}\n" "$cmd"
    if is_installed "$id"; then
      printf "    ${DIM}command  ${OFF}${OK}%s${OFF}\n" "$BIN/$cmd"
    else
      printf "    ${DIM}command  not installed${OFF}\n"
    fi
    if [ -d "$dir" ]; then
      printf "    ${DIM}data     %s, %s${OFF}\n" "$dir" "$(du -sh "$dir" 2>/dev/null | cut -f1)"
    else
      printf "    ${DIM}data     none yet${OFF}\n"
    fi
    if port_live "$port"; then
      printf "    ${DIM}port     ${OFF}${OK}%s answering${OFF}\n" "$port"
    else
      printf "    ${DIM}port     %s quiet${OFF}\n" "$port"
    fi
  done
  printf "\n  ${SAND}the umbrella${OFF}\n"
  printf "    ${DIM}payloads %s${OFF}\n" "$PAYDIR"
  if command -v sha256sum >/dev/null 2>&1 && [ -f "$PAYDIR/SHA256SUMS" ]; then
    if ( cd "$PAYDIR" && sha256sum -c --status SHA256SUMS 2>/dev/null ); then
      printf "    ${DIM}checked  ${OFF}${OK}all three match${OFF}\n"
    else
      printf "    ${DIM}checked  ${OFF}${BAD}a payload does not match its checksum${OFF}\n"
    fi
  else
    printf "    ${DIM}checked  no sha256sum here, sizes only${OFF}\n"
  fi
  if [ -s "$KEYFILE" ]; then
    printf "    ${DIM}key      present, %s characters${OFF}\n" \
      "$(tr -d ' \r\n' < "$KEYFILE" | wc -c | tr -d ' ')"
  else
    printf "    ${DIM}key      none${OFF}\n"
  fi
  printf "\n"
}

screen_help() {
  clear 2>/dev/null || true
  cat <<'HELPTEXT'

  MAHA COMMUTE

  Four quadrants, one app each. The fourth is free and stays
  drawn, so the screen does not move when a fourth app arrives.

  1 2 3 4 fill a quadrant. An empty quadrant is a server that
  is not running, so its number starts it and the quadrant
  fills. If it is already filled, the number opens its page.

  Arrows move between quadrants without starting anything,
  for when you want to look before you press.

  The verbs are the same for every quadrant and act on the
  focused one, which is the whole point: one set of keys.

      Enter  open it, starting it first if it is not running
      o      open the page again
      s      stop it
      R      restart it
      l      its log, the last twenty lines
      i      install it, or remove it if it is here

  Servers stack: start all three and all three keep running,
  on 8082, 8087 and 8084.

  The bottom row is always the same ten keys, dim when they do
  not apply. Press the letter. The number is only there because
  a phone has no F keys.

      h  this
      r  refresh every ZET stream, then check it
      c  check the streams without refreshing
      t  test every key this phone holds
      i  install or remove an app
      u  update from a newer installer file
      k  the shared google key
      S  stop all of them
      x  uninstall, which asks twice
      q  quit the menu, leaving the servers running

  Quitting does not stop anything. The servers keep serving and
  the pages stay open. S is what stops them.

HELPTEXT
  anykey
}

screen_install() {
  local id a cmd n
  while :; do
    clear 2>/dev/null || true
    printf "\n  ${KEY}INSTALL OR REMOVE${OFF}\n"
    printf "  ${DIM}a number adds it if missing, takes it away if here${OFF}\n\n"
    n=0
    for id in $(app_ids); do
      n=$((n+1))
      if is_installed "$id"; then
        printf "  ${KEY}%s${OFF}  ${OK}[x]${OFF} ${SAND}%-15s${OFF} ${DIM}%s${OFF}\n" \
          "$n" "$(field "$(app_row "$id")" 2)" "$(stamped "$id")"
      else
        printf "  ${KEY}%s${OFF}  ${DIM}[ ] %-15s not installed${OFF}\n" \
          "$n" "$(field "$(app_row "$id")" 2)"
      fi
    done
    printf "\n  ${KEY}a${OFF} ${DIM}all three${OFF}   ${KEY}q${OFF} ${DIM}back${OFF}\n\n  ${AM}>${OFF} "
    read -rsn1 a 2>/dev/null || read -r a
    printf "\n"
    case "$a" in
      1|2|3)
        id=$(app_at "$a")
        if is_installed "$id"; then
          running "$id" && stop_app "$id"
          cmd=$(field "$(app_row "$id")" 2)
          rm -f "$BIN/$cmd" "$STAMPDIR/$id"
          printf "  ${SAND}%s removed. Its data is untouched.${OFF}\n" "$cmd"
          anykey
        else
          bash "$APPHOME/install-one.sh" "$id" --offline || true; anykey
        fi ;;
      a|A) for id in $(app_ids); do
             is_installed "$id" || bash "$APPHOME/install-one.sh" "$id" --offline || true
           done; anykey ;;
      q|Q|"") return 0 ;;
    esac
  done
}

screen_key() {
  local a k
  clear 2>/dev/null || true
  printf "\n  ${KEY}GOOGLE KEY${OFF}\n"
  printf "  ${DIM}one key, shared by all three, never printed${OFF}\n\n"
  if [ -s "$KEYFILE" ]; then
    printf "  ${OK}present${OFF} ${DIM}%s characters${OFF}\n" \
      "$(tr -d ' \r\n' < "$KEYFILE" | wc -c | tr -d ' ')"
  else
    printf "  ${DIM}none stored${OFF}\n"
  fi
  printf "\n  ${KEY}Enter${OFF} ${DIM}back${OFF}  ${KEY}p${OFF} ${DIM}paste one${OFF}  ${KEY}x${OFF} ${DIM}forget it${OFF}\n\n  ${AM}>${OFF} "
  IFS= read -r a || a=""
  case "$a" in
    p|P) printf "\n  ${DIM}paste, then Enter${OFF}\n  ${AM}>${OFF} "
         IFS= read -r k || k=""
         k=$(printf '%s' "$k" | tr -cd 'A-Za-z0-9_.-' | head -c 200)
         if [ -n "$k" ]; then
           mkdir -p "$KEYDIR"; printf '%s\n' "$k" > "$KEYFILE"; chmod 600 "$KEYFILE"
           printf "\n  ${OK}stored${OFF}\n"
         else
           printf "\n  ${DIM}nothing was changed${OFF}\n"
         fi
         anykey ;;
    x|X) rm -f "$KEYFILE"; printf "\n  ${SAND}forgotten here${OFF}\n"; anykey ;;
  esac
}

case "${1:-}" in
  day|night|all)  start_app "$1"; exit 0 ;;
  stop)           if [ -n "${2:-}" ]; then stop_app "$2"; else stop_all; fi; exit 0 ;;
  # status draws the panel once and leaves. It asks the disk and the local
  # ports and nothing else: a question about what is installed must never
  # reach the network. This case was lost in a rewrite once, which turned
  # `maha-commute status` into an interactive session reading from whatever
  # stdin happened to be, so it is tested now rather than trusted.
  status)         draw; printf "\n"; exit 0 ;;
  info)           screen_info; exit 0 ;;
  install|add)    screen_install; exit 0 ;;
  key)            screen_key; exit 0 ;;
  keytest|keys)   exec "$PY" "$APPHOME/keytest.py" ;;
  refresh)        exec "$PY" "$APPHOME/stream.py" refresh --check ;;
  check|doctor)   exec "$PY" "$APPHOME/stream.py" check ;;
  update)         exec bash "$APPHOME/update.sh" ;;
  uninstall|wipe) exec bash "$APPHOME/uninstall.sh" ;;
  -h|--help)
    printf 'maha-commute [day|night|all|status|info|stop [app]|install|key|keytest|refresh|check|update|uninstall]\n'
    exit 0 ;;
esac

FOCUS=1
while :; do
  draw
  # End of input is not a keypress. Reading EOF used to leave c empty, which
  # matched the Enter case and started an app, so piping anything into the
  # launcher launched something. EOF means the person is gone: leave.
  if ! read -rsn1 c 2>/dev/null; then
    if ! read -r c 2>/dev/null; then printf "\n\n"; exit 0; fi
  fi
  # An arrow arrives as escape, bracket, letter. The two extra reads carry a
  # timeout so Escape on its own does not hang here waiting for the rest of
  # a sequence that is never coming.
  if [ "$c" = "$(printf '\033')" ]; then
    read -rsn1 -t 0.05 c2 2>/dev/null || c2=""
    read -rsn1 -t 0.05 c3 2>/dev/null || c3=""
    case "$c2$c3" in
      "[A"|"[D") c="prev" ;; "[B"|"[C") c="next" ;; *) c="esc" ;;
    esac
  fi
  SELAPP=$(app_at "$SEL")
  case "$c" in
    # A number goes to its quadrant AND fills it. An empty quadrant is a
    # server that is not running, so pressing its number starts it; a
    # quadrant that is already filled opens its page again. One meaning for
    # the number, whatever state the quadrant is in: put me in this app.
    1|2|3|4)
      SEL="$c"
      NEW=$(app_at "$SEL")
      [ -n "$NEW" ] && start_app "$NEW" ;;
    prev) SEL=$((SEL-1)); [ "$SEL" -lt 1 ] && SEL=4 ;;
    next) SEL=$((SEL+1)); [ "$SEL" -gt 4 ] && SEL=1 ;;

    # the verbs, on the focused quadrant
    "")  [ -n "$SELAPP" ] && start_app "$SELAPP" ;;
    o|O) [ -n "$SELAPP" ] && { if running "$SELAPP"; then
           LAST="$SELAPP"; open_url "http://127.0.0.1:$(app_port "$SELAPP")/?run=$RUN"
         else start_app "$SELAPP"; fi; } ;;
    s)   [ -n "$SELAPP" ] && { printf "\n"; stop_app "$SELAPP"; sleep 1; } ;;
    R)   [ -n "$SELAPP" ] && { printf "\n"; stop_app "$SELAPP"; start_app "$SELAPP"; } ;;
    l|L) [ -n "$SELAPP" ] && screen_log "$SELAPP" ;;

    # the things that belong to no single app
    h|H) screen_help ;;
    r)   printf "\n"; "$PY" "$APPHOME/stream.py" refresh --check; anykey ;;
    c|C|d|D) printf "\n"; "$PY" "$APPHOME/stream.py" check; anykey ;;
    t|T) printf "\n"; "$PY" "$APPHOME/keytest.py"; anykey ;;
    i|I) screen_install ;;
    k|K) screen_key ;;
    u|U) printf "\n"; bash "$APPHOME/update.sh"; anykey ;;
    S)   stop_all ;;
    w|W|x|X) printf "\n"; bash "$APPHOME/uninstall.sh"; anykey ;;
    q|Q) printf "\n"
         for id in $(app_ids); do
           running "$id" && { printf "  ${DIM}servers left running. S stops them.${OFF}\n"; break; }
         done
         printf "\n"; exit 0 ;;
  esac
done
