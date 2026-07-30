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
    python3Packages.pylatexenc # latex2text: \mathscr->ℒ, \frac, \sum for render-markdown.nvim
    python3Packages.unicodeit # LaTeX sub/superscripts -> unicode (₀ ² ⁽ᵏ⁾), which latex2text lacks
    # render-markdown's latex `converter`: unicodeit first (handles _/^ + greek), then
    # latex2text fills in \mathscr/\frac/\sum/\dots. Neither tool alone covers both; falls
    # back to the raw input if unicodeit chokes so a formula is never dropped.
    (writeShellScriptBin "latex2unicode" ''
      in=$(cat)
      uni=$(${pkgs.python3Packages.unicodeit}/bin/unicodeit "$in" 2>/dev/null) || uni=$in
      printf '%s' "$uni" | ${pkgs.python3Packages.pylatexenc}/bin/latex2text -q
    '')
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
