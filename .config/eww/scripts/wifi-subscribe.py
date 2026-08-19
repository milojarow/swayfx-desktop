#!/usr/bin/env python3
# feature: wifi
# role:    subscribe
"""
wifi-subscribe.py — eww deflisten source for the wifi bar module.

Emits a JSON object on startup and on every NetworkManager state change:
  {"icon": "...", "ssid": "MYWIFI", "signal": 57, "ip": "192.168.1.1",
   "freq": "5500 MHz", "security": "WPA2", "class": "connected", "connected": true}

Icons match waybar's network module (same codepoints).
"""

import json
import os
import subprocess

PUBLIC_IP_SCRIPT = os.path.expanduser("~/.config/eww/scripts/wifi-public-ip.sh")


def trigger_public_ip():
    """Fire-and-forget update of wifi-public-ip in the background."""
    subprocess.Popen(
        [PUBLIC_IP_SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

# Signal strength icons — same as waybar network format-icons
ICONS = [
    "\U000f092f",  # 0 bars  (< 20%)
    "\U000f091f",  # 1 bar   (20–39%)
    "\U000f0922",  # 2 bars  (40–59%)
    "\U000f0925",  # 3 bars  (60–79%)
    "\U000f0928",  # 4 bars  (80–100%)
]
ICON_DISCONNECTED = "\U000f05aa"
ICON_DISABLED     = "\U000f001d"


def signal_icon(pct):
    if pct >= 80: return ICONS[4]
    if pct >= 60: return ICONS[3]
    if pct >= 40: return ICONS[2]
    if pct >= 20: return ICONS[1]
    return ICONS[0]


def get_state():
    try:
        # Find active wifi device
        r = subprocess.run(
            ["nmcli", "-t", "-f", "device,type,state", "dev"],
            capture_output=True, text=True
        )
        device = None
        for line in r.stdout.splitlines():
            parts = line.split(":")
            if len(parts) >= 3 and parts[1] == "wifi" and parts[2] == "connected":
                device = parts[0]
                break

        if not device:
            return {
                "icon": ICON_DISCONNECTED, "ssid": "", "signal": 0,
                "ip": "", "freq": "", "security": "",
                "class": "disconnected", "connected": False,
            }

        # Active wifi details
        r2 = subprocess.run(
            ["nmcli", "-t", "-f", "active,ssid,signal,freq,security", "dev", "wifi"],
            capture_output=True, text=True
        )
        ssid = freq = security = ""
        signal_pct = 0
        for line in r2.stdout.splitlines():
            parts = line.split(":")
            if parts[0] == "yes" and len(parts) >= 5:
                ssid       = parts[1]
                signal_pct = int(parts[2]) if parts[2].isdigit() else 0
                freq       = parts[3]
                security   = parts[4]
                break

        # IP address
        r3 = subprocess.run(
            ["nmcli", "-t", "-f", "ip4.address", "dev", "show", device],
            capture_output=True, text=True
        )
        ip = ""
        for line in r3.stdout.splitlines():
            if line.startswith("IP4.ADDRESS"):
                ip = line.split(":", 1)[1].split("/")[0]
                break

        return {
            "icon": signal_icon(signal_pct),
            "ssid": ssid,
            "signal": signal_pct,
            "ip": ip,
            "freq": freq,
            "security": security,
            "class": "connected",
            "connected": True,
        }

    except Exception:
        return {
            "icon": ICON_DISCONNECTED, "ssid": "", "signal": 0,
            "ip": "", "freq": "", "security": "",
            "class": "disconnected", "connected": False,
        }


def emit(data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def main():
    state = get_state()
    emit(state)
    prev_key = (state["ssid"], state["connected"])
    trigger_public_ip()

    proc = subprocess.Popen(
        ["nmcli", "monitor"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )
    for line in proc.stdout:
        if line.strip():
            state = get_state()
            emit(state)
            key = (state["ssid"], state["connected"])
            if key != prev_key:
                trigger_public_ip()
                prev_key = key


if __name__ == "__main__":
    main()
