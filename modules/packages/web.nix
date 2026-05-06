{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    avahi
    openforticlient
    qbittorrent-enhanced
    networkmanagerapplet
    aria2
    pipeline
    brave
  ];
}
