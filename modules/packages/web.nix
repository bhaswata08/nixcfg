{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    avahi
    qbittorrent-enhanced
    networkmanagerapplet
    aria2
    pipeline
    brave
  ];
}
