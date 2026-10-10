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

AND THE LAST GOOD READING IS KEPT. A failed reading carries the last good one from
the same provider as "last", with "last_age_s" (seconds since it was taken: the
time since it was banked plus the age Android gave it, elapsedMs, which the phone
showed is the fix's age and not the call's duration). The page says "last known
fix, N min ago" and shows its accuracy and age under the failure, instead of "no
provider answered", and the fresh-fix button no longer says "Android answered."
when it did not.

A 500 IS WRITTEN DOWN. The route dispatch turned every exception into a 500 whose
reason went only into the response body, so the /gps 500 seen in the phone's
server.log at 07:39:35 left nothing to read. The traceback now goes to the log.

THE DOT FOLLOWS YOU. Marko, 10.10.2026: "All commute it followed me for some time,
then it stops." The position comes from the browser's watchPosition, opened in
bursts of 18 s and closed early once four fixes agreed within 8 m, then reopened
only by the 90 second tick: in good conditions about six seconds of listening every
ninety, so a walker's dot jumped once and sat still. And fuse() averaged every fix
of the last 90 s, so even while listening the dot trailed behind (68 m behind on a
135 m walk, measured by the phone session).

Now, while "follow me" is on (the default, a switch in Settings, Position), the watch
stays open as long as the page is visible: the 90 second tick keeps extending it and
nothing hangs up early. Hiding the page still releases the GNSS at once, which is the
battery bound. fuse() averages only the fixes near the newest one, so standing still
keeps the full average and walking drops the ones left behind. Off, it is the old
burst. Found and first patched on the phone by the phone session.
"""

ALL_FIXES = [
    ('APP_VERSION = "v47"\nAPP_BUILD = "b47"', 'APP_VERSION = "v48"\nAPP_BUILD = "b48"'),
    ('<div class="kv"><span>Interface</span><b>stations · v47</b></div>',
     '<div class="kv"><span>Interface</span><b>stations · v48</b></div>'),
    ('ALLC_UI_VERSION="v47"', 'ALLC_UI_VERSION="v48"'),
    ('let watchId = null, burstEnd = 0, burstTick = null;\n',
     'let watchId = null, burstEnd = 0, burstTick = null;\n'
     'let FOLLOW = LS.get("follow", true);   // keep listening while the page is visible\n'),
    ('  const live = FIXES.filter(f => now - f.t < FIX_TTL);\n  if (!live.length) return null;\n',
     '  const fresh = FIXES.filter(f => now - f.t < FIX_TTL);\n  if (!fresh.length) return null;\n'
     '  /* only the fixes near the newest one: standing still that is all of them, and\n'
     '     walking, the ones left behind drop out instead of dragging the dot back */\n'
     '  const newest = fresh[fresh.length - 1];\n'
     '  const span = Math.max(25, newest.acc || 25);\n'
     '  const live = fresh.filter(f => metres(newest.lat, newest.lng, f.lat, f.lng) <= span);\n'),
    ('    if (f && f.acc <= 8 && f.n >= 4 && Date.now() > burstEnd - ms + 6000) stopBurst();\n',
     '    if (!FOLLOW && f && f.acc <= 8 && f.n >= 4 && Date.now() > burstEnd - ms + 6000) stopBurst();\n'),
    ('  startBurst(force ? 30000 : 18000);\n}\n',
     '  startBurst(FOLLOW ? 3600000 : (force ? 30000 : 18000));\n}\n'),
    ('        <button class="btn" id="posSharpen">Sharpen — hold still</button>\n',
     '        <button class="btn" id="posSharpen">Sharpen — hold still</button>\n'
     '        <button class="btn ghost" id="posFollow">Follow me: on</button>\n'),
    ('document.getElementById("posSharpen").addEventListener("click", () => {\n',
     'function paintFollow(){\n'
     '  const b = document.getElementById("posFollow");\n'
     '  if (b) b.textContent = "Follow me: " + (FOLLOW ? "on" : "off");\n'
     '}\n'
     'paintFollow();\n'
     'document.getElementById("posFollow").addEventListener("click", () => {\n'
     '  FOLLOW = !FOLLOW; LS.set("follow", FOLLOW); paintFollow();\n'
     '  document.getElementById("posMsg").textContent = FOLLOW\n'
     '    ? "The dot follows you while this page is open. Uses more battery."\n'
     '    : "Listening in short bursts again, every 90 seconds.";\n'
     '  if (!FOLLOW) { stopBurst(); burstEnd = 0; }\n'
     '  autoLocate(true);\n'
     '});\n'
     'document.getElementById("posSharpen").addEventListener("click", () => {\n'),
    ('\n\ndef gps_state(fresh=False):\n',
     '\n\n_LAST_FIX = {}\n'
     '_LAST_FIX_LOCK = threading.Lock()\n'
     '_termux_fix_once = termux_fix\n'
     '\n\n'
     'def termux_fix(provider="gps", request="last", timeout=14):\n'
     '    """The reading, and on a failure the last good one from the same provider."""\n'
     '    r = _termux_fix_once(provider, request, timeout)\n'
     '    now = time.time()\n'
     '    with _LAST_FIX_LOCK:\n'
     '        if r.get("ok"):\n'
     '            _LAST_FIX[provider] = (now, dict(r))\n'
     '        elif provider in _LAST_FIX:\n'
     '            at, last = _LAST_FIX[provider]\n'
     '            r["last"] = last\n'
     '            r["last_age_s"] = int(now - at + (last.get("elapsedMs") or 0) / 1000)\n'
     '    return r\n'
     '\n\ndef gps_state(fresh=False):\n'),
    ('        except Exception as e:\n'
     '            return self._json({"ok": False, "reason": repr(e)}, 500)\n',
     '        except Exception as e:\n'
     '            import traceback\n'
     '            sys.stderr.write("500 on %s\\n%s" % (route, traceback.format_exc()))\n'
     '            sys.stderr.flush()\n'
     '            return self._json({"ok": False, "reason": repr(e)}, 500)\n'),
    ('  document.getElementById("posMsg").textContent = GPSINFO && GPSINFO.termux\n'
     '    ? "Android answered." : "Termux:API is not installed.";\n',
     '  document.getElementById("posMsg").textContent = !GPSINFO\n'
     '    ? "The app did not answer." : (!GPSINFO.termux ? "Termux:API is not installed."\n'
     '    : (GPSINFO.better ? "Android answered." : "Android could not get a fix just now."));\n'),
    ('  if (GPSINFO.better === "network") return "wifi / cell";\n'
     '  return "no provider answered";\n',
     '  if (GPSINFO.better === "network") return "wifi / cell";\n'
     '  const lastAge = gpsLastAge();\n'
     '  if (lastAge != null) return "last known fix, " + fmtSecsAgo(lastAge);\n'
     '  return "no provider answered";\n'
     '}\n'
     'function fmtSecsAgo(s){\n'
     '  if (s < 90) return Math.max(0, Math.round(s)) + " s ago";\n'
     '  if (s < 5400) return Math.round(s / 60) + " min ago";\n'
     '  return Math.round(s / 3600) + " h ago";\n'
     '}\n'
     'function gpsLastAge(){\n'
     '  if (!GPSINFO) return null;\n'
     '  const ages = [GPSINFO.gps, GPSINFO.network]\n'
     '    .filter(o => o && !o.ok && o.last && o.last_age_s != null).map(o => o.last_age_s);\n'
     '  return ages.length ? Math.min.apply(null, ages) : null;\n'),
    ('    if (!o || !o.ok) return \'<div class="kv"><span>\' + name + \'</span><b>\' +\n'
     '      esc((o && o.reason) || "no fix") + \'</b></div>\';\n',
     '    if (!o || !o.ok) return \'<div class="kv"><span>\' + name + \'</span><b>\' +\n'
     '      esc((o && o.reason) || "no fix") + \'</b></div>\' +\n'
     '      (o && o.last && o.last_age_s != null\n'
     '        ? \'<div class="kv"><span>last known</span><b>±\' +\n'
     '          (o.last.accuracy == null ? "?" : Math.round(o.last.accuracy)) + " m · " +\n'
     '          esc(fmtSecsAgo(o.last_age_s)) + \'</b></div>\' : "");\n'),
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
