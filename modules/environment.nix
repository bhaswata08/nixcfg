{
  pkgs,
  ...
}:

{

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    # The single place the Qt theme and cursor are set for the whole session.
    #
    # home-manager's qt module (configs/theming/themes.nix) installs the qt6ct
    # and Kvantum plugins, but its platformTheme.name = "qtct" emits
    # QT_QPA_PLATFORMTHEME=qt5ct into hm-session-vars.sh, and the plugin that is
    # actually installed is the Qt6 one. This value deliberately overrides that.
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
