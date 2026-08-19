#!/usr/bin/env bash

WALLPAPER_DIR="$(xdg-user-dir PICTURES)/wallpapers"
STATE_FILE="$HOME/.cache/eww/current-wallpaper"

# Verificar que el directorio existe y tiene imágenes
if [[ ! -d "$WALLPAPER_DIR" ]] || [[ -z "$(ls -A "$WALLPAPER_DIR"/*.{jpg,jpeg,png,webp} 2>/dev/null)" ]]; then
    echo "No wallpapers found in $WALLPAPER_DIR"
    exit 1
fi

WALLPAPER=""

# Si el widget de eww guardó un wallpaper específico, usar ese.
if [[ -f "$STATE_FILE" ]]; then
    SAVED=$(cat "$STATE_FILE" 2>/dev/null)
    if [[ -n "$SAVED" ]] && [[ -f "$SAVED" ]]; then
        WALLPAPER="$SAVED"
    fi
fi

# Fallback: random
if [[ -z "$WALLPAPER" ]]; then
    WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | shuf -n 1)
fi

# Aplicar wallpaper
swaymsg "output * bg \"$WALLPAPER\" fill"

echo "Applied wallpaper: $WALLPAPER"
