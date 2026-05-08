{
  pkgs, ...
}:
{
  programs.bat = {
    enable = true;
  };

  programs.btop = {
    enable = true;
  };

  programs.mangohud = {
    enable = true;
  };

  programs.neovim = {
    plugins = [
    (pkgs.vimPlugins.nvim-treesitter.withPlugins (p: [
      p.lua
      p.python
      ]))
    ];
  };
}
