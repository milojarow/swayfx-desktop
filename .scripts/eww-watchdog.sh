#!/bin/bash
# eww-watchdog — runs every minute from eww-watchdog.timer (see: man eww-guard).
#
# Heals eww.service when its daemon is alive-but-useless. Two failure modes:
#   1. rogue   — a daemon that is NOT the unit's MainPID listens on the eww IPC
#                socket path. A CLI (`eww open …` without --no-daemonize) forked
#                a duplicate daemon and stole the socket; the real daemon keeps
#                its windows but nobody can reach it, so its popups are stuck.
#   2. zombie  — the unit is active but the socket does not answer a ping in 3 s.
# Heal = restart eww.service: ExecStartPre pkills every eww daemon (rogues
# included), ExecStartPost reopens the persistent windows.
#
#   eww-watchdog.sh          probe and heal (timer)
#   eww-watchdog.sh --check  probe only, print the verdict, never restart

EWW=$HOME/.cargo/bin/eww
TAG=eww-watchdog
check_only=0; [ "${1:-}" = "--check" ] && check_only=1

if ! systemctl --user --quiet is-active eww.service; then
    [ $check_only = 1 ] && echo "eww.service not active — nothing to guard"
    exit 0
fi
main=$(systemctl --user show -p MainPID --value eww.service)
if ! [ "${main:-0}" -gt 0 ] 2>/dev/null; then
    [ $check_only = 1 ] && echo "eww.service has no MainPID — nothing to guard"
    exit 0
fi

# One line per (socket-name, pid) for every LISTENING eww IPC socket we own.
listeners=$(ss -xlpH 2>/dev/null | grep -F 'eww-server_' | while read -r line; do
    sock=$(grep -oE 'eww-server_[0-9a-f]+' <<<"$line" | head -1)
    grep -oE 'pid=[0-9]+' <<<"$line" | cut -d= -f2 | while read -r pid; do echo "$sock $pid"; done
done)

reason=""
main_sock=$(awk -v m="$main" '$2==m {print $1; exit}' <<<"$listeners")
if [ -z "$main_sock" ]; then
    reason="main daemon (pid $main) holds no IPC listener"
else
    rogues=$(awk -v m="$main" -v s="$main_sock" '$1==s && $2!=m {print $2}' <<<"$listeners" | tr '\n' ' ')
    [ -n "$rogues" ] && reason="rogue eww daemon(s) on $main_sock: pid(s) ${rogues% } (main pid $main)"
fi
if [ -z "$reason" ] && ! timeout 3 "$EWW" ping >/dev/null 2>&1; then
    reason="IPC unresponsive (ping timeout)"
fi

if [ -z "$reason" ]; then
    [ $check_only = 1 ] && echo "healthy: main pid $main is the only listener on ${main_sock:-?} and answers ping"
    exit 0
fi
if [ $check_only = 1 ]; then
    echo "UNHEALTHY: $reason"
    exit 1
fi
echo "$reason — restarting eww.service" | systemd-cat -t "$TAG" -p warning
systemctl --user restart eww.service
