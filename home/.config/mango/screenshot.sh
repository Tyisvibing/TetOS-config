#!/bin/bash
# Region screenshot: saved to ~/Pictures/Screenshots and copied to the clipboard.
dir=~/Pictures/Screenshots; mkdir -p "$dir"
f="$dir/screenshot-$(date +%Y%m%d-%H%M%S).png"
geom=$(slurp) || exit 0
grim -g "$geom" "$f" && wl-copy < "$f" && notify-send "Screenshot saved" "$f" 2>/dev/null
