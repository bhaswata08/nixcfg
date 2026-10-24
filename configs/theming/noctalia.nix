{
  inputs,
  pkgs,
  ...
}:
{
  programs.noctalia-shell = {
    enable = true;
    settings = ./noctalia-config.json;

    # Spawned from niri's `spawn-at-startup` instead of a user unit, so the
    # shell only runs under niri and never starts in xfce (where it crashes
    # with no wl_display). `noctalia-shell ipc call` addresses a running
    # instance by its shell.qml path, which lives in the store: after any
    # rebuild that moves the package the CLI points at the new path while the
    # process still serves the old one, and every ipc keybind (Super+V for the
    # clipboard, Ctrl+Alt+Delete for the session menu) silently stops working
    # until niri is restarted.
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
    # The `quickshell` override patches the noctalia-qs fork for Qt 6.12, which
    # nixpkgs moved to in October 2026. Qt 6.12 turned an incomplete metatype
    # into a hard error, so the fork's moc'd pointer properties (Hyprland
    # monitors and workspaces, i3 monitors and workspaces, pipewire nodes) fail
    # to compile with "Meta Types must be fully defined". Upstream quickshell
    # fixed this in 5d5d498 by swapping Q_DECLARE_OPAQUE_POINTER for
    # Q_MOC_INCLUDE; the fork sits on a June 2026 base and never picked it up.
    # noctalia-shell only symlinks ${quickshell}/bin/qs, so overriding the
    # callPackage argument is enough. Drop both the override and the patch once
    # the noctalia-qs input carries the fix.
    package =
      (inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
        quickshell =
          inputs.noctalia.inputs.noctalia-qs.packages.${pkgs.stdenv.hostPlatform.system}.quickshell.overrideAttrs
            (old: {
              patches = (old.patches or [ ]) ++ [ ./noctalia-qs-qt6.12.patch ];
            });
      }).overrideAttrs
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
