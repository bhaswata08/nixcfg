{
  lib,
  pkgs,
  ...
}:

let
  noMistakes = pkgs.callPackage ../modules/packages/no-mistakes.nix { };
in
{
  # `no-mistakes daemon start` writes its own systemd user unit whose ExecStart
  # is the absolute store path of the binary that installed it, and later starts
  # re-read that path instead of using the current binary. Without this script a
  # version bump leaves the daemon on the old store path until garbage
  # collection deletes it, so when a unit exists but points at another binary,
  # delete it and start again so it re-renders against the new one. No unit
  # means the daemon was never started on this machine, and nothing here starts
  # one: activation must not start a daemon the user never asked for.
  home.activation.noMistakesDaemon = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    found=""
    stale=""
    for unit in "$HOME"/.config/systemd/user/no-mistakes-daemon-*.service; do
      [ -e "$unit" ] || continue
      found=1
      if grep -Fq "${noMistakes}/bin/no-mistakes" "$unit"; then
        :
      else
        stale=1
      fi
    done
    if [ -n "$found" ] && [ -n "$stale" ]; then
      run rm -f "$HOME"/.config/systemd/user/no-mistakes-daemon-*.service
      # Absolute store path, not PATH: PATH during activation can still point at
      # the old generation, which would re-render the unit against the old binary.
      if run ${pkgs.systemd}/bin/systemctl --user daemon-reload \
        && run ${noMistakes}/bin/no-mistakes daemon start; then
        :
      else
        # Activation also runs without a user systemd session, where systemctl
        # has nothing to talk to. The unit is already deleted above, so the next
        # `no-mistakes daemon start` re-renders it; the switch itself still counts.
        echo "no-mistakes: no user systemd session, daemon left stopped until the next start" >&2
      fi
    fi
  '';
}
