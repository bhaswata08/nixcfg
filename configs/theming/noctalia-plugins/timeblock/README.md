# Time Blocks (Noctalia v5)

A day-scheduling / time-blocking plugin for [Noctalia Shell](https://github.com/noctalia-dev) v5. It lays out the current day as a sequence of labeled time blocks (Scrum, Deep Work, Lunch, …), tracks the active block with a live countdown, and lets the schedule be freely rearranged — both as a recurring standing **template** and as one-off **daily overrides**.

All schedule logic is implemented in pure Luau (`lib/schedule.luau`) and verified with unit tests.

## Plugin Entries

The plugin exposes four v5 entries:

- **`bhaswata/timeblock:bar`** — Compact bar widget displaying the current block's label and time remaining (e.g. `Scrum · 25m left`), or `Unscheduled` (`· next in …` during gaps). Left-click toggles the main panel; right-click toggles the quick-actions panel.
- **`bhaswata/timeblock:panel`** — Main panel containing quick override buttons, a proportional time axis with the *now* indicator, and the editable list of today's blocks (label, start/end times in `HH:MM`, color role, skip toggle, delete).
- **`bhaswata/timeblock:actions`** — Low-friction quick-actions panel with buttons for `End now`, `Insert now`, `+15m`, and `Reset today`.
- **`bhaswata/timeblock:template`** — Standing template editor allowing blocks to recur on specific weekdays (Sunday through Saturday).

## Two Layers

1. **Template** — The recurring weekly baseline day. Each block defines the weekdays it recurs on.
2. **Today's Instance** — Derived from the template at midnight or on the first run of the day. Freeform edits made today do not affect the template unless explicitly saved via **Save as template**. Reloading Noctalia mid-day preserves today's edits.

## CLI & IPC Commands

Control the plugin or bind shortcuts via Noctalia IPC:

```sh
# Override actions sent to the bar widget
noctalia msg plugin bhaswata/timeblock bar endNow       # shrink active block to end now (alias: next)
noctalia msg plugin bhaswata/timeblock bar insertNow    # insert ad-hoc block starting now
noctalia msg plugin bhaswata/timeblock bar push 15      # push remaining blocks by 15 min (or default pushIncrement)
noctalia msg plugin bhaswata/timeblock bar resetToday   # regenerate today from template

# Toggle panels
noctalia msg panel-toggle bhaswata/timeblock:panel      # open/close main panel
noctalia msg panel-toggle bhaswata/timeblock:actions    # open/close quick actions panel
noctalia msg panel-toggle bhaswata/timeblock:template   # open/close template manager
```

## Data Location & v4 Migration

- **State File**: State is stored at `pluginDataDir() / state.json` (typically `~/.local/state/noctalia/plugins/bhaswata/timeblock/state.json`). The plugin source directory is in the read-only Nix store, so plugin state is never saved in the source tree.
- **v4 Import**: If `state.json` does not exist upon initial launch, the plugin automatically imports legacy v4 configuration from `~/.config/noctalia/plugins/timeblock/settings.json`, normalizes the schema via `schedule.importV4`, and saves the initial v5 state. The legacy v4 file is read once and never overwritten.

## Running Tests

The pure Luau schedule core has zero external runtime dependencies and can be run with the Luau CLI:

```sh
nix shell nixpkgs#luau -c luau configs/theming/noctalia-plugins/timeblock/tests/schedule_test.luau
```
