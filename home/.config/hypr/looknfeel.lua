-- Change the default Omarchy look'n'feel.

-- Opt another application in to Omarchy's standard transparency.
-- Find its class with: hyprctl clients
-- o.transparent_window("my-app")
-- o.transparent_window("my-app", "0.9 0.85") -- Custom active/inactive opacity.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Claude / agent terminals: fully opaque so the wallpaper doesn't bleed through the text.
o.window({ class = "org\\.omarchy\\.(agent|claude)" }, { opacity = "1.0 override 1.0 override" })

-- TetOS window styling (2026-11-22)
hl.config({
  general = {
    gaps_in = 1,
    gaps_out = 0,
    border_size = 2,
  },
  decoration = {
    rounding = 0,
    dim_inactive = false,
    dim_strength = 0.15,
  },
})

-- Blur + animations (2026-11-22)
-- Frosted blur behind see-through windows, menus and the bar.
hl.config({
  decoration = {
    blur = {
      enabled = true,
      size = 3,
      passes = 2,
      new_optimizations = true,
      xray = false,
      noise = 0.02,
      contrast = 1.0,
      brightness = 0.85,
      vibrancy = 0.25,
      popups = true,
      special = true,
    },
  },
})

-- A little overshoot so windows "pop" into place.
hl.curve("overshot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.08 } } })

hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.5, bezier = "overshot", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2.5, bezier = "overshot", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.2, bezier = "easeOutQuint", style = "popin 80%" })
-- Workspaces slide left/right; the scratchpad slides down from the top.
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.5, bezier = "easeOutQuint", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2.5, bezier = "easeOutQuint", style = "slidevert" })
-- Menus and launcher slide in slightly instead of only fading.
hl.animation({ leaf = "layersIn", enabled = true, speed = 2.5, bezier = "easeOutQuint", style = "slide" })
-- Speed up Omarchy's base window/layer/fade animations too (speed = tenths of a second; lower is faster).
hl.animation({ leaf = "windows", enabled = true, speed = 2.5, bezier = "easeOutQuint" })
hl.animation({ leaf = "layers", enabled = true, speed = 2.5, bezier = "easeOutQuint" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.2, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.0, bezier = "almostLinear" })
