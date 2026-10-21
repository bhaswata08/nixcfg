{
  pkgs,
  ...
}:
let
  pluginsDir = pkgs.linkFarm "noctalia-plugins" [
    {
      name = "timeblock";
      path = ./noctalia-plugins/timeblock;
    }
  ];
in
{
  programs.noctalia = {
    enable = true;
    settings = pkgs.replaceVars ./noctalia.toml {
      rofiColorsTemplate = ../rofi/colors-template.rasi;
      pluginsDir = pluginsDir;
    };
    checkConfig = true;
    systemd.enable = true;
  };

  # The upstream module's systemd user service (`programs.noctalia.systemd.enable = true`)
  # is sufficient because it sets X-Restart-Triggers on config.toml (and custom palettes),
  # per nix/home-module.nix:109. This ensures Home Manager restarts the shell whenever
  # the rendered configuration changes.
}
