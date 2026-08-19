#!/usr/bin/env bash
# feature: bt
# role:    action
# Pair and trust a device. Works for "Just Works" devices (headphones, speakers).
# Devices requiring PIN confirmation will fail silently — use bluetuith for those.
trap 'eww update bt-pairing=""' EXIT
eww update bt-pairing="$1"

# Re-discover device if bluetoothctl dropped it after scan ended.
# One-shot 'scan on' stops discovery when the process exits, so use -t to keep it alive.
if ! bluetoothctl info "$1" 2>/dev/null | grep -q "Name:"; then
    bluetoothctl -t 8 scan on &>/dev/null &
    scan_pid=$!
    timeout=14
    elapsed=0
    until bluetoothctl info "$1" 2>/dev/null | grep -q "Name:"; do
        sleep 0.5
        (( elapsed++ ))
        if (( elapsed >= timeout )); then
            kill "$scan_pid" 2>/dev/null; wait "$scan_pid" 2>/dev/null
            notify-send -u critical "Bluetooth" "Device not found — try scanning again"
            exit 1
        fi
    done
    kill "$scan_pid" 2>/dev/null; wait "$scan_pid" 2>/dev/null
fi

pair_output=$(bluetoothctl pair "$1" 2>&1)
if ! echo "$pair_output" | grep -qi "successful\|already paired"; then
    notify-send -u critical "Bluetooth" "Pair failed: $pair_output"
    exit 1
fi
bluetoothctl trust "$1" 2>/dev/null
