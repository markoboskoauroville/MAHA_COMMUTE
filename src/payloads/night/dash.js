
/* ===========================================================================
   THE STATION DASHBOARD, night.commute v15

   Spliced into night.html at build time by tools/payload_v25.py, after live.js
   and star.js, because it wraps liveDraw and loadNet and a wrapper has to go
   round the finished thing.

   WHAT IT IS

   all.commute's dashboard, on the night network. Tap a station on the map and
   one full-screen panel slides up for that station alone: its Street View
   photograph, what has just left, what is coming, and WATCH. The ✕ or the
   phone's back gesture closes it.

   WHERE THE DATA COMES FROM, AND WHY THERE IS NO /board

   all.commute asks its server for a station's board. night.commute never had
   that route and does not grow one here: everything the board needs is already
   in the page. The scheduled departures come from realTimes(), the same
   function the Plan tab reads, and the live trams come from liveApproaching()
   and are paired to the scheduled rows by liveMatchRows() — the same pairing,
   in order, that the Plan legs use. So the dashboard says exactly what the Plan
   tab would say about the same station, in all.commute's shape.

   EARLY IS NOT A DELAY, HERE TOO

   The board is built on liveMins()/liveAt(), so a tram running ahead of its
   slot is shown as arriving-and-waiting, not as leaving early, and the
   countdown counts to the later of the two — the moment the tram can take you.
   That logic is night.commute's and is not re-derived here; it is reused.
   =========================================================================== */

let ND_SEL = null;          // the station whose dashboard is open, or null
let ND_WATCH = null;        // the watched station name (localStorage nc_watch)
let ND_HIST = false;        // a history entry was pushed for the open dashboard
let ND_TIMER = null;        // the 20 s board refresh while the dashboard is open
let ND_SIG = "";            // what the body was last built for (station|key|watch)
let ND_KEY = "";            // the Google key, for the Street View photograph
let ND_KEY_READY = false;   // whether the key has been asked for yet

try { ND_WATCH = localStorage.getItem("nc_watch") || null; } catch (e) { ND_WATCH = null; }

/* ---- the two destinations a station sends trams toward ---- */
// Direction 0 runs up the line's listed order, toward termB (the last station);
// direction 1 runs back down it, toward termA (the first). A station that IS
// the terminal in a direction sends nothing that way, so that direction is
// skipped — which is also the only case realTimes/liveApproaching cannot answer.
function ndDirs(name, L){
  const out = [];
  if (L.termB && L.termB !== name) out.push({ d: 0, dest: L.termB });
  if (L.termA && L.termA !== name) out.push({ d: 1, dest: L.termA });
  return out;
}

// Every scheduled departure from this station, across its lines and both
// directions, merged with the live tram coming to fill each row.
function ndStationDeps(name){
  const out = [];
  (ST_LINES[name] || []).forEach(ln => {
    const L = NET.lines[ln];
    if (!L || L.stations.indexOf(name) < 0) return;
    ndDirs(name, L).forEach(({ dest }) => {
      const rt = realTimes(ln, name, dest, 6);
      if (!rt || !rt.length) return;
      const M = (typeof liveMatchRows === "function") ? liveMatchRows(ln, name, dest, rt)
                                                      : rt.map(() => null);
      rt.forEach((u, i) => {
        const m = M[i];
        out.push({ route: ln, head: dest, dep: u.dep, arr: u.arr,
          mins: (m && typeof liveMins === "function") ? liveMins(m, u) : u.min,
          live: !!m, m: m, passed: false });
      });
    });
  });
  out.sort((a, b) => a.mins - b.mins);
  return out;
}

// What has just left: the real departures in the last twenty minutes, read
// straight from the schedule so they are not wrapped to the next night.
function ndGoneDeps(name){
  const now = nowNightSecs();
  const out = [];
  (ST_LINES[name] || []).forEach(ln => {
    const L = NET.lines[ln];
    if (!L || !L.stopmap || L.stations.indexOf(name) < 0) return;
    ndDirs(name, L).forEach(({ d, dest }) => {
      const sid = (L.stopmap[name] || [])[d];
      if (!sid) return;
      const trips = (SCHED[ln] && SCHED[ln][String(d)]) || [];
      trips.forEach(tr => {
        const da = tr[sid];
        if (da != null && da < now && da >= now - 1200)
          out.push({ route: ln, head: dest, dep: da, arr: null,
            mins: Math.round((da - now) / 60), live: false, m: null, passed: true });
      });
    });
  });
  out.sort((a, b) => a.dep - b.dep);
  return out.slice(-4);
}

// One arrival row, built in all.commute's shape (.nd-arow), with night's route
// colours and night's live annotation (the yellow arrival time + the wifi).
function ndArrowHTML(x){
  const c = LINE_COLORS[x.route] || "#5ad1ff";
  const cls = x.passed ? "" : (x.mins <= 0 ? "now" : (x.mins <= 5 ? "soon" : ""));
  const big = x.passed ? "−" + Math.abs(x.mins) : (x.mins <= 0 ? "now" : x.mins);
  const unit = x.passed ? "min ago" : (x.mins <= 0 ? "" : "min");
  const live = (x.m && typeof liveAt === "function") ? liveAt(x.m, x.dep) : "";
  return '<div class="nd-arow' + (x.passed ? " gone" : "") + '">' +
    '<span class="nd-rt" style="--r:' + c + '">' + esc(x.route) + '</span>' +
    '<span class="nd-od">' + esc(x.head || "—") +
      '<i>' + secClk(x.dep) + live + '</i></span>' +
    '<span class="nd-tm"><b class="' + cls + '">' + big + '</b>' +
      '<small>' + unit + '</small></span>' +
    '</div>';
}

function ndBoardHTML(name){
  const gone = ndGoneDeps(name);
  const coming = ndStationDeps(name).slice(0, 10);
  let html = "";
  if (gone.length) html += '<div class="nd-sec">just left</div>' + gone.map(ndArrowHTML).join("");
  html += '<div class="nd-sec">coming</div>';
  html += coming.length ? coming.map(ndArrowHTML).join("")
    : '<div class="nd-empty">' + ((SCHED && Object.keys(SCHED).length)
        ? "Nothing more on the night network from here."
        : "Live times appear once tonight's schedule has downloaded.") + '</div>';
  return html;
}

/* ---- the Street View photograph ---- */
function ndBearing(la1, lo1, la2, lo2){
  const t = Math.PI / 180;
  const y = Math.sin((lo2 - lo1) * t) * Math.cos(la2 * t);
  const x = Math.cos(la1 * t) * Math.sin(la2 * t) -
            Math.sin(la1 * t) * Math.cos(la2 * t) * Math.cos((lo2 - lo1) * t);
  return (Math.atan2(y, x) / t + 360) % 360;
}
// Face the way a passenger arrives, not the way the tram leaves: the heading to
// the next station on the line, turned around (+180), the same rule all.commute
// uses with its stored bearing.
function ndHeading(name){
  const lines = ST_LINES[name] || [];
  for (const ln of lines){
    const L = NET.lines[ln]; if (!L) continue;
    const i = L.stations.indexOf(name); if (i < 0) continue;
    const other = L.stations[i + 1] || L.stations[i - 1];
    const a = COORDS[name], b = other && COORDS[other];
    if (a && b) return (ndBearing(a[0], a[1], b[0], b[1]) + 180) % 360;
  }
  return null;
}
function ndSvUrl(name){
  if (!ND_KEY) return "";
  const c = COORDS[name]; if (!c) return "";
  const h = ndHeading(name);
  return "https://maps.googleapis.com/maps/api/streetview?size=640x260" +
    "&location=" + c[0] + "," + c[1] +
    (h != null ? "&heading=" + Math.round(h) : "") +
    "&fov=78&pitch=4&key=" + encodeURIComponent(ND_KEY);
}
// The photo did not load: no imagery at the stop, or -- the common case -- a
// Google key that is not authorised for the Street View Static API. Replace the
// WHOLE frame with the note, so the location pin and the 360 badge (both
// absolutely positioned inside it) do not collapse onto the card below and
// cover the WATCH button.
function ndSvFail(img){
  const w = img.closest(".nd-svwrap");
  if (w) w.outerHTML =
    '<div class="nd-svnone">No Street View here, or the Google key is not authorised for it.</div>';
}
function ndPhotoHTML(name){
  if (!ND_KEY_READY) return '<div class="nd-svnone">Loading the photograph…</div>';
  const url = ndSvUrl(name);
  if (!url) return '<div class="nd-svnone">Add a Google key in ⚙ to see the stop.</div>';
  return '<span class="nd-svwrap" data-pano="' + esc(name) + '">' +
    '<img class="nd-sv" src="' + esc(url) + '" alt="' + esc(name) + '" loading="lazy"' +
    ' onerror="ndSvFail(this)">' +
    '<span class="nd-svpin"><span class="nd-svpinlabel">' + esc(name) + '</span></span>' +
    '<span class="nd-sv360">◉ 360°</span></span>';
}

/* ---- the live 360 panorama, Google only, loaded on demand ---- */
function ndOpenPano(name){
  const c = COORDS[name]; if (!c) return;
  const ov = document.getElementById("ndPano");
  const view = document.getElementById("ndPanoView");
  document.getElementById("ndPanoName").textContent = name;
  view.innerHTML = '<div class="nd-panomsg">Loading the 360 view…</div>';
  ov.classList.add("show");
  document.body.classList.add("nd-panoopen");
  Promise.resolve(typeof GEng !== "undefined" && GEng.ensure ? GEng.ensure() : false)
    .then(ok => {
      if (!ok || !window.google || !google.maps){
        view.innerHTML = '<div class="nd-panomsg">A Google key is needed for the 360 view. Add one in ⚙.</div>';
        return;
      }
      const h = ndHeading(name);
      new google.maps.StreetViewService().getPanorama(
        { location: { lat: c[0], lng: c[1] }, radius: 70 },
        (data, status) => {
          if (status !== "OK" || !data || !data.location){
            view.innerHTML = '<div class="nd-panomsg">No 360 view at this stop.</div>';
            return;
          }
          view.innerHTML = "";
          new google.maps.StreetViewPanorama(view, {
            pano: data.location.pano,
            pov: { heading: (h != null ? h : 0), pitch: 4 }, zoom: 1,
            disableDefaultUI: true, addressControl: false, showRoadLabels: false,
            linksControl: true, motionTracking: false, motionTrackingControl: false });
        });
    });
}
function ndClosePano(){
  document.getElementById("ndPano").classList.remove("show");
  document.body.classList.remove("nd-panoopen");
  document.getElementById("ndPanoView").innerHTML = "";
}

/* ---- watching one station, and the bar at the bottom ---- */
function ndIsWatched(name){ return ND_WATCH === name; }
function ndSetWatch(name){
  ND_WATCH = name;
  try { localStorage.setItem("nc_watch", name); } catch (e) {}
  document.body.classList.add("nd-watching");
  updateNightWatchBar();
}
function ndClearWatch(){
  ND_WATCH = null;
  try { localStorage.removeItem("nc_watch"); } catch (e) {}
  document.body.classList.remove("nd-watching");
  if (ND_SEL){ ND_SIG = ""; renderNightDash(); }
}
function ndToggleWatch(name){
  if (ndIsWatched(name)) ndClearWatch(); else ndSetWatch(name);
  if (ND_SEL){ ND_SIG = ""; renderNightDash(); }
}
function updateNightWatchBar(){
  const bar = document.getElementById("ndWatchbar");
  if (!bar) return;
  if (!ND_WATCH){ document.body.classList.remove("nd-watching"); return; }
  document.body.classList.add("nd-watching");
  bar.style.setProperty("--c", LINE_COLORS[(ST_LINES[ND_WATCH] || [])[0]] || "#5ad1ff");
  const next = ndStationDeps(ND_WATCH).slice(0, 3);
  const rides = next.length ? next.map(x =>
    '<span class="nd-wride"><span class="nd-rt" style="--r:' +
      (LINE_COLORS[x.route] || "#5ad1ff") + '">' + esc(x.route) + '</span>' +
    '<span class="nd-m">' + (x.mins <= 0 ? "now" : x.mins + " min") + '</span>' +
    (x.live && typeof WIFI === "string" ? WIFI : "") + '</span>').join("")
    : '<span class="nd-wride">no night tram coming</span>';
  bar.innerHTML = '<span class="nd-wstar">★</span>' +
    '<span class="nd-wname">' + esc(ND_WATCH) + '</span>' +
    '<button class="nd-wx" id="ndWx" title="Stop watching">✕</button>' +
    '<span class="nd-wrides">' + rides + '</span>';
}

/* ---- from here / to here, which feed the journey planner ---- */
function ndSetJourney(which, name){
  if (!name) return;
  if (which === "from") FROM = name; else TO = name;
  const fi = document.getElementById("fromInput"), ti = document.getElementById("toInput");
  if (fi) fi.value = FROM || "";
  if (ti) ti.value = TO || "";
  if (typeof renderFavStrip === "function") renderFavStrip();
  computeRoute();
  if (typeof switchTab === "function") switchTab("plan");
  closeStationDash();
}

/* ---- the card, the header, the whole panel ---- */
function ndSubLine(name){
  const lines = ST_LINES[name] || [];
  let s = lines.length ? ("night tram " + lines.join(", ")) : "not on a night line";
  if (typeof liveUsable === "function" && liveUsable()) s += " · live";
  else if (typeof LIVE !== "undefined" && LIVE && LIVE.window === false)
    s += " · night trams start 23:50";
  return esc(s);
}
function ndBadgesHTML(name){
  return (ST_LINES[name] || []).map(ln =>
    '<span class="nd-badge" style="background:' + (LINE_COLORS[ln] || "#5ad1ff") + '">' +
    esc(ln) + '</span>').join("");
}
function ndCardHTML(name){
  const on = ndIsWatched(name);
  // The panel header already carries the station's name and lines, so the card
  // header is the watch control, as it is in all.commute, not the name again.
  return '<div class="nd-card' + (on ? " on" : "") + '">' +
    '<div class="nd-chead">' +
      '<span class="nd-cnm">' + (on ? "You are watching this stop" : "Watch this stop") +
        '<i>' + (on ? "it stays in the bar at the bottom of every tab"
                    : "its next trams stay in a bar at the bottom") + '</i></span>' +
      '<button class="nd-wbtn' + (on ? " on" : "") + '" data-watch="' + esc(name) + '">' +
        (on ? "WATCHING" : "WATCH") + '</button>' +
    '</div>' + ndPhotoHTML(name) +
    '<div class="nd-arr">' + ndBoardHTML(name) + '</div></div>' +
    '<div class="nd-acts">' +
      '<button class="nd-act' + (FROM === name ? " isset" : "") + '" data-journey="from">' +
        (FROM === name ? "★ From here" : "From here") + '</button>' +
      '<button class="nd-act' + (TO === name ? " isset" : "") + '" data-journey="to">' +
        (TO === name ? "★ To here" : "To here") + '</button>' +
    '</div>';
}
function renderNightDash(){
  const name = ND_SEL;
  if (!name) return;
  const dash = document.getElementById("ndDash");
  dash.style.setProperty("--c", LINE_COLORS[(ST_LINES[name] || [])[0]] || "#5ad1ff");
  document.getElementById("ndName").textContent = name;
  document.getElementById("ndSub").innerHTML = ndSubLine(name);
  document.getElementById("ndBadges").innerHTML = ndBadgesHTML(name);
  /* the body is rebuilt only when the station, the key or the watch changes, so
     a twenty-second refresh neither reloads the photograph nor moves the scroll */
  const sig = name + "|" + (ND_KEY_READY ? (ND_KEY ? "k" : "n") : "?") +
    "|" + (ndIsWatched(name) ? "w" : "") + "|" + (FROM === name ? "f" : "") +
    (TO === name ? "t" : "");
  const body = document.getElementById("ndBody");
  if (sig !== ND_SIG){
    ND_SIG = sig;
    const keep = body.scrollTop;
    body.innerHTML = ndCardHTML(name);
    body.scrollTop = keep;
  } else {
    const arr = body.querySelector(".nd-arr");
    if (arr) arr.innerHTML = ndBoardHTML(name);
  }
  updateNightWatchBar();
}
function openStationDash(name){
  if (!name) return;
  ND_SEL = name;
  ND_SIG = "";
  document.getElementById("ndDash").classList.add("show");
  document.body.classList.add("nd-dashopen");
  if (!ND_HIST){ try { history.pushState({ ndDash: 1 }, ""); ND_HIST = true; } catch (e) {} }
  renderNightDash();
  if (typeof liveWanted === "function" && liveWanted() && typeof livePoll === "function") livePoll();
  if (ND_TIMER) clearInterval(ND_TIMER);
  ND_TIMER = setInterval(renderNightDash, 20000);
}
function closeStationDash(fromBack){
  ND_SEL = null;
  document.getElementById("ndDash").classList.remove("show");
  document.body.classList.remove("nd-dashopen");
  if (ND_TIMER){ clearInterval(ND_TIMER); ND_TIMER = null; }
  if (!fromBack && ND_HIST){ ND_HIST = false; try { history.back(); } catch (e) {} }
  else ND_HIST = false;
}

/* ---- wiring, and the hooks into what is already there ---- */
(function(){
  const close = document.getElementById("ndClose");
  if (close) close.addEventListener("click", () => closeStationDash());
  const body = document.getElementById("ndBody");
  if (body) body.addEventListener("click", (e) => {
    const w = e.target.closest("[data-watch]");
    if (w){ ndToggleWatch(w.dataset.watch); return; }
    const j = e.target.closest("[data-journey]");
    if (j){ ndSetJourney(j.dataset.journey, ND_SEL); return; }
    const p = e.target.closest("[data-pano]");
    if (p){ ndOpenPano(p.dataset.pano); return; }
  });
  const bar = document.getElementById("ndWatchbar");
  if (bar) bar.addEventListener("click", (e) => {
    if (e.target.closest("#ndWx")){ ndClearWatch(); return; }
    if (ND_WATCH) openStationDash(ND_WATCH);
  });
  const pc = document.getElementById("ndPanoClose");
  if (pc) pc.addEventListener("click", ndClosePano);
  // The phone's back gesture closes the 360 view, then the dashboard, rather
  // than leaving the app. Guarded, because a page driven in a bare JS engine
  // (the mechanism test) has a window with no addEventListener, and a throw
  // here would take the rest of the script down with it.
  if (typeof window !== "undefined" && typeof window.addEventListener === "function")
    window.addEventListener("popstate", () => {
      const pano = document.getElementById("ndPano");
      if (pano && pano.classList.contains("show")) ndClosePano();
      if (ND_HIST){ ND_HIST = false; closeStationDash(true); }
    });
})();

// The key, for the photograph. Asked for once; the open dashboard redraws when
// the answer arrives.
fetch("gmaps-key", { cache: "no-store" }).then(r => r.json()).then(d => {
  ND_KEY = (d && d.key) || "";
  ND_KEY_READY = true;
  if (ND_SEL){ ND_SIG = ""; renderNightDash(); }
}).catch(() => { ND_KEY_READY = true; });

// A live poll just finished: an open dashboard and the watch bar both move with
// it, the same way the Plan legs and the map trams do.
const _liveDraw_beforeDash = (typeof liveDraw === "function") ? liveDraw : null;
if (_liveDraw_beforeDash) liveDraw = function(){
  _liveDraw_beforeDash();
  if (ND_SEL) renderNightDash();
  if (ND_WATCH) updateNightWatchBar();
};

// The network loads a moment after boot (and again when the real GTFS swaps in).
// The watch bar and any open dashboard are only meaningful once it is there.
const _loadNet_beforeDash = (typeof loadNet === "function") ? loadNet : null;
if (_loadNet_beforeDash) loadNet = async function(){
  await _loadNet_beforeDash();
  if (ND_WATCH){ document.body.classList.add("nd-watching"); updateNightWatchBar(); }
  if (ND_SEL){ ND_SIG = ""; renderNightDash(); }
};

if (ND_WATCH){ document.body.classList.add("nd-watching"); updateNightWatchBar(); }
