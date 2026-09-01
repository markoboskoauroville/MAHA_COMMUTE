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
