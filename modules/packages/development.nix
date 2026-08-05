{
  pkgs,
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
    rustup

    # Version Control and Editors
    vim
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
    python3Packages.pylatexenc # latex2text: \mathscr->ℒ, \sum for render-markdown.nvim
    python3Packages.unicodeit # LaTeX sub/superscripts -> unicode (₀ ² ⁽ᵏ⁾), which latex2text lacks
    # render-markdown's latex `converter`. Both libraries are line-oriented, so matrices
    # and \frac collapsed into an unreadable run of cells; this lays those out in 2D
    # (tall brackets, stacked fractions) and calls the two libraries per leaf. Falls back
    # to the flat conversion on any parse error so a formula is never dropped.
    (writers.writePython3Bin "latex2unicode" {
      libraries = with python3Packages; [
        unicodeit
        pylatexenc
      ];
      # E501 line length (the glyph tables read better wide); E203/W503 are the
      # usual flake8-vs-black disagreements over slices and wrapped operators.
      flakeIgnore = [
        "E501"
        "E203"
        "W503"
      ];
    } (builtins.readFile ./latex2unicode.py))
    markdownlint-cli2 # markdown linter surfaced via none-ls diagnostics

    # System and Desktop
    anyrun
    chromium
    cups
    libglvnd
    stdenv.cc.cc.lib
    gcc
    arduino-ide

# Mess
    opencode
    antigravity
    claude-code
    gh
    flyctl
  ];
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

}
