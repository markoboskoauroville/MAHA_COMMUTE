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

## Round 2 — night.commute per-stop dashboard (v25) — pending

## Round 3 — the common API-key database (v26) — pending
