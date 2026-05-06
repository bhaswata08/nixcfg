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
      "text/plain" = [ "neovim.desktop" ];
      "text/markdown" = [ "neovim.desktop" ];
      "application/json" = [ "neovim.desktop" ];
      "application/xml" = [ "neovim.desktop" ];
      "text/x-shellscript" = [ "neovim.desktop" ];

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
      "audio/mpeg" = [ "mpv" ];
      "audio/flac" = [ "mpv" ];
      "audio/ogg" = [ "mpv" ];
      "audio/wav" = [ "mpv" ];

      # Video
      "video/mp4" = [ "mpv" ];
      "video/x-matroska" = [ "mpv" ];
      "video/webm" = [ "mpv" ];
      "video/x-msvideo" = [ "mpv" ];

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
      "application/x-terminal-emulator" = [ "com.mitchellh.ghostty.desktop" ];
    };
  };

}
