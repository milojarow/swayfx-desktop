#!/usr/bin/env bash
# feature: wifi
# role:    action
# wifi-forget.sh — delete a saved wifi connection profile.
# Args: <ssid>

SSID="$1"
[ -z "$SSID" ] && exit 1
nmcli connection delete id "$SSID"
