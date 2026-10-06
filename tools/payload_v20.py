"""payload_v20.py, what v20 does to the payloads. Called from patch_payload.py.

ALL.COMMUTE: THE DASHBOARD BELONGS TO ONE STATION. Marko, 6.10.2026: "remove
dashboard user interface and make sure the dashboard is opened only for
selected stations inside the map ... robust clicking mechanism, tapping
mechanism on station name, and then it opens the dashboard for that
particular station."

So there is no DASHBOARD button any more, no list of every station around
you, and no small station window in the middle of the map. Tapping a
station's label slides up one full-screen dashboard for that station alone:
its Street View photograph, what has just left, what is coming, and WATCH.
The ✕, or the phone's own back gesture, puts the map back.

Why taps were missed before: the label you could see sat 37 px to the left of
the station and had pointer-events:none, so a finger on the number went
straight through it to the map. Only an invisible 34 px square at the
coordinate itself answered. Now the label sits on the station, it is the
thing that answers, and it carries a margin of extra reach for a thumb. A
tap that wobbles a few pixels still counts as a tap (clickTolerance), a
Google-engine pin no longer leaks the same tap through to the map, and the
wait between tap and dashboard is shorter.

DAY.COMMUTE: WHY IT SOMETIMES DID NOT START. Marko, 6.10.2026: "Sometimes it's
offline. Maybe the port is clashing ... Port must be always scanned before
starting. If not available, port is just bumped for one number."

The server already did exactly that: it tries 8082, then 8083, and on up to
forty ports, and writes the one it got to ~/.commute/port. The fault was in
recognising it afterwards:

  1. The menu found day.commute by the name "commute_server.py", which is
     also inside "all_commute_server.py". With all.commute running, the menu
     believed day.commute was already up, started nothing, and opened a page
     with nothing behind it. day.commute stop and status had the same blind
     spot, and stop took all.commute down with it.
  2. The menu counted an app as up the moment its process existed, before
     it had bound a port, and then opened the table's 8082 rather than the
     port the server really took.
  3. A second day.commute typed at the prompt started a second server on
     8083, and whichever one stopped first deleted the port file the other
     one still needed.

Now the day server is found by its own path, an app counts as up only when
its process is alive AND the port it wrote down answers, the launcher opens
the server that is already running instead of starting another, and a
server deletes the port file only when the file still names its own port.
"""

# ------------------------------------------------------------- day.commute
DAY_FIXES = [
    ('COMMUTE_VERSION="v16"', 'COMMUTE_VERSION="v17"'),
    ('APP_VERSION = "v16"', 'APP_VERSION = "v17"'),
    ('(v.version || "v16")', '(v.version || "v17")'),
    ('if (el) el.textContent = "v16 (a)"; });', 'if (el) el.textContent = "v17 (a)"; });'),
    # its own path, never a name all.commute's server also contains
    ('    if pkill -f commute_server.py 2>/dev/null; then',
     '    if pkill -f "$SERVER" 2>/dev/null; then'),
    ('    if pgrep -f commute_server.py >/dev/null 2>&1; then',
     '    if pgrep -f "$SERVER" >/dev/null 2>&1; then'),
    # one day server at a time: an answering one is opened, a hung one replaced
    ('rm -f "$PORTFILE"\nexec python "$SERVER"',
     '# v17: one day server at a time. One that is running and answering is\n'
     '# opened, not doubled; one that is alive but answers nothing is replaced.\n'
     'if pgrep -f "$SERVER" >/dev/null 2>&1; then\n'
     '  P=$(tr -d \' \\n\' < "$PORTFILE" 2>/dev/null)\n'
     '  if [ -n "$P" ] && (exec 3<>"/dev/tcp/127.0.0.1/$P") 2>/dev/null; then\n'
     '    printf "  ${OK}already running${OFF} on ${KEY}http://127.0.0.1:%s${OFF}\\n" "$P"\n'
     '    URL="http://127.0.0.1:$P/bus.html"\n'
     '    termux-open-url "$URL" 2>/dev/null ||\n'
     '      am start -a android.intent.action.VIEW -d "$URL" >/dev/null 2>&1 || true\n'
     '    exit 0\n'
     '  fi\n'
     '  printf "  ${DIM}a day server was left hanging, replacing it${OFF}\\n"\n'
     '  pkill -f "$SERVER" 2>/dev/null; sleep 1\n'
     'fi\n'
     'rm -f "$PORTFILE"\n'
     'exec python "$SERVER"'),
    # say which port was skipped, so a clash is visible in the log
    ('        except OSError:\n            continue\n    if httpd is None:\n        _log("no free port found',
     '        except OSError:\n            _log("port %d is taken, trying %d" % (p, p + 1))\n'
     '            continue\n    if httpd is None:\n        _log("no free port found'),
    # the port file is deleted only if it still names this server's port
    ('            os.remove(PORTFILE)',
     '            with open(PORTFILE) as _pf:\n'
     '                _mine = _pf.read().strip() == str(port)\n'
     '            if _mine:\n'
     '                os.remove(PORTFILE)'),
]

# ------------------------------------------------------------- all.commute
CSS_POP_OLD_START = '  /* the station window */\n'
CSS_POP_OLD_END = '  /* ---- the stars ---- */\n'
CSS_POP_NEW = '''  /* v20: what the station window kept, now inside the station's dashboard */
  .popsec{padding:10px 13px 4px;font:800 .66rem/1 system-ui,sans-serif;letter-spacing:.09em;
    color:var(--muted);text-transform:uppercase;}
  .arow.gone{opacity:.5;}
  .arow.gone .tm b{color:var(--muted);}

'''

CSS_DASHBTN_START = '  /* ---- the dashboard button ---- */\n'
CSS_DASHBTN_END = '  #watchbar{'

MARKUP_START = '  <button id="dashBtn">DASHBOARD</button>\n'
MARKUP_END = '  <div id="pano">'
MARKUP_NEW = '''  <div id="dash">
    <div class="dhead">
      <span class="pid" id="dId">—</span>
      <div class="dtitle"><b id="dName">—</b><div class="sub" id="dSub">—</div></div>
      <button class="close" id="dClose" title="Back to the map">✕</button>
    </div>
    <div class="dbody" id="dBody"></div>
  </div>

'''

JS_DASH_START = '/* ---------------- the dashboard ---------------- */\n'
JS_DASH_KEEP_UNTIL = 'function arrHTML(s){'
JS_DASH_END = '/* ---------------- settings ---------------- */\n'
JS_DASH_NEW = r'''function arrHTML(b){
  if (!b) return '<div class="empty">Reading the board…</div>';
  const all = b.departures || [];
  const gone = all.filter(x => x.passed).slice(-4);
  const coming = all.filter(x => !x.passed).slice(0, 10);
  let html = "";
  if (gone.length) html += '<div class="popsec">just left</div>' +
    gone.map(x => arrivalRow(x).replace('class="arow', 'class="arow gone')).join("");
  return html + '<div class="popsec">coming</div>' + (coming.length
    ? coming.map(arrivalRow).join("")
    : '<div class="empty">Nothing in the next hour.</div>');
}
function photoHTML(s){
  const sv = SV_CACHE[s.stop_id];
  if (sv === undefined) return '<div class="svnone">Loading the photograph…</div>';
  if (!sv) return '<div class="svnone">' + (API_KEY
    ? "No Street View photograph here."
    : "Add a Google key in ⚙ to see the stop.") + '</div>';
  return '<span class="svwrap" data-pano="' + esc(s.stop_id) + '">' +
    '<img class="sv" src="' + esc(sv) + '" alt="' + esc(s.name) + '" loading="lazy"' +
    ' onerror="this.style.display=\'none\'">' +
    '<span class="svpin"><span class="svpinlabel">' + esc(s.stop_id) + '</span></span>' +
    '<span class="sv360">◉ 360°</span></span>';
}
function cardHTML(s){
  const c = stationColour(s.stop_id), on = isWatched(s.stop_id);
  return '<div class="card' + (on ? " on" : "") + '" style="--c:' + c + '" id="card-' +
      esc(s.stop_id) + '">' +
    '<div class="chead">' + starHTML(c, false, true) +
      '<span class="nm">' + (on ? "You are watching this stop" : "Watch it from the map") +
        '<i>' + (on ? "the bar at the bottom keeps the next one" : "its next arrival stays in a bar") + '</i></span>' +
      '<button class="wbtn' + (on ? " on" : "") + '" data-watch="' + esc(s.stop_id) + '">' +
        (on ? "WATCHING" : "WATCH") + '</button>' +
    '</div>' + photoHTML(s) +
    '<div class="arr">' + arrHTML(BOARDS[s.stop_id]) + '</div></div>';
}

/* v20: one station, one dashboard. The dashboard is never a list of every
   station around you; it opens for the station that was tapped, and only
   that one. Everything it shows is that station: its photograph, what has
   just left and what is coming. */
let DASH_SIG = "", DASH_HIST = false;
function stationFor(id){
  if (SEL && SEL.stop_id === id) return SEL;
  const s = STOPS.find(x => x.stop_id === id);
  if (s) return s;
  if (WATCH && WATCH.stop_id === id) {
    const w = Object.assign({}, WATCH);
    if (ME) w.dist = metres(ME.lat, ME.lng, w.lat, w.lon);
    return w;
  }
  return null;
}
function renderDash(){
  const s = SEL, body = document.getElementById("dBody");
  if (!s) { DASH_SIG = ""; body.innerHTML = ""; return; }
  const b = BOARDS[s.stop_id];
  document.getElementById("dash").style.setProperty("--c", stationColour(s.stop_id));
  document.getElementById("dId").textContent = s.stop_id;
  document.getElementById("dName").textContent = s.name;
  document.getElementById("dSub").textContent =
    subLine(s, b) + (b && b.feed_ok ? " · live" : "");
  /* rebuilt only when the station, its photograph or the watch changes, so a
     twenty-second refresh neither reloads the picture nor moves your scroll */
  const sig = s.stop_id + ":" +
    (s.stop_id in SV_CACHE ? (SV_CACHE[s.stop_id] ? "p" : "n") : "?") +
    (isWatched(s.stop_id) ? "w" : "");
  if (sig !== DASH_SIG) {
    const same = DASH_SIG.split(":")[0] === s.stop_id;
    DASH_SIG = sig;
    const keep = same ? body.scrollTop : 0;
    body.innerHTML = cardHTML(s);
    body.scrollTop = keep;
    return;
  }
  const arr = body.querySelector(".arr");
  if (arr) arr.innerHTML = arrHTML(b);
}
function dashOpen(){ return document.getElementById("dash").classList.contains("show"); }
function openDash(id){ const s = stationFor(id); if (s) openPop(s); }
document.getElementById("dClose").addEventListener("click", () => closePop());
document.getElementById("dBody").addEventListener("click", (e) => {
  const w = e.target.closest("[data-watch]");
  if (w) { toggleWatch(w.dataset.watch); return; }
  const p = e.target.closest("[data-pano]");
  if (p) { openPano(p.dataset.pano); return; }
});
/* the phone's back gesture closes the dashboard instead of leaving the app */
window.addEventListener("popstate", () => {
  if (DASH_HIST) { DASH_HIST = false; closePop(true); }
});

/* ---------------- watching one station ---------------- */
function watchStation(s){
  WATCH = { stop_id: s.stop_id, name: s.name, lat: s.lat, lon: s.lon };
  LS.set("watch", WATCH);
  document.body.classList.add("watching");
  if (!COLOUR[s.stop_id]) COLOUR[s.stop_id] = stationColour(s.stop_id);
  drawStars(); updateWatchBar();
  if (!boardTimer) boardTimer = setInterval(refreshBoards, 20000);
}
function toggleWatch(id){
  if (isWatched(id)) { clearWatch(); return; }
  const s = stationFor(id);
  if (!s) return;
  watchStation(s); renderDash();
  hud("Watching <b>" + esc(s.name) + "</b>.");
}
function clearWatch(){
  WATCH = null; LS.del("watch");
  document.body.classList.remove("watching");
  drawStars(); renderDash();
}
function updateWatchBar(){
  if (!WATCH) return;
  const c = COLOUR[WATCH.stop_id] || PALETTE[0];
  const bar = document.getElementById("watchbar");
  bar.style.setProperty("--c", c);
  const st = document.getElementById("wbStar");
  if (st) st.outerHTML = starHTML(c, false, true)
    .replace('class="star mini"', 'class="star mini" id="wbStar"');
  document.getElementById("wbName").textContent = WATCH.name;
  const next = comingAt(WATCH.stop_id)[0];
  document.getElementById("wbEta").innerHTML = next
    ? '<span class="rt sm' + (next.live ? "" : " sched") + '" style="--r:' +
      routeColour(next.route) + '">' + esc(next.route) + '</span> ' +
      (next.mins <= 0 ? "now" : next.mins + " min") + (next.live ? WIFI : "")
    : "—";
}
document.getElementById("watchbar").addEventListener("click", (e) => {
  if (e.target.closest("#wbX")) { clearWatch(); return; }
  if (WATCH) openDash(WATCH.stop_id);
});

'''

JS_POP_START = '/* ---------------- the station window ---------------- */\n'
JS_POP_END = '/* ---------------- the view switch ---------------- */\n'
JS_POP_NEW = r'''/* ---------------- the station's dashboard ---------------- */
async function openPop(stop, gen){
  // gen is the arming generation. If a later tap has happened while this was
  // in flight, everything below would draw the wrong station over the right
  // one, so it stops here instead.
  if (gen !== undefined && gen !== SELGEN) return;
  if (!stop) return;
  SEL = stop;
  // Opening a station IS watching it, as it has been since v39.
  if (!WATCH || WATCH.stop_id !== stop.stop_id) watchStation(stop);
  markSel(stop);
  document.getElementById("dash").classList.add("show");
  if (!DASH_HIST) { try { history.pushState({ dash: 1 }, ""); DASH_HIST = true; } catch (e) {} }
  renderDash();
  streetView(stop).then(() => { if (SEL === stop) renderDash(); });
  await refreshPop();
  if (gen !== undefined && gen !== SELGEN) return;
  if (SEL !== stop) return;
  hud("<b>" + esc(stop.stop_id) + "</b> " + esc(stop.name), false);
  if (popTimer) clearInterval(popTimer);
  popTimer = setInterval(refreshPop, 20000);
}
async function refreshPop(){
  const s = SEL;
  if (!s) return;
  let b = null;
  try {
    b = await fetch("board?stop=" + encodeURIComponent(s.stop_id) +
      "&mins=60&back=10", { cache: "no-store" }).then(r => r.json());
  } catch (e) { return; }
  if (!b || !b.ok) return;
  BOARDS[s.stop_id] = b;
  if (SEL === s) renderDash();
  updateWatchBar();
}
function closePop(fromBack){
  SEL = null;
  SELGEN++;                              // a fetch still in flight stays closed
  if (ARM_T) { clearTimeout(ARM_T); ARM_T = null; }
  document.getElementById("dash").classList.remove("show");
  document.querySelectorAll(".pin.armed").forEach(e => e.classList.remove("armed"));
  if (popTimer) { clearInterval(popTimer); popTimer = null; }
  clearSel();
  if (!fromBack && DASH_HIST) { DASH_HIST = false; try { history.back(); } catch (e) {} }
  hud(MODE === "google" ? "Tap any station Google draws to see what is coming." : stopsLine());
}

'''

ALL_FIXES = [
    ('APP_VERSION = "v42"\nAPP_BUILD = "b42"', 'APP_VERSION = "v43"\nAPP_BUILD = "b43"'),
    ('<div class="kv"><span>Interface</span><b>stars · v39</b></div>',
     '<div class="kv"><span>Interface</span><b>stations · v43</b></div>'),
    # the label sits ON the station, and the label is what answers the finger
    ('  .pin{position:relative;width:34px;height:34px;}\n',
     '  /* v20: the label is centred on the station and is itself the tap target,\n'
     '     with a margin of extra reach around it for a thumb */\n'
     '  .pin{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);\n'
     '    cursor:pointer;touch-action:manipulation;}\n'
     '  .pin::before{content:"";position:absolute;inset:-12px -10px;}\n'),
    ('  .pinid{position:absolute;right:37px;top:50%;transform:translateY(-50%);\n'
     '    pointer-events:none;}\n',
     '  .pinid{position:relative;display:block;pointer-events:auto;}\n'),
    ('  .pinid span{display:inline-block;padding:4px 6px;',
     '  .pinid span{display:inline-block;padding:7px 9px;'),
    # the dashboard header carries the station's number, name and colour
    ('  .dhead b{font-size:1.05rem;letter-spacing:.02em;}\n',
     '  .dhead{background:color-mix(in srgb,var(--c,#2a323d) 15%,var(--bg));\n'
     '    border-bottom:2px solid var(--c,var(--border));}\n'
     '  .dhead .pid{flex:none;padding:5px 8px;border-radius:8px;color:var(--c);\n'
     '    border:1px solid var(--c);background:rgba(13,17,23,.5);\n'
     '    font:800 .78rem/1 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;}\n'
     '  .dhead .dtitle{flex:1;min-width:0;}\n'
     '  .dhead b{font-size:1.05rem;letter-spacing:.02em;display:block;line-height:1.2;}\n'),
    # a tap that wobbles a few pixels is still a tap, not a drag
    ('  map = L.map("map", { zoomControl: false, attributionControl: true })',
     '  map = L.map("map", { zoomControl: false, attributionControl: true,\n'
     '    clickTolerance: 10, tapTolerance: 22 })'),
    # Google engine: the pin's tap is the pin's, not also the map's
    ('      if (this.c) this.div.addEventListener("click", this.c);',
     '      if (this.c) {\n'
     '        this.div.addEventListener("click", (e) => { e.stopPropagation(); this.c(e); });\n'
     '        if (g.maps.OverlayView.preventMapHitsAndGesturesFrom)\n'
     '          g.maps.OverlayView.preventMapHitsAndGesturesFrom(this.div);\n'
     '      }'),
    ('        () => openPop(s), on ? 1000 : 500);', '        () => armStation(s), on ? 1000 : 500);'),
    # a shorter wait between the tap and the dashboard
    ('  }, 333);\n}\nfunction clearStars(){', '  }, 180);\n}\nfunction clearStars(){'),
    # Google's own station icons: a later tap wins, and a wider catch
    ('  const r = onIcon ? 90 : 40;\n  try {',
     '  const r = onIcon ? 120 : 40;\n  const gen = ++SELGEN;\n  try {'),
    ('    if (!st) { if (!onIcon) closePop(); else hud("No ZET stop registered at that icon."); return; }\n'
     '    openPop(st);',
     '    if (!st) { if (onIcon) hud("No ZET stop registered at that icon."); return; }\n'
     '    openPop(st, gen);'),
    # the 360 view finds the station that is open, wherever it came from
    ('async function openPano(id){\n  const s = STOPS.find(x => x.stop_id === id);',
     'async function openPano(id){\n  const s = stationFor(id);'),
    ('    document.getElementById("dashBtn").classList.add("hasbar");\n    document.getElementById("wbName")',
     '    document.getElementById("wbName")'),
    # nothing tells you to tap a button that is no longer there
    ('". Tap <b>DASHBOARD</b>.");', '". Tap a station.");'),
    ('. Tap <b>DASHBOARD</b>, or tap a star.";', '. Tap a station to see what is coming.";'),
    ('How far around you the dashboard looks.', 'How far around you the map looks for stations.'),
    ('open it, let it find you, tap DASHBOARD', 'open it, let it find you, tap a station'),
]

ALL_BLOCKS = [
    (CSS_POP_OLD_START, CSS_POP_OLD_END, CSS_POP_NEW),
    (CSS_DASHBTN_START, CSS_DASHBTN_END, ''),
    (MARKUP_START, MARKUP_END, MARKUP_NEW),
    (JS_POP_START, JS_POP_END, JS_POP_NEW),
]


def _block(src, start, end, new, keep_until=None):
    """Replace from start up to (not including) end. Both must be unique."""
    for m in (start, end):
        if src.count(m) != 1:
            raise SystemExit("payload_v20: all, this marker matches %d times, not once:\n    %s"
                             % (src.count(m), m.strip()[:70]))
    a = src.index(start)
    b = src.index(end)
    if b <= a:
        raise SystemExit("payload_v20: all, a block ends before it starts: %s" % start.strip())
    if keep_until is not None:
        k = src.index(keep_until, a)
        if k >= b:
            raise SystemExit("payload_v20: all, %s is not inside the dashboard block" % keep_until)
        return src[:k] + new + src[b:]
    return src[:a] + new + src[b:]


def patch_all(src):
    """The blocks go first, so the one-line fixes can find what is left."""
    for start, end, new in ALL_BLOCKS:
        src = _block(src, start, end, new)
    # The dashboard block keeps its first helpers (delayBit, arrivalRow,
    # subLine) and replaces everything from arrHTML on.
    src = _block(src, JS_DASH_START, JS_DASH_END, JS_DASH_NEW, keep_until=JS_DASH_KEEP_UNTIL)
    for old, new in ALL_FIXES:
        if src.count(old) != 1:
            raise SystemExit("payload_v20: all, this anchor matches %d times, not once:\n    %s"
                             % (src.count(old), old.splitlines()[0][:70]))
        src = src.replace(old, new, 1)
    if "dashBtn" in src or "popwrap" in src:
        raise SystemExit("payload_v20: all, the old dashboard button or window survived")
    return src
