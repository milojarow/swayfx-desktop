#!/usr/bin/env python3
"""Rofi-based app launcher that spawns the selected app in floating mode.

Reads .desktop files from the standard XDG dirs, shows them via
`rofi -dmenu -show-icons`, and on selection hands the Exec= line to
spawn-floating.sh, which uses the PID-pause trick to place the window
floating at creation time (no tiled flash).
"""

import glob
import os
import re
import shlex
import subprocess
import sys
from configparser import ConfigParser, Error as CPError

DESKTOP_DIRS = [
    '/usr/share/applications',
    '/usr/local/share/applications',
    os.path.expanduser('~/.local/share/applications'),
]

EXEC_FIELD_CODES = re.compile(r'%[fFuUdDnNickvm]')


def collect_apps():
    """Return a list of (name, exec, icon) tuples, deduped by name."""
    apps = {}
    for d in DESKTOP_DIRS:
        for path in glob.glob(os.path.join(d, '*.desktop')):
            try:
                cp = ConfigParser(interpolation=None, strict=False)
                cp.read(path, encoding='utf-8')
                if 'Desktop Entry' not in cp:
                    continue
                entry = cp['Desktop Entry']
                if entry.get('NoDisplay', 'false').lower() == 'true':
                    continue
                if entry.get('Hidden', 'false').lower() == 'true':
                    continue
                name = entry.get('Name', '').strip()
                exec_line = entry.get('Exec', '').strip()
                if not name or not exec_line:
                    continue
                # Strip field codes (%f, %u, …) — we don't pass files/URLs
                cmd = EXEC_FIELD_CODES.sub('', exec_line).strip()
                icon = entry.get('Icon', '').strip()
                # Terminal apps need a terminal wrapper; honor it minimally
                if entry.get('Terminal', 'false').lower() == 'true':
                    cmd = f"foot -e {cmd}"
                apps[name] = (cmd, icon)
            except (CPError, UnicodeDecodeError, OSError):
                continue
    return apps


def main():
    apps = collect_apps()
    if not apps:
        sys.exit(1)

    # Feed to rofi: "Name\x00icon\x1ficon-name\n"
    lines = []
    for name in sorted(apps, key=str.casefold):
        icon = apps[name][1]
        if icon:
            lines.append(f'{name}\x00icon\x1f{icon}')
        else:
            lines.append(name)
    rofi_input = '\n'.join(lines)

    try:
        result = subprocess.run(
            ['rofi', '-dmenu', '-i', '-show-icons', '-p', 'Floating',
             '-format', 's', '-lines', '10'],
            input=rofi_input, text=True, capture_output=True,
            encoding='utf-8',
        )
    except FileNotFoundError:
        sys.stderr.write('rofi not found in PATH\n')
        sys.exit(1)

    if result.returncode != 0:
        sys.exit(0)  # user cancelled

    selected = result.stdout.strip()
    if selected not in apps:
        sys.exit(0)

    cmd, _ = apps[selected]
    spawn = os.path.expanduser('~/.config/sway/scripts/spawn-floating.sh')
    os.execvp(spawn, [spawn, cmd])


if __name__ == '__main__':
    main()
