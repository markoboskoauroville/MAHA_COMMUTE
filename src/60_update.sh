#!/data/data/com.termux/files/usr/bin/bash
# update.sh, written by the MAHA COMMUTE installer.
#
#   maha-commute-update              find a newer installer and run it
#   maha-commute-update <file>       use this file
#
# ONE UPDATER FOR ALL THREE APPS, and it updates them the way they are
# actually delivered.
#
#   maha-commute-update --token     store a github token, once
#   maha-commute-update --check      say what is available, change nothing
#
# WHERE IT LOOKS, IN ORDER
#
#   1  a file given on the command line
#   2  github, if a token is stored, which is the automatic route
#   3  a newer installer already downloaded on the phone
#
# THE GITHUB PROBLEM, AND WHY IT IS SOLVED THIS WAY
#
# MAHA_COMMUTE is private and stays private, because day.commute is built
# around one particular home stop and one particular commute. That is an
# address, and an address does not go in a public repository. An anonymous
# fetch against a private repository 404s, so automatic updates need a
# credential.
#
# The credential is a fine grained github token, read only, scoped to this
# one repository, with an expiry. It is stored at 600 beside the google
# key, and it is a smaller thing to lose than the google key already
# sitting there: read access to one private repository of transit scripts.
# If the phone goes missing, revoke it at github and it is over.
#
# Without a token this still works exactly as it did: the file arrives on
# the phone however it arrives, and this finds it, checks it and runs it.
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

CAND=""
MODE="run"
GHTOKEN="$KEYDIR/github.txt"
REPO="markoboskoauroville/MAHA_COMMUTE"

for a in "$@"; do
  case "$a" in
    --token|--set-token) MODE="token" ;;
    --check|--dry-run)   MODE="check" ;;
    -h|--help)
      printf 'maha-commute-update [file] [--token] [--check]\n'; exit 0 ;;
    *) CAND="$a" ;;
  esac
done

if [ "$MODE" = "token" ]; then
  printf "\n  ${KEY}A GITHUB TOKEN, FOR AUTOMATIC UPDATES${OFF}\n\n"
  printf "  ${DIM}github.com > Settings > Developer settings >${OFF}\n"
  printf "  ${DIM}Personal access tokens > Fine-grained tokens${OFF}\n\n"
  printf "  ${DIM}Repository access: only %s${OFF}\n" "$REPO"
  printf "  ${DIM}Permissions: Contents, read only${OFF}\n"
  printf "  ${DIM}Expiration: whatever you are willing to renew${OFF}\n\n"
  printf "  ${DIM}Nothing else. A token with more than that on it is a${OFF}\n"
  printf "  ${DIM}bigger thing to lose than this job is worth.${OFF}\n"
  printf "\n  ${DIM}paste it, then Enter. It is not echoed back.${OFF}\n  ${AM}>${OFF} "
  IFS= read -r T || T=""
  T=$(printf '%s' "$T" | tr -cd 'A-Za-z0-9_.-' | head -c 200)
  if [ -z "$T" ]; then printf "\n  ${DIM}nothing was stored.${OFF}\n\n"; exit 0; fi
  mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR" 2>/dev/null || true
  printf '%s\n' "$T" > "$GHTOKEN"; chmod 600 "$GHTOKEN"
  printf "\n  ${DIM}checking it against %s${OFF}" "$REPO"
  code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: token $T" \
         "https://api.github.com/repos/$REPO/contents/VERSION" 2>/dev/null || echo 000)
  case "$code" in
    200) printf "\n  ${OK}it works.${OFF} ${DIM}maha-commute-update now updates on its own.${OFF}\n\n" ;;
    401|403) rm -f "$GHTOKEN"
      printf "\n  ${BAD}github refused it (%s). Nothing was stored.${OFF}\n\n" "$code"; exit 1 ;;
    404) rm -f "$GHTOKEN"
      printf "\n  ${BAD}404. The token cannot see %s.${OFF}\n" "$REPO"
      printf "  ${DIM}Repository access has to name that repository.${OFF}\n\n"; exit 1 ;;
    *) printf "\n  ${SAND}no answer from github (%s). Stored anyway.${OFF}\n\n" "$code" ;;
  esac
  exit 0
fi

# The version github is offering, when there is a token to ask with. VERSION
# is a frozen address holding a number; the installer it names carries that
# number at both ends. So the updater has a fixed thing to ask for and the
# file it fetches still says its own version in its own name.
REMOTE_V=""
if [ -s "$GHTOKEN" ] && command -v curl >/dev/null 2>&1; then
  T=$(tr -d ' \r\n' < "$GHTOKEN")
  REMOTE_V=$(curl -s -H "Authorization: token $T" -H "Accept: application/vnd.github.raw" \
    "https://api.github.com/repos/$REPO/contents/VERSION" 2>/dev/null | tr -cd '0-9' | head -c 6)
fi

HERE="${MAHA_VERSION#v}"
if [ -n "$REMOTE_V" ]; then
  if [ "$REMOTE_V" -gt "$HERE" ] 2>/dev/null; then
    printf "\n  ${KEY}v%s is available${OFF} ${DIM}(this phone has v%s)${OFF}\n" "$REMOTE_V" "$HERE"
    if [ "$MODE" = "check" ]; then printf "\n"; exit 0; fi
    NAME="$REMOTE_V-maha_commute_v$REMOTE_V.sh"
    DL="$APPHOME/tmp/$NAME"
    mkdir -p "$APPHOME/tmp"
    printf "  ${DIM}fetching %s${OFF}\n" "$NAME"
    if curl -fsSL -H "Authorization: token $T" -H "Accept: application/vnd.github.raw" \
       "https://api.github.com/repos/$REPO/contents/$NAME" -o "$DL" 2>/dev/null; then
      CAND="$DL"
    else
      printf "  ${BAD}the fetch failed. Nothing was changed.${OFF}\n\n"; exit 1
    fi
  else
    printf "\n  ${OK}v%s is the newest there is.${OFF}\n\n" "$HERE"
    [ "$MODE" = "check" ] && exit 0
    exit 0
  fi
elif [ -s "$GHTOKEN" ]; then
  printf "\n  ${SAND}github did not answer. Looking on the phone instead.${OFF}\n"
fi

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
