# Bootstrap a new machine

Everything this repo cannot carry for you. Work through it top to bottom on a
fresh install.

This repo deliberately holds no secrets and no encrypted secrets. Keys are
copied by hand or re-issued per machine, so every credential below is a manual
step.

## 1. Clone

The default branch on GitHub is `work-pc`, not `main`. A plain clone gets the
right branch. The nvim config is a submodule, so it needs `--recurse-submodules`
or you get an empty `configs/nvim` and neovim starts with no plugins.

```sh
git clone --recurse-submodules git@github.com:bhaswata08/nixcfg.git ~/dotfiles/nixcfg
cd ~/dotfiles/nixcfg
```

If you already cloned without the flag:

```sh
git submodule update --init --recursive
```

## 2. Regenerate the hardware config

`hardware-configuration.nix` is tracked, because `configuration.nix` imports it
and a fresh clone cannot evaluate without it. It describes *this* machine:
LUKS container UUIDs, filesystem UUIDs, the EFI partition. None of that is true
on a new box.

```sh
sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

Do this before the first build. Commit the result on a per-machine branch, or
keep it uncommitted, but do not push one machine's version over another's.

## 3. Decide on the hostname

The flake output is `nixosConfigurations.frosties` in `flake.nix`, and
`modules/networking.nix` sets `networking.hostName = "frosties"`. Keeping the
name is fine and is the least work. To use a different one, change it in both
places.

## 4. First build

`just switch` runs `nh os switch .`, but `nh` is installed *by* this config
(`modules/packages/utilities.nix`), so it does not exist yet. Use plain
`nixos-rebuild` once:

```sh
sudo nixos-rebuild switch --flake .#frosties
```

After that, `just switch` works for every later change.

### If activation aborts with "would be clobbered"

home-manager refuses to replace a real file with a store symlink. On a machine
that ran these tools before this config, move the offending path aside and
rebuild:

```sh
mv ~/.claude/statusline-command.sh{,.bak}
mv ~/.claude/skills/adversary{,.bak}
mv ~/.config/opencode/agent/adversary-deep.md{,.bak}
mv ~/.config/opencode/agent/researcher-or.md{,.bak}
```

A clean install will not hit this.

## 5. Log in to everything

None of these are in the repo. Each is one interactive command.

```sh
claude                  # primary Claude Code account
ccp                     # second account (CLAUDE_CONFIG_DIR=~/.claude-personal)
gh auth login           # stores in the system keyring
agy login               # Google account carrying the Jio subscription
```

## 6. Place the API keys

### synthetic.new

Spent by `synclaude`, and by the `reviewer` and `adversary` opencode seats.
Without it those two seats fail, and they fail with no useful message, so do
this before wondering why a review never returns.

```sh
mkdir -p ~/.config/synthetic
printf '%s' 'YOUR_KEY' > ~/.config/synthetic/key
chmod 600 ~/.config/synthetic/key
```

`SYNTHETIC_API_KEY` in the environment overrides the file if you prefer that.

### OpenRouter

Spent by the `coder` seat when it routes through OpenRouter. There is no key
file for this one: `setup-openrouter` in `configs/nushell/customfunctions.nu`
takes the key as an argument, which means it lands in nushell history every
time you run it. Worth changing to a 0600 file like the synthetic one.

### opencode providers

```sh
opencode auth login
```

Writes `~/.local/share/opencode/auth.json`. Kept out of the repo on purpose.

### OpenAI

`lua/plugins/tts.lua` in the nvim submodule reads `OPENAI_API_KEY` from the
environment for its speech backend. TTS is the only thing that needs it, so
skip it unless you want that.

## 7. Things nix does not install

### Claude skills owned by the skill installer

`configs/claude/skills` vendors the skills no installer owns. The rest live in
`~/.agents/skills`, tracked in `~/.agents/.skill-lock.json`, and are symlinked
into `~/.claude/skills`. That tree is outside this repo, and home-manager
deliberately does not manage those paths: two owners for one path made
`checkLinkTargets` abort the entire activation.

Reinstall them with the `find-skills` skill, or copy `~/.agents` across from a
working machine.

Currently installer-owned: `find-skills`, `lavish`, `learn-profile`,
`learn-verify`, `learn-visual`, `marimo-pair`, `probe`, `skill-creator`,
`teach`.

### opencode plugin dependencies

`~/.config/opencode/package.json` pins `@opencode-ai/plugin` and nothing in this
config installs it.

```sh
cd ~/.config/opencode && npm install
```

### Noctalia Time Blocks plugin

The plugin files are nix-managed (`configs/theming/noctalia.nix` links
`noctalia-plugins/timeblock`), but whether the plugin is *enabled* lives in
`~/.config/noctalia/plugins.json`, which noctalia writes itself. After the first
build the plugin is present and switched off. Turn it on in the Noctalia
settings UI.

## 8. Notes

Restart wezterm after the first `just switch`. It reads its config once at
startup, and the switch only swaps the symlink, so a running terminal keeps the
old one. Herdr panes survive a wezterm restart.

Wallust colors sort themselves out. `configs/wezterm.nix` has an activation
script that copies a checked-in fallback palette to
`~/.config/wallust/wezterm/colors-wezterm.toml` when none exists, so the first
boot is not colorless.
