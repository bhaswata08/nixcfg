{
  config,
  pkgs,
  ...
}:
{
  # Symlink ~/.config/nvim to the in-repo submodule (configs/nvim) rather than
  # copying into the read-only Nix store, so lazy.nvim can update lazy-lock.json
  # and `zg` can write the spellfile at runtime. The submodule tracks
  # github.com/bhaswata08/nvim.
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nixcfg/configs/nvim";

  # Prebuilt latex tree-sitter parser (for render-markdown $$ math). nvim-treesitter's
  # master generate step can't run against tree-sitter CLI 0.26, so we drop the grammar
  # onto ~/.local/share/nvim/site, which is already on runtimepath (see options.lua).
  home.file.".local/share/nvim/site/parser/latex.so".source =
    "${pkgs.tree-sitter-grammars.tree-sitter-latex}/parser";
}
