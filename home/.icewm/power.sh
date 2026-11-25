#!/bin/bash
# Super+Escape power menu (IceWM). "power.sh windows" goes straight to the Restart-to-Windows confirm.
pick=${1:-}
if [[ $pick != windows ]]; then
  pick=$(printf 'Log out\nLock (n/a)\nSuspend\nRestart\nRestart to Windows\nShut down\n' | rofi -dmenu -i -p "Power") || exit 0
else
  pick="Restart to Windows"
fi
case $pick in
  "Log out") icesh logout ;;
  Suspend) systemctl suspend ;;
  Restart) systemctl reboot ;;
  "Shut down") systemctl poweroff ;;
  "Restart to Windows")
    [[ $(printf 'Cancel\nRestart into Windows\n' | rofi -dmenu -p "Restart into Windows?") == "Restart into Windows" ]] || exit 0
    sudo -n /usr/local/bin/boot-windows-next >/dev/null && systemctl reboot || notify-send -u critical "Restart to Windows" "Couldn't set the Windows boot entry." ;;
esac
