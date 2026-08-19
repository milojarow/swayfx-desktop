#!/bin/bash
# Listens for system resume via D-Bus PrepareForSleep signal.
# When the system wakes from suspend/hibernate, reopens eww windows.

export PATH="$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin"

dbus-monitor --system \
  "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" \
  2>/dev/null |
while read -r line; do
  # PrepareForSleep(false) = system just resumed
  if echo "$line" | grep -q 'boolean false'; then
    # Wait for eww daemon to be responsive
    timeout=20
    elapsed=0
    until eww ping 2>/dev/null; do
      sleep 0.5
      elapsed=$((elapsed + 1))
      [ "$elapsed" -ge "$((timeout * 2))" ] && break
    done
    # Wait for sway to re-register monitors (race condition on resume)
    elapsed=0
    until swaymsg -t get_outputs 2>/dev/null | grep -q '"active": true'; do
      sleep 0.5
      elapsed=$((elapsed + 1))
      [ "$elapsed" -ge "$((timeout * 2))" ] && break
    done
    # Wait for output geometry to stabilize — kanshi may still be reconfiguring.
    # Require two consecutive identical non-zero widths before opening windows
    # so the bar's 100% width is computed against the final settled resolution.
    prev_width=0; stable=0; elapsed=0
    while [ "$stable" -lt 2 ]; do
      cur_width=$(swaymsg -t get_outputs 2>/dev/null | \
        python3 -c "import json,sys; ol=[o for o in json.load(sys.stdin) if o.get('active')]; print(max((o.get('current_mode',{}).get('width',0) for o in ol), default=0))" 2>/dev/null || echo 0)
      if [ "${cur_width:-0}" -gt 0 ] && [ "$cur_width" = "$prev_width" ]; then
        stable=$((stable + 1))
      else
        stable=0
        prev_width="${cur_width:-0}"
      fi
      sleep 0.3
      elapsed=$((elapsed + 1))
      [ "$elapsed" -ge 60 ] && break  # 18s hard timeout
    done
    $HOME/.config/eww/scripts/open-windows.sh
  fi
done
