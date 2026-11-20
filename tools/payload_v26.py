"""payload_v26.py, what v26 does to the payloads. Called from patch_payload.py
after the other version modules (the anchors here are their output).

ONE COMMON DATABASE OF API KEYS, SHARED BY ALL THREE APPS. Marko, 17.10.2026:
"make a common database of all APIs so it's shared between applications. It can
be picked through any application, but it's loaded in the common one. If already
exists, of course it's ignored."

WHAT WAS TRUE BEFORE. The umbrella already kept ONE shared file,
~/.maha.commute/keys/google-api.txt, and only all.commute ever read it (its
Maps key, since v22). Every app kept its own keys in its own folder, the Gemini
key was never shared, and a key pasted in one app stayed in that app.

WHAT V26 DOES. ~/.maha.commute/keys/ becomes the common database of BOTH keys:
google-api.txt (Maps/Street View) and gemini-api.txt (the PDF/notice reader).

  * Every app READS it as a fallback, for both keys. A key set anywhere is used
    everywhere. (all.commute already did this for Maps; now day and night do
    too, and all three do it for Gemini.) Local key first, the shared one next,
    so an app that was given its own key by hand still uses it.

  * Every app's pick SEEDS the common database when it has no key for that API
    yet, and LEAVES IT ALONE when it already has one -- "if already exists, it
    is ignored", the shared key wins, and a later pick in another app does not
    overwrite it. The app still writes its own local file, so the pick takes
    effect for that app at once; the shared store is only seeded, never
    clobbered. To REPLACE a shared key you use the launcher's key screen, which
    forces it (src/20_menu.sh).

  The helper is injected once into each server. It never prints a key, writes
  the store 600 and the directory 700, and writes through a temp file so a key
  is never half-written. A line shorter than twenty characters is not a key (an
  empty file or a lone newline is none), the same floor all.commute's _keys_from
  uses.

As ever, the sources in src/payloads stay byte for byte what was handed over;
everything here is spliced at build time against anchors that must match once.
"""

# The common key database, injected once into each app's server. os is imported
# at the top of all three servers before this lands.
_HELPER = '''# v26: the common API-key database, shared by all three apps.
#
# ~/.maha.commute/keys/{google,gemini}-api.txt is one store that day, night and
# all.commute all read. A key picked in ANY app is loaded here when this store
# has none for that API; if one already exists it is left alone, so the shared
# key wins and a later pick in another app does not overwrite it. To replace a
# shared key you use the launcher's key screen, which forces it. Reads fall back
# to this store, so one key set anywhere is used everywhere. A key is never
# printed and never leaves the phone.
_MAHA_KEYDIR = os.path.expanduser("~/.maha.commute/keys")


def _maha_shared_read(api):
    try:
        with open(os.path.join(_MAHA_KEYDIR, api + "-api.txt"), encoding="utf-8") as f:
            return [ln.strip() for ln in f if ln.strip()]
    except OSError:
        return []


def _maha_shared_seed(api, keys):
    # Loaded into the common store only when it is empty for this API: if a key
    # is already there it is ignored, never overwritten. A sub-twenty-character
    # line is not a key.
    keys = [s for s in (str(k).strip() for k in (keys or [])) if len(s) >= 20]
    if not keys or _maha_shared_read(api):
        return
    try:
        os.makedirs(_MAHA_KEYDIR, exist_ok=True)
        try:
            os.chmod(_MAHA_KEYDIR, 0o700)
        except OSError:
            pass
        dst = os.path.join(_MAHA_KEYDIR, api + "-api.txt")
        tmp = dst + ".new"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\\n".join(keys) + "\\n")
        try:
            os.chmod(tmp, 0o600)
        except OSError:
            pass
        os.replace(tmp, dst)
    except OSError:
        pass


'''

# ------------------------------------------------------------- day.commute
DAY_FIXES = [
    ('COMMUTE_VERSION="v18"', 'COMMUTE_VERSION="v19"'),
    ('APP_VERSION = "v18"', 'APP_VERSION = "v19"'),
    ('(v.version || "v18")', '(v.version || "v19")'),
    ('if (el) el.textContent = "v18 (a)"; });', 'if (el) el.textContent = "v19 (a)"; });'),

    # Maps read: local file, then the shared database. The helper rides in here.
    ('def read_keys():\n'
     '    try:\n'
     '        with open(KEYFILE, encoding="utf-8") as f:\n'
     '            return [ln.strip() for ln in f if ln.strip()]\n'
     '    except OSError:\n'
     '        return []',
     _HELPER +
     'def read_keys():\n'
     '    try:\n'
     '        with open(KEYFILE, encoding="utf-8") as f:\n'
     '            local = [ln.strip() for ln in f if ln.strip()]\n'
     '    except OSError:\n'
     '        local = []\n'
     '    return local or _maha_shared_read("google")'),

    # Gemini read: this app's own file, then the shared database, then the google
    # key as the old last resort (day stored one key for both).
    ('def read_gemini_keys():\n'
     '    keys = []\n'
     '    for path in (GEMINI_KEYFILE, KEYFILE):\n'
     '        try:\n'
     '            with open(path, encoding="utf-8") as f:\n'
     '                keys += [ln.strip() for ln in f if ln.strip()]\n'
     '        except OSError:\n'
     '            pass\n'
     '    return keys',
     'def read_gemini_keys():\n'
     '    def _lines(p):\n'
     '        try:\n'
     '            with open(p, encoding="utf-8") as f:\n'
     '                return [ln.strip() for ln in f if ln.strip()]\n'
     '        except OSError:\n'
     '            return []\n'
     '    return _lines(GEMINI_KEYFILE) or _maha_shared_read("gemini") or _lines(KEYFILE)'),

    # Maps write: the local file as before, then seed the shared store.
    ('def write_keys(keys):\n'
     '    os.makedirs(APPDIR, exist_ok=True)\n'
     '    with open(KEYFILE, "w", encoding="utf-8") as f:\n'
     '        f.write("\\n".join(keys) + ("\\n" if keys else ""))',
     'def write_keys(keys):\n'
     '    os.makedirs(APPDIR, exist_ok=True)\n'
     '    with open(KEYFILE, "w", encoding="utf-8") as f:\n'
     '        f.write("\\n".join(keys) + ("\\n" if keys else ""))\n'
     '    _maha_shared_seed("google", keys)'),

    # Gemini write: local file, then seed the shared store.
    ('def write_gemini_keys(keys):\n'
     '    os.makedirs(APPDIR, exist_ok=True)\n'
     '    with open(GEMINI_KEYFILE, "w", encoding="utf-8") as f:\n'
     '        f.write("\\n".join(keys) + ("\\n" if keys else ""))',
     'def write_gemini_keys(keys):\n'
     '    os.makedirs(APPDIR, exist_ok=True)\n'
     '    with open(GEMINI_KEYFILE, "w", encoding="utf-8") as f:\n'
     '        f.write("\\n".join(keys) + ("\\n" if keys else ""))\n'
     '    _maha_shared_seed("gemini", keys)'),
]

# ----------------------------------------------------------- night.commute
NIGHT_FIXES = [
    ('NIGHT_VERSION="v15 (a)"', 'NIGHT_VERSION="v16 (a)"'),
    ('APP_VERSION = "v15"', 'APP_VERSION = "v16"'),
    ('APP_BUILD = "n15-a"', 'APP_BUILD = "n16-a"'),
    ('(v.version||"v15")', '(v.version||"v16")'),
    ('textContent="v15 (a)"; });', 'textContent="v16 (a)"; });'),
    ('installed  night.commute v15 (a)', 'installed  night.commute v16 (a)'),

    # Gemini read + the helper.
    ('def read_gemini_keys():\n'
     '    try:\n'
     '        with open(GEMINI_KEYFILE, encoding="utf-8") as f:\n'
     '            return [x.strip() for x in f if x.strip()]\n'
     '    except OSError:\n'
     '        return []',
     _HELPER +
     'def read_gemini_keys():\n'
     '    try:\n'
     '        with open(GEMINI_KEYFILE, encoding="utf-8") as f:\n'
     '            keys=[x.strip() for x in f if x.strip()]\n'
     '    except OSError:\n'
     '        keys=[]\n'
     '    return keys or _maha_shared_read("gemini")'),

    # Maps read (single key): local file, then the shared database.
    ('def read_gmaps_key():\n'
     '    try:\n'
     '        with open(GMAPS_KEYFILE, encoding="utf-8") as f:\n'
     '            for ln in f:\n'
     '                ln=ln.strip()\n'
     '                if ln: return ln\n'
     '    except OSError:\n'
     '        pass\n'
     '    return ""',
     'def read_gmaps_key():\n'
     '    try:\n'
     '        with open(GMAPS_KEYFILE, encoding="utf-8") as f:\n'
     '            for ln in f:\n'
     '                ln=ln.strip()\n'
     '                if ln: return ln\n'
     '    except OSError:\n'
     '        pass\n'
     '    sh=_maha_shared_read("google")\n'
     '    return sh[0] if sh else ""'),

    # Maps write: local file, then seed the shared store.
    ('def write_gmaps_key(key):\n'
     '    os.makedirs(APPDIR, exist_ok=True)\n'
     '    with open(GMAPS_KEYFILE, "w", encoding="utf-8") as f:\n'
     '        f.write((key or "").strip() + "\\n")',
     'def write_gmaps_key(key):\n'
     '    os.makedirs(APPDIR, exist_ok=True)\n'
     '    with open(GMAPS_KEYFILE, "w", encoding="utf-8") as f:\n'
     '        f.write((key or "").strip() + "\\n")\n'
     '    _maha_shared_seed("google", [(key or "").strip()])'),

    # Gemini write: local file, then seed the shared store.
    ('def write_gemini_keys(keys):\n'
     '    os.makedirs(APPDIR, exist_ok=True)\n'
     '    with open(GEMINI_KEYFILE, "w", encoding="utf-8") as f:\n'
     '        f.write("\\n".join(keys) + ("\\n" if keys else ""))',
     'def write_gemini_keys(keys):\n'
     '    os.makedirs(APPDIR, exist_ok=True)\n'
     '    with open(GEMINI_KEYFILE, "w", encoding="utf-8") as f:\n'
     '        f.write("\\n".join(keys) + ("\\n" if keys else ""))\n'
     '    _maha_shared_seed("gemini", keys)'),
]

# ------------------------------------------------------------- all.commute
# all.commute's read_keys already reads the shared store (v22), so Maps reads
# need nothing. Here: seed the shared store on write, and give Gemini the same
# shared fallback the Maps key has.
ALL_FIXES = [
    ('ALLC_UI_VERSION="v47"', 'ALLC_UI_VERSION="v48"'),
    ('APP_VERSION = "v47"', 'APP_VERSION = "v48"'),
    ('<div class="kv"><span>Interface</span><b>stations · v47</b></div>',
     '<div class="kv"><span>Interface</span><b>stations · v48</b></div>'),

    # Maps write: local file as before, then seed the shared store. The helper
    # rides in here (read_keys above already uses the v22 SHARED_KEYFILE path).
    ('def write_keys(keys):\n'
     '    os.makedirs(APPDIR, exist_ok=True)\n'
     '    with open(KEYFILE, "w", encoding="utf-8") as f:\n'
     '        f.write("\\n".join(keys) + ("\\n" if keys else ""))',
     _HELPER +
     'def write_keys(keys):\n'
     '    os.makedirs(APPDIR, exist_ok=True)\n'
     '    with open(KEYFILE, "w", encoding="utf-8") as f:\n'
     '        f.write("\\n".join(keys) + ("\\n" if keys else ""))\n'
     '    _maha_shared_seed("google", keys)'),

    # Gemini read (single key): local file, then the shared database's first key.
    ('def read_gemini_key():\n'
     '    try:\n'
     '        with open(GEMINI_KEYFILE, encoding="utf-8") as f:\n'
     '            return f.read().strip()\n'
     '    except OSError:\n'
     '        return ""',
     'def read_gemini_key():\n'
     '    try:\n'
     '        with open(GEMINI_KEYFILE, encoding="utf-8") as f:\n'
     '            local = f.read().strip()\n'
     '    except OSError:\n'
     '        local = ""\n'
     '    if local:\n'
     '        return local\n'
     '    sh = _maha_shared_read("gemini")\n'
     '    return sh[0] if sh else ""'),

    # Gemini write: local file, then seed the shared store.
    ('def write_gemini_key(k):\n'
     '    os.makedirs(APPDIR, exist_ok=True)\n'
     '    with open(GEMINI_KEYFILE, "w", encoding="utf-8") as f:\n'
     '        f.write((k or "").strip() + "\\n")',
     'def write_gemini_key(k):\n'
     '    os.makedirs(APPDIR, exist_ok=True)\n'
     '    with open(GEMINI_KEYFILE, "w", encoding="utf-8") as f:\n'
     '        f.write((k or "").strip() + "\\n")\n'
     '    _maha_shared_seed("gemini", [(k or "").strip()])'),
]


def _apply(src, fixes, who):
    for old, new in fixes:
        if src.count(old) != 1:
            raise SystemExit("payload_v26: %s, this anchor matches %d times, not once:\n    %s"
                             % (who, src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)
    return src


def patch_day(src):
    return _apply(src, DAY_FIXES, "day")


def patch_night(src):
    return _apply(src, NIGHT_FIXES, "night")


def patch_all(src):
    return _apply(src, ALL_FIXES, "all")
