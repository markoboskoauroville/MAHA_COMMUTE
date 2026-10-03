# MANIFEST

**Change log for MAHA_COMMUTE. One entry per version, newest first.**

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
