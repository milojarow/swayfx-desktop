#!/bin/bash
# feature: disk
# role:    helper
#
# disk-usage.sh — reads the cached disk-usage payload for the disk widget.
# The expensive du traversal lives in disk-usage-refresh.sh, run by the
# systemd user timer eww-disk-refresh.timer OUTSIDE eww's cgroup: a du
# inside an eww defpoll froze every config reload 40-70s (eww joins the
# old script-var runtime on the GTK main thread, and a synchronous du
# there is uncancellable) and pinned eww.service at its MemoryHigh
# ceiling with page cache. This reader must stay O(ms).

CACHE="/tmp/eww-disk-usage.json"

if [ -s "$CACHE" ]; then
    cat "$CACHE"
else
    # Cache not primed yet (fresh boot, timer OnBootSec pending)
    printf '{"documents":0,"pictures":0,"downloads":0,"videos":0,"other":0,"root":0,"documents_path":"","pictures_path":"","downloads_path":"","videos_path":""}\n'
fi
