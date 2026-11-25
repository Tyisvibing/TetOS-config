#!/bin/bash
# Drag a region (or click a window) to screenshot it into ~/Pictures/Screenshots.
dir=~/Pictures/Screenshots; mkdir -p "$dir"
f="$dir/screenshot-$(date +%Y%m%d-%H%M%S).png"
magick import "$f" && notify-send "Screenshot saved" "$f" 2>/dev/null
