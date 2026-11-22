#!/bin/bash
# Emits kitty config. Agent/Claude windows (by --class / --app-id) get no background image.
# kitty runs this via `geninclude`; the parent is either the kitty instance itself or its
# config-watcher (`kitten __watch_conf__ <kitty-pid> ...`) during a live reload.
pid=$PPID
read -r -d '' -a argv < <(tr '\0' '\n' < /proc/$pid/cmdline 2>/dev/null)
[[ ${argv[1]:-} == __watch_conf__ ]] && pid=${argv[2]}
cmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
if [[ $cmd == *org.omarchy.agent* || $cmd == *org.omarchy.claude* ]]; then
  echo "background_image none"
  echo "background_opacity 0.75"
fi
