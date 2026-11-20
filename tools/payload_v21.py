"""payload_v21.py, what v21 does to the payloads. Imported by patch_payload.py.

ONE GTFS FOR THE WHOLE FAMILY. Marko, 7.10.2026: "Add central GTFS system so
all apps share the same folder and same data of GTFS."

Each app downloaded https://www.zet.hr/gtfs-scheduled/latest into its own
folder with its own copy of nearly the same function. Now each app's download
function is renamed _own_..., and a new one with the old name asks the shared
library first (~/.maha.commute/gtfs/gtfs.py, src/45_gtfs.py). Only if the
umbrella is not installed, or the shared library fails, does the app fall back
to its own download, unchanged. After a shared fetch the app's own copy is
deleted, so the phone holds one schedule, not three.

The callers are untouched: day and night still get (bytes, changed), all still
gets bytes. "changed" is measured per app by the library, so day rebuilds its
schedule even when all.commute was the one that fetched the new file.
"""

CENTRAL = '''
def _maha_gtfs():
    """MAHA COMMUTE v21: the one GTFS the family shares, if the umbrella is here."""
    try:
        import importlib.util
        p = os.path.join(os.path.expanduser("~"), ".maha.commute", "gtfs", "gtfs.py")
        if not os.path.isfile(p):
            return None
        spec = importlib.util.spec_from_file_location("maha_gtfs", p)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception:
        return None


def _maha_drop_own(paths):
    """The shared copy is the copy: an app's own old zip is only disk."""
    for p in paths:
        try:
            if os.path.isfile(p):
                os.remove(p)
        except OSError:
            pass

'''


def wrapper(name, who, returns_tuple, logfn, paths):
    ret = "data, changed" if returns_tuple else "data"
    return (CENTRAL +
            'def %s(force=False):\n'
            '    g = _maha_gtfs()\n'
            '    if g is not None:\n'
            '        try:\n'
            '            data, changed = g.fetch(force=force, who="%s", log=%s)\n'
            '            _maha_drop_own([%s])\n'
            '            return %s\n'
            '        except Exception as e:\n'
            '            %s("  the shared GTFS did not answer (%%r), fetching our own" %% (e,))\n'
            '    return _own%s(force)\n\n\n'
            % (name, who, logfn, ", ".join(paths), ret, logfn, name if name.startswith("_") else "_" + name))


def _own(name):
    return "_own" + (name if name.startswith("_") else "_" + name)


# ------------------------------------------------------------- day.commute
DAY_FIXES = [
    ('COMMUTE_VERSION="v17"', 'COMMUTE_VERSION="v18"'),
    ('APP_VERSION = "v17"', 'APP_VERSION = "v18"'),
    ('(v.version || "v17")', '(v.version || "v18")'),
    ('if (el) el.textContent = "v17 (a)"; });', 'if (el) el.textContent = "v18 (a)"; });'),
    ('def get_gtfs(force=False):\n    """Return (zip_bytes, changed). Asks the ZET server whether the zip',
     wrapper("get_gtfs", "day", True, "log", ["CACHE_ZIP", "META_PATH"]) +
     'def %s(force=False):\n    """Return (zip_bytes, changed). Asks the ZET server whether the zip' % _own("get_gtfs")),
]

# ------------------------------------------------------------- night.commute
NIGHT_FIXES = [
    ('NIGHT_VERSION="v13 (a)"', 'NIGHT_VERSION="v14 (a)"'),
    ('APP_VERSION = "v13"\nAPP_BUILD = "n13-a"', 'APP_VERSION = "v14"\nAPP_BUILD = "n14-a"'),
    ('installed  night.commute v13 (a)', 'installed  night.commute v14 (a)'),
    ('(v.version||"v13")', '(v.version||"v14")'),
    ('textContent="v13 (a)"; });', 'textContent="v14 (a)"; });'),
    ('def _get_gtfs(force=False):\n    meta = {}',
     wrapper("_get_gtfs", "night", True, "_log", ["CACHE_ZIP", "GTFS_META"]) +
     'def %s(force=False):\n    meta = {}' % _own("_get_gtfs")),
]

# ------------------------------------------------------------- all.commute
ALL_FIXES = [
    ('APP_VERSION = "v43"\nAPP_BUILD = "b43"', 'APP_VERSION = "v44"\nAPP_BUILD = "b44"'),
    ('<div class="kv"><span>Interface</span><b>stations · v43</b></div>',
     '<div class="kv"><span>Interface</span><b>stations · v44</b></div>'),
    ('def get_gtfs(force=False):\n    meta = _load_meta()\n    cached = None\n    if os.path.isfile(CACHE_ZIP):\n'
     '        try:\n            with open(CACHE_ZIP, "rb") as f:\n                cached = f.read()\n'
     '        except Exception:\n            cached = None\n    headers = {"User-Agent": "Mozilla/5.0 (Android; all-commute)"}',
     wrapper("get_gtfs", "all", False, "log", ["CACHE_ZIP", "META_PATH"]) +
     'def %s(force=False):\n    meta = _load_meta()\n    cached = None\n    if os.path.isfile(CACHE_ZIP):\n'
     '        try:\n            with open(CACHE_ZIP, "rb") as f:\n                cached = f.read()\n'
     '        except Exception:\n            cached = None\n    headers = {"User-Agent": "Mozilla/5.0 (Android; all-commute)"}' % _own("get_gtfs")),
]
