#!/usr/bin/env bash
# feature: wifi
# role:    action
# wifi-public-ip.sh — fetch current public IP and push to eww.
# Invoked from: wifi-toggle-popup.sh (on open), wifi-rescan.sh, wifi-subscribe.py (on connection change).

EWW=$HOME/.cargo/bin/eww

ip=$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)
[[ -z "$ip" ]] && ip="—"
"$EWW" update wifi-public-ip="$ip"
