{
  config,
  ...
}:
{
  imports = [
    ./configs/theming/misc.nix
    ./configs/theming/niri.nix
    ./configs/theming/waybar.nix
    ./configs/theming/noctalia.nix
    ./configs/anyrun.nix
    ./configs/fastfetch.nix
    ./configs/nushell.nix
    ./configs/programs.nix
    ./configs/starship.nix
    ./configs/xdg-defaults.nix
  ];
  gtk.gtk4.theme = config.gtk.theme;
  home.username = "bhaswata";
  home.homeDirectory = "/home/bhaswata";
  home.stateVersion = "25.11";
}
