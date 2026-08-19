#!/usr/bin/env bash
# feature: wifi
# role:    action
# wifi-password-toggle.sh — reveal/hide the connected network's PSK in the popup.
# Lazy: only pulls the secret from NetworkManager when revealing; clears it when
# hiding. The wifi-close-popup / wifi-toggle-popup scripts also clear it, so the
# password is never left revealed once the popup closes.

EWW=$HOME/.cargo/bin/eww

if [ -n "$("$EWW" get wifi-password 2>/dev/null)" ]; then
    # Currently revealed -> hide
    "$EWW" update wifi-password=""
else
    # Hidden -> fetch the PSK of the active wifi connection and reveal it
    conn=$(nmcli -t -f NAME,TYPE connection show --active \
           | awk -F: '$2=="802-11-wireless"{print $1; exit}')
    if [ -z "$conn" ]; then
        "$EWW" update wifi-password="(not connected)"
        exit 0
    fi
    psk=$(nmcli -s -g 802-11-wireless-security.psk connection show "$conn" 2>/dev/null)
    "$EWW" update wifi-password="${psk:-(none)}"
fi
