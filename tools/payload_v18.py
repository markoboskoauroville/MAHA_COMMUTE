"""payload_v18.py, what v18 does to the payloads. Imported by patch_payload.py.

THE MAP WENT BLANK, 4.10.2026. all.commute drew its free map from CARTO, and
CARTO began answering every tile with one and the same picture, "API KEY
REQUIRED" (measured: three different places on the map, one identical 2 KB
image). night.commute offered CARTO as two of its four map styles. Neither is
free any more without an account, so both now draw OpenStreetMap's own tiles,
which need no key (measured: real tiles, about 20 KB each, no key sent).
OpenStreetMap is the default everywhere it can be. Google Maps stays the
second choice, for whoever has a key.

THE KEY, AT THE TOP OF SETTINGS. The file picker for the map key moves to the
first card in each app's Settings, with a short guide to getting a Google key
inside it. The key is still optional for night and all. day.commute's bus map
is built on Google's own markers and lines, so it still needs the key; its
card says so instead of pretending.
"""

OSM = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
# OpenStreetMap is light. These apps are dark. The tiles are inverted and turned
# back to their own hues by the browser, which costs nothing and needs no
# second tile server.
DARK_FILTER = "filter:invert(1) hue-rotate(180deg) brightness(.95) contrast(.9) saturate(.7);"

CSS_KEYTOP = (
    "  .keytop { border-color:var(--gold, var(--accent, #d4a017)) !important; }\n"
    "  .keyguide { margin-top:10px; font-size:.86rem; line-height:1.45; }\n"
    "  .keyguide summary { cursor:pointer; font-weight:700; padding:6px 0; }\n"
    "  .keyguide ol { margin:6px 0 6px 18px; padding:0; }\n"
    "  .keyguide li { margin:4px 0; }\n"
    "  .keyguide a { color:inherit; font-weight:700; }\n"
)


def guide(intro, apis):
    """The same guide in all three apps; only the opening line and the APIs differ."""
    return (
        '      <div class="keyguide">\n'
        '        <p>%s</p>\n'
        '        <details><summary>How to get a Google Maps key</summary>\n'
        '        <ol>\n'
        '          <li>Open <a href="https://console.cloud.google.com/" target="_blank" rel="noopener">console.cloud.google.com</a> and sign in with a Google account.</li>\n'
        '          <li>Create a project: the project menu at the top, then New project.</li>\n'
        '          <li>Add billing. Google asks for a card before its maps work. The use of one person normally stays inside Google\'s free monthly allowance.</li>\n'
        '          <li>APIs and Services, then Library: switch on %s.</li>\n'
        '          <li>APIs and Services, then Credentials: Create credentials, API key. Copy the key.</li>\n'
        '          <li>Restrict the key to those APIs, so it is useless for anything else if it ever leaks.</li>\n'
        '          <li>Put the key alone in a text file named <b>google-api.txt</b>, then pick that file with the button above.</li>\n'
        '        </ol>\n'
        '        <a href="https://developers.google.com/maps/documentation/javascript/get-api-key" target="_blank" rel="noopener">Google\'s own guide</a>\n'
        '        </details>\n'
        '      </div>\n'
    ) % (intro, apis)


IPLINE = '    <div class="ipline" id="ipLine">on this phone only</div>\n'

# ---------------------------------------------------------------- day.commute
DAY_OLD_KEY = (
    '    <div class="zet-card">\n'
    '      <div class="zet-h">Google Maps key\n'
    '        <span class="keydot" id="mapsDot" title="key status"></span></div>\n'
    '      <input type="file" id="mapsFile" accept=".txt,text/plain" class="keyfile">\n'
    '      <label for="mapsFile" class="setup-save keybtn">Load key from file</label>\n'
    '      <div id="setupMsg" class="setup-msg"></div>\n'
    '      <p class="setup-note">The key itself is never shown. Stored on your phone\n'
    '        in ~/.commute/google-api.txt.</p>\n'
    '    </div>\n\n'
)
DAY_TOP = (
    '    <div class="zet-card keytop">\n'
    '      <div class="zet-h">Map key\n'
    '        <span class="keydot" id="mapsDot" title="key status"></span></div>\n'
    '      <input type="file" id="mapsFile" accept=".txt,text/plain" class="keyfile">\n'
    '      <label for="mapsFile" class="setup-save keybtn">Choose the key file</label>\n'
    '      <div id="setupMsg" class="setup-msg"></div>\n'
    + guide("The bus map is Google Maps and needs a key. Everything else in day.commute works without one. "
            "The key is never shown, and stays on this phone in ~/.commute/google-api.txt.",
            "<b>Maps JavaScript API</b>")
    + '    </div>\n\n'
)
DAY_FIXES = [
    ('COMMUTE_VERSION="v14"', 'COMMUTE_VERSION="v15"'),
    ('APP_VERSION = "v14"', 'APP_VERSION = "v15"'),
    ('(v.version || "v14")', '(v.version || "v15")'),
    ('if (el) el.textContent = "v14 (a)"; });', 'if (el) el.textContent = "v15 (a)"; });'),
    (DAY_OLD_KEY, ''),
    (IPLINE, IPLINE + DAY_TOP),
    ('</style>', CSS_KEYTOP + '</style>'),
]

# ---------------------------------------------------------------- night.commute
NIGHT_OLD_KEY = (
    '      <h4 style="margin-top:12px">Google Maps key <span class="keydot" id="gmapsDot"></span></h4>\n'
    '      <input type="file" id="gmapsFile" accept=".txt,text/plain" class="keyfile">\n'
    '      <label for="gmapsFile" class="btn">Load key from file</label>\n'
    '      <div id="gmapsMsg" class="msg"></div>\n'
    '      <span class="note">OpenStreetMap is free and needs no key. A Google key is\n'
    '        only needed for the Google Maps service. The key is never shown.</span>\n'
)
NIGHT_TOP = (
    '    <div class="card keytop">\n'
    '      <h4>Map key <span class="keydot" id="gmapsDot"></span></h4>\n'
    '      <input type="file" id="gmapsFile" accept=".txt,text/plain" class="keyfile">\n'
    '      <label for="gmapsFile" class="btn">Choose the key file</label>\n'
    '      <div id="gmapsMsg" class="msg"></div>\n'
    + guide("The map is OpenStreetMap: free, and it works without a key. A Google key only adds Google Maps "
            "as a second choice under Map service. The key is never shown.",
            "<b>Maps JavaScript API</b>")
    + '    </div>\n'
)
NIGHT_FIXES = [
    ('NIGHT_VERSION="v12 (a)"', 'NIGHT_VERSION="v13 (a)"'),
    ('APP_VERSION = "v12"\nAPP_BUILD = "n12-a"', 'APP_VERSION = "v13"\nAPP_BUILD = "n13-a"'),
    ('installed  night.commute v12 (a)', 'installed  night.commute v13 (a)'),
    ('(v.version||"v12")', '(v.version||"v13")'),
    ('textContent="v12 (a)"; });', 'textContent="v13 (a)"; });'),
    ('  light:{u:"https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png", a:"&copy; OpenStreetMap &copy; CARTO", max:20, sub:"abcd"},\n'
     '  dark: {u:"https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", a:"&copy; OpenStreetMap &copy; CARTO", max:20, sub:"abcd"},\n',
     '  light:{u:"https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png", a:"&copy; OpenStreetMap, HOT", max:19, sub:"abc"},\n'
     '  dark: {u:"' + OSM + '", a:"&copy; OpenStreetMap", max:19, sub:null},\n'),
    ('{k:"light",n:"Carto Light"},{k:"dark",n:"Carto Dark"}', '{k:"light",n:"OSM Humanitarian"},{k:"dark",n:"OSM Dark"}'),
    ('  setBase(k){ const t=OSM_TILES[k]||OSM_TILES.osm;\n',
     '  setBase(k){ const t=OSM_TILES[k]||OSM_TILES.osm;\n    MAP.getContainer().classList.toggle("osm-dark", k==="dark");\n'),
    (NIGHT_OLD_KEY, ''),
    (IPLINE, IPLINE + NIGHT_TOP),
    ('</style>', '  .osm-dark .leaflet-tile-pane { ' + DARK_FILTER + ' }\n' + CSS_KEYTOP + '</style>'),
]

# ---------------------------------------------------------------- all.commute
ALL_OLD_KEY = (
    '    <div class="box">\n'
    '      <h3>Google key <span class="dot" id="keyDot"></span></h3>\n'
    '      <input type="file" id="keyFile" accept=".txt,text/plain" class="keyfile">\n'
    '      <div class="btnrow">\n'
    '        <label for="keyFile" class="btn">Load key from file</label>\n'
    '        <button class="btn ghost" id="keyTest">Test key</button>\n'
    '      </div>\n'
    '      <div class="msg" id="keyMsg"></div>\n'
    '      <span class="note">Three things use it: the station photograph, the 360° view,\n'
    '        and the detailed map. Kept on the phone in ~/.all.commute/google-api.txt and\n'
    '        never shown. Needs <b>Street View Static API</b> for the photograph and\n'
    '        <b>Maps JavaScript API</b> for the other two.</span>\n'
    '    </div>\n\n'
)
ALL_TOP = (
    '    <div class="box keytop">\n'
    '      <h3>Map key <span class="dot" id="keyDot"></span></h3>\n'
    '      <input type="file" id="keyFile" accept=".txt,text/plain" class="keyfile">\n'
    '      <div class="btnrow">\n'
    '        <label for="keyFile" class="btn">Choose the key file</label>\n'
    '        <button class="btn ghost" id="keyTest">Test key</button>\n'
    '      </div>\n'
    '      <div class="msg" id="keyMsg"></div>\n'
    + guide("The map is OpenStreetMap: free, and it works without a key. A Google key adds three things: the "
            "detailed map, the station photograph and the 360&deg; view. Kept on the phone in "
            "~/.all.commute/google-api.txt and never shown.",
            "<b>Maps JavaScript API</b> and <b>Street View Static API</b>")
    + '    </div>\n\n'
)
ALL_FIXES = [
    ('APP_VERSION = "v41"\nAPP_BUILD = "b41"', 'APP_VERSION = "v42"\nAPP_BUILD = "b42"'),
    ('const TILE_BASE  = "https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png";\n'
     'const TILE_NAMES = "https://{s}.basemaps.cartocdn.com/dark_only_labels/{z}/{x}/{y}{r}.png";\n',
     '// v18: OpenStreetMap\'s own tiles. CARTO began answering every tile with one\n'
     '// picture saying API KEY REQUIRED. OpenStreetMap tiles carry their own labels,\n'
     '// so the separate names layer is an empty group and nothing else has to change.\n'
     'const TILE_BASE  = "' + OSM + '";\n'),
    ('{ maxZoom: 20, attribution: "© OpenStreetMap, © CARTO" }', '{ maxZoom: 19, attribution: "© OpenStreetMap contributors" }'),
    ('  names = L.tileLayer(TILE_NAMES, { maxZoom: 20, opacity: .95, pane: "names" });\n', '  names = L.layerGroup();\n'),
    (ALL_OLD_KEY, ''),
    (IPLINE, IPLINE + ALL_TOP),
    ('  #setup.show{display:block;}\n', '  #setup.show{display:block;}\n  #map .leaflet-tile-pane { ' + DARK_FILTER + ' }\n' + CSS_KEYTOP),
]
