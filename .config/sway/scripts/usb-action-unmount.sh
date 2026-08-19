#!/bin/bash
# ── USB Management ────────────────────────────────────────────────────────────
# Role:     Unmounts mounted USB partitions via udisksctl; shows rofi picker
#           if multiple devices are available, auto-unmounts if only one
# Files:    usb-monitor.sh · usb-monitor-wrapper.sh
#           usb-action-mount.sh · usb-action-unmount.sh · usb-action-eject.sh
#           usb-action-open.sh · usb-action-refresh.sh
#           ~/.config/rofi/themes/usb-manager.rasi   (picker UI theme)
#           ~/.config/waybar/usb-menu.xml             (right-click GTK menu)
#           ~/.config/waybar/config.jsonc             (custom/usb module)
# Programs: lsblk  udisksctl  rofi  notify-send  pkill
# Trigger:  waybar right-click → usb-menu.xml → "unmount" action
# Signal:   pkill -RTMIN+15 waybar  (refreshes the module after unmounting)
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

# Function to unmount device
unmount_device() {
    local device="$1"
    local label="$2"

    if udisksctl unmount -b "$device" 2>/dev/null; then
        notify "Successfully unmounted ${label:-$(basename "$device")}"
        pkill -RTMIN+15 waybar
        return 0
    else
        notify "Failed to unmount ${label:-$(basename "$device")}"
        return 1
    fi
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

    # If only one mounted USB, unmount it
    if [ "${#mounted_devices[@]}" -eq 1 ]; then
        IFS='|' read -r device mountpoint label <<< "${mounted_devices[0]}"
        unmount_device "$device" "$label"
        exit 0
    fi

    # Multiple mounted USBs - ask which one or all
    menu_items=("All mounted USBs|all|")
    menu_items+=("---SEPARATOR---|separator|")

    for device_info in "${mounted_devices[@]}"; do
        IFS='|' read -r device mountpoint label <<< "$device_info"
        device_name=$(basename "$device")
        display_label="${label:-$device_name}"
        menu_items+=("$display_label ($mountpoint)|single|$device|$label")
    done

    selection=$(printf '%s\n' "${menu_items[@]}" | grep -v "SEPARATOR" | rofi -dmenu -i \
        -theme "$HOME/.config/rofi/themes/usb-manager.rasi" \
        -p "Unmount USB" \
        -mesg "Select which USB(s) to unmount" \
        -no-custom)

    [ -z "$selection" ] && exit 0

    action=$(echo "$selection" | cut -d'|' -f2)

    if [ "$action" = "all" ]; then
        # Unmount all
        success_count=0
        for device_info in "${mounted_devices[@]}"; do
            IFS='|' read -r device mountpoint label <<< "$device_info"
            if unmount_device "$device" "$label"; then
                success_count=$((success_count + 1))
            fi
        done
        notify "Unmounted $success_count of ${#mounted_devices[@]} USB(s)"
    elif [ "$action" = "single" ]; then
        device=$(echo "$selection" | cut -d'|' -f3)
        label=$(echo "$selection" | cut -d'|' -f4)
        unmount_device "$device" "$label"
    fi
}

main
