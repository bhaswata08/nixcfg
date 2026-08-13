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
  # HyDE ships a 200-line version of this with an engine picker, a recent-query
  # cache and its own argument parser. anyrun's plugin was one DuckDuckGo
  # prefix, so this matches that instead.
  websearch = pkgs.writeShellScriptBin "rofi-websearch" ''
    set -eu
    if [ $# -eq 0 ]; then
      # rofi-script protocol: \0<option>\x1f<value> sets a mode property.
      printf '\0prompt\x1fweb\n'
      printf '\0message\x1fType a query, press Enter to search DuckDuckGo\n'
      exit 0
    fi
    query=$(printf '%s' "$1" | ${pkgs.jq}/bin/jq -sRr @uri)
    url="https://duckduckgo.com/?q=$query"
    # $BROWSER first, xdg-open only as a fallback. Under niri, xdg-open runs
    # its generic handler, and if the desktop-file lookup for zen ever misses
    # it walks a hardcoded list that reaches chromium before giving up.
    # modules/environment.nix sets $BROWSER to zen, which is checked first.
    if [ -n "''${BROWSER:-}" ]; then
      exec "$BROWSER" "$url"
    fi
    exec ${pkgs.xdg-utils}/bin/xdg-open "$url"
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

  home.packages = [ websearch ];

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
