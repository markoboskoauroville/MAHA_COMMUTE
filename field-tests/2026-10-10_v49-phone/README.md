# all.commute on the phone, 10.10.2026 — labels and the trace

These are the live files from Marko's phone (`~/.all.commute`), captured
before they have been ported into the payload patch chain. They are here so
the work cannot be lost with the phone; `tools/payload_v26.py` is where they
belong once the anchors have been read against the current payload.

Base: this branch, `60ffff5` (v25, all.commute v48), which already carries the
follow fix and the `termux_fix` fix.

## What is in all.html that is not yet in the chain

**1 · Labels are placed, not pushed apart.** `layoutPins()` was giving every
station a label and then shoving the labels off each other. Once a label is
wider than the gap between two stations that cannot converge, so labels ended
up far from the stations they name and overlapping anyway. Now each station is
offered positions in turn — above the dot first, then below, the sides, the
diagonals, then two rings further out — and takes the first that is free and
on screen. A station that cannot have a label without covering another keeps
its dot and loses its label.

**2 · The label is sized by the zoom.** `pinFontPx()` maps zoom 13 → 9 px and
zoom 18 and up → 17 px, published as `--pinfs` on the map container.

**3 · Android's text scaling no longer reaches the map.** `.pin` now sets
`text-size-adjust:100%`. Without it the system font slider was inflating the
labels to several hundred pixels, which is what the screenshot of 08:16 shows
and the reason no placement algorithm could have worked.

**4 · Every station always has a dot.** New `.pindot`, counter-translated
against the parent's `--dx/--dy` so it stays on the station while the label
moves. Zooming out now thins to a map of dots instead of a pile of text.

**5 · The trace.** A record button in `#tools`: tap to start and stop, hold to
clear. Fixes more than 8 m from the last recorded point are appended and drawn
as a red polyline, Leaflet and Google both. Kept in `ac2_trace`, which the
new-run reset does not clear, because a recorded journey is made rather than
picked.

## Not yet done

Untested in the running app at the time of writing — committed first, on
Marko's instruction, so that testing cannot lose it. `all.html.diff` is the
change against the file as it was before this session touched it.
