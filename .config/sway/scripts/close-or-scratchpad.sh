#!/bin/sh
# close-or-scratchpad — bound to $mod+Shift+q.
# If the focused window is nchat, hide it to the scratchpad (keep it alive,
# still receiving). For every other window, behave exactly like the normal kill.
app=$(swaymsg -t get_tree | jq -r '.. | select(.focused?==true) | .app_id // empty' | head -1)
if [ "$app" = "nchat" ]; then
    swaymsg move scratchpad && pkill -RTMIN+7 waybar   # refresh scratchpad indicator
else
    swaymsg kill
fi
