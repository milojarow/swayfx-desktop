#!/usr/bin/env bash
# feature: wallpaper-cycle
# role:    helper
# wallpaper-cycle.sh — backend for the wallpaper-cycle eww widget.
#
# Performance: each eww CLI call is a fork+exec+IPC roundtrip (~50-150ms).
# Click handlers must minimize them or rapid clicks pile up and feel dropped.
# We cache list length AND current index in tempfiles so prev/next only need
# one eww call (the update) per click.

set -u

EWW=$HOME/.cargo/bin/eww
WALLPAPER_DIR="$(xdg-user-dir PICTURES)/wallpapers"
STATE_FILE="$HOME/.cache/eww/current-wallpaper"
COUNT_FILE="/tmp/eww-wp-count"
INDEX_FILE="/tmp/eww-wp-index"
APPLIED_FILE="/tmp/eww-wp-applied-index"

mkdir -p "$(dirname "$STATE_FILE")"

build_list_json() {
    find "$WALLPAPER_DIR" -maxdepth 1 -type f \
         \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
         2>/dev/null | sort | python3 -c '
import sys, json, os
items = []
for line in sys.stdin:
    p = line.strip()
    if p:
        items.append({"path": p, "name": os.path.basename(p)})
sys.stdout.write(json.dumps(items) + "\n")
sys.stdout.flush()
'
}

emit_list_and_cache() {
    local json
    json=$(build_list_json)
    echo "$json"
    # Cache count so prev/next don't have to call eww get + python.
    echo "$json" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' > "$COUNT_FILE"
}

apply_index() {
    local idx="$1"
    local path
    path=$("$EWW" get wp-list 2>/dev/null | python3 -c "
import sys, json
try:
    l = json.load(sys.stdin)
    print(l[$idx]['path'])
except Exception:
    pass
")
    [ -z "$path" ] && return 1
    swaymsg "output * bg \"$path\" fill" >/dev/null 2>&1
    echo "$path" > "$STATE_FILE"
    echo "$idx" > "$APPLIED_FILE"
    "$EWW" update wp-applied-index="$idx"
}

cmd="${1:-list}"

case "$cmd" in
    list)
        emit_list_and_cache

        # After eww receives the list, sync wp-index/wp-applied-index to the
        # currently applied wallpaper (read from state file). Background so we
        # don't block the deflisten output stream.
        (
            sleep 0.3
            saved=""
            [ -f "$STATE_FILE" ] && saved=$(cat "$STATE_FILE" 2>/dev/null)
            idx=0
            if [ -n "$saved" ] && [ -f "$saved" ]; then
                idx=$("$EWW" get wp-list 2>/dev/null | python3 -c "
import sys, json
target = '$saved'
try:
    l = json.load(sys.stdin)
    for i, item in enumerate(l):
        if item['path'] == target:
            print(i); break
    else:
        print(0)
except Exception:
    print(0)
")
            fi
            echo "$idx" > "$INDEX_FILE"
            echo "$idx" > "$APPLIED_FILE"
            "$EWW" update wp-index="$idx" wp-applied-index="$idx"
        ) &

        # Watch the dir for adds/removes/renames; re-emit on each change.
        if command -v inotifywait >/dev/null 2>&1; then
            while inotifywait -qq -e create,delete,move "$WALLPAPER_DIR" 2>/dev/null; do
                emit_list_and_cache
            done
        else
            sleep infinity
        fi
        ;;

    # Click handlers below detach their whole body: eww SIGKILLs handler
    # commands after :timeout (200ms default) — a kill mid-body desyncs
    # INDEX_FILE from the wp-* vars. Detached, sh returns in ~5ms and the
    # kill never has a target.
    prev|next)
        (
        # Fast path: read both values from tempfiles, no eww calls except update.
        [ -f "$COUNT_FILE" ] || exit 0
        count=$(<"$COUNT_FILE")
        [ "$count" -gt 0 ] || exit 0
        idx=0
        [ -f "$INDEX_FILE" ] && idx=$(<"$INDEX_FILE")
        if [ "$cmd" = "prev" ]; then
            idx=$(( (idx - 1 + count) % count ))
        else
            idx=$(( (idx + 1) % count ))
        fi
        echo "$idx" > "$INDEX_FILE"
        "$EWW" update wp-index="$idx"
        ) &
        ;;

    dot-click)
        (
        rev=$("$EWW" get wp-revealed 2>/dev/null)
        if [ "$rev" = "true" ]; then
            idx=0
            [ -f "$INDEX_FILE" ] && idx=$(<"$INDEX_FILE")
            apply_index "$idx"
            "$EWW" update wp-revealed=false
        else
            "$EWW" update wp-revealed=true
        fi
        ) &
        ;;

    cancel)
        (
        applied=0
        [ -f "$APPLIED_FILE" ] && applied=$(<"$APPLIED_FILE")
        echo "$applied" > "$INDEX_FILE"
        "$EWW" update wp-index="$applied" wp-revealed=false
        ) &
        ;;

    *)
        echo "unknown command: $cmd" >&2
        exit 1
        ;;
esac
