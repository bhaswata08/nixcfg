local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- General
-- config.font_size = 19
config.line_height = 1.2
config.enable_tab_bar = false
config.window_decorations = "NONE"
config.window_background_opacity = 0.70

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
