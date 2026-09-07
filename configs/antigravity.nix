{
  lib,
  pkgs,
  ...
}:

let
  # agy's permission lists. `~/.gemini/antigravity-cli/settings.json` is not
  # nix-managed by default, so without this module the lists do not travel to
  # another machine with the rest of the config. The opencode plugin's agy
  # transport documents a suggested list in AGY_SCOPED_ALLOWLIST, but nothing
  # installs it.
  #
  # Rules use `command(<prefix>)` with argument-prefix matching: `command(git log)`
  # covers `git log -n 5`. Chained commands (`&&`, `;`) are denied whatever the
  # rules say, which is why the runner tells the model to issue one command per
  # call.
  #
  # The runner passes `--dangerously-skip-permissions`, so this allow list does
  # not currently gate anything - the deny list below is the floor. Keep it
  # accurate anyway: it is what applies to an interactive `agy` run by hand,
  # and what the setup falls back to if the flag is ever dropped.
  #
  # Read this before adding to the execution group below. `command(node)` covers
  # `node -e '<any javascript>'`, which reaches the filesystem and the network
  # directly. From that rule onward this list is not a security boundary: an
  # agent that wants curl can write fetch, and one that wants rm can write
  # fs.rmSync. What the list still does is stop a confused agent from reaching
  # for a destructive or outward-facing command by accident, which is why the
  # verbs left out below (git push, rm, curl, gh, ssh, sudo, doas, nix) are the
  # ones doing the remaining work. A real boundary would be process isolation,
  # not a command list, and this file cannot provide one.
  allow = [
    # read-only inspection
    "command(ls)"
    "command(cat)"
    "command(head)"
    "command(tail)"
    "command(wc)"
    "command(rg)"
    "command(grep)"
    "command(find)"
    "command(pwd)"

    # git, read-only verbs only. No `command(git)`, which would cover push.
    "command(git status)"
    "command(git diff)"
    "command(git log)"
    "command(git show)"
    "command(git rev-parse)"
    "command(git ls-files)"
    "command(git branch)"

    # More read-only inspection. Taken from what agy models actually reached
    # for across 128 distinct commands in ~/.gemini/antigravity-cli, not
    # guessed. Pipelines are checked stage by stage, so these compose: `awk
    # ... | tr ... | wc -l` passes once every stage is listed.
    "command(which)"
    "command(echo)"
    "command(test)"
    "command(readlink)"
    "command(git remote)"
    "command(git config --get)"
    "command(diff)"
    "command(sort)"
    "command(uniq)"
    "command(tr)"
    "command(awk)"
    "command(sed)"
    "command(cut)"
    "command(basename)"
    "command(dirname)"

    # Execution. See the note above the list: `command(node)` ends the list's
    # usefulness as a boundary. It is here because a coding agent that cannot
    # run what it writes is a much weaker one, and because `node --test`
    # already granted the same capability by a longer route.
    "command(node)"
    "command(npm test)"
    "command(npm run)"
    "command(npm ci)"
    "command(npm install)"
    "command(npx)"
    "command(mkdir)"
    "command(touch)"
  ];

  # Verified against agy 1.1.19 on 2026-09-07: a deny rule beats
  # `--dangerously-skip-permissions`. Running `echo X` with that flag and
  # `command(echo)` denied gives
  #   "Permission denied for command(echo X). Matches user-configured deny rule."
  # So this list is the one part of the permission config that holds no matter
  # how the run is launched, which makes it the right place for the commands
  # that must never happen by accident.
  #
  # It catches accidents, not intent: `command(node)` is allowed above, so
  # anything here is still reachable through `node -e`. Only the terminal
  # sandbox would close that, and it does not currently start on this machine.
  #
  # Matching is by argument prefix, so `command(git push)` covers
  # `git push --force origin main` but nothing rewrites the command first. A
  # rule cannot match a flag that appears in an arbitrary position, which is
  # why these name whole verbs rather than trying to catch `curl -d`.
  deny = [
    # privilege escalation
    "command(sudo)"
    "command(doas)"
    "command(su)"

    # publishing, and history rewrites that lose work
    "command(git push)"
    "command(git reset --hard)"
    "command(git clean)"
    "command(git rebase)"
    "command(git filter-branch)"
    "command(gh pr create)"
    "command(gh pr merge)"
    "command(gh release)"
    "command(gh repo delete)"
    "command(npm publish)"

    # destructive filesystem operations
    "command(rm -rf)"
    "command(rm -r)"
    "command(dd)"
    "command(mkfs)"
    "command(chown)"
    "command(chmod -R)"

    # the machine itself
    "command(shutdown)"
    "command(reboot)"
    "command(systemctl)"
    "command(nix-collect-garbage)"
    "command(nixos-rebuild)"

    # reaching other hosts
    "command(ssh)"
    "command(scp)"
    "command(rsync)"
  ];

  allowJson = builtins.toJSON allow;
  denyJson = builtins.toJSON deny;
in
{
  # agy owns this file at runtime: it writes `trustedWorkspaces` as the user
  # trusts new directories, and `model` when the default changes. So this
  # merges only the keys below instead of taking over the file the way
  # home.file would.
  home.activation.antigravityAllowlist = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.python3}/bin/python3 - <<'PY'
    import json, os

    path = os.path.expanduser("~/.gemini/antigravity-cli/settings.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)

    try:
        with open(path) as f:
            settings = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        settings = {}

    # These lists are replaced, not merged. A permission list should be exactly
    # what is declared here, so a rule added by hand on one machine cannot
    # survive into the next switch and quietly widen what agy may run.
    perms = settings.setdefault("permissions", {})
    perms["allow"] = json.loads(${builtins.toJSON allowJson})
    perms["deny"] = json.loads(${builtins.toJSON denyJson})

    # The agent's own file tools stay inside the workspace. This does not
    # constrain a subprocess: a command that runs at all can reach any path
    # the user can.
    settings["allowNonWorkspaceAccess"] = False

    with open(path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    PY
  '';
}
