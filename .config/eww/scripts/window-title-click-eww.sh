#!/usr/bin/env bash
# feature: window-title
# role:    action
# Left-click handler for eww window title — flashes the app name for 3 seconds.
# Writes the app name to a file watched by window-title-flash-watch.sh (deflisten).
# Expiry is handled here via a background sleep+rm — no polling needed.

FLASH_FILE="/tmp/eww-window-title-flash-${USER}"

# If already flashing, dismiss immediately
if [ -f "$FLASH_FILE" ]; then
    rm -f "$FLASH_FILE"
    exit 0
fi

# Get app_id of focused window
app_id=$(swaymsg -t get_tree | jq -r '
    [.. | select(.focused? == true and .pid?)] | first // empty |
    (.app_id // .window_properties.class // "")
')
[ -z "$app_id" ] && exit 0

get_app_name() {
    case "${1,,}" in
        *footclient*|*foot*)   echo "Foot terminal" ;;
        *ghostty*)             echo "Ghostty terminal" ;;
        *alacritty*)           echo "Alacritty" ;;
        *kitty*)               echo "Kitty terminal" ;;
        *firefox*|*librewolf*) echo "Firefox" ;;
        *brave*)               echo "Brave Browser" ;;
        *chromium*)            echo "Chromium" ;;
        *code*|*vscodium*)     echo "VS Code" ;;
        *vlc*)                 echo "VLC" ;;
        *obsidian*)            echo "Obsidian" ;;
        *telegram*)            echo "Telegram" ;;
        *discord*)             echo "Discord" ;;
        *mpv*)                 echo "mpv" ;;
        *)                     echo "$1" ;;
    esac
}

app_name=$(get_app_name "$app_id")
echo "$app_name" > "$FLASH_FILE"
# Expire after 3 seconds — the deflisten reacts to the DELETE event
(sleep 3; rm -f "$FLASH_FILE") &
