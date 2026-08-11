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
    # No noctalia-qs: it ships `qs`/`quickshell`, not noctalia-shell. The shell
    # comes from the noctalia flake input and carries its own quickshell build,
    # so this only added a second, unused quickshell to the closure.
    catppuccin-cursors.mochaDark
    (catppuccin-gtk.override {
      variant = "mocha";
      accents = [ "mauve" ];
    })
  ];

  programs.niri.enable = true;

}
