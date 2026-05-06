{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    wget
    tmux
    eza
    swaynotificationcenter
    man
    yt-dlp
    tlrc
    ncdu
    lutgen
    ffmpeg
    libXcursor
    fzf
    ark
    dolphin
    wl-clipboard
    keepassxc
    nh
    nix-output-monitor
    nvd
    pass
    home-manager
    cliphist
    gnome-disk-utility
    unzip
  ];

  programs.appimage.enable = true;
}
