#!/usr/bin/env bash
# ── Palette Theming — Runtime applier (no swaymsg reload) ────────────────────
# Role:     Replicates everything that 90-enable-theme.conf does (exec_always
#           inside sway config that requires `swaymsg reload`), but invoked
#           directly with resolved values via swaymsg IPC. This avoids the full
#           sway reload which destroys/recreates the layer-shell that waybar
#           rides on — that reload made the bar visually disappear for ~3 s on
#           every theme change.
# Usage:    theme-apply-runtime.sh <path-to-theme.conf>
# Files:    theme-apply-runtime.sh
#           ~/.config/sway/themes/<name>/theme.conf   (input)
#           ~/.config/sway/scripts/enable-gtk-theme.sh
#           ~/.config/sway/scripts/fontconfig.sh
# Programs: bash >=4, gsettings, swaymsg, grep
# ─────────────────────────────────────────────────────────────────────────────
set -u

theme_file="${1:-}"
if [ -z "$theme_file" ] || [ ! -f "$theme_file" ]; then
    echo "Usage: $0 <path-to-theme.conf>" >&2
    exit 2
fi

# Parse every `set $varname value` line into an associative array.
declare -A VARS
while IFS= read -r line; do
    if [[ "$line" =~ ^set[[:space:]]+\$([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
        # Trim trailing whitespace from the value.
        val="${BASH_REMATCH[2]}"
        val="${val%"${val##*[![:space:]]}"}"
        VARS["${BASH_REMATCH[1]}"]="$val"
    fi
done < "$theme_file"

# Pull commonly-used theme vars out of the array.
gtk_theme="${VARS[gtk-theme]:-}"
icon_theme="${VARS[icon-theme]:-}"
cursor_theme="${VARS[cursor-theme]:-}"
gui_font="${VARS[gui-font]:-}"
term_font="${VARS[term-font]:-}"
color_scheme="${VARS[gtk-color-scheme]:-}"

# ── GTK theme + gsettings (replica of 90-enable-theme.conf) ──────────────────
[ -n "$gtk_theme" ]    && "$HOME/.config/sway/scripts/enable-gtk-theme.sh" "$gtk_theme" >/dev/null 2>&1 || true
[ -n "$icon_theme" ]   && gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" 2>/dev/null
[ -n "$cursor_theme" ] && gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme" 2>/dev/null
[ -n "$gui_font" ]     && gsettings set org.gnome.desktop.interface font-name "$gui_font" 2>/dev/null
[ -n "$term_font" ]    && gsettings set org.gnome.desktop.interface monospace-font-name "$term_font" 2>/dev/null
if [ -n "$color_scheme" ]; then
    gsettings set org.freedesktop.appearance color-scheme "$color_scheme" 2>/dev/null
    gsettings set org.gnome.desktop.interface color-scheme "$color_scheme" 2>/dev/null
fi
[ -n "$term_font" ]    && "$HOME/.config/sway/scripts/fontconfig.sh" "monospace" "$term_font" >/dev/null 2>&1 || true

# Kvantum theme is already synced via sed on ~/.config/Kvantum/kvantum.kvconfig
# in apply_theme() FASE 0; calling kvantummanager here would be redundant.

# ── Sway client.* borders via IPC (replaces `swaymsg reload`) ────────────────
# Read each `client.*` line, resolve `$varname` tokens to their hex values,
# then send the whole command as one swaymsg invocation. This is the bit that
# used to require full reload — sending `client.focused #aaa #bbb ...` via IPC
# updates ALL live windows without disturbing the layer-shell.
while IFS= read -r line; do
    [ -z "$line" ] && continue
    resolved=""
    for token in $line; do
        if [[ "$token" == \$* ]]; then
            val="${VARS[${token:1}]:-}"
            resolved+="$val "
        else
            resolved+="$token "
        fi
    done
    swaymsg "${resolved% }" >/dev/null 2>&1 || true
done < <(grep '^client\.' "$theme_file")

# ── wob (on-screen volume/brightness bar) refresh ────────────────────────────
# wob.sh writes ~/.config/wob.ini from its args and respawns the daemon. It
# used to be re-invoked by sway's `exec_always $onscreen_bar --refresh` when
# `swaymsg reload` ran — removing the reload from the pipeline broke that.
# Replicate it here: resolve $accent-color and $background-color (2-level
# indirection: $accent-color → $color12 → #hex) and call wob.sh --refresh.
resolve_color() {
    local v="${VARS[$1]:-}"
    [[ "$v" == \$* ]] && v="${VARS[${v:1}]:-}"
    echo "$v"
}
accent_hex=$(resolve_color "accent-color")
bg_hex=$(resolve_color "background-color")
if [ -n "$accent_hex" ] && [ -n "$bg_hex" ] && [ -x "$HOME/.config/sway/scripts/wob.sh" ]; then
    "$HOME/.config/sway/scripts/wob.sh" "$accent_hex" "$bg_hex" --refresh >/dev/null 2>&1 || true
fi
