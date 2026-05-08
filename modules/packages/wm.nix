{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    xwayland-satellite
    waybar
    wezterm
    awww
    fastfetch
    hyprpolkitagent
    hyprlock
    starship
    btop
    wlogout
    papirus-icon-theme
    pipes
    sunsetr
    wl-kbptr
    wlrctl
    anyrun
    noctalia-qs
  ];

  programs.niri.enable = true;

}
