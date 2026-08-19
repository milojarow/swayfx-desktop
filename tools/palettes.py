#!/usr/bin/env python3
"""Print the palette of every theme in this repo, colours resolved.

`theme.conf` stores colours indirectly — `$accent-color` points at `$cyan`,
which points at a hex value — so reading the file does not hand you the palette.
This resolves the chain and prints the table. Run it instead of trusting a
table someone typed by hand: this one cannot drift from the theme files.

    python3 tools/palettes.py           # table
    python3 tools/palettes.py --md      # markdown, for pasting into docs
    python3 tools/palettes.py <name>    # every colour of one theme
"""
import re, sys
from pathlib import Path

THEMES = Path(__file__).resolve().parent.parent/".config/sway/themes"

def resolve(conf, var, depth=0):
    m = re.search(rf'^set \${re.escape(var)}\s+(\S+)', conf, re.M)
    if not m: return None
    v = m.group(1)
    if v.startswith("$") and depth < 4: return resolve(conf, v[1:], depth+1)
    return v

KEYS = [("background-color", "bg"), ("text-color", "text"),
        ("accent-color", "accent"), ("selection-color", "selection"),
        ("gtk-color-scheme", "mode")]

def themes():
    for d in sorted(THEMES.iterdir()):
        c = d/"theme.conf"
        if c.exists(): yield d.name, c.read_text(encoding="utf-8")

args = sys.argv[1:]

if args and not args[0].startswith("-"):
    name = args[0]
    conf = dict(themes()).get(name)
    if conf is None:
        sys.exit(f"no such theme: {name}\navailable: {' '.join(n for n, _ in themes())}")
    for line in conf.split("\n"):
        m = re.match(r'^set \$(\S+)\s+(\S+)', line)
        if m:
            val = m.group(2)
            hexv = resolve(conf, m.group(1))
            print(f"  ${m.group(1):<18} {val:<28}" + (f"→ {hexv}" if val != hexv else ""))
    sys.exit(0)

md = "--md" in args
rows = [(n, *[resolve(c, k) or "?" for k, _ in KEYS]) for n, c in themes()]
head = ["theme"] + [lbl for _, lbl in KEYS]

if md:
    print("| " + " | ".join(head) + " |")
    print("|" + "|".join("---" for _ in head) + "|")
    for r in rows: print("| " + " | ".join(f"`{x}`" if x.startswith("#") else x for x in r) + " |")
else:
    w = [max(len(str(r[i])) for r in rows + [tuple(head)]) for i in range(len(head))]
    print("  ".join(h.ljust(w[i]) for i, h in enumerate(head)))
    print("-" * (sum(w) + 2*len(w)))
    for r in rows: print("  ".join(str(x).ljust(w[i]) for i, x in enumerate(r)))
