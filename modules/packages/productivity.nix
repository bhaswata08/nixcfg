{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    anki
    onlyoffice-desktopeditors
    drawing
    obsidian
    koodo-reader
    thunderbird
  ];

}
