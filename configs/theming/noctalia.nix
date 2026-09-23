{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  programs.noctalia-shell = {
    enable = true;
    settings = ./noctalia-config.json;

    # Run as a user unit instead of niri's `spawn-at-startup`, so that a
    # rebuild restarts the shell. `noctalia-shell ipc call` addresses a running
    # instance by its shell.qml path, which lives in the store: after any
    # rebuild that moves the package the CLI points at the new path while the
    # process still serves the old one, and every ipc keybind (Super+V for the
    # clipboard, Ctrl+Alt+Delete for the session menu) silently stops working
    # until the next relog. The unit also carries X-Restart-Triggers on
    # settings.json and user-templates.toml, so config edits take effect too.
    #
    # The unit is defined below rather than through `systemd.enable`, which
    # warns on every evaluation. That warning belongs to the legacy-v4 branch
    # this input is pinned to: its docs link 404s, and upstream's current
    # module still ships the same unit with no deprecation at all. Since
    # legacy-v4 is frozen, declaring the unit here cannot drift from it.
    systemd.enable = false;

    # The session menu's large buttons hardcode an opaque `Color.mSurface`, and
    # no setting exposes it, so the cards sit as solid blocks over the
    # wallpaper. Everything else about the menu (layout, gaps, keybind badges,
    # countdown) is already what it should be, so this rewrites the one line.
    # 0.45 is a middle ground, not `ui.panelBackgroundOpacity`: the session menu
    # cards sit straight on the wallpaper with nothing behind them, so they need
    # more body than a panel that already has a blurred backdrop.
    #
    # Bumping the noctalia input: `replace-fail` turns a moved or reworded line
    # into a build error rather than a silent no-op, so a failed build here
    # means the upstream QML changed and the patch needs re-checking.
    #
    # This appends to installPhase rather than using postInstall, because
    # noctalia's installPhase is hand-written and never calls `runHook
    # postInstall`, so a postInstall would be dropped without a word.
    package =
      inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs
        (old: {
          installPhase = old.installPhase + ''
            substituteInPlace $out/share/noctalia-shell/Modules/Panels/SessionMenu/SessionMenu.qml \
              --replace-fail 'return Color.mSurface;' 'return Qt.alpha(Color.mSurface, 0.45);'
          '';
        });
  };

  # Local "Time Blocks" plugin. `recursive = true` makes the plugin directory a
  # real (writable) directory with each source file symlinked individually, so
  # Noctalia can still write its own settings.json into the folder at runtime.
  xdg.configFile."noctalia/plugins/timeblock" = {
    source = ./noctalia-plugins/timeblock;
    recursive = true;
  };

  # The unit the module's `systemd.enable` would have produced, reproduced
  # here so the deprecation warning stays quiet. Keep this in step with
  # nix/home-module.nix in the noctalia input if the pin ever moves off the
  # frozen legacy-v4 branch, at which point the option itself is the better
  # home for this again.
  #
  # X-Restart-Triggers is what makes a rebuild pick up config edits: the two
  # store paths change whenever settings.json or user-templates.toml does, so
  # home-manager restarts the shell instead of leaving a stale one running.
  systemd.user.services.noctalia-shell = {
    Unit = {
      Description = "Noctalia Shell - Wayland desktop shell";
      Documentation = "https://docs.noctalia.dev";
      PartOf = [ config.wayland.systemd.target ];
      After = [ config.wayland.systemd.target ];
      X-Restart-Triggers = [
        "${config.xdg.configFile."noctalia/settings.json".source}"
        "${config.xdg.configFile."noctalia/user-templates.toml".source}"
      ];
    };

    Service = {
      ExecStart = lib.getExe config.programs.noctalia-shell.package;
      Restart = "on-failure";
    };

    Install.WantedBy = [ config.wayland.systemd.target ];
  };
}
