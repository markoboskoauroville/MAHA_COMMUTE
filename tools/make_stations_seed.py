#!/usr/bin/env python3
"""make_stations_seed.py: the stations that ship INSIDE all.commute.

    tools/make_stations_seed.py <stations.json from a real rebuild>

Writes src/payloads/stations_seed.json. Stations do not move, so the app
carries every one of them and draws them the moment it opens, before any
timetable has been downloaded and with no network at all. The first rebuild
merges the live feed into this file and never takes a station out.

Make the input by running update_all.py on a real ZET feed (see MEMORY.md, v21)
and take its stations.json. Run this again only when ZET adds stops.
"""
import json, sys, os
src = json.load(open(sys.argv[1], encoding="utf-8"))["stops"]
out = {}
for k in sorted(src):
    name, la, lo, br = src[k]
    if not (45.5 < la < 46.1 and 15.5 < lo < 16.5):
        sys.exit("make_stations_seed: %s is outside Zagreb: %r" % (k, src[k]))
    out[k] = [name, round(la, 6), round(lo, 6), None if br is None else round(br, 1)]
if len(out) < 2000:
    sys.exit("make_stations_seed: only %d stations, that is not a whole feed" % len(out))
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "payloads", "stations_seed.json")
with open(dst, "w", encoding="utf-8") as f:
    json.dump({"updated": 0, "count": len(out), "stops": out}, f, ensure_ascii=False, separators=(",", ":"))
    f.write("\n")
print("wrote %d stations, %d bytes" % (len(out), os.path.getsize(dst)))
