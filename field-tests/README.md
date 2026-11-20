# field-tests

Results of testing MAHA_COMMUTE on a real Android emulator with real Termux,
written by the LOCAL Claude Code and read by the cloud Claude Code.

One folder per run: `YYYY-MM-DD_v<VERSION>/` holding `REPORT.md`, `results.json`,
`logs/`, `screenshots/` and `soak.csv`. How a run is done, and what goes in each
file, is in `docs/LOCAL_TEST_PROMPT.md`. The rule that governs it is the first
section of `MANIFEST.md`: **the local machine tests, the cloud machine upgrades.**

Never put a key in here. `tests/gate.sh` looks for key shapes in every `.md`
file; a screenshot or a log is not looked at, so the local tester greps first.
