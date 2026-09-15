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

*31.8.2026, v3, reversed 1.9.2026 for v4.*

**The repository is PUBLIC.** Baba made that call knowing what it costs: the
corridors day.commute is built around are his own commute, so the shape of
where he lives and works is now readable. Weigh that before adding anything
new to a payload.

The whole history was scanned before the flip, 58 blobs across 5 commits
against five key shapes, and two stray .pyc files were untracked. Going
public exposes every commit, not just the current tree, so the scan has to
be of the history and not of the working directory.

What it bought is a one word update with no credential anywhere. The earlier
private plan is below, kept because the reasoning still applies to any repo
that stays private.

*The earlier reasoning, no longer in force:*

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

## THE STAR IN ALL.COMMUTE

*1.9.2026, v5.* Every station wore a star, which made the star mean "a
station is here", something the number pill and the name pill already said.
It left nothing to mean "this is the one you picked".

Now the star appears on the watched station only, beside its name, and
**opening a station is what watching means**. Tap the number or tap the name,
either one, and that station is being watched until another is opened. The
pills were already one click target, so both halves worked from the start;
what was missing was that the tap did not make it the watched one.

The separate toggle still drops a station. Nothing has to be toggled on any
more: picking is the whole gesture.

Also visible in that screenshot and NOT fixed: the CARTO basemap tiles now
say API KEY REQUIRED across them, so the dark basemap needs a Carto key or a
different tile source. And the location line read "no provider answered" at
±71 m.

## WHY PRESSING 1 LOOKED LIKE IT DID NOTHING

*1.9.2026, v6.* A browser tab opened on 127.0.0.1 with nothing behind it,
and the launcher said the app had not come up.

Two causes, both in the launcher and neither in the app.

**The wait was sixteen seconds.** day.commute execs its server, and that
server fetches an eleven megabyte schedule from ZET and builds its caches
BEFORE it binds anything. On a phone on mobile data that is minutes. So the
launcher announced failure while the app was still working, and the app,
which opens its own browser tab, had already opened one. A tab with nothing
behind it yet.

Now the wait is three minutes, it prints the seconds and the app's own last
line while waiting, and any key leaves it working in the background instead
of killing it.

**The app inherited the terminal.** It was backgrounded with nohup but with
stdin still attached, so a server and the menu were both attached to the
same keyboard. Now it gets setsid and `</dev/null`: its own session, no
terminal, so it cannot eat a keypress meant for the menu and it does not die
when the menu is quit.

**A test failure that was not a bug.** Test 2 went red on "the server's own
record agrees with the socket" because a stray server from a manual
reproduction was still holding 8082, so the test's own server took 8083 and
recorded 8083. The test was right and the machine was dirty. Kill strays
before believing a port assertion.

## THE MAP PIN IS THE NUMBER

*1.9.2026, v7.* The pin carried three things: a number, a star and a name.
On a phone in the middle of the city that is three overlapping labels per
station with half a dozen stations in view, so the map became a pile of text
with a map underneath it.

Now it is the number and the direction letter. Tap the number, get the
arrivals.

**The star is gone entirely**, and with it the idea of a station being
"watched", which was a second concept stacked on top of simply picking one.
Baba asked for it removed twice: first to appear only on the picked station,
then not at all. The second ask is the right one, and the first was me
keeping a mechanism alive that had already been declined.

**The name is gone from the map** because the number identifies the station
and the name is in the popup, which is the only place it is needed. The
direction letter stays because two stops sharing a number on opposite sides
of a road is the confusion a map has to resolve rather than add to.

The internal WATCH still exists because the arrivals board and the dashboard
read it. Nothing draws it any more.

## THE INSTALL ASKS NOTHING NOW

*1.9.2026, v8.* Three questions were removed because none of them had a real
choice behind it.

**Which apps.** The answer was always all three. `--apps` still exists for a
test that installs a subset; nobody types it.

**Offline or online.** Missing dependencies are fetched, present ones are
left alone, and offline is what happens on its own when the network does not
answer. `--offline` still forces it.

**The key.** If there is no key it says so in one line and carries on. It
does not stop and ask.

So the installer reads no input at all now, which is also what makes it safe
for `maha-commute-update` to run unattended.

**AN UPDATE TOUCHES ONLY WHAT MOVED.** Each install records the sha256 of the
payload it installed in `installed/<app>.sha`. The next run compares, and an
app whose payload is identical is not reinstalled. Reinstalling all three
every time meant three apps rebuilding caches for nothing, and it buried the
one line worth reading. The closing now says `updated: night.commute` and
`already current, left alone: day.commute all.commute`.

## NO DEAD ZONE BETWEEN THE TAP AND THE DATA

*1.9.2026, v9.* Tapping a station went straight to the network, so the first
thing that happened after touching one was nothing, for as long as the
request took. On a phone that reads as a dead app and the finger taps again.

**The outline lands on the tap. The fetch waits 333ms.** Long enough to
change your mind after a mis-tap, short enough that a deliberate tap does not
feel held back. Tap three stations in a row and only the third is fetched:
each tap moves the white outline and cancels the one before it.

**SELGEN is what makes a cancelled fetch stay cancelled.** A request already
in flight cannot be recalled, but its answer can be thrown away, and the
generation it was started under is how it knows it is stale. Without that,
three quick taps race and the slowest answer wins, which is the wrong one.

The white outline is white on purpose: every other colour on that map means a
line or a station, and this one has to mean "you touched this" and nothing
else.

**hud() kept its signature** and gained a Braille spinner, so every existing
caller works unchanged. A turning spinner also distinguishes working from
died, which the old static dot did not.

Measured in node at real timings, taps at 0, 80 and 160ms: one fetch, of the
third station, with three outlines before it.

## NIGHT.COMMUTE V10 READS THE LIVE FEED

*16.9.2026, v10. Measured against the live tap at 01:03 and again at 01:20,
which is inside the night service window, so the night trams were out.*

`night.commute` reads `https://zet.hr/gtfs-rt-protobuf` and says where the
tram is: on the map as a moving car number, and under each leg on the Plan
tab as "car 460, at Kruge, 2 stops away, ~4 min".

**The trip descriptor carries `route_id`, and that is the whole join.** Field
5, plain text, on every entity. Nothing has to be matched against the static
schedule to know a tram is a 33. This is the reason the reader is short, and
it is the reason it does not depend on the agreement below holding.

**The live ids and the published build agree again.** On 31.8.2026 this
project measured the whole-trip-id join at **zero of 501**, because the live
feed carried service id 20 and the static build 45 to 50. Measured again on
16.9.2026: **56 of 57, 98.2 per cent**, with both sides saying `0_23`. ZET
changed it. The earlier measurement was not wrong, it was earlier, and the
lesson is that this particular agreement is something ZET moves without
telling anybody. Read `route_id` off the feed and it does not matter which
way it has moved this month.

**One tram arrives as TWO entities that never appear together.**

    X8HIDLT03R       a TripUpdate       trip 0_23_3302_33_10017, route 33
    X8HIDLT03R_460   a VehiclePosition  same trip, car 460, 45.7997,15.9713

Thirty one carried a TripUpdate, thirty five a VehiclePosition, and **zero
carried both**. The delay and the position for one tram are joined on the
trip id, in `parse_rt`.

**What a position does not carry.** No bearing, no speed, no `stop_id`, no
`current_stop_sequence`, no `current_status`: measured absent on all thirty
five. So which stop a tram is at is worked out here, from the coordinate
against that line's own stations, and which way it faces from the stop ids
its TripUpdate still has ahead of it.

### THE DELAY FIELD LIES, IN TWO TELLABLE WAYS

Of sixty two stop time updates in one reading, **thirty carried no time at
all, and every single one of those thirty claimed a delay of exactly zero**.
That is ZET's shape for "nothing known", and read naively it writes "on time"
against every tram ZET has lost track of. So **a delay needs a time beside
it** or it is not a delay.

Of the thirty two that did carry a time, the delays included **3605 and
24000 seconds**. A night tram on a fifty minute headway is not six hours
late. 3605 is an hour and five seconds, which is the shape of a clock an hour
out rather than of a late tram. So a delay over **thirty minutes** is thrown
away, and the bound is in `DELAY_SANE_S`.

### THE FEED IS GOOD AT WHERE AND BAD AT WHEN

Most stop time updates are for stops the tram has **already passed**, some by
the best part of an hour; only a handful are ahead of it. So the feed is
believed about where a tram is, which it is good at, and **the timetable the
app already holds answers how long it takes to get here**. `_running_times`
builds that from tonight's own trips, taking the median at each station so
one tram sitting at a terminal with its doors open does not become the
running time for everybody. It measures 43 to 48 minutes end to end on all
four lines, both directions agreeing within a minute, which is the internal
check that it is right.

A prediction from the feed is used only when it exists for the stop being
asked about and has not already happened. Those rows are exact; the rest
wear a `~`, and the two never look alike.

### A SIZE FLOOR THAT NEARLY BROKE IT AT THE HOUR IT IS FOR

The first reader refused any body under two hundred bytes as too small. The
feed measures 6327 bytes for 65 vehicles, which is about **97 bytes each**,
so that floor would have thrown away a perfectly good feed at half past four
in the morning with two trams left running. That is exactly the hour this app
exists for, and the app would have said "no live feed" on the night it was
most needed.

Found by Test 3, which builds small feeds by hand. The floor is now only what
cannot be a feed at all, and the real check is that **a feed says either what
time it is or what is moving**; something that says neither is not one.

### THE STAR, AND WHY IT IS NOT THE ONE THAT WAS REMOVED

`all.commute` put a star on **every** station, which made it mean "a station
is here" — something the number and the name already said — and left nothing
to mean "this is one of mine". It was taken off, twice, and rightly.

night.commute v10's star is the opposite: **it is only ever on a station the
person put it on.** Four stations out of a hundred and eight wearing a mark
says exactly one thing. It earns its keep in three places, all the same idea:
kept stations sort to the top of the picker, they sit as chips above the
pickers so the usual trip needs no search, and they are starred on the map
whether or not their line is switched on.

**Stored as names, not stop ids**, under `nc_fav`, because ZET renumbers
stops between schedule builds and this list has to outlive that. A name the
network no longer has stays in the store and is simply not drawn, so a
station that comes back brings its star with it.

**The star is its own tap target and the row is another.** Without that
guard, starring the stop you are standing at also sends you to it. Test 1
drives the real listener and proves it: with the guard taken out, the tap
lands on station B.

### HOW V10 IS BUILT, AND THE HOLE IT FOUND IN THE GATE

The new code is in `src/payloads/night-v10/` as ordinary `.py`, `.js` and
`.css` files, spliced into the payload at build time by `patch_payload.py`
against anchors that must match exactly once. It is not string literals
inside the patcher, because four hundred lines quoted in there would be four
hundred lines nothing can lint, diff or run.

**The gate was compiling the wrong copies.** It put `src/*.py` and the two
emitted tools through their interpreters, and nothing at all put
`night_server.py` or `night.html` through theirs. A splice that broke either
would have built, passed `bash -n`, and failed only on the phone. The gate
now pulls both back out of the artefact, compiles the python, runs
`node --check` over the page, and **checks that the splice actually happened**
— a patcher that quietly puts nothing in leaves a file that compiles
perfectly and does nothing.
