#!/usr/bin/env python3
# feature: sway-mode
# role:    subscribe
"""
sway-mode-subscribe.py — eww deflisten for the sway mode indicator.

Emits a JSON object on startup and on every mode change:
  {"name": "<pango markup string>", "active": true}   — non-default mode
  {"name": "", "active": false}                        — default mode
"""

import json
import subprocess


def emit(mode_name):
    active = mode_name.lower() != "default"
    print(json.dumps({
        "name": mode_name if active else "",
        "active": active,
    }, ensure_ascii=False), flush=True)


def main():
    # Bootstrap: get the current binding mode
    r = subprocess.run(
        ["swaymsg", "-t", "get_binding_state"],
        capture_output=True, text=True
    )
    emit(json.loads(r.stdout).get("name", "default"))

    # Subscribe to mode change events
    swaymsg_proc = subprocess.Popen(
        ["swaymsg", "-t", "subscribe", "-m", '["mode"]'],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    jq_proc = subprocess.Popen(
        ["jq", "--unbuffered", "-r", ".change"],
        stdin=swaymsg_proc.stdout,
        stdout=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    swaymsg_proc.stdout.close()

    for line in jq_proc.stdout:
        line = line.strip()
        if line and line != "null":
            emit(line)


if __name__ == "__main__":
    main()
