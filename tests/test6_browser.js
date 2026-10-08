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
const [base, leaflet, speed = "fast", exe] = process.argv.slice(2);
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
  check(speed + ": every station in range has a label on screen (" + st.texts.join(",") + ")", st.visible === 3 && st.texts.join() === "100,101,200");
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
  check(speed + ": zoomed out, no two labels overlap (" + rects.length + " labels)", rects.length === 3 && overlap === 0);
  let rightOnes = 0;
  for (const id of ["100", "101", "200"]) {
    await page.locator(".pin .pinid span", { hasText: id }).first().click();
    await page.waitForTimeout(700);
    const got = await page.evaluate(() => document.getElementById("dId").textContent);
    if (got === id) rightOnes++;
    await page.click("#dClose"); await page.waitForTimeout(300);
  }
  check(speed + ": each separated label opens its own station", rightOnes === 3);
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
  if (errors.length) console.log("errors: " + errors.join(" | "));
  await b.close();
  process.exit(0);
})().catch(e => { console.log("FAIL the browser test did not run: " + e.message); process.exit(0); });
