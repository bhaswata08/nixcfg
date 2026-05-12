{
  pkgs,
  ...
}:

{

  fonts.packages = [
    pkgs.nerd-fonts.martian-mono
    pkgs.lato
    pkgs.noto-fonts
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-color-emoji
    pkgs.liberation_ttf
    pkgs.fira-code
    pkgs.fira-code-symbols
    pkgs.mplus-outline-fonts.githubRelease
    pkgs.dina-font
    pkgs.proggyfonts
    pkgs.corefonts
    pkgs.nerd-fonts.iosevka        
    pkgs.nerd-fonts.iosevka-term  

  ];

  fonts.fontconfig.defaultFonts = {
    sansSerif = [
      "Lato Black"
    ];
    monospace = [
      "Martian Mono Condensed Semibold"
    ];
  };

}
