{
  pkgs,
  ...
}:
{

  environment.systemPackages = with pkgs; [
    # Languages and formatters
    uv
    go
    nodejs
    stylua
    luajit
    luarocks
    docker
    rustup

    # Version Control and Editors
    neovim
    git
    git-lfs

    # Shell
    carapace
    nushell
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

    # System and Desktop
    anyrun
    chromium
    cups
    libglvnd
    stdenv.cc.cc.lib
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

}
