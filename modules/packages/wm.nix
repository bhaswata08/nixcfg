{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    xwayland-satellite
    waybar
    ghostty
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
    fuzzel
    rofi
  ];

  programs.niri.enable = true;

}
