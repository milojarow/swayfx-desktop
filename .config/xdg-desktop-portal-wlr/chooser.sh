#!/bin/bash
# Screencast target chooser for xdg-desktop-portal-wlr.
#
# xdpw feeds a newline-separated list on stdin and expects back EXACTLY one of
# those lines, verbatim, on stdout — anything else (including no output) is read
# as "the user declined". The lines look like:
#
#   Monitor: eDP-1 Sharp Corporation 0x1453 (eDP-1)
#   Window: <window title> (<ext-foreign-toplevel-list-v1 id>)
#
# The default chooser is slurp, which selects a rectangle and therefore can only
# ever answer with a Monitor line — that, and not a missing feature, is why
# "share a window" degraded to "share a screen" on this machine. Windows only
# appear in the list when the requesting app asks for them (source type 2);
# monitor-only apps get the old list unchanged.
#
# rofi shows a cleaned-up label and returns the INDEX (-format i), so the line
# handed back to xdpw is byte-identical to the one it sent, ids and all.
set -uo pipefail

mapfile -t lines

((${#lines[@]})) || exit 0

labels=()
for line in "${lines[@]}"; do
    case "$line" in
        "Monitor: "*)
            labels+=("[pantalla]  ${line#Monitor: }")
            ;;
        "Window: "*)
            title=${line#Window: }
            title=${title% (*}          # drop the trailing (toplevel id)
            labels+=("[ventana]   ${title}")
            ;;
        *)
            labels+=("$line")
            ;;
    esac
done

idx=$(printf '%s\n' "${labels[@]}" |
      rofi -dmenu -i -no-custom -format i -p "Compartir" -mesg "Elige qué transmitir")

[[ $idx =~ ^[0-9]+$ ]] || exit 0
(( idx < ${#lines[@]} )) || exit 0

printf '%s\n' "${lines[$idx]}"
