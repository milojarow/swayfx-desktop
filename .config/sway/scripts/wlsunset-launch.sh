#!/usr/bin/env bash
# wlsunset-launch.sh — resolves geolocation, then execs wlsunset directly so
# systemd supervises the actual binary (Type=simple). Used as the ExecStart of
# wlsunset.service. Reads optional overrides from ~/.config/wlsunset/config.
#
# Usage:
#   wlsunset-launch.sh                  # normal day/night schedule
#   wlsunset-launch.sh --force-warm     # warm temp regardless of time of day

set -u

force_warm=0
[ "${1:-}" = "--force-warm" ] && force_warm=1

config="$HOME/.config/wlsunset/config"
[ -f "$config" ] && . "$config"

temp_low=${temp_low:-"4000"}
temp_high=${temp_high:-"6500"}
duration=${duration:-"900"}
location=${location:-"on"}
fallback_longitude=${fallback_longitude:-"8.7"}
fallback_latitude=${fallback_latitude:-"50.1"}

# Force-warm mode: clamp the high temp down to the low temp so wlsunset stays
# in warm regardless of the sun's position. wlsunset rejects equal temps with
# "high must be higher than low", so we use +1 K — visually imperceptible.
if [ "$force_warm" = "1" ]; then
    temp_high=$((temp_low + 1))
fi

if [ "$location" = "on" ]; then
    if [ -z "${longitude+x}" ] || [ -z "${latitude+x}" ]; then
        GEO=$(sh "$HOME/.config/sway/scripts/geoip.sh" 2>/dev/null || echo "")
    fi
    longitude=${longitude:-$(echo "$GEO" | jq -r '.longitude // empty' 2>/dev/null)}
    longitude=${longitude:-$fallback_longitude}
    latitude=${latitude:-$(echo "$GEO" | jq -r '.latitude // empty' 2>/dev/null)}
    latitude=${latitude:-$fallback_latitude}

    exec wlsunset -l "$latitude" -L "$longitude" \
                  -t "$temp_low" -T "$temp_high" -d "$duration"
else
    sunrise=${sunrise:-"07:00"}
    sunset_time=${sunset:-"19:00"}
    exec wlsunset -t "$temp_low" -T "$temp_high" -d "$duration" \
                  -S "$sunrise" -s "$sunset_time"
fi
