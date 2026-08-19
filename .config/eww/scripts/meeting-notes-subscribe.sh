#!/usr/bin/env bash
# feature: meeting-notes
# role:    subscribe
# meeting-notes-subscribe.sh — eww deflisten for meeting audio recording.
#
# Architecture:
# - Named pipe /tmp/eww-meeting-notes receives start/stop commands from eww button
# - On start: launches pw-record for sink + mic, emits JSON every second with elapsed time
# - On stop: kills pw-record, merges streams with ffmpeg, sends notification
# - On script exit (eww reload): cleanup active recording gracefully

PIPE="/tmp/eww-meeting-notes"
RECORDINGS_DIR="$HOME/recordings/meetings"
PID_SINK=""
PID_MIC=""
TMP_SINK=""
TMP_MIC=""
OUTFILE=""
START_TIME=""
RECORDING=false
TIMER_PID=""

ICON_IDLE=''
ICON_ACTIVE=''

emit_idle() {
    # Dual format: eww keys (active/icon/elapsed) + waybar keys (text/class/tooltip),
    # so BOTH bars render correctly during the migration. Each side ignores the
    # other's extra keys.
    printf '{"active": false, "icon": "%s", "elapsed": "", "text": "%s", "class": "idle", "tooltip": "Start meeting recording"}\n' "$ICON_IDLE" "$ICON_IDLE"
}

emit_active() {
    local now elapsed mins secs
    now=$(date +%s)
    elapsed=$(( now - START_TIME ))
    mins=$(( elapsed / 60 ))
    secs=$(( elapsed % 60 ))
    # Dual format: eww keys (active/icon/elapsed) + waybar keys (text/class/tooltip).
    printf '{"active": true, "icon": "%s", "elapsed": "%02d:%02d", "text": "%s %02d:%02d", "class": "active", "tooltip": "Recording: %s (%02d:%02d) — click to stop"}\n' \
        "$ICON_ACTIVE" "$mins" "$secs" "$ICON_ACTIVE" "$mins" "$secs" "$NAME" "$mins" "$secs"
}

start_recording() {
    local name="$1"
    NAME="${name:-meeting}"
    local timestamp
    timestamp="$(date +%Y-%m-%d_%H%M)"
    OUTFILE="$RECORDINGS_DIR/${timestamp}_${NAME}.wav"
    TMP_SINK="/tmp/meeting-sink-$$.wav"
    TMP_MIC="/tmp/meeting-mic-$$.wav"

    mkdir -p "$RECORDINGS_DIR"

    local sink_id
    sink_id="$(pw-dump | jq -r '.[] | select(.info.props."media.class"=="Audio/Sink") | .id' | head -1)"

    if [[ -z "$sink_id" ]]; then
        notify-send -u critical "Meeting Notes" "No PipeWire audio sink found"
        emit_idle
        return 1
    fi

    pw-record --target "$sink_id" "$TMP_SINK" &
    PID_SINK=$!

    pw-record "$TMP_MIC" &
    PID_MIC=$!

    START_TIME=$(date +%s)
    RECORDING=true

    emit_active

    # Timer loop: emit elapsed every second
    while $RECORDING; do
        sleep 1
        if $RECORDING; then
            emit_active
        fi
    done &
    TIMER_PID=$!
}

stop_recording() {
    if ! $RECORDING; then return; fi

    RECORDING=false

    # Stop timer
    if [[ -n "$TIMER_PID" ]]; then
        kill "$TIMER_PID" 2>/dev/null
        wait "$TIMER_PID" 2>/dev/null
        TIMER_PID=""
    fi

    # Stop recorders
    kill "$PID_SINK" "$PID_MIC" 2>/dev/null
    wait "$PID_SINK" "$PID_MIC" 2>/dev/null
    PID_SINK=""
    PID_MIC=""

    sleep 0.5

    # Merge streams
    if [[ -f "$TMP_SINK" && -f "$TMP_MIC" ]]; then
        ffmpeg -y -i "$TMP_SINK" -i "$TMP_MIC" \
            -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest:normalize=0[out]" \
            -map "[out]" -ac 1 -ar 16000 "$OUTFILE" 2>/dev/null

        if [[ -f "$OUTFILE" ]]; then
            local size
            size="$(du -h "$OUTFILE" | cut -f1)"
            notify-send -i audio-input-microphone "Meeting Notes" "Saved: $(basename "$OUTFILE") ($size)\nTranscribe: meeting-notes transcribe \"$OUTFILE\""
        else
            notify-send -u critical "Meeting Notes" "Merge failed — raw files in /tmp"
            emit_idle
            return 1
        fi
    fi

    rm -f "$TMP_SINK" "$TMP_MIC"
    TMP_SINK=""
    TMP_MIC=""

    emit_idle
}

cleanup() {
    stop_recording
    rm -f "$PIPE"
}

trap cleanup EXIT INT TERM

# Recreate pipe
rm -f "$PIPE"
mkfifo "$PIPE"

# Bootstrap
emit_idle

# Main loop: read commands from pipe
while read -r cmd < "$PIPE"; do
    case "$cmd" in
        start:*)
            if ! $RECORDING; then
                start_recording "${cmd#start:}"
            fi
            ;;
        stop)
            stop_recording
            ;;
        toggle)
            if $RECORDING; then
                stop_recording
            else
                # Prompt for name via rofi
                local_name=$(rofi -dmenu -p "Meeting name" -lines 0 -theme-str 'window { width: 300px; }' 2>/dev/null)
                if [[ -n "$local_name" ]]; then
                    start_recording "$local_name"
                fi
            fi
            ;;
    esac
done
