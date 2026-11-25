#!/bin/bash
# TetOS installer: puts the TetOS look onto Omarchy.
#
#   ./install.sh             guided: installs the essentials, then asks about each optional part
#   ./install.sh --all       everything except --monitors, no questions
#   ./install.sh --minimal   only the essentials, no questions
#
# Turn on single parts without being asked:
#   --apps        my other apps (packages/apps.txt)
#   --sessions    Mango + IceWM as extra sessions at the login screen (packages/sessions.txt)
#   --build       build my own apps: knobs (config editor) and muse-tui (terminal music player)
#   --sddm        TetOS login screen                              (sudo)
#   --plymouth    TetOS boot splash, real Omarchy installs only   (sudo)
#   --system      dual-boot helpers, only useful next to Windows  (sudo)
#   --wallfx      the ~1 GB "outline draw" wallpaper transition
#   --monitors    MY monitor layout (ASUS 610 Hz + portrait Acer): only for identical screens!
#   --no-packages don't install any packages (configs only)
#
# Every file that would be overwritten is backed up to ~/.local/state/tetos-backup-<date>/ first.
set -euo pipefail
cd "$(dirname "$(realpath "$0")")"
REPO=$PWD

declare -A want=([packages]=yes [apps]=ask [sessions]=ask [build]=ask [sddm]=ask [plymouth]=ask [system]=ask [wallfx]=ask [monitors]=no)
for a in "$@"; do
  case $a in
    --apps | --sessions | --build | --sddm | --plymouth | --system | --wallfx | --monitors) want[${a#--}]=yes ;;
    --no-packages) want[packages]=no ;;
    --all) for k in apps sessions build sddm plymouth system wallfx; do want[$k]=yes; done ;;
    --minimal) for k in apps sessions build sddm plymouth system wallfx; do [[ ${want[$k]} == ask ]] && want[$k]=no; done ;;
    -h | --help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $a (see ./install.sh --help)" >&2; exit 1 ;;
  esac
done

pink=$'\e[38;2;228;138;160m' yel=$'\e[33m' bold=$'\e[1m' off=$'\e[0m'
say()  { printf '\n%s==>%s %s%s%s\n' "$pink" "$off" "$bold" "$*" "$off"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s  ! %s%s\n' "$yel" "$*" "$off"; }
# wants <part> <question>: yes/no from the flags, or ask (default No).
wants() {
  case ${want[$1]} in
    yes) return 0 ;;
    no) return 1 ;;
  esac
  [[ -t 0 ]] || return 1
  local a
  read -rp "$(printf '\n%s?%s %s [y/N] ' "$pink" "$off" "$2")" a
  [[ ${a,,} == y || ${a,,} == yes ]]
}
pkglist() { grep -v '^\s*#' "$1" | sed 's/#.*//' | awk 'NF{print $1}'; }

# ---- checks ----------------------------------------------------------------
[[ $EUID -ne 0 ]] || { echo "Run ./install.sh as your normal user, not with sudo. It asks for your password when it needs it." >&2; exit 1; }
if ! command -v omarchy >/dev/null; then
  cat >&2 <<'EOF'
Omarchy isn't installed, and TetOS is a theme for Omarchy.

  * Easiest: install Omarchy from its ISO (https://omarchy.org), then run ./install.sh
  * Already on another Arch-based distro (Arch, EndeavourOS, CachyOS, ...)?
    Run the experimental bootstrap first:   ./bootstrap/omarchy-layer.sh

The step-by-step guide is in GUIDE.md.
EOF
  exit 1
fi

if [[ -f /etc/tetos/bootstrap ]]; then mode=bootstrap
elif grep -q '^ID=omarchy' /etc/os-release 2>/dev/null; then mode=omarchy
else mode=other
fi

windows=0
if [[ -d /sys/firmware/efi/efivars ]] && command -v efibootmgr >/dev/null && grep -q 'Windows Boot Manager' <<<"$(efibootmgr 2>/dev/null || true)"; then
  windows=1
fi

say "TetOS installer"
info "System: $( [[ $mode == omarchy ]] && echo "Omarchy" || echo "Omarchy desktop on another Arch distro ($mode)")"
[[ $mode == omarchy ]] || { want[plymouth]=no; }
[[ $windows == 1 || ${want[system]} == yes ]] || want[system]=no

# Ask everything up front, so the rest can run without you watching.
declare -A pick=()
wants apps     "Also install my other apps (VS Code, Steam, OBS, Opera, ...)? See packages/apps.txt" && pick[apps]=1
wants sessions "Add Mango and IceWM as extra sessions you can pick at the login screen?"             && pick[sessions]=1
wants build    "Build my own apps: knobs (config editor) and muse-tui (terminal music player)?"     && pick[build]=1
wants sddm     "Install the TetOS login screen (SDDM theme)? Needs your password"                 && pick[sddm]=1
wants plymouth "Install the TetOS boot splash (Plymouth)? Needs your password"                    && pick[plymouth]=1
wants system   "Windows found: install the dual-boot helpers (restart into Windows key)?"         && pick[system]=1
wants wallfx   "Install the 'outline draw' wallpaper transition? (~1 GB download)"               && pick[wallfx]=1
[[ ${want[monitors]} == yes ]] && pick[monitors]=1

# ---- packages ----------------------------------------------------------------
if [[ ${want[packages]} == yes ]]; then
  say "Installing the packages TetOS needs"
  mapfile -t repo_pkgs < <(pkglist packages/required.txt)
  mapfile -t aur_pkgs < <(pkglist packages/aur.txt)
  if [[ -n ${pick[sessions]:-} ]]; then mapfile -t -O "${#repo_pkgs[@]}" repo_pkgs < <(pkglist packages/sessions.txt); fi
  if [[ -n ${pick[apps]:-} ]]; then
    mapfile -t -O "${#repo_pkgs[@]}" repo_pkgs < <(grep -v '^\s*#' packages/apps.txt | grep -v '# AUR' | sed 's/#.*//' | awk 'NF{print $1}')
    mapfile -t -O "${#aur_pkgs[@]}" aur_pkgs < <(grep -v '^\s*#' packages/apps.txt | grep '# AUR' | awk 'NF{print $1}')
  fi
  # Skip anything this system's repos don't have (e.g. steam without [multilib])
  # instead of letting one missing name cancel the whole install.
  declare -A available=()
  while read -r name; do available[$name]=1; done < <(pacman -Slq 2>/dev/null || true)
  installable=() missing=()
  for p in "${repo_pkgs[@]}"; do
    if [[ -n ${available[$p]:-} ]] || pacman -Qq "$p" &>/dev/null; then installable+=("$p"); else missing+=("$p"); fi
  done
  ((${#missing[@]})) && warn "Not in your package repos, skipped: ${missing[*]}"
  if ((${#installable[@]})); then
    sudo pacman -S --needed --noconfirm "${installable[@]}" ||
      warn "pacman couldn't install everything. Continuing with the config; fix the error above and re-run ./install.sh."
  fi
  if command -v yay >/dev/null; then
    yay -S --needed --noconfirm "${aur_pkgs[@]}" || warn "Some AUR packages failed: ${aur_pkgs[*]} (try again later with yay -S <name>)"
  else
    warn "yay isn't installed, so these AUR packages were skipped: ${aur_pkgs[*]}"
  fi
fi

# ---- user files ---------------------------------------------------------------
BACKUP="$HOME/.local/state/tetos-backup-$(date +%Y%m%d-%H%M%S)"
say "Copying config into $HOME"
while IFS= read -r -d '' src; do
  rel=${src#home/}
  [[ -z ${pick[monitors]:-} && $rel == .config/hypr/monitors.lua ]] && continue
  dst="$HOME/$rel"
  if [[ -e $dst ]] && ! cmp -s "$src" "$dst"; then
    mkdir -p "$BACKUP/$(dirname "$rel")"
    cp -a "$dst" "$BACKUP/$rel"
  fi
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
  # Some launchers were written with my home folder in them.
  if [[ $HOME != /home/ty ]] && grep -Iq '/home/ty/' "$dst" 2>/dev/null; then
    sed -i "s|/home/ty/|$HOME/|g" "$dst"
  fi
done < <(find home -type f -print0)
[[ -d $BACKUP ]] && info "Your old versions are saved in $BACKUP"

# Bundled fonts: DepartureMono Nerd Font (terminals; SIL OFL) and FT Monogrid
# (freeware, non-commercial; see info.txt in its zip).
if command -v unzip >/dev/null; then
  fonts_added=0
  # Captured first: with pipefail, "fc-list | grep -q" can fail on SIGPIPE even when it matches.
  installed_fonts=$(fc-list 2>/dev/null || true)
  if ! grep -q 'DepartureMono Nerd Font' <<<"$installed_fonts"; then
    info "Installing the DepartureMono Nerd Font"
    mkdir -p "$HOME/.local/share/fonts/departure-mono"
    unzip -oq fonts/departure-mono-nerd-font.zip -d "$HOME/.local/share/fonts/departure-mono"
    fonts_added=1
  fi
  if ! grep -qi monogrid <<<"$installed_fonts"; then
    info "Installing the FT Monogrid font"
    mkdir -p "$HOME/.local/share/fonts/ft-monogrid"
    unzip -oq fonts/ft-monogrid-font.zip -d "$HOME/.local/share/fonts/ft-monogrid"
    fonts_added=1
  fi
  ((fonts_added)) && fc-cache -f "$HOME/.local/share/fonts" >/dev/null
fi

# The splash PNG is prebuilt, but rebuild it from the SVG when rsvg-convert is around.
if command -v rsvg-convert >/dev/null; then
  rsvg-convert -z 2 "$HOME/.config/quickshell/tetos-splash/tetos-splash.svg" -o "$HOME/.config/quickshell/tetos-splash/tetos-splash.png" || true
fi

# ---- theme ----------------------------------------------------------------------
say "Switching to the TetOS theme"
omarchy theme set tetos || warn "Couldn't set the theme. Run this later from the desktop: omarchy theme set tetos"

# ---- optional parts ---------------------------------------------------------------
if [[ -n ${pick[wallfx]:-} && ! -x $HOME/.local/share/wallfx/venv/bin/python ]]; then
  say "Setting up the wallfx outline transition (~1 GB, takes a few minutes)"
  "$HOME/.local/bin/wallfx" instalar || warn "wallfx setup failed. Wallpapers still change, with the pixel transition."
fi

if [[ -n ${pick[sddm]:-} ]]; then
  say "Installing the TetOS login screen"
  sudo "$REPO/sddm/install.sh" || warn "Login screen install failed."
  if grep -rqs '^User=' /etc/sddm.conf.d/ /etc/sddm.conf 2>/dev/null; then
    info "Autologin is on, so you won't normally see it. GUIDE.md explains how to turn autologin off."
  fi
fi

if [[ -n ${pick[plymouth]:-} ]]; then
  say "Installing the TetOS boot splash (rebuilds the initramfs, takes a minute)"
  sudo "$REPO/plymouth/install.sh" || warn "Boot splash install failed."
elif [[ $mode != omarchy && ${want[plymouth]} == no ]]; then
  info "(Boot splash skipped: it's only installed on real Omarchy, so your distro's boot setup stays untouched.)"
fi

if [[ -n ${pick[system]:-} ]]; then
  say "Installing the dual-boot helpers"
  sudo pacman -S --needed --noconfirm efibootmgr
  sudo install -m 755 -o root -g root system/usr/local/bin/* /usr/local/bin/
  sudo install -m 644 system/etc/systemd/system/boot-order-linux-first.service /etc/systemd/system/
  tmp=$(mktemp)
  sed "s/__USER__/$USER/g" system/etc/sudoers.d/tetos >"$tmp"
  if sudo visudo -cf "$tmp" >/dev/null; then
    sudo install -m 440 -o root -g root "$tmp" /etc/sudoers.d/tetos
  else
    warn "The sudoers rule failed validation, skipped."
  fi
  rm -f "$tmp"
  sudo systemctl daemon-reload
  if [[ $windows == 1 ]]; then
    sudo systemctl enable boot-order-linux-first.service
  else
    info "No Windows boot entry found, so the boot-order service is installed but not enabled."
  fi
fi

if [[ -n ${pick[build]:-} ]]; then
  say "Building knobs (config editor)"
  sudo pacman -S --needed --noconfirm base-devel qt6-base qt6-declarative qt6-wayland xdg-desktop-portal
  (cd apps/knobs && ./bin/install --noconfirm) || warn "knobs failed to build. See apps/knobs/README.md."
  say "Building muse-tui (terminal music player)"
  sudo pacman -S --needed --noconfirm go ffmpeg sqlite
  (cd apps/muse-tui && go build -o muse-tui . && install -Dm755 muse-tui "$HOME/.local/bin/muse-tui" && rm -f muse-tui) ||
    warn "muse-tui failed to build. See apps/muse-tui/README.md."
fi

# ---- reload -----------------------------------------------------------------------
say "Reloading the desktop"
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl reload >/dev/null 2>&1 || true
  omarchy restart shell >/dev/null 2>&1 || true
  pgrep -f 'qs -c wallfx' >/dev/null || (setsid qs -c wallfx >/dev/null 2>&1 &)
else
  info "Not inside the desktop right now; everything applies the next time you log in."
fi

cat <<DONE

${pink}${bold}TetOS is installed.${off}
    Log out and back in (Super + Escape > Log out) to see the login splash.
    Show the splash again any time:   qs -c tetos-splash
    Preview the lock screen:          omarchy-shell lock preview
    Keyboard shortcuts:               Super + K
DONE
[[ -d $BACKUP ]] && echo "    Your old config files:            $BACKUP"
exit 0
