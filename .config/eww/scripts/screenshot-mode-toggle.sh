#!/usr/bin/env bash
# feature: screenshot-mode
# role:    action
# screenshot-mode-toggle.sh — flips the Print-key capture mode
# (traditional <-> aggressive). The eww widget follows via
# screenshot-mode-subscribe.sh (inotify); sway's screenshot-dispatch.sh
# reads the same file on each Print press.

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/screenshot-mode"
STATE_FILE="$STATE_DIR/mode"
mkdir -p "$STATE_DIR"

current=$(cat "$STATE_FILE" 2>/dev/null)
if [ "$current" = "aggressive" ]; then
    new="traditional"
    hint="Print abre el menú (p: área + swappy · o: pantalla)"
else
    new="aggressive"
    hint="Print va directo: seleccionas área y queda en el clipboard"
fi

printf '%s\n' "$new" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
notify-send -t 2500 "Captura: $new" "$hint"
