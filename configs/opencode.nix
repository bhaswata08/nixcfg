{ ... }:

{
  # opencode's config was hand-written on this machine, so the agent seats and
  # their models did not travel to another branch with the rest of the config.
  # Same gap as the one configs/antigravity.nix closes for agy.
  #
  # These are symlinks into the store rather than an activation script: opencode
  # reads them and never writes them. Credentials are separate, in
  # ~/.local/share/opencode/auth.json, and stay out of this repo.
  #
  # The provider block that used to live in a stray opencode.jsonc is
  # deliberately not carried over. It held two plaintext API keys for internal
  # endpoints, and opencode.json takes precedence anyway, so that file had
  # already been dead for some time.
  xdg.configFile."opencode/opencode.json".source = ./opencode/opencode.json;

  # One file per seat. The plugin selects a seat by name, so the filename is the
  # interface: `coder`, `reviewer`, `adversary`, and the fallback the plugin
  # retries `adversary` on.
  #
  # Fallbacks are declared in the plugin, in scripts/lib/fallback.mjs, because
  # two of the three cross a boundary opencode has no way to express: `coder`
  # falls onto agy, and `reviewer` falls onto a Claude Code subagent, since
  # opencode has no Anthropic credential and lists no Claude model.
  xdg.configFile."opencode/agent" = {
    source = ./opencode/agent;
    recursive = true;
  };
}
