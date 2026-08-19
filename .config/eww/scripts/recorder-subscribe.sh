#!/usr/bin/env bash
# feature: recorder
# role:    subscribe
# recorder-subscribe.sh — eww deflisten for screen recording indicator.
#
# Architecture:
# - Emits JSON when wf-recorder starts/stops (signaled via USR1 from recorder.sh)
# - Named pipe receives stop commands from the eww button onclick
# - Widget only visible while recording is active

PIPE="/tmp/eww-recorder"

emit() {
    if pgrep -x wf-recorder > /dev/null 2>&1; then
        printf '{"active": true}\n'
    else
        printf '{"active": false}\n'
    fi
}

stop_recording() {
    if pgrep -x wf-recorder > /dev/null 2>&1; then
        pkill -x --signal SIGINT wf-recorder
    fi
    # Do not emit here — recorder.sh first instance will signal us after cleanup
}

# Re-emit state when signaled by recorder.sh
trap 'emit' USR1

# Recreate pipe on each (re)start
rm -f "$PIPE"
mkfifo "$PIPE"

# Bootstrap: emit current state immediately
emit

# Block waiting for stop signals from the button
while read -r _ < "$PIPE"; do
    stop_recording
done
