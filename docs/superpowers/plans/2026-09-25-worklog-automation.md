# Automated Daily Worklog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically generate and append a daily work log entry to `~/worklog.md`, summarizing git activity across `~/self_projects` and `~/work`, via a systemd user timer that calls headless Claude Haiku.

**Architecture:** A single bash script (`worklog-report.sh`) with four pure-ish functions — repo discovery, per-repo git activity collection, prompt building + `claude -p` invocation, and output writing — composed by a `main()` that also implements the "skip if nothing happened" and "abort without writing on failure" rules. The script is packaged with `pkgs.writeShellApplication` (which shellcheck-lints it at build time) in a new `configs/worklog.nix` home-manager module, alongside a `systemd.user.service` + `systemd.user.timer` pair firing 18:00 Mon–Fri.

**Tech Stack:** bash, git, the system's `claude-code` package (headless `claude -p --model haiku`), Nix/home-manager (`writeShellApplication`, `systemd.user.services`, `systemd.user.timers`).

**Spec:** `docs/superpowers/specs/2026-09-25-worklog-automation-design.md`

## Global Constraints

- Watched directories are exactly `~/self_projects` and `~/work` (spec: Scope).
- Repo discovery: `find <dir> -maxdepth 3 -name .git -type d`, deduplicated, skipping nested `.git` dirs under `node_modules` (spec: Data collection).
- A repo counts as "active today" only if it has commits by the repo's configured `user.email` since local midnight, OR a non-empty `git diff`, OR a non-empty `git diff --staged` (spec: Data collection).
- If zero repos are active, the script must exit without writing anything to `~/worklog.md` — no empty dated section ever (spec: Data collection, Output).
- Exactly one `claude -p --model haiku` call per run, with all active repos' data in a single prompt (spec: Report generation).
- Output has exactly two sections: a one-liner bullet per touched project, then a detailed per-project narrative (spec: Report generation).
- `~/worklog.md` is append-only: new runs add a `## YYYY-MM-DD` section at the end; past sections are never rewritten (spec: Output).
- `--dry-run` produces the same collection + summarization, but prints to stdout instead of appending (spec: Invocation modes).
- On `claude -p` failure or empty output, abort with a non-zero exit and write nothing (spec: Error handling).
- Timer: systemd user timer, 18:00, Monday–Friday only (spec: Scheduling, confirmed in chat).

## Review Focus

- A repo whose `user.email` is unset locally (no local override, no global fallback configured) — `collect_repo_activity` must not crash; it should treat the repo as having no commit activity and fall back to diff-only detection.
- A repo path containing spaces (common under `~/self_projects` for cloned repos with descriptive names) — repo discovery and every `git -C "$repo"` call must not word-split it.
- `~/worklog.md` not existing yet on the very first run — `write_output` must create it without a leading blank line or a crash on `[[ -s "$log_file" ]]`.
- `claude -p` returning exit 0 but an empty string (e.g. hits a content filter or truncates) — must be treated the same as a failure, not written as an empty section.
- Running twice in the same day (e.g. a manual `--dry-run` followed by the real timer firing) — the real run must still append its own dated section; the plan does not dedupe same-day sections, so this is expected behavior worth calling out rather than a bug to fix.

---

## File Structure

- Create: `configs/worklog/worklog-report.sh` — the script, all logic.
- Create: `configs/worklog/tests/run.sh` — a plain bash assertion script exercising each function against fixture git repos in a temp dir. This repo has no test framework (no bats/pytest/CI), so this follows the spec's own testing approach (manual verification) while still giving a regression check you can re-run instead of eyeballing output each time.
- Create: `configs/worklog.nix` — the home-manager module: packages the script via `writeShellApplication`, defines the systemd service + timer.
- Modify: `home.nix` — add `./configs/worklog.nix` to `imports`.

## Task 1: Repo discovery and per-repo activity collection

**Files:**
- Create: `configs/worklog/worklog-report.sh`
- Create: `configs/worklog/tests/run.sh`

**Interfaces:**
- Produces: `find_repos` — no args, prints one repo path per line (absolute, no trailing `/.git`) on stdout, deduplicated and sorted.
- Produces: `collect_repo_activity <repo_path>` — returns exit 0 and prints a markdown block (`### <repo>` + commits/diff/staged sections, whichever are non-empty) if the repo had activity today; returns exit 1 and prints nothing otherwise.

- [ ] **Step 1: Write the script skeleton with `find_repos` and `collect_repo_activity`**

Create `configs/worklog/worklog-report.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

watch_dirs=("$HOME/self_projects" "$HOME/work")
log_file="${WORKLOG_FILE:-$HOME/worklog.md}"

find_repos() {
  local dir
  for dir in "${watch_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    find "$dir" -maxdepth 3 -type d -name .git 2>/dev/null
  done | grep -v '/node_modules/' | sed 's#/\.git$##' | sort -u
}

collect_repo_activity() {
  local repo="$1"
  local author="" commits="" diff="" staged=""
  author="$(git -C "$repo" config user.email 2>/dev/null || true)"
  if [[ -n "$author" ]]; then
    commits="$(git -C "$repo" log --author="$author" --since=midnight --stat 2>/dev/null || true)"
  fi
  diff="$(git -C "$repo" diff 2>/dev/null || true)"
  staged="$(git -C "$repo" diff --staged 2>/dev/null || true)"

  if [[ -z "$commits" && -z "$diff" && -z "$staged" ]]; then
    return 1
  fi

  printf '### %s\n\n' "$repo"
  [[ -n "$commits" ]] && printf '**Commits:**\n```\n%s\n```\n\n' "$commits"
  [[ -n "$diff" ]] && printf '**Uncommitted changes:**\n```diff\n%s\n```\n\n' "$diff"
  [[ -n "$staged" ]] && printf '**Staged changes:**\n```diff\n%s\n```\n\n' "$staged"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "worklog-report: not fully implemented yet" >&2
  exit 1
fi
```

The `BASH_SOURCE` guard at the bottom lets `tests/run.sh` `source` this file to call its functions directly without triggering `main` (added in Task 4).

- [ ] **Step 2: Write the fixture-based test for both functions**

Create `configs/worklog/tests/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    fail=1
  else
    echo "PASS: $desc"
  fi
}

# --- fixtures ---
mkdir -p "$tmp/self_projects/active repo" "$tmp/self_projects/idle-repo" "$tmp/work/uncommitted-repo"

git init -q "$tmp/self_projects/active repo"
git -C "$tmp/self_projects/active repo" config user.email "test@example.com"
git -C "$tmp/self_projects/active repo" config user.name "Test"
echo hi > "$tmp/self_projects/active repo/file.txt"
git -C "$tmp/self_projects/active repo" add file.txt
git -C "$tmp/self_projects/active repo" commit -q -m "test commit"

git init -q "$tmp/self_projects/idle-repo"
git -C "$tmp/self_projects/idle-repo" config user.email "test@example.com"
git -C "$tmp/self_projects/idle-repo" config user.name "Test"

git init -q "$tmp/work/uncommitted-repo"
git -C "$tmp/work/uncommitted-repo" config user.email "test@example.com"
git -C "$tmp/work/uncommitted-repo" config user.name "Test"
echo base > "$tmp/work/uncommitted-repo/tracked.txt"
git -C "$tmp/work/uncommitted-repo" add tracked.txt
git -C "$tmp/work/uncommitted-repo" commit -q -m "base"
echo changed >> "$tmp/work/uncommitted-repo/tracked.txt"

mkdir -p "$tmp/work/no-email-repo"
git init -q "$tmp/work/no-email-repo"
echo base > "$tmp/work/no-email-repo/tracked.txt"
git -c user.email=t@example.com -c user.name=t -C "$tmp/work/no-email-repo" add tracked.txt
git -c user.email=t@example.com -c user.name=t -C "$tmp/work/no-email-repo" commit -q -m "base"
echo changed >> "$tmp/work/no-email-repo/tracked.txt"
# user.email intentionally left unconfigured for this repo (neither local
# nor inherited from a global config in this isolated HOME), to exercise
# the case where `git config user.email` returns nothing.

# --- load functions under test ---
watch_dirs=("$tmp/self_projects" "$tmp/work")
# shellcheck source=/dev/null
source "$script_dir/../worklog-report.sh"

# --- find_repos ---
found="$(find_repos)"
assert_eq "finds all three repos" "3" "$(echo "$found" | wc -l)"
if echo "$found" | grep -qF "$tmp/self_projects/active repo"; then
  echo "PASS: finds repo with a space in its path"
else
  echo "FAIL: finds repo with a space in its path"
  fail=1
fi

# --- collect_repo_activity ---
if collect_repo_activity "$tmp/self_projects/active repo" > /dev/null; then
  echo "PASS: active repo (commit today) reports activity"
else
  echo "FAIL: active repo (commit today) reports activity"
  fail=1
fi

if collect_repo_activity "$tmp/self_projects/idle-repo" > /dev/null; then
  echo "FAIL: idle repo incorrectly reports activity"
  fail=1
else
  echo "PASS: idle repo reports no activity"
fi

if collect_repo_activity "$tmp/work/uncommitted-repo" > /dev/null; then
  echo "PASS: repo with only an uncommitted diff reports activity"
else
  echo "FAIL: repo with only an uncommitted diff reports activity"
  fail=1
fi

# HOME is overridden to an empty dir with no .gitconfig so `git config
# user.email` genuinely returns nothing here, instead of falling back to
# the real user's global config.
mkdir -p "$tmp/fake_home"
if HOME="$tmp/fake_home" collect_repo_activity "$tmp/work/no-email-repo" > /dev/null; then
  echo "PASS: repo with no configured user.email still reports diff activity"
else
  echo "FAIL: repo with no configured user.email still reports diff activity"
  fail=1
fi

exit "$fail"
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `chmod +x configs/worklog/worklog-report.sh configs/worklog/tests/run.sh && bash configs/worklog/tests/run.sh`

Expected: every line starts `PASS:`, script exits 0. If `find_repos` returns the wrong count, check that `sed 's#/\.git$##'` matched (GNU sed syntax, present via `pkgs.gnused`/system bash).

- [ ] **Step 4: Commit**

```bash
git add configs/worklog/worklog-report.sh configs/worklog/tests/run.sh
git commit -m "worklog: add repo discovery and activity collection"
```

## Task 2: Prompt building and Claude invocation

**Files:**
- Modify: `configs/worklog/worklog-report.sh`
- Modify: `configs/worklog/tests/run.sh`

**Interfaces:**
- Consumes: nothing from Task 1 directly (takes the assembled activity text as a string).
- Produces: `build_prompt <activity_text>` — prints the full prompt string to stdout.
- Produces: `call_summarizer <prompt_text>` — pipes the prompt to `claude -p --model haiku` and prints its stdout; propagates `claude`'s exit code.

- [ ] **Step 1: Add `build_prompt` and `call_summarizer` to the script**

Insert into `configs/worklog/worklog-report.sh`, after `collect_repo_activity` and before the `BASH_SOURCE` guard block:

```bash
build_prompt() {
  local activity="$1"
  cat <<EOF
You are generating an entry for a personal engineering work log from raw
git activity below. Produce markdown with exactly two sections, in this
order:

## Summary
One bullet per project below, one line each, in plain language (not a
commit-message dump).

## Details
A short narrative per project describing what was actually done, written
the way an engineer would describe it in their own log.

Do not invent activity that isn't reflected in the data. Do not add any
other sections or preamble.

$activity
EOF
}

call_summarizer() {
  local prompt="$1"
  printf '%s' "$prompt" | claude -p --model haiku
}
```

- [ ] **Step 2: Write a stubbed-`claude` test for both functions**

Append to `configs/worklog/tests/run.sh`, just before the final `exit "$fail"` line:

```bash
# --- build_prompt ---
prompt="$(build_prompt "### repo-a

**Commits:**
did stuff
")"
if echo "$prompt" | grep -q "## Summary" && echo "$prompt" | grep -q "## Details" && echo "$prompt" | grep -q "repo-a"; then
  echo "PASS: build_prompt includes both section headers and the activity text"
else
  echo "FAIL: build_prompt includes both section headers and the activity text"
  fail=1
fi

# --- call_summarizer (stubbed claude) ---
stub_bin="$tmp/stub_bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/claude" <<'EOF'
#!/usr/bin/env bash
input="$(cat)"
if [[ "$input" == *"trigger-failure"* ]]; then
  exit 1
fi
echo "## Summary
- stub summary
## Details
stub details"
EOF
chmod +x "$stub_bin/claude"

if summary="$(PATH="$stub_bin:$PATH" call_summarizer "hello world")" && [[ "$summary" == *"stub summary"* ]]; then
  echo "PASS: call_summarizer returns the stub's output"
else
  echo "FAIL: call_summarizer returns the stub's output"
  fail=1
fi

if PATH="$stub_bin:$PATH" call_summarizer "please trigger-failure" > /dev/null 2>&1; then
  echo "FAIL: call_summarizer propagates a non-zero exit from claude"
  fail=1
else
  echo "PASS: call_summarizer propagates a non-zero exit from claude"
fi
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `bash configs/worklog/tests/run.sh`
Expected: all `PASS:` lines, exit 0.

- [ ] **Step 4: Commit**

```bash
git add configs/worklog/worklog-report.sh configs/worklog/tests/run.sh
git commit -m "worklog: add prompt building and claude invocation"
```

## Task 3: Output writer

**Files:**
- Modify: `configs/worklog/worklog-report.sh`
- Modify: `configs/worklog/tests/run.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks directly (takes a summary string + a dry-run flag).
- Produces: `write_output <summary_text> <dry_run:0|1>` — dry_run=1 prints `## <date>\n\n<summary>` to stdout; dry_run=0 appends the same to `$log_file`, creating it if absent, without a spurious leading blank line on a fresh file.

- [ ] **Step 1: Add `write_output` to the script**

Insert into `configs/worklog/worklog-report.sh`, after `call_summarizer`:

```bash
write_output() {
  local summary="$1" dry_run="$2"
  local heading
  heading="## $(date +%Y-%m-%d)"

  if [[ "$dry_run" == "1" ]]; then
    printf '%s\n\n%s\n' "$heading" "$summary"
    return 0
  fi

  local prefix=""
  [[ -s "$log_file" ]] && prefix=$'\n'
  printf '%s%s\n\n%s\n' "$prefix" "$heading" "$summary" >> "$log_file"
}
```

- [ ] **Step 2: Write the test for both modes**

Append to `configs/worklog/tests/run.sh`, before `exit "$fail"`:

```bash
# --- write_output: dry-run ---
dry_output="$(write_output "test summary" "1")"
if echo "$dry_output" | head -1 | grep -qE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}$' && echo "$dry_output" | grep -q "test summary"; then
  echo "PASS: write_output dry-run prints heading and summary, writes no file"
else
  echo "FAIL: write_output dry-run prints heading and summary, writes no file"
  fail=1
fi

# --- write_output: fresh file, no leading blank line ---
log_file="$tmp/fresh-worklog.md"
write_output "first entry" "0"
first_line="$(head -1 "$log_file")"
if [[ "$first_line" =~ ^\#\#\ [0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "PASS: write_output on a fresh file starts with the heading, no leading blank line"
else
  echo "FAIL: write_output on a fresh file starts with the heading, no leading blank line"
  fail=1
fi

# --- write_output: appends a second entry ---
write_output "second entry" "0"
if grep -q "first entry" "$log_file" && grep -q "second entry" "$log_file"; then
  echo "PASS: write_output appends without erasing prior entries"
else
  echo "FAIL: write_output appends without erasing prior entries"
  fail=1
fi
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `bash configs/worklog/tests/run.sh`
Expected: all `PASS:` lines, exit 0.

- [ ] **Step 4: Commit**

```bash
git add configs/worklog/worklog-report.sh configs/worklog/tests/run.sh
git commit -m "worklog: add output writer"
```

## Task 4: Wire together `main()` and error handling

**Files:**
- Modify: `configs/worklog/worklog-report.sh`
- Modify: `configs/worklog/tests/run.sh`

**Interfaces:**
- Consumes: `find_repos`, `collect_repo_activity` (Task 1); `build_prompt`, `call_summarizer` (Task 2); `write_output` (Task 3).
- Produces: `build_activity_report` (no args, concatenates every active repo's block, empty string if none) and `main "$@"` (script entry point: exit 0 silently if no activity, exit 1 with a stderr message if summarization fails/returns empty, otherwise calls `write_output`).

- [ ] **Step 1: Replace the placeholder guard block with `build_activity_report` and `main`**

Replace the `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi` placeholder block at the bottom of `configs/worklog/worklog-report.sh` with:

```bash
build_activity_report() {
  local repo activity report=""
  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    if activity="$(collect_repo_activity "$repo")"; then
      report+="$activity"
    fi
  done < <(find_repos)
  printf '%s' "$report"
}

main() {
  local dry_run=0
  [[ "${1:-}" == "--dry-run" ]] && dry_run=1

  local activity
  activity="$(build_activity_report)"

  if [[ -z "$activity" ]]; then
    exit 0
  fi

  local prompt summary
  prompt="$(build_prompt "$activity")"

  if ! summary="$(call_summarizer "$prompt")" || [[ -z "$summary" ]]; then
    echo "worklog-report: claude summarization failed" >&2
    exit 1
  fi

  write_output "$summary" "$dry_run"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 2: Write the integration test**

Append to `configs/worklog/tests/run.sh`, before `exit "$fail"`:

```bash
# --- main(): no activity anywhere -> exit 0, no output, no file write ---
mkdir -p "$tmp/empty_self_projects" "$tmp/empty_work"
(
  watch_dirs=("$tmp/empty_self_projects" "$tmp/empty_work")
  log_file="$tmp/should-not-exist.md"
  set +e
  out="$(main --dry-run 2>&1)"
  code=$?
  set -e
  if [[ $code -eq 0 && -z "$out" && ! -e "$log_file" ]]; then
    echo "PASS: main exits 0 silently with zero activity"
  else
    echo "FAIL: main exits 0 silently with zero activity (code=$code out=$out)"
    fail=1
  fi
)

# --- main(): activity present, claude fails -> exit 1, no file write ---
(
  watch_dirs=("$tmp/self_projects")
  log_file="$tmp/should-also-not-exist.md"
  claude() { return 1; }
  export -f claude
  set +e
  main --dry-run > /dev/null 2>&1
  code=$?
  set -e
  if [[ $code -ne 0 && ! -e "$log_file" ]]; then
    echo "PASS: main aborts without writing when claude fails"
  else
    echo "FAIL: main aborts without writing when claude fails"
    fail=1
  fi
)

# --- main(): activity present, claude exits 0 but prints nothing -> exit 1, no file write ---
(
  watch_dirs=("$tmp/self_projects")
  log_file="$tmp/should-not-exist-either.md"
  claude() { :; }
  export -f claude
  set +e
  main --dry-run > /dev/null 2>&1
  code=$?
  set -e
  if [[ $code -ne 0 && ! -e "$log_file" ]]; then
    echo "PASS: main treats empty claude output as a failure and writes nothing"
  else
    echo "FAIL: main treats empty claude output as a failure and writes nothing"
    fail=1
  fi
)

# --- main(): activity present, dry-run prints two sections ---
(
  watch_dirs=("$tmp/self_projects")
  claude() { echo "## Summary
- did stuff
## Details
did some stuff in detail"; }
  export -f claude
  out="$(main --dry-run)"
  if echo "$out" | grep -q "## Summary" && echo "$out" | grep -q "## Details"; then
    echo "PASS: main --dry-run produces both sections end to end"
  else
    echo "FAIL: main --dry-run produces both sections end to end"
    fail=1
  fi
)
```

Note: `call_summarizer` shells out to the `claude` command by name, so exporting a shell function named `claude` (rather than a PATH stub) intercepts it cleanly inside the subshell without touching `PATH` for the rest of the suite.

- [ ] **Step 3: Run the test to verify it passes**

Run: `bash configs/worklog/tests/run.sh`
Expected: all `PASS:` lines, exit 0.

- [ ] **Step 4: Manual dry-run against real repos**

Run: `bash configs/worklog/worklog-report.sh --dry-run`
Expected: either no output (if nothing changed in `~/self_projects` or `~/work` today) or a two-section markdown report on stdout, with `~/worklog.md` untouched either way (`git status`/`ls -la ~/worklog.md` unchanged from before the run). This exercises the real `claude -p --model haiku` call, so review the summary quality here before wiring the timer in Task 5.

- [ ] **Step 5: Commit**

```bash
git add configs/worklog/worklog-report.sh configs/worklog/tests/run.sh
git commit -m "worklog: wire main() with error handling"
```

## Task 5: Nix packaging and systemd timer

**Files:**
- Create: `configs/worklog.nix`
- Modify: `home.nix:6-26` (add import)

**Interfaces:**
- Consumes: `configs/worklog/worklog-report.sh` (Task 4) as the packaged script's source.
- Produces: a `worklog-report` binary on `$PATH` (via `home.packages`), plus `systemd.user.services.worklog` and `systemd.user.timers.worklog`.

- [ ] **Step 1: Write the nix module**

Create `configs/worklog.nix`:

```nix
{
  pkgs,
  ...
}:

let
  # Real logic lives in worklog-report.sh so it can be linted with shellcheck
  # (via writeShellApplication) and exercised by configs/worklog/tests/run.sh
  # outside of a Nix rebuild.
  worklogScript = pkgs.writeShellApplication {
    name = "worklog-report";
    runtimeInputs = [
      pkgs.git
      pkgs.claude-code
      pkgs.gnugrep
      pkgs.gnused
      pkgs.findutils
    ];
    text = builtins.readFile ./worklog/worklog-report.sh;
  };
in
{
  home.packages = [ worklogScript ];

  # Summarizes today's git activity across ~/self_projects and ~/work into
  # ~/worklog.md via headless Claude Haiku. See
  # docs/superpowers/specs/2026-09-25-worklog-automation-design.md.
  systemd.user.services.worklog = {
    Unit = {
      Description = "Generate today's work log entry";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${worklogScript}/bin/worklog-report";
    };
  };

  systemd.user.timers.worklog = {
    Unit = {
      Description = "Daily timer for the worklog service";
    };
    Timer = {
      OnCalendar = "Mon..Fri 18:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
```

`runtimeInputs` makes `writeShellApplication` wrap the script with those packages prepended to `PATH`, so the bare `git`/`claude` calls inside `worklog-report.sh` resolve without needing an explicit `Environment=PATH=...` in the systemd unit.

- [ ] **Step 2: Import the module**

In `home.nix`, add the import alongside the other `configs/*.nix` entries:

```nix
    ./configs/wezterm.nix
    ./configs/worklog.nix
```

- [ ] **Step 3: Verify the module builds**

Run: `nix flake check .` (or, if that's slow in this repo, `nh os build .` per this repo's usual workflow) from `/home/bhaswata/dotfiles/nixcfg`.
Expected: build succeeds. A shellcheck failure inside `worklog-report.sh` will fail this build — fix it here rather than suppressing it, since `writeShellApplication` treats shellcheck as part of the build.

- [ ] **Step 4: Apply and verify the timer is registered**

Run: `just switch`
Then run: `systemctl --user list-timers worklog.timer`
Expected: a row for `worklog.timer` with a `NEXT` time matching the next Mon–Fri 18:00.

- [ ] **Step 5: Manual end-to-end run through the installed unit**

Run: `systemctl --user start worklog.service && journalctl --user -u worklog.service -n 20`
Expected: exit code 0 in the journal, and (if there was real activity today) a new dated section appended to `~/worklog.md`. Re-run `bash configs/worklog/worklog-report.sh --dry-run` beforehand if you want to preview the entry before letting the real service append it.

- [ ] **Step 6: Commit**

```bash
git add configs/worklog.nix home.nix
git commit -m "worklog: package script and add systemd timer"
```
