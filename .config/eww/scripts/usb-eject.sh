#!/usr/bin/env bash
# feature: usb
# role:    action
# usb-eject.sh <device_name>
# Unmounts all partitions of a USB device, then powers it off safely.
for part in "/dev/${1}"*[0-9]; do
    [[ -b "$part" ]] && udisksctl unmount -b "$part" 2>/dev/null
done
udisksctl power-off -b "/dev/$1"
