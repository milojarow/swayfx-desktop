#!/usr/bin/env bash
# ── Screenshots ───────────────────────────────────────────────────────────────
# Role:     Daemon: monitors ~/Screenshots via inotifywait; sends notify-send on PNG save
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

LOCKFILE="/tmp/screenshot-notify.lock"
DIR=${XDG_SCREENSHOTS_DIR:-$HOME/Screenshots}

# Exit if already running
if [ -f "$LOCKFILE" ] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
    exit 0
fi

# Write our PID and setup cleanup
echo $$ > "$LOCKFILE"
trap "rm -f '$LOCKFILE'" EXIT
trap "rm -f '$LOCKFILE'; exit 0" INT TERM

# Export necessary environment variables for notify-send
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY}"
export DISPLAY="${DISPLAY}"

mkdir -p "$DIR"

# Monitor for file saves
while true; do
    FILE=$(inotifywait -q -e close_write --format '%f' "$DIR" 2>&1)
    case "$FILE" in
        *.png)
            # Debounce to prevent duplicate notifications (100ms threshold)
            NOW=$(date +%s%N)
            LAST=$(cat /tmp/screenshot-save-last 2>/dev/null || echo 0)
            DIFF=$((NOW - LAST))
            if [[ $DIFF -gt 100000000 ]]; then
                echo $NOW > /tmp/screenshot-save-last
                notify-send -t 5000 "Screenshot saved" "$FILE"
            fi
            ;;
    esac
done
