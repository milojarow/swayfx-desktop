#!/usr/bin/env bash
# feature: screenshot-mode
# role:    subscribe
# screenshot-mode-subscribe.sh — eww deflisten for the Print-key capture mode.
#
# Source of truth: ~/.local/state/screenshot-mode/mode ("traditional"|"aggressive"),
# shared with ~/.config/sway/scripts/screenshot-dispatch.sh (the Print dispatcher).
# Event-driven: emits one JSON line on start and on every state-file change
# (inotify on the dedicated state dir — no polling).

ICON=$'\xf3\xb0\x84\x84'  # 󰄄  camera-iris (U+F0104), same glyph as the sway screenshot mode

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/screenshot-mode"
STATE_FILE="$STATE_DIR/mode"

mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || printf 'traditional\n' > "$STATE_FILE"

emit() {
    local m
    m=$(cat "$STATE_FILE" 2>/dev/null)
    [ "$m" = "aggressive" ] || m="traditional"
    printf '{"mode":"%s","icon":"%s"}\n' "$m" "$ICON"
}

emit
while inotifywait -qq -e close_write -e moved_to -e create "$STATE_DIR"; do
    emit
done
