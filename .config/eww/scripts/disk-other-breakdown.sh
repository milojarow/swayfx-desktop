#!/bin/bash
# feature: disk
# role:    helper
# Reads the cached top-6 heaviest-dirs payload for the disk widget.
# The du traversal lives in disk-usage-refresh.sh (systemd user timer
# eww-disk-refresh.timer, outside eww's cgroup) — see disk-usage.sh for
# why. This reader must stay O(ms).

CACHE="/tmp/eww-disk-other.json"

if [ -s "$CACHE" ]; then
    cat "$CACHE"
else
    printf '[]\n'
fi
