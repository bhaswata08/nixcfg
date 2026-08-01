# TODO

- [x] Fix Ark drag-and-drop extraction. Root cause: Ark is a Qt/X11 app
      running under `xwayland-satellite` (niri has no built-in XWayland), so
      dragging files out to Nautilus (native Wayland) is a cross-protocol
      X11->Wayland drag. xwayland-satellite (0.8.1) does not bridge
      cross-protocol DnD — a known upstream gap, not a niri/portal/theming
      issue (niri maintainer: "report to xwayland-satellite", discussion
      #2566). Fixed by replacing `kdePackages.ark` with `file-roller`
      (Wayland-native GTK, integrates with Nautilus's Extract Here/Compress),
      so DnD stays Wayland<->Wayland. Ark removed from utilities.nix.
