#!/usr/bin/env bash
# feature: usb
# role:    subscribe
# usb-monitor.sh — eww deflisten script for USB management.
# Emits one JSON line per event: {"devices":[...],"count":N}
# Detection logic mirrors waybar usb-monitor.sh (HOTPLUG+RM flags).

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

emit_json() {
    mapfile -t disks < <(get_usb_disks)
    count=${#disks[@]}
    idx=0
    out="["

    for disk in "${disks[@]}"; do
        [[ $idx -gt 0 ]] && out+=","
        disk_name=$(basename "$disk")
        size=$(lsblk -ndo SIZE "$disk" 2>/dev/null)
        parts="["
        first=1

        while IFS= read -r pline; do
            part=$(echo "$pline" | awk '{print $1}')
            ptype=$(echo "$pline" | awk '{print $2}')
            [[ "$ptype" != "part" ]] && continue
            [[ $first -eq 0 ]] && parts+=","
            part_name=$(basename "$part")
            mp=$(lsblk -ndo MOUNTPOINT "$part" 2>/dev/null)
            label=$(lsblk -ndo LABEL "$part" 2>/dev/null)
            psize=$(lsblk -ndo SIZE "$part" 2>/dev/null)
            mounted="false"; [[ -n "$mp" ]] && mounted="true"
            parts+="{\"name\":\"$part_name\",\"device\":\"$disk_name\",\"label\":\"$label\",\"size\":\"$psize\",\"mountpoint\":\"$mp\",\"mounted\":$mounted}"
            first=0
        done < <(lsblk -nlo NAME,TYPE -p "$disk")

        # No partition table — disk used directly
        if [[ "$parts" == "[" ]]; then
            mp=$(lsblk -ndo MOUNTPOINT "$disk" 2>/dev/null)
            label=$(lsblk -ndo LABEL "$disk" 2>/dev/null)
            mounted="false"; [[ -n "$mp" ]] && mounted="true"
            parts+= "{\"name\":\"$disk_name\",\"device\":\"$disk_name\",\"label\":\"$label\",\"size\":\"$size\",\"mountpoint\":\"$mp\",\"mounted\":$mounted}"
        fi
        parts+="]"

        out+="{\"idx\":$idx,\"name\":\"$disk_name\",\"size\":\"$size\",\"partitions\":$parts}"
        idx=$((idx + 1))
    done

    out+="]"
    echo "{\"devices\":$out,\"count\":$count}"
}

emit_json

udevadm monitor --udev --subsystem-match=block 2>/dev/null | \
while IFS= read -r line; do
    case "$line" in
        *add*|*remove*|*change*)
            sleep 0.5
            emit_json
            ;;
    esac
done
