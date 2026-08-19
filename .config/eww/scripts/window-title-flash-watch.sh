#!/usr/bin/env bash
# feature: window-title
# role:    subscribe
# Event-driven flash watcher for the eww bar window title.
# Blocks on inotifywait — zero CPU between events.
# Fires only when the flash file is created, written, or deleted.

FLASH_FILE="/tmp/eww-window-title-flash-${USER}"

# Output initial state on startup
if [ -f "$FLASH_FILE" ]; then
    head -1 "$FLASH_FILE"
else
    echo ""
fi

# Block until /tmp events on this specific file
inotifywait -m -e create,close_write,delete --format '%e %f' /tmp/ 2>/dev/null |
while read -r event fname; do
    [[ "$fname" != "eww-window-title-flash-${USER}" ]] && continue
    if [[ "$event" == *DELETE* ]]; then
        echo ""
    else
        [ -f "$FLASH_FILE" ] && head -1 "$FLASH_FILE" || echo ""
    fi
done
