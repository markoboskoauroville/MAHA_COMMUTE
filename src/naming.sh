# The filename rule. It lives here rather than in 05_lib.sh because the
# artefact never needs it: the name is decided when the file is built,
# not when it is run, and a function the delivered file cannot call is
# dead weight inside it. The build and the test both source this, so
# there is still only one implementation of the rule.

# A version number turned into the two places it has to appear, so the
# leading number and the trailing one cannot drift apart by hand.
maha_artefact_name() {
  local n="$1"
  printf '%s-maha_commute_v%s.sh\n' "$n" "$n"
}
