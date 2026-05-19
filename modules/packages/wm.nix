{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    wallust
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
  ];

  programs.niri.enable = true;

}
