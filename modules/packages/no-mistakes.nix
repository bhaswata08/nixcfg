{ buildGoModule, fetchFromGitHub }:

# Git push gate that runs an agent pipeline in a worktree before forwarding to
# the real remote. Upstream ships a curl|sh installer and a `no-mistakes update`
# self-updater; neither works against the read-only store, so bump `version` and
# the two hashes here instead.
#
# `no-mistakes daemon start` writes its own systemd user unit whose ExecStart is
# the absolute store path of the binary that installed it, and on later starts it
# re-reads that path out of the existing unit instead of using the current binary
# (internal/daemon/selfexec.go, reinstallManagedServiceIfChanged). So after every
# version bump the unit has to re-render against the new store path, which the
# home-manager activation in configs/no-mistakes.nix does by deleting the stale
# unit and starting the daemon again.
#
# Skip that and the daemon keeps running the old binary while the CLI is new, until
# the next `nix-collect-garbage -d` deletes that path and the daemon stops starting.
#
# The skill in configs/claude/skills/no-mistakes is a vendored copy, so re-vendor
# it alongside every version bump:
#
#   curl -sL https://raw.githubusercontent.com/kunchenguid/no-mistakes/v1.70.1/skills/no-mistakes/SKILL.md \
#     -o configs/claude/skills/no-mistakes/SKILL.md
buildGoModule rec {
  pname = "no-mistakes";
  version = "1.70.1";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "no-mistakes";
    rev = "v${version}";
    hash = "sha256-XlVW3KbMzpmfuPYyUjdoL8LkBg46F5PmEUc4Jcj5TjA=";
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
}
