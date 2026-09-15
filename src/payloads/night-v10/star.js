
/* ===========================================================================
   FAVOURITE STATIONS, night.commute v10

   A star on a station you chose, and the stations you starred gathered where
   you can reach them without searching.

   WHY THIS STAR IS NOT THE ONE THAT WAS TAKEN OFF all.commute

   all.commute put a star on EVERY station. That made the star mean "a station
   is here", which the number and the name already said, and it left nothing
   to mean "this is one of mine". It was removed, twice, and rightly.

   This star is the opposite: it is only ever on a station the person put it
   on. A mark that everything wears says nothing; a mark that four stations
   out of a hundred and eight wear says exactly one thing.

   WHERE IT HAS TO WORK

   Finding a station is the slow part of this app at one in the morning: a
   hundred and eight names, typed with a thumb. So a favourite earns its keep
   in three places and they are all the same idea. It sits at the TOP of the
   picker, so scrolling finds it first. It sits on a ROW OF CHIPS above the
   pickers, so the common trip needs no search at all. And it is starred on
   the MAP whether or not its line is switched on, so "where is my stop"
   is answered by looking rather than by hunting.

   WHAT IS STORED, AND WHAT SURVIVES

   The names, in localStorage, under nc_fav. Names rather than stop ids,
   because ZET renumbers stops between schedule builds and this list has to
   outlive that. A name that stops existing is kept in the store and simply
   not drawn, so a station that comes back after a rebuild brings its star
   with it.

   It is never cleared on a new run. night.commute resets nothing, because
   everything it keeps is either a preference or the person's own work, and
   a list somebody built by hand is the second of those.
   =========================================================================== */

const STAR_ON = "★";      // filled: this one is mine
const STAR_OFF = "☆";     // hollow: it could be
const FAV_MARKS = {};          // station name -> the star drawn on the map

let FAV = [];
try { FAV = JSON.parse(localStorage.getItem("nc_fav") || "[]") || []; } catch(e){ FAV = []; }
if (!Array.isArray(FAV)) FAV = [];

function saveFav(){ try { localStorage.setItem("nc_fav", JSON.stringify(FAV)); } catch(e){} }
function isFav(s){ return FAV.indexOf(s) !== -1; }

function toggleFav(s){
  if (!s) return;
  const i = FAV.indexOf(s);
  if (i === -1) FAV.push(s); else FAV.splice(i, 1);
  saveFav();
  renderFavStrip();
  favDrawMap();
}

// The stored list can outlive a schedule rebuild that renamed or dropped a
// station. Those stay in the store and are simply not drawn, so nothing is
// thrown away on the person's behalf.
function favLive(){ return FAV.filter(s => ST_LINES && ST_LINES[s]); }

/* ---- the chips, above the pickers ---- */

// Taps cycle: the first fills From, the second fills To, the next starts
// again. One rule, no modes, and it corrects itself if you tap the wrong one.
function favPick(s){
  if (!FROM) FROM = s;
  else if (!TO && s !== FROM) TO = s;
  else { FROM = s; TO = ""; }
  const fi = document.getElementById("fromInput"), ti = document.getElementById("toInput");
  if (fi) fi.value = FROM || "";
  if (ti) ti.value = TO || "";
  renderFavStrip();
  computeRoute();
}

function renderFavStrip(){
  const box = document.getElementById("favStrip");
  if (!box) return;
  const live = favLive();
  if (!live.length){
    // Said once, where the feature is, rather than in a help screen nobody
    // opens. It disappears the moment there is a first favourite.
    box.innerHTML = '<div class="favhint">Tap ' + STAR_OFF +
      ' beside a station to keep it here.</div>';
    return;
  }
  box.innerHTML = '<div class="favrow">' + live.map(s =>
    '<button class="favchip' + (s === FROM ? " isfrom" : s === TO ? " isto" : "") +
    '" data-st="' + esc(s) + '">' + STAR_ON + ' ' + esc(s) +
    (s === FROM ? '<i>from</i>' : s === TO ? '<i>to</i>' : '') + '</button>').join("") + '</div>';
  box.querySelectorAll(".favchip").forEach(b =>
    b.addEventListener("click", () => favPick(b.dataset.st)));
}

/* ---- the star on the map ----
 * Drawn whether or not the station's line is switched on. The map opens
 * empty on purpose, and a favourite is the one thing worth seeing on an
 * empty map: it is where you are going.
 */
function favDrawMap(){
  if (!MAP) return;
  const E = theEng();
  if (!E.favourite) return;
  const want = {};
  favLive().forEach(s => {
    const c = COORDS[s];
    if (!c) return;
    want[s] = 1;
    if (!FAV_MARKS[s]) FAV_MARKS[s] = E.favourite(c, s);
  });
  Object.keys(FAV_MARKS).forEach(s => {
    if (!want[s]){ try { E.remove(FAV_MARKS[s]); } catch(e){} delete FAV_MARKS[s]; }
  });
}
function favClearMap(){
  const E = theEng();
  Object.keys(FAV_MARKS).forEach(s => {
    try { E.remove(FAV_MARKS[s]); } catch(e){}
    delete FAV_MARKS[s];
  });
}

GEng.favourite = function(c, name){
  return new google.maps.Marker({
    map: MAP, position:{lat:c[0], lng:c[1]}, title: name + " · favourite", zIndex: 800,
    icon:{ path:"M 0,-11 L 3.2,-3.6 L 11,-3.4 L 4.9,1.4 L 7,8.9 L 0,4.6 L -7,8.9 L -4.9,1.4 "
                + "L -11,-3.4 L -3.2,-3.6 Z",
           fillColor:"#ffb454", fillOpacity:1, strokeColor:"#0b0f1a", strokeWeight:2, scale:1 },
  });
};
LEng.favourite = function(c, name){
  const mk = L.marker([c[0], c[1]], {zIndexOffset:800, interactive:true, icon: L.divIcon({
    className:"", iconSize:[0,0], html:'<div class="favmark">' + STAR_ON + '</div>' })});
  mk.bindTooltip(name + " · favourite");
  mk.addTo(MAP);
  return mk;
};

/* ---- favourites first in the picker ----
 * The order inside each group is left exactly as the search produced it, so
 * what changes is which group you read first, not how well the search works.
 */
const _searchStations_ranked = searchStations;
searchStations = function(q){
  const list = _searchStations_ranked(q);
  if (!FAV.length) return list;
  const mine = [], rest = [];
  list.forEach(s => (isFav(s) ? mine : rest).push(s));
  return mine.concat(rest);
};

const _initMap_beforeFav = initMap;
initMap = async function(){
  await _initMap_beforeFav();
  if (MAP) favDrawMap();
};
const _resetMap_beforeFav = resetMap;
resetMap = function(){
  favClearMap();
  _resetMap_beforeFav();
};

/* ---- the strip goes above the From picker, which is where you start ---- */
(function(){
  const plan = document.getElementById("tab-plan");
  if (!plan) return;
  const first = plan.querySelector(".picker");
  if (!first) return;
  const strip = document.createElement("div");
  strip.id = "favStrip";
  strip.className = "favstrip";
  first.parentNode.insertBefore(strip, first);
  renderFavStrip();
})();
