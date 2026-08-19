#!/bin/bash
# feature: battery
# role:    subscribe
# Event-driven battery monitor via upower
# Emits JSON on every battery state change — instant charging detection

get_battery() {
    local capacity status
    capacity=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 0)
    status=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
    echo "{\"capacity\":${capacity},\"status\":\"${status}\"}"
}

# Emit initial state immediately
get_battery

# upower --monitor emits one line per event — filter for battery/AC only
upower --monitor 2>/dev/null | while read -r line; do
    case "$line" in
        *battery_BAT*|*line_power_AC*)
            get_battery
            ;;
    esac
done
