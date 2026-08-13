{
  ...
}:
{

  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      # Web / URLs
      "text/html" = [ "zen.desktop" ];
      "application/xhtml+xml" = [ "zen.desktop" ];
      "x-scheme-handler/http" = [ "zen.desktop" ];
      "x-scheme-handler/https" = [ "zen.desktop" ];
      "x-scheme-handler/about" = [ "zen.desktop" ];
      "x-scheme-handler/unknown" = [ "zen.desktop" ];

      # Documents
      "application/pdf" = [ "zen.desktop" ];
      # "application/epub+zip" = [ "org.pwmt.zathura.desktop" ];

      # Text / code
      "text/plain" = [ "nvim.desktop" ];
      "text/markdown" = [ "nvim.desktop" ];
      "application/json" = [ "nvim.desktop" ];
      "application/xml" = [ "nvim.desktop" ];
      "text/x-shellscript" = [ "nvim.desktop" ];

      # Images
      "image/png" = [ "org.gnome.Loupe.desktop" ];
      "image/jpeg" = [ "org.gnome.Loupe.desktop" ];
      "image/jpg" = [ "org.gnome.Loupe.desktop" ];
      "image/gif" = [ "org.gnome.Loupe.desktop" ];
      "image/webp" = [ "org.gnome.Loupe.desktop" ];
      "image/bmp" = [ "org.gnome.Loupe.desktop" ];
      "image/tiff" = [ "org.gnome.Loupe.desktop" ];
      "image/svg+xml" = [ "org.gnome.Loupe.desktop" ];

      # Audio
      "audio/mpeg" = [ "mpv.desktop" ];
      "audio/flac" = [ "mpv.desktop" ];
      "audio/ogg" = [ "mpv.desktop" ];
      "audio/wav" = [ "mpv.desktop" ];

      # Video
      "video/mp4" = [ "mpv.desktop" ];
      "video/x-matroska" = [ "mpv.desktop" ];
      "video/webm" = [ "mpv.desktop" ];
      "video/x-msvideo" = [ "mpv.desktop" ];

      # Archives
      # "application/zip" = [ "org.gnome.FileRoller.desktop" ];
      # "application/x-tar" = [ "org.gnome.FileRoller.desktop" ];
      # "application/x-gzip" = [ "org.gnome.FileRoller.desktop" ];
      # "application/x-bzip2" = [ "org.gnome.FileRoller.desktop" ];
      # "application/x-7z-compressed" = [ "org.gnome.FileRoller.desktop" ];
      # "application/x-rar" = [ "org.gnome.FileRoller.desktop" ];
      #
      # # File manager
      # "inode/directory" = [ "nemo.desktop" ];
      #
      # # Email
      # "x-scheme-handler/mailto" = [ "aerc.desktop" ];
      #
      # # Torrents
      # "application/x-bittorrent" = [ "transmission-gtk.desktop" ];

      # Terminal apps
      "application/x-terminal-emulator" = [ "org.wezfurlong.wezterm.desktop" ];
    };
  };

}
