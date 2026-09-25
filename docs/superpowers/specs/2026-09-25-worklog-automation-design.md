# Automated daily work log

## Purpose

The user currently writes an end-of-day work log by hand. This replaces
that manual step with a script that inspects git activity across the
user's two coding directories and generates the entry automatically via
Claude Haiku, appending it to a running log file.

## Success criteria

- No manual writing required on a normal work day.
- The log stays readable over months (one file, dated sections).
- Days with no coding activity produce no entry (no noise).
- The script can be run by hand to preview output before trusting the
  automatic timer.

## Scope

Directories watched: `~/self_projects`, `~/work`.

Out of scope: non-git file activity (raw filesystem watching), a UI,
editing/removing past entries, multi-machine sync of the log file.

## Data collection

For each directory found via `find ~/self_projects ~/work -maxdepth 3
-name .git -type d` (deduplicated, skipping nested `.git` dirs inside
`node_modules` etc.):

- Commits authored by the user since local midnight:
  `git log --author=<user> --since=midnight --stat`
- Uncommitted changes: `git diff` and `git diff --staged`

If a repo has neither commits nor a working-tree diff for the day, it is
dropped from the report entirely — it did not happen for the purposes of
the log.

If **no** repo has any activity for the day, the script exits without
writing anything (no empty dated section is ever appended).

## Report generation

One `claude -p --model haiku` call per run, with a single prompt
containing all touched repos' raw git data, each block labeled with its
repo path. A single call (rather than one per repo) keeps this cheap and
lets the model notice cross-repo context (e.g. related work spanning two
projects) — Haiku is sufficient here since the job is summarization/
extraction over text the model didn't have to reason hard about, not
code generation.

The prompt asks for exactly two markdown sections:

1. **One-liner per touched project** — a bullet list, one line per repo
   that had activity, in plain language (not a commit-message dump).
2. **Detailed work log** — a narrative paragraph or short list per repo
   describing what was actually done, written the way the user would
   write it themselves for their own record.

## Output

Appended to `~/worklog.md`. Each run adds:

```markdown
## 2026-09-25

<one-liner section>

<detailed section>
```

The file is created if it does not exist. Entries are append-only; the
script never rewrites past sections.

## Invocation modes

- Normal run: collects, summarizes, appends.
- `--dry-run`: collects and summarizes as normal, but prints the result
  to stdout instead of appending to `~/worklog.md`. Used for manually
  verifying prompt/output quality before trusting the timer.

## Scheduling

A systemd user timer + service pair, defined in a new
`configs/worklog.nix` home-manager module (following this repo's
`configs/<name>.nix` + `configs/<name>/` convention):

- Fires at 18:00, Monday–Friday only.
- Runs the script with no flags (real append mode).
- Failures (non-zero exit from the script or from `claude -p`) are
  logged to the systemd journal; no partial or empty entry is written to
  `~/worklog.md` on failure.

## Error handling

- `claude -p` exits non-zero or produces empty/unparseable output → abort
  without writing, error visible via `journalctl --user -u worklog`.
- A repo in a weird state (detached HEAD, no commits ever) is still
  handled: commit collection may return nothing, diff collection still
  runs independently.

## Testing

- Manual `--dry-run` runs against the user's real repos, iterated until
  prompt/output quality is acceptable.
- The systemd unit is enabled only after a few successful manual runs.
