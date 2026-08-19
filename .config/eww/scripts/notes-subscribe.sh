#!/usr/bin/env bash
# feature: notes
# role:    subscribe
# notes-subscribe.sh — eww deflisten for the desktop notes widget.
#
# Emits the full notes list as JSON on start and on every change to the
# notes file. Event-driven: inotifywait watches the PARENT DIR because
# sed -i (delete path) replaces the file by rename, which kills a watch
# placed on the file's inode.
#
# Line format in notes.txt: "YYYY-MM-DD HH:MM<TAB>text". Lines without a
# tab (hand-edits) are kept whole as text with empty time.

NOTES_DIR="$(xdg-user-dir DOCUMENTS)/notes"
NOTES_FILE="$NOTES_DIR/notes.txt"

mkdir -p "$NOTES_DIR"
touch "$NOTES_FILE"

emit() {
    jq -Rsc '
        split("\n") | map(select(length > 0)) | to_entries |
        map(.value as $l | ($l | split("\t")) as $p |
            {
                idx:  (.key + 1),
                time: (if ($p | length) > 1 then $p[0][5:] else "" end),
                text: (if ($p | length) > 1 then ($p[1:] | join("\t")) else $l end)
            }) |
        reverse | {notes: ., count: length}
    ' < "$NOTES_FILE"
}

emit

inotifywait -m -q -e close_write,moved_to,create --format '%f' "$NOTES_DIR" 2>/dev/null |
while read -r changed; do
    [[ "$changed" == "notes.txt" ]] && emit
done
