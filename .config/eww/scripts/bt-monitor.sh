#!/usr/bin/env bash
# feature: bt
# role:    subscribe
# bt-monitor.sh — eww deflisten script for bluetooth management.
# Emits one JSON line per state change: full bt state on every event.

declare -A discovered  # mac -> name, built from [NEW] Device events during scan

emit_state() {
    local powered
    powered=$(bluetoothctl show 2>/dev/null | grep -c "Powered: yes")

    if [[ "$powered" -eq 0 ]]; then
        printf '{"status":"off","scanning":false,"connected_count":0,"connected_device":"","trusted_count":0,"trusted":[],"discovered_count":0,"discovered":[]}\n'
        return
    fi

    local is_scanning
    is_scanning=$(bluetoothctl show 2>/dev/null | grep -c "Discovering: yes")
    local scan_bool
    scan_bool=$([[ "$is_scanning" -gt 0 ]] && echo "true" || echo "false")

    # Build trusted devices array
    local trusted_arr=()
    local connected_count=0
    local connected_device=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local mac name conn conn_bool
        mac=$(echo "$line" | awk '{print $2}')
        name=$(echo "$line" | cut -d' ' -f3-)
        conn=$(bluetoothctl info "$mac" 2>/dev/null | grep -c "Connected: yes")
        conn_bool=$([[ "$conn" -gt 0 ]] && echo "true" || echo "false")
        trusted_arr+=("{\"mac\":\"$mac\",\"name\":$(jq -Rn --arg v "$name" '$v'),\"connected\":$conn_bool}")
        if [[ "$conn" -gt 0 ]]; then
            (( connected_count++ ))
            [[ -z "$connected_device" ]] && connected_device="$name"
        fi
    done < <(bluetoothctl devices Trusted 2>/dev/null)

    local trusted_json="[]"
    local trusted_count="${#trusted_arr[@]}"
    [[ "$trusted_count" -gt 0 ]] && trusted_json="[$(IFS=,; echo "${trusted_arr[*]}")]"

    # Build discovered devices array (exclude already-trusted MACs)
    local trusted_macs
    trusted_macs=$(bluetoothctl devices Trusted 2>/dev/null | awk '{print $2}')
    local disc_arr=()

    for mac in "${!discovered[@]}"; do
        echo "$trusted_macs" | grep -qF "$mac" && continue
        disc_arr+=("{\"mac\":\"$mac\",\"name\":$(jq -Rn --arg v "${discovered[$mac]}" '$v')}")
    done

    local disc_json="[]"
    local disc_count="${#disc_arr[@]}"
    [[ "$disc_count" -gt 0 ]] && disc_json="[$(IFS=,; echo "${disc_arr[*]}")]"

    printf '{"status":"on","scanning":%s,"connected_count":%d,"connected_device":%s,"trusted_count":%d,"trusted":%s,"discovered_count":%d,"discovered":%s}\n' \
        "$scan_bool" \
        "$connected_count" \
        "$(jq -Rn --arg v "$connected_device" '$v')" \
        "$trusted_count" \
        "$trusted_json" \
        "$disc_count" \
        "$disc_json"
}

# Initial state
emit_state

# Watch for bluetooth events via interactive session.
# BlueZ 5.86+ removed the 'monitor' subcommand; interactive mode emits events.
# Strip ANSI escape codes and prompt noise from piped output.
(sleep infinity) | bluetoothctl 2>/dev/null |
    sed -u $'s/\x1b\\[[0-9;]*[a-zA-Z]//g; s/\x1b\\[[0-9]* q//g; s/\r//g' |
    while IFS= read -r line; do
    if echo "$line" | grep -qE '\[NEW\] Device [0-9A-Fa-f:]{17} '; then
        mac=$(echo "$line" | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
        name=$(echo "$line" | sed "s/.*\[NEW\] Device $mac //")
        [[ -n "$mac" ]] && discovered["$mac"]="$name"
        emit_state
    elif echo "$line" | grep -qE '\[DEL\] Device [0-9A-Fa-f:]{17}'; then
        # Ignore DEL events — keep discovered list stable after scan ends.
        # List is cleared when a new scan starts (Discovering: yes).
        :
    elif echo "$line" | grep -qE 'Connected:|Powered:|Discovering:|Trusted:|Paired:'; then
        # Clear discovered list when a new scan starts
        if echo "$line" | grep -q 'Discovering: yes'; then
            discovered=()
        fi
        emit_state
    fi
done
