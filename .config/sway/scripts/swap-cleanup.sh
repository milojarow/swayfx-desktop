#!/usr/bin/env bash

# Clean up swap mode - remove any temporary marks

# Remove swap target mark if it exists
swaymsg '[con_mark="swap_target"] unmark' 2>/dev/null

# Update waybar
pkill -RTMIN+7 waybar
