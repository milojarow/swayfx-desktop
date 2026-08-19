#!/usr/bin/env bash
# ── Palette Theming ───────────────────────────────────────────────────────────
# Role:     Generates ~/.config/waybar/theme.css from the active sway theme.
#           Reads ~/.config/sway/definitions.d/theme.conf, resolves
#           $background-color, $text-color, and $accent-color (supports one
#           level of variable indirection), and emits @define-color rules.
#           Called by theme-selector.sh on every theme switch.
# Files:    theme-waybar.sh
#           ~/.config/sway/definitions.d/theme.conf  (active theme symlink, input)
#           ~/.config/waybar/theme.css               (auto-generated CSS, output)
# Programs: grep
# Storage:  ~/.config/waybar/theme.css — overwritten on every theme switch
# Man:      man palette-theming
# ─────────────────────────────────────────────────────────────────────────────
set -u

# Paths
DEFINITIONS_DIR="$HOME/.config/sway/definitions.d"
CURRENT_THEME_LINK="$DEFINITIONS_DIR/theme.conf"
WAYBAR_CSS_DIR="$HOME/.config/waybar"
WAYBAR_THEME_CSS="$WAYBAR_CSS_DIR/theme.css"

# Get theme colors from the current theme
generate_theme_css() {
    # Only proceed if theme exists
    if [ ! -L "$CURRENT_THEME_LINK" ]; then
        echo "No theme currently set"
        return 1
    fi
    
    # Get the current theme
    theme_path=$(readlink -f "$CURRENT_THEME_LINK")
    theme_name=$(echo "$theme_path" | grep -o "[^/]\+/theme.conf" | cut -d/ -f1)
    
    # Resolve a sway variable to its hex color value (handles one level of indirection)
    # e.g. "background-color" → finds "set $background-color $color0" → finds "set $color0 #1a1b26" → "#1a1b26"
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

    # Fall back to defaults if resolution failed
    background_color="${background_color:-#1c1c1c}"
    text_color="${text_color:-#ffffff}"
    accent_color="${accent_color:-#1a5fb4}"
    
    # Generate CSS with theme variables
    cat > "$WAYBAR_THEME_CSS" << EOF
/* Auto-generated theme variables for Waybar */
/* Theme: $theme_name */

@define-color theme_base_color ${background_color};
@define-color theme_text_color ${text_color};
@define-color theme_bg_color ${background_color};
@define-color theme_selected_bg_color ${accent_color};
@define-color warning_color #f57900;
@define-color error_color #cc0000;
@define-color success_color #73d216;
@define-color background_color ${background_color};
@define-color wm_icon_bg ${text_color};
EOF
    
    echo "Generated theme CSS for Waybar based on theme: $theme_name"
}

# Main
generate_theme_css
