#!/usr/bin/env sh

pgrep -x wf-recorder > /dev/null
status=$?

countdown() {
    notify "Recording in 3 seconds" -t 1000
    sleep 1
    notify "Recording in 2 seconds" -t 1000
    sleep 1
    notify "Recording in 1 seconds" -t 1000
    sleep 1
}

notify() {
    line=$1
    shift
    notify-send "Recording" "${line}" -i /usr/share/icons/Papirus-Dark/32x32/devices/camera-video.svg $*
}

# Signal both eww (default) and waybar (fallback) bars
signal_bars() {
    waybar-signal recorder 2>/dev/null || true
    pid=$(pgrep -of "eww/scripts/recorder-subscribe.sh")
    [ -n "$pid" ] && kill -USR1 "$pid" 2>/dev/null || true
}

if [ $status != 0 ]; then
    target_path=$(xdg-user-dir VIDEOS)
    timestamp=$(date +'recording_%Y%m%d-%H%M%S')

    notify "Select a region to record" -t 1000
    area=$(swaymsg -t get_tree | jq -r '.. | select(.pid? and .visible?) | .rect | "\(.x),\(.y) \(.width)x\(.height)"' | slurp)
    # slurp exits non-zero with empty output on Esc/cancel; without this guard
    # wf-recorder treats -g "" as "capture whole output" and records anyway.
    if [ $? -ne 0 ] || [ -z "$area" ]; then
        notify "Recording cancelled" -t 1500
        exit 0
    fi

    countdown
    (sleep 0.5 && signal_bars) &

    if [ "$1" = "-a" ]; then
        file="$target_path/$timestamp.mp4"
        wf-recorder --audio -g "$area" --file="$file"
    elif [ "$1" = "-s" ]; then
        file="$target_path/$timestamp-sysaudio.mp4"
        monitor="$(pactl get-default-sink).monitor"
        wf-recorder --audio="$monitor" -g "$area" --file="$file"
    else
        file="$target_path/$timestamp.webm"
        wf-recorder -g "$area" -c libvpx --codec-param="qmin=0" --codec-param="qmax=25" --codec-param="crf=4" --codec-param="b:v=1M" --file="$file"
    fi

    signal_bars
    notify "Finished recording ${file}"
else
    pkill -x --signal SIGINT wf-recorder
    # Notification is handled by the first instance after wf-recorder exits.
fi
