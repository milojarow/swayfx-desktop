#!/usr/bin/env bash
# feature: wifi
# role:    action
# wifi-edit.sh — open the password prompt in "edit" mode to change a saved
# network's PSK in place, without forgetting it first.
# Args: <ssid> <security> <bssid>

EWW=$HOME/.cargo/bin/eww
SSID="$1"
SECURITY="$2"
BSSID="$3"

[ -z "$SSID" ] && exit 1

$EWW update wifi-pw-ssid="$SSID" wifi-pw-bssid="$BSSID" wifi-pw-security="$SECURITY" wifi-pw-mode="edit"
$EWW open wifi-password-prompt 2>/dev/null
