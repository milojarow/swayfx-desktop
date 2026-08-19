#!/bin/bash
# ── Lid Handling ──────────────────────────────────────────────────────────────
# Role:     Lid close: detects S3 wake interrupt, saves backlight, turns off displays
# Files:    lid-handler.sh · lid-open-handler.sh · lid-bluetooth-reconnect.sh
#           ~/.config/sway/config.d/75-lid-switch.conf  (bindswitch config)
# Programs: swaymsg  brightnessctl  journalctl  systemctl  bluetoothctl  pactl
# Trigger:  sway bindswitch lid:on / lid:off  (via 75-lid-switch.conf)
# Requires: HandleLidSwitch=ignore in /etc/systemd/logind.conf
# Logs:     ~/.cache/lid-handler.log · ~/.local/log/bluetooth-reconnect.log
# State:    /tmp/kbd-lid-brightness  (keyboard backlight saved on close)
# ─────────────────────────────────────────────────────────────────────────────

# Check if the system just woke from suspend (within last 5 seconds)
# This happens when closing the lid generates an ACPI wake event during S3
LAST_RESUME=$(journalctl -b --no-pager -o short-unix -n 1 \
    --grep="System returned from sleep operation" 2>/dev/null | awk '{print int($1)}')
NOW=$(date +%s)

if [ -n "$LAST_RESUME" ] && [ $((NOW - LAST_RESUME)) -lt 5 ]; then
    # Lid close woke us from suspend — re-suspend immediately
    echo "$(date): Lid close woke system from S3, re-suspending" >> ~/.cache/lid-handler.log
    systemctl suspend
    exit 0
fi

# Check if suspend process is already running
if pgrep -f "systemd-sleep\|systemctl.*sleep" > /dev/null; then
    echo "$(date): Suspend in progress, ignoring lid close" >> ~/.cache/lid-handler.log
    exit 0
fi

# Check if manual secure-suspend is preparing the lock screen
# (window between lock.sh launch and systemctl suspend — grim must not see a dark screen)
if pgrep -f "secure-suspend.sh" > /dev/null; then
    echo "$(date): Secure suspend in progress, lid close ignored" >> ~/.cache/lid-handler.log
    exit 0
fi

# Normal lid close: turn off displays and keyboard backlight
brightnessctl --device="dell::kbd_backlight" get > /tmp/kbd-lid-brightness 2>/dev/null
brightnessctl --device="dell::kbd_backlight" set 0 --quiet 2>/dev/null
swaymsg "output * power off"
