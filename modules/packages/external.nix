{
  pkgs,
  inputs,
  ...
}:
let
  # The Rust half of herdr.nvim (configs/nvim/lua/plugins/misc.lua). Herdr has no
  # process-aware key forwarding, so ctrl+h/j/k/l are bound in configs/herdr/config.toml
  # to this helper: it forwards the key into Neovim when the focused pane runs Neovim,
  # and moves Herdr panes otherwise. Built here rather than by the plugin's own
  # `cargo build --release`, since rustup ships without a default toolchain.
  # The rev must match the herdr.nvim commit in configs/nvim/lazy-lock.json.
  herdr-navigator = pkgs.rustPlatform.buildRustPackage {
    pname = "herdr-navigator";
    version = "0.1.0-unstable-2026-06-01";

    src = pkgs.fetchFromGitHub {
      owner = "devxplay";
      repo = "herdr.nvim";
      rev = "deed8496356aab90e1cc364dac4f95d898fa6067";
      hash = "sha256-NmBVVbh/fqwSfKBCrB589fCbzUyEP8wEP7IxD/T5RcE=";
    };

    cargoHash = "sha256-3DTa6VPTUKOSPKwLCXiUmexwhW2P3bBSFsgWXrcw/Po=";
  };

  # Git push gate that runs an agent pipeline in a worktree before forwarding to
  # the real remote. Upstream ships a curl|sh installer and a `no-mistakes update`
  # self-updater; neither works against the read-only store, so bump `version` and
  # the two hashes here instead.
  #
  # `no-mistakes daemon start` writes its own systemd user unit whose ExecStart is
  # the absolute store path of the binary that installed it, and on later starts it
  # re-reads that path out of the existing unit instead of using the current binary
  # (internal/daemon/selfexec.go, reinstallManagedServiceIfChanged). So after every
  # version bump below, drop the unit so it re-renders against the new store path:
  #
  #   rm ~/.config/systemd/user/no-mistakes-daemon-*.service
  #   no-mistakes daemon start
  #
  # Skip it and the daemon keeps running the old binary while the CLI is new, until
  # the next `nix-collect-garbage -d` deletes that path and the daemon stops starting.
  no-mistakes = pkgs.buildGoModule rec {
    pname = "no-mistakes";
    version = "1.45.3";

    src = pkgs.fetchFromGitHub {
      owner = "kunchenguid";
      repo = "no-mistakes";
      rev = "v${version}";
      hash = "sha256-uII42yFLpyo4rTHPVMJn1lsuhBo566BtcO52/1xsxCQ=";
    };

    vendorHash = "sha256-NZOYxNYvt4192uqKBdKRxdgrKFvWx3585psdCnRdPSM=";

    subPackages = [ "cmd/no-mistakes" ];

    # The upstream Makefile also bakes in a telemetry endpoint via ldflags.
    # Leaving those unset builds with an empty host, so the binary reports nothing.
    ldflags = [
      "-s"
      "-w"
      "-X github.com/kunchenguid/no-mistakes/internal/buildinfo.Version=v${version}"
    ];

    # `go test ./...` spawns git and real agent CLIs, which the sandbox has no network for.
    doCheck = false;
  };
in
{
  environment.systemPackages = [
    inputs.pfm.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.qml-niri.packages.${pkgs.stdenv.hostPlatform.system}.default
    # noctalia-shell is not listed here. programs.noctalia-shell already puts
    # its package on the user profile, and that one carries the session-menu
    # transparency patch (configs/theming/noctalia.nix); a second, unpatched
    # copy in systemPackages would just race it on PATH.
    inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    herdr-navigator
    no-mistakes
  ];
}
