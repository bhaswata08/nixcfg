{
  pkgs, ...
}:
{
  xdg.dataFile = {
    "themes/Abyssal-Wave".source = ./gtkstuff/Abyssal-Wave;
    "icons/Papirus-kanagawa".source = ./gtkstuff/Papirus-kanagawa;
  };

  gtk = {
    enable = true;
    theme = {
      name = "Abyssal-Wave";
    };
    iconTheme = {
      name = "Papirus-kanagawa";
    };
    cursorTheme = {
      name = "catppuccin-mocha-dark";
      package = pkgs.catppuccin-cursors.mochaMauve;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };
}
