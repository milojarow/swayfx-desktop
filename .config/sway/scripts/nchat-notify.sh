#!/bin/sh
# nchat-notify.sh — nchat's desktop_notify_command (see ~/.config/nchat/ui.conf):
#   desktop_notify_command=~/.config/sway/scripts/nchat-notify.sh '%1' '%2'
# Fires the desktop notification AND lights the waybar unread badge (red blink).
# %1 = sender (summary), %2 = message text (body).
notify-send -a nchat "$1" "$2"
touch /tmp/nchat-unread
pkill -RTMIN+10 waybar 2>/dev/null   # refresh custom/nchat -> .unread class
