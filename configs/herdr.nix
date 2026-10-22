{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;

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

  # The server doesn't watch config.toml, so a running one keeps the old
  # keybindings until told to reload. Panes survive the reload.
  home.activation.herdrReloadConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ -S "$HOME/.config/herdr/herdr.sock" ]; then
      run ${herdr}/bin/herdr server reload-config >/dev/null 2>&1 || true
    fi
  '';
}
