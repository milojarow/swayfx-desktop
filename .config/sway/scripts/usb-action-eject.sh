#!/bin/bash
# ── USB Management ────────────────────────────────────────────────────────────
# Role:     Safely removes USB disks — unmounts all partitions then powers off
#           the physical disk via udisksctl; rofi picker if multiple devices
# Files:    usb-monitor.sh · usb-monitor-wrapper.sh
#           usb-action-mount.sh · usb-action-unmount.sh · usb-action-eject.sh
#           usb-action-open.sh · usb-action-refresh.sh
#           ~/.config/rofi/themes/usb-manager.rasi   (picker UI theme)
#           ~/.config/waybar/usb-menu.xml             (right-click GTK menu)
#           ~/.config/waybar/config.jsonc             (custom/usb module)
# Programs: lsblk  udisksctl  rofi  notify-send  pkill
# Trigger:  waybar right-click → usb-menu.xml → "eject" action
# Signal:   pkill -RTMIN+15 waybar  (refreshes the module after ejecting)
# Note:     Operates on physical disks (not partitions) unlike mount/unmount
# ─────────────────────────────────────────────────────────────────────────────

# Returns physical USB disk info: device|label|size
get_usb_disks() {
    while IFS= read -r line; do
        device=$(echo "$line" | awk '{print $1}')
        rm=$(echo "$line" | awk '{print $2}')
        type=$(echo "$line" | awk '{print $3}')

        [[ "$rm" != "1" || "$type" != "disk" ]] && continue

        hotplug=$(lsblk -ndo HOTPLUG "$device" 2>/dev/null)
        [[ "$hotplug" != "1" ]] && continue

        model=$(lsblk -ndo MODEL "$device" 2>/dev/null | xargs)
        size=$(lsblk -ndo SIZE "$device" 2>/dev/null)
        label="${model:-$(basename "$device")}"
        echo "$device|$label|$size"
    done < <(lsblk -nlo NAME,RM,TYPE -p)
}

notify() {
    notify-send -u normal "USB Manager" "$1"
}

# Unmounts all mounted partitions of a disk, then powers it off
eject_disk() {
    local disk="$1"
    local label="$2"

    while IFS= read -r line; do
        part=$(echo "$line" | awk '{print $1}')
        type=$(echo "$line" | awk '{print $2}')
        [[ "$type" != "part" ]] && continue

        mountpoint=$(lsblk -ndo MOUNTPOINT "$part" 2>/dev/null)
        if [ -n "$mountpoint" ]; then
            if ! udisksctl unmount -b "$part" 2>/dev/null; then
                notify "Failed to unmount $part before ejecting $label"
                return 1
            fi
        fi
    done < <(lsblk -nlo NAME,TYPE -p "$disk")

    if udisksctl power-off -b "$disk" 2>/dev/null; then
        notify "Successfully ejected $label"
        pkill -RTMIN+15 waybar
        return 0
    else
        notify "Failed to eject $label"
        return 1
    fi
}

main() {
    mapfile -t usb_disks < <(get_usb_disks)

    if [ "${#usb_disks[@]}" -eq 0 ]; then
        notify "No USB devices found"
        exit 0
    fi

    # Single disk: eject directly
    if [ "${#usb_disks[@]}" -eq 1 ]; then
        IFS='|' read -r disk label size <<< "${usb_disks[0]}"
        eject_disk "$disk" "$label"
        exit 0
    fi

    # Multiple disks: let the user pick
    menu_items=("All USB devices|all")
    menu_items+=("---SEPARATOR---|separator")

    for disk_info in "${usb_disks[@]}"; do
        IFS='|' read -r disk label size <<< "$disk_info"
        menu_items+=("$label ($size)|single|$disk|$label")
    done

    selection=$(printf '%s\n' "${menu_items[@]}" | grep -v "SEPARATOR" | rofi -dmenu -i \
        -theme "$HOME/.config/rofi/themes/usb-manager.rasi" \
        -p "Eject USB" \
        -mesg "Select which USB to safely remove" \
        -no-custom)

    [ -z "$selection" ] && exit 0

    action=$(echo "$selection" | cut -d'|' -f2)

    if [ "$action" = "all" ]; then
        success_count=0
        for disk_info in "${usb_disks[@]}"; do
            IFS='|' read -r disk label size <<< "$disk_info"
            eject_disk "$disk" "$label" && success_count=$((success_count + 1))
        done
        notify "Ejected $success_count of ${#usb_disks[@]} USB(s)"
    elif [ "$action" = "single" ]; then
        disk=$(echo "$selection" | cut -d'|' -f3)
        label=$(echo "$selection" | cut -d'|' -f4)
        eject_disk "$disk" "$label"
    fi
}

main
