"""payload_v29: fresh downloads by default and an optional shared cache.

The default is fresh data: every app process forces one GTFS download and
rebuild when it starts. A single switch in each app's Settings persists the
same value under ~/.maha.commute/settings.json and restores the old reuse of
today's stored schedule.
"""

SETTINGS_ANCHOR = '_MAHA_KEYDIR = os.path.expanduser("~/.maha.commute/keys")\n'

SETTINGS_HELPER = SETTINGS_ANCHOR + '''
_MAHA_SETTINGS = os.path.expanduser("~/.maha.commute/settings.json")


def _maha_cache_enabled():
    try:
        with open(_MAHA_SETTINGS, encoding="utf-8") as f:
            data = json.load(f)
        return isinstance(data, dict) and data.get("cache_enabled") is True
    except (OSError, ValueError, TypeError):
        return False


def _maha_set_cache_enabled(enabled):
    data = {}
    try:
        with open(_MAHA_SETTINGS, encoding="utf-8") as f:
            saved = json.load(f)
        if isinstance(saved, dict):
            data = saved
    except (OSError, ValueError, TypeError):
        pass
    data["cache_enabled"] = bool(enabled)
    os.makedirs(os.path.dirname(_MAHA_SETTINGS), exist_ok=True)
    try:
        os.chmod(os.path.dirname(_MAHA_SETTINGS), 0o700)
    except OSError:
        pass
    tmp = _MAHA_SETTINGS + ".new"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, sort_keys=True)
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.replace(tmp, _MAHA_SETTINGS)
    return {"ok": True, "enabled": bool(enabled)}


'''

CACHE_GET_DAY = '''        if route == "/cache-mode":
            return self._json({"ok": True, "enabled": _maha_cache_enabled()})
        '''

CACHE_GET_NIGHT = '''        if r=="/cache-mode":
            return self._json({"ok": True, "enabled": _maha_cache_enabled()})
        '''

CACHE_GET_ALL = '''            if route == "/cache-mode":
                return self._json({"ok": True, "enabled": _maha_cache_enabled()})
            '''

CACHE_POST_DAY = '''        if route == "/cache-mode":
            try:
                ln = int(self.headers.get("Content-Length") or 0)
                body = self.rfile.read(ln).decode("utf-8", "replace") if ln else ""
                value = json.loads(body)
                if not isinstance(value, dict) or not isinstance(value.get("enabled"), bool):
                    return self._json({"ok": False, "reason": "enabled must be true or false"}, 400)
                return self._json(_maha_set_cache_enabled(value["enabled"]))
            except (OSError, ValueError, TypeError) as e:
                return self._json({"ok": False, "reason": repr(e)}, 400)
        '''

CACHE_POST_NIGHT = '''        if r=="/cache-mode":
            try:
                ln=int(self.headers.get("Content-Length") or 0)
                body=self.rfile.read(ln).decode("utf-8","replace") if ln else ""
                value=json.loads(body)
                if not isinstance(value,dict) or not isinstance(value.get("enabled"),bool):
                    return self._json({"ok":False,"reason":"enabled must be true or false"},400)
                return self._json(_maha_set_cache_enabled(value["enabled"]))
            except (OSError,ValueError,TypeError) as e:
                return self._json({"ok":False,"reason":repr(e)},400)
        '''

CACHE_POST_ALL = '''        if u.path == "/cache-mode":
            try:
                value = json.loads(body or "{}")
                if not isinstance(value, dict) or not isinstance(value.get("enabled"), bool):
                    return self._json({"ok": False, "reason": "enabled must be true or false"}, 400)
                return self._json(_maha_set_cache_enabled(value["enabled"]))
            except (OSError, ValueError, TypeError) as e:
                return self._json({"ok": False, "reason": repr(e)}, 400)
        '''

CACHE_CARD_DAY = '''
    <div class="zet-card">
      <div class="zet-h">Fresh data</div>
      <label class="zet-note" style="display:flex;gap:9px;align-items:center">
        <input type="checkbox" id="mahaCacheEnabled">
        Use stored schedule data
      </label>
      <span class="zet-note">Off by default. At every app start, all three apps
        download the schedule once again and rebuild from it. Turn this on only
        when you want to reuse today's stored download.</span>
      <div class="setup-msg" id="mahaCacheMsg"></div>
    </div>
'''

CACHE_CARD_NIGHT = '''
    <div class="card">
      <h4>Fresh data</h4>
      <label class="note" style="display:flex;gap:9px;align-items:center">
        <input type="checkbox" id="mahaCacheEnabled">
        Use stored schedule data
      </label>
      <span class="note">Off by default. At every app start, all three apps
        download the schedule once again and rebuild from it. Turn this on only
        when you want to reuse today's stored download.</span>
      <div class="msg" id="mahaCacheMsg"></div>
    </div>
'''

CACHE_CARD_ALL = '''
    <div class="box">
      <h3>Fresh data</h3>
      <label class="note" style="display:flex;gap:9px;align-items:center">
        <input type="checkbox" id="mahaCacheEnabled">
        Use stored schedule data
      </label>
      <span class="note">Off by default. At every app start, all three apps
        download the schedule once again and rebuild from it. Turn this on only
        when you want to reuse today's stored download.</span>
      <div class="msg" id="mahaCacheMsg"></div>
    </div>
'''

CACHE_JS = r'''
let MAHA_CACHE_ENABLED = false;
async function loadMahaCache(){
  const box = document.getElementById("mahaCacheEnabled");
  const msg = document.getElementById("mahaCacheMsg");
  try {
    const d = await fetch("cache-mode", { cache:"no-store" }).then(r => r.json());
    MAHA_CACHE_ENABLED = d.enabled === true;
    try { localStorage.setItem("maha_cache_enabled", MAHA_CACHE_ENABLED ? "1" : "0"); } catch (e) {}
    if (box) box.checked = MAHA_CACHE_ENABLED;
    if (msg) msg.textContent = MAHA_CACHE_ENABLED
      ? "Stored data is allowed until the next start."
      : "Fresh download is required at every start.";
  } catch (e) {
    try { MAHA_CACHE_ENABLED = localStorage.getItem("maha_cache_enabled") === "1"; }
    catch (ignored) { MAHA_CACHE_ENABLED = false; }
    if (box) box.checked = MAHA_CACHE_ENABLED;
    if (msg) msg.textContent = MAHA_CACHE_ENABLED
      ? "Stored data is allowed until the next start."
      : "Fresh download is required at every start.";
  }
  return MAHA_CACHE_ENABLED;
}
document.getElementById("mahaCacheEnabled").addEventListener("change", async (e) => {
  const enabled = e.target.checked;
  e.target.disabled = true;
  try {
    const d = await fetch("cache-mode", {
      method:"POST", headers:{"Content-Type":"application/json"},
      body:JSON.stringify({enabled})
    }).then(r => r.json());
    if (!d.ok) throw new Error(d.reason || "could not save");
    await loadMahaCache();
  } catch (err) {
    e.target.checked = !enabled;
    document.getElementById("mahaCacheMsg").textContent = "Could not save this setting.";
  } finally {
    e.target.disabled = false;
  }
});
'''


DAY_FIXES = [
    ('sed -i \'s/\\r$//\' "$BIN/day.commute"',
     'sed -i.bak \'s/\\r$//\' "$BIN/day.commute"\nrm -f "$BIN/day.commute.bak"'),
    (SETTINGS_ANCHOR, SETTINGS_HELPER),
    ('_PHONE_ONLY = ("/update-bus", "/api-keys", "/gemini-key", "/key-status", "/pdf-sched", "/pdf-delete")',
     '_PHONE_ONLY = ("/update-bus", "/api-keys", "/gemini-key", "/key-status", "/pdf-sched", "/pdf-delete", "/cache-mode")'),
    ('_STATE_CHANGING = ("/update-bus", "/pdf-delete", "/pdf-sched")',
     '_STATE_CHANGING = ("/update-bus", "/pdf-delete", "/pdf-sched", "/cache-mode")'),
    ('        if route == "/api-keys":\n            return self._json({"keys": read_keys()})',
     CACHE_GET_DAY + 'if route == "/api-keys":\n            return self._json({"keys": read_keys()})'),
    ('        if route == "/gemini-key":\n            try:\n',
     CACHE_POST_DAY + 'if route == "/gemini-key":\n            try:\n'),
    ('        start_update(False)\n',
     '        start_update(not _maha_cache_enabled())\n'),
    ('    if cached is not None:\n        log("network unavailable, using the local GTFS copy")',
     '    if cached is not None and not force:\n        log("network unavailable, using the local GTFS copy")'),
    ('    <div class="zet-card">\n      <div class="zet-h">Schedule <span class="zet-tag rule">the rule</span></div>',
     CACHE_CARD_DAY + '    <div class="zet-card">\n      <div class="zet-h">Schedule <span class="zet-tag rule">the rule</span></div>'),
    ('document.getElementById("setupClose").addEventListener("click",',
     CACHE_JS + 'loadMahaCache();\n' +
     'document.getElementById("setupClose").addEventListener("click",'),
]

NIGHT_FIXES = [
    ('sed -i \'s/\\r$//\' "$BIN/night.commute" 2>/dev/null || true',
     'sed -i.bak \'s/\\r$//\' "$BIN/night.commute" 2>/dev/null || true\nrm -f "$BIN/night.commute.bak"'),
    (SETTINGS_ANCHOR, SETTINGS_HELPER),
    ('_PHONE_ONLY = ("/gmaps-key", "/key-status", "/gemini-key", "/pdf-delete", "/pdf-sched", "/night-rebuild")',
     '_PHONE_ONLY = ("/gmaps-key", "/key-status", "/gemini-key", "/pdf-delete", "/pdf-sched", "/night-rebuild", "/cache-mode")'),
    ('_STATE_CHANGING = ("/night-rebuild", "/pdf-delete", "/pdf-sched")',
     '_STATE_CHANGING = ("/night-rebuild", "/pdf-delete", "/pdf-sched", "/cache-mode")'),
    ('        if r=="/version": return self._json({"version":APP_VERSION,"build":APP_BUILD})',
     '        if r=="/cache-mode":\n            return self._json({"ok": True, "enabled": _maha_cache_enabled()})\n'
     '        if r=="/version": return self._json({"version":APP_VERSION,"build":APP_BUILD})'),
    ('        if r=="/gemini-key":\n            try:\n',
     CACHE_POST_NIGHT + 'if r=="/gemini-key":\n            try:\n'),
    ('        if night_stale(): rebuild_night(force=False)',
     '        use_cache = _maha_cache_enabled()\n        if not use_cache or night_stale(): rebuild_night(force=not use_cache)'),
    ('    if cached is not None: return cached, False',
     '    if cached is not None and not force: return cached, False'),
    ('    <div class="card">\n      <h4>Live schedule <span style="color:var(--muted);font-size:.7rem">ZET GTFS</span></h4>',
     CACHE_CARD_NIGHT + '    <div class="card">\n      <h4>Live schedule <span style="color:var(--muted);font-size:.7rem">ZET GTFS</span></h4>'),
    ('document.getElementById("gearBtn").addEventListener("click",openSetup);',
     CACHE_JS + 'loadMahaCache();\n' +
     'document.getElementById("gearBtn").addEventListener("click",openSetup);'),
]

ALL_FIXES = [
    ('def get_gtfs(force=False):\n    meta = _load_meta()\n',
     'def get_gtfs(force=False):\n'
     '    local = os.environ.get("ALLC_GTFS_LOCAL")\n'
     '    if local:\n'
     '        if not os.path.isfile(local):\n'
     '            raise RuntimeError("local GTFS fixture is not here yet: " + local)\n'
     '        with open(local, "rb") as f:\n'
     '            return f.read()\n'
     '    meta = _load_meta()\n'),
    ('APP_VERSION = "v48"', 'APP_VERSION = "v52"'),
    ('APP_BUILD = "b47"', 'APP_BUILD = "b52"'),
    ('ALLC_UI_VERSION="v48"', 'ALLC_UI_VERSION="v52"'),
    ('<div class="kv"><span>Interface</span><b>stations · v48</b></div>',
     '<div class="kv"><span>Interface</span><b>stations · v52</b></div>'),
    ('sed -i \'s/\\r$//\' "$HOME/.shortcuts/all.commute"',
     'sed -i.bak \'s/\\r$//\' "$HOME/.shortcuts/all.commute"\nrm -f "$HOME/.shortcuts/all.commute.bak"'),
    (SETTINGS_ANCHOR, SETTINGS_HELPER),
    ('_STATE_CHANGING = ("/rebuild", "/cache/clear", "/sched-delete", "/track/save", "/track/delete")',
     '_STATE_CHANGING = ("/rebuild", "/cache/clear", "/sched-delete", "/track/save", "/track/delete", "/cache-mode")'),
    ('_PHONE_ONLY = ("/api-keys", "/gemini-key", "/gemini-test", "/key-test", "/gemini-model", "/gemini-models", "/gemini-models-old", "/rebuild", "/cache/clear", "/sched-delete", "/gps", "/tracks", "/track", "/track/save", "/track/delete")',
     '_PHONE_ONLY = ("/cache-mode", "/api-keys", "/gemini-key", "/gemini-test", "/key-test", "/gemini-model", "/gemini-models", "/gemini-models-old", "/rebuild", "/cache/clear", "/sched-delete", "/gps", "/tracks", "/track", "/track/save", "/track/delete")'),
    ('            if route == "/api-keys":\n                return self._json({"keys": read_keys()})',
     CACHE_GET_ALL + 'if route == "/api-keys":\n                return self._json({"keys": read_keys()})'),
    ('        if u.path == "/api-keys":\n',
     CACHE_POST_ALL + 'if u.path == "/api-keys":\n'),
    ('        ymd = datetime.date.today().strftime("%Y%m%d")\n        if index_ready():',
     '        ymd = datetime.date.today().strftime("%Y%m%d")\n        use_cache = _maha_cache_enabled()\n        if use_cache and index_ready():'),
    ('            r = rebuild(False)\n',
     '            r = rebuild(not use_cache)\n'),
    ('    if cached is not None:\n        log("network unavailable, using the local GTFS copy")',
     '    if cached is not None and not force:\n        log("network unavailable, using the local GTFS copy")'),
    ('    <div class="box">\n      <h3>Station cache</h3>',
     CACHE_CARD_ALL + '    <div class="box">\n      <h3>Station cache</h3>'),
    ('document.getElementById("btnSetup").addEventListener("click", () => {',
     CACHE_JS + 'document.getElementById("btnSetup").addEventListener("click", () => {'),
    ('  loadStationCache();\n  if (STATION_DB.length) loadStops();',
     '  await loadMahaCache();\n  if (MAHA_CACHE_ENABLED) loadStationCache();\n  if (STATION_DB.length) loadStops();'),
    ('    try { localStorage.setItem(CITIES[city].key, JSON.stringify({ rev: d.rev, stops: d.stops })); } catch (e) {}',
     '    if (MAHA_CACHE_ENABLED) {\n'
     '      try { localStorage.setItem(CITIES[city].key, JSON.stringify({ rev: d.rev, stops: d.stops })); } catch (e) {}\n'
     '    }'),
]


def _apply(src, fixes, who):
    for old, new in fixes:
        if src.count(old) != 1:
            raise SystemExit("payload_v29: %s, this anchor matches %d times, not once:\n    %s"
                             % (who, src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)
    return src


def patch_day(src):
    return _apply(src, DAY_FIXES, "day")


def patch_night(src):
    return _apply(src, NIGHT_FIXES, "night")


def patch_all(src):
    return _apply(src, ALL_FIXES, "all")
