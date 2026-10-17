"""payload_v27.py, what v27 does to the payloads. Called from patch_payload.py
after V26.patch_night (the anchors here are its output).

NIGHT.COMMUTE v17: THE STREET-VIEW FAILURE STATE, FOUND ON THE PHONE. The first
on-device test of v16 (Pixel 7, 17.10.2026, field-tests/2026-10-17_v26) showed
the dashboard working but caught two faults in the dashboard's LOOK when the
Street View photo does not load -- which is the common case, because most Google
keys are not authorised for the Street View Static API (Marko's was not):

  * When the <img> failed, its onerror only hid the image. The location pin and
    the "360" badge are absolutely positioned inside the same frame, so with the
    image gone the frame collapsed to nothing and the pin and badge floated down
    onto the card below and COVERED THE WATCH BUTTON. Now the whole frame is
    replaced with the "no Street View" note (dash.js, ndSvFail), so the failure
    state is clean and WATCH stays tappable.

  * The Leaflet/OSM attribution control sits at z-index 1000 and showed THROUGH
    the full-screen dashboard and over the watch bar. The dashboard, the watch
    bar and the 360 viewer now sit above it, and the attribution is hidden while
    the dashboard or the viewer is open (dash.css) -- the same thing all.commute
    does for its 360 viewer.

The fixes are in the dashboard's own files (src/payloads/night/dash.js and
dash.css), which are spliced in by v25's patcher, so only the version strings
need touching here. The Street View / 360 CONTENT failures themselves are not an
app fault: they are the key's Google Cloud API authorisation, which is Marko's
to enable. day and all.commute are unchanged in v27.
"""

NIGHT_FIXES = [
    ('NIGHT_VERSION="v16 (a)"', 'NIGHT_VERSION="v17 (a)"'),
    ('APP_VERSION = "v16"', 'APP_VERSION = "v17"'),
    ('APP_BUILD = "n16-a"', 'APP_BUILD = "n17-a"'),
    ('(v.version||"v16")', '(v.version||"v17")'),
    ('textContent="v16 (a)"; });', 'textContent="v17 (a)"; });'),
    ('installed  night.commute v16 (a)', 'installed  night.commute v17 (a)'),
]


def _apply(src, fixes, who):
    for old, new in fixes:
        if src.count(old) != 1:
            raise SystemExit("payload_v27: %s, this anchor matches %d times, not once:\n    %s"
                             % (who, src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)
    return src


def patch_night(src):
    return _apply(src, NIGHT_FIXES, "night")
