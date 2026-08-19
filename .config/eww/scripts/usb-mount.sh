#!/usr/bin/env bash
# feature: usb
# role:    action
# usb-mount.sh <partition_name>
# Mounts a USB partition via udisksctl (no sudo required).
# udisksctl automatically uses the partition label as the mount directory name.
udisksctl mount -b "/dev/$1"
