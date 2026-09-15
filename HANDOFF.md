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

**night.commute v11, to stop it clearing its own folder.** This was the job
pencilled in for v10, and v10 went to the live feed and the star instead. The
wipe is still there, the umbrella still copies the folder aside first, and the
fix is still one careful edit to the installer's own housekeeping.

**Seeing v10 in a browser.** The live rows, the trams on the map, the chips
and the star have all been driven in a javascript engine, and not one of them
has been looked at. Neither map engine has actually drawn a tram: both
`vehicle` and `favourite` markers were written against Leaflet's and Google's
APIs and are exercised by nothing, so a wrong option name in either shows as a
marker that never appears while every test stays green. That is the largest
unknown in this repository and it is first on the list in
`docs/NOT_TESTED.md`.

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

**Anything spliced into a payload needs a witness.** `WITNESS["night"]` lists
every function the live feed and the star reach into. They do not edit those
functions, they wrap them, and a wrapper around a function that has been
renamed upstream is not an error anywhere: it is a page that loads, runs, and
quietly never shows a tram. The witness turns that silence into a failed
build, and it is the only thing that does.

## The state it was left in

*Updated 16.9.2026, at the end of the session that built v10.*

Four tests: **213, 43, 67 and 43 passed**, with 0, 2, 4 and 13 failed. The
gate runs clean, 0 blocking findings.

**Those nineteen failures are the machine and not the build.** This was built
on a Linux box under proot rather than on a phone. The previous release was
checked out beside it and run there too, and it fails the same nineteen in the
same places: they want a real Termux, and Test 4's first half wants the
original hand-built installers, which are on the phone and not in this
repository. Establish that baseline again before believing any failure here is
yours. Every check added for v10 passes and none of the nineteen moved.

Each new check was made to fail on purpose first. Reversing the direction
comparison turns exactly two red; letting a stale feed through turns three
red and prints the tram it would have drawn from a forty minute old reading;
removing the star's tap guard sends the tap to station B.

Nothing has been run on an Android phone, and `docs/NOT_TESTED.md` now lists
thirty two things that are unproven because of it.
