local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- General
-- Report keys with the kitty keyboard protocol (CSI u) instead of legacy control
-- bytes, for apps that ask for it. Without this, Ctrl+/ arrives as the bare byte
-- 0x1f, which is also Ctrl+_; Herdr decodes that to the unshifted base key and
-- forwards Ctrl+- to Neovim, so Comment.nvim's Ctrl+/ mapping never fires. CSI u
-- carries the real key, so Neovim sees <C-/>.
config.enable_kitty_keyboard = true
-- config.font_size = 19
config.line_height = 1.2
config.enable_tab_bar = false
config.window_decorations = "NONE"
-- Background alpha only; glyphs stay fully opaque. niri pins this window to
-- opacity 1.0 (configs/theming/niri.nix) so this is the single place terminal
-- transparency is set. Below ~0.8 the wallpaper shows through the text enough
-- to hurt on a light background.
config.window_background_opacity = 0.88

-- Render on the integrated GPU. wgpu picks the highest-performance adapter,
-- which here is the discrete RTX 3060, but niri composites on the Intel iGPU;
-- the cross-GPU buffer handoff yields empty frames, so the window shows only
-- the blurred wallpaper behind it and no text at all. Pinning the adapter to
-- the iGPU keeps the surface on the same device the compositor uses.
config.front_end = "WebGpu"
for _, gpu in ipairs(wezterm.gui.enumerate_gpus()) do
  if gpu.backend == "Vulkan" and gpu.device_type == "IntegratedGpu" then
    config.webgpu_preferred_adapter = gpu
    break
  end
end

-- COLORS
local function load_wal_colors()
  local home = os.getenv("HOME")
  local wal_file = home .. "/.config/wallust/wezterm/colors-wezterm.toml"
  -- wezterm.color.load_scheme reads a TOML color scheme file
  local ok, scheme = pcall(wezterm.color.load_scheme, wal_file)
  if ok then
    return scheme
  end
  return nil
end

local wal = load_wal_colors()
if wal then
  config.colors = wal
end
wezterm.add_to_config_reload_watch_list(os.getenv("HOME") .. "/.config/wallust/wezterm/colors-wezterm.toml")


config.keys = {
    {
        key = 'w',
        mods = 'CTRL',
        action = wezterm.action.CloseCurrentPane { confirm = false },
    },
    {
        key = 'd',
        mods = 'SUPER',
        action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' },
    },
    {
        key = 'd',
        mods = 'SUPER|SHIFT',
        action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' },
    },
    {
      key = 'V',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.PasteFrom 'Clipboard',
    },
    {
      key = 'C',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.CopyTo 'Clipboard',
    }
}

return config
