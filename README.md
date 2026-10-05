# MAHA COMMUTE

**The umbrella over the Zagreb transit family. One file installs it, one word
opens it.**

```sh
curl -fsSL https://raw.githubusercontent.com/markoboskoauroville/MAHA_COMMUTE/main/get.sh -o get.sh && bash get.sh
```

[Copy this command: tap here for a page with a Copy button](https://markoboskoauroville.github.io/MAHA_COMMUTE/#cmd-1)

Paste that into Termux. It asks GitHub which version is current, fetches the
installer that number names, checks it four ways before running it, and
installs all three apps. Then type `maha.commute`.

It downloads before it runs rather than piping into `bash`, so the file is on
the phone and can be read first. A phone that walks out of signal halfway
through a download leaves a file that looks fine to `ls` and is cut in half,
which is what those four checks are for.

## Install one app, or all three

Every command is the same one-line download with one switch on the end. The
switch picks the app: `1` is day, `2` is night, `3` is all. Whichever you pick,
the launcher `maha-commute` is installed with it, and all three apps are kept on
the phone, so one left out can be added later from `maha-commute install` with
no download.

**The whole of Maha Commute, all three apps**

```sh
curl -fsSL https://raw.githubusercontent.com/markoboskoauroville/MAHA_COMMUTE/main/get.sh -o get.sh && bash get.sh
```

[Copy this command: tap here for a page with a Copy button](https://markoboskoauroville.github.io/MAHA_COMMUTE/#cmd-2)

**day.commute only**

```sh
curl -fsSL https://raw.githubusercontent.com/markoboskoauroville/MAHA_COMMUTE/main/get.sh -o get.sh && bash get.sh --apps 1
```

[Copy this command: tap here for a page with a Copy button](https://markoboskoauroville.github.io/MAHA_COMMUTE/#cmd-3)

**night.commute only**

```sh
curl -fsSL https://raw.githubusercontent.com/markoboskoauroville/MAHA_COMMUTE/main/get.sh -o get.sh && bash get.sh --apps 2
```

[Copy this command: tap here for a page with a Copy button](https://markoboskoauroville.github.io/MAHA_COMMUTE/#cmd-4)

**all.commute only**

```sh
curl -fsSL https://raw.githubusercontent.com/markoboskoauroville/MAHA_COMMUTE/main/get.sh -o get.sh && bash get.sh --apps 3
```

[Copy this command: tap here for a page with a Copy button](https://markoboskoauroville.github.io/MAHA_COMMUTE/#cmd-5)

Two of them go together: `--apps 12` is day and night, `--apps 13` is day and
all, `--apps 23` is night and all. On a phone that has never been set up, none
of these needs anything done first: Python and the other small tools are
fetched, and Android is asked about storage once.

Marko Boško · Mantra Productions · Zagreb · built 27.8.2026

---

Three apps had been living separately, each with its own installer, its own
name and its own folder. They are the same family and they are now under one
roof, whole and unchanged:

| | what it is | version | port |
|---|---|---|---|
| `day.commute` | the daytime ride, corridors that pick themselves | v15 | 8082 |
| `night.commute` | the four night trams, and where they are now | v13 | 8087 |
| `all.commute` | every station around you, in colour | v42 | 8084 |

## Installing

The one line at the top is the usual way in, and it ends here: one file, and
it carries all three apps inside it.

```sh
bash 18-maha_commute_v18.sh
```

[Copy this command: tap here for a page with a Copy button](https://markoboskoauroville.github.io/MAHA_COMMUTE/#cmd-6)

Run it directly like that when the file is already on the phone, which is what
`get.sh` does once it has fetched and checked it.

**It asks nothing.** All three are installed, missing dependencies are fetched
when the network answers and left alone when it does not, and a Google key is
found on the phone or done without. That is also what makes it safe for
`maha-commute-update` to run unattended.

**It asks for storage once, and carries on whatever the answer is.** On a phone
that has never been set up, the installer runs `termux-setup-storage` and
waits up to forty five seconds for the tap on Android's Allow popup, so a key
file saved in Downloads can be found. Allow is only for reading that file. Say
no, or ignore the popup, and the install is still a working install, and the
closing lines name the one command that would change it.

`--apps` picks which apps, as in the commands above. The other two switches
are for tests rather than for people: `--offline` forces it to use what the
phone already has, and `--verify` checks the file is whole without changing
anything.

**All three payloads are written to the phone whether they were installed or
not.** So an app left out on the first run can be added later, from inside the
menu, with no download and no second file.

## Using it

```sh
maha.commute
```

[Copy this command: tap here for a page with a Copy button](https://markoboskoauroville.github.io/MAHA_COMMUTE/#cmd-7)

### Updating, once it is installed

```sh
maha.commute-update
```

[Copy this command: tap here for a page with a Copy button](https://markoboskoauroville.github.io/MAHA_COMMUTE/#cmd-8)

It asks GitHub for the newest version and reinstalls only the apps that
changed. Your keys, your PDF timetables and the downloaded schedule stay where
they are. From inside the launcher the same thing is `maha.commute -update`.
The older names `maha-commute` and `maha-commute-update` still work.

**The map needs no key.** All three apps show OpenStreetMap, which is free.
A Google Maps key only adds Google's map as a second choice; how to get one is
written at the top of each app's Settings, next to the button that picks the
key file.

That is the whole interface. All three apps are on the screen from the first
frame whether they are installed or not: an app that is not here is dim rather
than absent, and pressing its number offers to install it. Colour carries the
state and nothing else, so green is running, sand is installed and ready, grey
is present but not available.

```
  ॐ  MAHA COMMUTE  v13

  1  day.commute      v13   running 8082
     the daytime ride
  2  night.commute    v11   ready
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
`maha-commute day`, `maha-commute status`, `maha-commute install`,
`maha-commute key`.

### The app's own name opens the same screen

`day.commute`, `night.commute` and `all.commute` open this launcher with that
app focused, starting it first if it is not running: the same screen and the
same keys as `maha-commute`, whichever way you came in. Typing the name with a verb
does the one thing without the screen:

```
day.commute stop | status | restart | open | log
```

Anything else (`day.commute update`, for one) goes to the app's own launcher,
which the installer keeps in `~/.maha.commute/orig/` and which the launcher
itself always talks to, so nothing in here can call itself.

### On the wifi, and what stays on the phone

Another device on the same wifi can open any of the three, and the top of each
app's Settings says the address in one line. What it can open is the page, the
timetable and the map. What it cannot open is anything that hands out a key,
spends money on a Gemini read, deletes a cache, rebuilds the schedule, or says
where the phone is: those answer the phone itself and nobody else. The
Detailed map in `all.commute` therefore needs the key and shows the free map to
a laptop. The check is two things at once, the address the request came from
and the name it was sent to, because a web page open in another tab can point a
name at the phone and the address alone does not catch that.

## Where the tram is

`night.commute` reads ZET's live feed, `zet.hr/gtfs-rt-protobuf`, and puts
the four night trams on the map as moving car numbers. Under each leg of a
journey it says which one is coming:

```
  02:24  02:17 ᯤ   (11 min)  → 02:42
  03:17            (64 min)  → 03:35
```

The first row has a tram behind it. The yellow **02:17** is when that tram
reaches your stop, the green wifi says it is broadcasting its position right
now, and a **+n** appears beside it when it is running late. The second row
has no tram near it yet and stands exactly as the timetable wrote it.

**Early is not a delay.** A night tram ahead of its slot arrives and waits,
because four trams on a fifty minute timetable are not allowed to drift, so
nothing claims the departure moved. The countdown counts to the moment the
tram can actually take you, which is the later of the two.

Underneath, the trams themselves:

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
tools/build_installer.sh          write 13-maha_commute_v13.sh
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
night.commute's live feed and star are in `src/payloads/night/` as
ordinary `.py`, `.js` and `.css` files: four hundred lines quoted inside the
patcher would be four hundred lines nothing can lint, diff or run.

`install-one.sh` is the only routine that installs anything, and both the
installer and the menu call it, so a fix to the install path cannot reach one
and miss the other.

## The tests

```
bash tests/test1_mechanism.sh   236 passed, 0 failed
bash tests/test2_real.sh          45 passed, 0 failed
bash tests/test3_ugly.sh          71 passed, 0 failed
bash tests/test4_upgrade.sh       25 passed, 0 failed
bash tests/gate.sh               0 blocking findings
```

Test 4 also names thirteen checks it did **not** run: they upgrade over the
three apps as they were installed by hand before the umbrella existed, which
needs the original installers, and those carry the key and are not in this
repository. Point `MAHA_ORIGINALS` at them to include that half. Thirteen red
lines saying a file is missing is not a test result; it is a test that did not
run wearing the clothes of one that failed.

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
