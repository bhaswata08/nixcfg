{
  pkgs,
  ...
}:
{
  xdg.dataFile."noctalia-plugins/timeblock".source = ./noctalia-plugins/timeblock;

  # The lock screen avatar: noctalia.toml sets `avatar_path = "~/.face"`.
  home.file.".face".source = ./face.png;

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
