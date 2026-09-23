# nixcfg

`just switch` applies this config. It wraps `nh os switch .`. On a fresh
machine `nh` does not exist yet, so the first build uses
`nixos-rebuild switch --flake .#frosties`. BOOTSTRAP.md covers the full
bring-up order.

`work-pc` is the default branch. `main` is abandoned.

Each tool is a `configs/<name>.nix` module plus a `configs/<name>/` directory
of files the module links into place.

`configs/nvim` is a git submodule. Clone with `--recurse-submodules`, or run
`git submodule update --init --recursive` in an existing clone.

Home Manager links config files under `~` as symlinks into `/nix/store`, so
they are read-only. Edit the repo copy and run `just switch` to apply.
