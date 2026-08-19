#!/usr/bin/env bash
# feature: notes
# role:    action
# notes-delete.sh <line-number> — archive that line, then remove it.
#
# Takes the 1-based line number in notes.txt (never the note text) so
# arbitrary note content never travels through a shell command line.
# Deleted notes append to archive.txt — nothing is destroyed.

NOTES_DIR="$(xdg-user-dir DOCUMENTS)/notes"
NOTES_FILE="$NOTES_DIR/notes.txt"
ARCHIVE_FILE="$NOTES_DIR/archive.txt"
LOCK="$NOTES_DIR/.lock"

idx="$1"
[[ "$idx" =~ ^[0-9]+$ ]] || exit 1
[[ -f "$NOTES_FILE" ]] || exit 1

{
    flock -x 9
    total=$(wc -l < "$NOTES_FILE")
    if (( idx >= 1 && idx <= total )); then
        sed -n "${idx}p" "$NOTES_FILE" >> "$ARCHIVE_FILE"
        sed -i "${idx}d" "$NOTES_FILE"
    fi
} 9>"$LOCK"
