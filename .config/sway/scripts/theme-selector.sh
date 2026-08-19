#!/usr/bin/env bash
# ── Palette Theming ───────────────────────────────────────────────────────────
# Role:     Main orchestrator for palette theme switching.
#           mode=menu: opens a wofi list, then on selection: symlinks the sway
#           theme.conf, copies foot-theme.ini, calls theme-apply-foot.sh to
#           push OSC colors to running terminals, reloads sway, regenerates
#           waybar CSS, and signals waybar.
#           mode=status: outputs a JSON icon for the waybar theme module.
# Files:    theme-selector.sh · theme-apply-foot.sh · theme-waybar.sh
#           theme-toggle.sh · theme-rofi.sh
#           ~/.config/sway/themes/<name>/theme.conf      (palette source)
#           ~/.config/sway/themes/<name>/foot-theme.ini  (terminal palette)
#           ~/.config/sway/definitions.d/theme.conf      (active sway theme, symlink)
#           ~/.config/foot/foot-theme.ini                (active foot theme, symlink)
#           ~/.config/sway/templates/foot.ini            (shared foot template)
#           ~/.config/waybar/theme.css                   (auto-generated CSS)
#           ~/.config/rofi/cachyos.rasi                  (auto-generated rofi colors)
# Programs: wofi  swaymsg  pkill
# Signals:  SIGUSR2     → waybar (CSS reload)
#           SIGRTMIN+17 → waybar (theme icon refresh)
# Man:      man palette-theming
# ─────────────────────────────────────────────────────────────────────────────
set -eu

# Paths
THEMES_DIR="$HOME/.config/sway/themes"
DEFINITIONS_DIR="$HOME/.config/sway/definitions.d"
CURRENT_THEME_LINK="$DEFINITIONS_DIR/theme.conf"
CURRENT_FOOT_THEME_LINK="$HOME/.config/foot/foot-theme.ini"

# Create directories if they don't exist
mkdir -p "$DEFINITIONS_DIR"
mkdir -p "$(dirname "$CURRENT_FOOT_THEME_LINK")"

# Get list of themes
get_themes() {
    find "$THEMES_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
}

# Apply selected theme — 3-phase pipeline optimized for reaction time:
#   FASE 0 (~5ms, atomic): symlinks (theme.conf, foot, 4 pre-cached outputs)
#                          + qt6ct sync (icon_theme + color_scheme_path).
#   FASE 1 (~50-100ms blocking): foot OSC + eww reload in parallel + waybar/mako signals.
#                                Visible apps catch up here.
#   FASE 2 (background, no wait): swaymsg reload (propagates GTK/Kvantum via
#                                 90-enable-theme.conf exec_always), terminal
#                                 configs for alacritty/ghostty/wezterm, and
#                                 papirus-folders (~800ms heaviest task).
# Total perceived: ~50-150ms. Heavy work continues in background after return.
# See ~/.claude/plans/fancy-plotting-snowflake.md for the full design rationale.
apply_theme() {
    local theme="$1"
    local theme_file="$THEMES_DIR/$theme/theme.conf"
    local foot_theme_file="$THEMES_DIR/$theme/foot-theme.ini"
    local cache_dir="$HOME/.cache/sway-theming/$theme"

    if [ ! -f "$theme_file" ]; then
        echo "Error: Theme file not found at $theme_file" >&2
        exit 1
    fi

    # Lazy-regenerate the cache the first time a theme is used (or after the
    # user clears the dir). theme-cache-regen.sh is idempotent.
    if [ ! -d "$cache_dir" ]; then
        ~/.config/sway/scripts/theme-cache-regen.sh "$theme" >/dev/null 2>&1 || true
    fi

    # ═══ FASE 0 — atomic config swaps (~5ms) ═════════════════════════════════
    # After this point every consumer app sees the new theme on disk; the only
    # thing left is signaling them so they actually re-read.
    ln -sf "$theme_file" "$CURRENT_THEME_LINK"
    if [ -f "$foot_theme_file" ]; then
        ln -sf "$foot_theme_file" "$CURRENT_FOOT_THEME_LINK"
    fi
    mkdir -p "$HOME/.config/waybar" "$HOME/.config/rofi" "$HOME/.config/wofi" "$HOME/.config/eww/styles"
    ln -sf "$cache_dir/waybar.theme.css"  "$HOME/.config/waybar/theme.css"
    ln -sf "$cache_dir/rofi.cachyos.rasi" "$HOME/.config/rofi/cachyos.rasi"
    ln -sf "$cache_dir/wofi.style.css"    "$HOME/.config/wofi/style.css"
    ln -sf "$cache_dir/eww.theme.scss"    "$HOME/.config/eww/styles/theme.scss"

    # Sync qt6ct so Qt apps respect the theme. Pre-fix the file had
    # `color_scheme_path=darker.conf` hardcoded, ignoring everything else.
    if [ -f "$HOME/.config/qt6ct/qt6ct.conf" ]; then
        local icon_theme qt6ct_scheme
        icon_theme=$(grep '^set \$icon-theme' "$theme_file" | awk '{print $3}')
        [ -n "$icon_theme" ] && sed -i "s|^icon_theme=.*|icon_theme=${icon_theme}|" "$HOME/.config/qt6ct/qt6ct.conf"
        if is_light_theme "$theme"; then
            qt6ct_scheme="/usr/share/qt6ct/colors/airy.conf"
        else
            qt6ct_scheme="/usr/share/qt6ct/colors/darker.conf"
        fi
        sed -i "s|^color_scheme_path=.*|color_scheme_path=${qt6ct_scheme}|" "$HOME/.config/qt6ct/qt6ct.conf"
    fi

    # Sync Kvantum (QT_STYLE_OVERRIDE=kvantum on this system → Kvantum dictates
    # widget palette, not qt6ct's color_scheme_path). Without this, Kvantum
    # would stay on whatever theme was last set manually.
    local kvantum_theme
    kvantum_theme=$(grep '^set \$kvantum-theme' "$theme_file" | awk '{print $3}')
    if [ -n "$kvantum_theme" ] && [ -f "$HOME/.config/Kvantum/kvantum.kvconfig" ]; then
        sed -i "s|^theme=.*|theme=${kvantum_theme}|" "$HOME/.config/Kvantum/kvantum.kvconfig"
    fi

    # Sync gtk-application-prefer-dark-theme flag in gtk-3.0/gtk-4.0 settings.ini.
    # Without this, the flag is hardcoded and overrides gsettings color-scheme,
    # making every new GTK/Qt-portal window dark regardless of the active theme.
    # Single source of truth: sync-gtk-dark-flag.sh is also called by the
    # boot/reload path (90-enable-theme.conf) so both paths can't drift.
    if is_light_theme "$theme"; then
        ~/.config/sway/scripts/sync-gtk-dark-flag.sh prefer-light
    else
        ~/.config/sway/scripts/sync-gtk-dark-flag.sh prefer-dark
    fi

    # ═══ FASE 1 — fast paths in parallel (~50-100ms blocking) ════════════════
    # foot OSC (recolor running terminals) + eww reload run in parallel; we
    # wait on these because they are the visible "instant" updates.
    # waybar/mako signals are sync (instant, no wait needed).
    local pids=()
    if [ -f "$foot_theme_file" ]; then
        ~/.config/sway/scripts/theme-apply-foot.sh "$foot_theme_file" >/dev/null 2>&1 &
        pids+=($!)
    fi
    "$HOME/.cargo/bin/eww" reload >/dev/null 2>&1 &
    pids+=($!)
    pkill -SIGUSR2 waybar  2>/dev/null || true   # waybar CSS reload (fallback bar)
    pkill -RTMIN+17 waybar 2>/dev/null || true   # waybar theme-icon refresh
    pkill -SIGHUP   mako   2>/dev/null || true   # mako notification daemon reload

    # ═══ FASE 2 — heavy work in background (does NOT block return) ═══════════
    # theme-apply-runtime.sh replicates what `swaymsg reload` used to do (it
    # triggered 90-enable-theme.conf exec_always → gsettings, enable-gtk-theme,
    # client.* borders) but invokes everything directly via IPC. Avoiding the
    # full reload keeps the waybar layer-shell alive — `swaymsg reload`
    # destroyed and recreated the layer, leaving the bar invisible for ~3s.
    ~/.config/sway/scripts/theme-apply-runtime.sh "$theme_file" >/dev/null 2>&1 &
    if [ -f "$foot_theme_file" ]; then
        ~/.config/sway/scripts/apply-theme-terminals.sh "$foot_theme_file" >/dev/null 2>&1 &
    fi

    # Papirus folder colors — heaviest task (~800ms cache rebuild). Maps each
    # theme to a Papirus color: catppuccin → `cat-<flavor>-<accent>`, others via
    # case statement. Fully backgrounded; folders update silently after return.
    {
        local papirus_color=""
        if [[ "$theme" =~ ^catppuccin-(latte|frappe|macchiato|mocha)(-(.+))?$ ]]; then
            local flavor="${BASH_REMATCH[1]}"
            local accent="${BASH_REMATCH[3]:-blue}"
            papirus_color="cat-${flavor}-${accent}"
        else
            case "$theme" in
                adwaita-light)                       papirus_color="adwaita" ;;
                high-contrast-light)                 papirus_color="black"   ;;
                tokyo-night|tokyo-night-light)       papirus_color="blue"    ;;
                matcha-light-sea|matcha-green)       papirus_color="teal"    ;;
                matcha-light-azul|matcha-blue)       papirus_color="blue"    ;;
                matcha-light-aliz|matcha-red)        papirus_color="red"     ;;
                matcha-light-pueril|matcha-leaf)     papirus_color="green"   ;;
                dracula)                             papirus_color="violet"  ;;
                gruvbox-dark)                        papirus_color="orange"  ;;
                nordic-bluish-accent)                papirus_color="nordic"  ;;
                *)                                   papirus_color=""        ;;
            esac
        fi
        if [ -n "$papirus_color" ]; then
            if is_light_theme "$theme"; then
                papirus-folders --color "$papirus_color" --theme Papirus-Light 2>/dev/null || true
            else
                papirus-folders --color "$papirus_color" --theme Papirus-Dark 2>/dev/null || true
            fi
        fi
    } &

    # Wait only on FASE 1 critical paths so visible apps are settled before
    # apply_theme returns. set -e is active globally; `|| true` keeps the
    # script alive even if a backgrounded pid already exited (race-safe).
    wait "${pids[@]}" 2>/dev/null || true
}

# Initialize theme if not exists, or if any of the runtime links are missing.
# Runtime symlinks (e.g., the foot theme) are gitignored, so a fresh clone
# arrives with a tracked theme.conf symlink but no foot link — re-applying
# the current theme (or a default) repairs the inconsistent state.
initialize_theme() {
    if [ ! -e "$CURRENT_THEME_LINK" ] || [ ! -e "$CURRENT_FOOT_THEME_LINK" ]; then
        # If sway theme link exists, reuse its theme; otherwise pick a default.
        local theme=""
        if [ -L "$CURRENT_THEME_LINK" ]; then
            theme=$(readlink -f "$CURRENT_THEME_LINK" | grep -o "[^/]\+/theme.conf" | cut -d/ -f1)
        fi
        if [ -z "$theme" ]; then
            if [ -d "$THEMES_DIR/dracula" ]; then
                theme="dracula"
            else
                theme=$(get_themes | head -1)
            fi
        fi
        if [ -n "$theme" ]; then
            apply_theme "$theme"
        else
            echo "Error: No themes found"
            exit 1
        fi
    fi
}

# Get current theme
get_current_theme() {
    if [ -L "$CURRENT_THEME_LINK" ]; then
        theme_path=$(readlink -f "$CURRENT_THEME_LINK")
        echo "$theme_path" | grep -o "[^/]\+/theme.conf" | cut -d/ -f1
    else
        echo "No theme currently set"
    fi
}

# Determine if a theme is light or dark by reading its canonical gtk-color-scheme
# (more robust than guessing from the theme name).
is_light_theme() {
    grep -q 'gtk-color-scheme prefer-light' "$THEMES_DIR/$1/theme.conf"
}

# Display menu (rofi, 2 columns: light themes left, dark themes right) and handle selection
display_menu() {
    initialize_theme
    current=$(get_current_theme)

    # Classify themes by their canonical gtk-color-scheme.
    local light=() dark=() theme
    while IFS= read -r theme; do
        if is_light_theme "$theme"; then
            light+=("$theme")
        else
            dark+=("$theme")
        fi
    done < <(get_themes)

    # Column-major fill (rofi flow:vertical): the first $max entries fill the left
    # column (light), the next $max fill the right (dark). Pad the shorter list with
    # blank lines so each side stays pure. Blank picks are ignored by the guard below.
    local nlight=${#light[@]} ndark=${#dark[@]} i
    local max=$(( nlight > ndark ? nlight : ndark ))
    local entries=()
    for ((i=0; i<max; i++)); do entries+=("${light[i]:-}"); done
    for ((i=0; i<max; i++)); do entries+=("${dark[i]:-}"); done

    selected=$(printf '%s\n' "${entries[@]}" | rofi -dmenu \
        -p "tema (actual: $current)" \
        -mesg '☀  claros                              🌙  oscuros' \
        -theme-str "listview { columns: 2; flow: vertical; lines: $max; fixed-columns: true; } window { width: 60%; }")

    if [ -n "$selected" ]; then
        apply_theme "$selected"
    fi
}

# Status output for Waybar
status_output() {
    initialize_theme
    current=$(get_current_theme)

    # Default icon that will always be visible (color palette icon)
    icon="󰏘"  # Color palette icon

    # Generic icon selection based on theme name patterns
    if is_light_theme "$current"; then
        icon=""  # Sun/light theme icon
    else
        icon=""  # Moon/dark theme icon
    fi

    # Check for specific theme families to use more specific icons if possible
    if [[ "$current" =~ ^catppuccin- ]]; then
        icon=""  # Coffee cup icon for Catppuccin
    elif [[ "$current" =~ ^matcha- ]]; then
        icon="󰌪"  # Leaf icon for Matcha
    elif [[ "$current" == "dracula" ]]; then
        icon="󰭟"  # Bat icon for Dracula
    elif [[ "$current" =~ nordic ]]; then
        icon=""  # Snowflake icon for Nordic
    fi

    printf '{"alt":"%s","tooltip":"Current theme: %s\nClick to change theme","text":"%s"}\n' \
        "$current" "$current" "$icon"
}

# Main
case "${1:-}" in
    "menu")
        display_menu
        ;;
    "status")
        status_output
        ;;
    *)
        echo "Usage: $0 {menu|status}"
        exit 1
        ;;
esac
