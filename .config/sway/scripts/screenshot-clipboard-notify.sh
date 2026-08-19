#!/usr/bin/env bash
# ── Screenshots ───────────────────────────────────────────────────────────────
# Role:     Daemon: monitors clipboard via wl-paste --watch; sends notify-send on PNG copy
# Files:    screenshot-dispatch.sh · screenshot-frozen.sh · screenshot-notify.sh · screenshot-clipboard-notify.sh
#           ~/.config/swappy/config                                    (editor settings)
#           ~/.config/systemd/user/screenshot-notify.service          (save daemon unit)
#           ~/.config/systemd/user/screenshot-clipboard-notify.service (clipboard daemon unit)
#           ~/.config/sway/modes/screenshot                           (mode + keybindings)
#           ~/.config/sway/config.d/01-definitions.conf               (grimshot, swappy, upload_pipe vars)
#           ~/.config/sway/autostart                                   ($swappy_notify, $screenshot_clipboard_notify)
#           ~/.config/sway/config.d/99-autostart-applications.conf    (exec_always daemon start)
# Programs: grim  slurp  swayimg  imagemagick  swappy  inotifywait  notify-send  wl-paste  wl-copy  curl
# Daemons:  screenshot-notify.service · screenshot-clipboard-notify.service  (sway-session.target)
# Triggers: Print keybind → screenshot mode → p / o / Shift+p / Shift+o
# Storage:  ~/Screenshots/  (or $XDG_SCREENSHOTS_DIR)
# ─────────────────────────────────────────────────────────────────────────────

# Monitor clipboard for image copies and notify
LOCKFILE="/tmp/screenshot-clipboard-notify.lock"

# Check if already running
if [ -f "$LOCKFILE" ]; then
    OLD_PID=$(cat "$LOCKFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && [ "$OLD_PID" != "$$" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        # Another instance is running, kill it and its children
        pkill -P "$OLD_PID" 2>/dev/null || true
        kill "$OLD_PID" 2>/dev/null || true
        sleep 0.5
    fi
    # Remove stale lockfile
    rm -f "$LOCKFILE"
fi

# Kill any orphaned wl-paste processes from previous runs
pkill -f "wl-paste.*clipboard-notify-callback" 2>/dev/null || true

# Write our PID and setup cleanup
echo $$ > "$LOCKFILE"
trap "rm -f '$LOCKFILE'" EXIT INT TERM

# Export necessary environment variables for notify-send
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY}"

# Create a callback script that will be executed by wl-paste --watch
CALLBACK_SCRIPT="/tmp/clipboard-notify-callback-$$.sh"
cat > "$CALLBACK_SCRIPT" << 'EOF'
#!/bin/bash
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY}"

MIME=$(wl-paste -l | head -1)
if [[ "$MIME" == "image/png" ]]; then
    # Use flock to prevent race condition when multiple clipboard events fire simultaneously
    (
        flock -x 200
        NOW=$(date +%s%N)
        LAST=$(cat /tmp/screenshot-clipboard-last 2>/dev/null || echo 0)
        DIFF=$((NOW - LAST))
        if [[ $DIFF -gt 500000000 ]]; then
            echo $NOW > /tmp/screenshot-clipboard-last
            notify-send -t 5000 "Screenshot copied to clipboard"
        fi
    ) 200>/tmp/screenshot-clipboard-debounce.lock
fi
EOF

chmod +x "$CALLBACK_SCRIPT"

# Update trap to cleanup both lockfile and callback script
trap "rm -f '$LOCKFILE' '$CALLBACK_SCRIPT'" EXIT INT TERM

wl-paste --watch "$CALLBACK_SCRIPT"
