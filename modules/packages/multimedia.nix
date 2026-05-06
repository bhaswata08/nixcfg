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
    stash
  ];

  programs.obs-studio.enable = true;

}
