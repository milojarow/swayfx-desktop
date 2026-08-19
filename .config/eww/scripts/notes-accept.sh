#!/usr/bin/env bash
# feature: notes
# role:    action
# notes-accept.sh — full accept flow for the notes input. Reads the note
# from stdin FIRST (heredoc from :onaccept — the injection-proof channel,
# see notes-add.sh), then detaches: eww SIGKILLs handler commands at
# :timeout (and a stalled daemon once killed the inline chain past 2s).
# Detached, sh returns in ~5ms and the kill never has a target.
# The clear uses ' ' then '' because eww only redraws the field when the
# bound variable actually changes value.

EWW=$HOME/.cargo/bin/eww

text="$(cat)"

{
    printf '%s' "$text" | "$HOME/.config/eww/scripts/notes-add.sh"
    "$EWW" update notes-input=' '
    "$EWW" update notes-input=''
} &
