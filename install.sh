#!/bin/bash
# TetOS installer — copies this repo's config onto a stock Omarchy install.
#
#   ./install.sh                 user config only (no sudo)
#   ./install.sh --monitors      also copy hypr/monitors.lua (written for my two screens)
#   ./install.sh --system        also install the dual-boot / session helpers (sudo)
#   ./install.sh --plymouth      also install the TetOS boot splash (sudo, rebuilds initramfs)
#   ./install.sh --all           everything above
#
# Every file that would be overwritten is backed up to ~/.local/state/tetos-backup-<date>/ first.
set -euo pipefail
cd "$(dirname "$(realpath "$0")")"
REPO=$PWD

monitors=0 system=0 plymouth=0
for a in "$@"; do
  case $a in
    --monitors) monitors=1 ;;
    --system) system=1 ;;
    --plymouth) plymouth=1 ;;
    --all) monitors=1 system=1 plymouth=1 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 1 ;;
  esac
done

command -v omarchy >/dev/null || { echo "Omarchy not found — install Omarchy first (https://omarchy.org)." >&2; exit 1; }

BACKUP="$HOME/.local/state/tetos-backup-$(date +%Y%m%d-%H%M%S)"
say() { printf '\e[38;2;228;138;160m==>\e[0m %s\n' "$*"; }

# ---- user files -----------------------------------------------------------
say "Copying config into $HOME (backups in $BACKUP)"
while IFS= read -r -d '' src; do
  rel=${src#home/}
  [[ $monitors == 0 && $rel == .config/hypr/monitors.lua ]] && continue
  dst="$HOME/$rel"
  if [[ -e $dst ]] && ! cmp -s "$src" "$dst"; then
    mkdir -p "$BACKUP/$(dirname "$rel")"
    cp -a "$dst" "$BACKUP/$rel"
  fi
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
done < <(find home -type f -print0)

# Paths in bindings.lua were written for /home/ty.
sed -i "s|/home/ty/|$HOME/|g" "$HOME/.config/hypr/bindings.lua"

# FT Monogrid (kitty font; freeware, non-commercial — see info.txt in the zip).
if ! fc-list | grep -qi monogrid; then
  say "Installing FT Monogrid font"
  mkdir -p "$HOME/.local/share/fonts/ft-monogrid"
  unzip -oq fonts/ft-monogrid-font.zip -d "$HOME/.local/share/fonts/ft-monogrid"
  fc-cache -f "$HOME/.local/share/fonts" >/dev/null
fi

# Splash/lock PNGs are prebuilt, but rebuild them if rsvg-convert is around.
if command -v rsvg-convert >/dev/null; then
  rsvg-convert -z 2 "$HOME/.config/quickshell/tetos-splash/tetos-splash.svg" -o "$HOME/.config/quickshell/tetos-splash/tetos-splash.png" || true
fi

# ---- theme ----------------------------------------------------------------
say "Switching to the TetOS theme"
omarchy theme set tetos || echo "  (couldn't set theme — run: omarchy theme set tetos)"

# ---- wallfx venv (optional, ~1 GB) ---------------------------------------
if [[ ! -x $HOME/.local/share/wallfx/venv/bin/python ]]; then
  say "wallfx: the outline-draw transition needs a ~1 GB venv. Without it, every wallpaper uses the pixel transition."
  read -rp "    Install it now? [y/N] " yn
  [[ ${yn,,} == y ]] && "$HOME/.local/bin/wallfx" instalar || true
fi

# ---- system helpers -------------------------------------------------------
if [[ $system == 1 ]]; then
  say "Installing dual-boot and session helpers (sudo)"
  sudo install -m 755 -o root -g root system/usr/local/bin/* /usr/local/bin/
  sudo install -m 644 system/etc/systemd/system/boot-order-linux-first.service /etc/systemd/system/
  tmp=$(mktemp)
  sed "s/__USER__/$USER/g" system/etc/sudoers.d/tetos > "$tmp"
  if sudo visudo -cf "$tmp" >/dev/null; then
    sudo install -m 440 -o root -g root "$tmp" /etc/sudoers.d/tetos
  else
    echo "  sudoers file failed validation, skipped" >&2
  fi
  rm -f "$tmp"
  if [[ -d /sys/firmware/efi/efivars ]] && efibootmgr 2>/dev/null | grep -q 'Windows Boot Manager'; then
    sudo systemctl daemon-reload
    sudo systemctl enable boot-order-linux-first.service
  else
    echo "  No Windows boot entry found — service installed but not enabled."
  fi
fi

if [[ $plymouth == 1 ]]; then
  say "Installing TetOS Plymouth theme (sudo, rebuilds initramfs)"
  sudo "$REPO/plymouth/install.sh"
fi

# ---- reload ---------------------------------------------------------------
say "Reloading"
hyprctl reload >/dev/null 2>&1 || true
omarchy restart shell >/dev/null 2>&1 || true
pgrep -f 'qs -c wallfx' >/dev/null || (setsid qs -c wallfx >/dev/null 2>&1 &)
say "Done. Replay the splash with: qs -c tetos-splash"
[[ -d $BACKUP ]] && echo "    Old files saved in $BACKUP"
exit 0
