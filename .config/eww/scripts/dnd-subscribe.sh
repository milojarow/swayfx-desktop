#!/usr/bin/env bash
# feature: dnd
# role:    subscribe
# dnd-subscribe.sh — eww deflisten for do-not-disturb (mako) state.
#
# Named pipe receives toggle signals from the button onclick.
# Delegates toggle logic to dnd.sh (same script waybar uses).

ICON_DEFAULT=$'\xf3\xb0\x9a\xa2'  # 󰚢  notifications on  (U+F06A2)
ICON_DND=$'\xf3\xb0\x9a\xa3'      # 󰚣  do-not-disturb    (U+F06A3)
PIPE="/tmp/eww-dnd"

emit() {
    if makoctl mode | grep -q 'do-not-disturb'; then
        printf '{"active": true, "icon": "%s"}\n' "$ICON_DND"
    else
        printf '{"active": false, "icon": "%s"}\n' "$ICON_DEFAULT"
    fi
}

toggle() {
    ~/.config/sway/scripts/dnd.sh toggle
    emit
}

rm -f "$PIPE"
mkfifo "$PIPE"

emit

while read -r _ < "$PIPE"; do
    toggle
done
