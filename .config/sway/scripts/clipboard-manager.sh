#!/usr/bin/env bash
# ── Clipboard Functionality ──────────────────────────────────────────────────
# Role:     Stable launcher for the clipboard history picker. The real picker is
#           clipboard-picker.py (GTK3). Kept as the entry point so eww, waybar and
#           the $mod+Shift+p keybind ($clipboard) need no changes.
# Args:     $1 = font hint (legacy). Ignored — the GTK app themes itself via CSS.
# See:      clipboard-picker.py  ·  man clipboard-functionality
# ─────────────────────────────────────────────────────────────────────────────
exec python3 "$HOME/.config/sway/scripts/clipboard-picker.py" "$@"
