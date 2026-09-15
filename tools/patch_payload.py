#!/usr/bin/env python3
"""patch_payload.py, applied at build time, never to the sources.

    tools/patch_payload.py <payload.sh> <app-id>   > patched

WHAT IT DOES AND WHY IT IS NOT A HAND EDIT

The three apps remember what you last picked, in the browser's own
localStorage. A new run of the server cannot clear that, because it is not
on the phone's filesystem at all: it belongs to the page's origin and it
outlives any number of restarts. So a few lines have to go into the page.

They go in HERE, at build time, and not into src/payloads, so that:

  the payloads stay byte for byte what was handed over, and importing
  day.commute v14 later means dropping the new file in, not merging

  the change is one visible transformation with one test, rather than an
  edit somewhere inside four thousand lines that nobody finds again

WHAT IS RESET AND WHAT IS KEPT

Reset is for what you PICKED. Kept is for how you like the thing to LOOK,
and for anything you typed and would have to type again. Losing a display
preference is an annoyance; losing a list of custom destinations is work
thrown away, so the two are on opposite lists.

  day.commute     reset  commute_pick    the destination you picked
                         bus_dir         the direction
                         commute_watch   the vehicle being watched
                  kept   commute_custom  destinations you typed yourself
                         commute_excluded, commute_scope_h, commute_autodir,
                         commuteMapStyle, bus_muted, commute_filtopen,
                         commute_pdfsched

  all.commute     reset  ac2_watch       the station you picked
                         ac2_view        where the map was left sitting
                  kept   ac2_mode, ac2_engine, ac2_radius, ac2_layers

  night.commute   reset  nothing, because it stores no selection. Its keys
                         are the map engine, the basemap, which lines are
                         shown, the stops you added yourself and nc_fav, the
                         stations you starred. Every one of those is a
                         preference or your own work. Saying "night resets
                         nothing" is the honest answer; inventing a reset for
                         symmetry would throw away a list somebody built by
                         hand, and the favourites are the clearest case of
                         that there is.

WHAT COUNTS AS A NEW RUN

The launcher opens the page with ?run=<seconds>, and a run id that differs
from the stored one is a new run. When there is no run id, because the URL
was typed or came from a bookmark, a fresh navigation counts as new and a
reload does not, so pulling to refresh does not wipe your pick mid journey.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
NIGHT_LIVE = os.path.join(HERE, "..", "src", "payloads", "night-v10")


def _part(name):
    with open(os.path.join(NIGHT_LIVE, name), encoding="utf-8") as f:
        return f.read()

RESET = {
    "day":   ["commute_pick", "bus_dir", "commute_watch"],
    "all":   ["ac2_watch", "ac2_view"],
    "night": [],
}

# A key that has to exist in the payload for the reset to mean anything. If
# an upstream version renames one, this fails the build rather than shipping
# a reset that silently clears nothing.
WITNESS = {
    "day":   ['localStorage.getItem("commute_pick")', 'localStorage.getItem("bus_dir")'],
    "all":   ['LS.get("watch"', 'LS.get("view"', 'function starHTML', 'function drawStars'],
    # Everything the live feed reaches into. It does not edit any of these, it
    # wraps them, and a wrapper around a function that has been renamed or
    # reshaped upstream is not an error anywhere: it is a page that loads,
    # runs, and quietly never shows a tram. These turn that silence into a
    # failed build.
    "night": [
        'function legHtml(ln, a, b, markNext)',   # the live rows hang off this
        'function dirIndex(ln,a,b)',              # which way you are travelling
        'async function initMap()',               # the trams are drawn after it
        'function resetMap()',                    # and taken off in it
        'function switchTab(t)',                  # what starts and stops polling
        'const GEng = {',                         # both engines are taught
        'const LEng = {',                         # to draw a vehicle
        'let MAP=null',                           # which map they draw on
        'id="lineChecks"',                        # what the status strip sits above
        '"stopmap"',                              # station name -> its two stop ids
        'NIGHT_ROUTES = ("31", "32", "33", "34")',
        'SCHED_JSON = os.path.join(APPDIR, "night_sched.json")',
        # and what the star reaches into
        'function searchStations(q)',             # favourites are sorted to the top
        'function wireSearch(inputId, sugId, which)',   # the picker they are starred in
        'function computeRoute(target)',          # a chip fills a field and re-plans
        'id="tab-plan"',                          # where the chips are inserted
        'class="picker"',                         # and just above which one
    ],
}

# Everything else that is done to a payload on its way out: the midnight
# countdown fix in day, the tap and the pin in all, and night's live feed.
# They live here rather than in src/payloads for one reason, which is that
# src/payloads holds the files as they were handed over, so importing
# day.commute v14 is dropping a file in rather than merging one.
#
# Each entry is an anchor and its replacement. The anchor must appear exactly
# once or the build stops: a change that lands twice, or not at all, is worse
# than one that refuses, because both of those ship.
FIXES = {
    "all": [
        ('function pinHTML(s){\n  const c = COLOUR[s.stop_id], on = isWatched(s.stop_id), ab = dirAbbr(s.bearing);\n  return \'<div class="pin">\' +\n    \'<span class="pinid"><span style="--c:\' + c + \'">\' + esc(s.stop_id) +\n    \'</span></span>\' + starHTML(c, on) +\n    \'<span class="pinchip"><span style="--c:\' + c + \'">\' + esc(s.name) +\n    (ab ? \' <i>\' + ab + \'</i>\' : "") + \'</span></span></div>\';\n}',
         'function pinHTML(s){\n  // The number, and nothing else.\n  //\n  // This pin used to carry three things: a number, a star and a name. On a\n  // phone, in the middle of a city, that is three overlapping labels for\n  // every station and half a dozen stations in view, so the map became a\n  // pile of text with a map somewhere underneath it.\n  //\n  // The star is gone. It marked a station as "watched", which was a second\n  // idea stacked on top of simply picking one, and it had to be learned\n  // before it meant anything.\n  //\n  // The name is gone from the map because the number already identifies the\n  // station, and the name comes back in the popup the moment the number is\n  // tapped, which is the only moment it is needed.\n  //\n  // The direction letter stays. It is one character, and two stops sharing\n  // a number on opposite sides of a road is exactly the confusion a map has\n  // to resolve rather than add to.\n  const c = COLOUR[s.stop_id], ab = dirAbbr(s.bearing);\n  return \'<div class="pin">\' +\n    \'<span class="pinid"><span style="--c:\' + c + \'">\' + esc(s.stop_id) +\n    (ab ? \' <i>\' + ab + \'</i>\' : "") + \'</span></span></div>\';\n}'),
        ('function hud(html, busy){\n  document.getElementById("hud").innerHTML =\n    (busy ? \'<span class="spin">●</span> \' : "") + html;\n}',
         'const BRAILLE = ["\\u280b","\\u2819","\\u2839","\\u2838","\\u283c","\\u2834","\\u2826","\\u2827","\\u2807","\\u280f"];\nlet _spinT = null, _spinI = 0;\nfunction hud(html, busy){\n  // Same signature it always had, so every existing caller keeps working.\n  // What changed is that busy now turns, instead of showing a dot that\n  // looks identical whether the app is working or has died.\n  const el = document.getElementById("hud");\n  if (!el) return;\n  if (_spinT) { clearInterval(_spinT); _spinT = null; }\n  if (!busy) { el.innerHTML = html; return; }\n  const paint = () => {\n    el.innerHTML = \'<span class="spin">\' + BRAILLE[_spinI % BRAILLE.length] +\n                   \'</span> \' + html;\n    _spinI++;\n  };\n  paint();\n  _spinT = setInterval(paint, 90);\n}'),
        ('function clearStars(){',
         '// Arming a station: the outline is immediate, the fetch is not.\n//\n// A tap used to go straight to the network, so the first thing that happened\n// after touching a station was nothing, for as long as the request took. On\n// a phone that reads as a dead app and the finger taps again.\n//\n// Now the outline lands on the same frame as the tap, and the fetch waits a\n// third of a second. Long enough to change your mind after a mis-tap, short\n// enough that a deliberate tap does not feel held back. Tap three stations\n// in a row and only the third is ever fetched: each tap moves the outline\n// and cancels the one before it.\n//\n// SELGEN is what makes a cancelled fetch stay cancelled. A request already\n// in flight cannot be recalled, but its answer can be thrown away, and the\n// generation it was started under is how it knows it is stale.\nlet ARM_T = null, SELGEN = 0;\nfunction armStation(s){\n  SELGEN++;\n  const gen = SELGEN;\n  if (ARM_T) { clearTimeout(ARM_T); ARM_T = null; }\n  document.querySelectorAll(".pin.armed").forEach(e => e.classList.remove("armed"));\n  const mk = MARKS[s.stop_id];\n  const el = mk && mk.getElement ? mk.getElement() : null;\n  const pin = el ? el.querySelector(".pin") : null;\n  if (pin) pin.classList.add("armed");\n  hud("<b>" + esc(s.stop_id) + "</b> selected", true);\n  ARM_T = setTimeout(() => {\n    if (gen !== SELGEN) return;\n    hud("<b>" + esc(s.stop_id) + "</b> reading arrivals", true);\n    openPop(s, gen);\n  }, 333);\n}\nfunction clearStars(){'),
        ('      m.on("click", () => openPop(s));',
         '      m.on("click", () => armStation(s));'),
        ('async function openPop(stop){\n  SEL = stop;',
         'async function openPop(stop, gen){\n  // gen is the arming generation. If a later tap has happened while this was\n  // in flight, everything below would draw the wrong station over the right\n  // one, so it stops here instead.\n  if (gen !== undefined && gen !== SELGEN) return;\n  SEL = stop;\n  // Opening a station IS watching it. Tap the number or tap the name, and\n  // that station is the one being watched until another is opened. The\n  // separate toggle still lets a station be dropped, but nothing has to be\n  // toggled on any more: picking is the whole gesture.\n  if (!WATCH || WATCH.stop_id !== stop.stop_id) {\n    WATCH = { stop_id: stop.stop_id, name: stop.name, lat: stop.lat, lon: stop.lon };\n    LS.set("watch", WATCH);\n    document.body.classList.add("watching");\n    const _db = document.getElementById("dashBtn");\n    if (_db) _db.classList.add("hasbar");\n    if (!COLOUR[stop.stop_id]) COLOUR[stop.stop_id] = stationColour(stop.stop_id);\n    drawStars(); updateWatchBar();\n    if (!boardTimer) boardTimer = setInterval(refreshBoards, 20000);\n  }'),
        ('  await refreshPop();',
         '  await refreshPop();\n  if (gen !== undefined && gen !== SELGEN) return;\n  hud("<b>" + esc(stop.stop_id) + "</b> " + esc(stop.name), false);'),
        ('  .starwrap{background:none;border:0;}',
         '  .starwrap{background:none;border:0;}\n  /* The armed outline. White, because every other colour on this map means\n     a line or a station, and this one has to mean "you touched this" and\n     nothing else. */\n  .pin.armed .pinid span{box-shadow:0 0 0 2px #fff,0 0 10px rgba(255,255,255,.55);}'),
    ],
    # night.commute v10: it reads the live feed and says where the tram is.
    #
    # The new code is in src/payloads/night-v10/ as ordinary .py, .js and
    # .css files rather than as string literals in here, because four hundred
    # lines quoted inside this file would be four hundred lines nothing can
    # lint, diff or run. What this table holds is the JOIN: an anchor that
    # must appear exactly once, and what goes next to it.
    "night": [
        # The app's own version. A change is a new version, and the app has
        # to say the number it is, not the number it grew out of.
        ('NIGHT_VERSION="v9 (a)"',
         'NIGHT_VERSION="v10 (a)"'),
        ('APP_VERSION = "v9"\nAPP_BUILD = "n9-a"',
         'APP_VERSION = "v10"\nAPP_BUILD = "n10-a"'),
        ('installed  night.commute v9 (a)',
         'installed  night.commute v10 (a)'),
        ('(v.version||"v9")',
         '(v.version||"v10")'),
        ('.catch(()=>{ document.getElementById("verLine").textContent="v9 (a)"; });',
         '.catch(()=>{ document.getElementById("verLine").textContent="v10 (a)"; });'),

        # The reader and the placing, ahead of the handler that serves them.
        ('class H(http.server.BaseHTTPRequestHandler):',
         _part("live.py") + '\n\nclass H(http.server.BaseHTTPRequestHandler):'),

        # One route. It never raises, so it needs no guard around it.
        ('        if r=="/version": return self._json({"version":APP_VERSION,"build":APP_BUILD})',
         '        if r=="/version": return self._json({"version":APP_VERSION,"build":APP_BUILD})\n'
         '        if r=="/live": return self._json(live_payload())'),

        # The look of a live row, of a tram on the map, and of a starred
        # station.
        ('</style>', _part("live.css") + _part("star.css") + '</style>'),

        # A star on each row of the station picker. It is its own target, and
        # it carries the station's name on itself, because the handler below
        # fires from the button rather than from the row around it.
        ('''    sug.innerHTML = list.map((s,i)=>
      '<div class="sg-item'+(i===hi?" hi":"")+'" data-i="'+i+'">'+s+
      '<span class="sg-lines">'+ST_LINES[s].map(lineBadge).join("")+'</span></div>').join("");''',
         '''    sug.innerHTML = list.map((s,i)=>
      '<div class="sg-item'+(i===hi?" hi":"")+(isFav(s)?" fav":"")+'" data-i="'+i+'">'+
      '<button class="sg-star" data-st="'+esc(s)+'" title="Keep this station">'+
      (isFav(s)?STAR_ON:STAR_OFF)+'</button>'+esc(s)+
      '<span class="sg-lines">'+ST_LINES[s].map(lineBadge).join("")+'</span></div>').join("");'''),

        # and the two taps kept apart. A tap on the star must not also choose
        # the station, or starring the stop you are standing at sends you to it.
        ('''    sug.querySelectorAll(".sg-item").forEach(el=>{
      el.addEventListener("mousedown",(e)=>{ e.preventDefault(); choose(list[+el.dataset.i]); });
    });''',
         '''    sug.querySelectorAll(".sg-item").forEach(el=>{
      el.addEventListener("mousedown",(e)=>{
        if (e.target && e.target.closest && e.target.closest(".sg-star")) return;
        e.preventDefault(); choose(list[+el.dataset.i]); });
    });
    sug.querySelectorAll(".sg-star").forEach(b=>{
      b.addEventListener("mousedown",(e)=>{
        e.preventDefault(); e.stopPropagation();
        toggleFav(b.dataset.st); render(); });
    });'''),

        # The front end, after everything it wraps and before the page boots.
        # The live feed goes in first: the star code wraps initMap and
        # resetMap in its turn, and a wrapper has to go round the finished one.
        ('/* boot */', _part("live.js") + _part("star.js") + '\n/* boot */'),
    ],
    "day": [
        ('function hhmmToTodaySecs(hhmm) {\n  const m = /^(\\d{1,2}):(\\d{2})/.exec(hhmm || "");\n  if (!m) return null;\n  const d = new Date();\n  d.setHours(+m[1], +m[2], 0, 0);\n  return Math.floor(d.getTime() / 1000);\n}',
         'function hhmmToTodaySecs(hhmm) {\n  const m = /^(\\d{1,2}):(\\d{2})/.exec(hhmm || "");\n  if (!m) return null;\n  const d = new Date();\n  d.setHours(+m[1], +m[2], 0, 0);\n  // A departure after midnight is tomorrow\'s, and setHours puts it on\n  // today. At 23:27 that made 00:02 into 00:02 THIS MORNING, so the live\n  // countdown read minus 1405 minutes, which is 1440 minus the 35 it should\n  // have said. The scheduled rows were right because their minutes are\n  // worked out in Python, where the rollover is already handled; only the\n  // live rows came through here, which is why one row in six was wrong.\n  // Same three hour threshold as minsUntil, so the two cannot disagree.\n  if (d.getTime() - Date.now() < -180 * 60000) d.setDate(d.getDate() + 1);\n  return Math.floor(d.getTime() / 1000);\n}'),
    ],
}

SNIPPET = '''
/* ---- MAHA COMMUTE, reset on a new run ---------------------------------
   Runs before anything below reads localStorage, which is the only reason
   it sits at the top of this block rather than at the end of the file. */
(function () {
  try {
    var run  = new URLSearchParams(location.search).get("run") || "";
    var nav  = (performance.getEntriesByType("navigation")[0] || {}).type || "";
    var prev = localStorage.getItem("maha_run") || "";
    // With a run id, a new run is a different id. Without one, a fresh
    // navigation is a new run and a reload is not, so refreshing the page
    // in the middle of a journey does not throw the pick away.
    var fresh = run ? (run !== prev) : (nav !== "reload" && nav !== "back_forward");
    if (fresh) {
      __KEYS__.forEach(function (k) { try { localStorage.removeItem(k); } catch (e) {} });
    }
    if (run) localStorage.setItem("maha_run", run);
  } catch (e) { /* a page that cannot reset is still a page that works */ }
})();
'''


def main():
    path, app = sys.argv[1], sys.argv[2]
    src = open(path, encoding="utf-8", errors="surrogateescape").read()

    for w in WITNESS.get(app, []):
        if w not in src:
            sys.exit("patch_payload: %s no longer contains %s, so the reset list "
                     "is out of date for this version" % (app, w))

    for old, new in FIXES.get(app, []):
        if src.count(old) != 1:
            sys.exit("patch_payload: %s, this anchor matches %d times, not "
                     "once, so the change cannot be placed:\n    %s\n"
                     "The payload was edited upstream and the change has to "
                     "be re-read against it."
                     % (app, src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)

    keys = RESET.get(app, [])
    if not keys:
        sys.stdout.write(src)
        return

    anchors = src.count("<script>")
    if anchors != 1:
        sys.exit("patch_payload: %s has %d <script> anchors, expected exactly 1"
                 % (app, anchors))

    snippet = SNIPPET.replace("__KEYS__", "[" + ", ".join('"%s"' % k for k in keys) + "]")
    out = src.replace("<script>", "<script>" + snippet, 1)

    if out.count("MAHA COMMUTE, reset on a new run") != 1:
        sys.exit("patch_payload: the snippet did not land exactly once")
    sys.stdout.write(out)


if __name__ == "__main__":
    main()
