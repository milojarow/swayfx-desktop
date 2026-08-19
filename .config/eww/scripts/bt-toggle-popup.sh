#!/usr/bin/env bash
# feature: bt
# role:    action
if eww active-windows 2>/dev/null | grep -q "bt-popup"; then
    eww close bt-popup
    eww update bt-popup-open=0
    echo "$(date): TRIGGER closed — bt-popup-open=$(eww get bt-popup-open 2>/dev/null)" >> /tmp/bt-close.log
else
    eww open bt-popup
    eww update bt-popup-open=1
    echo "$(date): TRIGGER opened — bt-popup-open=$(eww get bt-popup-open 2>/dev/null)" >> /tmp/bt-close.log
fi
