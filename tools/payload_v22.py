"""payload_v22.py, what v22 does to the payloads. Called from patch_payload.py
after v21's patch_all (the anchors here are v21's output).

Everything in this file answers a line of field-tests/2026-10-08_v21/REPORT.md,
the first report written by the LOCAL tester on a real Pixel 7 and an emulator.

ALL.COMMUTE
  F1  labels were laid out under the GPS chip and the watch bar, so tapping them
      opened Settings or the watched station. The clamp now measures what is on
      top of the map (the HUD, the buttons, the GPS chip, the watch bar) and keeps
      every label in the free area between them.
  F2  all.commute never got the Google key on a fresh install. Its server read
      only ~/.all.commute/google-api.txt. It now falls back to the shared store.
      (The installer also copies the key into every app, see 40_main.sh.)
  F6  /rebuild, /cache/clear and /sched-delete acted on a GET, so any page open in
      Chrome on the phone could fire them with an <img>. They are POST now, and
      EVERY POST and every state-changing GET of all three apps is refused when the
      browser says it came from another site (Sec-Fetch-Site) or from another
      origin (Origin differs from Host).
  F7  an offline start never built the timetable index, even when the network came
      back. It retries with a backoff and says so in /status.
  F8  the locate button centred on the old position and then let the fresh fix go
      by. It now waits for the new fix as well.
  F14 the HUD ran under the top buttons, the Leaflet attribution drew over the 360
      view, and the installer said "star interface v39" for v45.

DAY and NIGHT
  F6  the same cross-site refusal for their state-changing routes.
"""

# ---- the guard: a cross-site request never reaches a handler --------------
# Browsers send Sec-Fetch-Site on every request they make (same-origin for the
# app's own pages, none for a typed address or a bookmark, cross-site for an
# <img> or <form> on another site) and Origin on every POST. curl sends neither,
# which is right: it is the phone talking to itself.
_OLD_GUARD = ('    def _phone_only(self, path):\n'
              '        if path not in self._PHONE_ONLY:\n'
              '            return False\n')


def _new_guard(changing):
    tup = ", ".join('"%s"' % p for p in changing)
    return ('    # v22: a request that a web page on another site made on the phone\'s behalf\n'
            '    # is refused, for every POST and for every GET that changes something.\n'
            '    _STATE_CHANGING = (%s)\n'
            '    def _cross_site(self):\n'
            '        sf = (self.headers.get("Sec-Fetch-Site") or "").lower()\n'
            '        if sf in ("cross-site", "same-site"):\n'
            '            return True\n'
            '        org = self.headers.get("Origin") or ""\n'
            '        if org and org != "null":\n'
            '            return urllib.parse.urlparse(org).netloc.lower() != (self.headers.get("Host") or "").lower()\n'
            '        return bool(org)\n'
            '    def _phone_only(self, path):\n'
            '        if (self.command == "POST" or path in self._STATE_CHANGING) and self._cross_site():\n'
            '            return True\n'
            '        if path not in self._PHONE_ONLY:\n'
            '            return False\n') % tup


_REFUSE_OLD = '"this answers on the phone only"'
_REFUSE_NEW = '"this answers on the phone only, from its own pages"'

# ------------------------------------------------------------- all.commute
ALL_FIXES = [
    ('APP_VERSION = "v44"\nAPP_BUILD = "b44"', 'APP_VERSION = "v45"\nAPP_BUILD = "b45"'),
    ('<div class="kv"><span>Interface</span><b>stations · v44</b></div>',
     '<div class="kv"><span>Interface</span><b>stations · v45</b></div>'),
    ('ALLC_UI_VERSION="v39"', 'ALLC_UI_VERSION="v45"'),

    (_OLD_GUARD, _new_guard(("/rebuild", "/cache/clear", "/sched-delete"))),

    # POST, not GET, for what changes state
    ('            if route == "/sched-delete":\n'
     '                return self._json(sched_delete(q.get("route", [""])[0],\n'
     '                                               q.get("all", ["0"])[0] == "1"))\n',
     '            if route in ("/sched-delete", "/rebuild", "/cache/clear"):\n'
     '                return self._json({"ok": False, "reason": "use POST"}, 405)\n'),
    ('            if route == "/rebuild":\n'
     '                return self._json(rebuild(q.get("force", ["0"])[0] == "1"))\n'
     '            if route == "/cache/clear":\n'
     '                return self._json(clear_index())\n', ''),
    ('        if u.path == "/api-keys":\n            keys = [ln.strip() for ln in body.splitlines() if ln.strip()]\n',
     '        if u.path in ("/rebuild", "/cache/clear", "/sched-delete"):\n'
     '            q = urllib.parse.parse_qs(u.query)\n'
     '            if u.path == "/rebuild":\n'
     '                return self._json(rebuild(q.get("force", ["0"])[0] == "1"))\n'
     '            if u.path == "/cache/clear":\n'
     '                return self._json(clear_index())\n'
     '            return self._json(sched_delete(q.get("route", [""])[0], q.get("all", ["0"])[0] == "1"))\n'
     '        if u.path == "/api-keys":\n            keys = [ln.strip() for ln in body.splitlines() if ln.strip()]\n'),
    ('fetch("rebuild?force=1", { cache: "no-store" })', 'fetch("rebuild?force=1", { method: "POST" })'),
    ('await fetch("sched-delete?route=" + encodeURIComponent(b.dataset.sdel)).catch',
     'await fetch("sched-delete?route=" + encodeURIComponent(b.dataset.sdel), { method: "POST" }).catch'),
    ('await fetch("sched-delete?all=1").catch', 'await fetch("sched-delete?all=1", { method: "POST" }).catch'),

    # F2: the key from the shared store when the app's own file has none
    ('def read_keys():\n'
     '    try:\n'
     '        with open(KEYFILE, encoding="utf-8") as f:\n'
     '            return [ln.strip() for ln in f if ln.strip()]\n'
     '    except OSError:\n'
     '        return []\n',
     'SHARED_KEYFILE = os.path.expanduser("~/.maha.commute/keys/google-api.txt")\n'
     '\n'
     '\n'
     'def _keys_from(path):\n'
     '    """Lines that are long enough to be a key: an empty file or a lone newline is none."""\n'
     '    try:\n'
     '        with open(path, encoding="utf-8") as f:\n'
     '            return [ln.strip() for ln in f if len(ln.strip()) >= 20]\n'
     '    except OSError:\n'
     '        return []\n'
     '\n'
     '\n'
     'def read_keys():\n'
     '    # v22: this app\'s own file first, then the one store every app shares\n'
     '    return _keys_from(KEYFILE) or _keys_from(SHARED_KEYFILE)\n'),

    # F7: the index is built when the network returns
    ('    if st == "failed":\n        return "the index build failed: " + BUILD_STATE["reason"]\n',
     '    if st == "waiting_for_network":\n        return "waiting for the network to build the timetable"\n'
     '    if st == "failed":\n        return "the index build failed: " + BUILD_STATE["reason"]\n'),
    ('        _log("building the station index in the background")\n'
     '        rebuild(False)\n'
     '    threading.Thread(target=worker, daemon=True).start()\n',
     '        # v22: an offline start used to try once and never again. Now it keeps\n'
     '        # trying, 30 s then 1, 2, 5 minutes and every 5 minutes after, until the\n'
     '        # day is built, and /status says it is waiting rather than idle.\n'
     '        delay = int(os.environ.get("ALLC_RETRY_FIRST", "30"))   # a test sets it small\n'
     '        while True:\n'
     '            _log("building the station index in the background")\n'
     '            r = rebuild(False)\n'
     '            if r.get("ok"):\n'
     '                BUILD_STATE.update(state="idle", reason="")\n'
     '                return\n'
     '            if "already running" not in (r.get("reason") or ""):\n'
     '                BUILD_STATE.update(state="waiting_for_network", reason=(r.get("reason") or "")[:120])\n'
     '            time.sleep(delay)\n'
     '            delay = min(delay * 2, 300)\n'
     '    threading.Thread(target=worker, daemon=True).start()\n'),

    # F1: labels stay in the free area between what is drawn over the map
    ('  const sz = !usingGoogle() && map ? map.getSize() : null;\n',
     '  const sz = !usingGoogle() && map ? map.getSize() : null;\n'
     '  // What is drawn over the map, measured now and not guessed: the status line,\n'
     '  // the buttons and the GPS chip on top; the watch bar at the bottom.\n'
     '  const lim = { top: 8, bottom: sz ? sz.y - 4 : 0 };\n'
     '  if (sz) {\n'
     '    const mr = map.getContainer().getBoundingClientRect();\n'
     '    ["hud", "tools", "gpsChip"].forEach(id => {\n'
     '      const e = document.getElementById(id); if (!e) return;\n'
     '      const r = e.getBoundingClientRect();\n'
     '      if (r.width > 0 && r.height > 0) lim.top = Math.max(lim.top, r.bottom - mr.top + 6);\n'
     '    });\n'
     '    const wb = document.getElementById("watchbar");\n'
     '    if (wb && getComputedStyle(wb).display !== "none") {\n'
     '      const r = wb.getBoundingClientRect();\n'
     '      if (r.height > 0) lim.bottom = Math.min(lim.bottom, r.top - mr.top - 6);\n'
     '    }\n'
     '  }\n'),
    ('      const ny = Math.min(Math.max(o.p.y + o.dy, o.h / 2 + 64), sz.y - o.h / 2 - 4) - o.p.y;\n',
     '      const lo = lim.top + o.h / 2, hi = lim.bottom - o.h / 2;\n'
     '      const ny = (hi > lo ? Math.min(Math.max(o.p.y + o.dy, lo), hi) : o.p.y + o.dy) - o.p.y;\n'),

    # The clamp is in screen pixels, so it goes stale the moment the map is panned
    # (a station dragged up under the GPS chip kept its old, clear, position).
    ('  map.on("zoomend", layoutPins);\n', '  map.on("zoomend", layoutPins);\n  map.on("moveend", layoutPins);\n'),

    # A watch that is already running delivers nothing until the phone moves, so
    # pressing locate while one was running never got a fresh position. Restart it.
    ('  hud("Hold still — collecting satellites for 30 seconds…", true);\n  startBurst(30000);\n',
     '  stopBurst();       // a running watch says nothing until the phone moves; a new one answers at once\n'
     '  hud("Hold still — collecting satellites for 30 seconds…", true);\n  startBurst(30000);\n'),

    # Leaflet ignores a setView that arrives while a zoom animation is still running,
    # and the locate button's own first jump starts one, so the follow-up to the new
    # fix was swallowed and the map stayed at the old position. The map jumps.
    ('  else map.setView([v.lat, v.lng], z);\n', '  else map.setView([v.lat, v.lng], z, { animate: false });\n'),

    # F8: the locate button waits for the new burst's first fix as well
    ('  WANT_CENTRE = true;          // the button, and only the button, brings the map to you\n'
     '  if (ME) { setView(ME, Math.max(17, curZoom())); WANT_CENTRE = false; }\n',
     '  // The button, and only the button, brings the map to you: now to the last\n'
     '  // position, and again to the first fix of the new burst, which is where you\n'
     '  // are. The flag lapses after the burst so a later automatic fix cannot use it.\n'
     '  WANT_CENTRE = true;\n'
     '  if (ME) setView(ME, Math.max(17, curZoom()));\n'
     '  clearTimeout(window.__wantT); window.__wantT = setTimeout(() => { WANT_CENTRE = false; }, 35000);\n'),

    # F14: the status line under the buttons, the 360 view over the attribution
    ('  #hud{position:absolute;top:calc(12px + env(safe-area-inset-top));left:14px;right:206px;\n',
     '  #hud{position:absolute;top:calc(58px + env(safe-area-inset-top));left:14px;right:14px;\n'),
    ('    top:calc(64px + env(safe-area-inset-top));display:flex;align-items:center;gap:7px;\n',
     '    top:calc(104px + env(safe-area-inset-top));display:flex;align-items:center;gap:7px;\n'),
    ('  .leaflet-control-attribution{font-size:9px;',
     '  body.panoopen .leaflet-control-attribution{display:none;}\n  .leaflet-control-attribution{font-size:9px;'),
    ('  box.classList.add("show");\n  if (!API_KEY) {\n',
     '  box.classList.add("show");\n  document.body.classList.add("panoopen");\n  if (!API_KEY) {\n'),
    ('function closePano(){\n  document.getElementById("pano").classList.remove("show");\n',
     'function closePano(){\n  document.getElementById("pano").classList.remove("show");\n  document.body.classList.remove("panoopen");\n'),
]

# ------------------------------------------------------------- day.commute
DAY_FIXES = [
    (_OLD_GUARD, _new_guard(("/update-bus", "/pdf-delete", "/pdf-sched"))),
]

# ----------------------------------------------------------- night.commute
NIGHT_FIXES = [
    (_OLD_GUARD, _new_guard(("/night-rebuild", "/pdf-delete", "/pdf-sched"))),
]


def _apply(src, fixes, who):
    for old, new in fixes:
        if src.count(old) != 1:
            raise SystemExit("payload_v22: %s, this anchor matches %d times, not once:\n    %s"
                             % (who, src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)
    if _REFUSE_OLD in src:
        src = src.replace(_REFUSE_OLD, _REFUSE_NEW)
    return src


def patch_all(src):
    return _apply(src, ALL_FIXES, "all")


def patch_day(src):
    return _apply(src, DAY_FIXES, "day")


def patch_night(src):
    return _apply(src, NIGHT_FIXES, "night")
