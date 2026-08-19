#!/usr/bin/env bash
# ── USB Management ────────────────────────────────────────────────────────────
# Role:     Calls usb-monitor.sh with stderr suppressed for clean JSON output
# Files:    usb-monitor.sh · usb-monitor-wrapper.sh
#           usb-action-mount.sh · usb-action-unmount.sh · usb-action-eject.sh
#           usb-action-open.sh · usb-action-refresh.sh
#           ~/.config/rofi/themes/usb-manager.rasi   (picker UI theme)
#           ~/.config/waybar/usb-menu.xml             (right-click GTK menu)
#           ~/.config/waybar/config.jsonc             (custom/usb module, exec target)
# Trigger:  waybar polls this wrapper every 5s as the module exec command
# ─────────────────────────────────────────────────────────────────────────────

# Execute the main script and ensure only JSON output
/usr/bin/bash $HOME/.config/sway/scripts/usb-monitor.sh 2>/dev/null
