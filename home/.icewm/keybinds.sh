#!/bin/bash
# Super+K: searchable list of IceWM binds (custom keys + window/workspace prefs).
{
  grep -E '^key ' ~/.icewm/keys | sed -E 's/^key +"([^"]+)" +/\1\t/'
  grep -E '^Key[A-Za-z0-9]+="' ~/.icewm/preferences | sed -E 's/^Key(Sys|Win)([A-Za-z0-9]+)="([^"]+)"/\3\t\2/'
} | awk -F'\t' '{printf "%-28s %s\n", $1, $2}' | rofi -dmenu -i -p "Keybinds" >/dev/null
