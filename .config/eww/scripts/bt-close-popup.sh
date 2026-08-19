#!/usr/bin/env bash
# feature: bt
# role:    action
eww update bt-popup-open=0
eww close bt-popup
echo "$(date): X button — bt-popup-open=$(eww get bt-popup-open 2>/dev/null)" >> /tmp/bt-close.log
