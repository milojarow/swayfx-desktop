#!/usr/bin/env bash
# feature: bt
# role:    action
trap 'eww update bt-forgetting=""' EXIT
eww update bt-forgetting="$1"
bluetoothctl remove "$1" 2>/dev/null
sleep 0.5
if bluetoothctl devices Trusted 2>/dev/null | grep -qi "$1"; then
    notify-send -u critical "Bluetooth" "Failed to remove device"
fi
