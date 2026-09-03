#!/data/data/com.termux/files/usr/bin/bash
# install-one.sh, written by the MAHA COMMUTE installer.
#
# One app, from the payload already on the phone. This is the only
# routine that installs anything: the installer calls it for each app
# picked on the first run, and the commute menu calls the same file
# when an app is added later. Two callers, one implementation, so a
# fix to the install path cannot reach one of them and miss the other.
#
#   install-one.sh day --offline
#   install-one.sh night --online

set -e
. "$HOME/.maha.commute/env.sh"

APP="${1:-}"
FLAG="${2:---offline}"

if [ -t 1 ]; then
  AM="\033[38;5;214m"; OK="\033[1;32m"; BAD="\033[1;31m"
  DIM="\033[0;90m"; KEY="\033[1;37m"; OFF="\033[0m"
else
  AM=""; OK=""; BAD=""; DIM=""; KEY=""; OFF=""
fi

row=$(printf '%s\n' "$MAHA_APPS" | grep "^$APP|" || true)
if [ -z "$row" ]; then
  printf "  ${BAD}no such app: %s${OFF}\n" "$APP"; exit 2
fi
CMD=$(printf '%s' "$row" | cut -d'|' -f2)
VER=$(printf '%s' "$row" | cut -d'|' -f4)
PORT=$(printf '%s' "$row" | cut -d'|' -f5)
PROC=$(printf '%s' "$row" | cut -d'|' -f7)
SRC="$PAYDIR/$APP.payload.sh"

if [ ! -f "$SRC" ]; then
  printf "  ${BAD}the payload for %s is not on this phone${OFF}\n" "$APP"
  printf "  ${DIM}run the installer again to put it back${OFF}\n"
  exit 3
fi

# Check the payload before running it, not after. A payload that lost
# bytes somewhere installs half an app and says nothing.
if command -v sha256sum >/dev/null 2>&1 && [ -f "$PAYDIR/SHA256SUMS" ]; then
  if ! ( cd "$PAYDIR" && grep " $APP.payload.sh\$" SHA256SUMS | sha256sum -c --status - ); then
    printf "  ${BAD}the %s payload does not match its checksum${OFF}\n" "$APP"
    printf "  ${DIM}nothing was changed${OFF}\n"
    exit 4
  fi
else
  want=$(grep "^$APP|" "$PAYDIR/SIZES" 2>/dev/null | cut -d'|' -f2)
  have=$(wc -c < "$SRC" | tr -d ' ')
  if [ -n "$want" ] && [ "$want" != "$have" ]; then
    printf "  ${BAD}the %s payload is %s bytes, expected %s${OFF}\n" "$APP" "$have" "$want"
    printf "  ${DIM}nothing was changed${OFF}\n"
    exit 4
  fi
fi

# night.commute v9 begins by deleting its own app directory, so an
# upgrade takes everything in it with it. That is the payload's own
# decision and it is left alone: a clean directory is what stops stale
# state, and the umbrella does not get to overrule an app about its own
# data. What the umbrella can do is make it recoverable, so the payload
# is read first and a copy taken only when it is going to wipe.
APPDIR="$HOME/$(printf '%s' "$row" | cut -d'|' -f3)"
if [ -d "$APPDIR" ] && grep -qF "rm -rf \"\$HOME/$(printf '%s' "$row" | cut -d'|' -f3)\"" "$SRC"; then
  BK="$APPHOME/backup/$APP.prev"
  mkdir -p "$APPHOME/backup"
  rm -rf "$BK" 2>/dev/null || true
  if cp -a "$APPDIR" "$BK" 2>/dev/null; then
    printf "  ${DIM}%s clears its folder on install. A copy is kept in${OFF}\n" "$CMD"
    printf "  ${DIM}%s  (%s)${OFF}\n" "$BK" "$(du -sh "$BK" 2>/dev/null | cut -f1)"
  else
    printf "  ${BAD}could not copy %s, and this install will clear it${OFF}\n" "$APPDIR"
    printf "  ${DIM}nothing was changed${OFF}\n"
    exit 5
  fi
fi

mkdir -p "$APPHOME/tmp"
chmod 700 "$APPHOME/tmp" 2>/dev/null || true
TMP="$APPHOME/tmp/$APP.run.sh"
trap 'rm -f "$TMP"' EXIT INT TERM HUP

# Cleaned again here, at the point of use, because the file could have
# been edited by hand between being written and being read.
GKEY=""
if [ -f "$KEYFILE" ]; then
  GKEY=$(grep -v '^[[:space:]]*$' "$KEYFILE" | head -1 | tr -cd 'A-Za-z0-9_-' | head -c 200)
fi

# The key goes into the copy that runs and never into the copy that is
# kept. The kept payload holds a placeholder and nothing else, which is
# why this file can sit in a repository.
{
  head -1 "$SRC"
  printf 'clear() { :; }\n'
  tail -n +2 "$SRC" | sed "s|__MAHA_GOOGLE_KEY__|$GKEY|g"
} > "$TMP"
chmod 600 "$TMP"

printf "\n  ${AM}|${OFF} ${KEY}%s${OFF} ${DIM}%s${OFF}\n" "$CMD" "$VER"

# A server already running is holding the old code in memory, and it
# goes on serving that code after its files have been replaced. From
# outside that looks like an install that did nothing. So it is stopped
# first, by its own launcher where the launcher knows how, and by the
# name of its process where it does not.
if [ -x "$BIN/$CMD" ] && (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  exec 3<&-
  printf "  ${DIM}stopping the running server first${OFF}\n"
  if grep -q '^  stop)' "$BIN/$CMD" 2>/dev/null; then
    "$BIN/$CMD" stop >/dev/null 2>&1 || true
  fi
  pkill -f "$PROC" 2>/dev/null || true
  sleep 1
fi

rc=0
bash "$TMP" "$FLAG" || rc=$?
rm -f "$TMP"

if [ "$rc" != "0" ]; then
  printf "  ${BAD}%s did not finish, exit %s${OFF}\n" "$CMD" "$rc"
  exit "$rc"
fi

mkdir -p "$STAMPDIR"
printf '%s\n' "$VER" > "$STAMPDIR/$APP"
# The checksum of the payload that is now on this phone. The next install
# compares against it and leaves this app alone when it has not moved, so an
# update touches the apps that changed and no others.
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$SRC" | cut -d" " -f1 > "$STAMPDIR/$APP.sha"
else
  wc -c < "$SRC" | tr -d ' ' > "$STAMPDIR/$APP.sha"
fi
exit 0
