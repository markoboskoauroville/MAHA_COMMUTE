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
# All three are on the screen whether they are wanted or not, and one
# already on the phone says so, so the choice is made against what is
# actually here rather than against a memory of it.
# ---------------------------------------------------------------
CHOSEN=""
if [ -n "$PICK" ]; then
  CHOSEN=$(maha_parse_pick "$PICK") || {
    printf "  ${BAD}--apps %s is not something I can read${OFF}\n\n" "$PICK"; exit 2; }
else
  while :; do
    printf "  ${KEY}which apps${OFF}\n"
    n=0
    for id in $(app_ids); do
      n=$((n+1)); row=$(app_row "$id")
      cmd=$(field "$row" 2); ver=$(field "$row" 4); desc=$(field "$row" 6)
      if is_installed "$id"; then
        printf "    ${KEY}%s${OFF}  ${SAND}%-15s${OFF} ${DIM}%-4s %s${OFF} ${OK}installed${OFF}\n" \
          "$n" "$cmd" "$ver" "$desc"
      else
        printf "    ${KEY}%s${OFF}  ${SAND}%-15s${OFF} ${DIM}%-4s %s${OFF}\n" \
          "$n" "$cmd" "$ver" "$desc"
      fi
    done
    printf "\n    ${DIM}type the numbers together, 13 for two of them${OFF}\n"
    printf "    ${KEY}Enter${OFF} ${DIM}all three${OFF}      ${KEY}n${OFF} ${DIM}none, just the menu${OFF}\n"
    printf "\n  ${AM}>${OFF} "
    IFS= read -r ANS || ANS=""
    if CHOSEN=$(maha_parse_pick "$ANS"); then break; fi
    printf "\n  ${SAND}1, 2 and 3 are the ones there are. Try again.${OFF}\n\n"
  done
fi

if [ -z "$CHOSEN" ]; then
  printf "\n  ${DIM}no apps chosen. The menu and all three payloads go on anyway,${OFF}\n"
  printf "  ${DIM}so any of them can be added later from inside commute.${OFF}\n"
else
  printf "\n  ${DIM}installing:${OFF}"
  for id in $CHOSEN; do printf " ${SAND}%s${OFF}" "$(field "$(app_row "$id")" 2)"; done
  printf "\n"
fi

# ---------------------------------------------------------------
# offline or online
# ---------------------------------------------------------------
if [ -z "$MODE" ]; then
  printf "\n  ${KEY}install mode${OFF}\n"
  printf "    ${KEY}Enter${OFF}  ${DIM}offline, use what is already here${OFF}\n"
  printf "    ${KEY}y${OFF}      ${DIM}fetch the missing dependencies first${OFF}\n"
  if [ "$REQ_MISSING" -gt 0 ]; then
    printf "\n    ${SAND}python is not here, so y is the one to press${OFF}\n"
  fi
  printf "\n  ${AM}>${OFF} "
  IFS= read -r ANS || ANS=""
  case "$ANS" in [yY]*) MODE="online" ;; *) MODE="offline" ;; esac
fi
printf "  ${DIM}mode: %s${OFF}\n\n" "$MODE"

if [ "$MODE" = "online" ]; then
  step "python runtime"
  if [ "$HAVE_PY" = "0" ]; then
    printf " ${SAND}installing${OFF}\n"
    pkg install -y python >/dev/null 2>&1 || yes | pkg install python || true
    step "python runtime"; done_
  else
    done_
  fi
  step "termux-api tools"
  if [ "$HAVE_OPEN" = "0" ]; then
    printf " ${SAND}installing${OFF}\n"
    pkg install -y termux-api >/dev/null 2>&1 || true
    step "termux-api tools"; done_
  else
    done_
  fi
  step "psmisc, for fuser"
  if [ "$HAVE_FUSER" = "0" ]; then
    printf " ${SAND}installing${OFF}\n"
    pkg install -y psmisc >/dev/null 2>&1 || true
    step "psmisc, for fuser"; done_
  else
    done_
  fi
else
  step "dependency install"; skip_
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
  printf "\n  ${KEY}no google maps key on this phone${OFF}\n"
  printf "  ${DIM}the apps work without one. The maps draw, the photographs${OFF}\n"
  printf "  ${DIM}and the 360 view do not. It can be added later with${OFF} ${SAND}commute key${OFF}\n"
  printf "\n  ${KEY}Enter${OFF} ${DIM}carry on without it${OFF}   ${KEY}p${OFF} ${DIM}paste one now${OFF}\n"
  printf "\n  ${AM}>${OFF} "
  IFS= read -r ANS || ANS=""
  case "$ANS" in
    p|P)
      printf "\n  ${DIM}paste the key, then Enter${OFF}\n  ${AM}>${OFF} "
      IFS= read -r NEWKEY || NEWKEY=""
      NEWKEY=$(printf '%s' "$NEWKEY" | maha_clean_key)
      if [ -n "$NEWKEY" ]; then
        printf '%s\n' "$NEWKEY" > "$KEYFILE"; chmod 600 "$KEYFILE"
        printf "\n  ${OK}stored${OFF} ${DIM}%s characters${OFF}\n" "${#NEWKEY}"
      else
        printf "\n  ${DIM}nothing was pasted, carrying on without${OFF}\n"
      fi ;;
  esac
fi
printf "\n"

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

step "the commute menu"
maha_emit_menu | install_command "$BIN/commute"
done_

# ---------------------------------------------------------------
# the apps
# ---------------------------------------------------------------
FAILED=""
INSTALLED=""
for id in $CHOSEN; do
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
if [ -n "$FAILED" ]; then
  printf "\n    ${BAD}did not finish:${OFF}${DIM}%s${OFF}\n" "$FAILED"
fi
printf "\n  type ${KEY}commute${OFF} ${DIM}for the menu${OFF}\n"
printf "  ${DIM}or the app name on its own: day.commute, night.commute, all.commute${OFF}\n"
printf "\n  ${DIM}the three payloads are kept in %s${OFF}\n" "$PAYDIR"
printf "  ${DIM}so any app can be added or removed later with no download${OFF}\n"
if [ "$HAVE_PY" = "0" ]; then
  printf "\n  ${SAND}python is still missing. Run this again and press y.${OFF}\n"
fi
printf "\n  ${DIM}run termux-setup-storage once, by hand, if you have not:${OFF}\n"
printf "  ${DIM}nothing can do it for you, and without it the phone's own${OFF}\n"
printf "  ${DIM}Downloads folder is not reachable from here.${OFF}\n\n"
