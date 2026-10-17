# Field test — v26 (and v25), on a real Pixel 7

*17.10.2026. Run on Marko's Pixel 7 (Android 17) in real Termux/proot, by a
Claude Code session on the device driving it over adb/Remote Control, while the
cloud session (this repo's upgrader) sent the rounds and wrote this report.*

This is the first on-device test of **v25** (night.commute's per-stop dashboard)
and **v26** (the common API-key database). The cloud session verified both
against the live ZET feed and in headless Chromium before release; this closes
the gap those could not reach: real Termux, the real update path, and the two
pieces that need the on-device Google key (the Street View photo and the 360).

The phone started on **v21** and was updated the normal way.

## Round 1 — update via `maha.commute-update`, then smoke test — PASS

Marko approved the updater run on the device (the on-device session refuses to
run a freshly-downloaded installer without his approval, which is correct; the
cloud session did not route around it).

- **Update path.** `maha.commute-update` saw "v26 is available (this phone has
  v21)", fetched `26-maha_commute_v26.sh` (866636 bytes — byte-identical to the
  built artefact), checked it four ways (size, is-a-script, parses,
  `MAHA_COMMUTE_SENTINEL v26 0479eb671c416765`), and reinstalled all three apps.
  Closing line: "updated: day.commute night.commute all.commute". No errors.
- **Versions.** Launcher screen "MAHA COMMUTE v26"; day.commute **v19**,
  night.commute **v16**, all.commute **v48**, all "ready"; `env.sh`
  `MAHA_VERSION=v26`.
- **Servers answer.** `/version` → night `{"version":"v16","build":"n16-a"}`,
  day `{"version":"v19","build":"b41"}`, all `{"version":"v48","build":"b47"}`.
- **No crashes.** No traceback/exception in any server log. Startup logs healthy:
  night "rebuilt from gtfs 000396 service 20261017"; all "2523 stations kept,
  2450 with a departure today, 9557 trips indexed"; day "to-home: 127 deps".
- **Keys at update time:** the installer's check reported **google key ok,
  gemini key missing** — so the shared Google key is present (good for the
  dashboard's Street View), and there is no Gemini key yet (used in Round 3).

Observations, none blocking, none from v25/v26:
- The update **waits for Enter** ("Enter install it / n stop") before running the
  fetched installer; a run with no tty input does nothing and says "nothing was
  changed". This is a confirm-before-running-downloaded-code step, by design.
- `night.commute status` opened the interactive launcher screen rather than
  printing a status line and exiting. Pre-existing (the shim/status path was not
  touched by v25 or v26); noted for a later look.
- all.commute printed a stray "Terminated pgrep -f …" line while starting — the
  known cosmetic `pgrep/pkill` self-match, not a crash.

## Round 2 — night.commute per-stop dashboard (v25) — PASS (after a key fix)

Driven in the phone's browser (Firefox handles the http VIEW intent) by screencap
+ coordinate taps. Screenshots in `/storage/emulated/0/Download/maha_v26_test/`.
It was daytime, so the night trams were not running and the live feed showed none
(correct); the board showed tonight's scheduled departures (hours away).

- **Open / Map / toggle a line / tap a station → dashboard.** PASS. Tapping the
  Mihaljevac dot opened the dashboard: header "Mihaljevac · night tram 33 · live"
  with the 33 badge and ✕; COMING rows (33 pill, Savišće, 23:57 / 00:45 / … /
  04:00 with the minute countdowns); WATCH; From here / To here.
- **WATCH → bottom bar.** PASS. "★ Mihaljevac" with its next departures, shown on
  the Plan and Map tabs.
- **From here → planner.** PASS. Jumped to Plan with From = Mihaljevac.
- **Close.** PASS.

**Street View photo + 360 — FAILED on the first key, PASS on a new one.** The
first run showed no photo and no panorama. The tester proved the cause was not
app code: the Google key on the phone was rejected by Google — `streetview/
metadata` returned "This API key is not authorized to use this service or API"
and the static image returned HTTP 403. The Street View Static API and the Maps
JavaScript API were not enabled/authorised for that key in Google Cloud. Marko
supplied a new key (installed on the device with his approval; the old one backed
up to `~/.maha.commute/backup/google-api.old-20261017.txt`). Re-tested:
  - **Street View photo:** PASS — the Mihaljevac stop photo (a road with "BUS"
    markings), the green location pin, and the "◉ 360°" badge; WATCH sits above
    it and is not covered.
  - **360 panorama:** PASS — opens a full-screen Google panorama with navigation,
    ✕ closes it back into the app.

**Two UI faults in the FAILURE state (fixed in v17).** With a key that cannot
load Street View — the common case, since most keys are not Street-View-authorised
— the first run showed:
  1. the `<img>` onerror only hid the image, so the location pin and the 360
     badge (absolutely positioned in the same frame) collapsed onto the card and
     **covered the WATCH button**;
  2. the Leaflet/OSM attribution (z-index 1000) showed **through** the full-screen
     dashboard and over the watch bar.
Both fixed in night.commute **v17** (umbrella v27): on image failure the whole
frame is replaced with the "no Street View, or the key is not authorised" note
(`ndSvFail`), and the dashboard / watch bar / 360 viewer now sit above the
attribution, which is hidden while they are open. Verified in headless Chromium
by blocking the Street View request: the frame becomes the note, nothing overlaps
WATCH, no script errors.

## Round 3 — the common API-key database (v26) — PASS (A–E)

All on the real phone, with a harmless dummy Gemini key, cleaned up after.

- **A. Launcher "API KEYS" screen.** PASS. Shows "one shared store, used by all
  three, never printed / Google present (39 characters) / Gemini none stored" with
  g / e / x / Enter.
- **B. Shared Google read.** PASS. night `/gmaps-key`, day `/api-keys`, all
  `/api-keys` all return the same shared key.
- **C. Shared Gemini read.** PASS. A dummy key placed only in the common store is
  reported present by all three (`set: true`) though none has its own.
- **D. Seed + "ignored if exists".** PASS. all.commute seeded the empty store;
  a different pick in night.commute left the store unchanged (ignored); day read
  the seeded key from the shared store.
- **E. Cleanup.** PASS. Store back to google-api.txt only; night gemini status
  set:false.

## Two pre-existing security findings (not from v25/v26, present across the apps)

Surfaced by the on-device test; recorded for a considered follow-up because they
touch all three apps and the Settings UIs:

1. **The POST `/gemini-key` response echoes the submitted key** in its `keys`
   field (night and day; all.commute returns `{ok, set}` and does not). It is sent
   only back to the loopback client that posted it, over a phone-only route, so it
   does not reach the network — but it prints a real secret into a response, which
   is against this project's "never printed" rule and could be logged. The fix is
   to drop the key from the response (and check the Settings JS does not read it
   back).
2. **Per-app key files are written mode 644**, while the shared store is 600. On
   Android the whole Termux home is private to the Termux UID, so this is not a
   cross-app exposure today, but it is inconsistent with the store and with the
   project's discipline; the per-app `write_*` functions should `chmod 600`.

## Verdict

v25 (the night dashboard) and v26 (the shared key database) both work on the real
phone, through the normal `maha.commute-update` path, once the Google key is
authorised for Street View. v17/v27 fixes the dashboard's failure-state look. The
two security findings above are pre-existing and await a follow-up.
