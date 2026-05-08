{
  pkgs, inputs, ...
}:
{
  programs.noctalia-shell = {
    enable = true;
    settings = ./custom-config.json;
  };
}
