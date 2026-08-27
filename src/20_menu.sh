#!/data/data/com.termux/files/usr/bin/bash
# commute, the MAHA COMMUTE menu. Written by the installer.
#
# One word for the whole family. It starts any of the three, adds one
# that was left out, takes one away, and says what is running. Every
# app is on the screen from the first frame whether it is installed or
# not: an app that is not here is dim rather than absent, and pressing
# its number offers to install it from the payload already on the phone.
#
#   commute            the menu
#   commute day        start day.commute
#   commute night      start night.commute
#   commute all        start all.commute
#   commute status     what is installed and what is running
#   commute install    the install and remove screen

. "$HOME/.maha.commute/env.sh" 2>/dev/null || {
  printf 'commute: ~/.maha.commute/env.sh is missing, so the family cannot be found.\n'
  printf 'Run the MAHA COMMUTE installer again.\n'
  exit 1
}

if [ -t 1 ]; then
  AM="\033[38;5;214m"; SAND="\033[38;5;223m"; OK="\033[1;32m"
  BAD="\033[1;31m"; KEY="\033[1;37m"; DIM="\033[0;90m"; OFF="\033[0m"
else
  AM=""; SAND=""; OK=""; BAD=""; KEY=""; DIM=""; OFF=""
fi

# The trap is armed before the first stty, never after. A trap armed
# afterwards does not cover the window it was written for.
STTY_SAVED=""
restore_tty() { [ -n "$STTY_SAVED" ] && stty "$STTY_SAVED" 2>/dev/null || true; }
trap 'restore_tty' EXIT INT TERM HUP
STTY_SAVED=$(stty -g 2>/dev/null || true)

field()   { printf '%s' "$1" | cut -d'|' -f"$2"; }
app_row() { printf '%s\n' "$MAHA_APPS" | grep "^$1|" || true; }
app_ids() { printf '%s\n' "$MAHA_APPS" | cut -d'|' -f1; }

is_installed() {
  local cmd; cmd=$(field "$(app_row "$1")" 2)
  [ -n "$cmd" ] && [ -x "$BIN/$cmd" ]
}
stamped_version() {
  if [ -f "$STAMPDIR/$1" ]; then tr -d ' \n' < "$STAMPDIR/$1"; else printf '?'; fi
}
port_live() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && exec 3<&- && return 0
  return 1
}

key_present() { [ -s "$KEYFILE" ]; }
key_length()  { key_present && tr -d ' \r\n' < "$KEYFILE" | wc -c | tr -d ' ' || printf '0'; }

anykey() {
  printf "\n  ${DIM}%s${OFF} " "${1:-any key to go back}"
  read -rsn1 _x 2>/dev/null || read -r _x
  printf "\n"
}

# ---------------------------------------------------------------
# the menu itself
# ---------------------------------------------------------------
draw() {
  clear 2>/dev/null || true
  printf "\n"
  printf "  ${AM}%s${OFF}  ${KEY}MAHA COMMUTE${OFF}  ${DIM}%s${OFF}\n" "ॐ" "$MAHA_VERSION"
  printf "  ${DIM}Zagreb, the whole day and the whole night${OFF}\n\n"

  local id n=0 row cmd ver port desc state
  for id in $(app_ids); do
    n=$((n+1))
    row=$(app_row "$id")
    cmd=$(field "$row" 2); ver=$(field "$row" 4)
    port=$(field "$row" 5); desc=$(field "$row" 6)
    if is_installed "$id"; then
      ver=$(stamped_version "$id"); [ "$ver" = "?" ] && ver=$(field "$row" 4)
      if port_live "$port"; then
        state="${OK}running${OFF} ${DIM}$port${OFF}"
      else
        state="${SAND}ready${OFF}"
      fi
      printf "  ${KEY}%s${OFF}  ${SAND}%-16s${OFF} ${DIM}%-5s${OFF} %b\n" "$n" "$cmd" "$ver" "$state"
      printf "     ${DIM}%s${OFF}\n" "$desc"
    else
      printf "  ${DIM}%s  %-16s %-5s not installed${OFF}\n" "$n" "$cmd" "-"
      printf "     ${DIM}%s${OFF}\n" "$desc"
    fi
  done

  printf "\n"
  printf "  ${KEY}i${OFF} ${DIM}install or remove${OFF}     ${KEY}k${OFF} ${DIM}google key${OFF}\n"
  printf "  ${KEY}s${OFF} ${DIM}status${OFF}                ${KEY}q${OFF} ${DIM}quit${OFF}\n"
  printf "\n  ${AM}>${OFF} "
}

start_app() {
  local id="$1" row cmd
  row=$(app_row "$id"); cmd=$(field "$row" 2)
  if is_installed "$id"; then
    printf "\n"
    restore_tty
    "$BIN/$cmd" || true
    anykey "any key for the menu"
  else
    offer_install "$id"
  fi
}

offer_install() {
  local id="$1" row cmd
  row=$(app_row "$id"); cmd=$(field "$row" 2)
  printf "\n  ${SAND}%s is not installed.${OFF}\n" "$cmd"
  printf "  ${DIM}the payload is already on the phone, so this needs no download${OFF}\n"
  printf "\n  ${KEY}Enter${OFF} ${DIM}install it${OFF}    ${KEY}n${OFF} ${DIM}leave it${OFF}\n"
  printf "\n  ${AM}>${OFF} "
  IFS= read -r ans || ans="n"
  case "$ans" in
    [nN]*) return 0 ;;
  esac
  bash "$APPHOME/install-one.sh" "$id" --offline || true
  anykey
}

remove_app() {
  local id="$1" row cmd dir
  row=$(app_row "$id"); cmd=$(field "$row" 2); dir="$HOME/$(field "$row" 3)"
  rm -f "$BIN/$cmd"
  rm -f "$STAMPDIR/$id"
  printf "  ${SAND}%s removed.${OFF}\n" "$cmd"
  printf "  ${DIM}its data is untouched in %s${OFF}\n" "$dir"
  printf "  ${DIM}to delete that too:  rm -rf %s${OFF}\n" "$dir"
}

screen_install() {
  local id n row cmd ans
  while :; do
    clear 2>/dev/null || true
    printf "\n  ${KEY}INSTALL OR REMOVE${OFF}\n"
    printf "  ${DIM}a number adds the app if it is missing, takes it away if it is here${OFF}\n\n"
    n=0
    for id in $(app_ids); do
      n=$((n+1)); row=$(app_row "$id"); cmd=$(field "$row" 2)
      if is_installed "$id"; then
        printf "  ${KEY}%s${OFF}  ${OK}[x]${OFF} ${SAND}%-16s${OFF} ${DIM}%s${OFF}\n" \
          "$n" "$cmd" "$(stamped_version "$id")"
      else
        printf "  ${KEY}%s${OFF}  ${DIM}[ ] %-16s not installed${OFF}\n" "$n" "$cmd"
      fi
    done
    printf "\n  ${KEY}a${OFF} ${DIM}install all three${OFF}      ${KEY}q${OFF} ${DIM}back${OFF}\n"
    printf "\n  ${AM}>${OFF} "
    read -rsn1 ans 2>/dev/null || read -r ans
    printf "\n"
    case "$ans" in
      1|2|3)
        id=$(app_ids | sed -n "${ans}p")
        if is_installed "$id"; then
          printf "\n"
          remove_app "$id"; anykey
        else
          bash "$APPHOME/install-one.sh" "$id" --offline || true
          anykey
        fi
        ;;
      a|A)
        for id in $(app_ids); do
          is_installed "$id" || bash "$APPHOME/install-one.sh" "$id" --offline || true
        done
        anykey
        ;;
      q|Q|"") return 0 ;;
    esac
  done
}

screen_key() {
  clear 2>/dev/null || true
  printf "\n  ${KEY}GOOGLE MAPS KEY${OFF}\n"
  printf "  ${DIM}one key, shared by all three, kept in%s${OFF}\n" " ~/.maha.commute/keys"
  printf "  ${DIM}without it the apps run and the photographs do not${OFF}\n\n"
  if key_present; then
    printf "  ${OK}present${OFF} ${DIM}%s characters${OFF}\n" "$(key_length)"
  else
    printf "  ${DIM}none stored${OFF}\n"
  fi
  printf "\n  ${KEY}Enter${OFF} ${DIM}back${OFF}     ${KEY}p${OFF} ${DIM}paste a new one${OFF}     ${KEY}x${OFF} ${DIM}forget it${OFF}\n"
  printf "\n  ${AM}>${OFF} "
  IFS= read -r ans || ans=""
  case "$ans" in
    p|P)
      printf "\n  ${DIM}paste the key, then Enter${OFF}\n  ${AM}>${OFF} "
      IFS= read -r newkey || newkey=""
      newkey=$(printf '%s' "$newkey" | tr -cd 'A-Za-z0-9_-' | head -c 200)
      if [ -n "$newkey" ]; then
        mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR" 2>/dev/null || true
        printf '%s\n' "$newkey" > "$KEYFILE"; chmod 600 "$KEYFILE"
        printf "\n  ${OK}stored${OFF} ${DIM}%s characters${OFF}\n" "$(key_length)"
        printf "  ${DIM}reinstall an app from the install screen to hand it the new key${OFF}\n"
      else
        printf "\n  ${DIM}nothing was changed${OFF}\n"
      fi
      anykey ;;
    x|X)
      rm -f "$KEYFILE"
      printf "\n  ${SAND}forgotten here.${OFF} ${DIM}the copies inside each app stay where they are${OFF}\n"
      anykey ;;
  esac
}

screen_status() {
  clear 2>/dev/null || true
  printf "\n  ${KEY}STATUS${OFF}\n\n"
  local id row cmd dir port
  for id in $(app_ids); do
    row=$(app_row "$id"); cmd=$(field "$row" 2)
    dir="$HOME/$(field "$row" 3)"; port=$(field "$row" 5)
    printf "  ${SAND}%s${OFF}\n" "$cmd"
    if is_installed "$id"; then
      printf "    ${DIM}command${OFF}  ${OK}%s${OFF}\n" "$BIN/$cmd"
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
  if key_present; then
    printf "    ${DIM}key      present, %s characters${OFF}\n" "$(key_length)"
  else
    printf "    ${DIM}key      none${OFF}\n"
  fi
  anykey
}

# ---------------------------------------------------------------
# one shot forms, for when the menu is one keystroke too many
# ---------------------------------------------------------------
case "${1:-}" in
  day|night|all)   start_app "$1"; exit 0 ;;
  status)          screen_status; exit 0 ;;
  install|add)     screen_install; exit 0 ;;
  key)             screen_key; exit 0 ;;
  -h|--help)
    printf 'commute [day|night|all|status|install|key]\n'; exit 0 ;;
esac

while :; do
  draw
  read -rsn1 choice 2>/dev/null || read -r choice
  case "$choice" in
    1) start_app "$(app_ids | sed -n 1p)" ;;
    2) start_app "$(app_ids | sed -n 2p)" ;;
    3) start_app "$(app_ids | sed -n 3p)" ;;
    i|I) screen_install ;;
    k|K) screen_key ;;
    s|S) screen_status ;;
    q|Q) printf "\n\n"; exit 0 ;;
  esac
done
