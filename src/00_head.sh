#!/data/data/com.termux/files/usr/bin/bash
# @@HEADER@@
#
# MAHA COMMUTE, the umbrella over the Zagreb transit family.
#
# Three apps live under it, each one whole and unchanged:
#
#   day.commute     the daytime ride, corridors that pick themselves
#   night.commute   the four night trams, 23:50 to 04:40
#   all.commute     every station around you, in colour
#
# This one file carries all three. It asks which ones to install,
# installs only those, and leaves one word behind: commute. That word
# opens a menu that starts any of them, and can add or remove the
# others later with no download, because all three payloads are kept
# on the phone whether they were installed or not.
#
#   bash @@FILENAME@@             ask everything
#   bash @@FILENAME@@ --offline   install with what is already here
#   bash @@FILENAME@@ --online    fetch the missing dependencies first
#   bash @@FILENAME@@ --apps 13   day and all, no picker
#   bash @@FILENAME@@ --apps all  all three
#   bash @@FILENAME@@ --verify    check this file is whole, change nothing
#
# The Google Maps key is not in this file. It is looked for on the
# phone, in the shared store first and then in any app already
# installed, and asked for only if none is found. An install with no
# key is a working install with no photographs.

set -e

MAHA_VERSION="v1"
MAHA_FILE="@@FILENAME@@"
BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
APPHOME="$HOME/.maha.commute"
PAYDIR="$APPHOME/payloads"
KEYDIR="$APPHOME/keys"
KEYFILE="$KEYDIR/google-api.txt"
STAMPDIR="$APPHOME/installed"

# id | command | appdir | version | port | one line | server process
MAHA_APPS="day|day.commute|.commute|@@VER_DAY@@|8082|the daytime ride|commute_server.py
night|night.commute|.nightcommute|@@VER_NIGHT@@|8087|the four night trams|night_server.py
all|all.commute|.all.commute|@@VER_ALL@@|8084|every station around you|all_commute_server.py"

MODE=""
PICK=""
VERIFY_ONLY=0
for a in "$@"; do
  case "$a" in
    --online|--full|--deps) MODE="online" ;;
    --offline) MODE="offline" ;;
    --apps=*) PICK="${a#--apps=}" ;;
    --apps) PICK="__next__" ;;
    --verify) VERIFY_ONLY=1 ;;
    -h|--help)
      printf 'usage: bash %s [--offline|--online] [--apps 13|all] [--verify]\n' "$MAHA_FILE"
      exit 0 ;;
    *) [ "$PICK" = "__next__" ] && PICK="$a" ;;
  esac
done
[ "$PICK" = "__next__" ] && PICK=""

if [ -t 1 ]; then
  AM="\033[38;5;214m"; SAND="\033[38;5;223m"; OK="\033[1;32m"
  WARN="\033[1;33m"; BAD="\033[1;31m"; KEY="\033[1;37m"
  DIM="\033[0;90m"; OFF="\033[0m"
else
  AM=""; SAND=""; OK=""; WARN=""; BAD=""; KEY=""; DIM=""; OFF=""
fi

say()   { printf "  %b\n" "$1"; }
blank() { printf "\n"; }
step()  { printf "  ${AM}>${OFF} %s" "$1"; local i; for i in 1 2 3; do printf "."; sleep 0.06; done; }
done_() { printf " ${OK}ok${OFF}\n"; }
skip_() { printf " ${DIM}skipped${OFF}\n"; }
fail_() { printf " ${BAD}%s${OFF}\n" "${1:-failed}"; }
