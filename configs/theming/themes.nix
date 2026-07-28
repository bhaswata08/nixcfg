{
  pkgs, lib, ...
}:
{
  xdg.dataFile = {
    "themes/Abyssal-Wave".source = ./gtkstuff/Abyssal-Wave;
    "icons/Papirus-kanagawa".source = ./gtkstuff/Papirus-kanagawa;
  };

  home.pointerCursor = {
    name = "catppuccin-mocha-dark-cursors";
    package = pkgs.catppuccin-cursors.mochaDark;
    size = 24;
    gtk.enable = true;
  };

  catppuccin = {
    autoEnable = true;
    enable = true;
    flavor = "mocha";
    accent = "mauve";
    hyprlock.enable = false;
  };

  # Qt theming: Kvantum style driven by catppuccin (mocha/mauve). Setting
  # style.name = "kvantum" auto-installs the Kvantum engine for Qt5 + Qt6 and
  # exports QT_STYLE_OVERRIDE=kvantum, which themes Qt apps (KeePassXC,
  # Kdenlive). catppuccin.kvantum (autoEnabled) drops in the theme files.
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "kvantum";
  };

  gtk = {
    enable = true;
    theme = {
      name = "Abyssal-Wave";
    };
    iconTheme = {
      name = lib.mkForce "Papirus-kanagawa";
    };
    cursorTheme = {
      name = "catppuccin-mocha-dark-cursors";
      package = pkgs.catppuccin-cursors.mochaDark;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };
}
