#!/usr/bin/env bash

# Mark the currently focused window as swap target and switch to target mode

# Mark the current window as swap target
swaymsg mark swap_target

# Switch to the target selection mode using sway variable expansion
swaymsg mode '$mode_swap_target'

# Update waybar to reflect mode change
pkill -RTMIN+7 waybar
