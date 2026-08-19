#!/usr/bin/env python3
# feature: volume
# role:    subscribe
"""
volume-subscribe.py — eww deflisten for volume/mic state.

Emits a JSON object on startup and on every sink or source change:
  {"text": "...", "class": "", "volume": 75, "muted": false, "mic_muted": false}
  {"text": "...", "class": "muted", "volume": 75, "muted": true, "mic_muted": true}
"""

import json
import re
import subprocess


ICON_MUTED       = "\U000f0581"   # volume muted
ICON_LOW         = "\U000f057f"   # volume low  (< 34%)
ICON_MID         = "\U000f0580"   # volume mid  (< 67%)
ICON_HIGH        = "\U000f057e"   # volume high (>= 67%)
ICON_HEADPHONES  = "\U000f02cb"   # wired headphones connected
ICON_MIC_OFF     = "\U000f036d"   # mic muted


def is_headphones_active():
    try:
        # Bluetooth audio sink takes over output entirely
        default_sink = subprocess.run(
            ["pactl", "get-default-sink"],
            capture_output=True, text=True,
        ).stdout.strip()
        if default_sink.startswith("bluez_output"):
            return True

        # Wired headphones via analog port
        sinks = subprocess.run(
            ["pactl", "list", "sinks"],
            capture_output=True, text=True,
        ).stdout
        return bool(re.search(r"Active Port:\s*analog-output-headphones", sinks))
    except Exception:
        return False


def query():
    try:
        vol_raw = subprocess.run(
            ["pactl", "get-sink-volume", "@DEFAULT_SINK@"],
            capture_output=True, text=True,
        ).stdout
        m = re.search(r"(\d+)%", vol_raw)
        volume = int(m.group(1)) if m else 0
    except Exception:
        volume = 0

    try:
        sink_muted = "yes" in subprocess.run(
            ["pactl", "get-sink-mute", "@DEFAULT_SINK@"],
            capture_output=True, text=True,
        ).stdout
    except Exception:
        sink_muted = False

    try:
        mic_muted = "yes" in subprocess.run(
            ["pactl", "get-source-mute", "@DEFAULT_SOURCE@"],
            capture_output=True, text=True,
        ).stdout
    except Exception:
        mic_muted = False

    headphones = is_headphones_active()

    if sink_muted:
        icon = ICON_MUTED
    elif headphones:
        icon = ICON_HEADPHONES
    elif volume < 34:
        icon = ICON_LOW
    elif volume < 67:
        icon = ICON_MID
    else:
        icon = ICON_HIGH

    text = icon if sink_muted else f"{icon} {volume}%"
    if mic_muted:
        text += f" {ICON_MIC_OFF}"

    return {
        "icon": icon,
        "text": text,
        "class": "muted" if sink_muted else "",
        "volume": volume,
        "muted": sink_muted,
        "mic_muted": mic_muted,
        "headphones": headphones,
    }


def emit(data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def main():
    emit(query())

    proc = subprocess.Popen(
        ["pactl", "subscribe"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )

    for line in proc.stdout:
        # Only react to sink/source change events, not per-app sink-input events
        if re.search(r"Event '(change|new|remove)' on (sink|source|server)", line):
            emit(query())


if __name__ == "__main__":
    main()
