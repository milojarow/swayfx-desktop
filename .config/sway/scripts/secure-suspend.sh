#!/bin/bash
# ── Lock Screen & Idle ────────────────────────────────────────────────────────
# Role:     Locks screen before suspending so screenshot is taken while monitor is on
# Files:    lock.sh · idle-timeout.sh · auto-idle-timeout.sh · secure-suspend.sh
#           ~/.config/swaylock/config           (swaylock visual config)
#           ~/.config/swayidle/config           (generated — do not edit manually)
#           ~/.config/sway/autostart            ($initialize_idle_daemon)
#           ~/.config/sway/config.d/01-definitions.conf  ($locking)
#           ~/.config/sway/modes/default        ($mod+x keybind)
#           ~/.config/sway/modes/shutdown       (l=lock, u=suspend)
#           ~/.config/waybar/config.jsonc       (idle_inhibitor module)
# Programs: swaylock  swayidle  grim  imagemagick  systemctl  notify-send  rofi
# Daemon:   swayidle (systemd user service, config at ~/.config/swayidle/config)
# Triggers: $mod+x keybind · swayidle timeout · before-sleep · shutdown menu
# ─────────────────────────────────────────────────────────────────────────────

# Prevent double-execution: if already suspending, exit silently
LOCKFILE="/tmp/secure-suspend.lock"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    exit 0
fi

LOG="$HOME/.cache/secure-suspend.log"
echo "--- $(date) ---" >> "$LOG"
echo "XDG_SESSION_ID=${XDG_SESSION_ID} WAYLAND_DISPLAY=${WAYLAND_DISPLAY} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}" >> "$LOG"

# Save keyboard backlight level for resume-handler.sh to restore after wake
brightnessctl --device="dell::kbd_backlight" get > /tmp/kbd-suspend-brightness 2>/dev/null

# Pre-compute screenshot+blur synchronously so swaylock renders immediately on launch
SCREENSHOT="/tmp/swaylock-blur.png"
if grim "$SCREENSHOT" 2>/dev/null; then
    echo "grim: ok, size=$(stat -c%s $SCREENSHOT 2>/dev/null) bytes" >> "$LOG"
    if command -v magick &>/dev/null; then
        magick "$SCREENSHOT" -blur 0x8 "$SCREENSHOT" 2>/dev/null
    else
        convert "$SCREENSHOT" -blur 0x8 "$SCREENSHOT" 2>/dev/null
    fi
    echo "blur: done, screenshot exists=$(test -f $SCREENSHOT && echo yes || echo no)" >> "$LOG"
else
    echo "grim: FAILED (exit $?)" >> "$LOG"
fi

# Lock screen FIRST so grim captures before lid might close
SECURE_SUSPEND_PREBLURRED=1 ~/.config/sway/scripts/lock.sh &

# Wait for swaylock process to start (screenshot captured, swaylock launched)
for i in $(seq 1 50); do
    pgrep -x swaylock > /dev/null && break
    sleep 0.1
done
echo "swaylock started: $(pgrep -x swaylock > /dev/null && echo yes || echo no) (after ${i} x 0.1s)" >> "$LOG"

# Wait for swaylock to lock the session in logind (surfaces rendered on all outputs)
# LockedHint=yes is set by swaylock via SetLockedHint(true) once ext-session-lock is acquired
for i in $(seq 1 50); do
    loginctl show-session "${XDG_SESSION_ID}" 2>/dev/null | grep -q "^LockedHint=yes" && break
    pgrep -x swaylock > /dev/null || break  # bail if swaylock died unexpectedly
    sleep 0.1
done
echo "LockedHint=yes reached: $(loginctl show-session "${XDG_SESSION_ID}" 2>/dev/null | grep -q "^LockedHint=yes" && echo yes || echo no)" >> "$LOG"

echo "calling systemctl suspend" >> "$LOG"
systemctl suspend
