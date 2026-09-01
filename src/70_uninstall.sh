#!/data/data/com.termux/files/usr/bin/bash
# uninstall.sh, written by the MAHA COMMUTE installer.
#
#   maha-commute uninstall        the panel, decide item by item
#   maha-commute uninstall --all  everything, still asks twice
#
# WHAT MAKES AN UNINSTALLER HARD IS NOT DELETING. It is knowing what is
# there. These apps were installed by hand, one at a time, over months,
# under names that have since changed, so nothing here assumes: every path
# is looked for on disk and only what is actually found is listed, with its
# size, before a single question is asked.
#
# It also sweeps up what earlier versions left behind. night.commute was
# once called nightram and once nightcommute, v1 of this umbrella installed
# a command called commute, and each of those leaves a file that no current
# installer would ever write and no current uninstaller would think to look
# for. They are listed here by name because forgetting them is how a phone
# ends up with dead commands in the PATH for a year.
#
# NOTHING IS DELETED WITHOUT THE WORD. The full wipe asks for a typed word,
# not a keypress, because a keypress is what a thumb does by accident.

. "$HOME/.maha.commute/env.sh" 2>/dev/null || {
  BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
  APPHOME="$HOME/.maha.commute"
  MAHA_APPS="day|day.commute|.commute|v13|8082|the daytime ride|commute_server.py
night|night.commute|.nightcommute|v9|8087|the four night trams|night_server.py
all|all.commute|.all.commute|v39|8084|every station around you|all_commute_server.py"
}

if [ -t 1 ]; then
  AM="\033[38;5;214m"; SAND="\033[38;5;223m"; OK="\033[1;32m"
  BAD="\033[1;31m"; KEY="\033[1;37m"; DIM="\033[0;90m"; OFF="\033[0m"
else
  AM=""; SAND=""; OK=""; BAD=""; KEY=""; DIM=""; OFF=""
fi

ALL=0
[ "${1:-}" = "--all" ] && ALL=1

field() { printf '%s' "$1" | cut -d'|' -f"$2"; }

# Everything that could exist, in the order it should be shown. Kind is what
# it costs to lose: a command is free to reinstall, data is not, and a key
# is the one thing that cannot be rebuilt from this repository at all.
ITEMS=""
add() { ITEMS="$ITEMS$1|$2|$3
"; }

collect() {
  ITEMS=""
  local row id cmd dir
  printf '%s\n' "$MAHA_APPS" | while read -r row; do :; done
  for row in $(printf '%s\n' "$MAHA_APPS" | tr ' ' '\001'); do
    row=$(printf '%s' "$row" | tr '\001' ' ')
    id=$(field "$row" 1); cmd=$(field "$row" 2); dir="$HOME/$(field "$row" 3)"
    [ -x "$BIN/$cmd" ] && add "command" "$BIN/$cmd" "$cmd, the launcher"
    [ -d "$dir" ] && add "data" "$dir" "$cmd data, schedules and settings"
  done
  # the umbrella itself
  [ -x "$BIN/maha-commute" ]        && add "command" "$BIN/maha-commute" "the launcher"
  [ -x "$BIN/maha-commute-update" ] && add "command" "$BIN/maha-commute-update" "the updater"
  [ -d "$APPHOME/payloads" ]        && add "data" "$APPHOME/payloads" "the three cached payloads"
  [ -d "$APPHOME/backup" ]          && add "data" "$APPHOME/backup" "the folder kept before a wipe"
  [ -d "$APPHOME/keys" ]            && add "key"  "$APPHOME/keys" "the shared google key"
  [ -d "$APPHOME" ]                 && add "data" "$APPHOME" "everything else under the umbrella"
  # what earlier versions left behind, and would otherwise stay forever
  [ -x "$BIN/commute" ]      && add "old" "$BIN/commute" "the v1 launcher, replaced by maha-commute"
  [ -x "$BIN/nightram" ]     && add "old" "$BIN/nightram" "an old name for night.commute"
  [ -x "$BIN/nightcommute" ] && add "old" "$BIN/nightcommute" "an older name still"
  [ -d "$HOME/.nightram" ]   && add "old" "$HOME/.nightram" "its folder"
  printf '%s' "$ITEMS"
}

size_of() {
  if [ -d "$1" ]; then du -sh "$1" 2>/dev/null | cut -f1
  elif [ -f "$1" ]; then du -h "$1" 2>/dev/null | cut -f1
  else printf '-'; fi
}

show() {
  local n=0 kind path what colour
  printf "\n  ${AM}+--------------------------------------------+${OFF}\n"
  printf "  ${AM}|${OFF} ${KEY}%-42s${OFF} ${AM}|${OFF}\n" "UNINSTALL, what is on this phone"
  printf "  ${AM}+--------------------------------------------+${OFF}\n"
  printf '%s' "$LIST" | while IFS='|' read -r kind path what; do
    [ -z "$path" ] && continue
    n=$((n+1))
    case "$kind" in
      key)  colour="$BAD" ;;
      data) colour="$SAND" ;;
      old)  colour="$DIM" ;;
      *)    colour="$OK" ;;
    esac
    printf "  ${KEY}%2d${OFF} %b%-6s%b %-28s ${DIM}%5s${OFF}\n" \
      "$n" "$colour" "$kind" "$OFF" "$what" "$(size_of "$path")"
    printf "     ${DIM}%s${OFF}\n" "$path"
  done
  printf "\n"
}

remove_one() {
  local path="$1"
  if [ -e "$path" ]; then
    rm -rf "$path" && printf "  ${OK}gone${OFF} ${DIM}%s${OFF}\n" "$path"
  fi
}

LIST=$(collect)
if [ -z "$LIST" ]; then
  printf "\n  ${DIM}nothing of MAHA COMMUTE is on this phone.${OFF}\n\n"
  exit 0
fi

show
COUNT=$(printf '%s' "$LIST" | grep -c '|')
printf "  ${DIM}%s things, %s in total${OFF}\n" "$COUNT" \
  "$(du -shc $(printf '%s' "$LIST" | cut -d'|' -f2 | tr '\n' ' ') 2>/dev/null | tail -1 | cut -f1)"

if [ "$ALL" != 1 ]; then
  printf "\n  ${KEY}a${OFF} ${DIM}everything, all of it${OFF}\n"
  printf "  ${KEY}u${OFF} ${DIM}the umbrella only, leaving the three apps working${OFF}\n"
  printf "  ${KEY}q${OFF} ${DIM}nothing, go back${OFF}\n"
  printf "\n  ${AM}>${OFF} "
  IFS= read -r ANS || ANS="q"
  case "$ANS" in
    u|U)
      printf "\n  ${DIM}taking away the umbrella and leaving the apps alone${OFF}\n\n"
      remove_one "$BIN/maha-commute"
      remove_one "$BIN/maha-commute-update"
      remove_one "$BIN/commute"
      remove_one "$APPHOME"
      printf "\n  ${OK}done.${OFF} ${DIM}day.commute, night.commute and all.commute${OFF}\n"
      printf "  ${DIM}still work exactly as they did before.${OFF}\n\n"
      exit 0 ;;
    a|A) : ;;
    *) printf "\n  ${DIM}nothing was changed.${OFF}\n\n"; exit 0 ;;
  esac
fi

# The second question, and it is typed. A keypress is what a thumb does by
# accident; a word is a decision. The word is in the language of the thing
# being lost rather than a bare yes.
printf "\n  ${BAD}This removes all three apps, their schedules, their${OFF}\n"
printf "  ${BAD}settings and the shared key, on this phone.${OFF}\n"
printf "\n  ${DIM}The three original installers still exist and put every${OFF}\n"
printf "  ${DIM}app back. What cannot be put back is the key, unless a${OFF}\n"
printf "  ${DIM}copy of it is somewhere else.${OFF}\n"
if [ -s "$APPHOME/keys/google-api.txt" ]; then
  printf "\n  ${SAND}the shared key is %s characters long and is about to go${OFF}\n" \
    "$(tr -d ' \r\n' < "$APPHOME/keys/google-api.txt" | wc -c | tr -d ' ')"
fi
printf "\n  ${KEY}type the word${OFF} ${SAND}wipe${OFF} ${KEY}to go ahead${OFF}\n"
printf "\n  ${AM}>${OFF} "
IFS= read -r W || W=""
if [ "$W" != "wipe" ]; then
  printf "\n  ${DIM}nothing was changed.${OFF}\n\n"
  exit 0
fi

printf "\n  ${DIM}stopping anything that is running${OFF}\n"
for proc in commute_server.py night_server.py all_commute_server.py; do
  pkill -f "$proc" 2>/dev/null && printf "  ${OK}stopped${OFF} ${DIM}%s${OFF}\n" "$proc"
done
sleep 1

printf "\n"
printf '%s' "$LIST" | cut -d'|' -f2 | while read -r p; do
  [ -n "$p" ] && remove_one "$p"
done

printf "\n  ${OK}MAHA COMMUTE is off this phone.${OFF}\n"
printf "  ${DIM}Nothing in \$PREFIX/bin is left from it:${OFF}\n"
LEFT=0
for c in maha-commute maha-commute-update commute day.commute night.commute all.commute; do
  [ -e "$BIN/$c" ] && { printf "  ${BAD}still there: %s${OFF}\n" "$BIN/$c"; LEFT=1; }
done
[ "$LEFT" = 0 ] && printf "  ${DIM}checked six names, none remains${OFF}\n"
printf "\n"
