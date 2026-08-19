#!/usr/bin/env bash
# feature: wifi
# role:    action
EWW=$HOME/.cargo/bin/eww
$EWW close wifi-popup 2>/dev/null
$EWW update wifi-popup-open=0
$EWW update wifi-password=""
$EWW close wifi-qr 2>/dev/null
rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wifi-qr.png"
