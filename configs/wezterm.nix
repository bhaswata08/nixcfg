{
  ...
}:
{
  # WezTerm config. Colors are generated dynamically from the wallpaper by
  # wallust: .wezterm.lua reads ~/.config/wallust/wezterm/colors-wezterm.toml,
  # which wallust renders from the template below (wired via wallust.toml).
  home.file.".wezterm.lua".source = ./wezterm/wezterm.lua;

  xdg.configFile."wallust/wallust.toml".source = ./wezterm/wallust.toml;
  xdg.configFile."wallust/templates/wallust/colors-wezterm.toml".source =
    ./wezterm/templates/wallust/colors-wezterm.toml;
}
