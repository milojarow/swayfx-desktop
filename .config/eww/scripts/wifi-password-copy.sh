#!/usr/bin/env bash
# feature: wifi
# role:    action
# wifi-password-copy.sh — copy the connected network's PSK to the clipboard.
# Fetches fresh from NetworkManager, so it works whether or not the password
# is currently revealed in the popup (no need to toggle the eye first).

conn=$(nmcli -t -f NAME,TYPE connection show --active \
       | awk -F: '$2=="802-11-wireless"{print $1; exit}')
[ -z "$conn" ] && exit 0
psk=$(nmcli -s -g 802-11-wireless-security.psk connection show "$conn" 2>/dev/null)
[ -n "$psk" ] && printf %s "$psk" | wl-copy
