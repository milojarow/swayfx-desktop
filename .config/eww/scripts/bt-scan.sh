#!/usr/bin/env bash
# feature: bt
# role:    action
# Toggle bluetooth scan. If already scanning: stop. Otherwise: start for 15s.
if bluetoothctl show 2>/dev/null | grep -q "Discovering: yes"; then
    bluetoothctl scan off 2>/dev/null
    eww update bt-scan-done=false bt-scan-requested=false
else
    eww update bt-scan-requested=true        # instant visual feedback before bt-monitor.sh catches up
    (
        bluetoothctl -t 15 scan on 2>/dev/null
        sleep 1  # let bt-monitor.sh process final DEL/CHG events
        eww update bt-scan-requested=false
        eww update bt-scan-done=true
        sleep 4  # show "No devices found" for 4 seconds
        eww update bt-scan-done=false
    ) &
fi
