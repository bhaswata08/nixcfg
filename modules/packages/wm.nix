{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    wallust
    # Bound to XF86MonBrightnessUp/Down in configs/theming/niri.nix, which had
    # no matching package, so the brightness keys did nothing.
    brightnessctl
    xwayland-satellite
    wezterm
    awww
    fastfetch
    hyprpolkitagent
    wlogout
    papirus-icon-theme
    pipes
    sunsetr
    wl-kbptr
    wlrctl
    noctalia-qs
    catppuccin-cursors.mochaDark
    (catppuccin-gtk.override {
      variant = "mocha";
      accents = [ "mauve" ];
    })
  ];

  programs.niri.enable = true;

}
