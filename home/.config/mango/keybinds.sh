#!/bin/bash
# Super+K: searchable list of Mango binds (like Omarchy's keybindings menu).
grep -E '^(bind|mousebind)=' ~/.config/mango/config.conf | sed -E 's/^(bind|mousebind)=//; s/code:1([0-8])/\1+1/' |
  awk -F, '{mods=$1; key=$2; $1=$2=""; sub(/^ +/,""); printf "%-22s %-14s %s\n", mods, key, $0}' |
  rofi -dmenu -i -p "Keybinds" >/dev/null
