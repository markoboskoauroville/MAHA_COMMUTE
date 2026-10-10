#!/usr/bin/env python3
"""A stand-in for OpenStreetMap's Overpass API, for tests only.

    mock_overpass.py PORT COUNTFILE

Answers every POST with one bus stop at the middle of the box the query asked for,
named "Testna <call>.<k>", and appends a line to COUNTFILE per request, so a test can say how
many times the app asked. Nothing here goes near the network."""
import http.server, json, re, sys, urllib.parse
port, countfile = int(sys.argv[1]), sys.argv[2]
n = [0]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        q = urllib.parse.parse_qs(body).get("data", [""])[0]
        m = re.search(r"\((-?[\d.]+),(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)\)", q)
        n[0] += 1
        with open(countfile, "a") as f:
            f.write("%d\n" % n[0])
        els = []
        if m:
            s, w, nn, e = map(float, m.groups())
            for i in range(6):                  # a 6 by 6 grid of stops across the box asked for
                for j in range(6):
                    els.append({"type": "node", "id": 9000 + n[0] * 100 + i * 6 + j,
                                "lat": s + (nn - s) * (i + 0.5) / 6, "lon": w + (e - w) * (j + 0.5) / 6,
                                "tags": {"highway": "bus_stop", "name": "Testna %d.%d" % (n[0], i * 6 + j)}})
        out = json.dumps({"elements": els}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out))); self.end_headers(); self.wfile.write(out)
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
