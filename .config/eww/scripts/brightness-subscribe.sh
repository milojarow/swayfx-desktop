#!/bin/bash
# feature: brightness
# role:    subscribe
# Emits brightness percentage on start and on every hardware brightness change.
# Uses udevadm to react to kernel backlight uevents — zero polling delay.

brightnessctl -m | cut -d, -f4 | tr -d %

udevadm monitor --udev --subsystem-match=backlight 2>/dev/null |
while read -r line; do
  case "$line" in
    *change*)
      brightnessctl -m | cut -d, -f4 | tr -d %
      ;;
  esac
done
