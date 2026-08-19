#!/usr/bin/env bash
# Spawn a shell command so its window appears floating from the first frame.
# Usage: spawn-floating.sh <shell command string>
#
# Technique: fork, child self-stops before exec, parent registers
# `for_window [pid=X] floating enable` via swaymsg, then SIGCONT the child.
# Sway evaluates for_window at container creation, so the window is placed
# floating atomically (no tiled frame rendered).

if [[ $# -eq 0 ]]; then
  exit 0
fi

# Fork: child stops itself before any window-creating exec
(
  kill -STOP "$BASHPID"
  exec sh -c "$*"
) &
pid=$!

# Wait until the child is in stopped state (cap 500ms)
for _ in {1..500}; do
  state=$(awk '/^State:/ {print $2}' "/proc/$pid/status" 2>/dev/null)
  [[ "$state" = "T" ]] && break
  [[ -z "$state" ]] && exit 1
  sleep 0.001
done

# Register the rule; swaymsg returns after sway records it
swaymsg "for_window [pid=$pid] floating enable" >/dev/null

# Fallback for double-fork apps (Electron, browsers, Steam): if the
# pid rule doesn't match within 2s, this listener floats the next
# window it sees. One frame of flash for those apps; acceptable.
"$HOME/.config/sway/scripts/float-next-window.py" &

# Resume — from here the app execs and its window is placed floating
kill -CONT "$pid"
