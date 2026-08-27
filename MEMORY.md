# MEMORY

**The memory for MAHA_COMMUTE. Read it before working in this repo, and add
to it in the same turn as anything worth keeping is learned.**

The master memory is `MEMORY.md` in `MANTRA_MANIFEST`, which is private and is
the only place personal details belong. This file holds what is true about
this project.

---

## WHAT THIS REPO IS

*27.8.2026.* An umbrella over three apps that already existed and already
worked: `day.commute` v13, `night.commute` v9, `all.commute` v39. The three
were built separately over months and were installed by three separate files.
Nothing about them was rewritten here. They are carried whole, and the only
change made to any of them is the removal of the Google Maps key.

The umbrella adds four things and nothing else: a picker at install time, one
command called `commute`, a shared key store, and the cache of all three
payloads so an app left out can be added later with no download.

## THE KEY, AND WHY IT IS NOT HERE

*27.8.2026.* `13-install-day-commute-termux-v13.sh` and `9-night_commute_v9.sh`
both carried the **same** Google Maps API key, hardcoded in plain text, 39
characters. Every person who ever received either file has that key. It also
appeared in a chat transcript on 27.8.2026 while its usage was being traced.

**It should be restricted or rotated at Google.** Nothing in this repo depends
on that decision: the payloads here carry `__MAHA_GOOGLE_KEY__` and the
installer puts whatever key the phone has into a temporary copy that is deleted
straight after.

`all.commute` v39 never carried a key. It reads one from
`~/.all.commute/google-api.txt` and always did.

## WHAT NIGHT.COMMUTE V9 DOES TO ITS OWN FOLDER

*27.8.2026, found by Test 4.* Line 83 of the v9 installer runs
`rm -rf "$HOME/.nightcommute"` before it writes anything, so every install
loses whatever was in there. The umbrella does not overrule it. It reads the
payload, sees the wipe, copies the folder to `~/.maha.commute/backup/night.prev`
and prints where the copy is.

Fix it in night v10 by keeping the key file and anything the person wrote, and
clearing only what the installer itself put there.

## DECISIONS MADE HERE

*27.8.2026.*

**The umbrella command is `commute`, not `maha.commute`.** `day.commute` v13
already tells the person to type `commute` for the family menu, in its own
closing line, written before this repo existed. The name was already chosen.

**The repository is private and there is no updater.** An anonymous fetch
against a private repository returns 404 and a token does not go on a phone
that travels. Updating means a new installer file, run by hand. If it is ever
made public, the filename freezes and the version moves inside the file, per
`termux-app.md` §11.

**The payloads keep their original filenames** in `src/payloads/`, so the
provenance of each one is readable without opening it.

**One install routine, `install-one.sh`,** called by both the installer and the
menu. The second caller is the reason it exists as a file rather than a
function.

## THE PORTS

`day.commute` 8082, `all.commute` 8084, `night.commute` 8087. They do not
collide, so all three can run at once. The menu reads them to say what is
running, and a port that answers is the only claim it trusts.
