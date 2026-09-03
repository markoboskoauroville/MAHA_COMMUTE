# ---------------------------------------------------------------
# --verify, which changes nothing
#
# The honest limit of this switch: a file damaged badly enough may
# never reach this code at all. The check that matters runs on a file
# you have not run yet, and that one is tools/verify_installer.sh in
# the repository. This is the convenience version.
# ---------------------------------------------------------------
if [ "$VERIFY_ONLY" = "1" ]; then
  SELF="$0"
  printf "\n  ${KEY}verifying${OFF} ${DIM}%s${OFF}\n\n" "$SELF"
  vfail=0
  sz=$(wc -c < "$SELF" | tr -d ' ')
  if [ "$sz" -ge 400000 ]; then
    printf "  ${OK}size${OFF}      ${DIM}%s bytes${OFF}\n" "$sz"
  else
    printf "  ${BAD}size${OFF}      ${DIM}%s bytes, too small to hold three apps${OFF}\n" "$sz"
    vfail=$((vfail+1))
  fi
  if head -1 "$SELF" | grep -q '^#!'; then
    printf "  ${OK}shebang${OFF}   ${DIM}it is a script${OFF}\n"
  else
    printf "  ${BAD}shebang${OFF}   ${DIM}first line is not a shebang${OFF}\n"; vfail=$((vfail+1))
  fi
  nout=$(bash -n "$SELF" 2>&1 || true)
  if [ -z "$nout" ]; then
    printf "  ${OK}parse${OFF}     ${DIM}bash -n said nothing at all${OFF}\n"
  else
    printf "  ${BAD}parse${OFF}     ${DIM}%s${OFF}\n" "$(printf '%s' "$nout" | head -1)"
    vfail=$((vfail+1))
  fi
  if tail -1 "$SELF" | grep -q '^# MAHA_COMMUTE_SENTINEL'; then
    printf "  ${OK}sentinel${OFF}  ${DIM}the last line is present${OFF}\n"
  else
    printf "  ${BAD}sentinel${OFF}  ${DIM}the file ends early${OFF}\n"; vfail=$((vfail+1))
  fi
  printf "\n  ${DIM}4 checks, %s failed${OFF}\n\n" "$vfail"
  [ "$vfail" = "0" ] || exit 1
  exit 0
fi

# ---------------------------------------------------------------
# the banner
# ---------------------------------------------------------------
clear 2>/dev/null || true
printf "\n"
printf "  ${AM}%s${OFF}  ${KEY}MAHA COMMUTE${OFF}  ${DIM}installer %s${OFF}\n" "ॐ" "$MAHA_VERSION"
printf "  ${DIM}day, night and all of Zagreb, under one word${OFF}\n\n"

# ---------------------------------------------------------------
# is this a phone
# ---------------------------------------------------------------
step "checking Termux"
if [ -z "${PREFIX:-}" ] || [ ! -d "$BIN" ]; then
  fail_ "this installer is for Termux on Android"
  printf "\n  ${DIM}nothing was written.${OFF}\n\n"
  exit 1
fi
done_

# ---------------------------------------------------------------
# what is here already, before anything is asked
# ---------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }
HAVE_PY=0;   have python  && HAVE_PY=1
have python3 && HAVE_PY=1
HAVE_OPEN=0; have termux-open-url && HAVE_OPEN=1
HAVE_FUSER=0; have fuser && HAVE_FUSER=1
HAVE_SHA=0;  have sha256sum && HAVE_SHA=1
HAVE_B64=0;  have base64 && HAVE_B64=1
REQ_MISSING=0
[ "$HAVE_PY" = "0" ] && REQ_MISSING=$((REQ_MISSING+1))

dep_row() {
  if [ "$2" = "1" ]; then
    printf "    ${OK}ok${OFF}       ${SAND}%-14s${OFF} ${DIM}%s${OFF}\n" "$1" "$3"
  elif [ "$4" = "req" ]; then
    printf "    ${BAD}MISSING${OFF}  ${SAND}%-14s${OFF} ${DIM}%s${OFF}\n" "$1" "$3"
  else
    printf "    ${DIM}absent   %-14s %s${OFF}\n" "$1" "$3"
  fi
}
printf "\n  ${KEY}what this phone has${OFF}\n"
dep_row "python"       "$HAVE_PY"    "all three servers"        "req"
dep_row "termux-api"   "$HAVE_OPEN"  "opens the page by itself" "opt"
dep_row "fuser"        "$HAVE_FUSER" "frees a busy port"        "opt"
dep_row "sha256sum"    "$HAVE_SHA"   "checks the payloads"      "opt"
dep_row "base64"       "$HAVE_B64"   "used by all.commute"      "opt"
printf "\n"

# ---------------------------------------------------------------
# which apps
#
# All three, always. There used to be a picker here and it was the wrong
# question: the answer was always all three, and asking it once per install
# was a keystroke charged for nothing. --apps still exists for a test that
# needs to install a subset, and nobody types it.
# ---------------------------------------------------------------
if [ -n "$PICK" ]; then
  CHOSEN=$(maha_parse_pick "$PICK") || {
    printf "  ${BAD}--apps %s is not something I can read${OFF}\n\n" "$PICK"; exit 2; }
else
  CHOSEN=$(app_ids | tr '\n' ' ')
fi
# ---------------------------------------------------------------
# ---------------------------------------------------------------
# dependencies, decided rather than asked
#
# Present ones are left alone. Missing ones are fetched if anything is
# missing at all and the network answers. There is no question here because
# there was never a real choice in it: nobody wants a half installed app,
# and the offline case is what happens on its own when the network does not
# answer. --offline still forces the old behaviour for a test.
# ---------------------------------------------------------------
NEED=""
[ "$HAVE_PY" = "0" ]    && NEED="$NEED python"
[ "$HAVE_OPEN" = "0" ]  && NEED="$NEED termux-api"
[ "$HAVE_FUSER" = "0" ] && NEED="$NEED psmisc"

if [ "$MODE" = "offline" ]; then
  step "dependencies"; skip_
elif [ -z "$NEED" ]; then
  step "dependencies"; printf " ${OK}all present${OFF}\n"
else
  printf "  ${DIM}missing:${OFF}%s\n" "$NEED"
  for pkgname in $NEED; do
    step "installing $pkgname"
    if pkg install -y "$pkgname" >/dev/null 2>&1; then done_; else fail_ "not fetched"; fi
  done
  command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 && HAVE_PY=1
fi
# ---------------------------------------------------------------
# the google key
#
# Looked for in this order, and asked for only when every one of them
# comes back empty. The shared store wins, then any app already on the
# phone, then a file dropped in Downloads. The key is never printed.
# ---------------------------------------------------------------
step "google maps key"
mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR" 2>/dev/null || true
FOUND=""
if [ -s "$KEYFILE" ]; then
  FOUND="the shared store"
else
  for c in "$HOME/.commute/google-api.txt" \
           "$HOME/.nightcommute/gmaps-api.txt" \
           "$HOME/.all.commute/google-api.txt" \
           "./google-api.txt" "./Google-maps-api.txt" \
           "$HOME/storage/downloads/google-api.txt" \
           "$HOME/storage/downloads/Google-maps-api.txt" \
           "$HOME/downloads/google-api.txt"; do
    if [ -s "$c" ]; then
      grep -v '^[[:space:]]*$' "$c" | head -1 | maha_clean_key > "$KEYFILE"
      chmod 600 "$KEYFILE"
      FOUND="$c"
      break
    fi
  done
fi
if [ -n "$FOUND" ]; then
  printf " ${OK}found${OFF} ${DIM}(%s)${OFF}\n" "$FOUND"
  ASK_KEY=0
else
  skip_
  ASK_KEY=1
fi

if [ "$ASK_KEY" = "1" ]; then
  printf "  ${DIM}no google key here yet. The apps work without one: the maps${OFF}\n"
  printf "  ${DIM}draw, the photographs do not.${OFF} ${SAND}maha-commute key${OFF} ${DIM}adds one.${OFF}\n"
fi

# ---------------------------------------------------------------
# the umbrella itself
#
# Everything under ~/.maha.commute is written before any app is
# installed, so that a failure inside one app still leaves a working
# menu behind and the other two can be added from it.
# ---------------------------------------------------------------
step "the umbrella"
mkdir -p "$APPHOME" "$PAYDIR" "$STAMPDIR" "$APPHOME/tmp"
chmod 700 "$APPHOME/tmp" 2>/dev/null || true
rm -f "$PAYDIR"/*.new 2>/dev/null || true
{
  printf '# written by the MAHA COMMUTE installer %s\n' "$MAHA_VERSION"
  printf 'MAHA_VERSION=%s\n' "$MAHA_VERSION"
  printf 'BIN="%s"\n' "$BIN"
  printf 'APPHOME="%s"\n' "$APPHOME"
  printf 'PAYDIR="%s"\n' "$PAYDIR"
  printf 'KEYDIR="%s"\n' "$KEYDIR"
  printf 'KEYFILE="%s"\n' "$KEYFILE"
  printf 'STAMPDIR="%s"\n' "$STAMPDIR"
  printf 'MAHA_APPS="%s"\n' "$MAHA_APPS"
} > "$APPHOME/env.sh.new"
mv -f "$APPHOME/env.sh.new" "$APPHOME/env.sh"
done_

step "payloads, all three"
for id in $(app_ids); do
  maha_emit_payload "$id" > "$PAYDIR/$id.payload.sh.new"
  mv -f "$PAYDIR/$id.payload.sh.new" "$PAYDIR/$id.payload.sh"
  chmod 600 "$PAYDIR/$id.payload.sh"
done
{
  for id in $(app_ids); do
    printf '%s|%s\n' "$id" "$(wc -c < "$PAYDIR/$id.payload.sh" | tr -d ' ')"
  done
} > "$PAYDIR/SIZES"
if [ "$HAVE_SHA" = "1" ]; then
  ( cd "$PAYDIR" && sha256sum day.payload.sh night.payload.sh all.payload.sh > SHA256SUMS )
fi
done_

step "the install routine"
maha_emit_install_one | install_command "$APPHOME/install-one.sh"
done_

step "the stream checker"
maha_emit_stream > "$APPHOME/stream.py.new"
mv -f "$APPHOME/stream.py.new" "$APPHOME/stream.py"
done_

step "the key tester"
maha_emit_keytest > "$APPHOME/keytest.py.new"
mv -f "$APPHOME/keytest.py.new" "$APPHOME/keytest.py"
done_

step "the updater"
maha_emit_update | install_command "$APPHOME/update.sh"
done_

step "the uninstaller"
maha_emit_uninstall | install_command "$APPHOME/uninstall.sh"
done_

step "the launcher"
maha_emit_menu | install_command "$BIN/maha-commute"
done_

step "the updater command"
printf '#!%s\nexec bash "%s/update.sh" "$@"\n' "$BIN/bash" "$APPHOME" \
  | install_command "$BIN/maha-commute-update"
done_

# v1 of this umbrella left a command called commute. Leaving it behind
# means two launchers on the PATH, one of them stale, and the stale one is
# the shorter word so it is the one that gets typed. It is replaced by a
# line that points at the new name rather than deleted, because a command
# that vanishes with no explanation reads as a broken install.
if [ -f "$BIN/commute" ] && ! grep -q 'maha-commute' "$BIN/commute" 2>/dev/null; then
  step "the old commute command"
  {
    printf '#!%s\n' "$BIN/bash"
    printf '# left by MAHA COMMUTE v2. The launcher is called maha-commute now.\n'
    printf 'printf "\\n  this is maha-commute now.\\n\\n"\n'
    printf 'exec "%s/maha-commute" "$@"\n' "$BIN"
  } | install_command "$BIN/commute"
  done_
fi

# ---------------------------------------------------------------
# the apps
# ---------------------------------------------------------------
# What actually moved.
#
# An update that reinstalls all three every time is three apps rebuilding
# their caches to no purpose, and it hides the one thing worth reading: which
# app changed. So each app is compared against the checksum of the payload
# that is on the phone, and an app whose payload is identical is not touched
# at all.
payload_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$PAYDIR/$1.payload.sh" | cut -d" " -f1
  else
    wc -c < "$PAYDIR/$1.payload.sh" | tr -d ' '
  fi
}

FAILED=""
INSTALLED=""
UNCHANGED=""
for id in $CHOSEN; do
  want=$(payload_sha "$id")
  have=$(cat "$STAMPDIR/$id.sha" 2>/dev/null || printf 'none')
  if is_installed "$id" && [ "$want" = "$have" ]; then
    UNCHANGED="$UNCHANGED $id"
    continue
  fi
  if bash "$APPHOME/install-one.sh" "$id" "--$MODE"; then
    INSTALLED="$INSTALLED $id"
  else
    FAILED="$FAILED $id"
  fi
done

# ---------------------------------------------------------------
# what happened
# ---------------------------------------------------------------
printf "\n"
printf "  ${AM}%s${OFF}  ${KEY}MAHA COMMUTE${OFF}  ${DIM}%s${OFF}\n\n" "ॐ" "$MAHA_VERSION"
for id in $(app_ids); do
  row=$(app_row "$id"); cmd=$(field "$row" 2); port=$(field "$row" 5)
  if is_installed "$id"; then
    printf "    ${OK}on${OFF}   ${SAND}%-15s${OFF} ${DIM}%s, port %s${OFF}\n" \
      "$cmd" "$(stamped_version "$id")" "$port"
  else
    printf "    ${DIM}off  %-15s add it from the menu${OFF}\n" "$cmd"
  fi
done
if [ -n "$INSTALLED" ]; then
  printf "\n    ${OK}updated:${OFF}"
  for id in $INSTALLED; do printf " ${SAND}%s${OFF}" "$(field "$(app_row "$id")" 2)"; done
  printf "\n"
fi
if [ -n "$UNCHANGED" ]; then
  printf "    ${DIM}already current, left alone:%s${OFF}\n" \
    "$(for id in $UNCHANGED; do printf ' %s' "$(field "$(app_row "$id")" 2)"; done)"
fi
if [ -n "$FAILED" ]; then
  printf "\n    ${BAD}did not finish:${OFF}${DIM}%s${OFF}\n" "$FAILED"
fi
printf "\n  type ${KEY}maha-commute${OFF} ${DIM}for the launcher${OFF}\n"
printf "  ${DIM}or the app name on its own: day.commute, night.commute, all.commute${OFF}\n"
printf "\n  ${DIM}the three payloads are kept in %s${OFF}\n" "$PAYDIR"
printf "  ${DIM}so any app can be added or removed later with no download${OFF}\n"
if [ "$HAVE_PY" = "0" ]; then
  printf "\n  ${SAND}python is still missing. Run this again and press y.${OFF}\n"
fi
printf "\n  ${DIM}run termux-setup-storage once, by hand, if you have not:${OFF}\n"
printf "  ${DIM}nothing can do it for you, and without it the phone's own${OFF}\n"
printf "  ${DIM}Downloads folder is not reachable from here.${OFF}\n\n"
