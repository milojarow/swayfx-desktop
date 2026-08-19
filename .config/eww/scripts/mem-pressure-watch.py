#!/usr/bin/env python3
# feature: mem-pressure
# role:    subscribe
"""
mem-pressure-watch.py — PSI-driven memory pressure watcher for eww deflisten.

Uses Linux PSI (Pressure Stall Information) via poll() on /proc/pressure/memory.
Blocks indefinitely when system is healthy — zero CPU between events.
Emits JSON only when state changes.

Trigger: wakes when "some" stall rate exceeds ~5% in a 1-second window.
Recovery: re-checks every 30s to detect when pressure drops back to normal.
"""

import os
import json
import select

PSI_FILE   = "/proc/pressure/memory"
TRIGGER    = b"some 100000 2000000\n"  # wake when stall > 100ms in last 2s (~5% rate)
TIMEOUT_MS = 30_000                 # re-read every 30s to catch pressure recovery


def read_avg60(fd):
    os.lseek(fd, 0, os.SEEK_SET)
    data = os.read(fd, 256).decode()
    for line in data.splitlines():
        if line.startswith("some"):
            for field in line.split():
                if field.startswith("avg60="):
                    return float(field[6:])
    return 0.0


def make_payload(avg60):
    val = int(avg60)
    if val >= 20:
        cls, active = "critical", 1
    elif val >= 5:
        cls, active = "warning", 1
    else:
        cls, active = "normal", 0
    # waybar format: "text" carries the warning glyph (U+F071) only under pressure,
    # empty otherwise so the module collapses/hides. "class" drives CSS coloring.
    text = "" if active else ""
    tooltip = f"Memory pressure: {val}% (PSI avg60)"
    # Dual format: eww keys (avg60/class/active) + waybar keys (text/class/tooltip).
    return json.dumps({"avg60": val, "class": cls, "active": active, "text": text, "tooltip": tooltip})


def main():
    fd = os.open(PSI_FILE, os.O_RDWR)
    os.write(fd, TRIGGER)

    poller = select.poll()
    poller.register(fd, select.POLLPRI | select.POLLERR)

    # Emit initial state
    last = make_payload(read_avg60(fd))
    print(last, flush=True)

    while True:
        # Blocks here — wakes on PSI threshold crossed or every 30s
        poller.poll(TIMEOUT_MS)

        payload = make_payload(read_avg60(fd))
        if payload != last:
            print(payload, flush=True)
            last = payload


if __name__ == "__main__":
    main()
