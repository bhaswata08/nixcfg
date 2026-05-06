{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    anki
    onlyoffice
    drawing
    obsidian
  ];

}
