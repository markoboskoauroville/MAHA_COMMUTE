#!/usr/bin/env bash
# Startup update: a newer verified GitHub installer is applied without input.

set -euo pipefail
cd "$(dirname "$0")/.."

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export PATH="$T/bin:$PATH"
mkdir -p "$HOME/.maha.commute" "$T/bin" "$T/usr/bin"
export APPHOME="$HOME/.maha.commute"
export BIN="$T/usr/bin"

cat > "$APPHOME/env.sh" <<EOF
MAHA_VERSION=v27
MAHA_APPS='day|day.commute
night|night.commute
all|all.commute'
APPHOME='$APPHOME'
BIN='$BIN'
EOF
for app in day night all; do printf '#!/bin/sh\nexit 0\n' > "$BIN/$app.commute"; chmod +x "$BIN/$app.commute"; done

CAND="$T/99-maha_commute_v99.sh"
python3 - "$CAND" <<'PY'
import sys
path = sys.argv[1]
with open(path, "w") as f:
    f.write("#!/usr/bin/env bash\n")
    f.write('MAHA_VERSION="v99"\n')
    f.write('printf "%s\\n" "$*" > "$HOME/auto-update-ran"\n')
    f.write("#" * 410000 + "\n")
    f.write("# MAHA_COMMUTE_SENTINEL v99 test\n")
PY
chmod +x "$CAND"

cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  */VERSION) printf '%s\n' "${FAKE_REMOTE_VERSION:-99}" ;;
  *.sh)
    [ -n "$out" ] || exit 1
    cp "$FAKE_CANDIDATE" "$out"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$T/bin/curl"

export FAKE_CANDIDATE="$CAND"
export MAHA_UPDATE_RAW="https://test.invalid/main"
MAHA_VERSION=v27 bash src/60_update.sh --auto > "$T/auto.log" 2>&1
[ -s "$HOME/auto-update-ran" ]
grep -q -- '--offline --apps 123' "$HOME/auto-update-ran"
grep -q 'automatic update: installing v99 without a prompt' "$T/auto.log"
[ -s "$APPHOME/last-update-check" ]

rm -f "$HOME/auto-update-ran" "$APPHOME/last-update-check"
FAKE_REMOTE_VERSION=27 bash src/60_update.sh --auto > "$T/current.log" 2>&1
[ ! -e "$HOME/auto-update-ran" ]
grep -q 'v27 is the newest there is' "$T/current.log"
[ -s "$APPHOME/last-update-check" ]

grep -q 'auto_update_at_start "$@"' src/20_menu.sh
grep -q 'MAHA_AUTO_UPDATE_TRIED=1 exec "$BIN/maha-commute" "$@"' src/20_menu.sh
grep -q 'last-update-check' src/20_menu.sh

DAY=$(python3 tools/patch_payload.py src/payloads/13-install-day-commute-termux-v13.sh day)
NIGHT=$(python3 tools/patch_payload.py src/payloads/9-night_commute_v9.sh night)
ALL=$(python3 tools/patch_payload.py src/payloads/39-install-all_commute-termux-v39.sh all)
grep -q 'id="mahaCacheEnabled"' <<<"$DAY"
grep -q 'id="mahaCacheEnabled"' <<<"$NIGHT"
grep -q 'id="mahaCacheEnabled"' <<<"$ALL"
grep -q 'start_update(not _maha_cache_enabled())' <<<"$DAY"
grep -q 'rebuild_night(force=not use_cache)' <<<"$NIGHT"
grep -q 'r = rebuild(not use_cache)' <<<"$ALL"
grep -q 'if (MAHA_CACHE_ENABLED) loadStationCache()' <<<"$ALL"
grep -q 'if (MAHA_CACHE_ENABLED) {' <<<"$ALL"

printf 'startup auto-update and cache policy: 17 passed, 0 failed\n'
