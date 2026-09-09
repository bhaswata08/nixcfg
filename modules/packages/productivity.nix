{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    anki
    onlyoffice-desktopeditors
    libreoffice
    drawing
    obsidian
    koodo-reader
    thunderbird
  ];

}
