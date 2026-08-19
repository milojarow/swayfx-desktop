#!/usr/bin/env bash
# ── Palette Theming — Cache Regenerator ───────────────────────────────────────
# Role:     Pre-generates per-theme cached outputs in ~/.cache/sway-theming/
#           so that apply_theme() only swaps symlinks (atomic, ~5ms) instead of
#           regenerating CSS/SCSS on every theme switch (~150ms).
#           For each theme it creates 4 cached output files mirroring what the
#           per-app theme generators (theme-waybar.sh, theme-rofi.sh,
#           theme-wofi.sh, theme-eww.sh) would produce.
# Usage:    theme-cache-regen.sh <theme-name>   # regen one
#           theme-cache-regen.sh all            # regen all themes
# Files:    theme-cache-regen.sh
#           ~/.config/sway/themes/<name>/theme.conf   (input, per theme)
#           ~/.cache/sway-theming/<name>/             (output dir)
#             ├── waybar.theme.css
#             ├── rofi.cachyos.rasi
#             ├── wofi.style.css
#             └── eww.theme.scss
# Programs: grep, head, cat, mkdir, basename
# ─────────────────────────────────────────────────────────────────────────────
set -eu

THEMES_DIR="$HOME/.config/sway/themes"
CACHE_DIR="$HOME/.cache/sway-theming"

# Resolve a sway variable to its hex color value (one level of indirection).
# e.g. "background-color" → finds "set $background-color $color0" → "set $color0 #1a1b26" → "#1a1b26"
resolve_var() {
    local path="$1" varname="$2" value
    value=$(grep -oP "set \\\$$varname\s+\K\S+" "$path" 2>/dev/null | head -1)
    if [[ "$value" == "#"* ]]; then
        echo "$value"
    elif [[ "$value" == '$'* ]]; then
        local ref="${value#$}"
        grep -oP "set \\\$$ref\s+\K\S+" "$path" 2>/dev/null | head -1
    fi
}

regen_one() {
    local theme="$1"
    local theme_path="$THEMES_DIR/$theme/theme.conf"
    if [ ! -f "$theme_path" ]; then
        echo "ERROR: $theme_path not found" >&2
        return 1
    fi

    local out="$CACHE_DIR/$theme"
    mkdir -p "$out"

    local bg fg accent selection color2 color11
    bg=$(resolve_var "$theme_path" "background-color")
    fg=$(resolve_var "$theme_path" "text-color")
    accent=$(resolve_var "$theme_path" "accent-color")
    selection=$(resolve_var "$theme_path" "selection-color")
    color2=$(resolve_var "$theme_path" "color2")
    color11=$(resolve_var "$theme_path" "color11")

    bg="${bg:-#1c1c1c}"
    fg="${fg:-#ffffff}"
    accent="${accent:-#1a5fb4}"
    selection="${selection:-#303030}"
    color2="${color2:-#3B758C}"
    color11="${color11:-#98971a}"

    # Derive 3 accent-relative colors via HSL hue rotation. GTK CSS has no
    # hsl(from var() h s l) or color-mix() with hue rotation, so the math
    # happens here at cache-gen time and the results are emitted as static
    # @define-color values. When the active theme changes, the cache for that
    # theme has its own derived values — so the "relative" intent (color follows
    # the accent) holds across the whole palette-theming system.
    #   theme_accent_complement → accent rotated 180° (max contrast against accent)
    #   theme_accent_triad_a    → accent rotated 120° (harmonic triad, leg A)
    #   theme_accent_triad_b    → accent rotated 240° (harmonic triad, leg B)
    local derived
    derived=$(python3 -c "
import colorsys, sys
h_in = '${accent#\#}'
r = int(h_in[0:2], 16) / 255
g = int(h_in[2:4], 16) / 255
b = int(h_in[4:6], 16) / 255
H, L, S = colorsys.rgb_to_hls(r, g, b)
def rot(deg):
    nh = (H + deg/360.0) % 1.0
    rr, gg, bb = colorsys.hls_to_rgb(nh, L, S)
    return '#{:02x}{:02x}{:02x}'.format(int(round(rr*255)), int(round(gg*255)), int(round(bb*255)))
print(rot(180), rot(120), rot(240))
")
    local accent_complement accent_triad_a accent_triad_b
    read accent_complement accent_triad_a accent_triad_b <<< "$derived"

    # waybar theme.css (mirrors theme-waybar.sh output)
    cat > "$out/waybar.theme.css" << EOF
/* Auto-generated cached theme — do not edit manually */
/* Theme: $theme */

@define-color theme_base_color ${bg};
@define-color theme_text_color ${fg};
@define-color theme_bg_color ${bg};
@define-color theme_selected_bg_color ${accent};
@define-color theme_accent_complement ${accent_complement};
@define-color theme_accent_triad_a ${accent_triad_a};
@define-color theme_accent_triad_b ${accent_triad_b};
@define-color warning_color #f57900;
@define-color error_color #cc0000;
@define-color success_color #73d216;
@define-color background_color ${bg};
@define-color wm_icon_bg ${fg};
EOF

    # rofi cachyos.rasi (mirrors theme-rofi.sh output)
    cat > "$out/rofi.cachyos.rasi" << EOF
/* Auto-generated cached theme — do not edit manually */
/* Theme: $theme — see man palette-theming */
* {
    background-color: ${bg};
    text-color: ${fg};
    accent-color: ${accent};
    selected-bg: ${selection};
}
EOF

    # wofi style.css (mirrors theme-wofi.sh output)
    cat > "$out/wofi.style.css" << EOF
/* Auto-generated cached theme — do not edit manually.
 * Theme: $theme — Part of the Palette Theming system. */

window {
    margin: 0px;
    border: 2px solid ${accent};
    background-color: ${bg};
    border-radius: 5px;
}

#input {
    margin: 5px;
    border: 2px solid ${accent};
    border-radius: 5px;
    background-color: ${selection};
    color: ${fg};
    font-size: 18px;
}

#inner-box {
    margin: 5px;
    border: none;
    background-color: transparent;
}

#outer-box {
    margin: 5px;
    border: none;
    background-color: transparent;
}

#scroll {
    margin: 0px;
    border: none;
}

#text {
    margin: 5px;
    color: ${fg};
    font-size: 16px;
}

#entry {
    padding: 5px;
    border-radius: 5px;
}

#entry:selected {
    background-color: ${selection};
    border-radius: 5px;
}

#entry:selected #text {
    color: ${accent};
    font-weight: bold;
}

#img {
    margin-right: 10px;
}
EOF

    # eww theme.scss (mirrors theme-eww.sh output — colors only; no `eww reload`)
    cat > "$out/eww.theme.scss" << EOF
// Auto-generated cached theme — do not edit manually.
// Theme: $theme

\$theme-bg:        ${bg};
\$theme-fg:        ${fg};
\$theme-accent:    ${accent};
\$theme-selection: ${selection};
\$color2:          ${color2};
\$color11:         ${color11};
EOF
}

main() {
    local arg="${1:-}"
    if [ -z "$arg" ]; then
        echo "Usage: $0 <theme-name> | $0 all" >&2
        exit 2
    fi

    mkdir -p "$CACHE_DIR"

    if [ "$arg" = "all" ]; then
        local count=0 failed=0
        for d in "$THEMES_DIR"/*/; do
            local theme
            theme=$(basename "$d")
            if regen_one "$theme"; then
                count=$((count + 1))
            else
                failed=$((failed + 1))
            fi
        done
        echo "Regenerated $count theme cache(s). Failed: $failed"
    else
        regen_one "$arg" && echo "Regenerated cache for: $arg"
    fi
}

main "$@"
