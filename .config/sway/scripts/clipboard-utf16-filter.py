#!/usr/bin/env python3
# ── Clipboard Functionality ──────────────────────────────────────────────────
# Role:     Intercepts clipboard data from wl-paste; converts UTF-16 LE to
#           UTF-8 before storing, so Brave's URL copies appear clean in history
# Files:    clipboard-manager.sh · clipboard-utf16-filter.py
#           ~/.config/rofi/themes/coffee-metal          (picker UI theme)
#           ~/.config/waybar/config.jsonc               (custom/clipboard module)
#           ~/.config/sway/autostart                    ($cliphist_store, $cliphist_watch, $clip-persist)
#           ~/.config/sway/config.d/01-definitions.conf ($clipboard, $clipboard-del)
#           ~/.config/sway/config.d/99-autostart-applications.conf
#           ~/.config/sway/modes/shutdown               ($purge_cliphist)
# Programs: cliphist  wl-paste  wl-copy  wl-clip-persist  waybar-signal  rofi
# Daemons:  wl-paste --watch clipboard-utf16-filter.py    (via $cliphist_store)
#           wl-paste --watch waybar-signal clipboard       (via $cliphist_watch)
#           wl-clip-persist --clipboard regular ...        (via $clip-persist)
# Callers:  99-autostart-applications.conf (exec at sway startup)
# Storage:  ~/.cache/cliphist/db  (SQLite, purged on logout if configured)
# ─────────────────────────────────────────────────────────────────────────────
import sys
import subprocess


def normalize(data: bytes) -> bytes:
    # BOM-prefixed UTF-16 (FF FE)
    if data.startswith(b'\xff\xfe'):
        try:
            return data.decode('utf-16').encode('utf-8')
        except Exception:
            return data

    # Heuristic: if >=80% of odd-indexed bytes in the first 64 bytes are null,
    # the data is almost certainly UTF-16 LE without BOM.
    sample = data[:64]
    if len(sample) >= 4:
        odd_nulls = sum(1 for i in range(1, len(sample), 2) if sample[i] == 0)
        odd_count = len(sample) // 2
        if odd_count > 0 and odd_nulls / odd_count >= 0.80:
            try:
                return data.decode('utf-16-le').encode('utf-8')
            except Exception:
                return data

    return data


def main():
    data = sys.stdin.buffer.read()
    if not data:
        return
    result = normalize(data)
    subprocess.run(['cliphist', 'store'], input=result, check=False)


if __name__ == '__main__':
    main()
