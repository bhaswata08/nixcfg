{
  pkgs,
  ...
}:
let
  # Wraps herdr-navigator for the ctrl+h/j/k/l bindings so the keys reach
  # Neovim running over ssh. See the script header.
  navDispatch = pkgs.writeShellApplication {
    name = "herdr-nav-dispatch";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./herdr/herdr-nav-dispatch.sh;
  };
in
{
  home.packages = [ navDispatch ];
  xdg.configFile."herdr/config.toml".source = ./herdr/config.toml;
}
