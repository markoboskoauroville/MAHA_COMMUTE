# MANIFEST

## THE TWO-MACHINE RULE (set by Marko, 8.10.2026, applies to every version)

**The local machine tests. The cloud machine upgrades.**

- The **cloud** Claude Code owns the repository: sources, tools, tests, docs,
  version numbers, the build, the memory. Every change is made here, and only
  here.
- The **local** Claude Code (Marko's computer, with the Android emulator and real
  Termux) only **tests**. It follows `docs/LOCAL_TEST_PROMPT.md`, never edits
  anything outside `field-tests/`, writes its results to
  `field-tests/<date>_v<VERSION>/REPORT.md` (+ `results.json`, logs,
  screenshots), pushes only that folder, and ends by telling Marko to ask the
  cloud Claude Code to read the report and make the changes.
- The cycle is: cloud builds and tests what it can, local tests the rest on the
  emulator, cloud reads `field-tests/` and fixes, a new version, local tests
  again. A fix made on the test machine is a second copy of the source and is
  erased by the next build, so it is not allowed.
- When the cloud Claude Code starts a session, it checks `field-tests/` for a
  report newer than the last version and reads it before anything else.
- **THE PROMPT IS ALWAYS WRITTEN, IN A CODE BOX (Marko, 8.10.2026).** Every time
  the cloud Claude Code finishes a version, or Marko asks for a test, its last
  message contains the prompt for the local Claude Code, written out in full in
  a single code box he can copy, naming the exact version, the branch and what
  changed since the last field test and so deserves the most attention. Never
  "run the usual prompt", never a link to it, never left for him to ask for.
- **THE LOCAL CLAUDE CODE READS THIS MANIFEST EVERY TIME.** The first line of
  every such prompt orders it to read `MANIFEST.md` completely, then
  `docs/LOCAL_TEST_PROMPT.md`, before it touches the emulator, on every run,
  even if it did so last time.

---

**Change log for MAHA_COMMUTE. One entry per version, newest first.**

---

## v16 · 2026-10-03

**Umbrella installer: `16-maha_commute_v16.sh`**
**Uninstaller: `16-maha_commute_uninstall_v16.sh`**

### Change: GTFS stop code label above the location pin

**App affected:** `all.commute` (payload `src/payloads/39-install-all_commute-termux-v39.sh`)

**What was added:** The GTFS `stop_id` (e.g. `30001`) is now shown as a small
pill chip directly **above** the circle head of the drop-pin. The label uses
the stop's unique `--c` colour for text and border, dark glassmorphism
background, and sits flush above the pin — so the full stack reads:
label → circle → triangle tip pointing at the station.

**CSS:** New `.svpinlabel` class. `.svpin` now uses `flex-direction:column`.
**JS:** `photoHTML()` injects `<span class="svpinlabel">{stop_id}</span>`.

**Built:** `16-maha_commute_v16.sh` (652 585 bytes)

---

## v15 · 2026-10-03

**Umbrella installer: `15-maha_commute_v15.sh`**
**Uninstaller: `15-maha_commute_uninstall_v15.sh`**

### Change: Station location pin on the Street View card photo

**App affected:** `all.commute` (payload `src/payloads/39-install-all_commute-termux-v39.sh`)

**What was added:** A downward-pointing teardrop drop-pin is overlaid at the
**centre** of every Street View card photograph. It uses each stop's unique
`--c` colour (same as the stop ring on the map), has a white border, and
pulses gently so the eye is drawn to exactly where the station is within
the Street View frame.

The pin is purely CSS — no image files or SVGs. It is built from two
pseudo-elements on `.svpin`:
- `::before` — the circle head of the pin, with a ripple `@keyframes` pulse
- `::after` — the downward-pointing triangle tail

The pin is `pointer-events:none` so it does not interfere with the tap that
opens the 360° panorama.

**Files changed:**

```
src/payloads/39-install-all_commute-termux-v39.sh
```

| Location | Change |
|---|---|
| CSS block (after `.sv360`) | New `.svpin`, `.svpin::before`, `.svpin::after`, `@keyframes svpinpulse` |
| `photoHTML()` JS function | `<span class="svpin"></span>` inserted between `<img>` and `<span class="sv360">` |

**Built and verified:**
```
bash tools/build_installer.sh   → 15-maha_commute_v15.sh (652 209 bytes)
bash tools/build_uninstaller.sh → 15-maha_commute_uninstall_v15.sh (9 129 bytes)
```

---

## v14 · 2026-10-03


**Umbrella installer: `14-maha_commute_v14.sh`**
**Uninstaller: `14-maha_commute_uninstall_v14.sh`**

### Change: Street View bearing rotated 180°

**App affected:** `all.commute` (payload `src/payloads/39-install-all_commute-termux-v39.sh`)

**Problem:** The bearing stored for each stop is the mean heading of vehicles
*leaving* that stop (the direction they travel onward). Both the still Street
View card photo and the live 360° panorama were initialised to that same
bearing — so the user was always looking in the direction the tram just went,
not the direction it arrives from. Standing at a stop, the opposite direction
(180°) is what you face while you wait.

**Fix (two lines, one file):**

```
src/payloads/39-install-all_commute-termux-v39.sh
```

| Location | Before | After |
|---|---|---|
| `streetView()` still photo heading (~line 3758) | `Math.round(s.bearing)` | `Math.round((s.bearing + 180) % 360)` |
| `openPano()` 360° panorama POV (~line 3811) | `s.bearing` | `(s.bearing + 180) % 360` |

The `% 360` keeps the result inside 0–359° for any bearing, including those
already near 180° that would otherwise exceed 360°.

**Gyro note:** The gyro (motion tracking) button was not changed. When gyro is
active the device orientation overrides the initial heading anyway, so the
180° offset only matters for the first frame before the user moves the phone.
It now starts correctly.

**Built and verified:**
```
bash tools/build_installer.sh   → 14-maha_commute_v14.sh (651 330 bytes)
bash tools/build_uninstaller.sh → 14-maha_commute_uninstall_v14.sh (9 129 bytes)
```

---

## v13 · 2026-09-17

Initial public release of the MAHA_COMMUTE umbrella. See `MEMORY.md` and
`HANDOFF.md` for the full history of what v10–v13 built.

Carried payloads: `day.commute` v13, `night.commute` v11 (patched from v9),
`all.commute` v39.
