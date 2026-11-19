{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    loupe
    rhythmbox
    kdePackages.kdenlive
    playerctl
    mpv
    pavucontrol
    gimp
  ];

  programs.obs-studio.enable = true;

}
