#!/usr/bin/env sh
# Toggle the wlsunset systemd user services. Two services:
#   wlsunset.service       — auto schedule (normal day/night)
#   wlsunset-warm.service  — forced warm temperature regardless of time
# They have Conflicts= each other, so starting one stops the other.

# A unit is "on" if it's active, activating, or reloading. systemctl's
# default is-active --quiet only matches "active", which causes the toggle
# to misbehave during the brief activating window (e.g. geoip lookup).
unit_on() {
    case "$(systemctl --user show -p ActiveState --value "$1" 2>/dev/null)" in
        active|activating|reloading) return 0 ;;
        *) return 1 ;;
    esac
}

case $1'' in
'off')
    systemctl --user stop wlsunset.service wlsunset-warm.service
    ;;
'on')
    systemctl --user start wlsunset.service
    ;;
'toggle')
    if unit_on wlsunset.service; then
        systemctl --user stop wlsunset.service
    else
        systemctl --user start wlsunset.service
    fi
    ;;
'force-warm')
    if unit_on wlsunset-warm.service; then
        systemctl --user stop wlsunset-warm.service
    else
        systemctl --user start wlsunset-warm.service
    fi
    ;;
'status')
    # Emit JSON for the waybar custom/sunset module. The "alt" value selects the
    # format-icon (off/auto/warm). Mirrors eww's gamma-subscribe.sh state logic.
    if unit_on wlsunset-warm.service; then
        printf '{"alt":"warm","tooltip":"Gamma: máxima calidez (forzado)"}\n'
    elif unit_on wlsunset.service; then
        printf '{"alt":"auto","tooltip":"Gamma: horario automático día/noche"}\n'
    else
        printf '{"alt":"off","tooltip":"Gamma: corrección apagada"}\n'
    fi
    ;;
'check')
    command -v wlsunset
    exit $?
    ;;
esac
