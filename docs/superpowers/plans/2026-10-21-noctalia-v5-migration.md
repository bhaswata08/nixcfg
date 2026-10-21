# Noctalia v5 Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the noctalia `legacy-v4` shell (QML/quickshell) with noctalia v5 (`main`). Keep the bar, rebuild Time Blocks as a Luau plugin, and lift the nixpkgs hold.

**Architecture:**
- The `noctalia` flake input moves to `main` and is wired through its Home Manager module, `programs.noctalia`. Config is a TOML file in the repo.
- Time Blocks becomes a v5 plugin loaded from a read-only `path` source in the store:
  - Pure schedule logic lives in `lib/schedule.luau`, with no `noctalia.*` calls, so the `luau` CLI can unit-test it.
  - A thin `lib/store.luau` handles persistence and sharing between entries.
  - Four entries sit on top: a bar widget, a main panel, a quick-actions panel and a template panel.

**Tech Stack:** Nix flakes, Home Manager, noctalia v5 (5.3.x, plugin API level ≤ 39), Luau (`nixpkgs#luau` 0.738 for tests), niri.

**Spec:** `docs/superpowers/specs/2026-10-21-noctalia-v5-migration-design.md`

**v5 reference checkout:** `/tmp/claude-1000/-home-bhaswata-dotfiles-nixcfg/df381c16-c3fb-48c5-ad2c-fde010384d06/scratchpad/noctalia-v5` (commit `0c192f8`).
- If it's gone, run `git clone --depth 1 https://github.com/noctalia-dev/noctalia` again.
- Docs: `docs/user/**.mdx`.
- Plugin docs: `docs/user/plugins/development/{manifest,entries,runtime-api,declarative-ui}.mdx`.
- HM module: `nix/home-module.nix`.

## Global Constraints

- Branch `work-pc`. Apply with `just switch`. Build check without switching: `nix build .#nixosConfigurations.frosties.config.system.build.toplevel --no-link`.
- Keep `zen-browser` locked at `458cd16116c362a5e92d5db6bdc3599e4e8b1f4a`. Never run a blanket `nix flake update`. Update inputs by name only.
- `programs.noctalia.checkConfig = true` (build-time `noctalia config validate`).
- Plugin id: `bhaswata/timeblock`. Plugin data lives only under `noctalia.pluginDataDir()`. Never write into the plugin directory (it is in the store).
- Import v4 data from `~/.config/noctalia/plugins/timeblock/settings.json`. Read it once and never write it. A missing file is fine.
- Block fields:
  - every block: `id`, `label`, `start`, `end` (integer minutes since midnight, 0–1440), `color` (palette role), `notes`
  - template blocks also: `days` (0 = Sunday … 6 = Saturday)
  - today blocks also: `skipped`, `templateId`
- Settings defaults: `notifyTransitions = false`, `pushIncrement = 15`, `defaultBlockMinutes = 30`, `defaultColor = "primary"`.
- Bar widget text when nothing is active: `Unscheduled`. The ad-hoc block label is `Ad-hoc`.
- Match the repo's comment style. Nix modules carry "why" comments in full sentences.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Day rollover while the shell keeps running past midnight.** Expected: the widget's next tick regenerates today from the template for the new weekday, and yesterday's edits are gone. Test it in Task 2 with `ensureToday` across two dates.
2. **The v4 import file is missing, empty or malformed JSON.** Expected: the plugin starts with an empty template and no error spam. Test it in Task 2 with `importV4(nil)` and `importV4("not json")`.
3. **`push` near the end of the day.** Expected: starts and ends clamp at 1440, and a block pushed fully past midnight ends up `start == end == 1440`, not negative or past 1440. Test it in Task 2.
4. **End now when the current block started this same minute.** Expected: `end = start + 1`, never `end <= start`. Test it in Task 2.
5. **A stale persisted state from an earlier run with today's date already set.** Expected: a shell restart mid-day keeps the edits and does not regenerate. Test it in Task 2 with `ensureToday` on the same date.

---

### Task 1: Switch the shell to v5 (flake, module, config, bar, theming, keybinds)

**Files:**
- Modify: `flake.nix` (the `noctalia` input, lines 43–46)
- Modify: `flake.lock` (via `nix flake lock --update-input noctalia`)
- Rewrite: `configs/theming/noctalia.nix`
- Create: `configs/theming/noctalia.toml`
- Delete: `configs/theming/noctalia-config.json`
- Modify: `configs/rofi.nix:138-146` (option path and comment). `configs/rofi/colors-template.rasi` keeps its placeholders. Every one it uses (`on_surface`, `on_tertiary`, `tertiary`, `surface`, `surface_container_high`, `surface_container_highest`; formats `hex` and `hex_stripped`) exists in v5 per `docs/user/theming/templates.mdx`.
- Modify: `configs/theming/niri.nix:171-183, 282-283`
- Modify: the NixOS module that sets `nix.settings` (`grep -rn 'nix.settings' --include=*.nix .`), to add the noctalia cachix substituter
- Modify: `modules/packages/external.nix:37-40`, `modules/packages/wm.nix:23-25` (comments only)
- Modify: `BOOTSTRAP.md:151-160` (the plugin-enable instructions no longer apply: v5 enables plugins from config)

**Interfaces:**
- Produces:
  - `configs/theming/noctalia.toml` with a `[plugins]` table that Task 3 extends.
  - The bar's centre section reserves a slot for the widget instance `timeblock`, but Task 1 leaves it out of the section list. Task 3 adds it.
  - `programs.noctalia.settings` points at the TOML file.

- [ ] **Step 1: Point the input at v5.**
  - In `flake.nix`, set `noctalia.url = "github:noctalia-dev/noctalia"` and remove `inputs.nixpkgs.follows`. Add a comment explaining why: the binary cache only hits without `follows`, per `docs/user/getting-started/nixos.mdx`.
  - Run `nix flake update noctalia`.
  - Expected: the `noctalia` node in `flake.lock` moves to a `main` commit, and the `noctalia-qs` node is gone (`jq '.nodes|has("noctalia-qs")' flake.lock` prints `false`).
- [ ] **Step 2: Add the cachix substituter.** Use `extra-substituters = [ "https://noctalia.cachix.org" ]` and `extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ]`. Put them in the NixOS `nix.settings` (create the attr in the main NixOS config module if none exists).
- [ ] **Step 3: Write `configs/theming/noctalia.toml`.** Translate each spec item under "Settings to carry over" to v5 keys. Look every key up in `docs/user/bar/index.mdx`, `docs/user/bar/widgets/*.mdx`, `docs/user/theming/*.mdx`, `docs/user/lockscreen/*`, `docs/user/configuration/*`.
  - Bar: one bar, top, floating look, compact, capsules about 0.55, transparent background.
  - Sections:
    - `start`: workspaces, active_window
    - `center`: clock
    - `end`: sysmon, tray, bluetooth, notifications, battery, volume, brightness, control-center
  - Named `[widget.<name>]` instances where a widget needs settings:
    - clock format `hh:mm a ddd, MMM dd` in v5's format tokens, font `IosevkaTerm NFP Thin Obl`
    - volume middle-click `exec pwvucontrol || pavucontrol`
    - workspaces with index labels and unoccupied workspaces hidden
    - sysmon CPU usage + temp and memory
  - Theme: source wallpaper, dark mode. Use Kanagawa as the fallback where v5 has one.
  - Wallpaper: enabled, directory `/home/bhaswata/dotfiles/nixcfg/configs/theming/wallpapers`.
  - Lock screen: avatar `~/.face`, lock on suspend, session buttons shown, 10 s countdown.
  - Notifications: top right.
  - Panels attached to the bar, panel opacity about 0.25.
  - Dock, desktop widgets, idle, hooks and night light all off.
  - The rofi template under `[theme.templates.user.rofi]` is added in Step 5, not here.
  - Leave out any v4 setting with no v5 key, and list the omissions in a comment at the top of the file.
  - The top comment also says that GUI changes land in `~/.local/state/noctalia/settings.toml`, which overrides this file.
- [ ] **Step 4: Rewrite `configs/theming/noctalia.nix`.**
  - Set `programs.noctalia = { enable = true; settings = ./noctalia.toml; checkConfig = true; systemd.enable = true; }`.
  - Delete:
    - the `programs.noctalia-shell` block
    - the session-menu `overrideAttrs` patch: check `docs/user/configuration` for a session-menu opacity key, and use it in the TOML if one exists
    - the hand-written `systemd.user.services.noctalia-shell`
    - the `xdg.configFile."noctalia/plugins/timeblock"` link
  - Keep a short comment on why the module's unit is enough: `X-Restart-Triggers` on `config.toml`, per `nix/home-module.nix:109`.
- [ ] **Step 5: Move rofi to v5 templates.**
  - In `configs/rofi.nix`, replace `programs.noctalia-shell.user-templates.templates.rofi` with the v5 user-template entry. Its `input_path` is `${./rofi/colors-template.rasi}` and its `output_path` is `~/.config/rofi/colors.rasi`, written the way `docs/user/theming/templates.mdx` defines `[theme.templates.user.<id>]`.
  - Since settings is a TOML file, put the entry in `noctalia.toml`. The input path must be a store path, so either reference the file through `xdg.configFile` or render the TOML with `pkgs.replaceVars`, whichever is simpler.
  - Keep `seedRofiColors`. Update the comment: drop the v4 option names, and mention `noctalia msg templates-apply`.
- [ ] **Step 6: Update the niri keybinds.**
  - Super+V → `spawn "noctalia" "msg" "panel-toggle" "clipboard"`.
  - Ctrl+Alt+Delete → `spawn "noctalia" "msg" "panel-toggle" "session"`.
  - Rewrite the comments at lines 171–173 and 180–182 to describe the v5 unit, and drop the `TODO: Change to quickshell`.
  - Check `docs/user/compositor-settings/niri.mdx` for recommended settings and apply only those that relate to the systemd unit.
- [ ] **Step 7: Delete `configs/theming/noctalia-config.json`, and update the comments in `external.nix`, `wm.nix` and `BOOTSTRAP.md`.**
- [ ] **Step 8: Build.**
  - Run `nix build .#nixosConfigurations.frosties.config.system.build.toplevel --no-link 2>&1 | tail -20`.
  - Expected: a store path ending in `nixos-system-frosties-…`, with no `checkConfig` failure.
  - If validation fails, the error names the TOML key. Fix it and rebuild.
- [ ] **Step 9: Ask the user to run `just switch` and log out and back in, then check.**
  - `systemctl --user is-active noctalia` prints `active`.
  - `noctalia msg status` succeeds.
  - Ask the user to confirm that:
    - the bar matches the spec layout
    - Super+V and Ctrl+Alt+Delete open the clipboard and session panels
    - `noctalia msg wallpaper-random` (or the v5 equivalent in `docs/user/ipc`) rewrites `~/.config/rofi/colors.rasi` (check its mtime)
- [ ] **Step 10: Commit.** Run `git add -A flake.nix flake.lock configs modules BOOTSTRAP.md`, then `git commit -m "noctalia: move to v5 (main), bar and theming in TOML"`.

### Task 2: Time Blocks schedule logic (pure Luau, unit-tested)

**Files:**
- Delete: `configs/theming/noctalia-plugins/timeblock/*.qml`, `i18n/` (v4 sources)
- Create: `configs/theming/noctalia-plugins/timeblock/lib/schedule.luau`
- Create: `configs/theming/noctalia-plugins/timeblock/tests/schedule_test.luau`
- Rewrite: `configs/theming/noctalia-plugins/timeblock/README.md` (v5 usage, commands, data location)

**Interfaces:**
- Produces: the module `schedule` (returned table). Every function is pure and returns new tables or mutated copies. Time is always passed in, never read. `id` generation is injected.

```lua
export type Block = { id: string, label: string, start: number, ["end"]: number, color: string, notes: string,
                      days: {number}?, skipped: boolean?, templateId: string? }
export type State = { template: {Block}, today: { date: string, blocks: {Block} },
                      notifyTransitions: boolean, pushIncrement: number, defaultBlockMinutes: number, defaultColor: string }

schedule.defaultState(): State
schedule.importV4(raw: string?): State                -- parses the v4 settings.json, normalizes like v4 migrateBlocks; bad input -> defaultState()
schedule.normalize(blocks: {Block}, isTemplate: boolean, newId: () -> string): {Block}
schedule.generateToday(template: {Block}, date: string, weekday: number, newId: () -> string): { date: string, blocks: {Block} }
schedule.ensureToday(state: State, date: string, weekday: number, newId: () -> string): (State, boolean)  -- regenerates only if state.today.date ~= date
schedule.active(blocks: {Block}, nowMin: number): Block?   -- non-skipped, start <= now < end, latest start wins
schedule.upcoming(blocks: {Block}, nowMin: number): Block? -- non-skipped, start > now, earliest start
schedule.endNow(blocks: {Block}, nowMin: number): {Block}  -- active block's end = max(start+1, floor(nowMin))
schedule.insertNow(blocks: {Block}, nowMin: number, minutes: number, label: string, color: string, newId: () -> string): {Block}
schedule.push(blocks: {Block}, nowMin: number, minutes: number): {Block}  -- non-skipped with start >= floor(nowMin) shift by minutes, clamp 0..1440
schedule.saveAsTemplate(today: {Block}, newId: () -> string): ({Block}, {Block})  -- (newTemplate with days=0..6, today with templateId relinked; skipped -> templateId "")
schedule.overlappingIds(blocks: {Block}): {[string]: boolean}
schedule.sorted(blocks: {Block}): {Block}           -- by start, then end
schedule.fmt(min: number): string                   -- "HH:MM", 24h
schedule.remaining(blocks: {Block}, nowSec: number): (string, Block?)  -- bar text: "<label> · <Nm|Hh Mm> left", or "Unscheduled" (+ "· next in …" when an upcoming block exists)
```

`ensureToday` behaviour comes from v4 `Main.qml` `regenerateToday` / `computeNow`. It includes template blocks whose `days` contains `weekday`, or all template blocks if `days` is missing, sorted.

- [ ] **Step 1: Write `tests/schedule_test.luau`.**
  - It holds a tiny `check(name, cond)` helper that counts failures and calls `error()` at the end if any failed.
  - It loads the module with `require("../lib/schedule")`. The module itself has no `require`s.
  - Use `newId` as a counter closure, `"t1"`, `"t2"`, ….
  - Assertions, with these exact values:
    - `importV4(nil)` and `importV4("not json")`: both return 0 template blocks, `pushIncrement == 15`.
    - `importV4` of `{"template":[{"label":"Scrum","start":540,"end":600}]}`:
      - the template block gets `days == {0,1,2,3,4,5,6}`, `color == "primary"`, `notes == ""`, and a non-empty `id`
      - `today.date == ""`
    - `generateToday`:
      - template A has `days {1,2,3,4,5}`, start 540, end 600; template B has no `days`, start 720, end 780
      - with weekday 0 → 1 block (B)
      - with weekday 1 → 2 blocks, sorted A then B, `templateId` set, `skipped == false`
    - `ensureToday`:
      - state dated `"2026-10-21"` with an edited block, called with the same date → changed `false` and the blocks are untouched
      - called with `"2026-10-22"` → changed `true`, `today.date == "2026-10-22"`, blocks regenerated
    - `active`:
      - blocks 540–600 and 570–630, now 580 → returns the 570 block (latest start)
      - now 600 → returns the 570 block
      - a skipped block is never returned
      - now 700 → nil
    - `endNow`:
      - active 540–600 at now 540.4 → end 541
      - at now 575 → end 575
    - `push`:
      - non-skipped blocks at 600–660 and 1420–1440, now 590, push 30 → 630–690 and 1440–1440
      - a block that started before now (540–600) is unchanged
      - a skipped future block is unchanged
    - `insertNow` at now 600.7, minutes 30 → a new block 600–630 labelled `Ad-hoc` in sorted position; at now 1430 → end 1440
    - `saveAsTemplate`:
      - a skipped today block is excluded from the template and its `templateId` becomes `""`
      - the others get new template ids with `days` 0..6
    - `overlappingIds` on 540–600 and 570–630 → both ids; on 540–600 and 600–660 → none
    - `fmt(545) == "09:05"`
    - `remaining`:
      - at nowSec 575*60 with an active 540–600 "Scrum" block → `"Scrum · 25m left"`
      - with nothing active and next at 720, nowSec 600*60 → `"Unscheduled · next in 2h 0m"`
- [ ] **Step 2: Run it and watch it fail.** Run `nix shell nixpkgs#luau -c luau configs/theming/noctalia-plugins/timeblock/tests/schedule_test.luau`. Expected: fails with a module-not-found error for `../lib/schedule`.
- [ ] **Step 3: Implement `lib/schedule.luau` to the signatures above.**
  - Write your own minimal JSON decode for `importV4`, or pass a decoder in. Prefer `schedule.importV4(raw: string?, decode: (string) -> any?)`: the store passes `noctalia.json.decode`, and the test passes a small decoder it defines. If you change the signature this way, update the Interfaces block of Task 3 to match.
  - Do floor and clamp arithmetic with `math.floor` and `math.clamp`.
- [ ] **Step 4: Run the tests again.** Expected: exit 0, and the helper prints `all passed`.
- [ ] **Step 5: Delete the v4 QML and `i18n/`, and rewrite `README.md`.** The README covers: what the plugin does, the four entries, the commands from Task 3, where data lives (`pluginDataDir()/state.json`), the one-time import from v4, and how to run the tests.
- [ ] **Step 6: Commit.** Run `git add -A configs/theming/noctalia-plugins/timeblock`, then `git commit -m "timeblock: v5 schedule core in Luau with tests"`.

### Task 3: Time Blocks plugin (manifest, store, widget, panels, commands)

**Files:**
- Create in `configs/theming/noctalia-plugins/timeblock/`:
  - `plugin.toml`
  - `translations/en.json`
  - `lib/store.luau`
  - `widget.luau`
  - `panel.luau`
  - `actions.luau`
  - `template.luau`
- Modify: `configs/theming/noctalia.nix` (store path for the plugin source), `configs/theming/noctalia.toml` (`[plugins]` and the bar widget slot)
- Modify: `configs/theming/niri.nix` (optional binds; see Step 7)

**Interfaces:**
- Consumes: the `schedule` module from Task 2.
- Produces:
  - Entry ids:
    - `bhaswata/timeblock:bar` (widget)
    - `bhaswata/timeblock:panel` (main panel)
    - `bhaswata/timeblock:actions` (quick-actions panel)
    - `bhaswata/timeblock:template` (template panel)
  - `lib/store.luau`:
    - `store.load(): State` reads `pluginDataDir()/state.json`. When that file is missing, it imports v4 via `schedule.importV4(noctalia.readFile(expandPath("~/.config/noctalia/plugins/timeblock/settings.json")))` and saves. It then runs `ensureToday` with the local date and weekday from `noctalia.formatTime`.
    - `store.save(state)` writes the JSON and calls `noctalia.state.set("rev", <counter>)` so the other entries reload.
    - `store.mutate(fn: (State) -> State)` does load, apply and save.
    - `store.now(): (nowMin: number, nowSec: number, date: string, weekday: number)`.
  - Commands, handled in `widget.luau` `onIpc(event, payload)`:
    - `noctalia msg plugin bhaswata/timeblock bar endNow`; `next` is an alias of `endNow`, as in v4
    - `insertNow`
    - `push [N]`, where N defaults to `pushIncrement`
    - `resetToday`
    - toggling the panel uses `noctalia msg panel-toggle bhaswata/timeblock:panel`

- [ ] **Step 1: Write `plugin.toml`.**
  - `id = "bhaswata/timeblock"`, `name = "Time Blocks"`, `version = "2.0.0"`. Set `plugin_api` to the lowest level that covers every API used; check each against `plugin-api.mdx`.
  - `[[widget]] id="bar"` with `[widget.actions] middle = "none"`, so middle-click doesn't open widget settings and fall through.
  - `[[panel]]` entries `panel`, `actions` and `template`.
  - Plugin-level `[[setting]]`s for `notifyTransitions` (bool, false), `pushIncrement` (int, 15, min 1, max 240), `defaultBlockMinutes` (int, 30, min 5, max 480) and `defaultColor` (select over the palette roles `primary`, `secondary`, `tertiary`, `error`).
  - Labels go in `translations/en.json`.
  - Settings come from `noctalia.getConfig`, not from `state.json`, so the store ignores those four fields after import. Nothing is lost: the user's v4 values equal the defaults.
- [ ] **Step 2: Write `lib/store.luau` to the interface above.** Never write outside `pluginDataDir()`.
- [ ] **Step 3: Write `widget.luau`.**
  - Set `noctalia.setUpdateInterval(30000)`.
  - `update()` calls `store.load()` (which applies the day rollover), sets the text from `schedule.remaining`, and colours the text with the active block's `color` role via `barWidget.setColor`, or `on_surface` when there's none.
  - The tooltip shows the current block's time range and the next block.
  - If `notifyTransitions` is on, keep the last active id in a local and call `noctalia.notify("Time Blocks", "Now: <label> (HH:MM–HH:MM)")` or `"Unscheduled"` when it changes. Skip the first tick after load.
  - `onClick` → `noctalia.togglePanel("bhaswata/timeblock:panel")`. `onRightClick` → `noctalia.togglePanel("bhaswata/timeblock:actions")`.
  - `onIpc` handles the commands above through `store.mutate`, then calls `update()`.
  - Watch `noctalia.state` key `"rev"` so panel edits refresh the bar immediately.
- [ ] **Step 4: Write `actions.luau`.** A small `ui.column` of buttons: End now, Insert now, `+<pushIncrement>m`, Reset today. Each button mutates and then calls `panel.close()`.
- [ ] **Step 5: Write `panel.luau`.**
  - Header row of buttons: End now, Insert now, `+<N>m`, Reset today, Save as template, plus a "Template…" button that toggles `bhaswata/timeblock:template`.
  - Below it, one row per today block:
    - past blocks (`end <= nowMin`) dimmed
    - the active block highlighted with a `progress` element at (now − start) / (end − start)
    - ⚠ when the id is in `overlappingIds`
    - controls: a label `input`, start and end `input`s in `HH:MM` (an invalid entry reverts), a colour `select` over the four roles, skip `toggle`, delete `button`
  - An "Add block" button appends a block of `defaultBlockMinutes` starting at the end of the last block, or at now if there are none.
  - Re-render in `onOpen`, on the `"rev"` watch, and once a minute via `update()`.
  - Use only elements listed in `declarative-ui.mdx`.
- [ ] **Step 6: Write `template.luau`.** The same row editor over `state.template`, with seven weekday `toggle`s (S M T W T F S) in place of skip, plus add and delete.
- [ ] **Step 7: Wire it in.**
  - In `noctalia.toml`, add a `[[plugins.source]]` with `name = "nixcfg"`, `kind = "path"`, and `location` set to a store directory that contains `timeblock/`. Build that path in `noctalia.nix`, for example with `pkgs.linkFarm "noctalia-plugins" [ { name = "timeblock"; path = ./noctalia-plugins/timeblock; } ]`, and substitute it into the TOML. Then set `enabled = ["bhaswata/timeblock"]` and `auto_update = "official"`.
  - Add `[widget.timeblock] type = "bhaswata/timeblock:bar"` and put `"timeblock"` after the clock in the bar's `center` list.
  - Add niri binds only if the user asks. Otherwise document the commands in the README.
- [ ] **Step 8: Build.** Run the Task 1 Step 8 command. Expected: the build succeeds, and `checkConfig` accepts the plugin source and widget type. If it rejects the type because the plugin can't be resolved at build time, read `checkConfig`'s handling in `nix/home-module.nix` and the validator, and fix the source path rather than turning validation off.
- [ ] **Step 9: Ask the user to run `just switch`, then verify on the live session.**
  - The bar shows the current block from the user's 8-block template, seeded from v4.
  - `noctalia msg plugin bhaswata/timeblock bar push 15` moves the upcoming blocks by 15 minutes in the open panel.
  - Right-click shows the actions panel.
  - Template edits survive `systemctl --user restart noctalia`.
  - The tests from Task 2 still pass.
- [ ] **Step 10: Commit.** Run `git add -A configs/theming`, then `git commit -m "timeblock: v5 plugin with bar widget, panels and commands"`.

### Task 4: Lift the nixpkgs hold

**Files:**
- Modify: `flake.lock`
- Possibly modify: `flake.nix:38-41`, `modules/packages/external.nix:36` (only if `qml-niri` fails to build)
- Modify memories: `~/.claude/projects/-home-bhaswata-dotfiles-nixcfg/memory/flake-lock-holds.md`, `noctalia-timeblock-plugin.md`, `MEMORY.md`

- [ ] **Step 1: Update nixpkgs.** Run `nix flake update nixpkgs home-manager nix`. Leave `zen-browser` alone: `jq -r '.nodes["zen-browser"].locked.rev' flake.lock` must still print `458cd16116c362a5e92d5db6bdc3599e4e8b1f4a`.
- [ ] **Step 2: Build** with the Task 1 Step 8 command. Expected: success. If `qml-niri` fails on Qt 6.12, remove the input from `flake.nix` and the package line from `external.nix`, run `nix flake lock`, and rebuild. Report anything else that fails to the user before changing it.
- [ ] **Step 3: Update the memories.**
  - `flake-lock-holds.md`: only zen is held now, and say why.
  - `noctalia-timeblock-plugin.md`: v5 Luau plugin, path source, `pluginDataDir`, the test command.
  - Keep the `MEMORY.md` lines in step.
- [ ] **Step 4: Ask the user to run `just switch` and confirm the shell comes back.**
- [ ] **Step 5: Commit.** Run `git add flake.lock flake.nix modules`, then `git commit -m "flake: lift nixpkgs hold now that noctalia-qs is gone"`.
