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
  if (errors.length) console.log("errors: " + errors.join(" | "));
  await b.close();
  process.exit(0);
})().catch(e => { console.log("FAIL the browser test did not run: " + e.message); process.exit(0); });
