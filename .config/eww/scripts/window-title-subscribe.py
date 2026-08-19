#!/usr/bin/env python3
# feature: window-title
# role:    subscribe
"""
window-title-subscribe.py — eww deflisten source for the bar window-title widget.

Subscribes to sway window/workspace events and emits one JSON line per update:
  {"text": "~/projects: nvim", "css_class": "terminal"}
  {"text": "GitHub - Firefox", "css_class": "browser"}
  {"text": "", "css_class": "empty"}

Mirrors the title-processing logic of window-title.sh used by waybar.
"""

import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
SHELLS = frozenset(("fish", "bash", "zsh", "sh"))
NAMES_DIR = f"/tmp/eww-window-names-{os.getenv('USER', 'user')}"


# ── CSS class detection ───────────────────────────────────────────────────────

_TERMINAL_KEYS = ("footclient", "foot", "terminal", "alacritty", "kitty", "ghostty")
_BROWSER_KEYS  = ("firefox", "chromium", "chrome", "brave", "librewolf")
_EDITOR_KEYS   = ("code", "vscodium", "vim", "nvim", "helix")

def get_css_class(app_id):
    app = (app_id or "").lower()
    if any(k in app for k in _TERMINAL_KEYS):
        return "terminal"
    if any(k in app for k in _BROWSER_KEYS):
        return "browser"
    if any(k in app for k in _EDITOR_KEYS):
        return "editor"
    return ""


# ── Title parsing helpers (mirrors window-title.sh shell builtins) ────────────

def parse_title_pid(title):
    """Strip trailing [PID] suffix. Returns (clean_title, shell_pid_str)."""
    m = re.match(r"^(.*)\s+\[(\d+)\]$", title)
    if m:
        return m.group(1), m.group(2)
    return title, ""


def extract_path(title):
    """Extract leading directory path from a terminal title."""
    if re.match(r"^[~/]", title):
        if ":" in title:
            return title.split(":")[0]
        if " - " in title:
            part = title.rsplit(" - ", 1)[0]
            if re.match(r"^[~/]", part):
                return part
        if "/" in title:
            return title
    if title == "~" or title.startswith("~ ") or title.startswith("~:"):
        return "~"
    return ""


def extract_context(title):
    """Extract command/context portion from a terminal title."""
    if title.endswith(" Claude Code"):
        return "Claude Code"
    if title.startswith("\u2733 "):
        return title[2:]
    if ": " in title and " - " in title:
        after = title.split(": ", 1)[1]
        return after.rsplit(" - ", 1)[0]
    if ": " in title:
        return title.split(": ", 1)[1]
    return ""


def truncate_display(text, limit=60):
    if len(text) <= limit:
        return text
    if ":" in text:
        pp, rest = text.split(":", 1)
        cp = rest.lstrip()
        if len(pp) < 40:
            return f"{pp}: {cp[:17]}..."
        return f"...{pp[-50:]}:..."
    return text[:57] + "..."


# ── Process tree CWD fallback (mirrors get_footclient_cwd / get_process_cwd) ──

def _pid_comm(pid):
    try:
        with open(f"/proc/{pid}/comm") as f:
            return f.read().strip()
    except OSError:
        return ""


def _pid_ppid(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except OSError:
        pass
    return 0


def _read_cwd(pid):
    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
        if cwd.startswith(HOME):
            cwd = "~" + cwd[len(HOME):]
        return cwd if cwd not in ("/", "") else ""
    except OSError:
        return ""


def get_terminal_cwd(wpid_str, shell_pid_str=""):
    """
    Find the CWD of the terminal's shell child.
    1. If shell_pid_str (from title [PID] suffix) is given, read it directly.
    2. Otherwise walk direct children of wpid looking for a shell process.
    """
    # Fast path: shell PID is known from title suffix
    if shell_pid_str:
        cwd = _read_cwd(shell_pid_str)
        if cwd:
            return cwd

    if not wpid_str:
        return ""
    try:
        wpid_int = int(wpid_str)
    except (ValueError, TypeError):
        return ""

    # Walk /proc to find direct children of wpid that are shells
    idle_shells = []   # shells with no children of their own
    busy_shells = []

    try:
        for entry in os.scandir("/proc"):
            if not entry.name.isdigit():
                continue
            pid = int(entry.name)
            if _pid_ppid(pid) != wpid_int:
                continue
            comm = _pid_comm(pid)
            if comm not in SHELLS:
                continue
            cwd = _read_cwd(pid)
            if not cwd:
                continue
            # Does this shell have children of its own?
            has_children = any(
                _pid_ppid(int(e.name)) == pid
                for e in os.scandir("/proc")
                if e.name.isdigit()
            )
            if has_children:
                busy_shells.append(cwd)
            else:
                idle_shells.append(cwd)
    except OSError:
        pass

    # Prefer idle shell (shell waiting at prompt = current directory)
    if idle_shells:
        return idle_shells[0]
    if busy_shells:
        return busy_shells[0]

    return _read_cwd(wpid_int)


# ── Main window-title logic ───────────────────────────────────────────────────

def process_window(title, app_id, wpid="", win_id=""):
    if not title or title == "null":
        return {"text": "", "css_class": "empty"}

    # Custom rename takes priority over derived title
    if win_id:
        try:
            with open(os.path.join(NAMES_DIR, f"{win_id}.name")) as f:
                custom = f.read().strip()
            if custom:
                # For terminal windows, preserve the location prefix
                app_low = (app_id or "").lower()
                if any(k in app_low for k in _TERMINAL_KEYS):
                    clean, shell_pid = parse_title_pid(title)
                    location = extract_path(clean)
                    if not location:
                        location = get_terminal_cwd(wpid, shell_pid)
                    if location:
                        return {"text": truncate_display(f"{location}: {custom}"), "css_class": get_css_class(app_id)}
                return {"text": custom, "css_class": get_css_class(app_id)}
        except OSError:
            pass

    css     = get_css_class(app_id)
    app_low = (app_id or "").lower()

    if any(k in app_low for k in _TERMINAL_KEYS):
        clean, shell_pid = parse_title_pid(title)
        location = extract_path(clean)
        context  = extract_context(clean)

        # Fallback: read CWD from process tree when title has no path
        if not location:
            location = get_terminal_cwd(wpid, shell_pid)

        if location and context:
            display = f"{location}: {context}"
        elif location:
            display = location
        elif context:
            display = context
        else:
            display = clean
    else:
        display = title

    return {"text": truncate_display(display), "css_class": css}


# ── sway helpers ──────────────────────────────────────────────────────────────

def swaymsg(args):
    r = subprocess.run(["swaymsg"] + args, capture_output=True, text=True)
    return json.loads(r.stdout)


def find_focused(node):
    if node.get("focused") and node.get("type") not in ("root", "output", "workspace"):
        return node
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        result = find_focused(child)
        if result:
            return result
    return None


def emit(data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


# ── Bootstrap ─────────────────────────────────────────────────────────────────

def bootstrap():
    tree = swaymsg(["-t", "get_tree"])
    node = find_focused(tree)
    if node:
        title  = node.get("name") or ""
        app_id = node.get("app_id") or (node.get("window_properties") or {}).get("class", "")
        wpid   = str(node.get("pid") or "")
        win_id = str(node.get("id") or "")
        _last["title"]  = title
        _last["app_id"] = app_id
        _last["wpid"]   = wpid
        _last["win_id"] = win_id
        emit(process_window(title, app_id, wpid, win_id))
    else:
        emit({"text": "", "css_class": "empty"})


# ── Main event loop ───────────────────────────────────────────────────────────

# Tab-separated: win_id \t title \t app_id \t pid
JQ_FILTER = r"""
if .container then
  if (.change == "focus" or (.change == "title" and .container.focused)) then
    "WINDOW\t" + (.container.id|tostring) + "\t" + (.container.name // "") + "\t" + (.container.app_id // (.container.window_properties.class // "")) + "\t" + (.container.pid | tostring)
  elif (.change == "close" and .container.focused) then "EMPTY"
  else "SKIP" end
elif .current then
  if .change == "focus" then
    if (.current.focus | length) > 0 then "SKIP" else "EMPTY" end
  else "SKIP" end
else "SKIP" end
"""


def main():
    import signal

    # Stores last focused window so SIGUSR1 can re-emit with updated custom name
    global _last
    _last = {"title": "", "app_id": "", "wpid": "", "win_id": ""}

    def handle_usr1(signum, frame):
        # Re-query sway directly so we always get the current focused window,
        # regardless of any stale _last state from rofi focus events.
        tree = swaymsg(["-t", "get_tree"])
        node = find_focused(tree)
        if node:
            title  = node.get("name") or ""
            app_id = node.get("app_id") or (node.get("window_properties") or {}).get("class", "")
            wpid   = str(node.get("pid") or "")
            win_id = str(node.get("id") or "")
            emit(process_window(title, app_id, wpid, win_id))
        else:
            emit({"text": "", "css_class": "empty"})

    signal.signal(signal.SIGUSR1, handle_usr1)

    bootstrap()

    swaymsg_proc = subprocess.Popen(
        ["swaymsg", "-t", "subscribe", "-m", '["window","workspace"]'],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    jq_proc = subprocess.Popen(
        ["jq", "--unbuffered", "-r", JQ_FILTER],
        stdin=swaymsg_proc.stdout,
        stdout=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    swaymsg_proc.stdout.close()

    for line in jq_proc.stdout:
        line = line.strip()
        if not line or line == "SKIP":
            continue
        if line == "EMPTY":
            emit({"text": "", "css_class": "empty"})
            continue
        if line.startswith("WINDOW\t"):
            parts  = line[7:].split("\t")
            win_id = parts[0] if len(parts) > 0 else ""
            title  = parts[1] if len(parts) > 1 else ""
            app_id = parts[2] if len(parts) > 2 else ""
            wpid   = parts[3] if len(parts) > 3 else ""
            _last["title"]  = title
            _last["app_id"] = app_id
            _last["wpid"]   = wpid
            _last["win_id"] = win_id
            emit(process_window(title, app_id, wpid, win_id))


if __name__ == "__main__":
    main()
