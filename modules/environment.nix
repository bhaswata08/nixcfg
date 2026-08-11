{
  pkgs,
  ...
}:

{

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORMTHEME = "qt6ct";
    QT_STYLE_OVERRIDE = "kvantum";
    XCURSOR_THEME = "catppuccin-mocha-dark-cursors";
    XCURSOR_SIZE = "24";
    # This flake, not the stale /etc/nixos copy, so a bare `nh os switch`
    # rebuilds the same thing `just switch` does.
    NH_FLAKE = "/home/bhaswata/dotfiles/nixcfg";
    EDITOR = "${pkgs.neovim}/bin/nvim";
  };

}
