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

## WHAT ZET ACTUALLY PUBLISHES

*Measured 31.8.2026, against the live feeds.*

**Every weekday flag in `calendar.txt` is zero.** All six services, all seven
days. ZET declares which service runs on which day only through
`calendar_dates.txt`, which held 136 dated exceptions running to 31.12.2026.
On Monday 31.8.2026 exactly one service ran, `0_45`.

Two consequences, and both are faults in the apps rather than in the feed:

An app selecting services with `row.get(weekday) == "1"` gets **nothing, every
day**. An app selecting on the date window alone matches **all six services at
once**, so it shows Sunday trams on a Monday mixed in with weekday trams. That
is the wrong data that shows up in the field.

**The live feed and the published schedule use different service ids.** Every
live trip id carries `20` in its second field; the static build published
18.8.2026 carries 45 to 50, which are its service ids. A join on the whole
trip id therefore matches **zero of 501** live trips. Dropping that field and
joining on the rest matches 78.7%, so they are the same trips wearing a
different service id.

**Nothing reads the feed header timestamp.** `day.commute` fetches the
protobuf and has its own varint reader, but never looks at the header, so a
feed that stopped moving an hour ago is drawn as if it were now. `stream.py`
reads it, and cross checks it against the server's own Last-Modified, which is
an independent witness of the same fact.

## THE MIDNIGHT COUNTDOWN, day.commute v13

*Found 31.8.2026 from a screenshot at 23:27, fixed the same day.*

A 00:02 bus showed **minus 1405 minutes**, which is 1440 minus the 35 it
should have said.

`hhmmToTodaySecs` built the departure with `setHours` on **today**, so 00:02
became 00:02 that morning, 23 hours 25 minutes in the past. Only the LIVE
rows went through it: the scheduled rows get their minutes from Python, where
the rollover is already handled, which is why one row in six was wrong while
the two rows below it were right.

The same file already had `minsUntil` doing this correctly with a three hour
threshold. Two functions answering one question, and only one of them knew
the answer. The fix uses the same threshold so they cannot disagree.

It is applied by `tools/patch_payload.py` at build time, with a witness that
fails the build if the function is edited upstream, and six checks in Test 1
that run the shipped function in a real javascript engine against a clock
frozen at 23:27:13.

## THE UPDATER, AND THE DECISION BEHIND IT

*31.8.2026, v3.*

The repository stays **private**, because day.commute is built around one
home stop and one commute, and that is an address.

So automatic updates need a credential, and the credential is a **fine
grained github token, read only, scoped to this one repository, with an
expiry**, stored at 600 beside the google key. Losing it means read access to
one private repository of transit scripts, which is a smaller thing than the
google key already on that phone, and revoking it at github ends it.

    maha-commute-update --token     once
    maha-commute-update             from then on

Without a token it still works the old way: the file arrives on the phone
however it arrives and the updater finds it, checks it four ways and runs it.

**The frozen address is `VERSION`, not the installer.** VERSION holds a
number, and the installer it names carries that number at both ends. That is
how the filename keeps its number at both ends while the updater still has a
fixed thing to ask for.

## A PROCESS FAILURE WORTH REMEMBERING

*31.8.2026.* The midnight countdown fix was shipped inside v2 without a
version bump. A change is a new version, always, and a fix is a change. Baba
caught it. Anything that alters the artefact gets a number, however small it
looks while writing it.
