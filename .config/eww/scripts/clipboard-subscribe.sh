#!/usr/bin/env bash
# feature: clipboard
# role:    subscribe
# clipboard-subscribe.sh — eww deflisten for clipboard state.
# Watches ~/.cache/cliphist/ via inotifywait for real-time count updates.

ICON=$'\xf3\xb0\xa8\xb8'  # 󰨸  clipboard  (U+F0A38)
WATCH_DIR="$HOME/.cache/cliphist"

emit() {
    count=$(cliphist list 2>/dev/null | wc -l)
    printf '{"icon": "%s", "count": %d}\n' "$ICON" "$count"
}

mkdir -p "$WATCH_DIR"
emit

while inotifywait -q -e modify,create,delete,moved_to "$WATCH_DIR" 2>/dev/null; do
    emit
done
