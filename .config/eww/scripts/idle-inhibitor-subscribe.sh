#!/usr/bin/env bash
# feature: idle-inhibitor
# role:    subscribe
# idle-inhibitor-subscribe.sh — eww deflisten for idle inhibitor state.
#
# Architecture: named pipe receives toggle signals from the button onclick.
# Emits JSON on startup and after each toggle.
#
# Idle inhibition is implemented by killing/restarting swayidle — the same
# daemon managing the lock screen. When it's dead, the system never idles.

ICON_ACTIVE=$'\xf3\xb0\x92\xb3'    # 󰒳  inhibitor on  (U+F04B3)
ICON_INACTIVE=$'\xf3\xb0\x92\xb2'  # 󰒲  inhibitor off (U+F04B2)
PIPE="/tmp/eww-idle-inhibitor"

emit() {
    if pgrep -x swayidle > /dev/null; then
        printf '{"active": false, "icon": "%s"}\n' "$ICON_INACTIVE"
    else
        printf '{"active": true, "icon": "%s"}\n' "$ICON_ACTIVE"
    fi
}

# Re-emit current state when signaled (after external swayidle restart)
trap 'emit' USR1

toggle() {
    if pgrep -x swayidle > /dev/null; then
        pkill swayidle
    else
        swayidle -w -S seat0 &
    fi
    emit
}

# Recreate pipe on each (re)start
rm -f "$PIPE"
mkfifo "$PIPE"

# Bootstrap: emit current state immediately
emit

# Block waiting for toggle signals from the button
while read -r _ < "$PIPE"; do
    toggle
done
