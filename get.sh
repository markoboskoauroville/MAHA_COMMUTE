#!/data/data/com.termux/files/usr/bin/bash
# get.sh, the one command that gets MAHA COMMUTE onto a phone.
#
#     curl -fsSL https://raw.githubusercontent.com/markoboskoauroville/MAHA_COMMUTE/main/get.sh -o get.sh && bash get.sh
#
# It exists for one reason: an updater cannot deliver itself. A phone
# carrying v2 has a v2 updater, and that one only knows how to look for a
# file already on the phone, because fetching from github did not exist
# until v4. So the first hop has to come from outside, once.
#
# It asks VERSION for a number, fetches the installer that number names,
# CHECKS IT BEFORE RUNNING IT, and hands over. Anything after the first
# argument is passed to the installer, so --offline and --apps still work.
#
# The four checks are the same four the repository's own verifier runs, and
# they are here rather than trusted, because a truncated download is the
# ordinary failure on a phone that walks out of signal halfway through.

set -e
RAW="https://raw.githubusercontent.com/markoboskoauroville/MAHA_COMMUTE/main"

if [ -t 1 ]; then
  AM="\033[38;5;214m"; OK="\033[1;32m"; BAD="\033[1;31m"
  KEY="\033[1;37m"; DIM="\033[0;90m"; OFF="\033[0m"
else
  AM=""; OK=""; BAD=""; KEY=""; DIM=""; OFF=""
fi

fetch() { # fetch <url> <dest>
  if command -v curl >/dev/null 2>&1; then curl -fsSL --max-time 300 "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then wget -qO "$2" --timeout=300 "$1"
  else printf "  ${BAD}neither curl nor wget is here.${OFF}\n  ${DIM}pkg install curl${OFF}\n"; return 1; fi
}

printf "\n  ${AM}%s${OFF}  ${KEY}MAHA COMMUTE${OFF}\n\n" "ॐ"

printf "  ${DIM}asking github which version is current${OFF}\n"
V=$(fetch "$RAW/VERSION" /dev/stdout 2>/dev/null | tr -cd '0-9' | head -c 6 || true)
if [ -z "$V" ]; then
  printf "  ${BAD}github did not answer.${OFF} ${DIM}Check the connection.${OFF}\n\n"; exit 1
fi

NAME="$V-maha_commute_v$V.sh"
DEST="${TMPDIR:-/tmp}/$NAME"
printf "  ${DIM}fetching %s${OFF}\n" "$NAME"
fetch "$RAW/$NAME" "$DEST" || { printf "  ${BAD}the download failed. Nothing was changed.${OFF}\n\n"; exit 1; }

# The same four checks the repository verifier runs, before this is trusted
# enough to execute. A phone that loses signal mid download leaves a file
# that looks fine to ls and is cut in half.
fails=0
sz=$(wc -c < "$DEST" | tr -d ' ')
[ "$sz" -ge 400000 ] || { printf "  ${BAD}size      %s bytes, too small${OFF}\n" "$sz"; fails=1; }
head -1 "$DEST" | grep -q '^#!' || { printf "  ${BAD}shebang   not a script${OFF}\n"; fails=1; }
out=$(bash -n "$DEST" 2>&1 || true)
[ -z "$out" ] || { printf "  ${BAD}parse     %s${OFF}\n" "$(printf '%s' "$out" | head -1)"; fails=1; }
tail -1 "$DEST" | grep -q '^# MAHA_COMMUTE_SENTINEL' || { printf "  ${BAD}sentinel  the file ends early${OFF}\n"; fails=1; }
if [ "$fails" != 0 ]; then
  rm -f "$DEST"
  printf "\n  ${BAD}the download is damaged. Nothing was changed.${OFF}\n"
  printf "  ${DIM}Run this again.${OFF}\n\n"; exit 1
fi
printf "  ${OK}checked${OFF} ${DIM}%s bytes, 4 of 4${OFF}\n" "$sz"

printf "  ${DIM}handing over to the installer${OFF}\n"
bash "$DEST" "$@"
rc=$?
rm -f "$DEST"
exit $rc
