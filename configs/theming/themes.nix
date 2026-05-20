{
  pkgs, lib, ...
}:
{
  xdg.dataFile = {
    "themes/Abyssal-Wave".source = ./gtkstuff/Abyssal-Wave;
    "icons/Papirus-kanagawa".source = ./gtkstuff/Papirus-kanagawa;
  };

  home.pointerCursor = {
    name = "catppuccin-mocha-dark";
    package = pkgs.catppuccin-cursors.mochaMauve;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  catppuccin = {
    enable = true;
    flavor = "mocha";
    accent = "mauve";
    hyprlock.enable = false;
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
      name = "catppuccin-mocha-dark";
      package = pkgs.catppuccin-cursors.mochaMauve;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };
}
