#!/bin/bash
# ── USB Management ────────────────────────────────────────────────────────────
# Role:     Force-refreshes the waybar USB module and confirms via notification
# Files:    usb-monitor.sh · usb-monitor-wrapper.sh
#           usb-action-mount.sh · usb-action-unmount.sh · usb-action-eject.sh
#           usb-action-open.sh · usb-action-refresh.sh
#           ~/.config/rofi/themes/usb-manager.rasi   (picker UI theme)
#           ~/.config/waybar/usb-menu.xml             (right-click GTK menu)
#           ~/.config/waybar/config.jsonc             (custom/usb module)
# Trigger:  waybar right-click → usb-menu.xml → "refresh" action
# Signal:   pkill -RTMIN+15 waybar
# ─────────────────────────────────────────────────────────────────────────────

# Signal waybar to update
pkill -RTMIN+15 waybar

# Show notification
notify-send -u low "USB Manager" "Refreshed USB status"
