#!/usr/bin/env bash
# feature: bt
# role:    action
trap 'eww update bt-connecting=""' EXIT
eww update bt-connecting="$1"
output=$(bluetoothctl disconnect "$1" 2>&1)
if ! echo "$output" | grep -qi "successful"; then
    notify-send -u critical "Bluetooth" "Disconnect failed"
fi
