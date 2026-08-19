#!/bin/bash
# feature: _shared
# role:    shared
# Opens all persistent eww windows at daemon startup and after resume.
#
# Concurrency control:
#   - flock on fd 9 prevents two concurrent runs (e.g. ExecStartPost racing
#     eww-resume-watch.sh) which would create duplicate layer-shell surfaces
#     for ':exclusive true' windows like bar.
#   - Acquired with a 10s timeout so we never hang forever.
#   - Every eww CLI subprocess is spawned with '9>&-' so fd 9 does NOT leak
#     into the daemon's long-lived children (deflisten subscribe scripts).
#     Without that, any hung 'eww open' CLI would keep the open file
#     description — and its lock — alive for days, permanently blocking
#     every subsequent resume recovery. This is the true root cause behind
#     "bar missing after suspend" incidents.

EWW=$HOME/.cargo/bin/eww
LOG_TAG=eww-open-windows
RESTART_GUARD=/tmp/eww-open-windows.restart-guard

# Reap rogue eww daemons from prior runs. A rogue keeps the argv of the CLI
# that forked it ('eww open <window>'), so this pattern hits daemons, not just
# CLIs. Since 2026-08-16 every eww CLI runs through the ~/.scripts/eww guard
# (--no-daemonize), so rogues should no longer be born — this stays as a
# belt-and-braces sweep (e.g. after a `cargo install` overwrote the guard).
# See: man eww-guard.
pkill -f "^${EWW} (open|close|update)" 2>/dev/null || true
sleep 0.2

# Wait for the daemon we're about to drive. Right after resume it can stall
# for several seconds (GTK/Wayland re-init, pages coming back from zram) —
# measured 2026-08-15: no ping answered for ≥2.5 s. A single failed ping used
# to abort the whole run and leave the desktop without widgets, so retry for
# up to 30 s before giving up.
elapsed=0
until "$EWW" ping >/dev/null 2>&1; do
    sleep 0.5
    elapsed=$((elapsed + 1))
    if [ "$elapsed" -ge 60 ]; then
        logger -t "$LOG_TAG" "daemon not responding to ping after 30s, aborting"
        exit 1
    fi
done
[ "$elapsed" -gt 0 ] && logger -t "$LOG_TAG" "daemon answered ping after $((elapsed / 2))s"

exec 9>/tmp/eww-open-windows.lock
if ! flock -w 10 9; then
    logger -t "$LOG_TAG" "could not acquire lock within 10s, aborting"
    exit 1
fi

WINDOWS=(
    disk-widget
    activate-linux
    sysmonitor-window
    temps-window
    usb-widget
    bt-widget
    timer-widget
    clock
    battery-window
    wallpaper-cycle
    notes-widget
    screenshot-mode-widget
)

# '9>&-' closes fd 9 in the child, preventing flock inheritance leaks.
open_window() {
    "$EWW" close "$1" 2>/dev/null 9>&-
    "$EWW" open "$1" 2>/dev/null 9>&-
}

is_active() {
    "$EWW" active-windows 2>/dev/null 9>&- | grep -q "^${1}:"
}

# Phase 1: open all windows in order.
for w in "${WINDOWS[@]}"; do
    open_window "$w"
done

# Phase 2: give the daemon a moment to register the windows, then verify and
# retry anything that silently failed.
#
# IMPORTANT: bar is excluded from per-window retries. Its ':exclusive true'
# layer-shell surface can desync from eww's tracking after sway re-registers
# outputs on resume — eww forgets the surface but sway keeps rendering it.
# In that state 'eww close bar' fails ("no such window was open") and
# 'eww open bar' creates a SECOND surface, leaving the user with two
# stacked bars. So if bar is missing in Phase 2 we skip retry and let
# Phase 3 do a clean service restart, which is the only reliable way to
# clear orphan layer-shell surfaces.
sleep 0.4
for w in "${WINDOWS[@]}"; do
    [ "$w" = "bar" ] && continue
    attempts=0
    while [ "$attempts" -lt 3 ]; do
        if is_active "$w"; then
            break
        fi
        attempts=$((attempts + 1))
        logger -t "$LOG_TAG" "retry $attempts for window: $w"
        open_window "$w"
        sleep 0.3
    done
done

# Phase 3 (bar auto-restart) removed during the waybar migration: the bar moved
# to waybar, so there is no eww 'bar' window to recover anymore. The old logic
# restarted eww.service whenever 'bar' was missing — which would now loop forever.
# See bar.yuck.deprecated.
