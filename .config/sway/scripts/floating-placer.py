#!/usr/bin/env python3
# ── Floating Placer ──────────────────────────────────────────────────────────
# Role:     Sway IPC event daemon that auto-positions newly-floating windows
#           into a free slot. Preference order: top-right → bottom-right →
#           top-left → bottom-left → 3x3 grid (right→left, top→bottom) →
#           cascade offset from top-right. Tiled windows are ignored; sticky
#           and PiP-style floatings count as occupying space. The daemon
#           reacts only to `new`/`floating` events — manual moves afterwards
#           are not undone.
# Files:    floating-placer.py
# Programs: swaymsg
# Daemon:   ~/.config/systemd/user/floating-placer.service
# Storage:  /tmp/floating-placer-$USER.pid (single-instance guard)
# ─────────────────────────────────────────────────────────────────────────────

import json
import os
import re
import subprocess
import sys

BORDER = 16   # margin from workspace edges
INTER = 12    # margin between floating windows
CASCADE = 40  # offset step when no slot fits

# Floatings whose app_id (Wayland) or window class (XWayland) matches any of
# these patterns are ignored entirely: the daemon does not move them and
# treats them as invisible when placing other windows. These are either
# decorative overlays that don't behave like normal floatings, or apps that
# expect to draw themselves at a fixed position (e.g. screenshot editors).
IGNORE_PATTERNS = (
    re.compile(r"^ueberzugpp_"),  # ranger image previews via ueberzugpp
    re.compile(r"^swappy$", re.IGNORECASE),  # screenshot editor — keep centered
    # Managed by floating-memory.py, which restores their exact saved position —
    # this daemon must not reposition them. Keep in sync with that file's
    # TRACK_PATTERNS.
    re.compile(r"^Altus$"),
    re.compile(r"telegram", re.IGNORECASE),  # org.telegram.desktop / TelegramDesktop
)

PIDFILE = f"/tmp/floating-placer-{os.environ.get('USER', 'user')}.pid"


def is_ignored(con):
    app_id = con.get("app_id") or ""
    wclass = (con.get("window_properties") or {}).get("class") or ""
    return any(p.search(app_id) or p.search(wclass) for p in IGNORE_PATTERNS)


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def swaymsg(*args):
    """Run swaymsg and return stdout. JSON queries return parsed objects."""
    result = subprocess.run(
        ["swaymsg", *args], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        log(f"swaymsg failed: {' '.join(args)} -> {result.stderr.strip()}")
    return result.stdout


def get_tree():
    return json.loads(swaymsg("-t", "get_tree"))


def walk(node, output_name=None, workspace_name=None, results=None):
    """Walk the tree yielding (node, output_name, workspace_name)."""
    if results is None:
        results = []
    t = node.get("type")
    if t == "output":
        output_name = node.get("name")
    elif t == "workspace":
        workspace_name = node.get("name")
    results.append((node, output_name, workspace_name))
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        walk(child, output_name, workspace_name, results)
    return results


def find_con(tree, con_id):
    """Return (node, output_name, workspace_name) for the given con_id."""
    for node, out, ws in walk(tree):
        if node.get("id") == con_id:
            return node, out, ws
    return None, None, None


def visible_floatings(tree, output_name, exclude_id):
    """Floating cons currently visible on `output_name`, minus exclude_id.
    Excludes scratchpad-hidden cons (workspace name `__i3_scratch`)."""
    out = []
    # Build a map: for each output, which workspace is currently focused/visible.
    # Sway exposes this via get_workspaces (visible=true), which we query once.
    visible_ws = {
        ws["output"]: ws["name"]
        for ws in json.loads(swaymsg("-t", "get_workspaces"))
        if ws.get("visible")
    }
    target_ws = visible_ws.get(output_name)
    if target_ws is None:
        return out
    for node, o, ws in walk(tree):
        if node.get("type") != "floating_con":
            continue
        if node.get("id") == exclude_id:
            continue
        if o != output_name or ws != target_ws:
            continue
        if is_ignored(node):
            continue
        out.append(node)
    return out


def get_workspace_rect(tree, output_name, workspace_name):
    for node, o, ws in walk(tree):
        if node.get("type") == "workspace" and o == output_name and node.get("name") == workspace_name:
            return node["rect"]
    return None


def overlaps(a, others, margin):
    """a is (x, y, w, h). others is a list of con dicts. margin expands others."""
    ax, ay, aw, ah = a
    for o in others:
        r = o["rect"]
        ox, oy, ow, oh = r["x"] - margin, r["y"] - margin, r["width"] + 2 * margin, r["height"] + 2 * margin
        if ax < ox + ow and ax + aw > ox and ay < oy + oh and ay + ah > oy:
            return True
    return False


def bounded(rect, ws):
    x, y, w, h = rect
    return (
        x >= ws["x"] and y >= ws["y"]
        and x + w <= ws["x"] + ws["width"]
        and y + h <= ws["y"] + ws["height"]
    )


def corner_pos(corner, ws, w, h):
    """corner ∈ {TR, BR, TL, BL}. Returns (x, y) absolute."""
    if corner == "TR":
        return ws["x"] + ws["width"] - w - BORDER, ws["y"] + BORDER
    if corner == "BR":
        return ws["x"] + ws["width"] - w - BORDER, ws["y"] + ws["height"] - h - BORDER
    if corner == "TL":
        return ws["x"] + BORDER, ws["y"] + BORDER
    if corner == "BL":
        return ws["x"] + BORDER, ws["y"] + ws["height"] - h - BORDER
    raise ValueError(corner)


def grid_pos(col, row, ws, w, h):
    """col ∈ {right, mid, left}, row ∈ {top, mid, bottom}. Returns (x, y)."""
    if col == "right":
        x = ws["x"] + ws["width"] - w - BORDER
    elif col == "left":
        x = ws["x"] + BORDER
    else:
        x = ws["x"] + (ws["width"] - w) // 2
    if row == "top":
        y = ws["y"] + BORDER
    elif row == "bottom":
        y = ws["y"] + ws["height"] - h - BORDER
    else:
        y = ws["y"] + (ws["height"] - h) // 2
    return x, y


def place(con):
    con_id = con["id"]
    tree = get_tree()
    located, output_name, workspace_name = find_con(tree, con_id)
    if located is None or output_name is None or workspace_name is None:
        log(f"con {con_id} not found in tree, skipping")
        return
    ws_rect = get_workspace_rect(tree, output_name, workspace_name)
    if ws_rect is None:
        log(f"workspace rect not found for {output_name}/{workspace_name}")
        return
    floatings = visible_floatings(tree, output_name, con_id)
    w = located["rect"]["width"]
    h = located["rect"]["height"]

    # Pass 1: corners (TR, BR, TL, BL)
    for corner in ("TR", "BR", "TL", "BL"):
        x, y = corner_pos(corner, ws_rect, w, h)
        candidate = (x, y, w, h)
        if bounded(candidate, ws_rect) and not overlaps(candidate, floatings, INTER):
            return move(con_id, x, y, f"corner {corner}", located)

    # Pass 2: 3x3 grid (right→left, top→bottom)
    for col in ("right", "mid", "left"):
        for row in ("top", "mid", "bottom"):
            x, y = grid_pos(col, row, ws_rect, w, h)
            candidate = (x, y, w, h)
            if bounded(candidate, ws_rect) and not overlaps(candidate, floatings, INTER):
                return move(con_id, x, y, f"grid {col}/{row}", located)

    # Pass 3: cascade from top-left
    n = len(floatings)
    x = ws_rect["x"] + BORDER + n * CASCADE
    y = ws_rect["y"] + BORDER + n * CASCADE
    move(con_id, x, y, f"cascade TL n={n}", located)


def move(con_id, x, y, reason, con=None):
    cmd = f"[con_id={con_id}] move absolute position {x} {y}"
    if con is not None:
        log(
            f"placing {con_id} at ({x},{y}) — {reason} | "
            f"app_id={con.get('app_id')!r} class={(con.get('window_properties') or {}).get('class')!r} "
            f"name={con.get('name')!r} pid={con.get('pid')} "
            f"size={con['rect']['width']}x{con['rect']['height']}"
        )
    else:
        log(f"placing {con_id} at ({x},{y}) — {reason}")
    swaymsg(cmd)


def single_instance():
    if os.path.exists(PIDFILE):
        try:
            old = int(open(PIDFILE).read().strip())
            os.kill(old, 15)  # SIGTERM
        except (ValueError, ProcessLookupError, PermissionError):
            pass
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))


def main():
    single_instance()
    log("floating-placer subscribed to sway IPC")
    proc = subprocess.Popen(
        ["swaymsg", "-t", "subscribe", "-m", '["window"]'],
        stdout=subprocess.PIPE, text=True, bufsize=1,
    )
    for line in proc.stdout:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("change") not in ("new", "floating"):
            continue
        con = event.get("container") or {}
        if con.get("type") != "floating_con":
            continue
        if is_ignored(con):
            continue
        try:
            place(con)
        except Exception as exc:
            log(f"place() failed for con {con.get('id')}: {exc}")


if __name__ == "__main__":
    main()
