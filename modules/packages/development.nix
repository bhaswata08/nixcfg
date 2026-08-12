{
  pkgs,
  lib,
  ...
}:
{

  environment.systemPackages = with pkgs; [
    # Languages and formatters
    uv
    go
    lua
    nodejs
    stylua
    luajit
    luarocks

    # Rust from nixpkgs rather than rustup. rustup's shims resolved to
    # toolchains with no manifests, so cargo/rustc failed outright and
    # rust-analyzer fell back to its own shim and recursed forever. This also
    # matches how every other LSP server here is provided (see lsp.lua).
    # For a per-project nightly, use a devshell or oxalica's rust-overlay.
    rustc
    cargo
    rust-analyzer
    clippy
    rustfmt

    # Version Control and Editors
    # No `vim`: EDITOR is nvim and nothing here calls it, while the package
    # installs a gvim.desktop pointing at a gvim binary it does not ship, which
    # then shows up as a dead entry in every "Open With" list.
    neovim
    git
    git-lfs

    # Shell
    carapace
    direnv

    # QOL tools
    zoxide
    bat
    delta
    dust
    viu
    chafa
    ueberzugpp

    # CLI tools
    tree
    ripgrep
    fd
    lazygit
    imagemagick
    ghostscript
    dragon-drop
    just

    # Document and rendering
    mermaid-cli
    tectonic
    python3Packages.pylatexenc # latex2text: the fallback converter latex2unicode defers to
    # render-markdown's latex `converter`, laying formulas out in 2D (tall brackets,
    # stacked fractions and limits). Was a pylatexenc + unicodeit Python script, but
    # render-markdown converts every on-screen equation while blocking the UI thread,
    # and each call spent ~50ms starting an interpreter to do ~1ms of work. Native
    # startup cuts that to ~3ms per call, which measured as 124ms -> 66ms to open a
    # notes file and is paid again on every scroll into unconverted equations.
    (rustPlatform.buildRustPackage {
      pname = "latex2unicode";
      version = "0.1.0";
      # Listed explicitly so a local `cargo build` leaving ./latex2unicode/target
      # behind cannot end up in the store or change the derivation.
      src = lib.fileset.toSource {
        root = ./latex2unicode;
        fileset = lib.fileset.unions [
          ./latex2unicode/Cargo.toml
          ./latex2unicode/Cargo.lock
          ./latex2unicode/src
        ];
      };
      cargoLock.lockFile = ./latex2unicode/Cargo.lock;
    })
    markdownlint-cli2 # markdown linter surfaced via none-ls diagnostics

    # System and Desktop
    chromium
    cups
    libglvnd
    stdenv.cc.cc.lib
    gcc
    arduino-ide

# Mess
    opencode
    antigravity-ide
    claude-code
    gh
    flyctl
  ];
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

}
