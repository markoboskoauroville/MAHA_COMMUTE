"""payload_v19.py, what v19 does to the payloads. Imported by patch_payload.py.

THE FIRST BUTTON IN day.commute IS CALLED BUZIN. Marko, 5.10.2026: "just
rename button nova tv with Buzin". The ride, its stops and its corridor are
unchanged; only the name of the direction changes, everywhere it is shown as
the name of that direction. Where "Nova TV" names the PLACE (the corridor that
switches on when you are near the building) it stays, because the building is
still called that.

The label is written into bus.json by update_bus.py, and the phone keeps its
bus.json until the next rebuild, so a phone that updates in the evening would
still read "Nova TV" until the morning. The page therefore shows Buzin for that
one direction when it is handed a bus.json from before v16.
"""

DAY_FIXES = [
    ('COMMUTE_VERSION="v15"', 'COMMUTE_VERSION="v16"'),
    ('APP_VERSION = "v15"', 'APP_VERSION = "v16"'),
    ('(v.version || "v15")', '(v.version || "v16")'),
    ('if (el) el.textContent = "v15 (a)"; });', 'if (el) el.textContent = "v16 (a)"; });'),
    ('{"id": "to-work", "label": "Nova TV", "stops": COMMUTE_STOPS,',
     '{"id": "to-work", "label": "Buzin", "stops": COMMUTE_STOPS,'),
    ('    p.textContent = d.label;\n',
     '    // a bus.json built before v16 still says Nova TV until the next rebuild\n'
     '    p.textContent = (d.id === "to-work" && d.label === "Nova TV") ? "Buzin" : d.label;\n'),
    ('"to-work": "Nova TV  (to work)",', '"to-work": "Buzin  (to work)",'),
    ('const names = { "to-work": "the ride to Nova TV",', 'const names = { "to-work": "the ride to Buzin",'),
    ('Near home the app opens the ride to Nova TV, near', 'Near home the app opens the ride to Buzin, near'),
]
