#!/usr/bin/env bash
# build_uninstaller.sh, the standalone uninstaller.
#
# The uninstaller already ships inside the umbrella, at
# ~/.maha.commute/uninstall.sh. This builds the same file as a thing you can
# run on a phone that has NO umbrella on it: the three apps installed by
# hand months ago, the v1 command, the old names. That is the phone that
# most needs an uninstaller and it is exactly the phone that cannot reach
# the one inside.
#
# Same source, src/70_uninstall.sh, so there is one implementation. It
# already stands up without env.sh, because it was written to.

set -euo pipefail
cd "$(dirname "$0")/.."
. src/naming.sh
V=$(tr -d ' \n' < VERSION)
OUT="${V}-maha_commute_uninstall_v${V}.sh"
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT

{
  printf '#!/data/data/com.termux/files/usr/bin/bash\n'
  printf '# %s\n#\n' "$OUT"
  printf '# The MAHA COMMUTE uninstaller, on its own. Run it anywhere:\n#\n'
  printf '#     bash %s\n#\n' "$OUT"
  printf '# It needs nothing installed and it changes nothing until asked. It\n'
  printf '# looks on disk, lists what it finds with sizes, and offers four\n'
  printf '# routes: the leftovers of old versions, the umbrella only,\n'
  printf '# everything, or nothing. The full wipe asks for a typed word.\n#\n'
  printf '# Generated from src/70_uninstall.sh by tools/build_uninstaller.sh.\n'
  printf '# built %s\n' "$(date -u '+%Y-%m-%d %H:%M UTC')"
  tail -n +2 src/70_uninstall.sh
  printf '\n# MAHA_UNINSTALL_SENTINEL v%s\n' "$V"
} > "$TMP"

out=$(bash -n "$TMP" 2>&1 || true)
[ -z "$out" ] || { printf 'build: does not parse: %s\n' "$out" >&2; exit 1; }
grep -qE 'AIza[A-Za-z0-9_-]{30,}|AQ\.[A-Za-z0-9_.-]{30,}' "$TMP" && \
  { printf 'build: a key shape reached the uninstaller\n' >&2; exit 1; }
tail -1 "$TMP" | grep -q '^# MAHA_UNINSTALL_SENTINEL' || { printf 'build: no sentinel\n' >&2; exit 1; }

cp "$TMP" "$OUT"; chmod +x "$OUT"
printf 'built %s  %s bytes\n' "$OUT" "$(wc -c < "$OUT" | tr -d ' ')"
