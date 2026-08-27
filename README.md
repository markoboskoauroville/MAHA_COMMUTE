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
| `night.commute` | the four night trams, 23:50 to 04:40 | v9 | 8087 |
| `all.commute` | every station around you, in colour | v39 | 8084 |

## Installing

One file, and it carries all three apps inside it.

```
bash 1-maha_commute_v1.sh
```

It asks which ones to install. Type the numbers together, `13` for two of them,
Enter for all three, `n` for none. Then it asks whether to install offline with
what the phone already has, or to fetch the missing dependencies first, and it
draws the dependency table before asking rather than after.

Nothing needs choosing twice. `--apps 13 --offline` answers both questions from
the command line, and `--verify` checks the file is whole without changing
anything.

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
  ॐ  MAHA COMMUTE  v1

  1  day.commute      v13   running 8082
     the daytime ride
  2  night.commute    v9    ready
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
tools/build_installer.sh          write 1-maha_commute_v1.sh
tools/build_installer.sh --check  fail if the artefact is stale
tools/verify_installer.sh <file>  check a file you have not run yet
```

`src/` holds the pieces. `src/payloads/` holds the three original installers,
byte for byte as they were handed over, with only the key taken out. Editing
the generated file by hand puts a second copy of a payload in the world, and
two copies with a rule about keeping them in step are still two copies.

`install-one.sh` is the only routine that installs anything, and both the
installer and the menu call it, so a fix to the install path cannot reach one
and miss the other.

## The tests

```
bash tests/test1_mechanism.sh   57 passed
bash tests/test2_real.sh        30 passed
bash tests/test3_ugly.sh        38 passed
bash tests/test4_upgrade.sh     32 passed
bash tests/gate.sh              the nine gates before delivery
```

Each was made to fail on purpose before it was believed. Breaking the rename
into a truncating write turns Test 1 red on the held file descriptor; taking
out the stop of a running server turns Test 4 red on the old process; skipping
the payload checksum turns Test 3 red on the damaged payload.

**What was not tested is in [`docs/NOT_TESTED.md`](docs/NOT_TESTED.md), and it
is not a short list.** None of this ran on Android. The way back is in
[`docs/ROLLBACK.md`](docs/ROLLBACK.md).

## One thing found on the way

`night.commute` v9 deletes `~/.nightcommute` at the start of every install, so
anything kept in there is lost. That is the app's own decision about its own
folder and it is left alone, but the umbrella reads the payload first, notices
the wipe, copies the folder to `~/.maha.commute/backup/night.prev` and says so
on the screen. Worth fixing properly in night v10.

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
