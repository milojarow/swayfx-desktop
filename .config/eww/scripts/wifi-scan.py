#!/usr/bin/env python3
# feature: wifi
# role:    helper
"""
wifi-scan.py — eww defpoll source for the wifi manager widget.

Outputs a single JSON object with all networks (available + saved-only):
  {"networks": [
    {"ssid": "MyNet", "signal": 72, "security": "WPA2",
     "in_use": true, "known": true, "available": true, "icon": "󰤥",
     "band": "5G", "bssid": "AA:BB:CC:DD:EE:FF", "last_used": 1778248937},
    ...
  ]}

Same SSID on different bands (2.4G / 5G) appears as separate entries.
Sort order: in_use first → available by signal desc → saved-only by last_used desc.
"""

import json
import subprocess

# Signal strength icons (same as wifi-subscribe.py)
ICONS = [
    "\U000f092f",  # 0 bars  (< 20%)
    "\U000f091f",  # 1 bar   (20–39%)
    "\U000f0922",  # 2 bars  (40–59%)
    "\U000f0925",  # 3 bars  (60–79%)
    "\U000f0928",  # 4 bars  (80–100%)
]
ICON_SAVED = "\U000f092b"   # saved/offline network icon


def signal_icon(pct):
    if pct >= 80: return ICONS[4]
    if pct >= 60: return ICONS[3]
    if pct >= 40: return ICONS[2]
    if pct >= 20: return ICONS[1]
    return ICONS[0]


def freq_to_band(freq_str):
    """Convert frequency string like '5500 MHz' to band label."""
    try:
        mhz = int(freq_str.split()[0])
    except (ValueError, IndexError):
        return ""
    if mhz < 3000:
        return "2.4G"
    if mhz < 6000:
        return "5G"
    return "6G"


def get_known_connections():
    """Return dict {ssid: last_used_unix_timestamp} for saved wifi connections."""
    r = subprocess.run(
        ["nmcli", "-t", "-f", "NAME,TYPE,TIMESTAMP", "connection", "show"],
        capture_output=True, text=True
    )
    known = {}
    for line in r.stdout.splitlines():
        parts = line.replace("\\:", "\x00").split(":")
        parts = [p.replace("\x00", ":") for p in parts]
        if len(parts) >= 3 and parts[1] == "802-11-wireless":
            try:
                known[parts[0]] = int(parts[2])
            except ValueError:
                known[parts[0]] = 0
    return known


def get_available_networks(known_connections):
    """Parse nmcli wifi list output into a deduplicated dict keyed by (SSID, band)."""
    r = subprocess.run(
        ["nmcli", "-t", "-f", "BSSID,SSID,SIGNAL,SECURITY,IN-USE,FREQ",
         "device", "wifi", "list"],
        capture_output=True, text=True
    )
    networks = {}
    for line in r.stdout.splitlines():
        # nmcli -t escapes colons in values as \: — split on unescaped colons
        parts = line.replace("\\:", "\x00").split(":")
        parts = [p.replace("\x00", ":") for p in parts]
        if len(parts) < 6:
            continue
        bssid, ssid, signal_str, security, in_use_str, freq = (
            parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]
        )
        if not ssid:
            continue
        signal = int(signal_str) if signal_str.isdigit() else 0
        security = security if security not in ("", "--") else ""
        in_use = in_use_str.strip() == "*"
        band = freq_to_band(freq)
        # Dedup by (SSID, band) — same SSID on different bands shown separately
        key = (ssid, band)
        if key not in networks or signal > networks[key]["signal"]:
            networks[key] = {
                "ssid":      ssid,
                "signal":    signal,
                "security":  security,
                "in_use":    in_use,
                "known":     ssid in known_connections,
                "available": True,
                "icon":      signal_icon(signal),
                "band":      band,
                "bssid":     bssid,
                "last_used": known_connections.get(ssid, 0),
            }
    return networks


def main():
    try:
        known_connections = get_known_connections()
        networks = get_available_networks(known_connections)

        # Add saved-only entries (known but not visible in scan)
        visible_ssids = {k[0] for k in networks}
        for ssid, ts in known_connections.items():
            if ssid not in visible_ssids:
                networks[(ssid, "")] = {
                    "ssid":      ssid,
                    "signal":    0,
                    "security":  "",
                    "in_use":    False,
                    "known":     True,
                    "available": False,
                    "icon":      ICON_SAVED,
                    "band":      "",
                    "bssid":     "",
                    "last_used": ts,
                }

        result = sorted(
            networks.values(),
            key=lambda n: (not n["in_use"], not n["available"], -n["signal"], -n["last_used"])
        )
        print(json.dumps({"networks": result}, ensure_ascii=False), flush=True)

    except Exception as e:
        print(json.dumps({"networks": []}), flush=True)


if __name__ == "__main__":
    main()
