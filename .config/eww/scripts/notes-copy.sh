#!/usr/bin/env bash
# feature: notes
# role:    action
# notes-copy.sh <line-number> — copy that note's text to the clipboard.
# Same line-number contract as notes-delete.sh: note text never rides a
# shell command line.

NOTES_FILE="$(xdg-user-dir DOCUMENTS)/notes/notes.txt"

idx="$1"
[[ "$idx" =~ ^[0-9]+$ ]] || exit 1
[[ -f "$NOTES_FILE" ]] || exit 1

line="$(sed -n "${idx}p" "$NOTES_FILE")"
[[ -z "$line" ]] && exit 1

text="${line#*$'\t'}"
printf '%s' "$text" | wl-copy
notify-send -t 3000 "Notas" "Nota copiada al portapapeles"
