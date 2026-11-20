"""payload_v23.py, what v23 does to the payloads. Called from patch_payload.py
after v22's patch_all.

ALL.COMMUTE: THE WATCH BAR SHOWS THE NEXT THREE. Marko, 9.10.2026: "it needs to show
in the watch station, when the dashboard is collapsed, 3 rides. Now it's showing
only 1. 3 trams or buses coming to the station. Next 3 needs to be shown instead
of 1."

The bar that sits at the bottom of the map while a station is watched used to show
the first coming departure and nothing else. It is now two rows: the station's
name and the stop-watching button on top, and below them the next three
departures, each with its line, its minutes and the wifi mark when it is live.
Fewer than three coming means fewer are shown, and none shows a dash. The bar is
taller, which the labels already allow for: layoutPins measures the bar's real top
and keeps the labels above it.
"""

ALL_FIXES = [
    ('APP_VERSION = "v45"\nAPP_BUILD = "b45"', 'APP_VERSION = "v46"\nAPP_BUILD = "b46"'),
    ('<div class="kv"><span>Interface</span><b>stations · v45</b></div>',
     '<div class="kv"><span>Interface</span><b>stations · v46</b></div>'),
    ('ALLC_UI_VERSION="v45"', 'ALLC_UI_VERSION="v46"'),

    ('    align-items:center;gap:10px;padding:10px 12px;border-radius:14px;\n'
     '    background:rgba(20,26,34,.94);border:2px solid var(--c,var(--border));cursor:pointer;\n',
     '    align-items:center;gap:6px 10px;flex-wrap:wrap;padding:10px 12px;border-radius:14px;\n'
     '    background:rgba(20,26,34,.94);border:2px solid var(--c,var(--border));cursor:pointer;\n'),
    ('  #watchbar .weta{display:flex;align-items:center;gap:7px;font-weight:800;color:var(--cyan);\n'
     '    font-size:.92rem;white-space:nowrap;flex:none;}\n',
     '  /* v23: the next three, on a row of their own under the name */\n'
     '  #watchbar .weta{display:flex;align-items:center;justify-content:space-between;gap:8px;\n'
     '    font-weight:800;color:var(--cyan);font-size:.92rem;white-space:nowrap;\n'
     '    order:3;flex:1 0 100%;}\n'
     '  #watchbar .wride{display:inline-flex;align-items:center;gap:5px;min-width:0;}\n'),

    ('  const next = comingAt(WATCH.stop_id)[0];\n'
     '  document.getElementById("wbEta").innerHTML = next\n'
     '    ? \'<span class="rt sm\' + (next.live ? "" : " sched") + \'" style="--r:\' +\n'
     '      routeColour(next.route) + \'">\' + esc(next.route) + \'</span> \' +\n'
     '      (next.mins <= 0 ? "now" : next.mins + " min") + (next.live ? WIFI : "")\n'
     '    : "—";\n',
     '  // the next three coming, not just the first (v23)\n'
     '  const nexts = comingAt(WATCH.stop_id).slice(0, 3);\n'
     '  document.getElementById("wbEta").innerHTML = nexts.length\n'
     '    ? nexts.map(next => \'<span class="wride"><span class="rt sm\' + (next.live ? "" : " sched") + \'" style="--r:\' +\n'
     '      routeColour(next.route) + \'">\' + esc(next.route) + \'</span>\' +\n'
     '      (next.mins <= 0 ? "now" : next.mins + " min") + (next.live ? WIFI : "") + \'</span>\').join("")\n'
     '    : "—";\n'),
]


def patch_all(src):
    for old, new in ALL_FIXES:
        if src.count(old) != 1:
            raise SystemExit("payload_v23: all, this anchor matches %d times, not once:\n    %s"
                             % (src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)
    return src
