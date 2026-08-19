#!/usr/bin/env bash
# ── Palette Theming ───────────────────────────────────────────────────────────
# Role:     Generates ~/.config/rofi/cachyos.rasi from the active sway theme.
#           Reads ~/.config/sway/definitions.d/theme.conf, resolves
#           $background-color, $text-color, $accent-color, and $selection-color
#           (supports one level of variable indirection), and writes rofi
#           color variable definitions used by config.rasi via @import "cachyos".
#           Called by theme-selector.sh on every theme switch, and by
#           $update_rofi_theme (autostart) on every sway reload.
# Files:    theme-rofi.sh
#           ~/.config/sway/definitions.d/theme.conf  (active theme symlink, input)
#           ~/.config/rofi/cachyos.rasi               (auto-generated rasi vars, output)
# Programs: grep
# Storage:  ~/.config/rofi/cachyos.rasi — overwritten on every theme switch
# Man:      man palette-theming
# ─────────────────────────────────────────────────────────────────────────────
set -u

CURRENT_THEME_LINK="$HOME/.config/sway/definitions.d/theme.conf"
ROFI_THEME_FILE="$HOME/.config/rofi/cachyos.rasi"

generate_rofi_theme() {
    if [ ! -L "$CURRENT_THEME_LINK" ]; then
        echo "No theme currently set" >&2
        return 1
    fi

    theme_path=$(readlink -f "$CURRENT_THEME_LINK")
    theme_name=$(echo "$theme_path" | grep -o "[^/]\+/theme.conf" | cut -d/ -f1)

    # Resolve a sway variable to its hex color value (one level of indirection)
    resolve_var() {
        local path="$1" varname="$2"
        local value
        value=$(grep -oP "set \\\$$varname\s+\K\S+" "$path" | head -1)
        if [[ "$value" == "#"* ]]; then
            echo "$value"
        elif [[ "$value" == '$'* ]]; then
            resolve_var "$path" "${value#$}"
        fi
    }

    background_color=$(resolve_var "$theme_path" "background-color")
    text_color=$(resolve_var "$theme_path" "text-color")
    accent_color=$(resolve_var "$theme_path" "accent-color")
    selected_bg=$(resolve_var "$theme_path" "selection-color")

    background_color="${background_color:-#1c1c1c}"
    text_color="${text_color:-#ffffff}"
    accent_color="${accent_color:-#1a5fb4}"
    selected_bg="${selected_bg:-#303030}"

    mkdir -p "$(dirname "$ROFI_THEME_FILE")"
    cat > "$ROFI_THEME_FILE" << EOF
/* Auto-generated rofi color variables — do not edit */
/* Theme: $theme_name — see man palette-theming */
* {
    background-color: ${background_color};
    text-color: ${text_color};
    accent-color: ${accent_color};
    selected-bg: ${selected_bg};
}
EOF
}

generate_rofi_theme
