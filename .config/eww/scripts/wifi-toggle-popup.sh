#!/usr/bin/env bash
# feature: wifi
# role:    action
EWW=$HOME/.cargo/bin/eww

# Decide from the daemon's real window list, not from the shadow variable:
# the two can desync (a failed/slow `open`, a close that never ran) and then
# the click does the opposite of what the screen shows. See: man eww-guard.
if $EWW active-windows 2>/dev/null | grep -q '^wifi-popup:'; then
    $EWW close wifi-popup 2>/dev/null
    $EWW update wifi-popup-open=0
    $EWW update wifi-password=""
    $EWW close wifi-qr 2>/dev/null
    rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wifi-qr.png"
else
    $EWW open wifi-popup 2>/dev/null
    $EWW update wifi-popup-open=1
    ~/.config/eww/scripts/wifi-public-ip.sh &
fi
