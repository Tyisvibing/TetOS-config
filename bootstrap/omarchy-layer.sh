#!/bin/bash
# ============================================================================
#  TetOS bootstrap: Omarchy desktop on any Arch-based distro   (EXPERIMENTAL)
# ============================================================================
#
# TetOS is a theme for Omarchy. Omarchy only installs from its own ISO, so on
# another Arch-based distro (Arch, EndeavourOS, CachyOS, Garuda, ...) this
# script adds Omarchy's *desktop layer* on top of what you already have:
#
#   * Omarchy's package repository + signing key
#   * the Omarchy packages (Hyprland, the Omarchy shell, apps, fonts, ...)
#   * Omarchy's default config in your home folder (old files are backed up)
#   * the SDDM login manager
#
# What it deliberately does NOT touch, so your PC keeps booting the way it does now:
#
#   * your boot loader (GRUB / systemd-boot / Limine / rEFInd)
#   * your initramfs setup (mkinitcpio hooks or dracut)
#   * your distro's own package mirrors and repos
#   * your distro's name (/etc/os-release) and /etc/nsswitch.conf
#
# Because of that, these Omarchy features are NOT available after a bootstrap:
# Limine snapshot boot menu, the Plymouth boot splash, and Omarchy's
# disk-encryption login. Everything you see after logging in works.
#
# This has NOT been tested on every distro. Have a backup or snapshot first.
#
# Usage:  ./bootstrap/omarchy-layer.sh          (run as your normal user, NOT with sudo)
#
# Afterwards: reboot, pick "Omarchy (Hyprland uwsm)" at the login screen, then
# run ./install.sh from inside the new desktop.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
OMARCHY_KEY=40DFB630FF42BCFFB047046CF0134EE680CAC571
OMARCHY_SERVER='https://pkgs.omarchy.org/stable/$arch'
STATE=/etc/tetos                     # root-owned: original files + marker
LOG="$HOME/tetos-bootstrap.log"

# Files Omarchy's packages ship that would change how your PC boots. pacman's
# NoExtract keeps them from ever being written, now and on every update.
NOEXTRACT=(
  etc/mkinitcpio.conf.d/00-omarchy-hooks.conf
  etc/mkinitcpio.conf.d/omarchy_hooks.conf
  etc/mkinitcpio.conf.d/omarchy_vconsole.conf
  etc/mkinitcpio.conf.d/thunderbolt_module.conf
  etc/mkinitcpio.conf.d/i2c_hid_of_module.conf
  etc/limine-entry-tool.d/omarchy-defaults.conf
  etc/limine-entry-tool.d/omarchy-uki.conf
)

pink=$'\e[38;2;228;138;160m' red=$'\e[31m' yel=$'\e[33m' bold=$'\e[1m' off=$'\e[0m'
say()  { printf '\n%s==>%s %s%s%s\n' "$pink" "$off" "$bold" "$*" "$off"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s  ! %s%s\n' "$yel" "$*" "$off"; }
die()  { printf '\n%sERROR:%s %s\n' "$red" "$off" "$*" >&2; exit 1; }
yes_no() { local a; read -rp "    $1 [y/N] " a; [[ ${a,,} == y || ${a,,} == yes ]]; }

exec > >(tee -a "$LOG") 2>&1
echo "---- $(date) ----"

# ---------------------------------------------------------------------------
say "Checking this computer"
# ---------------------------------------------------------------------------
[[ $EUID -ne 0 ]] || die "Run this as your normal user, without sudo. It asks for your password when it needs it."
command -v pacman >/dev/null || die "pacman not found: this is not an Arch-based distro."
[[ $(uname -m) == x86_64 ]] || die "Only 64-bit Intel/AMD PCs (x86_64) are supported."
[[ -d /run/systemd/system ]] || die "This distro doesn't use systemd, which Omarchy needs."
[[ -d /sys/firmware/efi ]] || warn "This PC booted in legacy BIOS mode. That's fine for the desktop, but the dual-boot helpers won't work."

# shellcheck disable=SC1091
. /etc/os-release
distro="${PRETTY_NAME:-$ID}"
if [[ -e $STATE/os-release.original || -L $STATE/os-release.original ]]; then
  # A previous run saved this distro's identity (os-release may say Omarchy if that run was cut short).
  info "The TetOS bootstrap ran here before; running it again is safe."
  saved=$STATE/os-release.original
  if [[ -L $saved ]]; then saved=$(readlink "$saved"); [[ $saved == /* ]] || saved="/etc/$saved"; fi
  distro="$(. "$saved" 2>/dev/null; echo "${PRETTY_NAME:-${ID:-this distro}}")" || true
elif [[ $ID == omarchy ]]; then
  echo
  info "This is already Omarchy. You don't need the bootstrap: run ./install.sh instead."
  exit 0
fi
case " ${ID:-} ${ID_LIKE:-} " in
  *" manjaro "*)
    die "Manjaro is not supported. Its packages lag behind Arch's on purpose, and mixing them with
       Omarchy's (built for current Arch) breaks things. Use EndeavourOS, CachyOS or plain Arch." ;;
esac
grep -qE '^\[(core|extra)\]' /etc/pacman.conf || die "/etc/pacman.conf has no [core]/[extra] repos. Is this really Arch-based?"

info "Distro:        $distro"

boot="unknown"
if [[ -d /boot/EFI/limine || -d /efi/EFI/limine || -f /boot/limine.conf || -f /boot/limine/limine.conf ]]; then boot="Limine"
elif [[ -d /boot/grub || -d /boot/grub2 ]]; then boot="GRUB"
elif [[ -d /boot/loader/entries || -d /efi/loader/entries || -d /boot/efi/loader/entries ]]; then boot="systemd-boot"
elif [[ -d /boot/EFI/refind || -d /efi/EFI/refind ]]; then boot="rEFInd"
fi
initramfs="mkinitcpio"; command -v dracut >/dev/null && ! command -v mkinitcpio >/dev/null && initramfs="dracut"
info "Boot loader:   $boot (will not be changed)"
info "Initramfs:     $initramfs (will not be changed)"

dm=""
if [[ -L /etc/systemd/system/display-manager.service ]]; then
  dm=$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)
fi
info "Login manager: ${dm:-none}"

conflicts=()
for p in tlp auto-cpufreq tuned tuned-ppd tealdeer; do pacman -Q "$p" &>/dev/null && conflicts+=("$p"); done

for de in plasma-desktop gnome-shell xfce4-session cinnamon; do
  pacman -Q "$de" &>/dev/null && warn "You also have $de installed. It keeps working, but Omarchy changes some shared settings (fonts, default browser, power button = menu)."
done

sudo -v || die "This needs your password (sudo) to install packages."
curl -fsI "https://pkgs.omarchy.org/stable/x86_64/omarchy.db" >/dev/null 2>&1 ||
  die "Can't reach pkgs.omarchy.org. Check your internet connection."

# ---------------------------------------------------------------------------
say "Here's what will happen"
# ---------------------------------------------------------------------------
cat <<PLAN
    1. Update your whole system first (pacman -Syu).
    2. Trust Omarchy's package signing key and add its repo to /etc/pacman.conf
       (the original is saved as /etc/pacman.conf.pre-tetos).
    3. Install a tiny placeholder package so Omarchy doesn't swap your boot loader
       for Limine, and block Omarchy's initramfs/boot-entry files (NoExtract).
    4. Install Omarchy and its default apps (about 160 packages, a few GB).
    5. Keep $distro's /etc/os-release and /etc/nsswitch.conf (a pacman hook
       puts them back whenever Omarchy's settings package updates).
    6. Copy Omarchy's default config into your home folder. Anything it replaces
       is backed up to ~/.local/state/tetos-bootstrap-backup-<date>/.
    7. Set up the Omarchy lock screen, Bluetooth and the SDDM login screen.

    Not touched: boot loader, initramfs, your repos and mirrors.
    Log file: $LOG
PLAN
if ((${#conflicts[@]})); then
  echo
  warn "These packages conflict with Omarchy's and will be REPLACED: ${conflicts[*]}"
  warn "(power tools are replaced by Omarchy's power-profiles-daemon; tealdeer by tldr)"
fi
echo
echo "    ${bold}This is experimental.${off} Make a backup or snapshot first if you can."
read -rp "    Type ${bold}yes${off} to continue: " answer
[[ $answer == yes ]] || { echo "    Nothing was changed."; exit 1; }

if command -v timeshift >/dev/null; then
  yes_no "Timeshift is installed. Make a snapshot now (recommended)?" &&
    sudo timeshift --create --comments "before TetOS bootstrap" || true
elif command -v snapper >/dev/null && grep -q '^root' <<<"$(sudo snapper list-configs 2>/dev/null || true)"; then
  yes_no "Snapper is set up. Make a snapshot now (recommended)?" &&
    sudo snapper -c root create -d "before TetOS bootstrap" || true
fi

# ---------------------------------------------------------------------------
say "1/7  Updating the system"
# ---------------------------------------------------------------------------
# Plain `pacman -Syu` is refused once Omarchy is installed (it wants `omarchy update`).
info "pacman may ask questions here; pressing Enter picks the default answer."
sudo env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -Syu
sudo pacman -S --needed --noconfirm base-devel git curl

# ---------------------------------------------------------------------------
say "2/7  Adding Omarchy's package repository"
# ---------------------------------------------------------------------------
if ! sudo pacman-key --list-keys "$OMARCHY_KEY" &>/dev/null; then
  if ! sudo pacman-key --recv-keys "$OMARCHY_KEY" --keyserver keys.openpgp.org; then
    info "Keyserver unreachable, using the copy of the key in this repo."
    grep -q "^fpr:::::::::$OMARCHY_KEY:" <<<"$(gpg --show-keys --with-colons "$HERE/omarchy.gpg" 2>/dev/null || true)" ||
      die "bootstrap/omarchy.gpg doesn't contain the expected Omarchy key."
    sudo pacman-key --add "$HERE/omarchy.gpg"
  fi
fi
sudo pacman-key --lsign-key "$OMARCHY_KEY"

sudo install -d -m 755 "$STATE"
[[ -e /etc/pacman.conf.pre-tetos ]] || sudo cp -a /etc/pacman.conf /etc/pacman.conf.pre-tetos

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp /etc/pacman.conf "$tmp/pacman.conf"
if ! grep -q '^# TetOS bootstrap: NoExtract' "$tmp/pacman.conf"; then
  awk -v line="NoExtract = ${NOEXTRACT[*]}" '
    { print }
    /^\[options\]/ && !done {
      print "# TetOS bootstrap: NoExtract keeps Omarchy from changing how this PC boots"
      print line
      done = 1
    }' "$tmp/pacman.conf" >"$tmp/p2" && mv "$tmp/p2" "$tmp/pacman.conf"
fi
if ! grep -q '^\[omarchy\]' "$tmp/pacman.conf"; then
  # Omarchy's repo goes first, like on Omarchy itself, so its builds (quickshell, yay, ...) win.
  awk -v server="$OMARCHY_SERVER" '
    /^\[/ && $0 != "[options]" && !done {
      print "# TetOS bootstrap: Omarchy package repo (original file: /etc/pacman.conf.pre-tetos)"
      print "[omarchy]"
      print "SigLevel = Required DatabaseOptional"
      print "Server = " server
      print ""
      done = 1
    }
    { print }' "$tmp/pacman.conf" >"$tmp/p2" && mv "$tmp/p2" "$tmp/pacman.conf"
fi
sudo install -m 644 "$tmp/pacman.conf" /etc/pacman.conf
sudo pacman -Sy
sudo pacman -S --needed --noconfirm omarchy-keyring

# ---------------------------------------------------------------------------
say "3/7  Keeping your boot loader"
# ---------------------------------------------------------------------------
# The omarchy package depends on Limine's boot tools. Installing those would deploy
# Limine to your EFI partition and take over kernel installs. A placeholder package
# that "provides" them satisfies the dependency without touching anything.
# Versioned high so a future "limine-mkinitcpio-hook>=X" dependency is still met by the
# placeholder instead of pulling in the real thing.
shim_provides=()
for p in limine-mkinitcpio-hook limine-entry-tool limine-snapper-sync; do
  pacman -Q "$p" &>/dev/null || shim_provides+=("$p=9999")
done
if pacman -Q limine-mkinitcpio-hook &>/dev/null; then
  info "Limine's boot tools are already installed here (your distro uses them), so they stay."
fi
if ((${#shim_provides[@]})) && ! pacman -Q tetos-boot-shim &>/dev/null; then
  mkdir -p "$tmp/shim"
  cat >"$tmp/shim/PKGBUILD" <<EOF
pkgname=tetos-boot-shim
pkgver=1
pkgrel=1
pkgdesc="TetOS bootstrap: stands in for Omarchy's Limine boot tools so this distro's own boot loader is left alone"
arch=(any)
license=(MIT)
provides=(${shim_provides[*]})
options=(!debug !strip)
package() { :; }
EOF
  (cd "$tmp/shim" && PKGDEST="$tmp/shim" makepkg -f --noconfirm >/dev/null)
  sudo pacman -U --noconfirm "$tmp"/shim/tetos-boot-shim-*.pkg.tar*
  info "Installed tetos-boot-shim (provides: ${shim_provides[*]})"
fi

# ---------------------------------------------------------------------------
say "4/7  Installing Omarchy (this takes a while)"
# ---------------------------------------------------------------------------
# Save this distro's identity before omarchy-settings overwrites it.
for f in os-release nsswitch.conf; do
  [[ -e $STATE/$f.original ]] || sudo cp -a "/etc/$f" "$STATE/$f.original"
done
sudo install -d /usr/local/lib/tetos /etc/pacman.d/hooks
sudo tee /usr/local/lib/tetos/restore-etc >/dev/null <<'EOF'
#!/bin/bash
# TetOS bootstrap: Omarchy's settings package replaces these on every install/update.
for f in os-release nsswitch.conf; do
  [[ -e /etc/tetos/$f.original || -L /etc/tetos/$f.original ]] || continue
  rm -f "/etc/$f"
  cp -a "/etc/tetos/$f.original" "/etc/$f"
done
EOF
sudo chmod 755 /usr/local/lib/tetos/restore-etc
sudo tee /etc/pacman.d/hooks/zz-tetos-keep-distro-files.hook >/dev/null <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = omarchy-settings

[Action]
Description = TetOS: keeping this distro's os-release and nsswitch.conf...
When = PostTransaction
Exec = /usr/local/lib/tetos/restore-etc
EOF

# --ask 4 answers "yes" to replacing conflicting packages, as Omarchy's own installer does.
sudo env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -S --needed --noconfirm --ask 4 omarchy

export OMARCHY_PATH=/usr/share/omarchy
export OMARCHY_INSTALL=$OMARCHY_PATH/install
export PATH="$OMARCHY_PATH/bin:$PATH"

mapfile -t defaults < <(omarchy-pkg-defaults)
((${#defaults[@]})) || die "omarchy-pkg-defaults returned no packages; see $LOG"
info "Installing ${#defaults[@]} Omarchy default packages"
sudo env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -S --needed --noconfirm --ask 4 "${defaults[@]}"

# ---------------------------------------------------------------------------
say "5/7  System setup (lock screen, login screen, Bluetooth)"
# ---------------------------------------------------------------------------
# Only the parts of Omarchy's installer that don't touch booting, networking or
# your package mirrors. Each runs as root with the same environment the ISO uses.
root_steps=(
  config/theme-system.sh
  config/browser-policy.sh
  config/increase-lockout-limit.sh
  config/lockscreen-pam.sh
  login/sddm.sh
  hardware/bluetooth.sh
  post-install/udev.sh
  post-install/localdb.sh
)
for step in "${root_steps[@]}"; do
  if [[ -f $OMARCHY_INSTALL/$step ]]; then
    info "$step"
    sudo env OMARCHY_PATH="$OMARCHY_PATH" OMARCHY_INSTALL="$OMARCHY_INSTALL" OMARCHY_INSTALL_USER="$USER" \
      PATH="$OMARCHY_PATH/bin:/usr/local/sbin:/usr/local/bin:/usr/bin" \
      bash -e "$OMARCHY_INSTALL/$step" || warn "$step failed (continuing)"
  else
    warn "$step not found in this Omarchy version, skipped"
  fi
done
sudo systemctl enable power-profiles-daemon.service 2>/dev/null || true

# Login manager: TetOS's login screen is an SDDM theme.
if [[ $dm == sddm ]]; then
  info "SDDM is already your login manager."
elif [[ -z $dm ]]; then
  sudo systemctl enable sddm.service
  info "Enabled SDDM."
else
  echo
  info "Your login manager is $dm. TetOS's login screen needs SDDM."
  if yes_no "Switch from $dm to SDDM?"; then
    sudo systemctl disable "$dm.service"
    sudo systemctl enable sddm.service
    info "Switched. Undo later with: sudo systemctl disable sddm && sudo systemctl enable $dm"
  else
    info "Kept $dm. Pick \"Omarchy (Hyprland uwsm)\" from its session menu when you log in."
  fi
fi

# ---------------------------------------------------------------------------
say "6/7  Omarchy config for $USER"
# ---------------------------------------------------------------------------
backup="$HOME/.local/state/tetos-bootstrap-backup-$(date +%Y%m%d-%H%M%S)"
while IFS= read -r -d '' src; do
  rel=${src#/etc/skel/}
  dst="$HOME/$rel"
  if [[ -e $dst && ! -d $dst ]] && ! cmp -s "$src" "$dst"; then
    mkdir -p "$backup/$(dirname "$rel")"
    cp -a "$dst" "$backup/$rel"
  fi
done < <(find /etc/skel \( -type f -o -type l \) -print0)
cp -a /etc/skel/. "$HOME/"
[[ -d $backup ]] && info "Your previous versions of those files are in $backup"

# --first-install also marks Omarchy's upgrade migrations as done, so the first
# `omarchy update` doesn't try to "upgrade" a system that was never an older Omarchy.
omarchy-provision-user --first-install || warn "Some per-user Omarchy steps failed; see $LOG"

# ---------------------------------------------------------------------------
say "7/7  Finishing"
# ---------------------------------------------------------------------------
sudo tee "$STATE/bootstrap" >/dev/null <<EOF
# Written by TetOS bootstrap/omarchy-layer.sh. install.sh reads this.
date=$(date -Iseconds)
user=$USER
distro=$distro
boot_loader=$boot
EOF

cat <<DONE

${pink}${bold}Omarchy's desktop is installed on $distro.${off}

  Next:
    1. Restart:            sudo reboot
    2. At the login screen pick the session ${bold}Omarchy (Hyprland uwsm)${off} and log in.
    3. Open a terminal (${bold}Super + Enter${off}) and run:
         cd $(dirname "$HERE") && ./install.sh

  From now on, update with ${bold}omarchy update${off} (plain "pacman -Syu" is blocked by Omarchy).

  Log of everything above: $LOG
DONE
