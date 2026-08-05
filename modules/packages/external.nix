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

in
{
  environment.systemPackages = [
    inputs.kidex.packages.${pkgs.stdenv.hostPlatform.system}.kidex
    inputs.pfm.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.qml-niri.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    herdr-navigator
  ];
}
