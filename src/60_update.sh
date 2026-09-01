#!/data/data/com.termux/files/usr/bin/bash
# update.sh, written by the MAHA COMMUTE installer.
#
#   maha-commute-update              find a newer installer and run it
#   maha-commute-update <file>       use this file
#
# ONE UPDATER FOR ALL THREE APPS, and it updates them the way they are
# actually delivered.
#
# WHY IT DOES NOT FETCH FROM GITHUB
#
# termux-app.md is blunt about this: an updater cannot be anonymous
# against a private repository. It 404s, and there is no third way that
# does not put a token on a phone that travels. So the choice had to be
# made before this file was written rather than after.
#
# MAHA_COMMUTE is private and stays private, because day.commute is built
# around a particular home stop and a particular commute. That is an
# address, and an address does not go in a public repository. So the
# repository cannot be the source, and this updater takes the route that
# is left, which is also the route already used: the new installer arrives
# on the phone as a file, and this finds it, checks it, and runs it.
#
# WHAT IT ADDS OVER RUNNING THE FILE BY HAND
#
#   it finds the newest one, wherever the phone put it
#   it refuses to run a file that did not arrive whole
#   it installs exactly the apps that are installed now, so an update
#     never quietly adds an app that was deliberately left out, and never
#     drops one that was wanted
#   it says the version it is coming from and going to, before it starts

set -e
. "$HOME/.maha.commute/env.sh"

if [ -t 1 ]; then
  AM="\033[38;5;214m"; SAND="\033[38;5;223m"; OK="\033[1;32m"
  BAD="\033[1;31m"; KEY="\033[1;37m"; DIM="\033[0;90m"; OFF="\033[0m"
else
  AM=""; SAND=""; OK=""; BAD=""; KEY=""; DIM=""; OFF=""
fi

CAND="${1:-}"

# Where a phone puts a downloaded file, in the order it is likely to be.
if [ -z "$CAND" ]; then
  NEWEST=""
  for d in "$HOME/storage/downloads" "$HOME/downloads" "$HOME/Downloads" \
           "$HOME/storage/shared/Download" "$HOME"; do
    [ -d "$d" ] || continue
    for f in "$d"/*maha_commute_v*.sh; do
      [ -f "$f" ] || continue
      if [ -z "$NEWEST" ] || [ "$f" -nt "$NEWEST" ]; then NEWEST="$f"; fi
    done
  done
  CAND="$NEWEST"
fi

printf "\n  ${AM}%s${OFF}  ${KEY}MAHA COMMUTE${OFF} ${DIM}update${OFF}\n\n" "ॐ"

if [ -z "$CAND" ] || [ ! -f "$CAND" ]; then
  printf "  ${SAND}no installer found to update from.${OFF}\n\n"
  printf "  ${DIM}Download the newest %s-maha_commute_v%s.sh, then run${OFF}\n" "N" "N"
  printf "  ${DIM}maha-commute-update again. It looks in Downloads and in the${OFF}\n"
  printf "  ${DIM}home folder. A path can also be given:${OFF}\n"
  printf "  ${DIM}  maha-commute-update ~/storage/downloads/2-maha_commute_v2.sh${OFF}\n\n"
  printf "  ${DIM}nothing was changed${OFF}\n\n"
  exit 1
fi

printf "  ${DIM}found${OFF} %s\n" "$CAND"

# ---------------------------------------------------------------------
# Four checks before it is allowed to replace anything. A truncated file
# that gets installed is worse than an update that failed, because the
# failure is silent and arrives later.
# ---------------------------------------------------------------------
fails=0
sz=$(wc -c < "$CAND" | tr -d ' ')
if [ "$sz" -ge 400000 ]; then
  printf "  ${OK}ok${OFF}    ${DIM}size, %s bytes${OFF}\n" "$sz"
else
  printf "  ${BAD}FAIL${OFF}  ${DIM}size, %s bytes, too small to hold three apps${OFF}\n" "$sz"
  fails=$((fails+1))
fi
if head -1 "$CAND" | grep -q '^#!'; then
  printf "  ${OK}ok${OFF}    ${DIM}it is a script${OFF}\n"
else
  printf "  ${BAD}FAIL${OFF}  ${DIM}the first line is not a shebang${OFF}\n"; fails=$((fails+1))
fi
# The exit status is not the check. A file cut in the middle of a heredoc
# makes bash -n warn on stderr and exit zero, so the absence of output is
# what is being tested.
nout=$(bash -n "$CAND" 2>&1 || true)
if [ -z "$nout" ]; then
  printf "  ${OK}ok${OFF}    ${DIM}parses, and said nothing at all${OFF}\n"
else
  printf "  ${BAD}FAIL${OFF}  ${DIM}%s${OFF}\n" "$(printf '%s' "$nout" | head -1)"
  fails=$((fails+1))
fi
if tail -1 "$CAND" | grep -q '^# MAHA_COMMUTE_SENTINEL'; then
  printf "  ${OK}ok${OFF}    ${DIM}%s${OFF}\n" "$(tail -1 "$CAND" | cut -c3-)"
else
  printf "  ${BAD}FAIL${OFF}  ${DIM}the file ends early${OFF}\n"; fails=$((fails+1))
fi

if [ "$fails" != 0 ]; then
  printf "\n  ${BAD}%s of 4 checks failed. Nothing was changed.${OFF}\n" "$fails"
  printf "  ${DIM}download the file again${OFF}\n\n"
  exit 1
fi

NEW=$(grep -m1 '^MAHA_VERSION=' "$CAND" | cut -d'"' -f2)
printf "\n  ${DIM}this phone has${OFF} ${SAND}%s${OFF}${DIM}, the file is${OFF} ${SAND}%s${OFF}\n" \
  "$MAHA_VERSION" "${NEW:-unknown}"
if [ "$NEW" = "$MAHA_VERSION" ]; then
  printf "  ${DIM}the same version. Running it again changes nothing and is safe.${OFF}\n"
fi

# The apps that are installed now, so the update preserves the choice
# that was made rather than making it again.
PICK=""
n=0
for id in $(printf '%s\n' "$MAHA_APPS" | cut -d'|' -f1); do
  n=$((n+1))
  cmd=$(printf '%s\n' "$MAHA_APPS" | grep "^$id|" | cut -d'|' -f2)
  [ -x "$BIN/$cmd" ] && PICK="$PICK$n"
done
if [ -z "$PICK" ]; then
  printf "  ${DIM}no apps are installed, so the update installs none of them${OFF}\n"
  PICK="n"
else
  printf "  ${DIM}installed now, and kept:${OFF}"
  for id in $(printf '%s\n' "$MAHA_APPS" | cut -d'|' -f1); do
    cmd=$(printf '%s\n' "$MAHA_APPS" | grep "^$id|" | cut -d'|' -f2)
    [ -x "$BIN/$cmd" ] && printf " ${SAND}%s${OFF}" "$cmd"
  done
  printf "\n"
fi

printf "\n  ${KEY}Enter${OFF} ${DIM}install it${OFF}    ${KEY}n${OFF} ${DIM}stop, change nothing${OFF}\n"
printf "\n  ${AM}>${OFF} "
IFS= read -r ans || ans="n"
case "$ans" in [nN]*) printf "\n  ${DIM}nothing was changed${OFF}\n\n"; exit 0 ;; esac

printf "\n"
exec bash "$CAND" --offline --apps "$PICK"
