{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  opencodePluginSrc = inputs.opencode-plugin-cc;
  pluginJson = builtins.fromJSON (builtins.readFile "${opencodePluginSrc}/plugins/opencode/.claude-plugin/plugin.json");
  pluginVersion = pluginJson.version;

  claudeSessionIndexPkg = pkgs.runCommand "claude-session-index" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  } ''
    mkdir -p $out/bin $out/lib/claude-session-index
    cp -r ${./claude/session-index}/* $out/lib/claude-session-index/
    rm -rf $out/lib/claude-session-index/__pycache__
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/claude-session-index \
      --add-flags "$out/lib/claude-session-index/cli.py"
  '';

  claudeDefaultsJson = builtins.toJSON {
    enforce = {
      enabledPlugins = {
        "lua-lsp@claude-plugins-official" = true;
        "rust-analyzer-lsp@claude-plugins-official" = true;
        "superpowers@claude-plugins-official" = true;
        "context7@claude-plugins-official" = true;
        "code-simplifier@claude-plugins-official" = true;
      };
      statusLine = {
        type = "command";
        command = "bash ${config.home.homeDirectory}/.claude/statusline-command.sh";
      };
    };
    # Read-only commands that show up constantly in transcripts and can never
    # mutate anything. Every entry here is one permission prompt that stops
    # happening. `union` appends without clobbering, so anything added later
    # through /permissions survives the next activation.
    #
    # Deliberately absent: `cat` (bare, because `cat > file` writes), `sed -i`,
    # `node`, `uv run`, `docker exec` and `ssh`. Those either write or run
    # arbitrary code, and a prompt is the point.
    union = {
      permissions = {
        allow = [
          # Reading and searching
          "Bash(ls:*)"
          "Bash(sed -n:*)"
          "Bash(cat -n:*)"
          "Bash(head:*)"
          "Bash(tail:*)"
          "Bash(wc:*)"
          "Bash(grep:*)"
          "Bash(rg:*)"
          "Bash(fd:*)"
          "Bash(find:*)"
          "Bash(file:*)"
          "Bash(stat:*)"
          "Bash(du:*)"
          "Bash(realpath:*)"
          "Bash(readlink:*)"
          "Bash(jq:*)"
          "Bash(tree:*)"
          # Git, read-only subcommands only
          "Bash(git status:*)"
          "Bash(git diff:*)"
          "Bash(git log:*)"
          "Bash(git show:*)"
          "Bash(git blame:*)"
          "Bash(git branch:*)"
          "Bash(git remote -v)"
          "Bash(git stash list)"
          "Bash(git ls-files:*)"
          "Bash(git rev-parse:*)"
          "Bash(git describe:*)"
          "Bash(git worktree list)"
          # Nix, evaluation and inspection only. `nix flake update`,
          # `nix build` and `nh os switch` stay behind a prompt.
          "Bash(nix-instantiate --parse:*)"
          "Bash(nix flake metadata:*)"
          "Bash(nix flake show:*)"
          "Bash(nix eval:*)"
          "Bash(nix search:*)"
          "Bash(nix path-info:*)"
          "Bash(nixfmt --check:*)"
          "Bash(statix check:*)"
          "Bash(deadnix --fail:*)"
          # This machine's own read-only tooling
          "Bash(claude-session-index show:*)"
          "Bash(claude-session-index search:*)"
          "Bash(claude-session-index doctor:*)"
          "Bash(systemctl --user status:*)"
          "Bash(journalctl --user:*)"
        ];
      };
    };
    seed = {
      model = "opus";
      effortLevel = "medium";
      theme = "auto";
      modelSettings = {
        "claude-sonnet-5" = {
          effortLevel = "medium";
        };
        "claude-opus-5" = {
          effortLevel = "medium";
        };
      };
    };
  };
in
{
  # ~/.claude is not an XDG directory, so this uses home.file rather than the
  # xdg.configFile pattern used elsewhere in this repo.

  # Global agent instructions. One copy lives at ~/AGENTS.md, which is what
  # both Claude Code profiles read: Claude Code walks up from the working
  # directory to $HOME collecting AGENTS.md and CLAUDE.md without deduping
  # identical content, so a second copy at ~/.claude/CLAUDE.md would load this
  # file and the soul.md it imports twice every session. ~/AGENTS.md covers
  # every directory under /home/bhaswata, and non-Claude agents pick it up too.
  home.file."AGENTS.md".source = ./claude/AGENTS.md;

  # Default prose style, inlined by AGENTS.md via Claude Code's @path import.
  home.file.".claude/soul.md".source = ./claude/soul.md;

  # Statusline script. Kept at the stable path ~/.claude/statusline-command.sh
  # rather than pointing settings.json at a /nix/store path because (a) the
  # existing claudePersonalShared activation script symlinks that exact name
  # into ~/.claude-personal, and (b) a store path would churn every generation.
  home.file.".claude/statusline-command.sh".source = ./claude/statusline-command.sh;

  # Skills, vendored per file (recursive) so hand-installed skills can still be
  # dropped into ~/.claude/skills without colliding with this entry.
  #
  # Only vendor a skill no installer owns. find-skills, lavish and marimo-pair
  # used to live here too, but the skill installer tracks them in
  # ~/.agents/.skill-lock.json and symlinks them into ~/.claude/skills. Two
  # owners for one path made checkLinkTargets abort the whole activation with
  # "would be clobbered", so nothing at all got linked. The installer keeps
  # those three current; this list keeps the rest (e.g. adversary, herdr).
  #
  # adversary runs an adversarial review pass over plans via opencode companion;
  # vendored locally from ~/.claude/skills/adversary.
  #
  # herdr comes from upstream ogulcancelik/herdr; re-vendor with:
  #   curl -sL https://raw.githubusercontent.com/ogulcancelik/herdr/master/skills/herdr/SKILL.md \
  #     -o configs/claude/skills/herdr/SKILL.md
  home.file.".claude/skills" = {
    source = ./claude/skills;
    recursive = true;
  };

  # Second Claude account. `ccp` (configs/nushell/aliases.nu) points
  # CLAUDE_CONFIG_DIR here, which gives that account its own credentials while
  # sharing everything else with ~/.claude (see claudePersonalShared below).
  # Neither CLAUDE.md nor soul.md is mirrored here: ~/AGENTS.md already covers
  # this profile's working directories, and AGENTS.md imports soul.md as
  # @~/.claude/soul.md, an absolute path both profiles read.
  home.file.".claude-personal/skills" = {
    source = ./claude/skills;
    recursive = true;
  };

  # OpenCode plugin for Claude Code.
  # Both versioned and 'current' cache directories are created. Claude Code
  # sessions cache hook paths when they start, so pointing the registry at a
  # versioned path orphans running sessions whenever the plugin version bumps.
  # The 'current' symlink provides a stable path across generations while
  # keeping the versioned directory available for tools that reference it.
  home.file.".claude/plugins/marketplaces/tasict-opencode-plugin-cc".source = opencodePluginSrc;
  home.file.".claude/plugins/cache/tasict-opencode-plugin-cc/opencode/${pluginVersion}".source = "${opencodePluginSrc}/plugins/opencode";
  home.file.".claude/plugins/cache/tasict-opencode-plugin-cc/opencode/current".source = "${opencodePluginSrc}/plugins/opencode";

  home.packages = [
    claudeSessionIndexPkg
  ];

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
        'installPath': os.path.expanduser('~/.claude/plugins/cache/tasict-opencode-plugin-cc/opencode/current'),
        'version': '${pluginVersion}',
        'installedAt': now,
        'lastUpdated': now
    }]
    with open(inst_path, 'w') as f:
        json.dump(inst, f, indent=2)
        f.write('\n')

    "

    # 3. Ensure enabled in settings.json safely via settings_updater.py
    ${pkgs.python3}/bin/python3 ${./claude/session-index/settings_updater.py} enable-plugin "opencode@tasict-opencode-plugin-cc"
  '';

  # Register claude-session-index background hook in hooks.SessionStart.
  # claudeSessionIndexPkg is in home.packages, so the profile bin is the stable
  # path across generations and needs no symlink of its own.
  home.activation.claudeSessionIndexHook = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
    ${pkgs.python3}/bin/python3 ${./claude/session-index/settings_updater.py} hook "${config.home.profileDirectory}/bin/claude-session-index"
  '';

  # Enforce declared plugins and statusLine in settings.json, and seed defaults
  # (model, effortLevel, theme, modelSettings) if absent without clobbering user choices.
  home.activation.claudeSettingsDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.python3}/bin/python3 ${./claude/session-index/settings_updater.py} defaults ${lib.escapeShellArg claudeDefaultsJson}
  '';

  # Claude Code keeps credentials, settings and session transcripts in one
  # directory, so a second account needs a second CLAUDE_CONFIG_DIR and would
  # otherwise get a second, empty /resume list. Symlink everything that is not
  # the login back to ~/.claude so both accounts read and write one set of
  # sessions, prompt history, settings and plugins.
  #
  # Left unshared on purpose: .credentials.json and .claude.json carry the
  # account identity, and policy-limits.json, remote-settings.json and
  # stats-cache.json are per-account usage state. The daemon files are left
  # alone too, since both profiles running one daemon lock would collide.
  #
  # This is an activation script rather than home.file entries because
  # checkLinkTargets aborts activation when a path is a symlink that does not
  # point into the nix store, which is exactly what these are. `ln -sfn` also
  # repairs a link that Claude Code replaced with a real file.
  home.activation.claudePersonalShared = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    W="$HOME/.claude"
    P="$HOME/.claude-personal"
    mkdir -p "$P"
    for n in backups cache file-history jobs paste-cache plans plugins projects \
             session-env session-index sessions shell-snapshots tasks telemetry \
             history.jsonl settings.json statusline-command.sh; do
      [ -e "$W/$n" ] || continue
      if [ -e "$P/$n" ] && [ ! -L "$P/$n" ]; then
        echo "claude-personal: $P/$n is real, not linking (move it aside first)" >&2
        continue
      fi
      ln -sfn "$W/$n" "$P/$n"
    done
  '';
}
