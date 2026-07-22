# Time Blocks

A day-scheduling / time-blocking plugin for [Noctalia Shell](https://github.com/noctalia-dev). It lays out the current day as a sequence of labeled time blocks (Scrum, Office Work, Lunch, …), tracks which block is active right now, and lets the schedule be freely rearranged — both as a saved recurring **template** and as one-off **daily overrides**.

Nothing about the schedule is hardcoded: every block name, time, count, color and recurrence is user-authored data stored in plugin settings and editable from the UI.

## Surfaces

- **Bar widget** — compact indicator showing the current block's label + time remaining, or *Unscheduled* during a gap. Left-click opens the panel; right-click for quick actions.
- **Panel** — a proportional time axis with a *now* line, the editable list of today's blocks, and the low-friction override actions.
- **Settings** — manage the recurring template (per-weekday recurrence) and the transition-notification toggle.

## Two layers

1. **Template** — the recurring baseline day (edited in Settings). Each block has a set of weekdays it recurs on.
2. **Today's instance** — generated from the template once per day, then freely editable in the panel. Editing today never touches the template unless you press **Save as template**. A shell reload mid-day keeps your edited instance (it only regenerates on a new calendar day).

## Override-today actions (panel + bar menu + IPC)

- **End now** — shrink the current block to end at the present moment.
- **Insert now** — drop an ad-hoc block starting now.
- **+Nm** — push every not-yet-started block later by N minutes.
- **Reset today** — rebuild today from the template.
- **Save as template** — overwrite the standing template with today's blocks.

Overlapping blocks are allowed (a ⚠ marker warns you); the currently active block during an overlap is the most-recently-started one.

## IPC (scriptable from keybinds)

```sh
qs -c noctalia-shell ipc call plugin:timeblock toggle       # open/close panel
qs -c noctalia-shell ipc call plugin:timeblock current      # JSON of the active block
qs -c noctalia-shell ipc call plugin:timeblock next         # end current, advance
qs -c noctalia-shell ipc call plugin:timeblock endNow
qs -c noctalia-shell ipc call plugin:timeblock insertNow
qs -c noctalia-shell ipc call plugin:timeblock push 30      # push remaining by 30 min
qs -c noctalia-shell ipc call plugin:timeblock resetToday
```

## Data model

Each block: `id` (stable), `label`, `start`/`end` (minutes since midnight), `color` (semantic theme key), `notes`. Template blocks also carry `days` (weekday ints `0`=Sun … `6`=Sat); today's instances carry `skipped` and `templateId`.

## Install (this repo)

The plugin is symlinked into `~/.config/noctalia/plugins/timeblock` by `configs/theming/noctalia.nix` (via `xdg.configFile … recursive = true`). Rebuild home-manager, then enable **Time Blocks** and add its bar widget in Noctalia.
