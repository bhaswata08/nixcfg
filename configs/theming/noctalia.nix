{
  pkgs,
  ...
}:
{
  xdg.dataFile."noctalia-plugins/timeblock".source = ./noctalia-plugins/timeblock;

  programs.noctalia = {
    enable = true;
    settings = pkgs.replaceVars ./noctalia.toml {
      rofiColorsTemplate = ../rofi/colors-template.rasi;
      pluginsDir = "~/.local/share/noctalia-plugins";
    };
    checkConfig = true;
    systemd.enable = true;
  };

  systemd.user.services.noctalia.Unit.X-Restart-Triggers = [
    "${./noctalia-plugins/timeblock}"
  ];
}
