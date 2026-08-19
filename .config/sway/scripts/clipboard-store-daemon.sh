#!/bin/sh
# ── Clipboard Functionality ──────────────────────────────────────────────────
# Role:    Restart daemon: wl-paste --watch clipboard-utf16-filter.py
#          Kills any existing instance before launching a new one.
#          Called by exec_always in 99-autostart-applications.conf.
# ─────────────────────────────────────────────────────────────────────────────
FILTER="$HOME/.config/sway/scripts/clipboard-utf16-filter.py"

pkill -f "^wl-paste --watch.*clipboard-utf16-filter" 2>/dev/null
exec wl-paste --watch "$FILTER"
