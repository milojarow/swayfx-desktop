#!/usr/bin/env python3
# feature: workspaces
# role:    subscribe
"""
workspace-subscribe.py — eww deflisten source for the bar workspace widget.

Emits a JSON array on startup and on every sway workspace/window event.
Tracks the last-focused window per workspace to determine the displayed icon.
"""

import json
import os
import socket
import struct
import subprocess
import sys
import time

# ── Icon map ──────────────────────────────────────────────────────────────────
# Keys are lowercase app_id or window class (substring match as fallback).
ICON_MAP = {
    # Terminals
    "foot":                    "\ue285",
    "kitty":                   "\uea85",
    "alacritty":               "\uea85",
    "wezterm":                 "\uea85",
    "com.mitchellh.ghostty":   "\ue007",
    "ghostty":                 "\ue007",
    # Browsers
    "firefox":                 "\ue745",
    "librewolf":               "\ue745",
    "brave-browser":           "\ue639",
    "brave":                   "\ue639",
    # Messaging
    "altus":                   "\uf232",
    "org.telegram.desktop":    "\ue217",
    "telegramdesktop":         "\ue217",
    "discord":                 "\uf1ff",
    "vencord":                 "\uf1ff",
    # File browsers
    "nemo":                    "\uf114",
    "nautilus":                "\uf114",
    "org.gnome.nautilus":      "\uf114",
    "thunar":                  "\uf114",
    "pcmanfm":                 "\uf114",
    "ranger":                  "\uf114",
    # PDF viewers
    "org.pwmt.zathura":        "\U000f0226",
    "evince":                  "\U000f0226",
    "okular":                  "\U000f0226",
    # Text editors / IDEs
    "code":                    "\U000f1a7c",
    "vscodium":                "\U000f1a7c",
    "vscodium-url-handler":    "\U000f1a7c",
    "gedit":                   "\U000f1a7c",
    "kate":                    "\U000f1a7c",
    # Email
    "betterbird":              "\ueb1c",
    "thunderbird":             "\ueb1c",
    # Claude desktop
    "claude":                  "\U000f09d1",
    # Obsidian
    "obsidian":                "\ue2a6",
    # VLC
    "vlc":                     "\U000f057c",
    # pessoa
    "pessoa":        "\U000f0b5f",
    # Firefox with custom profile (app_id = profile name)
    # MongoDB Compass
    "mongodb compass":         "\U000f032a",  # leaf (database tooling)
}

ICON_UNKNOWN         = "\uebf2"
ICON_SCRATCHPAD_ONE  = "\U000f05af"
ICON_SCRATCHPAD_MANY = "\U000f05b2"
ICON_WS10            = "\U000F153C"  # secret workspace icon (U+F153C)

# Subscript number icons (Nerd Font U+F0B3A–U+F0B42) for workspace overlays.
# Workspace 10 and scratchpad (-1) fall back to plain string.
NUM_ICONS = {
    1: "\U000F0B3A",
    2: "\U000F0B3B",
    3: "\U000F0B3C",
    4: "\U000F0B3D",
    5: "\U000F0B3E",
    6: "\U000F0B3F",
    7: "\U000F0B40",
    8: "\U000F0B41",
    9: "\U000F0B42",
}

ALWAYS_SHOW = set(range(1, 10))  # workspaces 1-9 always visible


# ── Helpers ───────────────────────────────────────────────────────────────────

# ── sway IPC over a persistent socket (no per-event subprocess) ────────────────
# Querying via a long-lived UNIX socket instead of spawning `swaymsg` each event
# keeps the event path off fork()/execve() — the costly syscalls that stall the
# bar under memory pressure (binary + libs paged out to swap -> disk reads on the
# critical path). This is the same approach waybar uses to stay responsive.
# Protocol: 6-byte magic + u32 length + u32 type, native byte order.
_IPC_MAGIC = b"i3-ipc"
_MSG_GET_WORKSPACES = 1
_MSG_SUBSCRIBE = 2
_MSG_GET_TREE = 4
# Event message types (high bit set). Classify the event by type, not by
# payload, so a "focus" change can be told apart workspace-vs-window.
_EVT_WORKSPACE = 0x80000000
_EVT_WINDOW = 0x80000003
_SWAYSOCK = os.environ.get("SWAYSOCK", "")


def _ipc_connect():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(_SWAYSOCK)
    return s


def _recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise OSError("sway IPC socket closed")
        buf += chunk
    return buf


def _ipc_send(sock, msg_type, payload=b""):
    sock.sendall(_IPC_MAGIC + struct.pack("=II", len(payload), msg_type) + payload)


def _ipc_read(sock):
    hdr = _recv_exact(sock, 14)
    length, msg_type = struct.unpack("=II", hdr[6:14])
    return msg_type, _recv_exact(sock, length)


_query_sock = None


def swaymsg(args):
    """Drop-in replacement for the old subprocess helper. Routes get_tree /
    get_workspaces over a persistent socket; reconnects once if it has died."""
    global _query_sock
    if "get_tree" in args:
        msg_type = _MSG_GET_TREE
    elif "get_workspaces" in args:
        msg_type = _MSG_GET_WORKSPACES
    else:
        raise ValueError("unsupported swaymsg args: {}".format(args))
    for attempt in range(2):
        try:
            if _query_sock is None:
                _query_sock = _ipc_connect()
            _ipc_send(_query_sock, msg_type)
            _, data = _ipc_read(_query_sock)
            return json.loads(data)
        except OSError:
            if _query_sock is not None:
                try:
                    _query_sock.close()
                except OSError:
                    pass
            _query_sock = None
            if attempt == 1:
                raise
    return None


def get_app_id(node):
    return (
        node.get("app_id")
        or (node.get("window_properties") or {}).get("class")
        or ""
    )


def icon_for(app_id):
    if not app_id:
        return ICON_UNKNOWN
    key = app_id.lower()
    if key in ICON_MAP:
        return ICON_MAP[key]
    for pattern, icon in ICON_MAP.items():
        if pattern in key or key in pattern:
            return icon
    return ICON_UNKNOWN


def icon_for_leaf(leaf):
    """Resolve the icon for a sway leaf node."""
    return icon_for(get_app_id(leaf))


def walk_leaves(node, results):
    """Collect all leaf window nodes recursively."""
    children = node.get("nodes", []) + node.get("floating_nodes", [])
    if not children and node.get("type") not in ("root", "output", "workspace"):
        results.append(node)
    for child in children:
        walk_leaves(child, results)


def find_node(node, predicate):
    if predicate(node):
        return node
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        r = find_node(child, predicate)
        if r:
            return r
    return None


def get_workspaces_in_tree(tree):
    """Return all workspace nodes from the tree."""
    results = []
    def walk(n):
        if n.get("type") == "workspace":
            results.append(n)
        for c in n.get("nodes", []) + n.get("floating_nodes", []):
            walk(c)
    walk(tree)
    return results


def get_scratchpad_windows(tree):
    scratch = find_node(tree, lambda n: n.get("name") == "__i3_scratch")
    if not scratch:
        return []
    return scratch.get("floating_nodes", [])


def compute_icon_lines(icons):
    """Return (top, mid, bot) row strings for the geometric icon display.

    Only 'top' is always non-empty.  'mid' and 'bot' are empty string ""
    when unused — callers should check has_mid / has_bot before rendering.

    Shapes (center-aligned labels give the geometric feel):
      1 → top=A                           single
      2 → top=AB                          pair
      3 → top=A,   mid=BC                 △  1+2
      4 → top=AB,  mid=CD                 □  2+2
      5 → top=AB,  mid=CDE               ⬠  2+3
      6 → top=ABC, mid=DEF               ⬡  3+3
      7 → top=ABC, mid=DEF, bot=G
      8 → top=ABC, mid=DEF, bot=GH
      9+→ top=ABC, mid=DEF, bot=GHI       (capped at 9 icons)
    """
    n = len(icons)
    j = "".join
    if n <= 2: return j(icons),       "",           ""
    if n == 3: return icons[0],       j(icons[1:]), ""
    if n == 4: return j(icons[:2]),   j(icons[2:]), ""
    if n == 5: return j(icons[:2]),   j(icons[2:]), ""
    if n == 6: return j(icons[:3]),   j(icons[3:]), ""
    return     j(icons[:3]),   j(icons[3:6]),j(icons[6:9])


# ── State update ──────────────────────────────────────────────────────────────

def update_last_focused(last_focused, tree):
    """Walk tree and update last_focused[ws_num] for any focused leaf."""
    def walk(node, ws_num):
        if node.get("type") == "workspace":
            try:
                ws_num = int(node.get("num", -99))
            except (ValueError, TypeError):
                ws_num = -99
        if node.get("focused") and ws_num not in (-99, -1):
            app = get_app_id(node)
            if app:
                last_focused[ws_num] = app
        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            walk(child, ws_num)
    walk(tree, -99)


# ── Output builder ────────────────────────────────────────────────────────────

def build_output(last_focused, tree, ws_raw):
    ws_by_num = {ws["num"]: ws for ws in ws_raw}

    result = []

    for num in range(1, 10):
        raw = ws_by_num.get(num, {"num": num, "name": str(num),
                                   "focused": False, "urgent": False})
        ws_name = raw.get("name", str(num))

        # Find workspace node in tree
        ws_node = find_node(tree,
            lambda n, name=ws_name: n.get("type") == "workspace" and n.get("name") == name
        )

        leaves = []
        if ws_node:
            walk_leaves(ws_node, leaves)
        has_windows = len(leaves) > 0

        if has_windows:
            icon_list = [icon_for_leaf(leaf) for leaf in leaves]
            icon      = "".join(icon_list)
            top, mid, bot = compute_icon_lines(icon_list)
        else:
            icon      = str(num)
            top, mid, bot = str(num), "", ""

        result.append({
            "num":         num,
            "num_icon":    NUM_ICONS.get(num, str(num)),
            "name":        ws_name,
            "focused":     raw.get("focused", False),
            # Sway 1.11: workspace urgent flag sticks after urgent window moves away
            "urgent":      raw.get("urgent", False) and any(l.get("urgent", False) for l in leaves),
            "has_windows": has_windows,
            "icon":        icon,
            "icon_top":    top,
            "icon_mid":    mid,
            "icon_bot":    bot,
            "has_mid":     mid != "",
            "has_bot":     bot != "",
            "secret":      False,
            "cmd":         "swaymsg workspace {}".format(num),
        })

    # Workspace 10 — secret workspace: only visible when focused, fixed icon, no num, no app icons
    if 10 in ws_by_num and ws_by_num[10].get("focused"):
        raw10 = ws_by_num[10]
        result.append({
            "num":         10,
            "num_icon":    "",
            "name":        raw10.get("name", "10"),
            "focused":     True,
            "urgent":      raw10.get("urgent", False),
            "has_windows": False,
            "icon":        ICON_WS10,
            "icon_top":    ICON_WS10,
            "icon_mid":    "",
            "icon_bot":    "",
            "has_mid":     False,
            "has_bot":     False,
            "secret":      True,
            "cmd":         "swaymsg workspace 10",
        })

    # Scratchpad — only if it has content
    scratch_wins = get_scratchpad_windows(tree)
    if scratch_wins:
        count = len(scratch_wins)
        scratch_icon = ICON_SCRATCHPAD_ONE if count == 1 else ICON_SCRATCHPAD_MANY
        result.append({
            "num":         -1,
            "num_icon":    "-1",
            "name":        "scratchpad",
            "focused":     False,
            "urgent":      False,
            "has_windows": True,
            "icon":        scratch_icon,
            "icon_top":    scratch_icon,
            "icon_mid":    "",
            "icon_bot":    "",
            "has_mid":     False,
            "has_bot":     False,
            "secret":      False,
            "cmd":         "swaymsg scratchpad show",
        })

    return result


def emit(data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


# ── Main ──────────────────────────────────────────────────────────────────────

_LAG_LOG = os.path.expanduser("~/.cache/eww/workspaces-lag.log")
_LAG_MS = 80.0


def _log_lag(change, ms):
    """Record an event whose cycle exceeded the lag threshold, with memory
    pressure at that moment. Only runs when already slow, so it costs nothing on
    the hot path. Capped to the last 200 lines so it never grows unbounded.

    This is the net that catches the freeze without having to reproduce it: if
    the bar ever stalls again, the line says which event, how long, and under
    what memory/swap pressure."""
    try:
        mem_av = "?"
        swap_total = swap_free = 0
        with open("/proc/meminfo") as f:
            for line in f:
                parts = line.split()
                if line.startswith("MemAvailable:"):
                    mem_av = parts[1]
                elif line.startswith("SwapTotal:"):
                    swap_total = int(parts[1])
                elif line.startswith("SwapFree:"):
                    swap_free = int(parts[1])
        ts = time.strftime("%Y-%m-%dT%H:%M:%S")
        entry = "{}  change={:<8}  cycle={:.0f}ms  MemAvailable={}kB  SwapUsed={}kB\n".format(
            ts, change or "-", ms, mem_av, swap_total - swap_free)
        os.makedirs(os.path.dirname(_LAG_LOG), exist_ok=True)
        lines = []
        try:
            with open(_LAG_LOG) as f:
                lines = f.readlines()
        except OSError:
            pass
        lines.append(entry)
        with open(_LAG_LOG, "w") as f:
            f.writelines(lines[-200:])
    except OSError:
        pass


def main():
    last_focused = {}

    # Initial full build over the tree.
    tree   = swaymsg(["-t", "get_tree"])
    ws_raw = swaymsg(["-t", "get_workspaces"])
    update_last_focused(last_focused, tree)
    emit(build_output(last_focused, tree, ws_raw))

    # Subscribe over a dedicated persistent socket — no `swaymsg`/`jq` subprocess
    # per event. The event path is now socket I/O + in-RAM compute only.
    sub_payload = b'["workspace", "window"]'

    def subscribe():
        s = _ipc_connect()
        _ipc_send(s, _MSG_SUBSCRIBE, sub_payload)
        _ipc_read(s)  # consume the {"success": true} reply
        return s

    sub = subscribe()

    while True:
        try:
            msg_type, raw = _ipc_read(sub)
        except OSError:
            # sway restarted or the socket dropped — reconnect and resume.
            try:
                sub.close()
            except OSError:
                pass
            sub = subscribe()
            continue

        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            continue

        t0 = time.perf_counter()
        change = event.get("change", "")

        # A title change never alters the app-id icon — skip the render entirely.
        if msg_type == _EVT_WINDOW and change == "title":
            continue

        if change == "focus":
            # waybar's trick: a focus change moves no windows, so the per-workspace
            # app icons are unchanged. Do NOT re-read/parse the heavy tree — refresh
            # the focused/urgent flags from the small get_workspaces object and
            # rebuild over the CACHED tree. This is what keeps super+tab instant.
            ws_raw = swaymsg(["-t", "get_workspaces"])
            if msg_type == _EVT_WINDOW:
                app = get_app_id(event.get("container", {}))
                if app:
                    for ws in ws_raw:
                        if ws.get("focused"):
                            last_focused[ws["num"]] = app
                            break
            emit(build_output(last_focused, tree, ws_raw))
        else:
            # Structural change (new/close/move/init/empty/rename/urgent): the
            # window set or workspace layout changed — rebuild from a fresh tree.
            tree   = swaymsg(["-t", "get_tree"])
            ws_raw = swaymsg(["-t", "get_workspaces"])
            update_last_focused(last_focused, tree)
            emit(build_output(last_focused, tree, ws_raw))

        dt = (time.perf_counter() - t0) * 1000.0
        if dt > _LAG_MS:
            _log_lag(change, dt)


if __name__ == "__main__":
    main()
