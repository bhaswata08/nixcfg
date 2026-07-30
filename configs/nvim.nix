{
  config,
  ...
}:
{
  # Symlink ~/.config/nvim to the in-repo submodule (configs/nvim) rather than
  # copying into the read-only Nix store, so lazy.nvim can update lazy-lock.json
  # and `zg` can write the spellfile at runtime. The submodule tracks
  # github.com/bhaswata08/nvim.
  #
  # Tree-sitter parsers (incl. latex, for render-markdown $ math) are installed
  # by nvim-treesitter's `main` branch into ~/.local/share/nvim/site/parser/ —
  # not via Nix — so nothing parser-related lives here anymore.
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nixcfg/configs/nvim";
}
