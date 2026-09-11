{
  pkgs,
  inputs,
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
    # XDG_CURRENT_DESKTOP is niri, so xdg-open takes its generic path: it looks
    # up x-scheme-handler/https (zen, per configs/xdg-defaults.nix), and only
    # if finding or running that desktop file fails does it walk a hardcoded
    # list of browsers that reaches chromium. $BROWSER is checked before that
    # list, so setting it here pins zen without depending on the lookup.
    BROWSER = "${
      inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    }/bin/zen";
    # Where the opencode companion keeps its job records. Without this it walks
    # a fallback chain and lands in /tmp/opencode-companion, so every dispatched
    # job, its trace log and its result are lost on reboot. The plugin appends
    # "state" to this path. Kept outside ~/.claude/plugins so a plugin version
    # bump, which changes the cache directory, does not orphan the history.
    OPENCODE_COMPANION_DATA = "/home/bhaswata/.local/share/opencode-companion";
    # Absolute cap on one `agy --print` invocation. The agy runner has no idle
    # watchdog, unlike the opencode transport, so its only timer is this one.
    # Left at the shared 4h default, two jobs sat wedged for four hours each
    # after their last tool call, and the failure they eventually reported was
    # a stale stderr line from earlier in the run. Thirty minutes bounds what a
    # wedged run costs without cutting off work that is still progressing: the
    # longest job in a week of records ran 28 minutes of real activity.
    AGY_PRINT_TIMEOUT_MS = "1800000";
  };

}
