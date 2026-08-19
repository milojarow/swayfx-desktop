#!/bin/sh
# ── Clipboard Functionality ──────────────────────────────────────────────────
# Role:    Restart daemon: wl-paste --watch waybar-signal clipboard
#          Kills any existing instance before launching a new one.
#          Called by exec_always $cliphist_watch in autostart.
# ─────────────────────────────────────────────────────────────────────────────
pkill -f "^wl-paste --watch.*waybar-signal.*clipboard$" 2>/dev/null
exec wl-paste --watch $HOME/.local/bin/waybar-signal clipboard
