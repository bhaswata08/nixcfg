{
  lib,
  ...
}:
{
  # WezTerm config. Colors are read by .wezterm.lua from
  # ~/.config/wallust/wezterm/colors-wezterm.toml. Those colors were tuned by
  # hand via wallust generation configs, so they are committed verbatim
  # (colors-wezterm.toml) and treated as the source of truth.
  home.file.".wezterm.lua".source = ./wezterm/wezterm.lua;

  # wallust config + wezterm template kept in-repo so the colors can be
  # regenerated/re-experimented on, but regeneration is NOT wired into startup:
  # the curated colors below win.
  xdg.configFile."wallust/wallust.toml".source = ./wezterm/wallust.toml;
  xdg.configFile."wallust/templates/wallust/colors-wezterm.toml".source =
    ./wezterm/templates/wallust/colors-wezterm.toml;

  # Seed the curated colors on a fresh machine. Written only if absent, so a
  # local `wallust run` can still overwrite it, but a fresh clone always carries
  # the exact colors. (Not a read-only symlink, so wallust can rewrite it.)
  home.activation.seedWeztermColors = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.config/wallust/wezterm/colors-wezterm.toml"
    if [ ! -e "$target" ]; then
      run mkdir -p "$(dirname "$target")"
      run cp ${./wezterm/colors-wezterm.toml} "$target"
      run chmod u+w "$target"
    fi
  '';
}
