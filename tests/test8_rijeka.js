/* test8_rijeka.js, Rijeka beside Zagreb on one map (v52).
 *
 *   node tests/test8_rijeka.js <base-url> <leaflet-dir> [chrome-or-firefox]
 *
 * Runs against a REAL all.commute server (the phone's own on :8084 is the
 * intended one), because what it proves is that Autotrolej's live data reaches
 * the page: a person standing on Korzo sees Rijeka's stations, taps one, and
 * gets a board with Rijeka lines on it. Then that Zagreb is unchanged, and
 * that the City button carries a person in Zagreb to Rijeka.
 *
 * Prints PASS or FAIL per check; exits 1 on any FAIL.
 */
const { chromium, firefox } = require("playwright-core");
const [base, leaflet, exe] = process.argv.slice(2);
const fails = [];
const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) fails.push(n); };
const KORZO = { latitude: 45.3271, longitude: 14.4422, accuracy: 10 };
const ZG = { latitude: 45.8052, longitude: 15.9805, accuracy: 10 };

async function open(b, where, storage){
  const ctx = await b.newContext({ viewport: { width: 390, height: 780 },
    geolocation: where, permissions: ["geolocation"], storageState: storage });
  const page = await ctx.newPage();
  const errors = [], asked = [];
  page.on("pageerror", e => errors.push(e.message));
  await page.route("**/*", route => {
    const u = route.request().url();
    if (u.includes("leaflet@1.9.4/dist/leaflet.css")) return route.fulfill({ path: leaflet + "/leaflet.css", contentType: "text/css" });
    if (u.includes("leaflet@1.9.4/dist/leaflet.js")) return route.fulfill({ path: leaflet + "/leaflet.js", contentType: "application/javascript" });
    if (u.startsWith(base)) { asked.push(u.slice(base.length)); return route.continue(); }
    return route.abort();                       // no tiles, no Google: the test is about stations
  });
  await page.goto(base + "/all.html?run=test8");
  return { ctx, page, errors, asked };
}
const until = async (page, fn, ms) => {
  try { await page.waitForFunction(fn, null, { timeout: ms, polling: 250 }); return true; } catch (e) { return false; }
};

(async () => {
  // Chromium dies on a silent CHECK (SIGTRAP) inside PRoot on the phone; Firefox runs there.
  // Pass whichever browser the machine can run: the engine follows the path.
  const ff = /firefox/i.test(exe || "");
  const b = await (ff ? firefox : chromium).launch({ executablePath: exe,
    args: ff ? [] : ["--no-sandbox"] });

  // 1. standing on Korzo, first visit, nothing in the browser yet
  const R = await open(b, KORZO);
  const gotRj = await until(R.page, () => STATION_SET.rijeka.list.length > 500, 45000);
  check("Rijeka's stations reach the page (" + await R.page.evaluate(() => STATION_SET.rijeka.list.length) + ")", gotRj);
  const near = await until(R.page, () => STOPS.length > 0 && STOPS.every(s => stopCity(s) === "rijeka"), 20000);
  const st = await R.page.evaluate(() => STOPS.map(s => s.stop_id + " " + s.name + " " + s.dist + "m"));
  check("on Korzo the stations around you are Rijeka's (" + st.slice(0, 3).join(" | ") + ")", near);
  check("the nearest is within 300 m", await R.page.evaluate(() => STOPS[0] && STOPS[0].dist < 300));
  const boards = await until(R.page, () => STOPS.length && BOARDS[STOPS[0].stop_id] && BOARDS[STOPS[0].stop_id].city === "rijeka", 30000);
  check("the board of the nearest was asked of Rijeka, not Zagreb", boards);
  check("every board request carried city=rijeka",
    R.asked.filter(u => u.startsWith("/board")).every(u => u.includes("city=rijeka")) && R.asked.some(u => u.startsWith("/board")));
  // tap a Rijeka label that has rides coming
  const pick = await R.page.evaluate(() => {
    const s = STOPS.find(x => BOARDS[x.stop_id] && (BOARDS[x.stop_id].departures || []).some(d => !d.passed));
    return s ? s.stop_id : (STOPS[0] && STOPS[0].stop_id);
  });
  const lbl = R.page.locator(".pin .pinid span", { hasText: new RegExp("^" + pick + "\\b") }).first();
  let tapped = false;
  if (await lbl.count()) { await lbl.click({ timeout: 5000 }).then(() => { tapped = true; }).catch(() => {}); }
  if (!tapped) await R.page.evaluate(id => openPop(STOPS.find(s => s.stop_id === id)), pick);
  await until(R.page, () => document.getElementById("dash").classList.contains("show"), 5000);
  await R.page.waitForTimeout(2500);
  const dash = await R.page.evaluate(() => ({ on: document.getElementById("dash").classList.contains("show"),
    id: document.getElementById("dId").textContent, text: document.getElementById("dash").innerText,
    deps: (BOARDS[SEL && SEL.stop_id] || {}).departures || [] }));
  check("tapping label " + pick + (tapped ? "" : " (label off screen, opened directly)") + " opens its dashboard", dash.on && dash.id === pick);
  const hour = new Date().getHours();
  const service = hour >= 5 && hour < 23;
  const lines = [...new Set(dash.deps.map(d => d.route))];
  check("the dashboard carries Rijeka departures" + (service ? "" : " (night: none expected)") +
    " — lines " + lines.slice(0, 8).join(","), service ? dash.deps.length > 0 : true);
  check("and a departure's line is written on the dashboard",
    !dash.deps.length || dash.text.includes(dash.deps[0].route));
  const saved = await R.page.evaluate(() => { try { return Object.keys(JSON.parse(localStorage.getItem("ac2_stations_rj")).stops).length; } catch (e) { return 0; } });
  check("Rijeka's copy is kept in the browser (" + saved + ")", saved > 500);
  check("no script error in Rijeka", R.errors.length === 0 || (console.log("   " + R.errors.join("\n   ")), false));
  const storage = await R.ctx.storageState();
  await R.ctx.close();

  // 2. second visit with the server refusing everything but the page: drawn from the copy
  const ctx2 = await b.newContext({ viewport: { width: 390, height: 780 }, geolocation: KORZO,
    permissions: ["geolocation"], storageState: storage });
  const p2 = await ctx2.newPage();
  await p2.route("**/*", route => {
    const u = route.request().url();
    if (u.includes("leaflet@1.9.4/dist/leaflet.css")) return route.fulfill({ path: leaflet + "/leaflet.css", contentType: "text/css" });
    if (u.includes("leaflet@1.9.4/dist/leaflet.js")) return route.fulfill({ path: leaflet + "/leaflet.js", contentType: "application/javascript" });
    if (u.includes("/all.html")) return route.continue();
    return route.abort();
  });
  await p2.goto(base + "/all.html?run=test8b");
  const offline = await until(p2, () => STOPS.length > 0 && STOPS.every(s => stopCity(s) === "rijeka"), 15000);
  check("with no server, Rijeka's stations still draw from the browser's copy", offline);
  await ctx2.close();

  // 3. Zagreb is unchanged
  const Z = await open(b, ZG, storage);
  const zg = await until(Z.page, () => STOPS.length > 0 && STOPS.every(s => stopCity(s) === "zagreb"), 25000);
  check("in Zagreb the stations are ZET's (" + await Z.page.evaluate(() => STOPS.slice(0, 3).map(s => s.stop_id).join(",")) + ")", zg);
  const zb = await until(Z.page, () => STOPS.length && BOARDS[STOPS[0].stop_id] && BOARDS[STOPS[0].stop_id].ok && !BOARDS[STOPS[0].stop_id].city, 30000);
  // a Rijeka station watched in part 1 is still watched, and rightly still asks Rijeka;
  // what must hold is that no ZET station's board carries a city
  const zAsk = Z.asked.filter(u => u.startsWith("/board"));
  const wrong = zAsk.filter(u => /stop=[^&]*_/.test(u) && u.includes("city="));
  check("and their boards come from ZET, with no city parameter (" + zAsk.length + " asked" +
    (wrong.length ? ", wrong: " + wrong.slice(0, 2).join(" ") : "") + ")",
    zb && zAsk.some(u => /stop=[^&]*_/.test(u)) && wrong.length === 0);
  check("the Rijeka station watched in part 1 still asks Rijeka for its board",
    zAsk.filter(u => /stop=\d+&/.test(u)).every(u => u.includes("city=rijeka")));

  // 4. the City button carries a person in Zagreb to Rijeka, and back
  await Z.page.click("#btnSet").catch(() => {});
  await Z.page.evaluate(() => document.getElementById("cityRj").click());
  const jumped = await until(Z.page, () => STOPS.length > 0 && STOPS.every(s => stopCity(s) === "rijeka"), 10000);
  const c = await Z.page.evaluate(() => ({ lat: map.getCenter().lat, me: ME }));
  check("the Rijeka button pins you on Korzo and shows Rijeka's stations", jumped && c.me.pinned && Math.abs(c.lat - 45.3271) < 0.01);
  await Z.page.evaluate(() => document.getElementById("cityZg").click());
  const back = await until(Z.page, () => STOPS.length > 0 && STOPS.every(s => stopCity(s) === "zagreb"), 10000);
  check("the Zagreb button brings you back", back);
  check("no script error in Zagreb", Z.errors.length === 0 || (console.log("   " + Z.errors.join("\n   ")), false));
  await b.close();
  console.log(fails.length ? "\n" + fails.length + " FAILED" : "\nall passed");
  process.exit(fails.length ? 1 : 0);
})().catch(e => { console.log("FAIL the run itself: " + e.message); process.exit(1); });
