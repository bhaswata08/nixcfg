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
    thunderbird
  ];

}
