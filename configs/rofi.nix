{
  config,
  lib,
  pkgs,
  ...
}:

let
  # rofi script mode replacing anyrun's websearch plugin. rofi runs a script
  # mode twice: once with no argument to list entries, then again with the
  # picked entry as $1. Here the "entry" is whatever was typed, so the first
  # call prints nothing and the second opens the query.
  #
  # A leading word picks the engine, DuckDuckGo takes everything else. HyDE
  # ships 29 engines in a data file behind a picker UI; the six below are the
  # ones worth a keystroke here, and the rest are a URL bar away. The list is
  # repeated in the `message` line so the prefixes stay visible in the runner
  # rather than living only in this file.
  websearch = pkgs.writeShellScriptBin "rofi-websearch" ''
    set -eu
    if [ $# -eq 0 ]; then
      # rofi-script protocol: \0<option>\x1f<value> sets a mode property.
      printf '\0prompt\x1fweb\n'
      printf '\0message\x1fEnter searches DuckDuckGo. Prefix: nix opt gh yt w so\n'
      exit 0
    fi
    # A prefix only counts when something follows it, so a bare "nix" searches
    # for the word instead of opening an empty package list.
    head=''${1%% *}
    tail=''${1#* }
    if [ "$tail" = "$1" ]; then
      head=""
      tail="$1"
    fi
    case "$head" in
      nix) base="https://search.nixos.org/packages?query=" ;;
      opt) base="https://search.nixos.org/options?query=" ;;
      gh)  base="https://github.com/search?q=" ;;
      yt)  base="https://www.youtube.com/results?search_query=" ;;
      w)   base="https://en.wikipedia.org/w/index.php?search=" ;;
      so)  base="https://stackoverflow.com/search?q=" ;;
      *)   base="https://duckduckgo.com/?q="
           tail="$1" ;;
    esac
    url="$base$(printf '%s' "$tail" | ${pkgs.jq}/bin/jq -sRr @uri)"
    # $BROWSER first, xdg-open only as a fallback. Under niri, xdg-open runs
    # its generic handler, and if the desktop-file lookup for zen ever misses
    # it walks a hardcoded list that reaches chromium before giving up.
    # modules/environment.nix sets $BROWSER to zen, which is checked first.
    if [ -n "''${BROWSER:-}" ]; then
      exec "$BROWSER" "$url"
    fi
    exec ${pkgs.xdg-utils}/bin/xdg-open "$url"
  '';

  # Nerd Font glyph picker, the one rofi mode HyDE had that nothing here
  # covered. rofi-emoji handles Unicode emoji; this handles the private-use
  # glyphs the configs in this repo are full of.
  #
  # The 10,764-entry database is vendored from HyDE (GPL-3.0), which derives it
  # from ryanoasis/nerd-fonts glyphnames.json. Each line is the glyph, a tab,
  # then its name.
  glyph = pkgs.writeShellScriptBin "rofi-glyph" ''
    set -eu
    if [ $# -eq 0 ]; then
      printf '\0prompt\x1fglyph\n'
      printf '\0message\x1fType a name, Enter copies the glyph\n'
      # rofi draws a tab as a single space, which would leave the two columns
      # ragged, so the fields are rejoined with a fixed separator and the glyph
      # is split back off the front below.
      exec ${pkgs.gawk}/bin/awk -F'\t' '{ printf "%s  %s\n", $1, $2 }' ${./rofi/glyph.db}
    fi
    printf '%s' "''${1%% *}" | ${pkgs.wl-clipboard}/bin/wl-copy
  '';
in
{
  # Replaces anyrun. Every anyrun plugin that did anything on this machine has
  # a rofi counterpart: applications -> drun, rink -> rofi-calc (libqalculate,
  # which also does currency and dates), symbols -> rofi-emoji, websearch ->
  # the script above. The kidex and randr plugins are not carried over: kidex
  # crash-looped out of its restart limit, and anyrun's randr only implements a
  # Hyprland backend behind a no-op fallback, so neither worked under niri.
  programs.rofi = {
    enable = true;
    package = pkgs.rofi;
    plugins = [
      pkgs.rofi-calc
      pkgs.rofi-emoji
    ];
    terminal = "${pkgs.wezterm}/bin/wezterm";
    modes = [
      "drun"
      "run"
      "window"
      "filebrowser"
      "calc"
      "emoji"
      {
        name = "websearch";
        # By name, not by store path: runner.rasi has to name this mode too,
        # and a static .rasi cannot hold a store path. Resolving through PATH
        # lets both spell it the same way.
        path = "rofi-websearch";
      }
      {
        name = "glyph";
        path = "rofi-glyph";
      }
    ];
    extraConfig = {
      # Themes come from -theme on the command line (see configs/theming/
      # niri.nix), because the launcher and the runner use different ones.
      show-icons = true;
      drun-display-format = "{name}";
      display-drun = " ";
      display-run = " ";
      display-window = " ";
      display-filebrowser = " ";
      # rofi-calc: put the result on the clipboard, which is what
      # `anyrun ... | wl-copy` used to do on Super+Space.
      calc-command = "echo -n '{result}' | ${pkgs.wl-clipboard}/bin/wl-copy";
      no-persist-history = true;
      hide-scrollbar = true;
    };
  };

  home.packages = [
    websearch
    glyph
  ];

  xdg.configFile = {
    "rofi/launcher.rasi".source = ./rofi/launcher.rasi;
    "rofi/runner.rasi".source = ./rofi/runner.rasi;
  };

  # noctalia's answer to HyDE's wallbash: its template processor renders this
  # on every wallpaper and colour-scheme change, so rofi tracks the shell
  # instead of holding a palette of its own. colorSchemes.useWallpaperColors
  # and templates.enableUserTheming are both on in
  # configs/theming/noctalia-config.json.
  programs.noctalia-shell.user-templates.templates.rofi = {
    input_path = "${./rofi/colors-template.rasi}";
    output_path = "${config.xdg.configHome}/rofi/colors.rasi";
  };

  # ~/.config/rofi/colors.rasi has to be a plain writable file, since noctalia
  # rewrites it; home-manager cannot own it. But rofi treats a missing @import
  # as a fatal error, so the file must already exist the first time the
  # launcher opens, before any wallpaper change has happened.
  home.activation.seedRofiColors = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "${config.xdg.configHome}/rofi/colors.rasi" ]; then
      run mkdir -p "${config.xdg.configHome}/rofi"
      run cp ${./rofi/colors-fallback.rasi} "${config.xdg.configHome}/rofi/colors.rasi"
      run chmod u+w "${config.xdg.configHome}/rofi/colors.rasi"
    fi
  '';
}
