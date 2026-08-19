#!/bin/bash
# ── USB Management ────────────────────────────────────────────────────────────
# Role:     Opens a mounted USB partition in the file manager via xdg-open;
#           shows rofi picker if multiple devices are mounted
# Files:    usb-monitor.sh · usb-monitor-wrapper.sh
#           usb-action-mount.sh · usb-action-unmount.sh · usb-action-eject.sh
#           usb-action-open.sh · usb-action-refresh.sh
#           ~/.config/rofi/themes/usb-manager.rasi   (picker UI theme)
#           ~/.config/waybar/usb-menu.xml             (right-click GTK menu)
#           ~/.config/waybar/config.jsonc             (custom/usb module)
# Programs: lsblk  xdg-open  rofi  notify-send
# Trigger:  waybar right-click → usb-menu.xml → "open" action
# ─────────────────────────────────────────────────────────────────────────────

# Function to get USB devices
get_usb_devices() {
    while IFS= read -r line; do
        device=$(echo "$line" | awk '{print $1}')
        rm=$(echo "$line" | awk '{print $2}')
        type=$(echo "$line" | awk '{print $3}')

        [[ "$rm" != "1" || "$type" != "part" ]] && continue

        hotplug=$(lsblk -ndo HOTPLUG "$device" 2>/dev/null)
        [[ "$hotplug" != "1" ]] && continue

        mountpoint=$(lsblk -ndo MOUNTPOINT "$device" 2>/dev/null)
        label=$(lsblk -ndo LABEL "$device" 2>/dev/null)

        echo "$device|$mountpoint|$label"
    done < <(lsblk -nlo NAME,RM,TYPE -p)
}

# Function to show notification
notify() {
    notify-send -u normal "USB Manager" "$1"
}

# Main logic
main() {
    mapfile -t usb_devices < <(get_usb_devices)

    # Filter only mounted devices
    mounted_devices=()
    for device_info in "${usb_devices[@]}"; do
        IFS='|' read -r device mountpoint label <<< "$device_info"
        [ -n "$mountpoint" ] && mounted_devices+=("$device_info")
    done

    if [ "${#mounted_devices[@]}" -eq 0 ]; then
        notify "No mounted USB devices found"
        exit 0
    fi

    # If only one mounted USB, open it
    if [ "${#mounted_devices[@]}" -eq 1 ]; then
        IFS='|' read -r device mountpoint label <<< "${mounted_devices[0]}"
        if [ -d "$mountpoint" ]; then
            xdg-open "$mountpoint" &
            notify "Opening ${label:-$(basename "$device")} in file manager"
        else
            notify "Mount point not found: $mountpoint"
        fi
        exit 0
    fi

    # Multiple mounted USBs - show selector using rofi
    menu_items=()
    for device_info in "${mounted_devices[@]}"; do
        IFS='|' read -r device mountpoint label <<< "$device_info"
        device_name=$(basename "$device")
        display_label="${label:-$device_name}"
        menu_items+=("$display_label ($mountpoint)|$mountpoint|$device")
    done

    selection=$(printf '%s\n' "${menu_items[@]}" | rofi -dmenu -i \
        -theme "$HOME/.config/rofi/themes/usb-manager.rasi" \
        -p "Select USB to open" \
        -mesg "Choose which USB to open in file manager" \
        -no-custom | cut -d'|' -f2)

    if [ -n "$selection" ] && [ -d "$selection" ]; then
        xdg-open "$selection" &
        notify "Opening $selection in file manager"
    fi
}

main
