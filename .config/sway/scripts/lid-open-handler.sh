#!/bin/bash
# ── Lid Handling ──────────────────────────────────────────────────────────────
# Role:     Lid open: restores display, backlight, calls bluetooth fix
# Files:    lid-handler.sh · lid-open-handler.sh · lid-bluetooth-reconnect.sh
#           ~/.config/sway/config.d/75-lid-switch.conf  (bindswitch config)
# Programs: swaymsg  brightnessctl  journalctl  systemctl  bluetoothctl  pactl
# Trigger:  sway bindswitch lid:on / lid:off  (via 75-lid-switch.conf)
# Requires: HandleLidSwitch=ignore in /etc/systemd/logind.conf
# Logs:     ~/.cache/lid-handler.log · ~/.local/log/bluetooth-reconnect.log
# State:    /tmp/kbd-lid-brightness  (keyboard backlight saved on close)
# ─────────────────────────────────────────────────────────────────────────────

swaymsg "output * power on"

# Restore keyboard backlight to pre-close brightness
if [ -f /tmp/kbd-lid-brightness ]; then
    SAVED=$(cat /tmp/kbd-lid-brightness)
    brightnessctl --device="dell::kbd_backlight" set "${SAVED}" --quiet 2>/dev/null
    rm -f /tmp/kbd-lid-brightness
else
    brightnessctl --device="dell::kbd_backlight" set 2 --quiet 2>/dev/null
fi

~/.config/sway/scripts/lid-bluetooth-reconnect.sh
