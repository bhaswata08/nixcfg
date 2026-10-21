# Noctalia v4 → v5 migration

Date: 2026-10-21. Repo: nixcfg, branch `work-pc`. Host: `frosties` (NixOS + Home Manager, niri).

## Why

The `noctalia` flake input is pinned to `legacy-v4`. That branch is marked unsupported. It builds against `noctalia-qs`, a quickshell fork that has had only lock bumps since July. The fork does not compile on Qt 6.12 (`Meta Types must be fully defined` on `HyprlandWorkspace`). Qt 6.12 arrived with nixpkgs `02c087f`. Right now `flake.lock` is held at commit `774dc99` (nixpkgs `55bfb4d`) to keep the system building.

v5 (branch `main`, 5.3.0 at the time of writing) is a native Wayland/OpenGL ES rewrite with no Qt. Moving to v5 removes the quickshell dependency and lets nixpkgs move forward again.

## Goals

1. **The bar works as it does today.** It keeps the same widgets in the same sections: a floating, compact, top-positioned bar with capsules and a transparent background.
2. **Time Blocks works on v5.** It is rebuilt as a v5 Luau plugin (described below). The user's existing template and today's blocks carry over.
3. **Colours follow the wallpaper**, as they do now. Rofi keeps getting its colours from the shell.
4. **The niri keybinds that drive the shell work again**: Super+V for the clipboard and Ctrl+Alt+Delete for the session menu.
5. After the migration, `nix flake update nixpkgs` builds. The nixpkgs hold is lifted as part of this work.

## Non-goals

- Pixel-identical styling. "Same widgets, same places, similar look" is enough.
- Porting every v4 setting. Defaults are fine wherever the user has not changed something that matters (see the inventory below).
- Lifting the zen-browser hold. That is a separate stale-hash problem upstream. Keep `zen-browser` at `458cd16`.
- Publishing the plugin anywhere.

## Anti-goals (this fails even if it "works")

- Time Blocks loses the user's saved weekly template, or today's schedule is wrong on the first day.
- The shell has to be started by hand after login, or a `just switch` leaves the old shell running.
- Rofi fails to open because `colors.rasi` is missing or malformed.

## Decisions made with the user

- **Panel is a list, not a timeline.** The v4 drawn time axis with a "now" line is dropped. The user mostly glances at what's current and next, and taps quick actions a few times a day.
- **Clean cut.** v4 is removed in one change. The fallback is a git revert.

## Time Blocks v5 spec

The v4 QML source in `configs/theming/noctalia-plugins/timeblock/` (Main.qml, Panel.qml, BarWidget.qml, Settings.qml, README.md) is the behavioural reference. It is replaced by a v5 plugin: `plugin.toml` plus `.luau` entries.

**Data model.** Unchanged from v4:
- Each block has `id`, `label`, `start` and `end` (minutes since midnight), `color` (semantic palette key) and `notes`.
- Template blocks also carry `days` (0 = Sunday … 6 = Saturday).
- Today's instances carry `skipped` and `templateId`.
- Settings: `notifyTransitions` (default false), `pushIncrement` (15), `defaultBlockMinutes` (30), `defaultColor` ("primary").

**Rules.** Unchanged from v4:
- Today is generated from the template once per calendar day. Reloading the shell mid-day keeps edits.
- Editing today never touches the template, except through "Save as template".
- Overlapping blocks are allowed and marked with ⚠. During an overlap, the most recently started block is active.

**Bar widget.**
- Shows the current block's label and the time left, tinted with the block's colour. During a gap it shows "Unscheduled".
- Updates on a timer (around 30 s is enough).
- Left-click toggles the panel.
- Right-click opens a small second `[[panel]]` with the quick actions: End now, Insert now, +N min and Reset today. v5 bar widgets can't open context menus, so a second panel stands in for one (my call).

**Panel.**
- A header row of actions: End now, Insert now, +N min (N = `pushIncrement`), Reset today, Save as template.
- Below it, today's blocks as a list. Past blocks are dimmed. The current block is highlighted with a progress bar. Upcoming blocks are shown normally.
- Each row is editable in place (label, start, end, colour) and can be skipped or deleted.
- An add-block control.

**Template editing.** The weekly template as a plain list. Each block has the same fields plus weekday toggles. It lives either as a second view inside the panel or as the plugin's settings surface, whichever v5 supports more cleanly (builder's call).

**Commands.** `toggle`, `next`, `endNow`, `insertNow`, `push N` and `resetToday`, reachable through `noctalia msg plugin …` and `noctalia msg panel-toggle …`.

`current` is dropped. v5 plugin commands can't return output to the caller, and nothing uses it. The user agreed.

**Notifications.** If `notifyTransitions` is on, send a notification on each block transition.

**Persistence.**
- The plugin's state must live somewhere writable outside the Nix store.
- On first run, seed it from the user's v4 data at `~/.config/noctalia/plugins/timeblock/settings.json`, which currently holds 8 template blocks. Read it once. Never write to it, and don't require it to exist.
- The repo copy of the plugin is read-only.

**Install.**
- The plugin source lives in the repo. Where exactly is the builder's call, e.g. `configs/theming/noctalia-plugins/timeblock/`, with the v4 QML removed.
- It is loaded through a `[[plugins.source]] kind = "path"` entry pointing into the store, and listed in `[plugins] enabled`.

## The rest of the migration

**Flake.**
- Point `noctalia` at `github:noctalia-dev/noctalia` (`main`).
- Use `inputs.noctalia.homeModules.default` with `programs.noctalia`. Note that this module disables Home Manager's own `programs/noctalia` module.
- Remove the `noctalia-qs` lock node.
- Builder's call: whether to drop `inputs.nixpkgs.follows` to hit `noctalia.cachix.org`, or keep `follows` and build locally. Either way, the lock must end up on current nixpkgs.

**Service.**
- Use `programs.noctalia.systemd.enable = true`, and delete the hand-written unit in `configs/theming/noctalia.nix`.
- A rebuild must restart the shell when its config changes. The module's `X-Restart-Triggers` is expected to cover this. Verify it.

**Config.**
- Write the v5 TOML through `programs.noctalia.settings`, either as a Nix attrset or a `.toml` file in the repo (builder's call).
- Keep `checkConfig = true`.
- Delete `noctalia-config.json`.

**Settings to carry over (v4 → v5).** Map each to its closest v5 equivalent. Drop and note any that have none.
- Bar
  - Floating, top, compact.
  - Capsules on at around 0.55 opacity, background transparent.
  - Widgets:
    - left: workspaces (index labels, hide unoccupied), active window (icon only)
    - center: clock (`hh:mm a ddd, MMM dd`, font IosevkaTerm NFP Thin Obl), Time Blocks
    - right: sysmon (CPU usage + temp, memory, compact), tray, Bluetooth, notifications (unread badge), battery, volume (middle-click runs `pwvucontrol || pavucontrol`), brightness, control centre
- Theme
  - Colours come from the wallpaper, dark mode. Kanagawa is the fallback or predefined scheme.
  - GTK sync was on (`syncGsettings`). Keep it if v5 has an equivalent.
- Wallpaper
  - Enabled, directory `configs/theming/wallpapers` (absolute path in the repo checkout).
  - Random rotation was not enabled.
- Lock screen
  - Avatar `~/.face`.
  - Lock on suspend.
  - Session buttons shown on the lock screen.
  - Countdown enabled at 10 s.
- Notifications: enabled, top right.
- UI: panels attached to the bar, panel background opacity around 0.25, translucent widgets.
- Dock, desktop widgets, idle, hooks and night light were all disabled in v4. Leave them off.

**Templates.**
- Port the rofi user template (`configs/rofi.nix`, `rofi/colors-template.rasi`) to v5 template syntax (`{{ }}`, under `[theme.templates.user.rofi]`).
- Keep the `seedRofiColors` activation fallback.
- Update the comment in `rofi.nix`, which references v4 option names.

**Dropped.**
- The SessionMenu QML transparency patch (`overrideAttrs` in `noctalia.nix`) goes away. If v5 has a setting for session-menu card opacity, use it. Otherwise accept the default.

**niri** (`configs/theming/niri.nix`).
- Super+V → `noctalia msg panel-toggle clipboard`.
- Ctrl+Alt+Delete → `noctalia msg panel-toggle session`.
- Update the comments that mention the v4 unit and the `TODO: Change to quickshell` line.
- Optional: v5 docs recommend niri's `launch_apps_as_systemd_services` when using the systemd unit. Check, and decide.

**`qml-niri`.**
- This flake input (`github:imiric/qml-niri`) is installed from `modules/packages/external.nix`. It brings its own quickshell built against nixpkgs' Qt. Nothing in the repo uses it once v4 is gone.
- The user cleared it for removal. Remove it if it blocks the nixpkgs bump.
- If it builds fine, leave it.

**Other references.**
- `modules/packages/wm.nix` and `modules/packages/external.nix` have comments about `noctalia-qs` and noctalia packaging. Update them.
- Update `configs/zen.nix` if it references v4 paths.
- Update the memories `noctalia-timeblock-plugin` and `flake-lock-holds` once done.

**Runtime state.**
- v5 writes GUI changes to `~/.local/state/noctalia/settings.toml`, and that file overrides the Nix config.
- That's acceptable, but mention it in a comment so a "my config change didn't apply" moment has an answer.

## Verification

- `nix flake check` or a `toplevel` build of `frosties` succeeds on the updated nixpkgs.
- `noctalia config validate` passes. With `checkConfig` this happens at build time.
- After `just switch` and a relog, verify that:
  - the bar shows on top with the listed widgets
  - Time Blocks shows today's blocks seeded from the v4 data, and each quick action works
  - Super+V and Ctrl+Alt+Delete work
  - changing the wallpaper recolours rofi
  - `systemctl --user status noctalia` is active
- The plugin's Luau logic (day generation, active-block selection, push, end now) gets whatever test harness v5 supports. If none exists, test it with a small standalone Luau script run in `luau`.

## Left to the builder

- Exact v5 option names and widget ids, from the v5 docs and source.
- Plugin file layout and Luau structure.
- Cachix versus local build.
- How to split the work into commits. Suggested: (1) the flake, the module and the bar config with the v4 plugin disabled; (2) Time Blocks v5; (3) the nixpkgs bump.
