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
  ];

}
