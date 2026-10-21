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
    kitty
    awww
    fastfetch
    hyprpolkitagent
    wlogout
    papirus-icon-theme
    pipes
    sunsetr
    wl-kbptr
    wlrctl
    # No noctalia / quickshell packages here: noctalia v5 is a native Wayland shell
    # provided via the noctalia flake input and enabled in Home Manager.
    catppuccin-cursors.mochaDark
    (catppuccin-gtk.override {
      variant = "mocha";
      accents = [ "mauve" ];
    })
  ];

  programs.niri.enable = true;

}
