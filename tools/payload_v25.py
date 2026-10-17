"""payload_v25.py, what v25 does to the payloads. Called from patch_payload.py
after v22's patch_night (the anchors here are v22's output).

NIGHT.COMMUTE GETS all.commute's STATION DASHBOARD. Marko, 16.10.2026: "update
Night Commute app so it has dashboard for each station, same as All Commute …
the same look and same functionality, only with different set of lines."

So tapping a station on the Map now slides up one full-screen dashboard for that
station alone — its Street View photograph, what has just left, what is coming,
and WATCH — exactly the panel all.commute grew in v20, and a bottom watch bar
that keeps the next three departures, as all.commute's does since v23. The look
is all.commute's; the data under it is night.commute's own four night trams
(31–34) and the live feed it already reads, so there is no new server route and
no second copy of the schedule logic: the board is built from realTimes() and
liveApproaching(), the same functions the Plan tab reads.

WHERE THE CODE IS, AND WHY IT IS NOT A HAND EDIT

In src/payloads/night/dash.js and dash.css as ordinary files, spliced in here
against anchors that must match exactly once. Four hundred lines of dashboard
quoted inside this module would be four hundred lines nothing can lint, diff or
run, and the payload in src/payloads stays byte for byte what was handed over.

dash.js goes in AFTER live.js and star.js, because it wraps liveDraw and loadNet
and a wrapper has to go round the finished one. dash.css goes in after the live
and star CSS, for the same no-reason-to-be-last that any addition has.

The classes are prefixed nd- because night.commute already owns a .card, a .btn
and other short names that all.commute's dashboard CSS also uses; the look is
borrowed and the names are this app's own, so nothing already on the page moves.
"""

import os

HERE = os.path.dirname(os.path.abspath(__file__))
NIGHT_DIR = os.path.join(HERE, "..", "src", "payloads", "night")


def _part(name):
    with open(os.path.join(NIGHT_DIR, name), encoding="utf-8") as f:
        return f.read()


# The overlay elements: the dashboard, its watch bar and the 360 viewer. They
# are position:fixed, so where they sit in the body does not matter; they go in
# just before the top HUD so they are the first thing after <body>.
_MARKUP = '''  <div id="ndWatchbar"></div>
  <div id="ndDash">
    <div class="nd-dhead">
      <div class="nd-dtitle">
        <b id="ndName">—</b>
        <div class="nd-sub" id="ndSub">—</div>
        <div class="nd-badges" id="ndBadges"></div>
      </div>
      <button class="nd-close" id="ndClose" title="Back to the map">✕</button>
    </div>
    <div class="nd-dbody" id="ndBody"></div>
  </div>
  <div id="ndPano">
    <div class="nd-panobar"><span id="ndPanoName">—</span>
      <button id="ndPanoClose" title="Close">✕</button></div>
    <div id="ndPanoView"></div>
  </div>
'''


def _night_fixes():
    dash_css = _part("dash.css")
    dash_js = _part("dash.js")
    return [
        # A change is a new version, and the app says the number it is.
        ('NIGHT_VERSION="v14 (a)"', 'NIGHT_VERSION="v15 (a)"'),
        ('APP_VERSION = "v14"', 'APP_VERSION = "v15"'),
        ('APP_BUILD = "n13-a"', 'APP_BUILD = "n15-a"'),
        ('(v.version||"v14")', '(v.version||"v15")'),
        ('textContent="v14 (a)"; });', 'textContent="v15 (a)"; });'),
        ('installed  night.commute v14 (a)', 'installed  night.commute v15 (a)'),

        # The look, after the live and star CSS.
        ('</style>', dash_css + '</style>'),

        # The overlay markup, before the top HUD.
        ('  <div class="tophud">', _MARKUP + '  <div class="tophud">'),

        # The code, after live.js and star.js and before the page boots.
        ('/* boot */', dash_js + '\n/* boot */'),

        # A tap on a station opens its dashboard. The background-tap that picks a
        # journey end (onClick -> nearestStation -> pickMapStation) is untouched,
        # so the Map tab still sets A and B; only the dot itself now opens the
        # dashboard, which is what all.commute does.
        ('()=>pickMapStation(s)', '()=>openStationDash(s)'),

        # and the map tip says the dot is now a way in.
        ('One finger pans, pinch to zoom.</div>',
         'Tap a station dot to open its full dashboard. One finger pans, pinch to zoom.</div>'),
    ]


def _apply(src, fixes, who):
    for old, new in fixes:
        if src.count(old) != 1:
            raise SystemExit("payload_v25: %s, this anchor matches %d times, not once:\n    %s"
                             % (who, src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)
    return src


def patch_night(src):
    return _apply(src, _night_fixes(), "night")
