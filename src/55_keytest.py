#!/usr/bin/env python3
"""keytest.py, written by the MAHA COMMUTE installer.

    python keytest.py            test every key this phone holds
    python keytest.py --file F   also read keys out of a note
    python keytest.py --quiet    one line per key

WHAT THIS IS FOR

`keyring.md` says never test a key speculatively: use the first key not
known dead and let a real request find out. That rule is about the app's
normal running. This is the one place it does not apply, because being
asked "is this key good" IS the job here, and it is asked by hand.

The question actually being asked is never "does the key work". It is one
of five, and they need different answers and different fixes:

    is it a key at all          shape, before a single call is made
    is it accepted              the credential itself
    is the API turned on        a good key on a project with that API off
    is it restricted            a browser key called from a server. This is
                                the one that looks like a dead key and is not
    has the money run out       billing off, or the cap reached

The last one is the reason this exists, and it needs saying plainly:
**neither Google API has an endpoint that reports a balance.** No call
returns how much credit is left. What the wire does say, exactly, is
whether billing is switched off, whether a cap has been hit, and whether
the request was throttled. Anything beyond that is in the Cloud console
and nowhere else, and a tester that claims otherwise is guessing.

NO KEY IS EVER PRINTED. Not in full, not redacted. Each is named by its
prefix, its length and four characters of its hash, which is enough to
tell two keys apart and useless to anybody who reads it. Redaction is
what leaked a key once already: a pattern that recognises secrets is safe
for extraction, where an unknown format fails closed, and unsafe for
redaction, where an unknown format fails open and prints.
"""

import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

APPHOME = os.path.join(os.path.expanduser("~"), ".maha.commute")
UA = "maha.commute-keytest/1 (+https://github.com/markoboskoauroville/MAHA_COMMUTE)"

# Both Google formats. A filter written for AIza alone finds nothing in a
# file full of AQ. keys, and Google has changed this once already, so a
# third format should be assumed to be coming.
KEY_SHAPES = [
    ("google", re.compile(r"AIza[A-Za-z0-9_-]{30,}")),
    ("google", re.compile(r"AQ\.[A-Za-z0-9_.-]{20,}")),
]

# Where each app keeps the key it is actually using. Read so the tester can
# say "the app is not using the key you think it is", which is its own
# whole class of confusion.
APP_KEYFILES = [
    ("shared store", os.path.join(APPHOME, "keys", "google-api.txt")),
    ("day.commute", os.path.expanduser("~/.commute/google-api.txt")),
    ("night.commute", os.path.expanduser("~/.nightcommute/gmaps-api.txt")),
    ("all.commute", os.path.expanduser("~/.all.commute/google-api.txt")),
    ("all.commute gemini", os.path.expanduser("~/.all.commute/gemini-api.txt")),
]

STREETVIEW = ("https://maps.googleapis.com/maps/api/streetview/metadata"
              "?location=45.8131,15.9775&key=%s")
GEOCODE = ("https://maps.googleapis.com/maps/api/geocode/json"
           "?address=Zagreb&key=%s")
GEMINI = "https://generativelanguage.googleapis.com/v1beta/models"

TTY = sys.stdout.isatty()
C = {"ok": "\033[1;32m", "warn": "\033[38;5;214m", "bad": "\033[1;31m",
     "dim": "\033[0;90m", "key": "\033[1;37m", "off": "\033[0m"}
LEVEL_RANK = {"ok": "ok", "warn": "warn", "bad": "bad", "dim": "ok"}
if not TTY:
    C = {k: "" for k in C}


def name_of(key):
    """A key named without being shown. Prefix, length, and four characters
    of a hash: enough to tell two apart, useless to anybody reading it."""
    fp = hashlib.sha256(key.encode()).hexdigest()[:4]
    prefix = key[:4] if key.startswith("AIza") else key[:3]
    return "%s\u2026 %d chars, fp %s" % (prefix, len(key), fp)


def find_keys(text):
    """Keys out of a handwritten note. The file is a working note with
    dates, account names, the word CANCELLED and URLs carrying tracking
    tokens that are the right length and the wrong thing. Shape takes the
    keys and leaves the prose."""
    out = []
    for _provider, rx in KEY_SHAPES:
        for m in rx.finditer(text):
            k = m.group(0).rstrip(".,;:)\"'")
            if k not in out:
                out.append(k)
    return out


def _req(url, headers=None, timeout=25):
    """One place, so no call can forget the User-Agent. A provider behind
    Cloudflare answers a request without one with 403 on every endpoint,
    which looks exactly like a ring of dead keys and is nothing to do with
    the keys."""
    h = {"User-Agent": UA}
    h.update(headers or {})
    req = urllib.request.Request(url, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(), None
    except urllib.error.HTTPError as e:
        return e.code, e.read(), None
    except Exception as e:
        return None, b"", e


def _json(body):
    try:
        return json.loads(body.decode("utf-8", "replace"))
    except Exception:
        return {}


# ---------------------------------------------------------------------------
# the probes
#
# The cheapest legitimate question in each case. Street View METADATA is
# free and is documented as free; the image is not, so the image is never
# asked for. Gemini is asked to list models, which generates nothing.
# ---------------------------------------------------------------------------

def probe_streetview(key):
    status, body, err = _req(STREETVIEW % key)
    if err:
        return ("warn", "no answer", str(err), None)
    d = _json(body)
    s = d.get("status", "")
    msg = d.get("error_message", "")
    if s in ("OK", "ZERO_RESULTS"):
        return ("ok", s, "the key is accepted for Street View", True)
    if s == "REQUEST_DENIED":
        low = msg.lower()
        if "referer" in low or "referrer" in low:
            return ("warn", "browser only",
                    "locked to a web page, so the browser map works and "
                    "anything asked from the terminal does not", False)
        if "not authorized" in low or "api is not enabled" in low or "disabled" in low:
            return ("bad", "api off",
                    "the key is good, Street View Static is off on its project",
                    False)
        if "billing" in low:
            return ("bad", "billing off",
                    "billing is not enabled on the project behind this key",
                    False)
        if "expired" in low:
            return ("bad", "expired", "the key has expired", False)
        return ("bad", "denied", msg or "no reason given", False)
    if s == "OVER_QUERY_LIMIT":
        return ("bad", "over cap",
                "the cap is reached. The key is valid and refused until it "
                "resets or is raised", False)
    if s == "INVALID_REQUEST":
        return ("warn", "invalid request", "the probe is wrong, not the key", None)
    return ("warn", s or "http %s" % status, msg or "unexpected", None)


def probe_geocode(key):
    """A second Google API on the same key. Two APIs answering differently
    is what separates 'this key is dead' from 'this one API is switched
    off', and that is a different afternoon's work to fix."""
    status, body, err = _req(GEOCODE % key)
    if err:
        return ("warn", "no answer", str(err), None)
    d = _json(body)
    s = d.get("status", "")
    msg = d.get("error_message", "")
    if s in ("OK", "ZERO_RESULTS"):
        return ("ok", s, "accepted for Geocoding too", True)
    if s == "REQUEST_DENIED":
        low = msg.lower()
        if "referer" in low or "referrer" in low:
            return ("warn", "browser only", "same restriction here", False)
        if "not authorized" in low or "disabled" in low:
            return ("warn", "api off",
                    "Geocoding is off on this project, which may be deliberate",
                    False)
        if "billing" in low:
            return ("bad", "billing off", "billing is not enabled", False)
        return ("warn", "denied", msg or "no reason given", False)
    if s == "OVER_QUERY_LIMIT":
        return ("bad", "over cap", "the cap has been reached", False)
    return ("warn", s or "http %s" % status, msg or "unexpected", None)


def probe_gemini(key):
    status, body, err = _req(GEMINI, headers={"x-goog-api-key": key})
    if err:
        return ("warn", "no answer", str(err), None)
    d = _json(body)
    if status == 200:
        models = d.get("models", [])
        names = [m.get("name", "").replace("models/", "") for m in models]
        img = [n for n in names if "image" in n]
        detail = "%d models" % len(names)
        if img:
            detail += ", image models present"
        return ("ok", "accepted", detail, True)
    e = d.get("error", {})
    msg = (e.get("message") or "").strip()
    reason = ""
    for det in e.get("details", []) or []:
        if det.get("reason"):
            reason = det["reason"]
            break
    if status == 429 or reason == "RESOURCE_EXHAUSTED":
        # The one that gets lost, and losing it burns working keys.
        return ("warn", "429, throttled",
                "valid and rate limited. This is NOT a dead key and must "
                "never be condemned for it", True)
    if status == 400:
        return ("bad", "invalid key", msg or "rejected", False)
    if status == 403:
        low = msg.lower()
        if "billing" in low:
            return ("bad", "billing off", msg, False)
        if "disabled" in low or "has not been used" in low or reason == "SERVICE_DISABLED":
            return ("bad", "api off",
                    "the Generative Language API is off on this project", False)
        return ("bad", "refused", msg or "403", False)
    if status == 401:
        # Measured 31.8.2026 with a real AQ. key whose last four characters
        # were changed. A malformed key in this format is not read as a bad
        # key but as a bad OAuth token, so the answer is 401 and not 400.
        # The status mapping says 401 is a dead credential, so it is named
        # as one rather than left as a bare number.
        return ("bad", "not accepted", "the credential was refused outright", False)
    if status == 404:
        return ("warn", "404", "the probe URL is wrong, not the key", None)
    return ("warn", "http %s" % status, msg or "unexpected", None)


# ---------------------------------------------------------------------------

WIDTH = 42


def line(level, label, verdict, detail):
    """A phone terminal is about fifty characters and the rule is that
    nothing goes off the screen. Google's own refusals arrive three lines
    long with two URLs in them, so the row is STACKED rather than having
    its columns narrowed: verdict and label on one line, the reason
    underneath, wrapped. Narrowing the columns would not remove the
    clipping, it would only move it to a different word."""
    import textwrap
    # The verdict column is sized to the longest verdict there is, not to a
    # number that looked about right. At nine it clipped "not a maps key" to
    # "not a map", which is a word cut to fit a layout instead of a layout
    # sized to its words.
    print("     %s%-14s%s %s%s%s"
          % (C[level], verdict[:14], C["off"], C["key"], label, C["off"]))
    # A URL in a wrapped message is a single unbreakable word that is
    # longer than the line, so wrapping alone cannot hold the promise.
    # The URLs are dropped: the sentence carries the meaning and the link
    # is not something anybody follows from a phone terminal.
    d = (detail or "").split(" Learn more")[0]
    d = re.sub(r"https?://\S+", "", d)
    d = re.sub(r"\s+", " ", d).strip().rstrip(":").strip()
    for chunk in textwrap.wrap(d, WIDTH, break_long_words=True) or []:
        print("       %s%s%s" % (C["dim"], chunk, C["off"]))


def test_key(key, quiet=False):
    print("\n  %s%s%s" % (C["key"], name_of(key), C["off"]))
    results = {}
    # An AQ. key is a Generative Language credential and Maps has never
    # heard of it. Its refusal there is the correct answer to the wrong
    # question, so it is reported quietly. A tester that paints an expected
    # answer red teaches the person to ignore red.
    gemini_shaped = key.startswith("AQ.")
    for label, fn in (("street view", probe_streetview),
                      ("geocoding", probe_geocode),
                      ("gemini", probe_gemini)):
        level, verdict, detail, good = fn(key)
        if gemini_shaped and label in ("street view", "geocoding") and not good:
            level, verdict = "dim", "not maps"
            detail = "expected: the AQ. format is a Gemini credential"
        results[label] = (level, verdict, good)
        if not quiet:
            line(level, label, verdict, detail)
        time.sleep(0.2)

    maps_ok = results["street view"][2] or results["geocoding"][2]
    gem_ok = results["gemini"][2]
    restricted = any(r[1] == "browser only" for r in results.values())

    if gem_ok and not maps_ok:
        v, lvl = "a Gemini key", "ok"
    elif maps_ok and not gem_ok:
        v, lvl = "a Maps key", "ok"
    elif maps_ok and gem_ok:
        v, lvl = "works for both Maps and Gemini", "ok"
    elif restricted:
        v, lvl = "browser only, locked to a referrer", "warn"
    else:
        v, lvl = "nothing accepted it", "bad"
    print("     %s%-14s%s %s%s%s" % (C[lvl], "verdict", C["off"], C["key"], v, C["off"]))
    return LEVEL_RANK.get(lvl, lvl)


def main(argv):
    keys = []
    seen = set()
    sources = {}

    for label, path in APP_KEYFILES:
        if os.path.exists(path):
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    for k in find_keys(f.read()):
                        if k not in seen:
                            seen.add(k)
                            keys.append(k)
                        sources.setdefault(k, []).append(label)
            except Exception:
                pass

    if "--file" in argv:
        p = argv[argv.index("--file") + 1]
        with open(p, encoding="utf-8", errors="replace") as f:
            text = f.read()
        found = find_keys(text)
        print("\n  %s%d keys found by shape in %s%s"
              % (C["dim"], len(found), os.path.basename(p), C["off"]))
        for k in found:
            if k not in seen:
                seen.add(k)
                keys.append(k)
            sources.setdefault(k, []).append("the note")

    if not keys:
        print("\n  no keys on this phone yet. maha-commute key, then p, pastes one.\n")
        return 1

    print("\n  %sKEY TESTER%s  %d keys, none is printed"
          % (C["key"], C["off"], len(keys)))
    print("  %sthe cheapest question each provider has,%s" % (C["dim"], C["off"]))
    print("  %snothing generated, nothing billed%s" % (C["dim"], C["off"]))

    counts = {"ok": 0, "warn": 0, "bad": 0}
    for k in keys:
        lvl = test_key(k, "--quiet" in argv)
        counts[lvl] += 1
        where = sources.get(k, [])
        if where:
            print("     %s%-14s %s%s" % (C["dim"], "held by",
                                        ", ".join(where), C["off"]))

    # Which key each app is really using. An app quietly holding a different
    # key from the one just tested is its own class of confusion, and it is
    # invisible unless somebody compares them.
    print("\n  %swhat each app is actually holding%s" % (C["key"], C["off"]))
    shared = None
    for label, path in APP_KEYFILES:
        if not os.path.exists(path):
            print("     %s%-20s none%s" % (C["dim"], label, C["off"]))
            continue
        with open(path, encoding="utf-8", errors="replace") as f:
            found = find_keys(f.read())
        if not found:
            print("     %s%-20s a file with no key shape in it%s"
                  % (C["warn"], label, C["off"]))
            continue
        fp = hashlib.sha256(found[0].encode()).hexdigest()[:4]
        if label == "shared store":
            shared = fp
            note = ""
        elif shared and fp != shared and "gemini" not in label:
            note = "  differs from the shared store"
        else:
            note = ""
        print("     %-20s fp %s%s" % (label, fp, note))

    print("\n  %d good, %d worth a look, %d refused"
          % (counts["ok"], counts["warn"], counts["bad"]))
    print("  %sno Google API reports a balance. Billing off," % C["dim"])
    print("  a cap reached and throttling are visible above.")
    print("  What is left to spend is only in the console.%s\n" % C["off"])
    return 0 if counts["bad"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
