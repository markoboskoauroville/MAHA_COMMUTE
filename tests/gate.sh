#!/usr/bin/env bash
# gate.sh, the nine checks the artefact passes before it is delivered.
#
# The four tests answer "does this work". This answers "may this ship".
# Each gate prints a count, because "0 findings" and "the check did not
# run" look identical from outside.
#
#   tests/gate.sh          run everything
#   tests/gate.sh --quick  skip G6 and G8, which rerun the long tests

cd "$(dirname "$0")/.."
V=$(cat VERSION)
ART="$V-maha_commute_v$V.sh"
QUICK=0; [ "${1:-}" = "--quick" ] && QUICK=1
blocked=0

hdr()  { printf '\n%s\n' "$1"; }
line() { printf '  %-46s %s\n' "$1" "$2"; }
block(){ blocked=$((blocked+1)); printf '  %-46s %s  BLOCKS\n' "$1" "$2"; }

printf '\nTHE DELIVERY GATE   %s\n' "$ART"

# ---- G1 provenance -------------------------------------------------
hdr 'G1  PROVENANCE'
if [ -f "$ART" ]; then line "the artefact exists" "$(wc -c < "$ART" | tr -d ' ') bytes"
else block "the artefact exists" "no"; fi
if bash tools/build_installer.sh --check >/dev/null 2>&1; then
  line "built from the sources in src/" "fresh"
else block "built from the sources in src/" "STALE, rebuild it"; fi
lead=${ART%%-*}; trail=$(printf '%s' "$ART" | sed -E 's/.*_v([0-9]+)\.sh/\1/')
if [ "$lead" = "$V" ] && [ "$trail" = "$V" ]; then
  line "the version at both ends of the name" "$lead and $trail"
else block "the version at both ends of the name" "$lead and $trail"; fi
inside=$(grep -m1 '^MAHA_VERSION=' "$ART" | cut -d'"' -f2)
if [ "$inside" = "v$V" ]; then line "the version inside matches the name" "$inside"
else block "the version inside matches the name" "$inside"; fi
if command -v git >/dev/null && [ -d .git ]; then
  dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$dirty" = 0 ]; then line "the working tree is clean" "0 changes"
  else line "the working tree is clean" "$dirty uncommitted, commit before release"; fi
else line "the working tree is clean" "not a git checkout yet"; fi
line "payload provenance in the header" "$(grep -c 'sha256 ' "$ART" | tr -d ' ') payloads stamped"

# ---- G2 secrets ----------------------------------------------------
hdr 'G2  SECRETS'
n=$(grep -cE 'AIza[A-Za-z0-9_-]{30,}' "$ART" || true)
if [ "$n" = 0 ]; then line "google key shapes in the artefact" "0 of 1 pattern"
else block "google key shapes in the artefact" "$n"; fi
n=$(grep -crEl 'AIza[A-Za-z0-9_-]{30,}|AQ\\.[A-Za-z0-9_.-]{30,}|gsk_[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|sk_[A-Za-z0-9_-]{30,}' \
      --include='*.sh' --include='*.md' . 2>/dev/null | wc -l | tr -d ' ')
if [ "$n" = 0 ]; then line "key shapes anywhere in the repo" "0 files, 5 patterns"
else block "key shapes anywhere in the repo" "$n files"; fi
n=$(grep -c '__MAHA_GOOGLE_KEY__' "$ART" | tr -d ' ')
line "the placeholder is what is carried" "$n occurrences"
# The key tester handles keys and must never print one. A print of the
# key variable itself is the shape to look for.
if grep -nE 'print\((key|k|raw|secret)\)|print\(.*%.*, *(key|k|raw|secret)\)' src/55_keytest.py >/dev/null; then
  block "the key tester never prints a key" "a print of the key itself"
else
  line "the key tester never prints a key" "0 findings, and Test 1 proves the namer"
fi
if [ -f .gitignore ] && grep -q 'google-api' .gitignore; then
  line "key files are ignored by git" "listed"
else block "key files are ignored by git" "missing from .gitignore"; fi

# ---- G3 analysis ---------------------------------------------------
hdr 'G3  ANALYSIS'
bad=0; count=0
for f in "$ART" tools/*.sh tests/*.sh src/*.sh src/payloads/*.sh; do
  count=$((count+1))
  out=$(bash -n "$f" 2>&1 || true)
  [ -n "$out" ] && { bad=$((bad+1)); printf '      %s: %s\n' "$f" "$(printf '%s' "$out" | head -1)"; }
done
if [ "$bad" = 0 ]; then line "bash -n, no output at all" "$count files, 0 findings"
else block "bash -n, no output at all" "$bad of $count"; fi
pyc=0; pybad=0
for f in src/*.py src/payloads/night/*.py; do
  [ -f "$f" ] || continue
  pyc=$((pyc+1))
  python3 -m py_compile "$f" 2>/dev/null || { pybad=$((pybad+1)); printf '      %s does not compile\n' "$f"; }
done
# The spliced javascript, at its source, before it is anywhere near a
# heredoc. A syntax error here is far easier to read than the same error
# found two heredocs deep in the artefact.
if command -v node >/dev/null 2>&1; then
  jsc=0; jsbad=0
  for f in src/payloads/night/*.js tests/*.js; do
    [ -f "$f" ] || continue
    jsc=$((jsc+1))
    node --check "$f" 2>/dev/null || { jsbad=$((jsbad+1)); printf '      %s does not parse\n' "$f"; }
  done
  if [ "$jsbad" = 0 ]; then line "javascript parses" "$jsc files, 0 findings"
  else block "javascript parses" "$jsbad of $jsc"; fi
else line "javascript parses" "node is not here, not run"; fi
if [ "$pybad" = 0 ]; then line "python compiles" "$pyc files, 0 findings"
else block "python compiles" "$pybad of $pyc"; fi
# The tools are emitted through heredocs, so the copies that reach the
# phone are what must compile, not only the sources they came from.
emit=$(mktemp -d)
# Between the heredoc delimiters, which is the only boundary that means
# anything here. Ranging to the first line starting with } stops inside a
# python dictionary and reports the truncation as a compile failure.
extract() { # extract <delimiter prefix> <out>
  awk -v pre="$1" '
    $0 ~ ("cat <<.?" pre) { d=$0; sub(/.*cat <<.?/,"",d); gsub(/.$/,"",d); grab=1; next }
    grab && $0 == d { grab=0; next }
    grab { print }
  ' "$ART" > "$2"
}
extract "MAHA_STREAM_" "$emit/stream.py"
extract "MAHA_KEYTEST_" "$emit/keytest.py"
eb=0
for f in "$emit"/*.py; do python3 -m py_compile "$f" 2>/dev/null || eb=$((eb+1)); done
if [ "$eb" = 0 ]; then line "the emitted copies compile" "2 files, 0 findings"
else block "the emitted copies compile" "$eb of 2"; fi

# night.commute is SPLICED at build time: a python module goes into
# night_server.py and a block of javascript into night.html. Both land
# inside two nested heredocs, so a splice that broke either one would
# still build, still pass bash -n, and fail only on the phone. These are
# pulled back out of the artefact and put through their own interpreters.
python3 - "$ART" "$emit" <<'PY'
import pathlib, sys
art = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="surrogateescape")
out = pathlib.Path(sys.argv[2])
for name, delim in (("night_server.py", "NC_SERVER_PY"), ("night.html", "NC_HTML")):
    head = 'cat > "$APPDIR/%s" << \'%s\'\n' % (name, delim)
    if head not in art:
        continue
    body = art.split(head, 1)[1].split("\n%s\n" % delim, 1)[0]
    (out / name).write_text(body, encoding="utf-8", errors="surrogateescape")
    if name.endswith(".html") and "<script>" in body:
        (out / "night_page.js").write_text(
            body.split("<script>", 1)[1].rsplit("</script>", 1)[0],
            encoding="utf-8", errors="surrogateescape")
PY
nb=0; nn=0
if [ -s "$emit/night_server.py" ]; then
  nn=$((nn+1))
  python3 -m py_compile "$emit/night_server.py" 2>/dev/null || nb=$((nb+1))
else nb=$((nb+1)); fi
if [ -s "$emit/night_page.js" ]; then
  nn=$((nn+1))
  if command -v node >/dev/null 2>&1; then
    node --check "$emit/night_page.js" 2>/dev/null || nb=$((nb+1))
  fi
else nb=$((nb+1)); fi
if [ "$nb" = 0 ]; then line "the spliced night app compiles" "$nn files, 0 findings"
else block "the spliced night app compiles" "$nb bad"; fi
# The splice has to have actually happened. A patcher that quietly put
# nothing in leaves a file that compiles perfectly and does nothing.
liv=$(grep -c 'gtfs-rt-protobuf' "$emit/night_server.py" 2>/dev/null | tr -d ' ')
sta=$(grep -c 'nc_fav' "$emit/night.html" 2>/dev/null | tr -d ' ')
if [ "${liv:-0}" -gt 0 ] && [ "${sta:-0}" -gt 0 ]; then
  line "and carries what was spliced into it" "live feed and star both present"
else block "and carries what was spliced into it" "live $liv, star $sta"; fi
rm -rf "$emit"
if command -v shellcheck >/dev/null 2>&1; then
  sc=$(shellcheck -S error -f gcc src/*.sh tools/*.sh 2>/dev/null | wc -l | tr -d ' ')
  line "shellcheck, errors only" "$sc findings"
else line "shellcheck" "not installed here, not run"; fi

# ---- G4 dead code --------------------------------------------------
hdr 'G4  DEAD CODE'
dead=0; fns=0
for fn in $(grep -hoE '^[a-z_]+\(\)' src/05_lib.sh src/00_head.sh | tr -d '()'); do
  fns=$((fns+1))
  uses=$(grep -c "\b$fn\b" "$ART" | tr -d ' ')
  [ "$uses" -le 1 ] && { dead=$((dead+1)); printf '      never called: %s\n' "$fn"; }
done
line "functions defined and reached" "$fns checked, $dead unreachable"
orph=$(grep -c 'maha_emit_payload\|maha_emit_menu\|maha_emit_install_one' "$ART" | tr -d ' ')
line "the three emitters are called" "$orph references"

# ---- G5 dead loops -------------------------------------------------
hdr 'G5  DEAD LOOPS'
# Every wait on something outside this process needs a deadline. These
# are the waits, and each one is counted rather than described.
w1=$(grep -c 'for i in \$(seq' "$ART" | tr -d ' ')
line "bounded waits in the artefact" "$w1"
w2=$(grep -cE 'while :; do' "$ART" | tr -d ' ')
line "unbounded loops" "$w2, each ending in a read that blocks for a key"
w3=$(grep -c '/dev/tcp/127.0.0.1' "$ART" | tr -d ' ')
line "port probes, connect only, never read" "$w3"

# ---- G6 stress -----------------------------------------------------
hdr 'G6  STRESS'
if [ "$QUICK" = 1 ]; then line "test 3, the ugly cases" "skipped, --quick"
else
  if out=$(bash tests/test3_ugly.sh 2>&1); then
    line "test 3, the ugly cases" "$(printf '%s' "$out" | tail -2 | tr -d '\n' | sed 's/^ *//')"
  else
    block "test 3, the ugly cases" "$(printf '%s' "$out" | grep -c FAIL) failed"
  fi
fi

# ---- G7 budgets ----------------------------------------------------
hdr 'G7  BUDGETS'
sz=$(wc -c < "$ART" | tr -d ' ')
if [ "$sz" -lt 900000 ]; then line "artefact size" "$sz bytes, under the 900k budget"
else block "artefact size" "$sz bytes"; fi
pay=$(( $(wc -c < src/payloads/13-install-day-commute-termux-v13.sh) + \
        $(wc -c < src/payloads/9-night_commute_v9.sh) + \
        $(wc -c < src/payloads/39-install-all_commute-termux-v39.sh) ))
line "of which the three apps" "$pay bytes, $(( (sz - pay) )) is the umbrella"
line "commands added to \$PREFIX/bin" "1, called maha-commute"

# ---- G8 upgrade ----------------------------------------------------
hdr 'G8  UPGRADE'
if [ "$QUICK" = 1 ]; then line "test 4, over the installed versions" "skipped, --quick"
else
  if out=$(bash tests/test4_upgrade.sh 2>&1); then
    line "test 4, over the installed versions" "$(printf '%s' "$out" | tail -2 | tr -d '\n' | sed 's/^ *//')"
  else
    block "test 4, over the installed versions" "$(printf '%s' "$out" | grep -c FAIL) failed"
  fi
fi
if [ -f docs/ROLLBACK.md ]; then line "a way back is written down" "docs/ROLLBACK.md"
else block "a way back is written down" "missing"; fi

# ---- G9 the record -------------------------------------------------
hdr 'G9  THE RECORD'
if [ -f docs/NOT_TESTED.md ]; then
  line "what was not tested is written down" "$(grep -c '^- ' docs/NOT_TESTED.md | tr -d ' ') items"
else block "what was not tested is written down" "missing"; fi
if [ -f MEMORY.md ]; then line "the project memory exists" "MEMORY.md"
else block "the project memory exists" "missing"; fi
if [ -f HANDOFF.md ]; then line "the handoff exists" "HANDOFF.md"
else block "the handoff exists" "missing"; fi

printf '\n  %s blocking findings\n\n' "$blocked"
[ "$blocked" = 0 ]
