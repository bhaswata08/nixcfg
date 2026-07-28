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
    NH_FLAKE = "/etc/nixos";
    EDITOR = "${pkgs.neovim}/bin/nvim";
  };

}
