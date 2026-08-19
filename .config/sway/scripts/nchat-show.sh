#!/usr/bin/env bash
# ── nchat-show.sh ─────────────────────────────────────────────────────────────
# Click a WhatsApp/nchat notification → bring nchat to the current workspace and
# jump to the unread chat (the message's chat, in the common case).
#
# Wired from mako (~/.config/mako/config):
#   [app-name="nchat"]
#   on-button-left=exec $HOME/.config/sway/scripts/nchat-show.sh "$id"
#   on-touch=exec      $HOME/.config/sway/scripts/nchat-show.sh "$id"
#
# nchat has no CLI to open a chat by name; the closest is its internal Ctrl-f
# (jump to unread), sent via wtype once nchat holds focus. With a single unread
# chat (the usual case right after a message) this lands on the right one.
# ──────────────────────────────────────────────────────────────────────────────
APP_ID="nchat"

# mako passes the clicked notification id; our exec replaces mako's default
# dismiss action, so dismiss it explicitly so it disappears on click.
notif_id="${1:-}"
[ -n "$notif_id" ] && makoctl dismiss -n "$notif_id" >/dev/null 2>&1

# Service is supervised, but start it if somehow down.
systemctl --user is-active --quiet nchat.service || systemctl --user start nchat.service

# Wait until nchat has a window (it lives in the scratchpad), then pull it to the
# current workspace and focus it.
for _ in $(seq 1 30); do
    swaymsg -t get_tree | jq -e --arg a "$APP_ID" '.. | objects | select(.app_id? == $a)' >/dev/null 2>&1 && break
    sleep 0.1
done
swaymsg "[app_id=\"$APP_ID\"] move container to workspace current, focus" >/dev/null 2>&1
pkill -RTMIN+7 waybar
rm -f /tmp/nchat-unread; pkill -RTMIN+10 waybar 2>/dev/null   # apagar badge de no-leídos

# Once nchat actually holds focus, jump to the unread chat.
for _ in $(seq 1 15); do
    [ "$(swaymsg -t get_tree | jq -r 'recurse(.nodes[]?,.floating_nodes[]?) | select(.focused? == true) | .app_id // empty')" = "$APP_ID" ] && break
    sleep 0.1
done
command -v wtype >/dev/null 2>&1 && wtype -M ctrl -k f -m ctrl 2>/dev/null
