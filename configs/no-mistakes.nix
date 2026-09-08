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
  # collection deletes it.
  #
  # The order matters. `daemon start` is a no-op when a daemon is already
  # running, so deleting the unit first and starting second leaves the machine
  # with no unit at all. Stop first, and only delete once the stop succeeded.
  # A plain `daemon stop` refuses while pipeline runs are active, which is the
  # behaviour we want: an interrupted run loses work, and a switch is not worth
  # that. Leave the old unit in place and say so instead.
  #
  # No unit means the daemon was never started on this machine, and nothing here
  # starts one: activation must not start a daemon the user never asked for.
  home.activation.noMistakesDaemon = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    stale=""
    for unit in "$HOME"/.config/systemd/user/no-mistakes-daemon-*.service; do
      [ -e "$unit" ] || continue
      grep -Fq "${noMistakes}/bin/no-mistakes" "$unit" || stale=1
    done
    if [ -n "$stale" ]; then
      # Absolute store path, not PATH: PATH during activation can still point at
      # the old generation, which would re-render the unit against the old binary.
      if ${noMistakes}/bin/no-mistakes daemon stop >/dev/null 2>&1; then
        run rm -f "$HOME"/.config/systemd/user/no-mistakes-daemon-*.service
        run ${pkgs.systemd}/bin/systemctl --user daemon-reload || true
        if ! run ${noMistakes}/bin/no-mistakes daemon start; then
          # Activation also runs without a user systemd session, where there is
          # nothing to talk to. The unit is already gone, so the next
          # `no-mistakes daemon start` re-renders it against this build.
          echo "no-mistakes: could not start the daemon; run 'no-mistakes daemon start' to re-create the unit" >&2
        fi
      else
        echo "no-mistakes: daemon left on the old build, most likely because a pipeline run is active" >&2
        echo "no-mistakes: run 'no-mistakes daemon stop; no-mistakes daemon start' once it finishes" >&2
      fi
    fi
  '';
}
