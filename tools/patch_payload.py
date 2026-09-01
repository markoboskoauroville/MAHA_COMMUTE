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

  night.commute   reset  nothing, because it stores no selection. Its four
                         keys are the map engine, the basemap, which lines
                         are shown and the stops you added yourself, and
                         every one of those is a preference or your own
                         work. Saying "night resets nothing" is the honest
                         answer; inventing a reset for symmetry would throw
                         away typed stops.

WHAT COUNTS AS A NEW RUN

The launcher opens the page with ?run=<seconds>, and a run id that differs
from the stored one is a new run. When there is no run id, because the URL
was typed or came from a bookmark, a fresh navigation counts as new and a
reload does not, so pulling to refresh does not wipe your pick mid journey.
"""

import re
import sys

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
    "all":   ['LS.get("watch"', 'LS.get("view"'],
    "night": [],
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
