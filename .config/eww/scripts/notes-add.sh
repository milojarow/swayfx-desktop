#!/usr/bin/env bash
# feature: notes
# role:    action
# notes-add.sh — append one timestamped note to notes.txt.
#
# Text arrives on stdin (the eww input :onaccept feeds it via a
# quoted-delimiter heredoc — eww substitutes {} into the command string
# RAW, so argv would break on quotes and EXECUTE $(...); stdin is the
# only injection-proof channel) or as argv for CLI use.

NOTES_DIR="$(xdg-user-dir DOCUMENTS)/notes"
NOTES_FILE="$NOTES_DIR/notes.txt"
LOCK="$NOTES_DIR/.lock"

if [[ $# -gt 0 ]]; then
    text="$*"
else
    text="$(cat)"
fi

text="${text//$'\n'/ }"
text="${text#"${text%%[![:space:]]*}"}"
text="${text%"${text##*[![:space:]]}"}"
[[ -z "$text" ]] && exit 0

mkdir -p "$NOTES_DIR"
{
    flock -x 9
    printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$text" >> "$NOTES_FILE"
} 9>"$LOCK"
