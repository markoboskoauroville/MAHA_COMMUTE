#!/usr/bin/env bash
# verify_installer.sh, run on a file you have not run yet.
#
#   tools/verify_installer.sh 1-maha_commute_v1.sh
#
# The installer has a --verify switch of its own, and this is not that.
# That one runs the file, which is exactly what you cannot do with a
# file you do not yet trust, and a file damaged badly enough may never
# reach its own verify code. This one only reads.
#
# Four checks, and each has to be able to fail while the other three
# pass. The pair worth understanding is 3 and 4. A file cut in half in
# the middle of a heredoc makes bash -n print
#
#     warning: here-document at line N delimited by end-of-file
#
# on stderr AND EXIT ZERO. So the exit status is not the check: the
# absence of output is. And a truncated file cannot carry the last
# line, so the sentinel answers a question bash -n cannot, which is
# whether all of it arrived. A file cut mid heredoc with a sentinel
# glued back on is caught by check 3 alone; a whole file with its last
# line missing is caught by check 4 alone. That is what keeps them two
# checks rather than one wearing two names.

F="${1:-}"
[ -n "$F" ] || { printf 'usage: verify_installer.sh <file>\n'; exit 2; }
[ -f "$F" ] || { printf 'no such file: %s\n' "$F"; exit 2; }

fails=0
green() { printf '  ok    %-10s %s\n' "$1" "$2"; }
red()   { printf '  FAIL  %-10s %s\n' "$1" "$2"; fails=$((fails+1)); }

printf '\nverifying %s\n\n' "$F"

sz=$(wc -c < "$F" | tr -d ' ')
if [ "$sz" -ge 400000 ]; then green size "$sz bytes"
else red size "$sz bytes, too small to hold three apps"; fi

if head -1 "$F" | grep -q '^#!'; then green shebang "it is a script"
else red shebang "the first line is not a shebang"; fi

nout=$(bash -n "$F" 2>&1 || true)
if [ -z "$nout" ]; then green parse "bash -n said nothing at all"
else red parse "$(printf '%s' "$nout" | head -1)"; fi

if tail -1 "$F" | grep -q '^# MAHA_COMMUTE_SENTINEL'; then
  green sentinel "$(tail -1 "$F" | cut -c3-)"
else red sentinel "the file ends early"; fi

printf '\n  4 checks, %s failed\n' "$fails"
if [ "$fails" != 0 ]; then
  printf '  nothing was changed. Fetch the file again.\n\n'
  exit 1
fi
printf '\n'
