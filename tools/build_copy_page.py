#!/usr/bin/env python3
"""build_copy_page.py: the page that gives every README command a real copy button.

    tools/build_copy_page.py           write docs/index.html (and docs/.nojekyll)
    tools/build_copy_page.py --check   exit 1 if the page is stale, or if a command in
                                       the README has no link to its card under it

WHY THIS EXISTS. GitHub's website puts a copy button on every code block of a
README. The GitHub APP does not: it draws the block itself, with no button, and
cuts a long line off at the edge of the screen. Markdown cannot carry a button
of its own, so the only button that works in the app is on a page the app
can open. Each command block tagged `sh` in README.md is a card on this page,
with a large Copy button, and the README has a link under the block that opens
that card.

THE PAGE IS GENERATED, NOT WRITTEN, for the reason src/ is: a command typed
into the README and again into a page is two copies with a rule about keeping
them in step, and the rule is eventually not followed. The card text IS the
README block, byte for byte, and --check is what keeps it so.

Nothing on the page runs anything. It copies text.
"""
import html, os, re, sys
from markdown_it import MarkdownIt

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
README = os.path.join(ROOT, "README.md")
PAGE = os.path.join(ROOT, "docs", "index.html")
BASE = "https://markoboskoauroville.github.io/MAHA_COMMUTE/"


def blocks(text):
    """The `sh` blocks of the README in order: (label, command, end_line)."""
    toks = MarkdownIt("commonmark").parse(text)
    out, heading, label = [], "", ""
    for i, t in enumerate(toks):
        if t.type == "heading_open":
            heading = toks[i + 1].content.strip()
        if t.type == "paragraph_open":
            inl = toks[i + 1]
            # the parser leaves empty text pieces either side of a bold label
            kids = [c for c in inl.children if c.type != "softbreak" and not (c.type == "text" and c.content == "")]
            if len(kids) == 3 and kids[0].type == "strong_open" and len(inl.content) <= 60:
                label = inl.content.strip("* ").strip()
            else:
                label = ""
        if t.type == "fence" and t.info.strip() in ("sh", "bash"):
            out.append((label or heading or "command", t.content.rstrip("\n"), t.map[1]))
            label = ""
    return out


CSS = """
:root{--bg:#0d1117;--card:#161b22;--line:#30363d;--text:#e6edf3;--muted:#8b949e;--amber:#d4a017;--ok:#3fb950}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:17px/1.5 system-ui,sans-serif;padding:18px 14px 60px;max-width:640px;margin:auto}
h1{font-size:1.35rem;margin:6px 0 4px}
p.note{color:var(--muted);font-size:.9rem;margin:0 0 18px}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px;margin:0 0 16px}
.card h2{font-size:1rem;margin:0 0 10px;color:var(--amber)}
pre{margin:0 0 12px;background:#0b0f14;border:1px solid var(--line);border-radius:10px;padding:12px;
    white-space:pre-wrap;word-break:break-all;font:14px/1.45 ui-monospace,Menlo,Consolas,monospace;user-select:all;-webkit-user-select:all}
button{display:block;width:100%;min-height:58px;border:0;border-radius:12px;background:var(--amber);color:#1a1300;
       font:700 1.1rem system-ui,sans-serif;cursor:pointer}
button.done{background:var(--ok);color:#04110a}
.hint{color:var(--muted);font-size:.85rem;margin:8px 0 0;min-height:1.2em}
"""

JS = """
function flash(b, msg, ok){ b.textContent = msg; b.classList.toggle('done', !!ok);
  setTimeout(function(){ b.textContent = 'Copy'; b.classList.remove('done'); }, 2200); }
function selectIt(pre){ var r = document.createRange(); r.selectNodeContents(pre);
  var s = getSelection(); s.removeAllRanges(); s.addRange(r); }
async function copyCard(b){
  var pre = b.parentNode.querySelector('pre'), text = pre.textContent, hint = b.parentNode.querySelector('.hint');
  hint.textContent = '';
  try { await navigator.clipboard.writeText(text); flash(b, 'Copied', true); return; } catch (e) {}
  try { var ta = document.createElement('textarea'); ta.value = text; ta.setAttribute('readonly','');
        ta.style.position='fixed'; ta.style.opacity='0'; document.body.appendChild(ta); ta.select();
        var ok = document.execCommand('copy'); document.body.removeChild(ta);
        if (ok) { flash(b, 'Copied', true); return; } } catch (e) {}
  selectIt(pre); hint.textContent = 'The phone would not let a page copy. The command is selected: long-press it and choose Copy.';
}
"""


def page(text):
    cards = []
    for n, (label, cmd, _end) in enumerate(blocks(text), 1):
        cards.append('<section class="card" id="cmd-%d"><h2>%s</h2><pre>%s</pre>'
                     '<button type="button" onclick="copyCard(this)">Copy</button><p class="hint"></p></section>'
                     % (n, html.escape(label), html.escape(cmd)))
    return ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>MAHA COMMUTE, copy a command</title><style>%s</style></head><body>'
            '<h1>MAHA COMMUTE</h1><p class="note">Tap Copy, then paste into Termux. Nothing on this page runs anything.</p>'
            '%s<script>%s</script></body></html>\n' % (CSS, "\n".join(cards), JS))


def readme_links_ok(text):
    """Every command block has a link to its own card on the line after it."""
    lines, bad = text.split("\n"), []
    for n, (label, cmd, end) in enumerate(blocks(text), 1):
        want = BASE + "#cmd-%d" % n
        nxt = " ".join(lines[end:end + 3])
        if want not in nxt:
            bad.append(n)
    return bad


def main():
    text = open(README, encoding="utf-8").read()
    out = page(text)
    if "--check" in sys.argv:
        stale = (not os.path.exists(PAGE)) or open(PAGE, encoding="utf-8").read() != out
        missing = readme_links_ok(text)
        if stale: print("stale: docs/index.html does not match the README, run tools/build_copy_page.py")
        if missing: print("no copy link under README command block(s): %s" % missing)
        if not stale and not missing:
            print("fresh: %d command cards, every one linked from the README" % len(blocks(text)))
        sys.exit(1 if (stale or missing) else 0)
    os.makedirs(os.path.dirname(PAGE), exist_ok=True)
    open(PAGE, "w", encoding="utf-8").write(out)
    open(os.path.join(os.path.dirname(PAGE), ".nojekyll"), "w").write("")
    print("wrote docs/index.html with %d command cards" % len(blocks(text)))


if __name__ == "__main__":
    main()
