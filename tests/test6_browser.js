/* test6_browser.js, the all.commute page in a real browser.
 *
 *   node tests/test6_browser.js <base-url> <leaflet-dir> [slow|fast] [chrome]
 *
 * Needs playwright-core, a Chromium and leaflet@1.9.4 on disk (the page asks
 * unpkg for it, and a test must not depend on that). test6_browser.sh finds
 * them and skips with a printed reason when it cannot.
 *
 * "slow" delays /api-keys by 1.5 s. That is the race that hid the labels: the
 * phone's first position arrived BEFORE the map had been created, drawing the
 * "you are here" ring threw, and the map was never moved to the person, so the
 * stations were loaded around them and drawn off screen. A fast phone and a
 * slow one disagreed about whether the labels were there at all.
 *
 * Prints PASS or FAIL per check.
 */
const { chromium } = require("playwright-core");
const [base, leaflet, speed = "fast", exe, mockCount] = process.argv.slice(2);
const fs = require("fs");
const mockCalls = () => { try { return fs.readFileSync(mockCount, "utf8").split("\n").filter(Boolean).length; } catch (e) { return 0; } };
const fails = [];
const check = (n, c) => { console.log((c ? "PASS " : "FAIL ") + n); if (!c) fails.push(n); };
(async () => {
  const b = await chromium.launch({ executablePath: exe, args: ["--no-sandbox"] });
  const ctx = await b.newContext({ viewport: { width: 390, height: 780 },
    geolocation: { latitude: 45.8052, longitude: 15.9805, accuracy: 15 }, permissions: ["geolocation"] });
  const page = await ctx.newPage();
  const errors = [];
  page.on("pageerror", e => errors.push(e.message));
  await page.route("**/*", route => {
    const u = route.request().url();
    if (u.includes("leaflet@1.9.4/dist/leaflet.css")) return route.fulfill({ path: leaflet + "/leaflet.css", contentType: "text/css" });
    if (u.includes("leaflet@1.9.4/dist/leaflet.js")) return route.fulfill({ path: leaflet + "/leaflet.js", contentType: "application/javascript" });
    if (u.endsWith("/api-keys") && speed === "slow") return setTimeout(() => route.continue(), 1500);
    if (u.startsWith(base)) return route.continue();
    return route.abort();
  });
  await page.goto(base + "/all.html");
  await page.waitForTimeout(5000);
  const st = await page.evaluate(() => ({
    center: map.getCenter(),
    visible: [...document.querySelectorAll(".pin .pinid span")].filter(e => {
      const r = e.getBoundingClientRect();
      return r.width > 0 && r.left >= 0 && r.right <= innerWidth && r.top >= 0 && r.bottom <= innerHeight; }).length,
    texts: [...document.querySelectorAll(".pin .pinid span")].map(e => e.textContent.trim().split(" ")[0]).sort() }));
  check(speed + ": no script error on the way in", errors.length === 0);
  check(speed + ": the map was moved to the person", Math.abs(st.center.lat - 45.8052) < 0.001);
  check(speed + ": every station in range has a label on screen (" + st.texts.join(",") + ")", st.visible === 4 && st.texts.join() === "100,101,200,300");
  await page.locator(".pin .pinid span", { hasText: "100" }).first().click();
  await page.waitForTimeout(1200);
  const d = await page.evaluate(() => ({ on: document.getElementById("dash").classList.contains("show"),
    id: document.getElementById("dId").textContent }));
  check(speed + ": tapping a label opens that station's dashboard", d.on && d.id === "100");
  await page.click("#dClose"); await page.waitForTimeout(300);
  // Zoomed out, the three stations are a few pixels apart. The labels must not
  // overlap, and each must open ITS OWN station when tapped.
  await page.evaluate(() => { map.setView([45.8055, 15.9800], 15, { animate: false }); });
  await page.waitForTimeout(600);
  const rects = await page.evaluate(() => [...document.querySelectorAll(".pin .pinid span")].map(e => {
    const r = e.getBoundingClientRect(); return { id: e.textContent.trim().split(" ")[0], l: r.left, t: r.top, r: r.right, b: r.bottom }; }));
  let overlap = 0;
  for (let i = 0; i < rects.length; i++) for (let j = i + 1; j < rects.length; j++) {
    const a = rects[i], b = rects[j];
    if (a.l < b.r && b.l < a.r && a.t < b.b && b.t < a.b) overlap++;
  }
  check(speed + ": zoomed out, no two labels overlap (" + rects.length + " labels)", rects.length >= 4 && overlap === 0);
  // v22 (field test F1): no label may sit under the status line, the buttons, the GPS
  // chip or the watch bar, or the tap lands on THEM. Several views, so a station is
  // sometimes near the top edge and sometimes near the bottom one.
  const under = async () => page.evaluate(() => {
    const boxes = ["hud", "tools", "gpsChip", "watchbar"].map(id => document.getElementById(id))
      .filter(e => e && getComputedStyle(e).display !== "none").map(e => e.getBoundingClientRect())
      .filter(r => r.width > 0 && r.height > 0);
    return [...document.querySelectorAll(".pin .pinid span")].filter(e => {
      const l = e.getBoundingClientRect();
      return boxes.some(r => l.left < r.right && r.left < l.right && l.top < r.bottom && r.top < l.bottom);
    }).map(e => e.textContent.trim().split(" ")[0]);
  });
  let hidden = [];
  for (const c of [[45.8035, 15.9800], [45.8075, 15.9800], [45.8055, 15.9780], [45.8055, 15.9825]]) {
    await page.evaluate(([la, lo]) => { map.setView([la, lo], 17, { animate: false }); }, c);
    await page.waitForTimeout(500);
    hidden = hidden.concat(await under());
  }
  check(speed + ": no label sits under the status line, buttons, GPS chip or watch bar" +
        (hidden.length ? " (under: " + hidden.join(",") + ")" : ""), hidden.length === 0);
  await page.evaluate(() => { map.setView([45.8055, 15.9800], 15, { animate: false }); });
  await page.waitForTimeout(500);
  let rightOnes = 0;
  for (const id of ["100", "101", "200", "300"]) {
    await page.locator(".pin .pinid span", { hasText: id }).first().click();
    await page.waitForTimeout(700);
    const got = await page.evaluate(() => document.getElementById("dId").textContent);
    if (got === id) rightOnes++;
    await page.click("#dClose"); await page.waitForTimeout(300);
  }
  check(speed + ": each separated label opens its own station", rightOnes === 4);
  await page.evaluate(() => { map.setView([45.8052, 15.9805], 17, { animate: false }); });
  await page.waitForTimeout(300);
  // The map does not follow the dot. Pan away and zoom out; the phone moves; a new
  // burst of fixes arrives. The map must stay exactly where the person left it,
  // and only the locate button brings it back.
  await page.evaluate(() => { map.setView([45.8200, 15.9900], 14, { animate: false }); });
  await page.waitForTimeout(300);
  await ctx.setGeolocation({ latitude: 45.8049, longitude: 15.9801, accuracy: 5 });
  await page.evaluate(() => { FIXES = []; autoLocate(true); });
  await page.waitForTimeout(2500);
  const away = await page.evaluate(() => ({ lat: map.getCenter().lat, lng: map.getCenter().lng, z: map.getZoom(), me: ME }));
  check(speed + ": the dot moved with the phone", Math.abs(away.me.lat - 45.8049) < 0.0005);
  check(speed + ": the map did not follow it, or change zoom", Math.abs(away.lat - 45.82) < 1e-6 && away.z === 14);
  await page.click("#btnLocate");
  await page.waitForTimeout(2500);
  const back = await page.evaluate(() => ({ lat: map.getCenter().lat, z: map.getZoom() }));
  check(speed + ": the locate button brings the map to the dot", Math.abs(back.lat - 45.8049) < 0.002 && back.z >= 17);
  // v22 (F8): the phone is 3 km away and no burst is running; the button must end up
  // THERE, not at the old position, once the new fix arrives.
  await ctx.setGeolocation({ latitude: 45.8300, longitude: 15.9900, accuracy: 5 });
  await page.evaluate(() => { map.setView([45.8049, 15.9801], 15, { animate: false }); });
  await page.click("#btnLocate");
  await page.waitForTimeout(4000);
  const far = await page.evaluate(() => ({ lat: map.getCenter().lat }));
  check(speed + ": the locate button follows up on the new fix (3 km away)", Math.abs(far.lat - 45.83) < 0.002);
  // v23: the watch bar shows the next THREE departures, not one. Fed directly with a
  // board, so the check does not depend on what the fixture timetable has at this hour.
  const wb = await page.evaluate(() => {
    const feed = (deps) => {
      WATCH = { stop_id: "100", name: "Glavni kolodvor", lat: 45.805, lon: 15.98 };
      document.body.classList.add("watching");
      BOARDS["100"] = { ok: true, departures: deps };
      updateWatchBar();
      const el = document.getElementById("wbEta"), bar = document.getElementById("watchbar");
      return { n: el.querySelectorAll(".rt").length, lines: [...el.querySelectorAll(".rt")].map(e => e.textContent),
               text: el.textContent, fits: bar.scrollWidth <= bar.clientWidth + 1,
               inside: bar.getBoundingClientRect().right <= innerWidth && bar.getBoundingClientRect().left >= 0,
               h: bar.getBoundingClientRect().height };
    };
    const d = (route, mins, live) => ({ route, mins, live: !!live, passed: false });
    return { four: feed([d("6", 2, true), d("4", 5), d("13", 9), d("2", 14)]),
             two: feed([d("6", 2), d("4", 5)]),
             none: feed([]),
             gone: feed([{ route: "9", mins: -3, passed: true }, d("6", 4), d("4", 8), d("13", 12), d("2", 20)]) };
  });
  check(speed + ": the watch bar shows three rides when four are coming", wb.four.n === 3 && wb.four.lines.join() === "6,4,13");
  check(speed + ": the three fit inside the bar and the screen", wb.four.fits && wb.four.inside);
  check(speed + ": it shows what there is when fewer than three are coming", wb.two.n === 2);
  check(speed + ": it shows a dash when nothing is coming", wb.none.n === 0 && wb.none.text.trim() === "—");
  check(speed + ": a ride that has left is not counted among the next three", wb.gone.lines.join() === "6,4,13");
  // the labels must still stay clear of the taller bar
  await page.evaluate(() => { map.setView([45.8035, 15.9800], 17, { animate: false }); });
  await page.waitForTimeout(500);
  const hiddenBar = await page.evaluate(() => {
    const r = document.getElementById("watchbar").getBoundingClientRect();
    return [...document.querySelectorAll(".pin .pinid span")].filter(e => {
      const l = e.getBoundingClientRect(); return l.left < r.right && r.left < l.right && l.top < r.bottom && r.top < l.bottom; }).length;
  });
  check(speed + ": no label sits under the taller watch bar", hiddenBar === 0);
  // v24: the page's own copy. A SECOND visit with every request to the server refused
  // (only the page itself is let through) must still draw the stations, because they
  // are drawn from the browser's copy before anything is asked.
  const cached = await page.evaluate(() => { try { return Object.keys(JSON.parse(localStorage.getItem("ac2_stations")).stops).length; } catch (e) { return 0; } });
  check(speed + ": the page keeps its own copy of the stations (" + cached + ")", cached >= 4);
  const p2 = await ctx.newPage();
  const seen = [];
  await p2.route("**/*", route => {
    const u = route.request().url();
    if (u.includes("leaflet@1.9.4/dist/leaflet.css")) return route.fulfill({ path: leaflet + "/leaflet.css", contentType: "text/css" });
    if (u.includes("leaflet@1.9.4/dist/leaflet.js")) return route.fulfill({ path: leaflet + "/leaflet.js", contentType: "application/javascript" });
    if (u.endsWith("/all.html") || u.includes("/all.html?")) return route.continue();
    seen.push(u.replace(base, "")); return route.abort();           // the server answers nothing else
  });
  await p2.goto(base + "/all.html");
  await p2.waitForTimeout(1500);
  const offline = await p2.evaluate(() => ({ labels: document.querySelectorAll(".pin .pinid span").length,
                                             stops: typeof STOPS !== "undefined" ? STOPS.length : -1 }));
  check(speed + ": with the server refusing everything, the stations still draw (" + offline.labels + " labels)", offline.labels >= 3);
  await p2.close();
  // v25: the stations follow the map, not the dot, and beyond ZET's network the server
  // discovers stops tile by tile as you scroll and the page keeps them for good.
  const labelsNow = () => page.evaluate(() => [...document.querySelectorAll(".pin .pinid span")].map(e => e.textContent.trim().split(" ")[0]));
  const labelsAt = async (c, z) => {
    await page.evaluate(([la, lo, zz]) => { map.setView([la, lo], zz, { animate: false }); }, [c[0], c[1], z]);
    await page.waitForTimeout(800);
    return labelsNow();
  };
  let L = await labelsAt([45.8070, 15.9820], 17);
  check(speed + ": scrolled to another corner, the stations there are drawn (" + L.join(",") + ")", L.includes("300"));
  L = await labelsAt([45.8055, 15.9800], 13);
  check(speed + ": zoomed out to 13 there are no labels, too many to read", L.length === 0);
  const before = mockCalls();
  L = await labelsAt([45.9030, 16.1040], 16);
  for (let w = 0; w < 30 && !L.some(t => t.startsWith("Testna")); w++) { await page.waitForTimeout(500); L = await labelsNow(); }
  check(speed + ": beyond ZET's network, stops found by scrolling are drawn (" + L.join(",") + ")", L.some(t => t.startsWith("Testna")));
  const afterFirst = mockCalls();
  check(speed + ": that took one request per tile in view (" + (afterFirst - before) + ")", (speed === "fast" ? afterFirst > before : true) && afterFirst - before <= 4);   // the second run finds the first one's tiles already kept
  await labelsAt([45.8055, 15.9800], 17);
  L = await labelsAt([45.9030, 16.1040], 16);
  await page.waitForTimeout(1500);
  check(speed + ": coming back asks nothing again, the stops are there at once", mockCalls() === afterFirst && L.some(t => t.startsWith("Testna")));
  // a second visit with the server refusing everything but the page: the same view, from the browser's copy
  const p3 = await ctx.newPage();
  const asked = [];
  await p3.route("**/*", route => {
    const u = route.request().url();
    if (u.includes("leaflet@1.9.4/dist/leaflet.css")) return route.fulfill({ path: leaflet + "/leaflet.css", contentType: "text/css" });
    if (u.includes("leaflet@1.9.4/dist/leaflet.js")) return route.fulfill({ path: leaflet + "/leaflet.js", contentType: "application/javascript" });
    if (u.endsWith("/all.html") || u.includes("/all.html?")) return route.continue();
    asked.push(u); return route.abort();
  });
  await p3.goto(base + "/all.html");
  await p3.waitForTimeout(1500);
  const offlineX = await p3.evaluate(() => [...document.querySelectorAll(".pin .pinid span")].map(e => e.textContent.trim().split(" ")[0]));
  check(speed + ": a later visit, with no server, draws the discovered stops from the browser's copy", offlineX.some(t => t.startsWith("Testna")));
  await p3.close();
  if (errors.length) console.log("errors: " + errors.join(" | "));
  await b.close();
  process.exit(0);
})().catch(e => { console.log("FAIL the browser test did not run: " + e.message); process.exit(0); });
