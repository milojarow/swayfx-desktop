#!/usr/bin/env python3
# feature: window-title
# role:    rename  (Method 3 — right-click handler for custom window names)
"""
window-title-rename.py — assign or clear a custom name for the focused window.

Bound to waybar custom/window-title on-click-right. Opens a rofi prompt
pre-filled with the current label (override or live title); a non-empty entry is
stored at NAMES_DIR/<window-id>.name, an empty entry clears it. Then it sends
SIGUSR1 to window-title-stream.py so the module re-renders immediately.
"""
import json
import os
import subprocess
import sys

NAMES_DIR = "/tmp/waybar-window-names-{}".format(os.environ.get("USER", ""))
STREAM = "window-title-stream.py"


def find_focused(node):
    if node.get("focused") and node.get("pid"):
        return node
    for c in node.get("nodes", []) + node.get("floating_nodes", []):
        r = find_focused(c)
        if r:
            return r
    return None


def main():
    try:
        tree = json.loads(subprocess.check_output(["swaymsg", "-t", "get_tree"]))
    except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
        sys.exit(1)

    node = find_focused(tree)
    if not node:
        sys.exit(0)

    wid = node.get("id")
    os.makedirs(NAMES_DIR, exist_ok=True)
    path = os.path.join(NAMES_DIR, "{}.name".format(wid))

    if os.path.exists(path):
        prefill = open(path).read().strip()
    else:
        prefill = node.get("name", "") or ""

    try:
        res = subprocess.run(
            ["rofi", "-dmenu", "-p", "Window name", "-lines", "0",
             "-theme-str", "window {width: 360px;}"],
            input=prefill, capture_output=True, text=True,
        )
    except FileNotFoundError:
        sys.exit(1)

    if res.returncode != 0:
        sys.exit(0)  # cancelled (Escape)

    label = res.stdout.strip()
    if label:
        with open(path, "w") as f:
            f.write(label)
    else:
        try:
            os.remove(path)  # empty submission clears the override
        except OSError:
            pass

    # Tell the stream daemon to re-emit the focused window with the new label.
    subprocess.run(["pkill", "-USR1", "-f", STREAM], check=False)


if __name__ == "__main__":
    main()
