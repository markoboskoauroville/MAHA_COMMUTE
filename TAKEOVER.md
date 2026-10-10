# TAKEOVER — all.commute, 10.10.2026

**Written at the end of a phone session that was about to run out of quota. Everything below is
either on a branch or on the phone; nothing important lives only in a transcript.**

Session: `https://claude.ai/code/session_012BHkqjYM4iD2QPRuUELVFH`
Branch with all of this session's work: **`phone/v49-labels-trace`**
The other session's branch: **`ccr-9334170f-y5rjg5`** (cloud, owns the real sources)

---

## 0 · The one thing to finish: Rijeka

**This is the unfinished work and the reason this file exists.** Marko asked for Autotrolej
(Rijeka) schedules in all.commute. The research is done and verified against live endpoints on
10.10.2026; the implementation has not been started.

Full findings are in the manifest: `MANTRA_MANIFEST/modules/rijeka-autotrolej.md` (commit
`f7dbb44`). The short version:

**There is no GTFS and no GTFS-Realtime for Autotrolej.** Do not plan around one. Third-party
sites showing "Autotrolej GTFS routes" derived those themselves.

**There is an open REST API that needs no credentials**, `https://api.autotrolej.hr/api/open/v1/…`,
spec at `/api/open/swagger/v1/swagger.json`:

    GET /voznired/stanice                       every stop, each with a polazakList
    GET /voznired/polasciStanica?stanicaId=1734 departures at one stop     <- the board
    GET /voznired/autobusi                      live buses: gbr, lat, lon, voznjaId
    GET /voznired/linije                        lines
    GET /voznired/polasci, /polasciLinija       departures, departures per line
    GET /token/login, /token/refresh

Every data endpoint declares a `token` header. **Every one answered 200 with real data when
called with no token**, and `/token/login` returns a token when called with no credentials. Send
a token if you have one, carry on without it, and do not build a registration step.

Verified live: `/autobusi` returned **18 buses** with real coordinates at ~08:5x on 10.10.2026.

There is also a whole-network anonymous JSON dump over **plain http** on
`e-usluge2.rijeka.hr/OpenData/`: `ATstanice.json` (127 K), `ATvoznired.json` (6.6 M),
`ATlinije.json` (3.7 M), plus `-tjedan`, `-subota`, `-nedjelja` variants. CC BY 4.0.
**`GpsX` is LONGITUDE, `GpsY` is LATITUDE.** Swap them and you are in the sea off Pula with no
error to tell you. `ATpozicije.json` does not exist — that was a guessed name and it 404s.

### The question to answer BEFORE building anything

`polasciStanica?stanicaId=1734` returned departures stamped **2026-09-30** when asked on
**10.10.2026**. Either the timetable is a fixed service-day snapshot that has not rolled over, or
that field is not the date it appears to be. **A departure board ten days stale is worse than no
board, because it looks right.** Settle this first.

### The shape the work would take

all.commute already wants exactly what this API gives — a board per stop and live vehicles — so
it needs less assembly than GTFS does, not more. A Rijeka adapter would be: stops from
`/stanice`, the board from `/polasciStanica`, live vehicles from `/autobusi`, and a city switch
in the UI. Marko has not yet said whether Rijeka should be a second city alongside Zagreb or a
separate mode. **Ask him that before writing code.**

---

## 1 · Where the code is

**The phone is the truth for this session's work.** `~/.all.commute/all.html` and
`~/.all.commute/all_commute_server.py` are hand-patched and running. Snapshots of both, plus
unified diffs against the state before this session, are committed at
`field-tests/2026-10-10_v49-phone/`.

**None of it has been ported into the payload patch chain.** It belongs in a
`tools/payload_v26.py` written against the v48 payload. The cloud session offered to do that
port and to run it through test 6, which does label-overlap and tap-target checks in Chromium.

**The checkout at `/sdcard/Download/MAHA_COMMUTE` was 27 commits behind `origin/main` at the
start of this session.** `origin/main` is VERSION 24 and uses the `tools/payload_vNN.py`
architecture. An installer built from the old v16 tree would roll back eight versions — one was
built by mistake early in this session and discarded unpushed. **Fast-forward before touching
anything.**

Nothing has been installed on the phone from any branch. The running app still reports
`v47 / b47`; the version strings were deliberately not bumped. Every `v49`/`v50`/`v51` in the
file is a comment marker, never code, so the next real build is free to be whatever number it
wants.

---

## 2 · What was done, and what state it is in

### Shipped by the cloud session into `ccr-9334170f-y5rjg5` (v25, all.commute v48)

- **The GPS dropout.** `termux-location` exits 0 and prints `{"API_ERROR": "Failed to get
  location"}` when Android has no fix. `termux_fix()` parsed that as good JSON, found no
  coordinates to copy, and returned `{"ok": true, "provider": "gps"}` — a failure wearing a
  success. Now an `API_ERROR`, or any reply without both latitude and longitude, is `ok: false`
  with Android's own reason, and the last good fix per provider comes back as `last` /
  `last_age_s`.
- **A 500 now logs route plus `traceback.format_exc()`** to stderr, so it reaches `server.log`.
  Before, `all_commute_server.py:2092` put the reason in the response body and nowhere else,
  which is why the `/gps` 500 at 07:39:35 could not be explained afterwards.
- **Follow.** `FOLLOW` as a setting, `LS.get("follow", true)`, with a toggle in the Position
  panel; the early hang-up gated on it; `fuse()` averaging only fixes within
  `max(25, newest.acc)` m of the newest.

### On the phone and on `phone/v49-labels-trace`, NOT yet in the chain

- **Labels are placed, not pushed apart.** `layoutPins()` offers each station a series of
  positions — above the dot first, then below, sides, diagonals, then rings at 1.9x and 2.9x —
  and takes the first that is free and on screen. A station that cannot have a label without
  covering another label or another station's dot keeps its dot and loses its label.
- **`text-size-adjust:100%` on `.pin`.** Android's font-scale slider was inflating labels to
  several hundred pixels. **This is the precondition for everything above**; without it no
  placement algorithm can work, and a desktop Chromium test will pass while the phone is broken.
  If test 6 is to mean anything it must run at a text scale other than 100% at least once.
- **`pinFontPx()`** maps zoom 13 → 9 px and 18+ → 17 px via `--pinfs`.
- **`.pindot`**, always drawn, counter-translated against the parent's `--dx/--dy` so it stays on
  the station while the label moves.
- **The map belongs to the user.** No automatic zoom anywhere: three sites passed
  `Math.max(17, curZoom())` when centring, which silently zoomed to 17; all now pass
  `curZoom()`. No automatic panning. What can move the map: the saved view at startup and on an
  engine switch, a tap on the locate button, the two items in its long-press menu, and one cold
  start on a first run with no saved view.
- **The lock.** 550 ms on the locate button opens `#lockMenu`: *Lock to my position* (middle of
  the screen stays on you, state in `ac2_lock`, button goes cyan) and *Centre on me once*.
  Unlocked, the dot drifts off screen, which is correct.
- **The trace.** Record button in `#tools`; tap starts and stops, long press opens `#recMenu`.
  Points more than 8 m apart are appended and drawn as a red polyline. State in `ac2_trace` /
  `ac2_rec`, which the new-run reset does not clear.
- **Tracks as GPX files.** New server routes `GET /tracks`, `GET /track?f=`, `POST /track/save`,
  `POST /track/delete`, all in `_PHONE_ONLY`, the two writes in `_STATE_CHANGING`.

### The track file format — settled, do not change it

Tracks are **GPX in Mantra Trail's exact dialect**, because Marko's other map apps already write
it and the point of putting files in Documents is that they are not ours alone. The header was
compared element for element against
`/sdcard/Documents/Track_Records/2026-09-17 22-17 Track.gpx` and is identical apart from
`creator`.

    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="all.commute"
         xmlns="http://www.topografix.com/GPX/1/1"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
      <metadata><name>…</name><time>…Z</time></metadata>
      <trk><name>…</name><trkseg>
        <trkpt lat="45.805213" lon="15.979278"><ele>120.5</ele><time>…Z</time></trkpt>

`<sat>` and `<hdop>` are Mantra Trail's and stay its own: this app cannot read a satellite count,
and turning the browser's accuracy in metres into a dimensionless hdop would be inventing a
number.

**Write to** `/storage/emulated/0/Documents/All Commute/Tracks` (Marko's instruction).
**Read also** `/storage/emulated/0/Documents/Track_Records`, which is Mantra Trail's folder and
holds 10 existing journeys; they list in the picker and open on the map. Deleting a file there is
refused — another app's journey is not ours to remove.

**Default name**, when the user types none: date, then time, then the nearest station at the
start and the nearest at the end, each within 400 m, and silently omitted when there is none.
`2026-10-10 08-33 109_1 630_24.gpx`, or `… Track.gpx` in open country.

**The picker is a list this app draws, not `<input type="file">`.** On Android that input opens
Chrome's chooser, which asks for the camera, swallows the first tap and offers no Files entry at
all — see `MANTRA_MANIFEST/modules/streamlit-file-picker-android.md`. Drawing the list also means
a rename made in a file browser simply shows up.

---

## 3 · What has NOT been tested

**Marko confirmed the follow fix and the map-control changes work.** Beyond that:

- **The label rewrite has had no test but a parse check and his eye on it.** No automated
  coverage at all. The overlap rules, the priority order, the exclusion zones under `#hud`,
  `#tools`, `#gpsChip` and `#watchbar` — none of it is checked by anything.
- **The screen clamp is Leaflet-only.** `pxOf()` returns world pixels under Google and there is
  no container origin to clamp against, so in the Google view a label can go off screen. Real
  gap, not closed.
- **The trace and the track menu were only verified end to end on the server side** — save, list
  across both folders, load, the default naming, the name sanitiser. The menu, the picker UI and
  the long-press gestures have been loaded into Chrome but not driven by hand.
- The `/gps` 500 of 07:39:35 was never reproduced after the restart.

---

## 4 · How to pick this up

    cd /sdcard/Download/MAHA_COMMUTE
    git fetch origin
    git checkout phone/v49-labels-trace      # this session's work
    git log --oneline -5

The app on the phone: `all.commute restart` to reload the **server**; a page refresh is enough for
**all.html**, because the server reads it from disk on every request. It serves on
`http://127.0.0.1:8084`. To put it in front of Marko:

    am start --user 0 -a android.intent.action.VIEW \
      -d "http://127.0.0.1:8084/?run=$(date +%s)" \
      -n com.android.chrome/com.google.android.apps.chrome.Main

`am start` prints `Warning: Activity not started, its current task has been brought to the front`
even when it did navigate — **check `server.log` for the `run=` id rather than believing the
warning.**

This session runs inside proot-distro as root. `$PREFIX` is empty, `/root` and
`/data/data/com.termux/files/home` are the same directory under two spellings, and `dpkg -s` from
in here cannot see Termux's packages — read
`/data/data/com.termux/files/usr/var/lib/dpkg/status` instead.

---

## 5 · Standing instructions that shaped this

- **Commit before testing and again after**, so nothing is lost to a crash. That is why this
  branch carries untested snapshots; it is deliberate.
- **Never push from a stale checkout**, and never to another session's branch.
- **Read the manifest from GitHub, write to GitHub, keep no local copy.** Two entries were added
  today: `modules/termux-proot-working.md` on the `API_ERROR` trap, and
  `modules/rijeka-autotrolej.md`.
- Keys live in `Download/api/` and never reach a commit. `Gmap.txt` is the 39-character key the
  app already uses; it tests OK.
