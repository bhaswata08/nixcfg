{
  pkgs,
  ...
}:
{

  environment.systemPackages = with pkgs; [
    tree-sitter
    nixfmt
    nixd
    marksman
    pandoc
    typst
    tinymist

    # LSP servers (installed via Nix instead of Mason, which ships FHS
    # binaries that cannot run on NixOS).
    lua-language-server
    basedpyright
    ruff
    ty
    yaml-language-server
    vscode-langservers-extracted # provides vscode-json-language-server
    dockerfile-language-server

    # Formatters / linters (used by none-ls, must be on PATH).
    # Note: stylua is already provided by development.nix.
    shfmt
    prettier
    checkmake
  ];

}
