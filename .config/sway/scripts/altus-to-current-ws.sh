#!/usr/bin/env bash
# ── altus-to-current-ws.sh ────────────────────────────────────────────────────
# Bring Altus to the currently focused workspace, mirroring how Telegram behaves
# when you click its notification: the app shows up on the workspace you're on.
#
# Wired from mako (see ~/.config/mako/config):
#   [app-name="Altus"]
#   on-button-left=exec $HOME/.config/sway/scripts/altus-to-current-ws.sh
#   on-touch=exec      $HOME/.config/sway/scripts/altus-to-current-ws.sh
#
# Mechanism:
#   - If Altus already has a window (on any workspace) -> pull it here + focus.
#   - If it's in the tray (no window) -> Activate its StatusNotifierItem, which
#     spawns the window on the focused workspace (verified), then pin it here.
# The tray bus name (:1.NNN) is ephemeral, so it's resolved at runtime by the
# owning PID of Altus' main electron process.
# ──────────────────────────────────────────────────────────────────────────────

APP_ID="Altus"

# mako passes the clicked notification's id as $1 (see ~/.config/mako/config).
# Our exec binding replaces mako's default invoke-default-action, which would
# normally dismiss the notification — so dismiss it explicitly, right away, so
# it disappears the moment you click instead of lingering until it expires.
notif_id="${1:-}"
[ -n "$notif_id" ] && makoctl dismiss -n "$notif_id" >/dev/null 2>&1

have_window() {
    swaymsg -t get_tree | jq -e --arg a "$APP_ID" \
        '.. | objects | select(.app_id? == $a)' >/dev/null 2>&1
}

# Already mapped somewhere: just bring it to the current workspace.
if have_window; then
    swaymsg "[app_id=\"$APP_ID\"] move container to workspace current, focus" >/dev/null 2>&1
    exit 0
fi

# In the tray: resolve Altus' main PID (the electron running /usr/lib/altus/app,
# not a --type= helper child) and Activate the tray item it owns.
altus_pid="$(ps -eo pid,args | grep -F '/usr/lib/altus/app' | grep -v grep \
    | grep -v -- '--type=' | awk '{print $1; exit}')"

if [ -n "$altus_pid" ]; then
    items="$(busctl --user get-property org.kde.StatusNotifierWatcher \
        /StatusNotifierWatcher org.kde.StatusNotifierWatcher \
        RegisteredStatusNotifierItems 2>/dev/null)"
    for bus in $(printf '%s\n' "$items" | grep -oE ':[0-9]+\.[0-9]+'); do
        owner="$(busctl --user status "$bus" 2>/dev/null \
            | grep -oE 'PID=[0-9]+' | head -1 | cut -d= -f2)"
        if [ "$owner" = "$altus_pid" ]; then
            busctl --user call "$bus" /StatusNotifierItem \
                org.kde.StatusNotifierItem Activate ii 0 0 >/dev/null 2>&1
            break
        fi
    done
fi

# Once the window shows up, pin it to the workspace we're on right now.
for _ in $(seq 1 50); do
    have_window && break
    sleep 0.1
done
swaymsg "[app_id=\"$APP_ID\"] move container to workspace current, focus" >/dev/null 2>&1
