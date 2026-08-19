#!/usr/bin/env bash
# feature: usb
# role:    action
# usb-umount.sh <partition_name>
# Unmounts a USB partition via udisksctl.
udisksctl unmount -b "/dev/$1"
