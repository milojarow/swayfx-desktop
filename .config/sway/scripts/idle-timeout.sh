#!/bin/bash
# ── Lock Screen & Idle ────────────────────────────────────────────────────────
# Role:     Interactive rofi dialog to set custom idle timeout; regenerates swayidle config
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

# Use rofi in dmenu mode to get timeout input with custom theme
timeout_minutes=$(rofi -dmenu \
                      -theme-str 'window {width: 400px;}' \
                      -theme-str 'entry {min-width: 100px;}' \
                      -theme-str 'inputbar {padding: 12px;}' \
                      -theme-str 'listview {lines: 0;}' \
                      -p "Idle timeout (minutes):" \
                      -mesg "Press Enter to confirm or Escape to cancel" \
                      -filter "5")

# Check if user canceled the dialog
if [ -z "$timeout_minutes" ]; then
    exit 0
fi

# Validate input is a number
if ! [[ "$timeout_minutes" =~ ^[0-9]+$ ]]; then
    notify-send "Invalid input" "Please enter a valid number"
    exit 1
fi

# Convert minutes to seconds
timeout_seconds=$((timeout_minutes * 60))

# Update config file - this keeps the other settings but updates the timeout
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

# Restart swayidle to apply changes
pkill swayidle || true
swayidle -w -S seat0 &
{ sleep 0.1; pkill -USR1 -f 'idle-inhibitor-subscribe.sh' 2>/dev/null; } &

# Notify user
notify-send "Idle timeout set" "System will lock after $timeout_minutes minutes of inactivity"
