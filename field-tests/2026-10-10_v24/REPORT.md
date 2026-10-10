# Field test, MAHA_COMMUTE v24, 10.10.2026

**Partial.** Read-only checks against the v24 install on Marko's phone, run by a Claude
Code session on the phone (Remote Control) and directed from the cloud session.
Step 6 (the CLI returning) passed; steps 7 and 8 were cancelled by Marko: "Work only
with All Commute app. Cancel all other tests."

## Environment

| | |
|---|---|
| Phone | model A142, Android 16, arm64-v8a, Termux (termux-tools 1.45.0, Termux:API 1002, Termux:Widget 1001) |
| Session | Claude Code **inside proot-distro as root**, not the Termux user. `$PREFIX` empty, `dpkg` reads proot's own database |
| Installed | umbrella v24 (env.sh), all.commute v47, day v18, night v14 |
| Running | all.commute on 8084 (pid 7537), started 07:08 local |
| Feed | real ZET GTFS, service date 20261010, 2523 stations, 164 761 departures, live feed 373-376 trips |

## Results

| id | expectation | what happened | result |
|---|---|---|---|
| KEY-1 (F2, F3) | all.commute has the key from the shared store | store 39 B, all/day/night copies 40 B (trailing newline); `/api-keys` answers one key, length 39 | **PASS** |
| KEY-2 | the key works against Google | `/key-test`: ok, streetview true, status OK | **PASS** |
| ST-1 (v24) | 2523 stations, with a revision and a change report | `/status` stations_count 2523, stations_rev 2f8ce767a843, stations_changes 0 new / 0 moved / 0 renamed / 0 not in feed; `/stations.json` count 2523, stops a dict of 2523 | **PASS** |
| BOARD-1 | Glavni kolodvor board | 109_1 answers lines 13, 2, 4, 6, 9; index_stale false; live feed ok | **PASS** |
| SEC-1 (F6) | cross-site POST to /cache/clear refused | 403 | **PASS** |
| SEC-2 | HEAD /cache/clear does not act | 501 (no do_HEAD; the stdlib refuses, not the v22 guard) | **PASS** |
| DEP-1 (F9) | termux-api installed, termux-location present | Termux's own dpkg status: installed; termux-location in usr/bin; network fix ±100 m | **PASS** |
| GPS-1 | a failed reading is reported as failed | **termux-location prints `{"API_ERROR": "Failed to get location"}` and exits 0; termux_fix answered `{"ok": true, "provider": "gps"}` with no coordinates**. The page's position froze while status said fine. One `/gps` 500 also seen in server.log at 07:39:35 | **FAIL, fixed in v25** |
| GPS-2 | cold `termux-location -p network -r once` within 25 s | first call timed out at 25 s, the retry answered at once | note: the app uses `-r last` with 8-14 s |
| TEST-3 on phone | ugly cases | 71 passed, 0 failed (run from the old v16 checkout, so it is v16's test 3) | not v24 evidence |
| CLI-1 (F5, F10) | `maha-commute day </dev/null \| cat` returns | rc 0 in 15 s, day answered 200 afterwards; `running/day.port` is not written (the 8082 fallback answered) | **PASS** |
| GPS-3 | elapsedMs is the fix's age | 92 744 ms on a fix 92 s old, 397 533 ms on one 6.6 min old, 14 ms on fresh calls: it is the age | **PASS** |
| GPS-4 | the /gps 500 at 07:39:35 can be diagnosed | no traceback anywhere: the route dispatch returned `repr(e)` only in the body. A 200 and a 500 for /gps in the same second, on a threading server, each shelling out to termux-location. Not reproduced | **FAIL, logged from v25** |
| PORT-1 | night bumps off a busy port | cancelled by Marko | **NOT RUN** |
| LCH-W (F12, F13) | launcher at 40 and 60 columns | cancelled by Marko | **NOT RUN** |

## Cautions for the next field test

- A session in proot as root is not the Termux user: `dpkg -s` lies about Termux packages, and `termux-notification-list` hung (killed at 20 s). Prefer the Termux shell itself, or sshd in Termux.
- `/sdcard/Download/MAHA_COMMUTE` on the phone is a checkout at v16. Nothing should be built or installed from it until it is updated to the branch.

## For the cloud

1. **Done in v25:** a location answer counts only if it carries latitude and longitude; `API_ERROR` is `ok: false` with Android's reason (`tools/payload_v25.py`, three checks in test 7).
2. **Done in v25:** a failed reading carries the last good one and its age; the page says
   "last known fix, N min ago" instead of "no provider answered", and the fresh-fix button
   no longer says "Android answered." when it did not. A 500 writes its traceback to the log.
3. Open: gps_state asks the two providers one after the other (8 s + 6 s at worst) while
   the page repaints the chip every 3 s; `-r once` hung past 30 s on this phone.
4. The phone runs a hand-patched all.commute (pid 13406) with the same location fix, made
   by the phone session; installing v25 replaces it.
