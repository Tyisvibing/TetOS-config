#!/bin/bash
# Install the TetOS Plymouth theme and rebuild the initramfs.
# Revert: sudo plymouth-set-default-theme -R omarchy
set -e
cp -r "$(dirname "$0")/tetos" /usr/share/plymouth/themes/
plymouth-set-default-theme -R tetos
