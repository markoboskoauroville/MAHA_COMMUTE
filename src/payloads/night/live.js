
/* ===========================================================================
   THE LIVE FEED, night.commute v10

   Spliced into night.html at build time. The server does the reading and the
   placing; everything here is about saying it on a phone screen at one in the
   morning without saying more than is known.

   THREE THINGS IT WILL NOT DO

   It will not draw a tram from a feed that has stopped. A stale feed is the
   common failure and it is invisible: the answer is the right size, the right
   shape, and forty minutes old. When that happens the trams come off the map
   and the strip says so, because an empty map is honest and a wrong tram is
   not.

   It will not turn a distance into a promise. Where ZET has a prediction for
   the stop being asked about, that is used. Where it has not, the minutes come
   from this app's own timetable and are written with a ~ in front of them, and
   the two never look alike.

   It will not quietly drop the trams it cannot place. Four of eleven were
   unlocated on the night this was built. They are counted on the strip, so
   "three trams" never means "three trams exist".
   =========================================================================== */

let LIVE = null;            // the last good answer
let LIVE_ERR = "";          // why there is no answer, if there is none
let LIVE_T = null;          // the poll timer
let LIVE_BUSY = false;      // one request in flight at a time
const LIVE_EVERY = 10000;   // ZET republishes about every ten seconds
const LIVE_MARKS = {};      // trip id -> the marker drawn for it

function liveWanted(){
  // Nothing is fetched for a page nobody is looking at. A phone in a pocket
  // polling a transit feed all night is a battery complaint, not a feature.
  return document.visibilityState !== "hidden" && (TAB === "plan" || TAB === "map");
}

async function livePoll(){
  if (LIVE_BUSY || !liveWanted()) return;
  LIVE_BUSY = true;
  try {
    const d = await fetch("live", {cache:"no-store"}).then(r=>r.json());
    if (d && d.ok){ LIVE = d; LIVE_ERR = ""; }
    else { LIVE_ERR = (d && d.reason) || "the feed did not answer"; if (d) LIVE = d; }
  } catch(e){
    LIVE_ERR = "the app could not reach its own server";
  } finally {
    LIVE_BUSY = false;
  }
  liveDraw();
}

// Whether anything may be drawn from what is held. "late" still draws, with
// the age shown; "stale" draws nothing at all.
function liveUsable(){
  return !!(LIVE && LIVE.ok && (LIVE.state === "live" || LIVE.state === "late" ||
                                LIVE.state === "ahead" || LIVE.state === "undated"));
}
function liveTrams(){ return liveUsable() ? (LIVE.trams || []) : []; }
function liveLocated(t){ return t.lat !== null && t.lat !== undefined; }

/* ---- the answer under a leg on the Plan tab ---- */

// Seconds from where the tram is to where you are, out of this app's own
// timetable. Positive means it has yet to reach you.
function liveRunSecs(ln, d, fromI, nearI){
  const run = LIVE && LIVE.run && LIVE.run[ln] && LIVE.run[ln][String(d)];
  if (!run) return null;
  const a = run[nearI], b = run[fromI];
  if (a === null || a === undefined || b === null || b === undefined) return null;
  return b - a;
}

// The trams on this line that are still behind you and coming your way.
function liveApproaching(ln, a, b){
  const d = dirIndex(ln, a, b);
  if (d < 0) return [];
  const sts = NET.lines[ln].stations, fromI = sts.indexOf(a);
  if (fromI < 0) return [];
  const L = NET.lines[ln];
  const myStop = (L.stopmap && L.stopmap[a]) ? L.stopmap[a][d] : "";
  const out = [];
  liveTrams().forEach(t=>{
    if (t.line !== ln || t.dir !== d || !liveLocated(t) || t.near_i < 0) return;
    // Direction 0 runs up the listed order and direction 1 runs back down it,
    // so "still behind me" is the opposite comparison in each.
    const behind = d === 0 ? (t.near_i <= fromI) : (t.near_i >= fromI);
    if (!behind) return;
    const stops = Math.abs(fromI - t.near_i);
    let eta = null, exact = false;
    const pred = myStop && t.ahead ? t.ahead[myStop] : null;
    if (pred){ eta = pred - LIVE.now; exact = true; }
    else {
      const r = liveRunSecs(ln, d, fromI, t.near_i);
      if (r !== null) eta = r;
    }
    if (eta !== null && eta < -90) return;     // it has been and gone
    out.push({t:t, stops:stops, eta:eta, exact:exact});
  });
  out.sort((x,y)=>(x.eta===null?1e9:x.eta)-(y.eta===null?1e9:y.eta));
  return out;
}

function liveEtaText(eta){
  if (eta === null) return "";
  const m = Math.round(eta/60);
  return m <= 0 ? "now" : m + " min";
}

function liveLegHtml(ln, a, b){
  // No feed, or a feed too old to draw from: the scheduled times stand on
  // their own and nothing is added. The Map tab's strip is where the reason
  // is given, once, rather than under every leg.
  if (!liveUsable()) return '';
  const app = liveApproaching(ln, a, b);
  const c = LINE_COLORS[ln] || "#5ad1ff";
  if (!app.length){
    // Silence here would read as "none coming", which is a claim. Outside the
    // service window there is nothing to be sorry about, and inside it the
    // right answer is that nothing is broadcasting, not that nothing is running.
    const why = LIVE.window ? "no " + ln + " is broadcasting on this stretch"
                            : "the night trams start at 23:50";
    return '<div class="livenone">' + why + '</div>';
  }
  let html = '<div class="livewrap" style="--lc:' + c + '">';
  app.slice(0,2).forEach(x=>{
    const t = x.t;
    const where = t.near
      ? (x.stops === 0 ? "at " + esc(t.near)
                       : "at " + esc(t.near) + ", " + x.stops + " stop" + (x.stops>1?"s":"") + " away")
      : "somewhere on the line";
    const guess = t.pos_src !== "gps";
    html += '<div class="liverow' + (x.exact ? '' : ' est') + '">' +
      '<span class="lvdot' + (LIVE.state === "late" ? ' flat' : '') + '"></span>' +
      '<span class="lvcar">' + (t.car ? esc(t.car) : ln) + '</span>' +
      '<span class="lvwhere">' + where + (guess ? ' <i>(estimated)</i>' : '') + '</span>' +
      '<span class="lveta">' + (x.exact ? '' : '~') + liveEtaText(x.eta) + '</span>' +
      '</div>';
  });
  html += '</div>';
  return html;
}

function esc(s){ return String(s == null ? "" : s)
  .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;"); }

/* ---- the wifi mark, and the real time beside the scheduled one ----------
   Byte for byte the mark day.commute uses, and for the same reason: it says
   this vehicle is broadcasting its position now. One family, one symbol, so
   it is learned once and read in both apps.

   The yellow time beside the scheduled one is when that tram will actually
   reach your stop, and the number after it is how far off its timetable it is
   running. day.commute's colours, unchanged: yellow for a live time, red for
   a delay in either direction, grey for dead on time. */
const WIFI = '<svg class="wifi" width="14" height="11" viewBox="0 0 16 12" ' +
  'xmlns="http://www.w3.org/2000/svg">' +
  '<circle cx="8" cy="10" r="1.2" fill="#3fb950"/>' +
  '<path d="M4.8 7.2a4.5 4.5 0 0 1 6.4 0" fill="none" stroke="#3fb950" ' +
  'stroke-width="1.5" stroke-linecap="round"/>' +
  '<path d="M2.6 4.8a7.6 7.6 0 0 1 10.8 0" fill="none" stroke="#3fb950" ' +
  'stroke-width="1.5" stroke-linecap="round"/></svg>';

// Twelve minutes. The night trams run about every fifty, so a tram within
// twelve minutes of a scheduled slot is that slot's tram and nothing else is
// near it. A tram further out than this gets NO mark rather than a guessed
// one: the wifi has to mean "this is that tram", and a wrong pairing writes a
// live time against the wrong departure, which is worse than leaving the row
// exactly as the timetable had it.
const MATCH_WINDOW = 720;

// Pair each scheduled row with at most one live tram and each tram with at
// most one row. They are paired IN ORDER: the next tram to reach you is the
// next departure, the one behind it is the one after that. Both lists are
// already sorted, the trams by how soon they arrive and the rows by when they
// are due, so this is one walk down the two of them.
//
// The obvious alternative, giving each row whichever tram lands closest to
// its scheduled time, was written first and is wrong in the case that
// matters. Two trams, four minutes and two minutes away, one scheduled
// departure between them: closest-by-time hands the mark to the FOUR minute
// tram, because it happens to sit nearer the timetable, and leaves the tram
// you are about to catch unmarked. Order pairing gives it to the two minute
// one, which is the tram on the platform.
//
// A row no tram lines up with keeps nothing, and that tram stays available
// for the row after it.
function liveMatchRows(ln, a, b, rows){
  const out = rows.map(() => null);
  if (!liveUsable() || !rows || !rows.length) return out;
  const app = liveApproaching(ln, a, b);
  if (!app.length) return out;

  const nowS = nowNightSecs();
  let ri = 0;
  for (let i = 0; i < app.length && ri < rows.length; i++) {
    const x = app[i];
    if (x.eta === null) continue;
    const at = nowS + x.eta;
    // A row this tram is already well past belongs to no tram at all.
    while (ri < rows.length && rows[ri].dep < at - MATCH_WINDOW) ri++;
    if (ri >= rows.length) break;
    if (Math.abs(at - rows[ri].dep) <= MATCH_WINDOW) {
      out[ri] = {tram: x.t, at: at, eta: x.eta, exact: x.exact};
      ri++;
    }
    // Too early for this row: leave it for the tram behind this one, which
    // is running later and therefore lands nearer to it.
  }
  return out;
}

// What is written into a scheduled row that has a tram behind it.
//
// THE YELLOW TIME IS WHEN THE TRAM REACHES YOUR STOP. It is not when it
// leaves, and on a timetabled service those are not the same thing.
//
// Measured against the real feed at 02:12: car 325, three stops out, reaching
// Središće at 02:16 against a scheduled 02:28. The first version wrote that
// as "-12" and it was wrong. A night tram running ahead of its slot does not
// leave twelve minutes early, it arrives and WAITS, because the whole network
// is four trams on a fifty minute timetable and nothing is allowed to drift.
//
// So a delay is only ever shown when the tram is LATE, which is the case
// where the departure really does move. Early is not a delay, it is a tram
// already standing there, and the yellow time says so on its own.
function liveAt(m, schedDep){
  const d = Math.round((m.at - schedDep) / 60);
  const dtxt = d >= 2 ? ' <span class="le-d">+' + d + '</span>'
             : d >= -1 ? ' <span class="le-ok">±0</span>'
             : '';
  return ' <span class="le-t">' + secClk(m.at) + '</span>' + dtxt + WIFI;
}

// The countdown counts to the moment the tram can actually take you, which is
// the later of the two: a late tram leaves when it arrives, and an early one
// waits for its scheduled departure. Counting to the arrival of an early tram
// would say "5 min" about a tram that does not leave for sixteen.
function liveMins(m, u){
  return m ? Math.round((Math.max(m.at, u.dep) - nowNightSecs()) / 60) : u.min;
}

/* ---- the strip, which says what state the feed is in ---- */
function liveBarHtml(){
  if (LIVE_ERR && !liveUsable())
    return '<div class="livebar bad"><span class="lvdot flat"></span>' +
           'no live feed &middot; ' + esc(LIVE_ERR) + '</div>';
  if (!LIVE)
    return '<div class="livebar"><span class="lvdot flat"></span>reading the ZET feed&hellip;</div>';
  if (LIVE.state === "stale")
    return '<div class="livebar bad"><span class="lvdot flat"></span>' +
           'the ZET feed stopped <b>' + Math.round(LIVE.age/60) + ' min</b> ago &middot; ' +
           'nothing is drawn from it</div>';
  if (LIVE.state === "unreachable")
    return '<div class="livebar bad"><span class="lvdot flat"></span>' +
           'the ZET feed did not answer</div>';

  const trams = liveTrams();
  const located = trams.filter(liveLocated).length;
  const lost = trams.length - located;
  const cls = LIVE.state === "late" ? " warn" : "";
  let html = '<div class="livebar' + cls + '">' +
    '<span class="lvdot' + (LIVE.state === "late" ? ' flat' : '') + '"></span>' +
    '<b>' + located + '</b>&nbsp;night tram' + (located === 1 ? '' : 's') + ' on the map';
  if (lost) html += ' <span class="lvlost">&middot; ' + lost + ' not being located</span>';
  html += '<span class="lvspacer"></span>';
  html += (LIVE.age === null || LIVE.age === undefined)
    ? 'undated'
    : (LIVE.age <= 90 ? 'feed <b>' + Math.max(0,LIVE.age) + 's</b> old'
                      : 'feed <b>' + Math.round(LIVE.age/60) + ' min</b> old');
  html += '</div>';
  if (!trams.length && LIVE.window)
    html += '<div class="livenone" style="margin-left:0">ZET is publishing ' +
            LIVE.entities + ' vehicles, none of them a night tram yet.</div>';
  return html;
}

/* ---- the trams, on the map ---- */
function liveDrawMap(){
  if (!MAP || TAB !== "map") return;
  const E = theEng();
  if (!E.vehicle) return;
  const want = {};
  liveTrams().forEach(t=>{
    if (!liveLocated(t)) return;
    want[t.trip] = 1;
    const c = LINE_COLORS[t.line] || "#5ad1ff";
    const guess = t.pos_src !== "gps";
    const title = t.line + (t.car ? " · car " + t.car : "") +
      (t.towards ? " → " + t.towards : "") +
      (t.near ? " · at " + t.near : "") +
      (guess ? " · estimated position" : "");
    const mk = LIVE_MARKS[t.trip];
    if (mk) E.vehicleMove(mk, [t.lat, t.lon], title);
    else LIVE_MARKS[t.trip] = E.vehicle([t.lat, t.lon], c, t.line, title, guess);
  });
  // A tram that has left the feed has to leave the map with it, or the map
  // slowly fills with trams that finished their run an hour ago.
  Object.keys(LIVE_MARKS).forEach(k=>{
    if (!want[k]){ try{ E.remove(LIVE_MARKS[k]); }catch(e){} delete LIVE_MARKS[k]; }
  });
}
function liveClearMap(){
  const E = theEng();
  Object.keys(LIVE_MARKS).forEach(k=>{
    try{ E.remove(LIVE_MARKS[k]); }catch(e){}
    delete LIVE_MARKS[k];
  });
}

function liveDraw(){
  const bar = document.getElementById("liveBar");
  if (bar) bar.innerHTML = liveBarHtml();
  if (TAB === "map") liveDrawMap();
  if (TAB === "plan" && FROM && TO) computeRoute();
  if (TAB === "map" && MAP_A && MAP_B) computeRoute("mapResult");
}

/* ---- the two map engines learn to draw a vehicle ---- */
GEng.vehicle = function(c, color, label, title, guess){
  const mk = new google.maps.Marker({
    map: MAP, position:{lat:c[0], lng:c[1]}, title:title, zIndex:900,
    icon:{ path: google.maps.SymbolPath.CIRCLE, scale:11,
           fillColor: guess ? "#0b0f1a" : color, fillOpacity: guess ? .55 : 1,
           strokeColor: color, strokeWeight: guess ? 2 : 3 },
    label:{ text:String(label), color: guess ? color : "#0b0f1a",
            fontSize:"11px", fontWeight:"800" },
  });
  return mk;
};
GEng.vehicleMove = function(h, c, title){
  h.setPosition(new google.maps.LatLng(c[0], c[1]));
  if (title) h.setTitle(title);
};
LEng.vehicle = function(c, color, label, title, guess){
  const icon = L.divIcon({ className:"", iconSize:[0,0],
    html:'<div class="tram' + (guess ? ' guess' : '') + '" style="--c:' + color + '">' +
         String(label) + '</div>' });
  const mk = L.marker([c[0], c[1]], {icon:icon, zIndexOffset:900, interactive:true});
  mk.bindTooltip(title);
  mk.addTo(MAP);
  return mk;
};
LEng.vehicleMove = function(h, c, title){
  h.setLatLng([c[0], c[1]]);
  if (title && h.getTooltip()) h.setTooltipContent(title);
};

/* ---- wiring, all of it by wrapping what is already there ---------------
   Nothing above this line is called by the v9 page, so every entry point is
   taken by wrapping the function that already existed. It keeps the whole
   feature in one block that can be lifted out, and it means a night.commute
   v11 that rewrites one of these is a build failure rather than a silence. */

const _legHtml_sched = legHtml;
legHtml = function(ln, a, b, markNext){
  return _legHtml_sched(ln, a, b, markNext) + liveLegHtml(ln, a, b);
};

const _initMap_base = initMap;
initMap = async function(){
  await _initMap_base();
  if (MAP) liveDrawMap();
};

const _resetMap_base = resetMap;
resetMap = function(){
  liveClearMap();
  _resetMap_base();
};

const _switchTab_base = switchTab;
switchTab = function(t){
  _switchTab_base(t);
  liveDraw();
  if (liveWanted()) livePoll();
};

// The strip goes above the line checklist on the Map tab, and the map is the
// one place it belongs: it is about what is on the map.
(function(){
  const checks = document.getElementById("lineChecks");
  if (!checks || !checks.parentNode) return;
  const bar = document.createElement("div");
  bar.id = "liveBar";
  checks.parentNode.insertBefore(bar, checks);
})();

document.addEventListener("visibilitychange", ()=>{ if (liveWanted()) livePoll(); });
LIVE_T = setInterval(livePoll, LIVE_EVERY);
livePoll();
