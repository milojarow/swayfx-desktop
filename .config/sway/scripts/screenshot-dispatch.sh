#!/bin/bash
# ── Screenshots ───────────────────────────────────────────────────────────────
# Role:     Print-key dispatcher: routes to the screenshot binding mode
#           (traditional) or frozen region-select straight to clipboard
#           (aggressive), based on the capture-mode state file
# Files:    screenshot-dispatch.sh · screenshot-frozen.sh · screenshot-notify.sh
#           screenshot-clipboard-notify.sh
#           ~/.local/state/screenshot-mode/mode                        (capture mode state)
#           ~/.config/eww/widgets/screenshot-mode.yuck                 (desktop toggle widget)
#           ~/.config/eww/scripts/screenshot-mode-subscribe.sh         (widget state feed)
#           ~/.config/eww/scripts/screenshot-mode-toggle.sh            (widget click action)
#           ~/.config/sway/modes/screenshot                            (mode + Print binding)
#           ~/.config/sway/config.d/01-definitions.conf                ($screenshot_dispatch)
# Programs: swaymsg  jq  wl-copy  notify-send
# Daemons:  screenshot-clipboard-notify.service  (sends the toast when the PNG
#           lands in the clipboard — aggressive mode relies on it, no own notify)
# Triggers: Print keybind (always; behavior depends on state file)
# Storage:  aggressive mode: clipboard only, nothing on disk
# ─────────────────────────────────────────────────────────────────────────────

set -u

STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/screenshot-mode/mode"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mode=$(cat "$STATE_FILE" 2>/dev/null || echo traditional)

if [ "$mode" = "aggressive" ]; then
    # Frozen screen + slurp region select -> clipboard. No swappy, no menu.
    tmp=$(mktemp /tmp/screenshot-aggressive-XXXXXX.png)
    trap 'rm -f "$tmp"' EXIT
    # screenshot-frozen.sh exits 1 on cancelled selection (Escape): copy
    # nothing rather than clobber the clipboard with an empty PNG.
    if "$SCRIPT_DIR/screenshot-frozen.sh" > "$tmp" && [ -s "$tmp" ]; then
        wl-copy --type image/png < "$tmp"
    fi
else
    # The traditional binding mode's name is the full pango hint string with
    # theme colors already expanded, so resolve it live from sway instead of
    # hardcoding: it is the only binding mode containing "Pick".
    mode_name=$(swaymsg -t get_binding_modes | jq -r '[.[] | select(contains("Pick"))][0] // empty')
    if [ -n "$mode_name" ]; then
        swaymsg "mode \"$mode_name\"" >/dev/null
    else
        notify-send -t 3000 "Screenshots" "screenshot binding mode not found"
    fi
fi
