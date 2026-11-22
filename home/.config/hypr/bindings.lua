-- Keep only your personal keybinding overrides here. Add new bindings with
-- o.bind or replace defaults with o.rebind.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding. o.rebind takes the same arguments as o.bind.
-- This example replaces the default file manager with Flea.
-- o.rebind("SUPER + SHIFT + F", "File manager", { launch = "flea" })

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, { panel = "omarchy.emojis" })

o.rebind("SUPER + CTRL + C", "VS Code", { launch = "code" })
o.bind("SUPER + SHIFT + D", "Discord", { launch = "discord" })

-- pocket-dots wallpaper transitions (wallfx). Was: the stock Background switcher.
o.rebind("SUPER + CTRL + W", "Background switcher", 'background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && ~/.local/bin/wallfx-bg-set "$background"')
o.rebind("SUPER + CTRL + SPACE", "Background switcher", 'background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && ~/.local/bin/wallfx-bg-set "$background"')

-- Retro desktop: log out and switch to the IceWM session (same combo switches back).
o.bind("SUPER + CTRL + ALT + I", "Switch to retro IceWM desktop", "~/.local/bin/retro-switch icewm")

-- Claude Code in a terminal.
o.bind("SUPER + ALT + A", "Claude Code", "setsid uwsm-app -- kitty --class=org.omarchy.claude -o background_image=none -e /home/ty/.local/share/mise/command-wrappers/bin/claude")

-- Muse music player (focus if already open). Was: Spotify.
o.rebind("SUPER + SHIFT + M", "Muse", { launch = "/home/ty/.local/share/muse/app/muse-player", focus = "^muse-player$" })

-- Mission Center task manager, on the Windows Task Manager key (focus if already open).
o.bind("CTRL + SHIFT + ESCAPE", "Task manager", { launch = "missioncenter", focus = "^io.missioncenter.MissionCenter$" })

-- Restart straight into Windows (asks first). Super+Alt+] is the webcam overlay, so this adds Ctrl.
o.bind("SUPER + CTRL + ALT + BRACKETRIGHT", "Restart to Windows", "~/.local/bin/reboot-to-windows")

-- Pulsar editor (snap). Forced onto XWayland: the strict snap cannot reach the Wayland socket on Arch.
o.bind("SUPER + ALT + P", "Pulsar", { launch = "/var/lib/snapd/snap/bin/pulsar-edit --ozone-platform=x11", focus = "^Pulsar$" })
