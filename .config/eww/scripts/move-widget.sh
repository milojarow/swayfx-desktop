#!/usr/bin/env bash
# feature: _shared
# role:    shared
# move-widget.sh <window-name> <yuck-file> <axis> <delta>
#
# Moves a defwindow's position by editing its geometry block in the yuck file.
# Uses Python to precisely target the named defwindow, avoiding false matches
# when multiple defwindows share the same file.

WINDOW="$1"
YUCK="$2"
AXIS="$3"
DELTA="$4"

python3 - "$WINDOW" "$YUCK" "$AXIS" "$DELTA" << 'PYEOF'
import re, sys

window, path, axis, delta = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

with open(path) as f:
    content = f.read()

block_re = re.compile(r'(\(defwindow ' + re.escape(window) + r'\b.*?)(?=\(defwindow|\Z)', re.DOTALL)
m = block_re.search(content)
if not m:
    print(f"Error: defwindow '{window}' not found in {path}", file=sys.stderr)
    sys.exit(1)

old_block = m.group(1)

# Invert deltas so arrow directions match visual movement.
#   x axis: right-anchored windows have positive x growing leftward; invert.
#   y axis: top-anchored AND center-anchored windows have positive y growing
#           downward; the up arrow sends positive delta, so invert. Only
#           bottom-anchored windows treat positive y as upward (no inversion).
anchor_match = re.search(r':anchor\s+"([^"]+)"', old_block)
anchor = anchor_match.group(1) if anchor_match else ''
if axis == 'x' and 'right' in anchor:
    delta = -delta
if axis == 'y' and 'bottom' not in anchor:
    delta = -delta

val_match = re.search(rf':{axis} "(-?\d+)px"', old_block)
if not val_match:
    print(f"Error: :{axis} not found in defwindow '{window}'", file=sys.stderr)
    sys.exit(1)

val = int(val_match.group(1))
new_val = val + delta
new_block = re.sub(rf'(:{axis} ")(-?\d+)(px")', rf'\g<1>{new_val}\3', old_block, count=1)

with open(path, 'w') as f:
    f.write(content[:m.start()] + new_block + content[m.end():])
PYEOF

~/.cargo/bin/eww close "$WINDOW" 2>/dev/null
~/.cargo/bin/eww open "$WINDOW"
