#!/usr/bin/env python3
"""One-shot listener: float the next new window, then exit.

Used by launch-floating.sh to make apps spawned from a specific launcher
appear in floating mode. Self-terminates after 15s if no window appears.
"""

import threading
import i3ipc

TIMEOUT_SECONDS = 2


def main():
    conn = i3ipc.Connection()

    def on_new(_ipc, event):
        event.container.command('floating enable')
        conn.main_quit()

    conn.on('window::new', on_new)
    threading.Timer(TIMEOUT_SECONDS, conn.main_quit).start()
    conn.main()


if __name__ == '__main__':
    main()
