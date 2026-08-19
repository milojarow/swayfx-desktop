#!/usr/bin/env bash
# feature: timer
# role:    subscribe
# timer-subscribe.sh — eww deflisten daemon for countdown timer.
#
# Named-pipe protocol (writes to /tmp/eww-timer):
#   play:H:M:S  — start a new countdown from H hours, M minutes, S seconds
#   resume      — resume a paused timer
#   pause       — pause a running timer
#   reset       — stop and return to idle state
#
# Emits one JSON line per second:
#   {"status":"idle","remaining":0,"total":0,"display":"00:00:00"}
# Status values: idle | running | paused | finished

PIPE="/tmp/eww-timer"

status="idle"
total=0
end_time=0
pause_remaining=0

format_time() {
    local s=$1
    printf '%02d:%02d:%02d' $(( s / 3600 )) $(( (s % 3600) / 60 )) $(( s % 60 ))
}

get_remaining() {
    local now r
    case "$status" in
        running)
            now=$(date +%s)
            r=$(( end_time - now ))
            echo $(( r < 0 ? 0 : r ))
            ;;
        paused)
            echo "$pause_remaining"
            ;;
        *)
            echo 0
            ;;
    esac
}

last_payload=""

emit() {
    local remaining display payload
    remaining=$(get_remaining)

    # Transition running → finished when countdown hits zero
    if [[ "$status" == "running" && "$remaining" -eq 0 ]]; then
        status="finished"
        notify-send -u normal -i dialog-information "Timer" "Time's up!" 2>/dev/null || true
    fi

    display=$(format_time "$remaining")
    payload=$(printf '{"status":"%s","remaining":%d,"total":%d,"display":"%s"}' \
        "$status" "$remaining" "$total" "$display")

    # Suppress no-op emissions: while idle/paused/finished the payload is
    # identical every tick, and eww applies every update with no
    # equal-value dedup — each one re-renders the widget for nothing.
    if [[ "$payload" != "$last_payload" ]]; then
        printf '%s\n' "$payload"
        last_payload="$payload"
    fi
}

handle_cmd() {
    local cmd=$1
    local h m s t now
    case "${cmd%%:*}" in
        play)
            IFS=: read -r _ h m s <<< "$cmd"
            t=$(( h * 3600 + m * 60 + s ))
            if (( t > 0 )); then
                now=$(date +%s)
                total=$t
                end_time=$(( now + t ))
                status="running"
            fi
            ;;
        resume)
            if [[ "$status" == "paused" ]] && (( pause_remaining > 0 )); then
                now=$(date +%s)
                end_time=$(( now + pause_remaining ))
                status="running"
            fi
            ;;
        pause)
            if [[ "$status" == "running" ]]; then
                pause_remaining=$(get_remaining)
                status="paused"
            fi
            ;;
        reset)
            status="idle"
            total=0
            end_time=0
            pause_remaining=0
            ;;
    esac
}

# Recreate pipe on each (re)start to avoid stale writers
rm -f "$PIPE"
mkfifo "$PIPE"

# Keep both ends of the FIFO open on fd 3 so that read -t never gets
# instant EOF when no external writer is currently connected.
exec 3<> "$PIPE"

# Emit initial state immediately
emit

while true; do
    # read -t 1 acts as our 1-second tick:
    #   - if a command arrives within 1 s, handle it then emit
    #   - if the timeout fires, just emit (and decrement running timer)
    if IFS= read -r -t 1 cmd <&3; then
        handle_cmd "$cmd"
    fi
    emit
done
