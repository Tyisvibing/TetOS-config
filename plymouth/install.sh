#!/bin/bash
# Install the TetOS Plymouth (boot splash) theme and rebuild the initramfs.
# Only for real Omarchy installs: on other distros the boot chain is left alone.
# Revert: sudo plymouth-set-default-theme -R omarchy
set -euo pipefail
[[ $EUID == 0 ]] || { echo "Run with sudo: sudo $0" >&2; exit 1; }
command -v plymouth-set-default-theme >/dev/null || { echo "Plymouth is not installed." >&2; exit 1; }
cp -r "$(dirname "$(readlink -f "$0")")/tetos" /usr/share/plymouth/themes/
plymouth-set-default-theme -R tetos
