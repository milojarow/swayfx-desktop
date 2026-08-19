#!/usr/bin/env sh
# Get scratchpad windows
windows=$(swaymsg -t get_tree | jq -r 'recurse(.nodes[]) | select(.name=="__i3_scratch") | .floating_nodes | length')

# Debug output
echo "Found $windows windows in scratchpad" >&2

# Set class based on number of windows
if [ "$windows" -eq 0 ]; then
    # No windows in scratchpad
    exit 1
elif [ "$windows" -eq 1 ]; then
    class="one"
else
    class="many"
fi

# Get window details for tooltip
tooltip=$(swaymsg -t get_tree | jq -r 'recurse(.nodes[]) | select(.name=="__i3_scratch") | .floating_nodes[] | "\(.app_id // .window_properties.class) | \(.name)"')

# Output JSON for waybar
printf '{"text":"%s", "class":"%s", "alt":"%s", "tooltip":"%s"}\n' "$windows" "$class" "$class" "$(echo "$tooltip" | sed -z 's/\n/\\n/g')"
