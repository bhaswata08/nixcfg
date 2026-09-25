{
  pkgs,
  ...
}:

let
  # Real logic lives in worklog-report.sh so it can be linted with shellcheck
  # (via writeShellApplication) and exercised by configs/worklog/tests/run.sh
  # outside of a Nix rebuild.
  worklogScript = pkgs.writeShellApplication {
    name = "worklog-report";
    runtimeInputs = [
      pkgs.git
      pkgs.claude-code
      pkgs.gnugrep
      pkgs.gnused
      pkgs.findutils
    ];
    text = builtins.readFile ./worklog/worklog-report.sh;
  };
in
{
  home.packages = [ worklogScript ];

  # Summarizes today's git activity across ~/self_projects and ~/work into
  # ~/worklog.md via headless Claude Haiku. See
  # docs/superpowers/specs/2026-09-25-worklog-automation-design.md.
  systemd.user.services.worklog = {
    Unit = {
      Description = "Generate today's work log entry";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${worklogScript}/bin/worklog-report";
    };
  };

  systemd.user.timers.worklog = {
    Unit = {
      Description = "Daily timer for the worklog service";
    };
    Timer = {
      OnCalendar = "Mon..Fri 18:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
