"""payload_v17.py, what v17 does to the three payloads on their way out.

Imported by patch_payload.py. Same contract as everything in FIXES: each
entry is an anchor and its replacement, and the anchor must appear exactly
once or the build stops. A change that lands twice, or not at all, is worse
than one that refuses.

FOUR THINGS, and why each one is here

1. THE WIFI ADDRESS, AT THE TOP OF SETTINGS. The apps bind wide on purpose
   (termux-app.md section 7), so a laptop on the same wifi can open them.
   Nothing on screen said where. Each page now says it, in one line, from a
   /lan-ip route that asks the server for the address it would really be
   reached on.

2. NIGHT BINDS WIDE LIKE THE OTHER TWO. It bound 127.0.0.1 only, so the line
   above would have been a lie for it. Binding wide is only safe because of 3.

3. CREDENTIALS AND SPEND ANSWER THE PHONE ONLY. termux-app.md section 7 says an
   app that holds keys does not hand them to a room full of strangers, and
   all.commute was doing exactly that: GET /api-keys returned the keys, and
   GET /gps returned where the phone is, to anybody on the wifi. The page, the
   timetable and the map stay open to the room. Keys, the paid Gemini reads,
   deleting caches and rebuilding stay on the phone. Two checks, because
   they catch different things: the peer address (a device on the wifi) and
   the Host header (a web page in another tab rebinding a name to 127.0.0.1,
   which binding to loopback does not stop).

4. NO BLUR, EVER. all.commute carried seven backdrop-filter:blur(). Marko's
   rule, restated 3.10.2026: never blur the background, in any app. The
   translucent colour stays; only the blur goes. The count is checked, so an
   upstream change that adds an eighth fails the build rather than ships.

NIGHT ALSO STOPS DELETING WHAT THE PERSON OWNS. See NIGHT_KEEP below.
"""

CSS_IPLINE = (
    "  .ipline { font-size:.74rem; color:var(--cyan); background:var(--card); border:1px solid var(--border);\n"
    "    border-radius:9px; padding:7px 10px; margin:0 0 10px; font-variant-numeric:tabular-nums; word-break:break-all; }\n"
)


def _js_ip(port, page, indent="  "):
    return (
        indent + 'fetch("lan-ip", { cache: "no-store" }).then(r => r.json()).then(d => { const el = document.getElementById("ipLine");\n'
        + indent + '  if (el) el.textContent = (d && d.ip) ? "on Wi-Fi:  http://" + d.ip + ":" + (location.port || "%s") + "/%s"\n'
        + indent + '    : "on this phone only (no Wi-Fi address)"; }).catch(() => {});\n'
    ) % (port, page)


def _guard_method(paths):
    """The method that goes into each handler class, ahead of do_GET."""
    tup = ", ".join('"%s"' % p for p in paths)
    return (
        "    # Credentials, spend and housekeeping answer the phone and nobody else\n"
        "    # on the wifi. The page and the timetable stay open to the room.\n"
        "    _PHONE_ONLY = (%s)\n"
        "    def _phone_only(self, path):\n"
        "        if path not in self._PHONE_ONLY:\n"
        "            return False\n"
        "        peer = self.client_address[0]\n"
        "        host = (self.headers.get(\"Host\") or \"\").rsplit(\":\", 1)[0].strip(\"[]\").lower()\n"
        "        return not (peer in (\"127.0.0.1\", \"::1\", \"::ffff:127.0.0.1\")\n"
        "                    and host in (\"127.0.0.1\", \"localhost\", \"::1\"))\n\n"
    ) % tup


REFUSE = '{"ok": False, "reason": "this answers on the phone only"}, 403'

# ---------------------------------------------------------------- day.commute
DAY_FIXES = [
    # the app says the number it is
    ('COMMUTE_VERSION="v13"', 'COMMUTE_VERSION="v14"'),
    ('APP_VERSION = "v13"', 'APP_VERSION = "v14"'),
    ('(v.version || "v13")', '(v.version || "v14")'),
    ('if (el) el.textContent = "v13 (a)"; });', 'if (el) el.textContent = "v14 (a)"; });'),

    # the guard: method first, then the two doors
    ('    def do_GET(self):\n        route = urllib.parse.urlparse(self.path).path\n        if route in ("/", "/index.html"):\n            route = "/bus.html"\n',
     _guard_method(("/update-bus", "/api-keys", "/gemini-key", "/key-status", "/pdf-sched", "/pdf-delete"))
     + '    def do_GET(self):\n        route = urllib.parse.urlparse(self.path).path\n        if route in ("/", "/index.html"):\n            route = "/bus.html"\n'
     '        if self._phone_only(route):\n            return self._json(' + REFUSE + ')\n'),
    ('    def do_POST(self):\n        route = urllib.parse.urlparse(self.path).path\n        if route == "/gemini-key":',
     '    def do_POST(self):\n        route = urllib.parse.urlparse(self.path).path\n'
     '        if self._phone_only(route):\n            return self._json(' + REFUSE + ')\n'
     '        if route == "/gemini-key":'),

    # the wifi address
    ('        if route == "/version":\n            return self._json({"version": APP_VERSION, "build": APP_BUILD})',
     '        if route == "/lan-ip":\n            return self._json({"ip": _lan_ip()})\n'
     '        if route == "/version":\n            return self._json({"version": APP_VERSION, "build": APP_BUILD})'),
    ('  .watchrow .wstop { margin-left:auto; color:var(--muted); font-weight:700; padding:0 4px; }\n</style>',
     '  .watchrow .wstop { margin-left:auto; color:var(--muted); font-weight:700; padding:0 4px; }\n' + CSS_IPLINE + '</style>'),
    ('      <button class="bm-close" id="setupClose">Close</button>\n    </div>\n',
     '      <button class="bm-close" id="setupClose">Close</button>\n    </div>\n    <div class="ipline" id="ipLine">on this phone only</div>\n'),
    ('  refreshKeyDots();\n  renderPdfManager();\n',
     '  refreshKeyDots();\n  renderPdfManager();\n' + _js_ip(8082, "bus.html")),
]

# ---------------------------------------------------------------- all.commute
ALL_FIXES = [
    ('APP_VERSION = "v40"\nAPP_BUILD = "b40"', 'APP_VERSION = "v41"\nAPP_BUILD = "b41"'),

    ('    def do_GET(self):\n        u = urllib.parse.urlparse(self.path)\n        q = urllib.parse.parse_qs(u.query)\n        route = u.path\n        if route in ("/", "/index.html"):\n            route = "/all.html"\n',
     _guard_method(("/api-keys", "/gemini-key", "/gemini-test", "/key-test", "/gemini-model", "/gemini-models",
                    "/gemini-models-old", "/rebuild", "/cache/clear", "/sched-delete", "/gps"))
     + '    def do_GET(self):\n        u = urllib.parse.urlparse(self.path)\n        q = urllib.parse.parse_qs(u.query)\n        route = u.path\n        if route in ("/", "/index.html"):\n            route = "/all.html"\n'
     '        if self._phone_only(route):\n            return self._json(' + REFUSE + ')\n'),
    ('        body = self.rfile.read(n).decode("utf-8", "replace")\n        if u.path == "/api-keys":',
     '        body = self.rfile.read(n).decode("utf-8", "replace")\n'
     '        if self._phone_only(u.path):\n            return self._json(' + REFUSE + ')\n'
     '        if u.path == "/api-keys":'),

    ('            if route == "/version":\n                return self._json({"version": APP_VERSION, "build": APP_BUILD})',
     '            if route == "/lan-ip":\n                return self._json({"ip": _lan_ip()})\n'
     '            if route == "/version":\n                return self._json({"version": APP_VERSION, "build": APP_BUILD})'),
    ('  #setup.show{display:block;}\n', '  #setup.show{display:block;}\n' + CSS_IPLINE),
    ('    <div class="sh"><b>all.commute</b><button class="btn ghost close" id="sClose">Done</button></div>\n',
     '    <div class="sh"><b>all.commute</b><button class="btn ghost close" id="sClose">Done</button></div>\n'
     '    <div class="ipline" id="ipLine">on this phone only</div>\n'),
    ('  renderLayers(); loadStatus(); updateAccBox();\n  loadGemStatus().then(() => { loadSched(); loadModelState(); });',
     _js_ip(8084, "all.html") + '  renderLayers(); loadStatus(); updateAccBox();\n  loadGemStatus().then(() => { loadSched(); loadModelState(); });'),
]

# Counted, not hoped for. Anchored replacements cannot express "all seven of these".
ALL_REGEX = [
    (r'backdrop-filter:\s*blur\([0-9.]+px\)\s*;?', '', 7),
]

# ---------------------------------------------------------------- night.commute
# What the install is allowed to keep when it clears its own folder. The wipe
# is still there, because a clean folder is what stops stale state. What it
# no longer takes is what the person owns (the Gemini key they pasted) and
# what costs a download to get again (the timetables read from PDF, and the
# fourteen megabyte ZET schedule). gmaps-api.txt is NOT kept: the umbrella's
# shared key store is where that key comes from, and it supplies it every
# install, so the store stays the one source.
NIGHT_KEEP = ("gemini-api.txt", "pdf", "zet_gtfs.zip", "zet_gtfs.zip.meta.json")

NIGHT_FIXES = [
    ('import os, json, time, base64, hashlib, threading, urllib.parse, urllib.request\n',
     'import os, json, time, base64, hashlib, threading, socket, urllib.parse, urllib.request\n'),
    ('            srv=Server(("127.0.0.1",port),H); break',
     '            srv=Server((os.environ.get("NIGHTCOMMUTE_HOST","0.0.0.0"),port),H); break'),
    ('_BUILD_LOCK = threading.Lock()\n',
     '_BUILD_LOCK = threading.Lock()\n\ndef _lan_ip():\n    try:\n        so=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); so.connect(("8.8.8.8",80))\n'
     '        ip=so.getsockname()[0]; so.close(); return ip\n    except Exception: return ""\n'),

    ('    def do_GET(self):\n        r=urllib.parse.urlparse(self.path).path\n        if r in ("/","/index.html"): r="/night.html"\n',
     _guard_method(("/gmaps-key", "/key-status", "/gemini-key", "/pdf-delete", "/pdf-sched", "/night-rebuild"))
     + '    def do_GET(self):\n        r=urllib.parse.urlparse(self.path).path\n        if r in ("/","/index.html"): r="/night.html"\n'
     '        if self._phone_only(r): return self._json(' + REFUSE + ')\n'),
    ('    def do_POST(self):\n        r=urllib.parse.urlparse(self.path).path\n        if r=="/gemini-key":',
     '    def do_POST(self):\n        r=urllib.parse.urlparse(self.path).path\n'
     '        if self._phone_only(r): return self._json(' + REFUSE + ')\n'
     '        if r=="/gemini-key":'),

    ('Build your own scheme on the <b>C</b> button (top bar).', 'Build your own scheme with the colour wheel.'),
    ('    <div class="sh-head"><h3>Setup</h3><button class="sh-close" id="setupClose">Close</button></div>\n',
     '    <div class="sh-head"><h3>Setup</h3><button class="sh-close" id="setupClose">Close</button></div>\n'
     '    <div class="ipline" id="ipLine">on this phone only</div>\n'),
    ('function openSetup(){ refreshDots(); renderPdfMgr(); renderViewGrid(); renderNightSched();\n',
     'function openSetup(){ refreshDots(); renderPdfMgr(); renderViewGrid(); renderNightSched();\n' + _js_ip(8087, "night.html")),

    # the folder: keep what is owned, clear the rest as before
    ('rm -rf "$HOME/.nightcommute" 2>/dev/null || true\n',
     '# v17: keep what the person owns and what costs a download to get again.\n'
     'KEEP_TMP="$(mktemp -d 2>/dev/null || echo "$HOME/.nightcommute.keep.$$")"; mkdir -p "$KEEP_TMP"\n'
     'for _k in ' + " ".join(NIGHT_KEEP) + '; do\n'
     '  [ -e "$HOME/.nightcommute/$_k" ] && cp -a "$HOME/.nightcommute/$_k" "$KEEP_TMP/" 2>/dev/null\n'
     'done\n'
     'rm -rf "$HOME/.nightcommute" 2>/dev/null || true\n'),
    ('mkdir -p "$APPDIR" 2>/dev/null || true\ndone_\n\nGEMINI_KEYFILE=',
     'mkdir -p "$APPDIR" 2>/dev/null || true\n'
     'cp -a "$KEEP_TMP"/. "$APPDIR"/ 2>/dev/null || true; rm -rf "$KEEP_TMP"\n'
     'done_\n\nGEMINI_KEYFILE='),
]
# The ipline css rides on the </style> that night's live feed already extends.
NIGHT_CSS = CSS_IPLINE
