#!/usr/bin/env bash
# feature: gamma
# role:    subscribe
# gamma-subscribe.sh — eww deflisten for gamma correction state.
#
# Three states tracked via systemd services:
#   off   — neither wlsunset.service nor wlsunset-warm.service active
#   auto  — wlsunset.service active (normal day/night schedule)
#   warm  — wlsunset-warm.service active (forced warm temperature)
#
# FIFO commands:
#   t  toggle auto schedule (sunset.sh toggle)
#   w  toggle forced warm   (sunset.sh force-warm)

ICON_OFF=$'\xf3\xb0\x8c\xb6'   # 󰌶  gamma off  (U+F0336)
ICON_AUTO=$'\xf3\xb0\x8c\xb5'  # 󰌵  gamma auto (U+F0335)
ICON_WARM=$'\xf3\xb1\xa9\x8c'  # 󱩌  gamma warm (U+F1A4C)
PIPE="/tmp/eww-gamma"

unit_running() {
    # Treat both "active" and "activating" as on. Systemd's Conflicts= lets
    # one unit be in "activating" while the other is still "deactivating" for
    # a few hundred ms; emitting the right state during that window matters
    # for the icon to feel responsive.
    case "$(systemctl --user show -p ActiveState --value "$1" 2>/dev/null)" in
        active|activating|reloading) return 0 ;;
        *) return 1 ;;
    esac
}

emit() {
    if unit_running wlsunset-warm.service; then
        printf '{"active": true, "warm": true, "icon": "%s"}\n' "$ICON_WARM"
    elif unit_running wlsunset.service; then
        printf '{"active": true, "warm": false, "icon": "%s"}\n' "$ICON_AUTO"
    else
        printf '{"active": false, "warm": false, "icon": "%s"}\n' "$ICON_OFF"
    fi
}

toggle_auto() {
    ~/.config/sway/scripts/sunset.sh toggle
    emit
}

toggle_warm() {
    ~/.config/sway/scripts/sunset.sh force-warm
    emit
}

rm -f "$PIPE"
mkfifo "$PIPE"

emit

while read -r cmd < "$PIPE"; do
    case "$cmd" in
        w) toggle_warm ;;
        *) toggle_auto ;;
    esac
done
