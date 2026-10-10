"""payload_v25.py, what v25 does to the payloads. Called from patch_payload.py
after v24's patch_all.

ALL.COMMUTE: A LOCATION ERROR IS NOT A FIX. Found on Marko's phone, 10.10.2026, by
the phone session: when Android has no position to give, termux-location prints
{"API_ERROR": "Failed to get location"} and exits 0. termux_fix parsed that as
good JSON, copied no coordinates, and answered {"ok": true, "provider": "gps"}: a
failure reported as a success with its reason thrown away, so the position in the
page froze while every status said it was fine.

Now a reading counts only if it carries a latitude and a longitude; API_ERROR, or
any answer without both, is ok false with the reason Android gave.
"""

ALL_FIXES = [
    ('APP_VERSION = "v47"\nAPP_BUILD = "b47"', 'APP_VERSION = "v48"\nAPP_BUILD = "b48"'),
    ('<div class="kv"><span>Interface</span><b>stations · v47</b></div>',
     '<div class="kv"><span>Interface</span><b>stations · v48</b></div>'),
    ('ALLC_UI_VERSION="v47"', 'ALLC_UI_VERSION="v48"'),
    ('    out = {"ok": True, "provider": d.get("provider", provider)}\n',
     '    if not isinstance(d, dict) or d.get("API_ERROR") or \\\n'
     '            d.get("latitude") is None or d.get("longitude") is None:\n'
     '        why = d.get("API_ERROR") if isinstance(d, dict) else None\n'
     '        return {"ok": False, "provider": provider,\n'
     '                "reason": str(why or "no position in the answer")[:160]}\n'
     '    out = {"ok": True, "provider": d.get("provider", provider)}\n'),
]


def patch_all(src):
    for old, new in ALL_FIXES:
        if src.count(old) != 1:
            raise SystemExit("payload_v25: all, this anchor matches %d times, not once:\n    %s"
                             % (src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)
    return src
