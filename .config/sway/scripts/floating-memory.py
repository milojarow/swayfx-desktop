#!/usr/bin/env python3
# ── Floating Memory ───────────────────────────────────────────────────────────
# Role:     Sway IPC event daemon that remembers, per application, whether the
#           user last left its window floating or tiling AND — for floating
#           windows — its exact position+size, then re-applies all of it when the
#           app reopens. Targets tray apps (Altus, Telegram) that destroy their
#           toplevel when "closed" to the system tray and create a brand-new
#           window on reopen — at which point sway would otherwise drop them into
#           the default tiling layout at an arbitrary spot, losing both the
#           floating flag and the placement the user had set.
# Files:    floating-memory.py
# Daemon:   ~/.config/systemd/user/floating-memory.service
# Storage:  ~/.local/state/sway-floating-memory.json  (persistent per-app state)
#           /tmp/floating-memory-$USER.pid            (single-instance guard)
# State:    { "<app>": { "floating": bool, "rect": {x,y,width,height}? } }
# How:      Geometry is captured on `window::close` (sway emits no move/resize
#           event for floating drags, but `close` carries the final rect). The
#           floating flag is also tracked live on `window::floating`. On
#           `window::new` the remembered state is re-applied in one command.
# Note:     This daemon is the SOLE authority for floating/tiling AND placement
#           of tracked apps. (1) Do NOT add a `for_window [...] floating enable`
#           rule for them. (2) These apps are excluded from floating-placer.py's
#           IGNORE_PATTERNS so it won't fight this daemon over their position —
#           keep that list in sync with TRACK_PATTERNS below.
# ──────────────────────────────────────────────────────────────────────────────

import json
import os
import re
import sys
import tempfile

import i3ipc

# Apps whose floating/tiling choice + placement are remembered. Matched against
# app_id (Wayland) or window class (XWayland). Add a pattern to track more apps
# — and mirror it in floating-placer.py's IGNORE_PATTERNS.
TRACK_PATTERNS = (
    re.compile(r"^Altus$"),
    re.compile(r"telegram", re.IGNORECASE),  # app_id org.telegram.desktop / class TelegramDesktop
)

STATE_DIR = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
STATE_FILE = os.path.join(STATE_DIR, "sway-floating-memory.json")
PIDFILE = f"/tmp/floating-memory-{os.environ.get('USER', 'user')}.pid"


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def identify(con):
    """Stable key for an app: app_id (Wayland) -> window class (XWayland) -> None."""
    return con.app_id or con.window_class or None


def is_tracked(key):
    return bool(key) and any(p.search(key) for p in TRACK_PATTERNS)


def is_floating(con):
    return con.floating in ("user_on", "auto_on")


def rect_of(con):
    r = con.rect
    return {"x": r.x, "y": r.y, "width": r.width, "height": r.height}


def load():
    try:
        with open(STATE_FILE) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def save(data):
    os.makedirs(STATE_DIR, exist_ok=True)
    # Atomic write: tmp file in the same dir, then os.replace over the target.
    fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix=".sway-floating-memory.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2, sort_keys=True)
        os.replace(tmp, STATE_FILE)
    except OSError as exc:
        log(f"save failed: {exc}")
        try:
            os.unlink(tmp)
        except OSError:
            pass


def entry_for(data, key):
    """Return the per-app dict, tolerating legacy/garbled values."""
    entry = data.get(key)
    return entry if isinstance(entry, dict) else {}


def on_floating(_conn, event):
    """User (or this daemon) toggled floating state -> update the flag (no rect:
    the final position isn't known until the window is closed)."""
    con = event.container
    key = identify(con)
    if not is_tracked(key):
        return
    data = load()
    entry = entry_for(data, key)
    entry["floating"] = is_floating(con)
    data[key] = entry
    save(data)
    log(f"remember {key!r} floating={entry['floating']}")


def on_close(_conn, event):
    """Window closed (e.g. to the tray) -> capture the final state + geometry.
    The close event carries the last rect, which is where the user left it."""
    con = event.container
    key = identify(con)
    if not is_tracked(key):
        return
    data = load()
    entry = entry_for(data, key)
    floating = is_floating(con)
    entry["floating"] = floating
    if floating:
        entry["rect"] = rect_of(con)
    data[key] = entry
    save(data)
    log(f"remember {key!r} on close floating={floating} rect={entry.get('rect')}")


def on_new(_conn, event):
    """Window born (incl. reopen from tray) -> re-apply remembered state+placement."""
    con = event.container
    key = identify(con)
    if not is_tracked(key):
        return
    entry = entry_for(load(), key)
    if not entry.get("floating"):
        return  # tiling is the default -> nothing to do
    cmd = "floating enable"
    r = entry.get("rect")
    if r:
        # resize before move: setting size can change the anchor, so place last.
        cmd += f", resize set width {r['width']} px height {r['height']} px"
        cmd += f", move absolute position {r['x']} {r['y']}"
    con.command(cmd)  # comma-joined keeps the target container across subcommands
    log(f"apply {key!r} -> {cmd}")


def single_instance():
    if os.path.exists(PIDFILE):
        try:
            old = int(open(PIDFILE).read().strip())
            os.kill(old, 15)  # SIGTERM the previous instance
        except (ValueError, ProcessLookupError, PermissionError, OSError):
            pass
    try:
        with open(PIDFILE, "w") as f:
            f.write(str(os.getpid()))
    except OSError as exc:
        log(f"could not write pidfile: {exc}")


def main():
    single_instance()
    conn = i3ipc.Connection()
    conn.on("window::floating", on_floating)
    conn.on("window::close", on_close)
    conn.on("window::new", on_new)
    log("floating-memory subscribed to sway IPC")
    conn.main()


if __name__ == "__main__":
    main()
