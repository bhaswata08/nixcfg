{
  inputs,
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
    systemd.enable = true;

    # The session menu's large buttons hardcode an opaque `Color.mSurface`, and
    # no setting exposes it, so the cards sit as solid blocks over the
    # wallpaper. Everything else about the menu (layout, gaps, keybind badges,
    # countdown) is already what it should be, so this rewrites the one line.
    # 0.45 is `ui.panelBackgroundOpacity` from noctalia-config.json spelled out
    # again, because the QML cannot reach the setting from here; change both.
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
}
