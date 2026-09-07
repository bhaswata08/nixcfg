{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  opencodePluginSrc = inputs.opencode-plugin-cc;
  pluginJson = builtins.fromJSON (builtins.readFile "${opencodePluginSrc}/plugins/opencode/.claude-plugin/plugin.json");
  pluginVersion = pluginJson.version;
in
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

  # OpenCode plugin for Claude Code
  home.file.".claude/plugins/marketplaces/tasict-opencode-plugin-cc".source = opencodePluginSrc;
  home.file.".claude/plugins/cache/tasict-opencode-plugin-cc/opencode/${pluginVersion}".source = "${opencodePluginSrc}/plugins/opencode";

  home.activation.claudeOpencodePlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PLUGINS_DIR="$HOME/.claude/plugins"
    KNOWN_MKT="$PLUGINS_DIR/known_marketplaces.json"
    INSTALLED="$PLUGINS_DIR/installed_plugins.json"

    mkdir -p "$PLUGINS_DIR"

    ${pkgs.python3}/bin/python3 -c "
    import json, os, datetime
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()

    # 1. Update known_marketplaces.json
    known_path = os.path.expanduser('$KNOWN_MKT')
    known = {}
    if os.path.exists(known_path):
        try:
            with open(known_path, 'r') as f:
                known = json.load(f)
        except Exception:
            known = {}

    known['tasict-opencode-plugin-cc'] = {
        'source': {'source': 'github', 'repo': 'tasict/opencode-plugin-cc'},
        'installLocation': os.path.expanduser('~/.claude/plugins/marketplaces/tasict-opencode-plugin-cc'),
        'lastUpdated': now
    }
    with open(known_path, 'w') as f:
        json.dump(known, f, indent=2)
        f.write('\n')

    # 2. Update installed_plugins.json
    inst_path = os.path.expanduser('$INSTALLED')
    inst = {'version': 2, 'plugins': {}}
    if os.path.exists(inst_path):
        try:
            with open(inst_path, 'r') as f:
                inst = json.load(f)
        except Exception:
            inst = {'version': 2, 'plugins': {}}

    if 'plugins' not in inst:
        inst['plugins'] = {}

    inst['plugins']['opencode@tasict-opencode-plugin-cc'] = [{
        'scope': 'user',
        'installPath': os.path.expanduser('~/.claude/plugins/cache/tasict-opencode-plugin-cc/opencode/${pluginVersion}'),
        'version': '${pluginVersion}',
        'installedAt': now,
        'lastUpdated': now
    }]
    with open(inst_path, 'w') as f:
        json.dump(inst, f, indent=2)
        f.write('\n')

    # 3. Ensure enabled in settings.json
    settings_path = os.path.expanduser('~/.claude/settings.json')
    if os.path.exists(settings_path):
        try:
            with open(settings_path, 'r') as f:
                settings = json.load(f)
        except Exception:
            settings = {}
        if 'enabledPlugins' not in settings or not isinstance(settings['enabledPlugins'], dict):
            settings['enabledPlugins'] = {}
        settings['enabledPlugins']['opencode@tasict-opencode-plugin-cc'] = True
        with open(settings_path, 'w') as f:
            json.dump(settings, f, indent=2)
            f.write('\n')
    "
  '';
}
