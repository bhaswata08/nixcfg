{
  pkgs, ...
}:
{
  # anyrun-daemon and kidex lived here. Both went with anyrun: rofi covers the
  # launcher and runner (configs/rofi.nix), and kidex had been crash-looping
  # out of its restart limit, so its index was never there to search.
  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };
}
