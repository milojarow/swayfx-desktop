#!/usr/bin/env bash
# ── foot notify wrapper ───────────────────────────────────────────────────────
# Role:    Wraps `fyi` (foot's [desktop-notifications] command). Two jobs:
#          1) Tags every notification with the sway con_id of the foot window
#             that emitted it (--category=claudewin:<con_id>) so
#             notif-dismiss-on-focus.py can dismiss PER-WINDOW.
#          2) Bell notifications (title "Bell", from [bell] notify=yes): only
#             windows holding an ssh/mosh-client session get a popup — that BEL
#             is the one signal that survives remote tmux + mosh, rung by the
#             remote Claude Code (preferredNotifChannel=terminal_bell). The
#             generic "Bell/Bell in terminal" text is rewritten with the remote
#             host name. Local bells are dropped: local Claude notifies via
#             OSC 9 (different title) and fish's done plugin sends its own
#             notify-send, so a popup here would duplicate.
#          foot's native click-to-focus is preserved: this execs fyi, so fyi's
#          stdout (id=/action=/xdgtoken=) flows straight to foot.
# Files:   foot-notify-wrapper.sh   (paired: notif-dismiss-on-focus.py)
# Wired:   ~/.config/foot/foot.ini  [desktop-notifications] command=
# Test:    FOOT_NOTIFY_FOOT_PID=<pid> overrides the emitting-foot pid (both the
#          con_id lookup and the ssh/mosh descendant walk start there).
# Notes:   - Writes nothing to stdout itself; only exec'd fyi does (foot parses
#            that stdout for window activation).
#          - On any failure it still execs fyi untagged, so notifications never
#            break (click-to-focus still works, just no per-window auto-dismiss).
#          - Assumes foot normal mode (one process per window). In --server mode
#            $PPID would be the shared server and the tag would be wrong.
# ─────────────────────────────────────────────────────────────────────────────

set -u

ROOT_PID=${FOOT_NOTIFY_FOOT_PID:-$PPID}

# con_id of the nearest foot ancestor = the window that emitted this notification.
find_con_id() {
    local p=$ROOT_PID tree pid cid i
    local -a pids=()
    for ((i = 0; i < 12; i++)); do
        [[ -z $p || $p -le 1 ]] && break
        pids+=("$p")
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    done
    [[ ${#pids[@]} -eq 0 ]] && return 1
    tree=$(swaymsg -t get_tree 2>/dev/null) || return 1
    for pid in "${pids[@]}"; do
        cid=$(jq -r --argjson pid "$pid" \
            '.. | objects | select(.pid? == $pid) | .id' <<<"$tree" 2>/dev/null | head -1)
        if [[ -n $cid ]]; then
            printf '%s' "$cid"
            return 0
        fi
    done
    return 1
}

# BFS down from the emitting foot: print the argv of the first ssh / mosh-client
# descendant (the remote session living in that window), or fail.
find_remote_argv() {
    local ps_out
    ps_out=$(ps -eo pid=,ppid=,args= 2>/dev/null) || return 1
    local -a queue=("$ROOT_PID") next=()
    local depth parent pid ppid args
    for ((depth = 0; depth < 8; depth++)); do
        [[ ${#queue[@]} -eq 0 ]] && break
        next=()
        for parent in "${queue[@]}"; do
            while read -r pid ppid args; do
                [[ $ppid == "$parent" ]] || continue
                case $args in
                    mosh-client\ * | */mosh-client\ * | ssh\ * | */ssh\ *)
                        printf '%s' "$args"
                        return 0
                        ;;
                esac
                next+=("$pid")
            done <<<"$ps_out"
        done
        queue=("${next[@]:-}")
    done
    return 1
}

# Best-effort remote host from an ssh / mosh-client argv.
host_from_argv() {
    local -a argv
    read -r -a argv <<<"$1"
    local prog=${argv[0]##*/} i
    case $prog in
        mosh-client)
            # mosh launches: mosh-client -# <original args> -- ...
            for ((i = 1; i < ${#argv[@]} - 1; i++)); do
                if [[ ${argv[i]} == "-#" ]]; then
                    printf '%s' "${argv[i + 1]}"
                    return 0
                fi
            done
            ;;
        ssh)
            for ((i = 1; i < ${#argv[@]}; i++)); do
                case ${argv[i]} in
                    -o | -p | -l | -i | -F | -L | -R | -D | -J | -W | -E | -e | -b | -c | -m | -O | -Q | -S | -w | -B | -P)
                        ((i++)) ;;
                    -*) ;;
                    *)
                        printf '%s' "${argv[i]%%@*}"
                        return 0
                        ;;
                esac
            done
            ;;
    esac
    return 1
}

# Split our argv at "--": pre = fyi options, post = title + body.
declare -a pre=() post=()
seen_sep=0
for a in "$@"; do
    if ((seen_sep)); then
        post+=("$a")
    elif [[ $a == "--" ]]; then
        seen_sep=1
    else
        pre+=("$a")
    fi
done
title=${post[0]:-}

# Bell branch: popup only for windows holding a remote (ssh/mosh) session.
if [[ $title == "Bell" ]]; then
    remote_argv=$(find_remote_argv) || exit 0 # local bell -> no popup
    host=$(host_from_argv "$remote_argv") || host="remota"
    post=("Sesión en «${host}» espera tu atención" "Claude terminó o un proceso remoto pide input")
fi

conid=$(find_con_id) || conid=""

if [[ -n $conid ]]; then
    exec fyi --category="claudewin:$conid" "${pre[@]}" -- "${post[@]}"
else
    exec fyi "${pre[@]}" -- "${post[@]}"
fi
