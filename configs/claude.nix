{
  ...
}:
{
  # ~/.claude is not an XDG directory, so this uses home.file rather than the
  # xdg.configFile pattern used elsewhere in this repo.

  # Global agent instructions. The file lives at ~/AGENTS.md so non-Claude
  # agents pick it up too, and ~/.claude/CLAUDE.md points at the same content.
  home.file."AGENTS.md".source = ./claude/AGENTS.md;
  home.file.".claude/CLAUDE.md".source = ./claude/AGENTS.md;

  # Skills, vendored per file (recursive) so hand-installed skills can still be
  # dropped into ~/.claude/skills without colliding with this entry.
  #
  # herdr comes from upstream ogulcancelik/herdr; re-vendor with:
  #   curl -sL https://raw.githubusercontent.com/ogulcancelik/herdr/master/skills/herdr/SKILL.md \
  #     -o configs/claude/skills/herdr/SKILL.md
  home.file.".claude/skills" = {
    source = ./claude/skills;
    recursive = true;
  };
}
