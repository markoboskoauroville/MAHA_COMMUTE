# Visual Language and Logic

**How MAHA COMMUTE looks and why, and what every key does.** This is the
document to read before changing anything on the screen, and the document to
change first when the screen should work differently.

Written 31.8.2026 for v2.

---

## The idea in one sentence

Four quadrants, one app each, always labelled, and pressing a quadrant's
number fills it by starting that server.

## The screen

```
  MAHA COMMUTE v2
  +---------------------+---------------------+
  |1 day.commute        |2 night.commute      |
  |  v13  8082  4m      |  v9  ready          |
  |  the daytime ride   |  four night trams   |
  +---------------------+---------------------+
  |3 all.commute        |4 free               |
  |  not installed      |                     |
  |  stations around you|  room for a fourth  |
  +---------------------+---------------------+
  on day.commute:  Enter=open  stop  Restart  log

  1help    2refresh 3check   4test    5install
  6update  7key     8StopAll 9wipe    0quit

  1 2 3 4 fill a quadrant, arrows move without starting
```

Three lines to a quadrant, always three, whatever state it is in. The label,
then what it is doing, then what it is for.

## Filling a quadrant

**An empty quadrant is a server that is not running.** Its number starts
that server, and the quadrant fills in front of you: the second line changes
from `ready` to the port it bound and how long it has been up.

The number means the same thing in every state, which is the point:

| the quadrant is | pressing its number |
|---|---|
| running | opens its page again |
| installed, not running | starts it, and the quadrant fills |
| not installed | offers to install it, from the payload already on the phone |
| free, no app | moves there and does nothing, because there is nothing to do |

**The label is drawn whether the quadrant is filled or not.** 1 is
day.commute on this phone and on every other one, so the number never has to
be looked up and the hand learns it once.

Arrows move between quadrants without starting anything, for when you want
to look before you press.

## The verbs

Every quadrant has the same verbs and they act on the focused one. That is
the whole reason for the layout: one set of keys, learned once, and the only
thing that changes is which app is listening.

```
Enter   open it, starting it first if it is not running
o       open the page again, for when the tab was closed
s       stop it
R       restart it
l       its log, the last twenty lines in its own words
```

The line above the function row names the app the verbs will hit, so there
is never a question about which quadrant is about to be stopped.

## The function row

Ten slots, always the same ten, in the same order, dim when they do not
apply. It never moves and it never disappears. That is what makes mc usable
without being read, and it is the one thing worth copying wholesale.

```
1 help     2 refresh   3 check    4 test     5 install
6 update   7 key       8 StopAll  9 wipe     0 quit
```

**Every label is spelled by its own key.** r efresh, c heck, w ipe, q uit. A
key whose letter does not begin its word has to be read rather than
recognised, and this row is meant to be recognised. Termux has no F keys on
a soft keyboard, so the letter is what is pressed and the number is there
only because mc put one there.

## Colour and the bar

**Colour carries state. The bar carries focus.** They are different channels
so both can be read at once, and neither one has to be given up to show the
other.

| | |
|---|---|
| green | running |
| sand | installed and idle |
| grey | not installed, or nothing there |
| the bar | where you are |

Red is kept for faults and appears nowhere else, so it means something when
it does appear.

## Rules that produced all of the above

**Nothing appears and nothing disappears. Things become active or
inactive.** The fourth quadrant stays drawn while it is empty, and a
function key that cannot be used goes dim rather than away. A screen that
rearranges itself when the state changes is a screen the hand cannot learn.

**Words are not cut to fit a layout.** At twenty one characters "the four
night trams" loses its last letter and "every station around you" loses
three. The layout was not narrowed and the words were not clipped: a shorter
sentence was written for the quadrant, and the long one is still used where
there is room for it. Sizing a word by a fraction of the line is a promise
about width that a word cannot keep.

**Widths were measured, not guessed.** Twenty one characters inside each
quadrant, two quadrants and three rules, which is forty five columns and
fits a phone terminal with room to spare.

**Padding is done on the plain text and the colour wrapped around it
afterwards.** `printf` counts the bytes of an escape sequence as width, so a
coloured string handed to `%-21s` comes out short by exactly the length of
its escapes and every rule on the right walks left. This is the single
easiest way to break the panel and it is invisible until the colours are on.

**Nothing in the panel may wait.** It redraws on every keypress, so every
probe behind it carries a deadline. A port is read as digits only, because
bash resolves a non numeric `/dev/tcp` port as a service *name*, sends it to
the resolver, and one stray character in a port file turns a local question
into a network wait.

## A filled quadrant starts clean

Starting an app opens its page with a run id, and a run id the page has not
seen before clears what you last picked: the destination in day.commute, the
station in all.commute. So a quadrant that has just been filled is showing
today, not the last time you looked.

What you typed yourself is never cleared. Custom destinations and custom
stops survive every restart, because losing a preference is an annoyance and
losing your own work is not. The full list of what resets and what stays is
at the top of `tools/patch_payload.py`, in one place, so moving a key from
one list to the other is a one line change.

## Quitting

`q` leaves the launcher and leaves the servers running. The pages stay open
and stay live. `S` is what stops them, and it says so on the way out.
