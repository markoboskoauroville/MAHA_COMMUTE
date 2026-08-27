# HANDOFF

**For the next chat, or the next Claude Code session, working on MAHA_COMMUTE.**

Written 27.8.2026, at the end of the session that built v1.

---

## Read first

`MEMORY.md` in this repo. Then `MANTRA_MANIFEST/START_HERE.md`, and from it
`four-tests.md`, `secrets.md`, `design-language.md`, `termux-app.md` and
`versioning.md`. This project matches all five of those rows.

## The shape in one paragraph

One generated file, `1-maha_commute_v1.sh`, carrying three whole app installers
inside it. `tools/build_installer.sh` writes it from `src/`; nothing is edited
by hand. It installs the apps the person picks, writes `~/.maha.commute` with
all three payloads cached, and leaves one command called `commute`. The menu
and the installer both install through `~/.maha.commute/install-one.sh`.

## Where the work would go next

**A fourth app.** Add a row to `MAHA_APPS` in `src/00_head.sh`, a row to `APPS`
in `tools/build_installer.sh`, and drop the payload in `src/payloads/`. The
menu, the picker, the status screen and the install screen all read that one
table, so nothing else needs touching. The picker in `src/05_lib.sh` currently
understands 1, 2 and 3 only, and that is the one place a fourth app needs code
rather than a row.

**night.commute v10**, to stop it clearing its own folder. See `MEMORY.md`.

**An updater.** Not written on purpose. Decide public or private first, because
that decision is the whole design. See `MEMORY.md`.

**The banner.** `day.commute` looks for `~/.ma/banner.sh` and uses the shared MA
banner when it is there. The umbrella does not write one. If a family banner is
ever built, this is where it belongs.

## What to be careful about

**Never edit the generated file.** Change `src/`, run the build, run
`tools/build_installer.sh --check` to prove the artefact is not stale.

**The delimiters are checked, not hoped for.** The build refuses to run if a
payload contains a line equal to its own heredoc terminator, or if a key shape
survived into a payload.

**The sentinel is the last line and it means the file arrived whole.** `bash -n`
exits zero on a file cut in the middle of a heredoc, so the check is that
`bash -n` produces **no output at all**, and the sentinel is a second, separate
check. `tests/test3_ugly.sh` proves they can fail apart, which is the only
reason they are two checks.

**The key is never printed.** Not in a log, not in a status screen, not
redacted. The status screen prints the character count and nothing else.

## The state it was left in

Four tests green: 57, 30, 38, 32 passed, 0 failed. Each one was made to fail on
purpose first. The gate runs clean. Nothing has been run on an Android phone,
and `docs/NOT_TESTED.md` lists twelve things that are unproven because of it.
