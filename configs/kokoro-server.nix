{
  pkgs,
  ...
}:

let
  projectDir = "/home/bhaswata/self_projects/kokoro_server";
  upstream = "http://127.0.0.1:8880";
in
{
  # Adapter for the Kokoro TTS Firefox addon, which is installed in zen and
  # signed, so its code cannot be changed without re-signing it through AMO.
  # It has http://localhost:8000/* hardcoded in its manifest and calls three
  # endpoints there: /health, /generate and /stream.
  #
  # This service answers those three and forwards the actual synthesis to the
  # kokoro-fastapi container in modules/daemons.nix, which already holds
  # Kokoro-82M in memory for tts.nvim. Running the addon's own bundled server
  # instead would load a second copy of the same weights plus a second PyTorch
  # runtime, about 1.1 GiB, to serve a model that is already resident.
  #
  # The addon plays the /stream PCM at a hardcoded 22050 Hz while kokoro
  # synthesizes at 24000, which made the original pair run 8.8% slow in both
  # halves at once. The adapter resamples to cancel that out. server.py has the
  # detail.
  #
  # A user service because the project and its uv venv live under /home/bhaswata.
  # The project is not in this repo and is not managed by Nix: Nix owns the unit,
  # uv owns what runs inside it.
  systemd.user.services.kokoro-server = {
    Unit = {
      Description = "Kokoro TTS adapter for the Firefox addon";
      Documentation = "file://${projectDir}/server.py";
      After = [ "network.target" ];
    };

    Service = {
      Type = "simple";
      WorkingDirectory = projectDir;

      # The container is a system service and this is a user service, so there
      # is no ordering edge between them. It does not need one: /health reports
      # the upstream as down and the addon shows that, and a request that
      # arrives early fails with a normal error rather than a crash.
      Environment = [ "KOKORO_UPSTREAM=${upstream}" ];

      # --frozen pins the run to uv.lock instead of re-resolving on every start.
      # uv still rebuilds the venv if it is missing, which is what makes this
      # survive a `rm -rf .venv`, but it will not quietly drift onto new
      # versions behind the service's back.
      #
      # The wheels in that venv are generic-linux binaries that look for
      # /lib64/ld-linux-x86-64.so.2. nix-ld (modules/nix-ld.nix) supplies that
      # loader and already lists what numpy and scipy reach for, so nothing
      # extra belongs in this unit.
      ExecStart = "${pkgs.uv}/bin/uv run --frozen python server.py";

      # Nothing here loads a model, so a restart is cheap and a short backoff is
      # fine. The usual reason to fail is the container not being up yet.
      Restart = "on-failure";
      RestartSec = 10;
    };

    Install.WantedBy = [ "default.target" ];
  };
}
