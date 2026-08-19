#!/usr/bin/env bash
# feature: wifi
# role:    action
# wifi-pw-submit.sh — close the eww password prompt and apply the typed key.
# Invoked by the prompt's input :onaccept as:  wifi-pw-submit.sh '{}'
# The password arrives as $1 (single-quoted in the yuck, so spaces / $ / ` are
# preserved literally). setsid -f detaches the connect so eww's onaccept timeout
# can't kill it mid-connection, and passes the password as a literal argv slot
# (no shell re-parsing — avoids the swaymsg-exec quoting trap).
#
# Two modes (wifi-pw-mode defvar):
#   connect — new/unknown secured network → device wifi connect with the password
#   edit    — saved network → modify the existing profile's PSK in place, then
#             reconnect via the known path (no forget needed)

EWW=$HOME/.cargo/bin/eww
pw="$1"

"$EWW" close wifi-password-prompt 2>/dev/null

mode=$("$EWW" get wifi-pw-mode)
"$EWW" update wifi-pw-mode="connect"   # reset to default for the next prompt

[ -z "$pw" ] && exit 0   # empty submit = cancel

ssid=$("$EWW" get wifi-pw-ssid)
bssid=$("$EWW" get wifi-pw-bssid)
sec=$("$EWW" get wifi-pw-security)

if [ "$mode" = "edit" ]; then
    # Change the saved profile's PSK in place, then reconnect via the known
    # path (wifi-connect.sh with known=true does `connection up id "$ssid"`).
    nmcli connection modify "$ssid" wifi-sec.psk "$pw" 2>/dev/null
    setsid -f ~/.config/eww/scripts/wifi-connect.sh "$ssid" true "$sec" "$bssid" >/dev/null 2>&1
else
    setsid -f ~/.config/eww/scripts/wifi-connect.sh "$ssid" false "$sec" "$bssid" "$pw" >/dev/null 2>&1
fi
