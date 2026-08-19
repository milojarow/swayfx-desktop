#!/usr/bin/env bash

# Execute swap between marked target and currently focused window

# Check if target is marked
if ! swaymsg -t get_marks | grep -q '"swap_target"'; then
    exit 1
fi

# Execute the swap
swaymsg swap container with mark swap_target

# Clean up the mark
swaymsg '[con_mark="swap_target"] unmark'

# Update waybar
pkill -RTMIN+7 waybar
