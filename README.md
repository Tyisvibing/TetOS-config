# TetOS 4.1 — *Welcome to Kasane Territory*

A Kasane Teto–themed setup for [Omarchy](https://omarchy.org) (Arch + Hyprland). It's a set of config files for a stock Omarchy install, not a separate distro.

<p align="center"><img src="home/.config/quickshell/tetos-splash/tetos-splash.png" width="360" alt="TetOS splash"></p>

## What's in it

| Piece | What it does | Files |
|---|---|---|
| **TetOS theme** | Teto red `#c43552` / pink `#e48aa0` Omarchy theme, plus Teto wallpapers | `~/.config/omarchy/themes/tetos/` |
| **Login splash** | A retro "Welcome to Kasane Territory" box on every screen at login. It fades after 4 s, or click to close it | `~/.config/quickshell/tetos-splash/` |
| **Lock screen** | A retro grey dialog with the TetOS logo, a serif clock and a ChicagoFLF date (plugin `ty.lock`, a copy of `omarchy.lock`) | `~/.config/omarchy/plugins/ty.lock/` |
| **Wallpaper transitions** | Outline-draw / pixel-"contagion" transitions on background change, ported from [pocket-dots](https://github.com/diegoMalagrida/pocket-dots) | `~/.config/quickshell/wallfx/`, `~/.local/bin/wallfx*` |
| **Window look** | 1 px gaps, 2 px square borders, frosted blur, pop-in "overshoot" animations | `~/.config/hypr/looknfeel.lua` |
| **Bar** | Top bar with icon workspaces (custom-workspaces plugin by Jim Cruz, MIT), world clocks and weather | `~/.config/omarchy/shell.json`, `plugins/jcruz.custom-workspaces/` |
| **Branding** | TetOS wordmark in *About*, Teto ASCII art screensaver | `~/.config/omarchy/branding/` |
| **fastfetch** | TetOS logo, boxed sections and a Claude Code usage block | `~/.config/fastfetch/` |
| **Terminals** | kitty with a Teto background image (turned off in Claude/agent windows), plus ghostty/foot/alacritty in VictorMono | `~/.config/{kitty,ghostty,foot,alacritty}/` |
| **Boot splash** | A Plymouth theme with the TetOS logo on purple and a Teto-red progress bar | `plymouth/` |
| **Dual-boot helpers** | Restarts come back to the OS you were last in. `Super+Ctrl+Alt+]` reboots straight into Windows once | `system/` |

## Requirements

- A working **Omarchy** install (this was built on Omarchy with the Lua Hyprland config: `~/.config/hypr/*.lua`)
- An internet connection for packages

## Setup

### 1. Get the repo

```bash
git clone https://github.com/<you>/tetos-config.git ~/tetos-config
cd ~/tetos-config
```

### 2. Install the packages

Needed for TetOS:

```bash
sudo pacman -S --needed $(grep -v '^#' packages/required.txt | awk '{print $1}')
yay -S --needed $(grep -v '^#' packages/aur.txt | awk '{print $1}')
```

The rest of my apps (optional — see [`packages/apps.txt`](packages/apps.txt)):

```bash
grep -v '^#' packages/apps.txt | awk 'NF{print $1}' | xargs yay -S --needed
```

> **FT Monogrid** (the kitty font) isn't in any package repo. It's bundled in `fonts/ft-monogrid-font.zip`, and `install.sh` installs it to `~/.local/share/fonts/`. It's freeware for non-commercial use ([fontspace](https://www.fontspace.com/ft-monogrid-font-f163310)).

### 3. Run the installer

```bash
./install.sh            # user config + theme (no sudo)
./install.sh --all      # also monitors, dual-boot helpers and Plymouth splash
```

| Flag | Adds |
|---|---|
| `--monitors` | `hypr/monitors.lua`. It's set up for **my** screens (ASUS XG248QSG 610 Hz plus an Acer KG272 rotated portrait), so only use it on the same hardware |
| `--system` | `/usr/local/bin` helpers, a sudoers rule, and the `boot-order-linux-first` service (enabled only when a Windows boot entry exists) |
| `--plymouth` | The TetOS boot splash (rebuilds the initramfs) |

The installer:
- backs up every file it overwrites to `~/.local/state/tetos-backup-<date>/`
- rewrites the `/home/ty` paths in `bindings.lua` to your home folder
- runs `omarchy theme set tetos`
- offers to set up the wallfx venv. This is about 1 GB (rembg + onnxruntime + a 210 MB model) and gives the outline-draw transition. Without it, every wallpaper change uses the pixel transition.
- reloads Hyprland and the Omarchy shell

### 4. Log out and back in

You should see the TetOS splash. To show it again: `qs -c tetos-splash`. To preview the lock screen: `omarchy-shell lock preview`.

## Keybindings added

| Keys | Action |
|---|---|
| `Super + Ctrl + W` / `Super + Ctrl + Space` | Background switcher (with wallfx transition) |
| `Super + Alt + A` | Claude Code in kitty |
| `Super + Shift + D` | Discord |
| `Super + Shift + M` | Muse music player |
| `Super + Ctrl + C` | VS Code |
| `Super + Alt + P` | Pulsar (snap) |
| `Ctrl + Shift + Esc` | Mission Center (task manager) |
| `Super + Ctrl + Alt + ]` | Restart to Windows (needs `--system`) |
| `Super + Ctrl + Alt + I` | Switch to IceWM retro session (needs `--system` and `icewm`. This one is shelved) |

The Omarchy menu also gets **System → Restart to Windows**, and its **Background** item goes through wallfx.

## Things to change for your machine

- **Weather** in fastfetch: `~/.config/fastfetch/config.jsonc` → `"location": "London"`. Use `+` in place of spaces (`New+York`), because fastfetch doesn't URL-encode the name.
- **World clocks** in the bar: `~/.config/omarchy/shell.json` → `omarchy.elsewhen.cities`.
- **Dock apps**: `shell.json` → `dock.pinned`.
- **Launcher paths** for Muse / Pulsar / Claude in `~/.config/hypr/bindings.lua` assume they're installed where mine are.

## Dual-boot notes (`--system`)

- `boot-order-linux-first.service` puts Limine first in the UEFI BootOrder at every Linux boot, so a plain restart comes back to Linux.
- `reboot-to-windows` → `sudo boot-windows-next` sets a one-shot UEFI `BootNext` to Windows Boot Manager, then reboots.
- **Windows side** (not in this repo): you need a matching startup task that puts Windows Boot Manager first while you're in Windows, plus a "Restart to Omarchy" shortcut (`bcdedit /set {fwbootmgr} bootsequence {<limine-guid>}`). Without it, restarts from Windows still go to Linux.

## Reverting

```bash
omarchy theme set <another-theme>
# lock screen: remove "ty.lock" from "plugins" and "omarchy.lock" from "disabledPlugins" in shell.json
omarchy restart shell
sudo plymouth-set-default-theme -R omarchy          # boot splash
sudo systemctl disable boot-order-linux-first       # dual-boot service
```

To get your old files back, copy them out of `~/.local/state/tetos-backup-<date>/`.

## Repo layout

```
home/            → copied into $HOME as-is
  .config/hypr, omarchy, quickshell, fastfetch, kitty, ghostty, foot, alacritty, starship.toml
  .local/bin/    wallfx, wallfx-bg-set, wallfx-bg-next, reboot-to-windows, retro-switch
system/          → /usr/local/bin helpers, systemd unit, sudoers template (--system)
plymouth/        → TetOS Plymouth theme (--plymouth)
packages/        → required.txt, aur.txt, apps.txt
fonts/           → FT Monogrid (installed by install.sh)
install.sh
```

## Credits

- Kasane Teto © TWINDRILL. The wallpapers and art here are fan material; they're credited to their artists and not covered by this repo.
- Wallpaper transitions: [pocket-dots](https://github.com/diegoMalagrida/pocket-dots) (license in `quickshell/wallfx/LICENSE`).
- Custom Workspaces bar plugin: Jim Cruz (MIT).
- FT Monogrid font: freeware, non-commercial ([fontspace](https://www.fontspace.com/ft-monogrid-font-f163310)).
- Built on [Omarchy](https://omarchy.org).
