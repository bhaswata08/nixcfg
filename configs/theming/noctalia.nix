{
  ...
}:
{
  programs.noctalia-shell = {
    enable = true;
    settings = ./noctalia-config.json;
  };

  # Local "Time Blocks" plugin. `recursive = true` makes the plugin directory a
  # real (writable) directory with each source file symlinked individually, so
  # Noctalia can still write its own settings.json into the folder at runtime.
  xdg.configFile."noctalia/plugins/timeblock" = {
    source = ./noctalia-plugins/timeblock;
    recursive = true;
  };
}
