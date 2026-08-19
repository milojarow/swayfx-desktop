#!/bin/bash
# ── Lock Screen & Idle ────────────────────────────────────────────────────────
# Role:     Restore keyboard backlight after system wake from suspend
# Files:    secure-suspend.sh · auto-idle-timeout.sh · idle-timeout.sh
# State:    /tmp/kbd-suspend-brightness  (saved by secure-suspend.sh before sleep)
# Trigger:  swayidle after-resume event (configured in auto-idle-timeout.sh / idle-timeout.sh)
# Note:     swaymsg "output * power on" is called before this script via after-resume
# ─────────────────────────────────────────────────────────────────────────────

# eww windows are reopened by eww-resume.service (~/.scripts/eww-resume-watch.sh:
# it waits for the eww daemon to answer and for the outputs to settle first).
# This handler used to call open-windows.sh too (2026-03-08, before that service
# existed) — two concurrent runners raced and pkill'ed each other's CLIs, and
# during the 2026-08-15 resume storm one of them forked a rogue eww daemon.
# Single owner now. See: man eww-guard.

# Restore keyboard backlight to pre-suspend level, or default to 2
if [[ -f /tmp/kbd-suspend-brightness ]]; then
    SAVED=$(cat /tmp/kbd-suspend-brightness)
    brightnessctl --device="dell::kbd_backlight" set "${SAVED}" --quiet 2>/dev/null
    rm -f /tmp/kbd-suspend-brightness
else
    brightnessctl --device="dell::kbd_backlight" set 2 --quiet 2>/dev/null
fi
