{
  config,
  ...
}:
{
  # Symlink ~/.config/nvim to the in-repo submodule (configs/nvim) rather than
  # copying into the read-only Nix store, so lazy.nvim can update lazy-lock.json
  # and `zg` can write the spellfile at runtime. The submodule tracks
  # github.com/bhaswata08/nvim.
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nixcfg/configs/nvim";
}
