{
  pkgs,
  ...
}:

{

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORMTHEME = "qt6ct";
    XCURSOR_THEME = "catppuccin-mocha-dark";
    XCURSOR_SIZE = "24";
    NH_FLAKE = "/etc/nixos";
    EDITOR = "${pkgs.neovim}/bin/nvim";
  };

}
