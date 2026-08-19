#!/usr/bin/env bash
# feature: wifi
# role:    action
# wifi-rescan.sh — force a hardware wifi rescan and immediately update eww.
# Spawned via swaymsg exec from the rescan button.

EWW=$HOME/.cargo/bin/eww

nmcli device wifi rescan 2>/dev/null || true
result=$(python3 $HOME/.config/eww/scripts/wifi-scan.py)
$EWW update wifi-networks="$result"
~/.config/eww/scripts/wifi-public-ip.sh &
