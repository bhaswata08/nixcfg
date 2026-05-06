{
  pkgs, inputs, ...
}:
{
  systemd.user.services.anyrun-daemon = {
    Unit = {
      description = "Anyrun Daemon";
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
    };
    Service = {
      environment = { PATH = "${pkgs.anyrun}/bin"; };
      execStart = "${pkgs.anyrun}/bin/anyrun daemon";
      restart = "on-failure";
    };
    Install = {
      wantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.kidex = {
    Unit = {
      description = "Kidex file indexer";
      after = [ "graphical-session-pre.target" ];
      partOf = [ "graphical-session.target" ];
    };
    Service = {
      execStart = "${inputs.kidex.packages.${pkgs.stdenv.hostPlatform.system}.kidex}/bin/kidex";
      restart = "always";
    };
    Install = {
      wantedBy = [ "default.target" ];
    };
  };
}
