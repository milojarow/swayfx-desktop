#!/usr/bin/env python3
# ── Notification Dismiss-on-Focus (per-window) ────────────────────────────────
# Role:     Sway IPC event daemon. When a window regains keyboard focus, dismiss
#           the desktop notifications that THAT specific window generated. Each
#           notification is tagged at creation with category "claudewin:<con_id>"
#           by foot-notify-wrapper.sh (foot's [desktop-notifications] command);
#           here we match the focused window's con_id against that tag, so
#           focusing terminal A clears only A's notification, never B's.
#           Clicking a notification still focuses + closes it via foot's native
#           window activation (fyi); this only covers reaching the window by
#           other means (Super+n, swayr, bar click).
# Files:    notif-dismiss-on-focus.py   (paired: foot-notify-wrapper.sh)
# Programs: swaymsg, makoctl
# Daemon:   ~/.config/systemd/user/notif-dismiss-on-focus.service
# Storage:  /tmp/notif-dismiss-on-focus-$USER.pid (single-instance guard)
# ─────────────────────────────────────────────────────────────────────────────

import json
import os
import subprocess
import sys

PIDFILE = f"/tmp/notif-dismiss-on-focus-{os.environ.get('USER', 'user')}.pid"


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def dismiss_for_con(con_id):
    """Dismiss (no history) mako notifications tagged for this con_id."""
    tag = f"claudewin:{con_id}"
    try:
        result = subprocess.run(
            ["makoctl", "list", "-j"], capture_output=True, text=True, check=False
        )
        if result.returncode != 0:
            return
        notifs = json.loads(result.stdout or "[]")
    except (json.JSONDecodeError, OSError) as exc:
        log(f"makoctl list failed: {exc}")
        return
    for n in notifs:
        if n.get("category") == tag:
            subprocess.run(
                ["makoctl", "dismiss", "-n", str(n.get("id")), "-h"],
                capture_output=True, text=True, check=False,
            )


def single_instance():
    if os.path.exists(PIDFILE):
        try:
            old = int(open(PIDFILE).read().strip())
            os.kill(old, 15)  # SIGTERM
        except (ValueError, ProcessLookupError, PermissionError):
            pass
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))


def main():
    single_instance()
    log("notif-dismiss-on-focus subscribed to sway IPC")
    proc = subprocess.Popen(
        ["swaymsg", "-t", "subscribe", "-m", '["window"]'],
        stdout=subprocess.PIPE, text=True, bufsize=1,
    )
    for line in proc.stdout:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("change") != "focus":
            continue
        con = event.get("container") or {}
        con_id = con.get("id")
        if con_id is not None:
            dismiss_for_con(con_id)


if __name__ == "__main__":
    main()
