{
  pkgs, inputs, ...
}:
{

  systemd.user.services.anyrun-daemon = {
    Unit = {
      Description = "Anyrun Daemon";
      # Ensures it only starts once Wayland is ready
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      # Environment ensures it can find its own plugins and Wayland socket
      Environment = [ "PATH=${pkgs.anyrun}/bin" ];
      ExecStart = "${pkgs.anyrun}/bin/anyrun daemon";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.kidex = {
    Unit = {
      Description = "Kidex file indexer";
      After = [ "graphical-session-pre.target" ];
      Partof = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${inputs.kidex.packages.${pkgs.stdenv.hostPlatform.system}.kidex}/bin/kidex";
      Restart = "always";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}

