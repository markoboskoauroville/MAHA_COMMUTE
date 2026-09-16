# What was not tested

Written 27.8.2026 for v1, updated 31.8.2026 for v2. Every delivery names what is
unproven as plainly as what works, because a confident report on an
untested feature spends trust that has to be earned back later.

Everything below was developed and tested on Linux, with the Termux
shebang provided as a symlink to this machine's bash and `$PREFIX`
pointed at a temporary folder. That proves the wiring. It proves
nothing about Android.

## Not tested at all, because it needs the phone

- `pkg install python`, `pkg install termux-api` and `pkg install psmisc` inside real Termux. The online branch of the installer has never run.
- Whether `$PREFIX/bin` is really on the PATH on Baba's phone, so whether typing `commute` finds it.
- `termux-open-url` and `am start` reaching a real browser. None of the three apps was opened on a phone screen from this umbrella.
- `termux-wake-lock` around a long run.
- The menu at 390px in the Termux terminal. Its widths were counted by hand and read in an 80 column terminal, not measured on the device.
- Whether `sha256sum` is present in this phone's Termux. The install falls back to a byte count comparison when it is missing, and that fallback ran, but not on Termux.
- Single keypress reading in the menu, `read -rsn1`, on the Termux soft keyboard. It was exercised through a pipe, which is not a keyboard.

## Tested only on this machine, where it may behave differently

- The three apps' own servers. `day.commute` was started and answered 200 on port 8082 with the port it recorded for itself. `night.commute` and `all.commute` were installed and their files written, but their servers were never started, so a fault inside either one would not have been seen.
- The Google key path was exercised with a fabricated key of the right shape and with a hostile one. It was never exercised with the real key against Google, so nothing here proves the maps draw.

## Known and left alone on purpose

- `night.commute` v9 deletes `~/.nightcommute` at the start of every install, so anything kept in there is lost in place. The umbrella copies the folder to `~/.maha.commute/backup/night.prev` first and says so, and does not restore it, because a clean folder is the app's own decision about its own data. Worth fixing in night v10.
- The three apps still hold their own copies of the key in their own folders. The shared store seeds them; it does not replace them.
- There is no updater. `commute update` does not exist, because the repository is private and an anonymous fetch against a private repository returns 404, and a token does not go on a phone that travels. Updating is a new installer file, run by hand.

## Added for v2, and unproven

- The four quadrant panel has never been drawn on a phone screen. Its widths were measured in an eighty column terminal and reasoned about, not seen at 390px.
- The number keys filling a quadrant by starting a server was exercised through a pipe, never by a thumb on a soft keyboard.
- Arrow keys move the focus. The escape sequence handling has never met the Termux soft keyboard, which is the only place it matters.
- `nohup` backgrounding of the three servers works here. Whether Android's power management leaves them running is a different question and is not answered.
- The reset on a new run has never been seen in a browser. The JavaScript was injected and the build proves it lands exactly once and that the keys it clears still exist upstream, but no page has actually been loaded and no selection has actually been cleared.
- The uninstaller ran no wipe. The listing and the refusal paths were exercised; the full `wipe` was never typed against a real install.
- The stream sanity checks ran against the live ZET feed from a Linux box. They have never run from Termux.
- The key tester was run against real keys and proved its verdicts, but only for Google Maps and Gemini. The other providers in its table are untested.

## Added for v10, the live feed and the star, and unproven

- **None of it has been seen in a browser.** The live rows, the status strip, the trams on the map, the chips and the star in the picker were all built and driven in a javascript engine with a small DOM standing in for a real one. No page has been loaded, so nothing here proves any of it is legible, or even visible, at 390px at one in the morning.
- **Neither map engine has drawn a tram.** `LEng.vehicle` and `GEng.vehicle` and their two favourite markers were written against Leaflet's and Google's APIs and are exercised by nothing: the harness has no map in it. A wrong option name in either would show as a marker that never appears, and every test here would still be green.
- **Google Maps was never the engine.** Everything that ran, ran with no key and no map at all. The Google half of both new markers is code inspection only.
- The live feed was read from a Linux box under proot, over wifi. It has never been read from Termux, and never on mobile data, where the twelve second timeout is the number that matters and is untested.
- **The trams were seen once, at night.** Test 2 asserts trams are on the map only when it is inside the 23:50 to 04:40 window, and it was inside it when this was built. Outside the window the test asserts only that the list is empty rather than broken, so the hours the app is actually for have been exercised and the hours it is not have not.
- The stale, late, ahead and undated feed states were all built by hand and proved. **A genuinely stalled ZET feed has never been met.** What is proven is that a feed carrying an old timestamp is refused, not that ZET's failure looks like that when it comes.
- The direction of a tram is taken from the stop ids its TripUpdate still carries, and falls back to reading the pattern digits out of the trip id. **The fallback has never been the answer against real data**: every live tram measured had stop ids to vote with. It is proven only against hand-made trips.
- `_locate_from_stops`, which places a tram ZET is not locating, fired for none of the eleven trams measured. It is proven on hand-made input only, and the "it was at this stop N seconds ago" branch has never been drawn.
- Favourites survive an install because they are in the browser's storage, and Test 4 proves the reset list stays empty. **No favourite has ever actually survived a reinstall**, because no favourite has ever been made in a real browser.
- The star was never tapped with a thumb. Whether its tap target is genuinely far enough from the row it sits in is a question about fingers, and it has only been answered about event targets.

## Known and left alone on purpose, still

- `night.commute` still deletes `~/.nightcommute` at the start of every install. v10 added the live feed and the star and deliberately did not touch the installer's own housekeeping, so the umbrella's copy to `~/.maha.commute/backup/night.prev` is still what saves anything kept there. Still worth fixing.
- ZET's delay field is read and carried in the `/live` answer and **is not shown anywhere**. Measured values included 3605 and 24000 seconds and a suspiciously constant -600. It is kept because it is information, and not drawn because it has not earned it.

## Added for v11, the wifi mark and the live arrival, and unproven

- **The pairing has been seen against real trams but never over time.** Rows were rendered from tonight's feed and read correctly, but nobody has watched one tram through a whole approach to check the mark stays on the same departure as it gets closer. A mark that jumps between rows as the tram moves would look exactly like this in a single reading.
- **"Early means it waits" is a claim about how ZET runs its night trams**, taken from the timetable's own structure and from watching trams arrive ahead of their slots. It has not been checked by standing at a stop and seeing one wait. If a night tram ever does leave early, this app will say it is still coming.
- The twelve minute matching window is set from the fifty minute headway. **No tram has been observed more than twelve minutes off its slot**, so the boundary behaviour is proven only against hand-made inputs.
- The yellow live time, the green wifi and the `+n` have been checked as markup and never seen rendered. The contrast of the darkened colours on the filled cyan "next departure" pill is reasoned about, not looked at.
