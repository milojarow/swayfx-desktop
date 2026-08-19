#!/usr/bin/env bash
# feature: window-title
# role:    action
# Right-click handler for eww window title — opens rofi to rename the focused
# window. Empty submit clears the custom name. Signals subscribe.py to re-emit.

LOG=/tmp/eww-wt-rename-debug.log
exec >> "$LOG" 2>&1
echo "--- $(date) ---"

NAMES_DIR="/tmp/eww-window-names-$USER"

info=$(swaymsg -t get_tree | jq -r '
    [.. | select(.focused? == true and .pid?)] | first // empty |
    [(.id|tostring), (.app_id // .window_properties.class // "")] | @tsv
')
echo "info: $info"
[ -z "$info" ] && echo "no focused window, exit" && exit 0

IFS=$'\t' read -r win_id _app_id <<< "$info"
echo "win_id: $win_id"

current_ctx=""
[ -f "$NAMES_DIR/$win_id.name" ] && current_ctx=$(cat "$NAMES_DIR/$win_id.name")

new_name=$(rofi \
    -dmenu \
    -theme-str 'window {location: north; anchor: north; y-offset: 40px; width: 360px;}' \
    -theme-str 'listview {lines: 0;}' \
    -theme-str 'inputbar {padding: 10px 14px;}' \
    -p "Window name:" \
    -filter "$current_ctx")
rofi_exit=$?
echo "rofi exit: $rofi_exit, new_name: '$new_name'"

[ $rofi_exit -ne 0 ] && echo "rofi cancelled" && exit 0

if [ -z "$new_name" ]; then
    rm -f "$NAMES_DIR/$win_id.name"
    echo "name cleared"
else
    mkdir -p "$NAMES_DIR"
    printf '%s' "$new_name" > "$NAMES_DIR/$win_id.name"
    echo "saved: $NAMES_DIR/$win_id.name"
fi

SUBSCRIBE_PID=$(pgrep -o -f "eww/scripts/window-title-subscribe.py")
echo "subscribe pid: $SUBSCRIBE_PID"
if [ -n "$SUBSCRIBE_PID" ]; then
    kill -USR1 "$SUBSCRIBE_PID"
    echo "signal sent"
else
    echo "subscribe.py not found"
fi
