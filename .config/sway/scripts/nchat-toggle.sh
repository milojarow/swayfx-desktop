#!/bin/sh
# nchat-toggle — bound to $mod+m and the waybar WhatsApp icon.
# Ensure the supervised service is up, then toggle nchat in/out of the scratchpad.
systemctl --user is-active --quiet nchat.service || systemctl --user start nchat.service
swaymsg '[app_id="nchat"] scratchpad show' && pkill -RTMIN+7 waybar
rm -f /tmp/nchat-unread; pkill -RTMIN+10 waybar 2>/dev/null   # apagar badge de no-leídos
