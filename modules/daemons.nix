{
  pkgs, ...
}:
{
  # anyrun-daemon and kidex lived here. Both went with anyrun: rofi covers the
  # launcher and runner (configs/rofi.nix), and kidex had been crash-looping
  # out of its restart limit, so its index was never there to search.
  # Ordered after network-online.target because `remote-add` fetches the
  # .flatpakrepo over HTTPS. Without it the unit raced DNS and failed on every
  # boot with "Could not resolve hostname", which is why every activation
  # reported flatpak-repo.service among the failed units. NetworkManager-
  # wait-online is already enabled, so the target actually waits for a link.
  # oneshot + RemainAfterExit so a finished run reads as active rather than
  # dead, and `--if-not-exists` keeps the re-run harmless.
  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };
}
