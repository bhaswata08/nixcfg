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

  # Default prose style, inlined by AGENTS.md via Claude Code's @path import.
  home.file.".claude/soul.md".source = ./claude/soul.md;

  # Skills, vendored per file (recursive) so hand-installed skills can still be
  # dropped into ~/.claude/skills without colliding with this entry.
  #
  # Only vendor a skill no installer owns. find-skills, lavish and marimo-pair
  # used to live here too, but the skill installer tracks them in
  # ~/.agents/.skill-lock.json and symlinks them into ~/.claude/skills. Two
  # owners for one path made checkLinkTargets abort the whole activation with
  # "would be clobbered", so nothing at all got linked. The installer keeps
  # those three current; this list keeps the rest.
  #
  # herdr comes from upstream ogulcancelik/herdr; re-vendor with:
  #   curl -sL https://raw.githubusercontent.com/ogulcancelik/herdr/master/skills/herdr/SKILL.md \
  #     -o configs/claude/skills/herdr/SKILL.md
  home.file.".claude/skills" = {
    source = ./claude/skills;
    recursive = true;
  };
}
