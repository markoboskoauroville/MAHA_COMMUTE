"""payload_v30: reachable Rijeka fallback and all.commute v53."""

_RIJEKA_FALLBACK = '''
def _rj_api_rows():
    """Normalized timetable rows from Autotrolej's HTTPS endpoint.

    e-usluge2.rijeka.hr is an HTTP-only host that some mobile networks cannot
    reach. The official HTTPS API carries the same stop sequence and departure
    times, so it is the fallback rather than an invented or partial timetable.
    """
    data = _rj_fetch(RJ_API + "/voznired/polasci", timeout=90)
    result = data.get("res") if isinstance(data, dict) else data
    variants = result.values() if isinstance(result, dict) else (result or [])
    rows = []
    for variant in variants:
        if not isinstance(variant, dict):
            continue
        variant_id = str(variant.get("uniqueLinijaId") or variant.get("varijantaId") or "")
        route = str(variant.get("brojLinije") or "")
        head = variant.get("naziv") or ""
        direction = variant.get("smjerNaziv") or ""
        seq = {}
        for departure in variant.get("polazakList") or []:
            stop = departure.get("stanica") or {}
            sid = str(departure.get("stanicaId") or stop.get("id") or "")
            trip = str(departure.get("voznjaId") or "")
            when = str(departure.get("polazak") or "")
            if "T" in when:
                when = when.split("T", 1)[1][:8]
            trip_key = variant_id + ":" + trip
            seq[trip_key] = seq.get(trip_key, 0) + 1
            rows.append({
                "StanicaId": sid,
                "Naziv": stop.get("naziv") or sid,
                "GpsY": stop.get("gpsY"),
                "GpsX": stop.get("gpsX"),
                "BrojLinije": route,
                "NazivVarijanteLinije": head,
                "PolazakId": trip,
                "Polazak": when,
                "Smjer": stop.get("smjer") or direction,
                "LinVarId": trip_key,
                "RedniBrojStanice": seq[trip_key],
            })
    if not rows:
        raise RuntimeError("the Rijeka HTTPS API returned no departures")
    tmp = RJ_CACHE + ".api.part"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False)
    os.replace(tmp, RJ_CACHE)
    return rows


'''

ALL_FIXES = [
    ('APP_VERSION = "v52"', 'APP_VERSION = "v53"'),
    ('APP_BUILD = "b52"', 'APP_BUILD = "b53"'),
    ('ALLC_UI_VERSION="v52"', 'ALLC_UI_VERSION="v53"'),
    ('<div class="kv"><span>Interface</span><b>stations · v52</b></div>',
     '<div class="kv"><span>Interface</span><b>stations · v53</b></div>'),
    ('        data = _rj_fetch(url)\n',
     '        data = _rj_fetch(url, timeout=8 if "e-usluge2.rijeka.hr" in url else 60)\n'),
    ('\ndef _rj_load():\n',
     _RIJEKA_FALLBACK + 'def _rj_load():\n'),
    ('        rows, _src = _rj_cached(RJ_CACHE, RJ_BASE + "/ATvoznired.json", 6 * 3600)\n'
     '        if rows is None:\n',
     '        rows, _src = _rj_cached(RJ_CACHE, RJ_BASE + "/ATvoznired.json", 6 * 3600)\n'
     '        if _src in ("stale", "none"):\n'
     '            try:\n'
     '                fresh = _rj_api_rows()\n'
     '                if fresh:\n'
     '                    rows = fresh\n'
     '                    _log("Rijeka: used the official HTTPS API fallback")\n'
     '            except Exception as e:\n'
     '                _log("Rijeka HTTPS fallback: %r" % (e,))\n'
     '        if rows is None:\n'),
]


def patch_all(src):
    for old, new in ALL_FIXES:
        if src.count(old) != 1:
            raise SystemExit("payload_v30: this anchor matches %d times, not once:\n    %s"
                             % (src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)
    return src
