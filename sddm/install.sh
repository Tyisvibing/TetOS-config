#!/bin/bash
# Install the TetOS SDDM (login screen) theme and make it the active one.
#
#   sudo ./sddm/install.sh            install + activate
#   sudo ./sddm/install.sh --revert   go back to the previous theme
#
# The theme is picked with a drop-in (/etc/sddm.conf.d/zz-tetos-theme.conf) instead
# of editing Omarchy's own files, so `omarchy update` never fights with it.
# You only see the login screen if SDDM autologin is off (Omarchy turns it on by
# default, because the disk-encryption password already protects the machine).
set -euo pipefail
[[ $EUID == 0 ]] || { echo "Run with sudo: sudo $0 $*" >&2; exit 1; }

dropin=/etc/sddm.conf.d/zz-tetos-theme.conf

if [[ ${1:-} == --revert ]]; then
  rm -f "$dropin"
  # Older TetOS versions edited Omarchy's files directly; undo that too.
  for f in /etc/sddm.conf.d/10-theme.conf /etc/sddm.conf.d/99-omarchy-login.conf; do
    [[ -f $f ]] && sed -i 's/^Current=tetos$/Current=omarchy/' "$f"
  done
  echo "Reverted. The login screen uses the previous theme again."
  exit 0
fi

command -v sddm >/dev/null || { echo "SDDM is not installed (sudo pacman -S sddm)." >&2; exit 1; }

src="$(dirname "$(readlink -f "$0")")/tetos"
rm -rf /usr/share/sddm/themes/tetos
mkdir -p /usr/share/sddm/themes
cp -r "$src" /usr/share/sddm/themes/
chmod -R a+rX /usr/share/sddm/themes/tetos

mkdir -p /etc/sddm.conf.d
printf '# Written by TetOS (sddm/install.sh). Delete this file to undo.\n[Theme]\nCurrent=tetos\n' >"$dropin"
echo "Installed. Active login theme: tetos"
echo "Test it without logging out: sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/tetos"
