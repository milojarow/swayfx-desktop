#!/usr/bin/env bash
# first-run.sh — run ONCE, after copying this repo's dotfiles into $HOME.
#
# It does the three things that are not obvious and without which the desktop
# comes up broken:
#
#   1. expands __HOME__ in the three config formats that do not go through a
#      shell and therefore cannot use $HOME (foot, xdg-desktop-portal-wlr, and
#      the D-Bus service file)
#   2. makes every shipped script executable — git preserves the bit, a manual
#      copy through some file managers does not
#   3. bootstraps the palette theming system, which GENERATES the colour files
#      that ~20 eww stylesheets, waybar's style.css and rofi's config.rasi
#      import by name. Until it has run once those imports resolve to nothing
#      and everything renders unstyled.
#
# Safe to re-run.
set -euo pipefail

THEME="${1:-catppuccin-frappe}"
C="$HOME/.config"

[ -d "$C/sway/themes/$THEME" ] || {
    echo "no such theme: $THEME" >&2
    echo "available: $(ls "$C/sway/themes" 2>/dev/null | tr '\n' ' ')" >&2
    exit 1
}

echo "1. expanding __HOME__"
for f in "$C/foot/foot.ini" \
         "$C/xdg-desktop-portal-wlr/config" \
         "$HOME/.local/share/dbus-1/services/org.freedesktop.FileManager1.service"; do
    [ -f "$f" ] || { echo "   missing (skipped): $f"; continue; }
    sed -i "s|__HOME__|$HOME|g" "$f"
    echo "   $f"
done

echo "2. making scripts executable"
n=0
while IFS= read -r -d '' f; do
    head -c2 "$f" | grep -q '#!' && { chmod +x "$f"; n=$((n+1)); }
done < <(find "$C/sway/scripts" "$C/eww/scripts" "$C/xdg-desktop-portal-wlr" \
              "$HOME/.scripts" "$HOME/.local/bin" -type f -print0 2>/dev/null)
echo "   $n scripts"

echo "3. bootstrapping theme: $THEME"
"$C/sway/scripts/theme-cache-regen.sh" all
CACHE="$HOME/.cache/sway-theming/$THEME"
mkdir -p "$C/sway/definitions.d" "$C/foot" "$C/waybar" "$C/rofi" "$C/wofi" "$C/eww/styles"
ln -sf "$C/sway/themes/$THEME/theme.conf"     "$C/sway/definitions.d/theme.conf"
ln -sf "$C/sway/themes/$THEME/foot-theme.ini" "$C/foot/foot-theme.ini"
ln -sf "$CACHE/waybar.theme.css"  "$C/waybar/theme.css"
ln -sf "$CACHE/rofi.cachyos.rasi" "$C/rofi/cachyos.rasi"
ln -sf "$CACHE/wofi.style.css"    "$C/wofi/style.css"
ln -sf "$CACHE/eww.theme.scss"    "$C/eww/styles/theme.scss"
echo "   6 symlinks (same ones \$mod+t swaps from now on)"

echo "4. systemd user units"
systemctl --user daemon-reload
systemctl --user enable eww.service waybar.service eww-watchdog.timer \
                        floating-memory.service floating-placer.service \
                        notif-dismiss-on-focus.service 2>&1 | sed 's/^/   /'

echo
echo "done. log out, pick the Sway session, log back in."
echo "inside sway: \$mod+slash = cheatsheet · \$mod+t = theme picker"
