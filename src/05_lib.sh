# ---------------------------------------------------------------
# The pure part. No side effects on load, so a test can source this
# file on its own and attack the logic without starting anything.
# ---------------------------------------------------------------

field() { printf '%s' "$1" | cut -d'|' -f"$2"; }

app_row() { printf '%s\n' "$MAHA_APPS" | grep "^$1|" || true; }

app_ids() { printf '%s\n' "$MAHA_APPS" | cut -d'|' -f1; }

# The number a person types in the picker, in the order the family is
# listed rather than the order it was typed. 1 day, 2 night, 3 all.
#
#   ""  a  all           all three
#   n  none  0  q        nothing
#   13  31  113          day and all, once each
#   anything else        rejected, exit 2, so the caller can ask again
maha_parse_pick() {
  local raw="$1" lower out="" c
  lower=$(printf '%s' "$raw" | tr 'A-Z' 'a-z' | tr -d ' \t')
  case "$lower" in
    ""|a|all)      printf 'day night all\n'; return 0 ;;
    n|none|0|q)    printf '\n'; return 0 ;;
  esac
  local want_day=0 want_night=0 want_all=0
  local i=0
  while [ "$i" -lt "${#lower}" ]; do
    c="${lower:$i:1}"
    case "$c" in
      1) want_day=1 ;;
      2) want_night=1 ;;
      3) want_all=1 ;;
      ,|+|/) ;;
      *) return 2 ;;
    esac
    i=$((i+1))
  done
  [ "$want_day" = 1 ]   && out="$out day"
  [ "$want_night" = 1 ] && out="$out night"
  [ "$want_all" = 1 ]   && out="$out all"
  printf '%s\n' "${out# }"
  return 0
}

# A Google API key is letters, digits, underscore and minus and
# nothing else. Cleaning by shape at the moment it is stored means the
# key can never carry a character that means something to sed, to the
# shell, or to the file it is written into. A filter used this way
# fails closed: a key of an unknown shape comes back short or empty and
# the maps quietly do not draw, which is visible. The same filter used
# to hide a key in printed output would fail open, which is why nothing
# here ever prints one.
maha_clean_key() {
  tr -cd 'A-Za-z0-9_-' | head -c 200
}

# A file counts as holding a key only if, once cleaned, it is long enough to be
# one. A lone newline (one byte, so `-s` calls it non-empty) used to win over the
# real key in another app's folder and fill the shared store with nothing.
maha_key_ok() {   # maha_key_ok FILE
  [ -f "$1" ] && [ "$(grep -v '^[[:space:]]*$' "$1" 2>/dev/null | head -1 | maha_clean_key | wc -c | tr -d ' ')" -ge 20 ]
}

# The truth about an app is the command on disk AND its own files. The stamp
# file only supplies the version. A command whose folder was deleted is not an
# installed app (field test v21, F4): the installer called it "already current"
# and left it broken.
app_files_present() {
  local row dir proc
  row=$(app_row "$1"); dir=$(field "$row" 3); proc=$(field "$row" 7)
  [ -n "$dir" ] && [ -f "$HOME/$dir/$(basename "$proc")" ]
}
is_installed() {
  local cmd; cmd=$(field "$(app_row "$1")" 2)
  [ -n "$cmd" ] && [ -x "$BIN/$cmd" ] && app_files_present "$1"
}

stamped_version() {
  if [ -f "$STAMPDIR/$1" ]; then
    tr -d ' \n' < "$STAMPDIR/$1"
  else
    printf '?'
  fi
}

# A port that answers is an app that is running. Nothing else on the
# phone claims these three numbers.
port_live() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && exec 3<&- && return 0
  return 1
}

# Write a file beside its own name and rename it over the top. A plain
# cat into a script that is currently being read truncates the file the
# running shell is reading from, and bash then carries on at the old
# byte offset into whatever is there now.
install_command() {
  local dest="$1"
  cat > "$dest.new"
  sed -i 's/\r$//' "$dest.new" 2>/dev/null || true
  chmod +x "$dest.new"
  mv -f "$dest.new" "$dest"
}
