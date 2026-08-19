#!/bin/sh

# Define path to a state file to ensure consistency
STATE_FILE="$HOME/.cache/dnd_state"

# Initialize state file if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
    # Check actual state and store it
    if makoctl mode | grep -q 'do-not-disturb'; then
        echo "dnd" > "$STATE_FILE"
    else
        echo "default" > "$STATE_FILE"
    fi
fi

case $1'' in
'status') 
    # Get current real state from makoctl
    current_state=$(makoctl mode | grep -q 'do-not-disturb' && echo "dnd" || echo "default")
    
    # Update state file to match reality
    echo "$current_state" > "$STATE_FILE"
    
    # Read from state file for output
    stored_state=$(cat "$STATE_FILE")
    
    if [ "$stored_state" = "dnd" ]; then
        tooltip="mode: do-not-disturb"
    else
        tooltip="mode: default"
    fi
    
    printf '{"alt":"%s","tooltip":"%s"}\n' "$stored_state" "$tooltip"
    ;;
'restore')
    makoctl restore
    echo "default" > "$STATE_FILE"
    ;;
'toggle')
    # Read current state from file
    current_state=$(cat "$STATE_FILE")
    
    # Toggle state based on stored state
    if [ "$current_state" = "dnd" ]; then
        makoctl mode -r do-not-disturb
        echo "default" > "$STATE_FILE"
    else
        makoctl mode -a do-not-disturb
        echo "dnd" > "$STATE_FILE"
    fi
    ;;
esac
