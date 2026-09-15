# MAHA COMMUTE

**The umbrella over the Zagreb transit family. One file installs it, one word
opens it.**

Marko Boško · Mantra Productions · Zagreb · built 27.8.2026

---

Three apps had been living separately, each with its own installer, its own
name and its own folder. They are the same family and they are now under one
roof, whole and unchanged:

| | what it is | version | port |
|---|---|---|---|
| `day.commute` | the daytime ride, corridors that pick themselves | v13 | 8082 |
| `night.commute` | the four night trams, and where they are now | v10 | 8087 |
| `all.commute` | every station around you, in colour | v39 | 8084 |

## Installing

One file, and it carries all three apps inside it.

```
bash 10-maha_commute_v10.sh
```

**It asks nothing.** All three are installed, missing dependencies are fetched
when the network answers and left alone when it does not, and a Google key is
found on the phone or done without. That is also what makes it safe for
`maha-commute-update` to run unattended.

The switches are for tests rather than for people: `--apps 13` installs a
subset, `--offline` forces it to use what the phone already has, and
`--verify` checks the file is whole without changing anything.

**All three payloads are written to the phone whether they were installed or
not.** So an app left out on the first run can be added later, from inside the
menu, with no download and no second file.

## Using it

```
commute
```

That is the whole interface. All three apps are on the screen from the first
frame whether they are installed or not: an app that is not here is dim rather
than absent, and pressing its number offers to install it. Colour carries the
state and nothing else, so green is running, sand is installed and ready, grey
is present but not available.

```
  ॐ  MAHA COMMUTE  v10

  1  day.commute      v13   running 8082
     the daytime ride
  2  night.commute    v10   ready
     the four night trams
  3  all.commute      -     not installed
     every station around you

  i install or remove     k google key
  s status                q quit
```

`i` adds or takes away any of the three. Taking one away removes its command
and leaves its data exactly where it is, and prints the one line that would
delete that too. `k` handles the shared Google key and never prints it. `s`
checks the payload checksums, the three ports and the folders.

The one shot forms are there for when the menu is one keystroke too many:
`commute day`, `commute status`, `commute install`, `commute key`.

## Where the tram is

`night.commute` v10 reads ZET's live feed, `zet.hr/gtfs-rt-protobuf`, and puts
the four night trams on the map as moving car numbers. Under each leg of a
journey it says which one is coming:

```
  ● 460   at Kruge, 2 stops away              ~4 min
  ● 453   at Sheraton, 7 stops away          ~14 min
```

A `~` means the minutes came from the timetable, counted from the stop the
tram is standing at. No `~` means ZET published a prediction for your own
stop. The two are never made to look alike.

**The feed is trusted about where a tram is and not about when it arrives.**
Measured over one reading: thirty of its sixty two stop predictions carried no
time at all, and all thirty of those claimed to be exactly on time. Most of
the rest were for stops the tram had already gone past. So the position is
read from the feed, and the minutes come from the schedule this app already
holds.

**A feed that has stopped draws nothing.** The common failure is invisible —
the right size, the right shape, forty minutes old — so the header timestamp
is read on every fetch, and when it goes stale the trams come off the map and
the strip says why. An empty map is honest. A tram that is not there is not.

The strip under the map also counts the trams ZET is publishing but not
locating, so "three trams" never quietly means "three trams exist".

## Favourites

Tap the ☆ beside a station in the picker and it becomes ★. Starred stations
sort to the top of the picker, appear as chips above it so the usual trip
needs no searching, and are marked on the map whether or not their line is
switched on.

Tapping the chips fills the journey in order: the first tap is where you are,
the second is where you are going, and the next starts again.

They are stored by name rather than by stop id, because ZET renumbers stops
between schedule builds and this list has to outlive that. Nothing clears
them: they are a list somebody built by hand.

## The key

**No key is in this repository or in the installer.** The two original
installers each carried the same Google Maps key in plain text, so anybody
who ever received one of those files has it. Here it is taken out and replaced
with a placeholder.

At install time a key is looked for in this order: the shared store, then any
of the three apps already installed on the phone, then a file dropped in
Downloads. Only when all of those come back empty is anything asked. An
install with no key is a working install: the maps draw, the photographs and
the 360 view do not.

The key is cleaned to its own shape, letters and digits and underscore and
minus, at the moment it is stored. That is a filter used for extraction, where
it fails closed, and never for redaction, where it would fail open.

## How it is built

The delivered file is generated, never edited:

```
tools/build_installer.sh          write 10-maha_commute_v10.sh
tools/build_installer.sh --check  fail if the artefact is stale
tools/verify_installer.sh <file>  check a file you have not run yet
```

`src/` holds the pieces. `src/payloads/` holds the three original installers,
byte for byte as they were handed over, with only the key taken out. Editing
the generated file by hand puts a second copy of a payload in the world, and
two copies with a rule about keeping them in step are still two copies.

What a payload gains on its way out is spliced in by `tools/patch_payload.py`
against anchors that must match **exactly once**, so an upstream version that
renamed the thing being patched fails the build rather than shipping a silence.
night.commute v10's live feed and star are in `src/payloads/night-v10/` as
ordinary `.py`, `.js` and `.css` files: four hundred lines quoted inside the
patcher would be four hundred lines nothing can lint, diff or run.

`install-one.sh` is the only routine that installs anything, and both the
installer and the menu call it, so a fix to the install path cannot reach one
and miss the other.

## The tests

```
bash tests/test1_mechanism.sh   213 passed,  0 failed
bash tests/test2_real.sh          43 passed,  2 failed
bash tests/test3_ugly.sh          67 passed,  4 failed
bash tests/test4_upgrade.sh       43 passed, 13 failed
bash tests/gate.sh               0 blocking findings
```

**Those nineteen failures are the machine, not the build, and that claim was
checked rather than assumed.** v10 was built and tested on a Linux box under
proot rather than on a phone. The previous release was checked out beside it
and run there too, and it fails the same nineteen, in the same places: they
need a real Termux, and Test 4's first half needs the original hand-built
installers, which live on the phone and not in this repository. Every check
added for v10 passes, and none of the nineteen moved.

Each was made to fail on purpose before it was believed. Breaking the rename
into a truncating write turns Test 1 red on the held file descriptor; taking
out the stop of a running server turns Test 4 red on the old process; skipping
the payload checksum turns Test 3 red on the damaged payload. Reversing the
direction comparison in the live feed turns two checks red and only those two;
letting a stale feed be drawn turns three red, one of them printing the tram
it would have drawn from a forty minute old reading; removing the guard that
keeps a tap on the star off the row sends the tap to station B.

Test 1 pulls night.html out of the ARTEFACT and drives it in a real javascript
engine, so what is measured is what ships rather than a copy kept in the test.

**What was not tested is in [`docs/NOT_TESTED.md`](docs/NOT_TESTED.md), and it
is not a short list.** None of this ran on Android. The way back is in
[`docs/ROLLBACK.md`](docs/ROLLBACK.md).

## One thing found on the way

`night.commute` deletes `~/.nightcommute` at the start of every install, so
anything kept in there is lost. That is the app's own decision about its own
folder and it is left alone, but the umbrella reads the payload first, notices
the wipe, copies the folder to `~/.maha.commute/backup/night.prev` and says so
on the screen.

**This is still true in v10 and is still worth fixing.** v10 added the live
feed and the star and deliberately did not touch the installer's own
housekeeping. The favourites are safe from it either way, because they live in
the browser's storage rather than in that folder.

## Where things live

```
~/.maha.commute/
  env.sh                 the constants, read by the menu and the installer
  install-one.sh         the one install routine
  payloads/              all three, kept whether installed or not
    SHA256SUMS           checked before anything is run
  keys/google-api.txt    the shared key, 600
  installed/             one stamp per installed app
  backup/                one previous folder, for the app that wipes its own
```

The three apps keep their own folders exactly where they always were:
`~/.commute`, `~/.nightcommute`, `~/.all.commute`.
