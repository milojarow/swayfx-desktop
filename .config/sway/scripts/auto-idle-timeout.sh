#!/bin/bash
# Use a lock file to ensure only one instance runs at a time
LOCKFILE="/tmp/auto-idle-timeout.lock"
exec 9>"$LOCKFILE"
flock -n 9 || exit 0
# ── Lock Screen & Idle ────────────────────────────────────────────────────────
# Role:     Non-interactive startup init; generates swayidle config with 5-min default
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

# Set timeout value (in minutes)
timeout_minutes=5

# Convert minutes to seconds
timeout_seconds=$((timeout_minutes * 60))

# Update swayidle config file
mkdir -p ~/.config/swayidle
cat > ~/.config/swayidle/config << EOF
# Lock screen after timeout
timeout $timeout_seconds 'pgrep -x swaylock > /dev/null || $HOME/.config/sway/scripts/lock.sh'

# Turn off displays after 2x timeout
timeout $(($timeout_seconds * 2)) 'swaymsg "output * power off"' resume 'swaymsg "output * power on"'

# Lock before sleep (skip if already locked)
before-sleep 'pgrep -x swaylock > /dev/null || $HOME/.config/sway/scripts/lock.sh'

# Make sure there's only one lock when the lock command is used
lock 'pgrep -x swaylock > /dev/null || $HOME/.config/sway/scripts/lock.sh'

# Restore display and keyboard backlight after system wake from suspend
after-resume 'swaymsg "output * power on"'
after-resume '$HOME/.config/sway/scripts/resume-handler.sh'
EOF

# Restart swayidle cleanly - minimize gap without sleep inhibitor
pkill -x swayidle 2>/dev/null
# Wait for old process to fully exit before starting new one
while pgrep -x swayidle > /dev/null 2>&1; do sleep 0.1; done
swayidle -w -S seat0 &
disown
{ sleep 0.1; pkill -USR1 -f 'idle-inhibitor-subscribe.sh' 2>/dev/null; } &
