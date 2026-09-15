/* page_v10.js — night.commute v10's page, run the way the page runs it.
 *
 *     node tests/page_v10.js <artefact.sh>
 *
 * Both of v10's additions are here: the live feed, which says where the tram
 * is, and the star, which keeps a station where it can be found again.
 *
 * It does not copy any function into this file. It pulls night.html out of
 * the ARTEFACT, builds just enough browser around it, and drives the code
 * that ships. A test holding its own copy of a function tests the copy, and
 * the copy is the one thing that cannot be wrong in the field.
 *
 * The browser below is small but it is not a pretence: elements are kept by
 * id so the page is handed the same one twice, listeners are recorded so they
 * can be fired, and setting innerHTML parses the rows back out so
 * querySelectorAll finds them. That is what makes it possible to TAP a star
 * rather than to call the function a tap would have called, and the
 * difference between those two is the whole of Test 2's reason to exist.
 *
 * Prints one PASS or FAIL line per check, which test1_mechanism.sh counts.
 */
"use strict";
const fs = require("fs");

const art = fs.readFileSync(process.argv[2], "utf8");

/* ---- the page, out of the artefact ---- */
// Two heredocs deep: the night payload sits inside the umbrella's, and
// night.html inside the payload's. Both delimiters survive into the artefact
// verbatim, so the inner one is enough to find.
const html = art.split("cat > \"$APPDIR/night.html\" << 'NC_HTML'")[1];
if (!html) { console.log("FAIL night.html is not in the artefact"); process.exit(0); }
const page = html.split("\nNC_HTML\n")[0];
const script = page.split("<script>")[1].split("</script>")[0];

/* ---- the smallest browser the page will run in ---- */

// A row inside a container whose innerHTML was just written. Only the two
// classes the picker uses are parsed out, because they are the only ones
// anything here asks for.
function rowsFrom(html){
  const out = [];
  const re = /<(div|button)\s+class="([^"]*)"([^>]*)>/g;
  let m;
  while ((m = re.exec(html))) {
    const cls = m[2];
    if (!/\bsg-item\b|\bsg-star\b|\bfavchip\b|\blchk\b/.test(cls)) continue;
    const attrs = m[3] || "";
    const row = { cls: cls, dataset: {}, listeners: {} };
    const ar = /data-([a-z]+)="([^"]*)"/g;
    let a;
    while ((a = ar.exec(attrs))) row.dataset[a[1]] = a[2];
    row.addEventListener = (t, f) => { (row.listeners[t] = row.listeners[t] || []).push(f); };
    row.fire = (t, ev) => (row.listeners[t] || []).forEach(f => f(ev || mkEvent()));
    row.matches = sel => cls.split(/\s+/).indexOf(sel.replace(".", "")) !== -1;
    row.closest = sel => (row.matches(sel) ? row : null);
    out.push(row);
  }
  return out;
}
function mkEvent(target){
  return { preventDefault(){}, stopPropagation(){}, target: target || null, key: "" };
}

function el(id){
  const e = {
    id: id || "", _html: "", textContent: "", value: "", disabled: false,
    dataset: {}, rows: [], listeners: {}, classes: {},
    style: { setProperty(){}, removeProperty(){} },
    get innerHTML(){ return this._html; },
    set innerHTML(v){ this._html = String(v); this.rows = rowsFrom(this._html); },
    addEventListener(t, f){ (this.listeners[t] = this.listeners[t] || []).push(f); },
    removeEventListener(){},
    fire(t, ev){ (this.listeners[t] || []).forEach(f => f(ev || mkEvent())); },
    appendChild(){}, insertBefore(){}, remove(){},
    querySelector(){ return el(); },
    querySelectorAll(sel){ return this.rows.filter(r => r.matches(sel)); },
    setAttribute(){}, removeAttribute(){}, hasAttribute(){ return true; },
    getAttribute(){ return null; }, focus(){}, blur(){},
    closest(){ return el(); }, getElement(){ return el(); },
  };
  e.classList = {
    add: c => { e.classes[c] = 1; },
    remove: c => { delete e.classes[c]; },
    toggle: (c, on) => { if (on) e.classes[c] = 1; else delete e.classes[c]; },
    contains: c => !!e.classes[c],
  };
  e.parentNode = { insertBefore(){}, appendChild(){} };
  return e;
}

// One element per id, so the page and this test are looking at the same one.
const BY_ID = {};
function byId(id){ return (BY_ID[id] = BY_ID[id] || el(id)); }

// Real enough to lose a favourite across a reload, which is a thing worth
// being able to test.
const STORE = {};
const ctx = {
  console,
  // The page sets a one second clock and a ten second poll. Neither is wanted
  // here: the checks below drive the functions directly, and a live timer
  // would both keep node running forever and repaint between two assertions.
  setTimeout(){ return 0; }, clearTimeout(){},
  setInterval(){ return 0; }, clearInterval(){},
  document: {
    visibilityState: "visible",
    documentElement: el(),
    getElementById(id){ return byId(id); },
    querySelectorAll(){ return []; },
    createElement(){ return el(); },
    addEventListener(){},
    body: el(),
  },
  localStorage: {
    getItem(k){ return k in STORE ? STORE[k] : null; },
    setItem(k, v){ STORE[k] = String(v); },
    removeItem(k){ delete STORE[k]; },
  },
  // Nothing may reach the network from here. A test that quietly fetched the
  // real feed would pass or fail with Zagreb's trams, which is Test 2's job.
  fetch(){ return Promise.resolve({ json: () => ({}) }); },
  performance: { getEntriesByType(){ return []; } },
  getComputedStyle(){ return { getPropertyValue(){ return "#000000"; } }; },
};
ctx.window = ctx;
ctx.globalThis = ctx;

const EXPORTS = ["liveApproaching","liveRunSecs","liveEtaText","liveLegHtml",
                 "liveBarHtml","liveUsable","liveTrams","liveLocated","esc",
                 "isFav","toggleFav","favLive","favPick","renderFavStrip",
                 "searchStations","wireSearch"];
const epilogue = "\n;globalThis.__T={" +
  EXPORTS.map(n => n + ":" + n).join(",") +
  ",setLive(v){LIVE=v;},setErr(v){LIVE_ERR=v;},setNet(v){NET=v;}," +
  "setColors(v){Object.assign(LINE_COLORS,v);},setTab(v){TAB=v;}," +
  "setStations(s,l){STATIONS=s;ST_LINES=l;},setCoords(c){COORDS=c;}," +
  "setFrom(v){FROM=v;},setTo(v){TO=v;},from(){return FROM;},to(){return TO;}," +
  "fav(){return FAV;},starOn:STAR_ON,starOff:STAR_OFF};\n";

const vm = require("vm");
vm.createContext(ctx);
try {
  vm.runInContext(script + epilogue, ctx, {filename:"night.html"});
} catch (e) {
  console.log("FAIL the page did not evaluate: " + e.message);
  process.exit(0);
}
const T = ctx.__T;

/* ---- a small network to drive it with ----
 * Six stations in a line, west to east, a kilometre apart. Direction 0 runs
 * A to F, direction 1 runs F back to A. Every number below is chosen so the
 * right answer is arithmetic rather than opinion.
 */
const NAMES = ["A","B","C","D","E","F"];
const NET = { lines: { "33": {
  termA:"A", termB:"F", stations: NAMES,
  stopmap: Object.fromEntries(NAMES.map(n => [n, [n+"_0", n+"_1"]])),
}}};
T.setNet(NET);
T.setColors({"33":"#06d6a0"});
T.setTab("plan");
const ST_LINES = {};
NAMES.forEach(n => { ST_LINES[n] = ["33"]; });
T.setStations(NAMES.slice(), ST_LINES);
const COORDS = {};
NAMES.forEach((n, i) => { COORDS[n] = [45.80, 15.90 + i * 0.01]; });
T.setCoords(COORDS);

const NOW = 1789500000;
// Two minutes between stations in direction 0. Direction 1 is the same run
// measured along the same listed order, so it counts DOWN.
const RUN = { "33": { "0":[0,120,240,360,480,600], "1":[600,480,360,240,120,0] } };

function tram(o){
  return Object.assign({
    line:"33", trip:"t"+Math.random(), car:"100", dir:0, dir_src:"stops",
    towards:"F", lat:45.8, lon:15.98, pos_src:"gps", pos_age:5,
    near:"B", near_i:1, near_m:40, delay:null, ahead:{},
  }, o);
}
function feed(trams, over){
  return Object.assign({ ok:true, now:NOW, state:"live", age:6, entities:80,
    window:true, trams:trams, run:RUN, routes:["31","32","33","34"] }, over||{});
}

let pass = 0, fail = 0;
function is(label, want, got){
  if (String(want) === String(got)) { pass++; console.log("PASS " + label); }
  else { fail++; console.log("FAIL " + label + ": wanted [" + want + "] got [" + got + "]"); }
}

/* ---- the direction comparison, which is the whole of it ----
 * "Still behind me" is the opposite test in each direction, and getting it
 * backwards produces an app that confidently shows you the trams that have
 * already gone. Both sides of it, in both directions.
 */
T.setLive(feed([ tram({near_i:1, car:"behind"}) ]));
is("dir 0: a tram before me is coming", 1, T.liveApproaching("33","D","F").length);

T.setLive(feed([ tram({near_i:5, car:"past"}) ]));
is("dir 0: a tram past me is not", 0, T.liveApproaching("33","D","F").length);

T.setLive(feed([ tram({dir:1, towards:"A", near_i:5, car:"behind"}) ]));
is("dir 1: the comparison flips", 1, T.liveApproaching("33","C","A").length);

T.setLive(feed([ tram({dir:1, towards:"A", near_i:1, car:"past"}) ]));
is("dir 1: and a tram past me is still not", 0, T.liveApproaching("33","C","A").length);

T.setLive(feed([ tram({near_i:3}) ]));
is("a tram at my own stop counts as here", 1, T.liveApproaching("33","D","F").length);

/* ---- the boundary: exactly at my station, both directions ---- */
T.setLive(feed([ tram({near_i:3}) ]));
is("dir 0: zero stops away at my stop", 0, T.liveApproaching("33","D","F")[0].stops);
T.setLive(feed([ tram({dir:1, near_i:3}) ]));
is("dir 1: zero stops away at my stop", 0, T.liveApproaching("33","D","C")[0].stops);

/* ---- how far, and how long ---- */
T.setLive(feed([ tram({near_i:1}) ]));
const a = T.liveApproaching("33","D","F")[0];
is("three stations between B and D... is 2 stops", 2, a.stops);
is("and 4 minutes at two minutes a stop", 240, a.eta);
is("with no prediction it is an estimate", false, a.exact);

T.setLive(feed([ tram({dir:1, near_i:5}) ]));
const b = T.liveApproaching("33","C","A")[0];
is("dir 1 counts the same stops", 3, b.stops);
is("and the same subtraction comes out positive", 360, b.eta);

/* ---- ZET's own prediction wins where it has one ---- */
T.setLive(feed([ tram({near_i:1, ahead:{ "D_0": NOW + 90 }}) ]));
const c = T.liveApproaching("33","D","F")[0];
is("a prediction for my stop is used", 90, c.eta);
is("and it is exact, not an estimate", true, c.exact);

T.setLive(feed([ tram({near_i:1, ahead:{ "E_0": NOW + 90 }}) ]));
is("a prediction for somebody else's stop is not", 240, T.liveApproaching("33","D","F")[0].eta);

/* ---- been and gone ---- */
T.setLive(feed([ tram({near_i:1, ahead:{ "D_0": NOW - 600 }}) ]));
is("a tram that passed ten minutes ago is dropped", 0, T.liveApproaching("33","D","F").length);
T.setLive(feed([ tram({near_i:1, ahead:{ "D_0": NOW - 30 }}) ]));
is("one that passed thirty seconds ago is still shown", 1, T.liveApproaching("33","D","F").length);

/* ---- order ---- */
T.setLive(feed([ tram({near_i:0, car:"far"}), tram({near_i:2, car:"near"}) ]));
is("the closest tram is first", "near", T.liveApproaching("33","D","F")[0].t.car);

/* ---- what may not be drawn ---- */
T.setLive(feed([ tram({}) ], {state:"stale", age:2400}));
is("a stale feed offers no trams", 0, T.liveTrams().length);
is("and draws no rows", "", T.liveLegHtml("33","D","F"));
is("and is not usable", false, T.liveUsable());

T.setLive(feed([ tram({lat:null, lon:null, pos_src:"none", near:null, near_i:null}) ]));
is("a tram with no position is not placed", 0, T.liveApproaching("33","D","F").length);
is("but it is still a tram in the list", 1, T.liveTrams().length);

T.setLive(feed([ tram({line:"31"}) ]));
is("another line's tram is not mine", 0, T.liveApproaching("33","D","F").length);

/* ---- what the row says ---- */
T.setLive(feed([ tram({near_i:1, car:"460"}) ]));
let row = T.liveLegHtml("33","D","F");
is("the row names the car", true, /460/.test(row));
is("the row names where it is", true, /at B/.test(row));
is("an estimate wears a tilde", true, /~/.test(row));
is("an estimate is not called exact", false, /class="liverow"/.test(row) && !/est/.test(row));

T.setLive(feed([ tram({near_i:1, ahead:{ "D_0": NOW + 120 }}) ]));
row = T.liveLegHtml("33","D","F");
is("a real prediction wears no tilde", false, /~/.test(row));

T.setLive(feed([ tram({near_i:1, pos_src:"laststop", pos_age:200}) ]));
is("a guessed position says so", true, /estimated/.test(T.liveLegHtml("33","D","F")));

T.setLive(feed([]));
is("no tram broadcasting says exactly that", true,
   /no 33 is broadcasting/.test(T.liveLegHtml("33","D","F")));
T.setLive(feed([], {window:false}));
is("outside the service window it says that instead", true,
   /23:50/.test(T.liveLegHtml("33","D","F")));

/* ---- the strip counts what it cannot see ----
 * Four of eleven were unlocated on the night this was built. A strip that
 * says "seven trams" when there are eleven is the quiet kind of wrong.
 */
T.setLive(feed([ tram({}), tram({}), tram({lat:null, near_i:null}) ]));
const bar = T.liveBarHtml();
is("the strip counts the located", true, /<b>2<\/b>/.test(bar));
is("and admits the ones it cannot place", true, /1 not being located/.test(bar));

T.setLive(feed([], {state:"stale", age:3000}));
is("a stale strip gives the age in minutes", true, /50 min/.test(T.liveBarHtml()));
is("and says nothing is drawn from it", true, /nothing is drawn/.test(T.liveBarHtml()));

T.setLive(null); T.setErr("boom");
is("no feed at all is reported as such", true, /no live feed/.test(T.liveBarHtml()));
T.setErr("");

/* ---- minutes ---- */
is("zero seconds is now", "now", T.liveEtaText(0));
is("a tram already due is now, not -1 min", "now", T.liveEtaText(-40));
is("ninety seconds rounds to 2 min", "2 min", T.liveEtaText(90));
is("nothing known says nothing", "", T.liveEtaText(null));

/* ---- a station name is not markup ----
 * Station names come off ZET's feed and land in innerHTML. They are ordinary
 * Croatian today; they are still not to be trusted into the page unescaped.
 */
is("angle brackets are escaped", "&lt;b&gt;", T.esc("<b>"));
is("quotes are escaped", "&quot;", T.esc('"'));
is("nothing is the empty string, not the word null", "", T.esc(null));
T.setLive(feed([ tram({near_i:1, near:'<img src=x onerror=1>', car:"1"}) ]));
is("a hostile station name cannot open a tag", false,
   /<img/.test(T.liveLegHtml("33","D","F")));

/* =======================================================================
   THE STAR

   A station is kept by tapping the star beside it, and a kept station has
   to turn up in three places without being searched for. What is driven
   below is the picker itself: the star is TAPPED, through the listener the
   shipped page attached to it, rather than by calling what a tap calls.
   ======================================================================= */

is("nothing is starred to begin with", 0, T.fav().length);
is("and nothing claims to be", false, T.isFav("C"));

T.toggleFav("C");
is("a station can be kept", true, T.isFav("C"));
is("and it is written down", true, /"C"/.test(STORE["nc_fav"] || ""));
T.toggleFav("C");
is("and given up again", false, T.isFav("C"));
is("leaving nothing behind", 0, T.fav().length);

T.toggleFav("E"); T.toggleFav("B");
is("two can be kept at once", 2, T.fav().length);

// A schedule rebuild can rename or drop a station. The name stays in the
// store, so it comes back with its star if the station does, but nothing
// draws a station the network no longer has.
T.toggleFav("Nikola Tesla trg");
is("a station the network lost is still stored", 3, T.fav().length);
is("but it is not drawn", 2, T.favLive().length);
T.toggleFav("Nikola Tesla trg");

/* ---- kept stations come first in the picker ---- */
const ranked = T.searchStations("");
is("the kept ones are at the top", "B,E", ranked.slice(0, 2).join(","));
is("and the rest follow in their own order", "A,C,D,F", ranked.slice(2).join(","));
is("and none of them went missing", 6, ranked.length);

/* ---- the strip above the pickers ---- */
T.renderFavStrip();
let strip = BY_ID["favStrip"].innerHTML;
is("the strip names a kept station", true, /favchip[^>]*data-st="B"/.test(strip));
is("and the other one", true, /data-st="E"/.test(strip));

/* ---- one tap fills From, the next fills To ---- */
T.setFrom(""); T.setTo("");
T.favPick("B");
is("the first tap fills From", "B", T.from());
is("and leaves To alone", "", T.to());
T.favPick("E");
is("the second tap fills To", "E", T.to());
is("and From stays where it was", "B", T.from());
T.favPick("B");
is("a third tap starts again from From", "B", T.from());
is("and clears To rather than leaving a stale one", "", T.to());
// The same station cannot be both ends, which would plan a journey to
// where you already are.
T.setFrom("B"); T.setTo("");
T.favPick("B");
is("tapping the one already in From does not also fill To", "", T.to());

/* ---- the star in the picker, tapped for real ---- */
T.setFrom(""); T.setTo("");
T.wireSearch("fromInput", "fromSug", "from");
const inp = BY_ID["fromInput"], sug = BY_ID["fromSug"];
// The taps above left a station in the box, and the picker quite correctly
// filters to it. The list under test is the unfiltered one.
inp.value = "";
inp.fire("focus");
is("the picker drew its rows", 6, sug.querySelectorAll(".sg-item").length);
is("and every row carries a star", 6, sug.querySelectorAll(".sg-star").length);

function starFor(name){
  return sug.querySelectorAll(".sg-star").filter(s => s.dataset.st === name)[0];
}
is("a kept station wears the filled star", true,
   new RegExp('data-st="B"[^>]*>\\' + T.starOn).test(sug.innerHTML));
is("and the rest wear the hollow one", true,
   new RegExp('data-st="A"[^>]*>\\' + T.starOff).test(sug.innerHTML));
is("a kept row is marked as one", true, /class="sg-item fav"/.test(sug.innerHTML));

// Tapping the star keeps the station and must NOT also choose it. Getting
// this wrong sends you to the stop you were only trying to remember.
const before = T.from();
starFor("D").fire("mousedown");
is("tapping the star keeps the station", true, T.isFav("D"));
is("and does not choose it", before, T.from());
starFor("D").fire("mousedown");
is("tapping it again gives it up", false, T.isFav("D"));

// And the row itself still selects, which is what it always did.
const items = sug.querySelectorAll(".sg-item");
const firstName = T.searchStations("")[0];
items[0].fire("mousedown", mkEvent(null));
is("tapping the row still chooses the station", firstName, T.from());

// The guard is the target, not the coordinates: a tap whose target is the
// star is refused even when it arrives at the row.
T.setFrom("");
inp.value = "";
inp.fire("focus");
sug.querySelectorAll(".sg-item")[0].fire("mousedown",
  mkEvent({ closest: sel => (sel === ".sg-star" ? {} : null) }));
is("a tap that landed on a star never reaches the row", "", T.from());

/* ---- a name is not markup, here either ---- */
T.setStations(['<img src=x onerror=1>'], {'<img src=x onerror=1>': ["33"]});
inp.value = "";
inp.fire("focus");
is("a hostile station name cannot open a tag in the picker", false,
   /<img/.test(sug.innerHTML));
T.setStations(NAMES.slice(), ST_LINES);

console.log("COUNT " + pass + " " + fail);
// The page's own timers are stubbed out, but the boot code leaves a pending
// promise or two behind it. Nothing is waiting on them and the counts are
// printed, so this is the end.
process.exit(0);
