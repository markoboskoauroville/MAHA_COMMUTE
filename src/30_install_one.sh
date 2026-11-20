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

# --sync-key [force]: copy the shared key into every installed app's own key
# file. Without "force" an app that already holds a key is left alone (it may be
# a different one, and it was put there by hand); with it (the person pasted a
# new key in the launcher) every app gets it. Never prints the key.
key_ok() { [ -f "$1" ] && [ "$(grep -v '^[[:space:]]*$' "$1" 2>/dev/null | head -1 | tr -cd 'A-Za-z0-9_-' | head -c 200 | wc -c | tr -d ' ')" -ge 20 ]; }
sync_key() {   # sync_key FORCE
  local force="$1" id row dir name dst
  key_ok "$KEYFILE" || return 0
  for id in $(printf '%s\n' "$MAHA_APPS" | cut -d'|' -f1); do
    row=$(printf '%s\n' "$MAHA_APPS" | grep "^$id|" || true)
    dir="$HOME/$(printf '%s' "$row" | cut -d'|' -f3)"
    name=$(printf '%s' "$row" | cut -d'|' -f9)
    [ -d "$dir" ] && [ -n "$name" ] || continue
    dst="$dir/$name"
    if [ "$force" = "force" ] || ! key_ok "$dst"; then
      grep -v '^[[:space:]]*$' "$KEYFILE" | head -1 | tr -cd 'A-Za-z0-9_-' | head -c 200 > "$dst.new"
      printf '\n' >> "$dst.new"; chmod 600 "$dst.new"; mv -f "$dst.new" "$dst"
    fi
  done
}
if [ "$APP" = "--sync-key" ]; then sync_key "${2:-}"; exit 0; fi

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
    printf "  ${DIM}its key, its PDF timetables and the ZET schedule are kept in place${OFF}\n"
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
LAUNCH="$BIN/$CMD"; [ -x "$APPHOME/orig/$CMD" ] && LAUNCH="$APPHOME/orig/$CMD"
if [ -x "$BIN/$CMD" ] && (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  exec 3<&-
  printf "  ${DIM}stopping the running server first${OFF}\n"
  if grep -q '^  stop)' "$LAUNCH" 2>/dev/null; then
    "$LAUNCH" stop >/dev/null 2>&1 || true
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

# BEGIN SHIM
# v17: typing the app's own name opens the launcher's screen with that app
# focused, the same screen and the same verbs as everywhere else. The app's
# real launcher is kept in orig/ and the launcher always talks to THAT, never
# to this file, so nothing here can call itself. The new file is written beside
# its name and renamed over it, never truncated in place (termux-app.md 4).
write_shim() {   # write_shim ID CMD
  local id="$1" cmd="$2" orig="$APPHOME/orig/$2" new="$BIN/.$2.new"
  if [ -f "$BIN/$cmd" ] && ! grep -q '^# MAHA_SHIM ' "$BIN/$cmd" 2>/dev/null; then
    mkdir -p "$APPHOME/orig"
    cp -f "$BIN/$cmd" "$orig.new" && chmod +x "$orig.new" && mv -f "$orig.new" "$orig"
  fi
  [ -x "$orig" ] || return 0
  rm -f "$new"
  cat > "$new" <<'MAHA_SHIM_TEXT'
#!/data/data/com.termux/files/usr/bin/bash
# MAHA_SHIM @ID@, written by the MAHA COMMUTE installer and not part of the app.
# Typing this command opens the launcher screen with this app focused. The
# app's own launcher is kept in ~/.maha.commute/orig/ and still does the work.
ORIG="$HOME/.maha.commute/orig/@CMD@"
[ -x "$ORIG" ] || { echo "the launcher for @CMD@ is missing, run the MAHA COMMUTE installer again" >&2; exit 1; }
command -v maha-commute >/dev/null 2>&1 || exec "$ORIG" "$@"
case "${1:-}" in
"")      exec maha-commute focus @ID@ ;;
stop)    exec maha-commute stop @ID@ ;;
status)  exec maha-commute status ;;
restart) exec maha-commute restart @ID@ ;;
open)    exec maha-commute open @ID@ ;;
log)     exec maha-commute log @ID@ ;;
*)       exec "$ORIG" "$@" ;;
esac
MAHA_SHIM_TEXT
  sed -i "s/@ID@/$id/g; s/@CMD@/$cmd/g" "$new"
  chmod +x "$new" && mv -f "$new" "$BIN/$cmd"
}
# END SHIM
write_shim "$APP" "$CMD"
sync_key ""

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
