# Field test, MAHA_COMMUTE v21, 8.10.2026

**INTERIM** (written 08.10.2026 19:00). Testing is still running; this file is updated as each test finishes, and the cloud may start on the requests below now.

## Verdict

**Do not ship.** 34 passed, 14 failed, 3 blocked so far. The v21 headline features hold: stations stay at 2523 on every date, labels never overlap, the map never follows the dot, the page race is fixed. The failures are around them: labels hidden under the controls, the key not reaching all.commute, the installer and the launcher's command line.

## Environment

| | |
|---|---|
| Real phone | Pixel 7, Android 16, Termux 0.118.3 F-Droid (API 0.53.0, Boot, Styling, Widget), over Wi-Fi adb + sshd in Termux. Upgraded from v20 (all v43, day v17, night v13) with Marko's real data, backed up to the Mac first |
| Emulator | AVD Pixel_7_API_35, Android 15, arm64-v8a (Apple Silicon host), google_apis_playstore image `AE3A.240806.036`, no root (dates set with `cmd alarm set-time`), Termux 0.118.3 + API 0.53.0 + Boot + Styling + Widget from F-Droid, Chrome driven over DevTools with Playwright |
| Host | macOS 15.0 |
| Commit tested | d47a514 (branch claude/confident-babbage-5hz8yr) |
| Installer | `21-maha_commute_v21.sh`, 811 808 bytes, sha256 `45df3e60f6e2d1d22eaf27d8f8aadd2e728b676d975d395ac57f739235e70948` |
| Feed | the real ZET GTFS (12 760 995 bytes, 3797 stops) and the live feed |

The real phone was used first; at Marko's request (8.10.2026 17:00) the rest moved to the emulator, because the phone was needed for another app.

## Results

| id | device | expectation | what happened | result | evidence |
|---|---|---|---|---|---|
| INS-UPG | Pixel 7 | v21 over v20 with data: network.db, PDFs, night.json, keys survive | all checksums identical before/after; all.commute v43->v44, day/night left alone | **PASS** | logs/INS-UPG_before.txt, logs/INS-UPG_after.txt, logs/INS-UPG_install.txt |
| INS-KEY-1 | Pixel 7 | the shared key store is seeded from the app that holds the real key | store got 0 bytes: ~/.commute/google-api.txt (1 byte, a newline) passed -s and won over ~/.all.commute/google-api.txt (40 chars); `info` says key none | **FAIL** | logs/INS-UPG_after.txt |
| INS-1 | emulator | fresh online install of all three with key in Downloads | python installed, storage allowed, key found, real GTFS 12.7 MB fetched, 2523 stations, EXIT 0 in 2:50 | **PASS** | logs/INS-1_fresh_online_emulator.txt |
| INS-DEP-1 | emulator | dependency check reports termux-api correctly and installs it | says `termux-api ok` but the package is not installed (dpkg: un); termux-location absent; only termux-open-url (termux-tools) exists | **FAIL** | logs/INS-1_fresh_online_emulator.txt |
| INS-KEY-2 | emulator | fresh install gives all.commute the key that was found | key found and stored (shared store 39 B, day 40 B, night 40 B) but ~/.all.commute/google-api.txt never written; /api-keys answers {"keys": []}; settings shows Map key red | **FAIL** | logs/SRV-SEC_http_emulator.txt, screenshots/ALL-1_airplane_first_load.png |
| INS-CMD | emulator | every command exists | maha-commute, maha.commute, day.commute, night.commute, all.commute, maha-commute-update, maha.commute-update present; no day/night/all -update forms | **PASS** | logs/INS-1_fresh_online_emulator.txt |
| INS-REINST | emulator | rm -rf ~/.all.commute then the umbrella installer reinstalls it | says `already current, left alone: all.commute` and lists it as on; nothing installed; launcher shows `v44 ready`; install-one.sh all --offline worked | **FAIL** | logs/ALL-1_airplane_fresh_emulator.txt |
| SRV-1 | both | `maha-commute day|all` from a script starts the app and returns | app starts and prints `up on 8082`, EXIT 0, but a forked copy of maha-commute stays in do_wait as the server's parent holding the caller's stdout: the caller hangs until the server dies (9 min on emulator, 25 min on phone). night returns (its launcher does not exec) | **FAIL** | logs/SRV-1_cli_start_emulator.txt, logs/SRV-hang_cli_start_phone.txt |
| SRV-2 | emulator | all three at once on own ports, port file matches | 8082/8087/8084 all 200, port files match | **PASS** | logs/SRV-1_cli_start_emulator.txt |
| SRV-WAIT | emulator | the first-start wait counts real seconds | with no terminal, read -t 0.4 returns at once, so `24s waiting` was printed after 2.5 s; the 3 minute wait shrinks to seconds | **FAIL** | logs/SRV-1_cli_start_emulator.txt |
| SEC-PEER | emulator | /api-keys and /gps 403 from LAN peer and foreign Host; page 200 | day and all: local 200, LAN 403, Host evil 403, Host rebind 403; page 200 everywhere | **PASS** | logs/SRV-SEC_http_emulator.txt |
| SEC-CORS | emulator | a foreign origin cannot read /api-keys | no Access-Control-Allow-Origin header, so the browser blocks the read | **PASS** | logs/SRV-SEC_http_emulator.txt |
| SEC-CSRF | emulator | state-changing routes cannot be triggered by another web page | /cache/clear, /rebuild, /sched-delete act on GET; any site open in Chrome on the phone can fire them with an <img> (peer and Host are both local). /cache/clear removed network.db | **FAIL** | logs/SRV-SEC_http_emulator.txt |
| SEC-DISK | emulator | key only in the key store (and the app copies documented in NOT_TESTED) | 4 files: keys/google-api.txt, .commute/google-api.txt, .nightcommute/gmaps-api.txt, and the Downloads file the tester pushed; none in logs or html | **PASS** | logs/SEC-1_key_on_disk_emulator.txt |
| ALL-API | emulator | /stops /find-stops /board /trip /status /cache/clear work; stations survive the clear | stops 14 at Glavni, find-stops Jelacic ok, board 40 departures at 109_1, trip path ok, after /cache/clear stations still answer (14) and status stations:true | **PASS** | logs/SRV-SEC_http_emulator.txt |
| ALL-ST-1 | Pixel 7 | real feed, weekday: 2523 stations | 3797 stops in feed, 2507 served, 2523 kept, /status stops 2523 | **PASS** | logs/ALL-rebuild_phone_realfeed.txt |
| ALL-ST-2 | emulator | Sunday 11.10: 2523 stations while departures change | 7193 trips, 124708 departures, 2336 served, 2523 kept | **PASS** | logs/ALL-dates_rebuild_emulator.txt |
| ALL-ST-3 | emulator | holiday 18.11: 2523 | Sunday service (124708 departures), 2523 kept | **PASS** | logs/ALL-dates_rebuild_emulator.txt |
| ALL-ST-4 | emulator | after midnight Fri 9.10 00:30: 2523 | service_date 20261009, 2523 kept | **PASS** | logs/ALL-dates_rebuild_emulator.txt |
| ALL-ST-5 | emulator | airplane mode, no feed ever downloaded: stations drawn at once | seed stations.json 2523 (updated 0); 4 stations drawn 0.7 s after load with no network, 5 after first fix; no overlap | **PASS** | logs/ALL-1_first_load.txt, screenshots/ALL-1_airplane_first_load.png |
| ALL-REB | emulator | rebuild time and memory | about 14 s wall, peak RSS 51 MB of update_all.py | **PASS** | logs/ALL-dates_rebuild_emulator.txt |
| ALL-OFF-1 | emulator | after an offline start the index is built once the network returns | update failed at start (no network), never retried: `no station index yet` 25 min after the network came back; no departures until a manual /rebuild | **FAIL** | logs/ALL-1_airplane_fresh_emulator.txt |
| ALL-LBL-1 | emulator | no two labels overlap at zoom 15-18 at Glavni, Jelacic, Kvaternik | 0 overlaps in 12 screens | **PASS** | logs/ALL-LBL_labels.txt, screenshots/ALL-LBL_*.png |
| ALL-LBL-2 | emulator | every label tap at centre and edges opens its own station | labels are clamped to y>=64 but the GPS chip reaches about y=90 and the watch bar covers the bottom; taps on 106_1, 106_2, 1849_23, 1849_24, 247_1, 247_2 open SETTINGS; taps on 110_41, 110_51, 292_2 open the watched station from the watch bar | **FAIL** | logs/ALL-LBL_labels.txt, screenshots/ALL-LBL_jelacic_z17.png |
| ALL-FOL-1 | emulator | map does not follow the dot: pan, geo fix, 2 min, app switch, lock/unlock | centre and zoom unchanged through all five | **PASS** | logs/ALL-FOL_follow.txt |
| ALL-FOL-2 | emulator | locate button centres on where you are | centres on the last known ME immediately and clears WANT_CENTRE; the fresh fix from sharpen() only moves the dot. After moving 3.8 km the map went to the old place | **FAIL** | logs/ALL-FOL_follow.txt |
| ALL-FOL-3 | emulator | first run centres once | CENTRED at the first fix (4.8 s), then never again | **PASS** | logs/ALL-1_first_load.txt |
| RACE-1 | emulator | page race: fast and slow (2 s, 5 s per request) first-run loads centre and draw stations | 15/15 drew stations and centred on a fix (soak GPS was moving; rerun clean below) | **PASS** | logs/RACE_page.txt |
| ALL-DASH-1 | emulator | dashboard opens on tap, closes with X and with back, back once more leaves | all as expected; WATCH set by opening | **PASS** | logs/ALL-DASH_nokey.txt |
| ALL-DASH-2 | emulator | arrivals refresh | text changed within 45 s; JUST LEFT and COMING, live delays and wifi marks shown | **PASS** | logs/ALL-DASH_refresh.txt, screenshots/ALL-DASH_streetview_key.png |
| ALL-DASH-3 | emulator | Street View without key | says `Add a Google key in settings to see the stop.` | **PASS** | logs/ALL-DASH_nokey.txt |
| ALL-DASH-4 | emulator | Street View photo with key | 640x260 photo with the pin label | **PASS** | screenshots/ALL-DASH_360_key.png |
| ALL-DASH-5 | emulator | 360 view with key | opens (Google loaded, arrows, gyro, X) but imagery black: emulator software WebGL; needs the real phone | **BLOCKED** | screenshots/ALL-DASH_360_tapped.png |
| UPD-1 | emulator | update --check says what is there and changes nothing | `v21 is the newest there is`, EXIT 0; --app nosuch rejected EXIT 2 | **PASS** | logs/UPD_check_emulator.txt |
| UPD-2 | emulator | update --check <file> changes nothing | --check is ignored when a file is given: it offers `Enter install it` | **FAIL** | logs/UPD_check_emulator.txt |
| UPD-3 | emulator | a missing file path is reported | silently ignored, falls back to github | **FAIL** | logs/UPD_check_emulator.txt |
| LCH-1 | emulator | 1-3 on running apps only move the light, open nothing | 0 Chrome starts for keys 1,2,3; verbs line follows the light | **PASS** | logs/LCH-1_keys_0to4.txt |
| LCH-2 | emulator | 0 lights nothing, verbs say launcher; 4 free | `on launcher: apps are running, so u needs one lit app`; `quadrant 4 is free` | **PASS** | logs/LCH-1_keys_0to4.txt |
| LCH-3 | emulator | RUNNING with port and age | `RUNNING 8082  48m` etc. | **PASS** | logs/LCH-1_keys_0to4.txt |
| LCH-4 | emulator | arrows move the light | down arrow moved the light to day | **PASS** | logs/LCH-1_keys_0to4.txt |
| LCH-W | emulator | frame intact at 40, 50, 60, 80 columns | 60 and 80 clean; 50 wraps the two hint lines mid-word; 40 breaks every row of the frame (fixed 47 wide) | **FAIL** | logs/LCH-width_40.txt, logs/LCH-1_keys_0to4.txt |
| LCH-H | emulator | h shows help that fits | help is wider than 60 columns (wraps mid-word) and still says the numbers are there because a phone has no F keys (removed in v21); lists x for uninstall while the row says wipe | **FAIL** | logs/LCH-keys_h_i_q.txt |
| LCH-Q | emulator | q quits leaving servers running | `servers left running. S stops them.` | **PASS** | logs/LCH-key_q.txt |
| LCH-I | emulator | i shows install/remove | INSTALL OR REMOVE screen with [x] for the three | **PASS** | logs/LCH-key_i.txt |
| LCH-EOF | emulator | end of input leaves, starts nothing | EXIT 0 in 0.55 s, 0 Chrome starts | **PASS** | logs/LCH-keys_h_i_q.txt |
| DAY-1 | emulator | day.commute page: corridors and live rows | Buzin, Gl.kolodvor, Britanac corridors; rows with minutes | **PASS** | screenshots/DAY-1_page.png |
| DAY-PDF | emulator | printed timetables parse without Gemini | 4 PDFs (220, 221, 241, 268) parsed, source regex-approx | **PASS** | logs/DAY-pdf_gemini_emulator.txt |
| DAY-GEM-0 | emulator | no Gemini key: nothing breaks | /pdf-sched answers ok with no routes; /key-status set:true working:false (the Maps key is tried as a Gemini key) | **PASS** | logs/DAY-pdf_gemini_emulator.txt |
| DAY-GEM-1 | emulator | Gemini key present | no Gemini key was provided for this test | **BLOCKED** |  |
| AND-API | emulator | termux-location, notification, wake lock (after installing termux-api by hand) | gps fix ±5 m, notification posted, wake lock rc 0, all.commute /gps reads the fix | **PASS** | logs/ANDROID-termuxapi_emulator.txt |
| AND-NETLOC | emulator | location while only the network provider answers | the emulator has no network location provider (times out) | **BLOCKED** | logs/ANDROID-termuxapi_emulator.txt |

## FAILURES

### F1. Labels are drawn under the GPS chip and the watch bar, so tapping them opens something else (blocks release)
- Steps: all.commute, Leaflet map, GPS at Trg bana Jelačića (45.8130, 15.9772) or Kvaternikov trg (45.8152, 16.0044), zoom 15-18, tap a label near the top or the bottom of the map.
- Happened: labels sit at y≈80 CSS px, under `#gpsChip` (which reaches y≈90): the tap opens Settings (`#setup`). Labels at y≈705 of 759 sit under the watch bar: the tap opens the watched station. 106_1, 106_2, 1849_23, 1849_24, 247_1, 247_2 opened Settings; 110_41, 110_51, 292_2 opened the watched station (`logs/ALL-LBL_labels.txt`, `screenshots/ALL-LBL_jelacic_z17.png`: 106_1 is covered by the "±3 m satellites" chip).
- Should: every label tappable, opening its own station.
- Suspect: `layoutPins()` in all.html, `clampAll`: `o.h / 2 + 64` top margin and `sz.y - o.h / 2 - 4` bottom margin ignore the HUD, the GPS chip and the watch bar.

### F2. A fresh install gives all.commute no Google key (blocks release)
- Steps: fresh emulator, key file in Downloads as Google-maps-api.txt, `bash 21-maha_commute_v21.sh --online --apps all`.
- Happened: installer says `google maps key... found`, the shared store gets it (39 B), day.commute and night.commute get it (40 B), but `~/.all.commute/google-api.txt` is never written; `/api-keys` answers `{"keys": []}`, settings shows Map key red, no photograph. all.commute's server reads only its own KEYFILE, and its payload's own search looks only for `google-api.txt`, not `Google-maps-api.txt` and not the shared store.
- Should: every app that uses the key gets it from the shared store.

### F3. The shared key store is filled from an empty file (blocks release)
- Steps: the real phone (v20 to v21 upgrade): `~/.commute/google-api.txt` is 1 byte (a newline), `~/.all.commute/google-api.txt` holds the real 40 character key.
- Happened: the umbrella's search takes the first `-s` file, the 1 byte one, writes an empty key to `~/.maha.commute/keys/google-api.txt` (0 bytes); `maha-commute info` says `key none`.
- Should: a candidate counts only if it holds a key after cleaning (e.g. matches `^AIza[0-9A-Za-z_-]{35}$`).

### F4. The installer does not reinstall an app whose folder was deleted (blocks release)
- Steps: `rm -rf ~/.all.commute`, then `bash 21-maha_commute_v21.sh --offline --apps 3`.
- Happened: `already current, left alone: all.commute`, the summary says `on all.commute v44`, nothing is installed; the launcher still shows `v44 ready`. `bash ~/.maha.commute/install-one.sh all --offline` did reinstall it.
- Should: "installed" means the stamp AND the app's files exist.
- Suspect: the stamp check (`~/.maha.commute/installed/<id>`) alone decides "current".

### F5. `maha-commute day` and `maha-commute all` never return to their caller (blocks release for scripts, widgets and Termux:Boot)
- Steps: `ssh ... 'maha-commute day </dev/null'` (or any script, widget or boot script).
- Happened: prints `up on 8082` and `EXIT=0`, but a forked copy of maha-commute (same argv) stays in `do_wait` as the PARENT of `commute_server.py`, holding the caller's stdout pipe (fd 1 -> pipe, fd 0 and 2 -> /dev/null), so the caller hangs until the server dies: 9 minutes on the emulator, 25 on the phone, before it was killed. `maha-commute night` returns, because night's launcher does not `exec`; day's and all's launchers end in `exec python "$SERVER"`.
- Suspect: `start_app()`'s `( cd "$HOME" && setsid nohup "$(launcher_of "$id")" </dev/null > log 2>&1 & echo $! > pid ) 2>/dev/null || (...)`: the subshell ends up waiting on the exec'd server. A `setsid -f`, or `disown`, or running the launcher through `nohup setsid bash -c '...' &` outside a subshell would avoid it. Test from a non-tty caller.

### F6. State-changing routes act on GET (blocks release: any web page can wipe the index)
- `/cache/clear`, `/rebuild`, `/sched-delete` are handled in `do_GET`. They are phone-only by peer and Host, but a web page open in Chrome on the same phone sends `<img src="http://127.0.0.1:8084/cache/clear">` with peer 127.0.0.1 and Host 127.0.0.1:8084, so the guard lets it through. Verified: GET /cache/clear removed network.db.
- Should: POST only, plus an `Origin`/`Sec-Fetch-Site` check (reject cross-site), or a per-run token the page holds.

### F7. After an offline start the timetable index is never built (annoying)
- Steps: airplane mode, install, start all.commute, airplane off.
- Happened: the start-up build failed (`could not download GTFS zip: gaierror 7`) and was not retried: `/board` said `no station index yet` 25 minutes after the network came back. Stations were fine; departures absent until `/rebuild`.
- Should: retry the build with backoff (e.g. 30 s, 1, 2, 5 min) while there is no index, or when `/status` is asked and the index is missing.

### F8. The locate button centres on the old position (annoying)
- Steps: dot at A, move the phone 3.8 km to B (no burst running), press locate.
- Happened: the map went to A; the fresh fix from `sharpen()` arrived and only moved the dot (`logs/ALL-FOL_follow.txt`, first row).
- Suspect: the click handler does `if (ME) { setView(ME, ...); WANT_CENTRE = false; }` before the new fix. Keep `WANT_CENTRE` true until the first fix of the new burst (and centre again on it), or centre only when the stored fix is fresh.

### F9. termux-api is reported as present but not installed (annoying)
- Fresh install: the dependency table says `ok termux-api`, `dpkg -l termux-api` says `un`; `termux-location` does not exist. The check uses `termux-open-url` (`HAVE_OPEN`), which comes from termux-tools. After `pkg install termux-api` by hand, `termux-location` and all.commute's `/gps` work.

### F10. The first-start wait does not wait without a terminal (annoying)
- `start_app()` paces itself with `read -rsn1 -t 0.4`; with stdin at /dev/null `read` returns at once, so the 450-step "three minutes" passes in seconds (`24s waiting` printed after 2.5 s). A slow first start from a widget or Boot would be declared failed early. Use `sleep 0.4` when stdin is not a terminal.

### F11. `update --check <file>` offers to install, and a missing file is ignored (annoying)
- `maha-commute-update --check /sdcard/Download/21-maha_commute_v21.sh` printed `Enter install it  n stop`; --check promises to change nothing. `maha-commute-update --check /sdcard/Download/nope.sh` silently fell back to GitHub.

### F12. The launcher frame breaks below 47 columns (cosmetic; annoying on a big font)
- 40 columns: every frame row wraps. 50: the two hint lines wrap mid-word (`the laun|cher`). 60 and 80 clean.

### F13. Help text (cosmetic)
- Wider than 60 columns (wraps mid-word at 60); still says "The number is only there because a phone has no F keys" (the F-key digits were removed in v21); lists `x uninstall` while the bottom row says `wipe`.

### F14. Small visual faults (cosmetic)
- The HUD line ("5 stations within 149 m. Tap a station…") runs under the ★ and tram buttons (`screenshots/ALL-1_airplane_first_load.png`).
- The Leaflet attribution is drawn over the Google footer in the 360 view (`screenshots/ALL-DASH_360_tapped.png`).
- The quadrant's third line repeats the version (`v44 ready` / `v44`) instead of the app's one-line description.
- The installer prints `installed the star interface v39` for all.commute v44.


## Unplanned findings

- The watched stop is fetched twice in the same second, once by the dashboard and once by the watch bar.
- Each `maha-commute` start opens a new Chrome tab; after a morning of tests the emulator had 12 tabs, several of them the same app.
- github main's `VERSION` says 20 while the branch is at 21; `--check` therefore says "v21 is the newest there is", which is correct here but means a phone on v20 is not offered v21 until main is updated.
- Real feed numbers for the cloud: 3797 rows in stops.txt, 2523 platforms kept, 2507 served on a Thursday, 2336 on Sunday and on the 18.11 holiday (Sunday service, 7193 trips, 124 708 departures), 13 532 trips and 228 676 departures on a weekday. The rebuild takes about 14 s on the emulator with a 51 MB peak.

## BLOCKED (so far)

- ALL-DASH-5: the 360 view's imagery is black on the emulator (software WebGL); the view itself opens. Needs the real phone.
- Network-only location: the emulator has no network location provider (`termux-location -p network` times out).
- Still to run when this was written: SOAK (2 h, running), Doze and the phantom process killer, Termux killed from recents, reboot with Termux:Boot, low storage and memory, location denied, port bumping with `nc -l`, kill -9 with a stale port file, 20 starts of day.commute, install twice and while running, `u` and `--app`, uninstall and reinstall, DAY midnight countdown, PDF and Gemini fallback, NIT night trams, the live feed row, the star across restart and update, the page race rerun with the GPS still.


## Requests for the cloud

1. **Keep labels off the controls.** In `layoutPins()` clamp each label inside the map area that is not covered: below the bottom edge of `#gpsChip`/the HUD (measure them, do not hard-code 64) and above the top of the watch bar when it is shown; and make the label, not the chip, win the tap if they still meet. Add a test6 case: a station whose label would land under the chip.
2. **Give all.commute the key.** The installer (and all.commute's own payload) should copy the shared store's key into `~/.all.commute/google-api.txt`, or all.commute's server should fall back to `~/.maha.commute/keys/google-api.txt`. Also accept `Google-maps-api.txt` in Downloads in the payload's own search.
3. **Validate a key before using it as the source.** In the umbrella's search, skip files whose cleaned content is not a key (empty, a newline, too short); keep looking.
4. **"Installed" must mean files present.** Treat an app whose folder or server file is missing as not installed, both in the installer's "already current" decision and in the launcher's quadrant and the `i` screen.
5. **Make `maha-commute day|night|all|restart|open` return.** The started server must not be a child of a process that holds the caller's terminal or pipe (see F5). Add a test that runs `maha-commute day </dev/null | cat` with a timeout and expects it to end within 30 s while the server stays up.
6. **POST and a same-origin check for every route that changes state** (`/cache/clear`, `/rebuild`, `/sched-delete`, the key and Gemini setters): reject GET, and reject requests whose `Sec-Fetch-Site` is `cross-site` or whose `Origin` is not the app's own.
7. **Retry the station index build** while there is none and the network fails, with a backoff, and say so in `/status` (`state: waiting_for_network`).
8. **Locate button:** keep `WANT_CENTRE` until the new burst's first fix and centre on that one (it may centre on the last position first, but must follow up once).
9. **Install `termux-api` (the package) in the dependency step**, check it with `command -v termux-location`, and say clearly if Termux:API (the app) is missing.
10. **Pace the first-start wait with `sleep`** when stdin is not a terminal.
11. **update.sh:** `--check` with a file must only describe it; a path that does not exist must be an error.
12. **Launcher at narrow widths:** below 47 columns draw a one-column layout (four rows) instead of the 2x2 frame; keep the hint lines under the width.
13. **Help:** wrap to the terminal width, remove the F-key sentence, use the same letter for uninstall as the bottom row.
14. **Cosmetic:** HUD text must not run under the top buttons; hide the Leaflet attribution while the 360 view is open; quadrant third line = the description; the payload's banner should say v44.


## Testing status

**TESTING IS STILL RUNNING** (last update 08.10.2026 19:00). More results will be added to this file and pushed after each test. Re-fetch it before deciding anything; the list of failures and requests above only grows.
