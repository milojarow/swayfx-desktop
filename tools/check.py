#!/usr/bin/env python3
"""Gate for this repo. Exit 0 = shippable. Non-zero = do not publish.

Three defect classes, all invisible to the eye in a 300-file tree, all of
which a future re-export can reintroduce:

  1. syntax    a script that cannot even parse
  2. leaks     an identifier or an absolute home path from the machine this
               config was exported from
  3. dangling  a config that names a file the repo does not ship

Reruns on an unchanged tree must agree. If two runs disagree, the checker is
the suspect, not the tree.

    python3 tools/check.py
"""
import os, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
fails, warns = [], []
def bad(m):  fails.append(m); print(f"  \033[31m✗\033[0m {m}")
def warn(m): warns.append(m); print(f"  \033[33m!\033[0m {m}")
def ok(m):   print(f"  {m}")

# What ships is what git tracks. Checking the working tree instead would flag
# gitignored operator files (CLAUDE.md, .claude/) that never leave this machine.
def shipped():
    # --cached --others --exclude-standard = lo que se publicaría si commiteas
    # AHORA: lo trackeado más lo nuevo que no está gitignoreado. Con solo
    # --cached, un archivo recién agregado al árbol no se revisa hasta después
    # del commit, que es cuando la compuerta ya no puede detener nada.
    r = subprocess.run(["git", "ls-files", "-z", "--cached", "--others",
                        "--exclude-standard"], capture_output=True, cwd=ROOT)
    if r.returncode == 0 and r.stdout:
        return [ROOT / f for f in r.stdout.decode().split("\0") if f]
    skip = {".git", ".claude", "__pycache__"}
    return [p for p in ROOT.rglob("*")
            if p.is_file() and not skip & set(p.parts) and p.name != "CLAUDE.md"]

FILES = shipped()
def text(p):
    try: return p.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError): return None

# ── 1. syntax ────────────────────────────────────────────────────────────────
print("── 1. syntax")
sh = py = 0
for p in FILES:
    t = text(p)
    if t is None: continue
    first = t.split("\n", 1)[0]
    if re.match(r"^#!.*\b(bash|sh)$", first):
        sh += 1
        if subprocess.run(["bash", "-n", str(p)], capture_output=True).returncode:
            bad(f"bash -n falla: {p.relative_to(ROOT)}")
    if p.suffix == ".py":
        py += 1
        if subprocess.run([sys.executable, "-m", "py_compile", str(p)],
                          capture_output=True).returncode:
            bad(f"python no compila: {p.relative_to(ROOT)}")
ok(f"{sh} scripts de shell, {py} de python")
subprocess.run(["find", ".", "-name", "__pycache__", "-type", "d",
                "-exec", "rm", "-rf", "{}", "+"], capture_output=True)

# ── 2. leaks ─────────────────────────────────────────────────────────────────
print("── 2. leaks")
# Only $HOME, %h, ~ and __HOME__ are legal ways to name the user's home.
HOMEPATH = re.compile(r"/home/[a-z][a-z0-9_-]*/")
# Identifiers belonging to the operator this config was exported from.
LEAKS = re.compile(r"\b(selene|helios|endymion|solutions45|blindando|jungla"
                   r"|espocrm|ahuja|camioncito|la[- ]perlita"
                   r"|taqueria[- ]texas|loteria[- ]lulu)\b", re.I)
nh = nl = 0
for p in FILES:
    if p == Path(__file__): continue
    t = text(p)
    if t is None: continue
    for i, line in enumerate(t.split("\n"), 1):
        if HOMEPATH.search(line):
            bad(f"home absoluto: {p.relative_to(ROOT)}:{i}: {line.strip()[:90]}"); nh += 1
        if LEAKS.search(line):
            bad(f"identificador: {p.relative_to(ROOT)}:{i}: {line.strip()[:90]}"); nl += 1
if not nh: ok("0 rutas /home/<user>/ hardcodeadas")
if not nl: ok("0 identificadores personales")

# ── 3. dangling refs ─────────────────────────────────────────────────────────
print("── 3. dangling refs")
# Created at runtime or owned by another tool — legitimately absent from a
# fresh checkout. The theme files are written by the palette system.
RUNTIME = re.compile(r"""^(
    \.cache | \.cargo | \.dotfiles | \.claude | \.secrets | \.ssh
  | \.local/(state|lib|log|src)
  | \.local/share/(applications|cliphist|bemoji|containers|Trash|wallpapers)
  | \.config/(autostart|fontconfig|nchat|dotfiles-hosts\.conf|wob\.ini)
  | \.config/swayidle/config
  | \.config/sway/(generated_background\.svg|autostart\.log|definitions\.d/theme)
  | \.config/(eww/styles/theme\.scss|waybar/theme\.css|wofi/style\.css
             |gtk-4\.0/gtk\.css|rofi/cachyos\.rasi|foot/foot-theme
             |wlsunset/config|ghostty/colors|wezterm/colors\.lua
             |alacritty/colors\.toml)
  | projects | pond | documents | downloads | media | pictures
  | recordings | Screenshots | Videos
  | \.local/auto-theme-toggle | \.local/share/clipboard-pins
  | \.local/share/meeting-notes | \.config/huggingface
)""", re.X)
COMMENT = re.compile(r"^\s*([#;]|//|\.\\\")")
REF = re.compile(r"(?:\$HOME|~)/[A-Za-z0-9_.@/\\-]+")

refs = {}                                    # rel path -> [(file, lineno, is_comment)]
for p in FILES:
    t = text(p)
    if t is None: continue
    for i, line in enumerate(t.split("\n"), 1):
        clean = re.sub(r"\\f[A-Z]", "", line).replace("\\", "")
        for m in REF.finditer(clean):
            # roff escapes a literal hyphen as \- ; undo before resolving
            r = m.group(0).split("/", 1)[1].rstrip("/.,;:'\")")
            if not r: continue
            refs.setdefault(r, []).append((p, i, bool(COMMENT.match(line))))

miss = 0
for r, sites in sorted(refs.items()):
    if RUNTIME.match(r) or (ROOT / r).exists() or (ROOT / (r + ".rasi")).exists(): continue
    where = f"{sites[0][0].relative_to(ROOT)}:{sites[0][1]}"
    if all(c for _, _, c in sites):
        warn(f"citado solo en comentarios, no existe: {r}  ({where})")
    else:
        bad(f"citado y no existe: {r}  ({where})"); miss += 1
ok(f"{len(refs)} rutas citadas, {miss} rotas, {len(warns)} solo-en-comentario")

# ── 4. eww graph ─────────────────────────────────────────────────────────────
print("── 4. eww graph")
broken = 0
for f, pat in [(".config/eww/eww.yuck", r'^\(include "\./([^"]+)"'),
               (".config/eww/eww.scss", r'^@import "\./([^"]+)"')]:
    for i, line in enumerate((ROOT / f).read_text(encoding="utf-8").split("\n"), 1):
        if COMMENT.match(line): continue          # deprecated includes stay commented
        m = re.match(pat, line)
        if m and not (ROOT / ".config/eww" / m.group(1)).exists():
            bad(f"{f}:{i} apunta a archivo ausente: {m.group(1)}"); broken += 1
ok(f"grafo de eww: {broken} referencias rotas")

print()
print("\033[32mPASA\033[0m" if not fails else f"\033[31mNO PASA\033[0m ({len(fails)} fallas)")
sys.exit(1 if fails else 0)
