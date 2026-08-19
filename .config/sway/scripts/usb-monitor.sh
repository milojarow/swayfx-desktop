#!/bin/bash
# ── USB Management ────────────────────────────────────────────────────────────
# Role:     Detects connected USB storage devices and outputs JSON for waybar
# Files:    usb-monitor.sh · usb-monitor-wrapper.sh
#           usb-action-mount.sh · usb-action-unmount.sh · usb-action-eject.sh
#           usb-action-open.sh · usb-action-refresh.sh
#           ~/.config/rofi/themes/usb-manager.rasi   (picker UI theme)
#           ~/.config/waybar/usb-menu.xml             (right-click GTK menu)
#           ~/.config/waybar/config.jsonc             (custom/usb module)
# Programs: lsblk  udisksctl  rofi  notify-send  xdg-open  pkill
# Trigger:  waybar right-click → usb-menu.xml → menu-actions in config.jsonc
# Signal:   pkill -RTMIN+15 waybar  (refreshes the module after any action)
# ─────────────────────────────────────────────────────────────────────────────

# Glyphs
GLYPH_MOUNTED="󱊞"
GLYPH_UNMOUNTED="󱊟"

# Returns physical USB disk paths, one per line
get_usb_disks() {
    while IFS= read -r line; do
        device=$(echo "$line" | awk '{print $1}')
        rm=$(echo "$line" | awk '{print $2}')
        type=$(echo "$line" | awk '{print $3}')

        [[ "$rm" != "1" || "$type" != "disk" ]] && continue

        hotplug=$(lsblk -ndo HOTPLUG "$device" 2>/dev/null)
        [[ "$hotplug" != "1" ]] && continue

        echo "$device"
    done < <(lsblk -nlo NAME,RM,TYPE -p)
}

# Returns partition info for a given disk: part|mountpoint|fstype|label|size
get_disk_partitions() {
    local disk="$1"
    while IFS= read -r line; do
        part=$(echo "$line" | awk '{print $1}')
        type=$(echo "$line" | awk '{print $2}')
        [[ "$type" != "part" ]] && continue

        mountpoint=$(lsblk -ndo MOUNTPOINT "$part" 2>/dev/null)
        fstype=$(lsblk -ndo FSTYPE "$part" 2>/dev/null)
        label=$(lsblk -ndo LABEL "$part" 2>/dev/null)
        size=$(lsblk -ndo SIZE "$part" 2>/dev/null)
        echo "$part|$mountpoint|$fstype|$label|$size"
    done < <(lsblk -nlo NAME,TYPE -p "$disk")
}

main() {
    mapfile -t usb_disks < <(get_usb_disks)
    disk_count=${#usb_disks[@]}

    if [ "$disk_count" -eq 0 ]; then
        echo "{\"text\":\"$GLYPH_UNMOUNTED\",\"tooltip\":\"No USB devices connected\",\"class\":\"none\",\"alt\":\"none\"}"
        exit 0
    fi

    tooltip=""
    total_mounted=0

    for disk in "${usb_disks[@]}"; do
        model=$(lsblk -ndo MODEL "$disk" 2>/dev/null | xargs)
        disk_size=$(lsblk -ndo SIZE "$disk" 2>/dev/null)
        disk_label="${model:-$(basename "$disk")}"

        tooltip+="$disk_label ($disk_size)\\n"

        while IFS='|' read -r part mountpoint fstype label size; do
            [ -z "$part" ] && continue
            display="${label:-$(basename "$part")}"
            if [ -n "$mountpoint" ]; then
                total_mounted=$((total_mounted + 1))
                usage=$(df -h "$mountpoint" 2>/dev/null | awk 'NR==2 {print $3" / "$2" ("$5" used)"}')
                tooltip+="  [Mounted] $display\\n"
                tooltip+="  Mount: $mountpoint | Space: ${usage:-mounted}\\n"
            else
                tooltip+="  [Not Mounted] $display\\n"
                tooltip+="  Size: $size | Type: ${fstype:-unknown}\\n"
            fi
        done < <(get_disk_partitions "$disk")

        tooltip+="\\n"
    done

    # Strip trailing newlines
    tooltip=$(echo -e "$tooltip" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')

    if [ "$total_mounted" -gt 0 ]; then
        icon="$GLYPH_MOUNTED"
        state="mounted"
    else
        icon="$GLYPH_UNMOUNTED"
        state="unmounted"
    fi

    if [ "$disk_count" -eq 1 ]; then
        text="$icon"
    else
        text="$icon $disk_count"
    fi

    jq -nc \
        --arg text "$text" \
        --arg tooltip "$tooltip" \
        --arg class "$state" \
        --arg alt "$state" \
        '{text: $text, tooltip: $tooltip, class: $class, alt: $alt}'
}

main
