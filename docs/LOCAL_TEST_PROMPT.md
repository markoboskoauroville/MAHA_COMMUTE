# Prompt for the LOCAL Claude Code: run the Android emulator and stress test MAHA_COMMUTE

*Written 8.10.2026 for umbrella v21. Paste the short prompt at the bottom into
Claude Code on your own computer, in a clone of this repo. Everything above it
is what that Claude Code reads and follows.*

---

## THE RULE (read this first, it is not negotiable)

**This machine TESTS. The cloud machine UPGRADES.**

You are the local Claude Code. You have the Android emulator, a real network and
real Termux. The cloud Claude Code has none of that, but it is where every
change to this repository is made.

- You **never edit** `src/`, `tools/`, `tests/`, `docs/`, the `*-maha_commute_v*.sh`
  files, `VERSION`, `README.md`, `MEMORY.md`, `MANIFEST.md` or `HANDOFF.md`.
  Not a typo, not "just one line". If you think something needs changing, you
  write it in the report and stop there.
- You **only write** inside `field-tests/<date>_v<VERSION>/` and you commit and
  push **only that folder**.
- When the testing is finished you **tell the person**, in plain words, to ask
  the cloud Claude Code to read the report and make the fixes (exact wording
  in "When you are done"). Then the loop is: cloud fixes, publishes a new
  version, you test again, a new folder.

Why: the cloud side keeps the sources, the build, the version numbers and the
memory consistent. A fix made on a test machine is a second copy of the
source, and the next build erases it.

## What you are testing

The newest installer in the repo root: `<VERSION>-maha_commute_v<VERSION>.sh`
(the number in `VERSION`). Read `README.md`, `docs/NOT_TESTED.md` (it lists
what has never been seen on a phone: that is your work list) and the V17 to V21
sections of `MEMORY.md` before you start, so you know what each thing is
supposed to do.

Three apps under one launcher, all in Termux:

| app | command | port | what to prove |
|---|---|---|---|
| day.commute | `day.commute` | 8082 | corridors, live rows, starts every time |
| night.commute | `night.commute` | 8087 | the four night trams, live feed, stars |
| all.commute | `all.commute` | 8084 | every station, labels, dashboard, GPS dot |
| launcher | `maha-commute` | n/a | quadrants, keys, update, status |

## Set up the emulator (do it, do not ask)

1. Android SDK command line tools, `platform-tools`, `emulator`, a **Pixel
   class AVD, API 34, x86_64, `google_apis`** image. 4 GB RAM, 8 GB data
   partition, hardware keyboard off. Start it with `-no-snapshot-save
   -gpu swiftshader_indirect` if the host has no GPU.
2. Install **from F-Droid only** (all Termux apps must share one signature, so
   a Play or GitHub build mixed with an F-Droid one will refuse to talk to the
   others): F-Droid itself, then **Termux, Termux:API, Termux:Boot,
   Termux:Styling, Termux:Widget**. Download the APKs from
   `https://f-droid.org/repo/` and `adb install` them. Open each app once.
   Grant Termux:API its permissions (location, storage, notifications).
3. Chrome (the emulator image has it, or install it). It is the browser the
   launcher opens pages in.
4. In Termux: `pkg update`, then `termux-setup-storage` and tap Allow with
   `adb shell input tap` (find the button with `uiautomator dump`).
5. GPS: `adb emu geo fix 15.9800 45.8050` (longitude first). Move the phone
   later with the same command.
6. Put the installer on the phone: `adb push <VERSION>-maha_commute_v<VERSION>.sh
   /sdcard/Download/` then in Termux `bash ~/storage/downloads/<file>`.
7. **The Google Maps key** is in
   `~/Downloads/API/Google-maps-api termux (working 7.10.2026).txt` on this
   computer. Push it to the phone's Download folder so the installer finds it.
   **Never print it, never write it into a report, a log or a screenshot, never
   commit it.** Before every commit run `grep -rE 'AIza[A-Za-z0-9_-]{30,}'
   field-tests/` and expect nothing. If it shows, delete the file and redo it.

If any set-up step cannot be done, that is the first line of the report, with
the error. Do not skip it silently.

## Test plan (run all of it; mark BLOCKED with the reason when you cannot)

Give every check an id (`INS-1`, `LCH-3` ...), the expectation written BEFORE
you run it, what actually happened, PASS / FAIL / BLOCKED, and the evidence
(a log file or a screenshot path).

**INS install**
- fresh install of all three; install of one; `--offline`; with and without the
  key file; storage permission not yet granted
- upgrade over the previous version (take the v20 file from git history),
  with data present: the Gemini key, the `night` timetables and the 14 MB ZET
  schedule must survive
- install twice in a row; install while a server is running (it must stop it)
- `maha-commute status`, `info`, `--help`, `uninstall` (asks twice), reinstall
- every command exists: `maha-commute`, `maha.commute`, `day.commute`,
  `night.commute`, `all.commute`, their `-update` forms

**LCH launcher (type into Termux with `adb shell input text` and keyevents)**
- `1`..`4` start an idle app; on a running app they only move the light and
  open nothing (count Chrome launches with `dumpsys activity`)
- `0` lights nothing; the verbs line says `launcher`
- `u` with nothing running updates the whole launcher; with apps running and one
  lit it updates only that one (`--app`); with none lit it explains and does
  nothing
- Enter, `o`, `s`, `R`, `l`, `i`, `h`, `r`, `c`, `t`, `k`, `S`, `w`, `q`, arrows
- an app started from a second Termux session appears within 4 s, unprompted
- terminal widths 40, 50, 60, 80 columns and rotation: the frame must not break
- end of input must leave, not start something

**SRV servers**
- all three at once; each on its own port; the port file matches the socket
- occupy 8082, 8084, 8087 first (`nc -l`): each server must take the next port
  and the launcher must open THAT one
- `kill -9` a server, leave a stale `port` file: the launcher must say it is
  not running and a restart must work
- start day.commute 20 times in a row, from the launcher and from the command
  line: it must come up every time (this was a real bug)
- peer and Host protection: from the host machine (`adb forward`, or the
  emulator's `10.0.2.15` address) `/api-keys` and `/gps` must answer 403, the
  page must answer 200

**ALL all.commute (drive Chrome through DevTools: `adb forward
tcp:9222 localabstract:chrome_devtools_remote`, then Playwright
`connectOverCDP`, or `uiautomator` and `input tap` if that fails)**
- **stations are there at once**: airplane mode on, no feed ever downloaded
  (`rm -rf ~/.all.commute` then reinstall): the first screen must draw the
  stations around the GPS point with no network. Count labels vs expectation.
- labels: on a zoom where several platforms collide (Glavni kolodvor, Trg bana
  Jelacica, Kvaternikov trg), no two labels overlap; screenshot at zoom 15, 16, 17,
  18; tap every label with `input tap` at its centre and at its edge: each opens
  its own station, never a neighbour
- the map **does not follow the dot**: pan away and zoom out, move the phone
  with `adb emu geo fix`, wait 2 minutes, switch app and come back, lock and
  unlock: centre and zoom must be unchanged. The locate button brings it back.
- first run only: the map centres on the first fix
- dashboard: open, close with the X and with the back gesture, arrivals refresh,
  WATCH, Street View photo and 360 view (key present and key absent)
- the daily rebuild with the real feed: time it, watch memory with
  `dumpsys meminfo com.termux`; kill the server in the middle of it (the old
  index must still work and `stations.json` must be intact); corrupt the zip
  (`truncate -s 1M`): it must fall back, not crash; no network: it must use the
  local copy
- change the emulator date (`adb shell su 0 date ...` or the settings) to a
  Sunday, a holiday and just after midnight, rebuild: the **number of stations
  must stay 2523** while departures change
- `/stops`, `/find-stops`, `/board`, `/trip`, `/status`, `/cache/clear` (stations
  must survive it)

**DAY day.commute**
- starts, port bump, live rows, the Buzin direction, the midnight countdown
  (set the clock to 23:27 and read the minutes), corridors by location
- PDF schedule fallback, Gemini key present and absent

**NIT night.commute**
- all four trams, the live feed row, the wifi mark on a broadcasting tram, a
  star kept across restart and across an update, the 14 MB schedule survives
  an update, the map on both engines

**ANDROID what only a phone does**
- screen off and Doze for 30 minutes (`dumpsys deviceidle force-idle`): do the
  servers survive, does Android's phantom process killer take them
  (`adb shell settings put global settings_enable_monitor_phantom_procs false`
  vs default), does `termux-wake-lock` help
- Termux killed from recents, then reopened; phone rebooted with Termux:Boot
- low storage (fill the data partition), low memory (`stress`), airplane mode
  toggled mid-session, wifi to mobile data
- location denied; location while only the network provider answers
- Termux:API: `termux-location`, `termux-open-url`, notifications

**SOAK**
- all three apps running for 2 hours with the page open and the GPS moving
  (script `adb emu geo fix` along the tram 6 route): sample RSS, CPU, open
  sockets and battery every minute into `soak.csv`. A server that grows
  without bound, a socket leak, or a crash is a FAIL. Plot the numbers.

**SEC**
- no key anywhere on the phone's disk except the key store
  (`grep -rE 'AIza' ~` inside Termux, report only the count and the files)
- a web page in another origin cannot read `/api-keys` (DNS rebinding with a
  Host header)

Anything else you notice while using it goes under **Unplanned findings**.
That list is often the most valuable one.

## What you write (and only this)

`field-tests/<YYYY-MM-DD>_v<VERSION>/`

- `REPORT.md`, in this order: **verdict** (one line: ship / do not ship and the
  count of FAIL), **environment** (AVD, API level, Termux versions, host OS, the
  commit hash you tested, the installer's sha256), **results table** (every id,
  expectation, result, evidence), **FAILURES** (for each: the steps to
  reproduce, what happened, what should have happened, the file you suspect, and
  how bad it is: blocks release / annoying / cosmetic), **Unplanned findings**,
  **BLOCKED** (what and why), **Requests for the cloud** (a numbered list of
  exactly what you would like changed, written so that someone who cannot see
  the phone can act on it)
- `results.json`: the same table, one object per check, for a machine to read
- `logs/` (server logs, `logcat` excerpts, installer output with the key
  redacted), `screenshots/` (PNG, named by check id), `soak.csv`
- nothing larger than 5 MB per file; trim logs

Report **faithfully**: a check you did not run is BLOCKED, not PASS. A flaky
check is run five times and reported as `3/5`. Do not round a failure into a
pass and do not soften the verdict.

## When you are done

1. `grep -rE 'AIza[A-Za-z0-9_-]{30,}' field-tests/` returns nothing.
2. `git pull --rebase`, then `git add field-tests/<folder>`, commit
   (`field test v<VERSION>: N passed, M failed, K blocked`) and push to the
   branch the person named (default: the branch you cloned).
3. Tell the person, as the last thing you say, in these words:

   > **Testing of v<VERSION> is finished. Please ask Cloud Code to fetch
   > `field-tests/<folder>/REPORT.md`, read it, and make the changes under
   > "Requests for the cloud". I have changed nothing in the source. Verdict:
   > <ship / do not ship>, <M> failed, <K> blocked.**

4. Stop. Do not start fixing.

---

## The prompt to paste into the local Claude Code

The cloud Claude Code writes this out, in a code box, with the version, branch
and "what changed since the last field test" filled in, at the end of every
version and whenever asked (see `MANIFEST.md`). The template:

```
FIRST, before anything else, read MANIFEST.md completely, then
docs/LOCAL_TEST_PROMPT.md, then docs/NOT_TESTED.md and the newest
field-tests/*/REPORT.md. Do this on every run, even if you did it last time.

You are the LOCAL tester for MAHA_COMMUTE. Branch: <BRANCH>. Version to test:
<VERSION> (the file <VERSION>-maha_commute_v<VERSION>.sh in the repo root).
Pull the latest of that branch first.

What changed since the last field test, and so deserves the most attention:
<LIST>

Set up the Android emulator with F-Droid Termux, Termux:API, Termux:Boot and
Termux:Styling, install that file, and stress test the whole app with the real
ZET feed and my Google Maps key (in ~/Downloads/API/, never print, log, shoot or
commit it). You only TEST. Never edit source, tools, tests, docs or version
files. Write results only inside field-tests/<date>_v<VERSION>/ (REPORT.md,
results.json, logs, screenshots, soak.csv), commit and push only that folder.
Report faithfully: not run means BLOCKED, never PASS. When finished, tell me to
ask Cloud Code to fetch the report and make the changes. Then stop.
```
