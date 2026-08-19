#!/usr/bin/env bash
# feature: wifi
# role:    action
# wifi-qr-show.sh — generate and show a Wi-Fi join QR for the active network.
# Builds the standard `WIFI:` URI that Android/iOS cameras scan to join without
# typing the PSK, renders it to a private tmpfs PNG, and opens the centered
# wifi-qr window. The PSK only ever lands in the PNG (0600, on tmpfs) — never in
# an eww var nor on screen as text.

EWW=$HOME/.cargo/bin/eww
PNG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wifi-qr.png"

# Active wifi connection (NAME of the in-use 802-11-wireless connection)
conn=$(nmcli -t -f NAME,TYPE connection show --active \
       | awk -F: '$2=="802-11-wireless"{print $1; exit}')
[ -z "$conn" ] && exit 0

# Real broadcast SSID (fallback to the connection name) + PSK
ssid=$(nmcli -g 802-11-wireless.ssid connection show "$conn" 2>/dev/null)
[ -z "$ssid" ] && ssid="$conn"
psk=$(nmcli -s -g 802-11-wireless-security.psk connection show "$conn" 2>/dev/null)

# Escape the 5 special chars of the WIFI: format (backslash first)
esc() {
    printf '%s' "$1" \
      | sed -e 's/\\/\\\\/g' -e 's/;/\\;/g' -e 's/,/\\,/g' -e 's/:/\\:/g' -e 's/"/\\"/g'
}
ssid_e=$(esc "$ssid")

# Build the payload. The WPA token covers WPA/WPA2/WPA3 for phones; open nets
# use nopass (no P field).
if [ -n "$psk" ]; then
    payload="WIFI:T:WPA;S:${ssid_e};P:$(esc "$psk");;"
else
    payload="WIFI:T:nopass;S:${ssid_e};;"
fi

# Render to a private PNG (umask 077 -> 0600). Bail if qrencode fails.
( umask 077; qrencode -t PNG -o "$PNG" -s 8 -m 2 -l M -- "$payload" ) || exit 1

# Hand only the SSID to the window label (PSK is never stored in a var)
"$EWW" update wifi-qr-ssid="$ssid"

# close-then-open so GTK reloads the fresh PNG (defeats the pixbuf cache between opens)
"$EWW" close wifi-qr 2>/dev/null
"$EWW" open wifi-qr
