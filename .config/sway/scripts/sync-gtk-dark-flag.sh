#!/bin/bash
# Sync gtk-application-prefer-dark-theme in gtk-{3,4}.0/settings.ini to the active
# color-scheme. GTK3 apps (e.g. Electron/Altus) read THIS flag and it OVERRIDES
# gsettings color-scheme; a stale "=1" left from a previous dark theme makes the
# flag-gated built-in themes (Adwaita / HighContrast) render dark while the page
# stays light -> split / white text. Called by the boot+reload path
# (90-enable-theme.conf); mirrors theme-selector.sh FASE0 so both paths agree.
# Arg 1: the active $gtk-color-scheme value ("prefer-light" | "prefer-dark").
set -u

scheme="${1:-}"
if [ "$scheme" = "prefer-light" ]; then pd=0; else pd=1; fi

for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
    if [ -f "$f" ] && grep -q '^gtk-application-prefer-dark-theme=' "$f"; then
        sed -i "s|^gtk-application-prefer-dark-theme=.*|gtk-application-prefer-dark-theme=${pd}|" "$f"
    fi
done
