#!/usr/bin/env bash
# ── Palette Theming ───────────────────────────────────────────────────────────
# Role:     Live terminal palette update via OSC escape sequences. Parses
#           [colors-dark] from a foot-theme.ini, builds OSC payloads
#           (OSC 10=fg, OSC 11=bg, OSC 4;N=palette color N), and writes them
#           to all writable /dev/pts/* PTY slave devices so running foot
#           instances update their color palette instantly without restart.
# Files:    theme-apply-foot.sh
#           ~/.config/sway/themes/<name>/foot-theme.ini  (source palette arg)
# Programs: awk
# Man:      man palette-theming
# ─────────────────────────────────────────────────────────────────────────────
# Apply foot theme colors to all running foot terminals via OSC escape sequences.
# Writes directly to each terminal's PTY slave so foot renders the color changes
# in real time without restarting the server.
#
# OSC 10 = foreground, OSC 11 = background, OSC 4;N = palette color N

set -u

THEME_FILE="${1:-}"
if [[ -z "$THEME_FILE" || ! -f "$THEME_FILE" ]]; then
    echo "Usage: $0 <foot-theme.ini>" >&2
    exit 1
fi

# Extract a color value from the [colors-dark] section (returns bare 6-char hex)
get_color() {
    awk -v key="$1" '
        /^\[colors-dark\]/ { in_s=1; next }
        /^\[/              { in_s=0 }
        in_s && $0 ~ ("^" key "=[0-9a-fA-F]") {
            sub(/^[^=]+=/, "")
            sub(/[[:space:]].*/, "")
            print substr($0, 1, 6)
            exit
        }
    ' "$THEME_FILE"
}

bg=$(get_color background); fg=$(get_color foreground)
r0=$(get_color regular0);   r1=$(get_color regular1)
r2=$(get_color regular2);   r3=$(get_color regular3)
r4=$(get_color regular4);   r5=$(get_color regular5)
r6=$(get_color regular6);   r7=$(get_color regular7)
b0=$(get_color bright0);    b1=$(get_color bright1)
b2=$(get_color bright2);    b3=$(get_color bright3)
b4=$(get_color bright4);    b5=$(get_color bright5)
b6=$(get_color bright6);    b7=$(get_color bright7)

build_osc() {
    [[ -n "$fg" ]] && printf "\e]10;#%s\a" "$fg"
    [[ -n "$bg" ]] && printf "\e]11;#%s\a" "$bg"
    local i=0
    for c in "$r0" "$r1" "$r2" "$r3" "$r4" "$r5" "$r6" "$r7" \
             "$b0" "$b1" "$b2" "$b3" "$b4" "$b5" "$b6" "$b7"; do
        [[ -n "$c" ]] && printf "\e]4;%d;#%s\a" "$i" "$c"
        (( i++ ))
    done
}

osc_payload=$(build_osc)

# Write to all writable PTY slave devices owned by this user.
# Writing to a PTY slave sends data to the master's read buffer,
# which foot (the terminal emulator) processes as program output.
for pty in /dev/pts/[0-9]*; do
    [[ -w "$pty" ]] && printf '%s' "$osc_payload" > "$pty" 2>/dev/null
done
