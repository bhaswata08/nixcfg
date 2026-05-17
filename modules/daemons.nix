{
  pkgs, inputs, ...
}:
{
  systemd.user.services.anyrun-daemon = {
    enable = true;
    description = "Anyrun Daemon";
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Environment = "PATH=${pkgs.anyrun}/bin";
      ExecStart = "${pkgs.anyrun}/bin/anyrun daemon";
      Restart = "on-failure";
    };
  };

  systemd.user.services.kidex = {
    enable = true;
    description = "Kidex file indexer";
    after = [ "graphical-session-pre.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${inputs.kidex.packages.${pkgs.stdenv.hostPlatform.system}.kidex}/bin/kidex";
      Restart = "always";
    };
  };

  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };
}
