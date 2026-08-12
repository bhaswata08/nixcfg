{
  config,
  ...
}:
{
  imports = [
    ./configs/theming/misc.nix
    ./configs/theming/niri.nix
    ./configs/theming/noctalia.nix
    ./configs/theming/themes.nix
    ./configs/claude.nix
    ./configs/nushell.nix
    ./configs/nvim.nix
    ./configs/obsidian.nix
    ./configs/herdr.nix
    ./configs/wezterm.nix
    ./configs/programs.nix
    ./configs/rofi.nix
    ./configs/starship.nix
    ./configs/xdg-defaults.nix
    ./configs/zen.nix
  ];
  gtk.gtk4.theme = config.gtk.theme;
  home.username = "bhaswata";
  home.homeDirectory = "/home/bhaswata";
  home.stateVersion = "25.11";
}
