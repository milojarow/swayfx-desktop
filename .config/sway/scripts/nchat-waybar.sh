#!/bin/sh
# nchat-waybar.sh — exec for the custom/nchat waybar module (return-type json).
# Emits the unread state as a CSS class so the WhatsApp icon can blink red.
#   /tmp/nchat-unread present  -> class "unread" (CSS makes it blink @error_color)
#   absent                     -> class "idle"   (normal)
if [ -f /tmp/nchat-unread ]; then
    echo '{"class":"unread","tooltip":"WhatsApp — mensajes sin leer"}'
else
    echo '{"class":"idle","tooltip":"WhatsApp (nchat)"}'
fi
