#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${watch_dirs+x}" ]]; then
  watch_dirs=("$HOME/self_projects" "$HOME/work")
fi
log_file="${WORKLOG_FILE:-$HOME/worklog.md}"
# Caps the file list handed to the file-activity session, so a day that
# rewrote thousands of files (a dataset dump, a build) can't flood the prompt.
max_touched_files="${WORKLOG_MAX_FILES:-400}"

find_repos() {
  local dir
  # Depth 6 reaches repos like ~/work/projects/llmhosting/syntheticdatagen/synthdata.
  # Dependency and cache dirs are pruned so the deeper walk stays cheap and
  # vendored checkouts inside them aren't mistaken for the user's repos.
  for dir in "${watch_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    find "$dir" -maxdepth 6 \
      -type d \( -name node_modules -o -name .venv -o -name venv \
        -o -name .cache -o -name __pycache__ -o -name .direnv \
        -o -name .tox -o -name .mypy_cache -o -name target \) -prune \
      -o -type d -name .git -print -prune 2>/dev/null
  done | sed 's#/\.git$##' | sort -u
}

_touched_since() {
  local repo="$1" cutoff="$2" f mtime
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ -f "$repo/$f" ]] || continue
    # A deleted file can't be stat'd, so it's skipped rather than assumed
    # recent — we'd rather miss a same-day deletion than keep resurrecting
    # months-old diffs just because one of the changed paths is gone.
    mtime="$(stat -c %Y "$repo/$f" 2>/dev/null || echo 0)"
    (( mtime >= cutoff )) && return 0
  done
  return 1
}

collect_repo_activity() {
  local repo="$1"
  local author="" commits="" diff="" staged=""
  local midnight
  midnight="$(date -d "today 00:00" +%s)"
  author="$(git -C "$repo" config user.email 2>/dev/null || true)"
  if [[ -n "$author" ]]; then
    commits="$(git -C "$repo" log --author="$author" --since=midnight --stat 2>/dev/null || true)"
  fi
  diff="$(git -C "$repo" diff 2>/dev/null || true)"
  if [[ -n "$diff" ]] && ! git -C "$repo" diff --name-only 2>/dev/null | _touched_since "$repo" "$midnight"; then
    diff=""
  fi
  if [[ ${#diff} -gt 15000 ]]; then
    diff="${diff:0:15000}"$'\n'"[... truncated, ${#diff} bytes total ...]"
  fi
  staged="$(git -C "$repo" diff --staged 2>/dev/null || true)"
  if [[ -n "$staged" ]] && ! git -C "$repo" diff --staged --name-only 2>/dev/null | _touched_since "$repo" "$midnight"; then
    staged=""
  fi
  if [[ ${#staged} -gt 15000 ]]; then
    staged="${staged:0:15000}"$'\n'"[... truncated, ${#staged} bytes total ...]"
  fi

  if [[ -z "$commits" && -z "$diff" && -z "$staged" ]]; then
    return 1
  fi

  printf '### %s\n\n' "$repo"
  [[ -n "$commits" ]] && printf $'**Commits:**\n```\n%s\n```\n\n' "$commits"
  [[ -n "$diff" ]] && printf $'**Uncommitted changes:**\n```diff\n%s\n```\n\n' "$diff"
  [[ -n "$staged" ]] && printf $'**Staged changes:**\n```diff\n%s\n```\n\n' "$staged"
  return 0
}

# Lists files under the watch dirs modified since midnight, by mtime. Names
# only: the file-activity session opens whatever it needs to judge them.
find_touched_files() {
  local dir midnight
  midnight="$(date -d "today 00:00" +%s)"
  for dir in "${watch_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    find "$dir" -maxdepth 8 \
      -type d \( -name .git -o -name node_modules -o -name .venv -o -name venv \
        -o -name .cache -o -name __pycache__ -o -name .direnv \
        -o -name .tox -o -name .mypy_cache -o -name target \
        -o -name .pytest_cache -o -name .ruff_cache -o -name .ipynb_checkpoints \) -prune \
      -o -type f -newermt "@$midnight" -print 2>/dev/null
  done | sort
}

build_file_activity_report() {
  local files count
  files="$(find_touched_files)"
  [[ -n "$files" ]] || return 0
  count="$(printf '%s\n' "$files" | wc -l)"
  printf '%s\n' "$files" | head -n "$max_touched_files"
  if (( count > max_touched_files )); then
    printf '[... %d more files not listed ...]\n' "$(( count - max_touched_files ))"
  fi
}

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

build_file_prompt() {
  local files="$1" git_summary="$2"
  cat <<EOF
You are adding to a personal engineering work log. Below are the files under
the user's project directories that were modified today, by file mtime. A
long list is cut short, with a note saying how many files were left out. Many
of them will not be work: caches, logs, build output, lockfiles, checkpoints,
editor swap files, generated data. Keep only work-shaped items: things a
person did on purpose, like writing code, notes, docs, configs, experiments
or analyses. Use the Read, Glob and Grep tools to open a file when its name
alone doesn't tell you what the work was. Don't open every file.

The git-based entry for today follows the file list. Don't repeat work it
already covers. Only add what it misses: uncommitted work, files outside git
repos, notes, scratch experiments.

Output one "- " bullet per work item, one line each, in plain language,
starting with the project name in bold, like "- **project**: what was done".
Reply with the bullets only: no headings, no preamble, no explanation of what
you filtered out. If nothing is left after filtering, output exactly NONE.

Files modified today:
$files

Git-based entry for today:
${git_summary:-(none, no git activity today)}
EOF
}

call_file_summarizer() {
  local prompt="$1" dir
  local add_dirs=()
  for dir in "${watch_dirs[@]}"; do
    [[ -d "$dir" ]] && add_dirs+=("$dir")
  done
  printf '%s' "$prompt" | claude -p --model haiku --safe-mode \
    --tools "Read,Glob,Grep" --allowedTools "Read,Glob,Grep" \
    --permission-mode dontAsk --add-dir "${add_dirs[@]}" \
    --no-session-persistence
}

call_summarizer() {
  local prompt="$1"
  printf '%s' "$prompt" | claude -p --model haiku --safe-mode --tools "" --no-session-persistence
}

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

# Adds a section to the entry write_output just started, without a new
# date heading.
append_section() {
  local section="$1" dry_run="$2"
  if [[ "$dry_run" == "1" ]]; then
    printf '\n%s\n' "$section"
  else
    printf '\n%s\n' "$section" >> "$log_file"
  fi
}

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

  local activity files
  activity="$(build_activity_report)"
  files="$(build_file_activity_report)"

  if [[ -z "$activity" && -z "$files" ]]; then
    return 0
  fi

  local summary=""
  if [[ -n "$activity" ]]; then
    if ! summary="$(call_summarizer "$(build_prompt "$activity")")" || [[ -z "$summary" ]]; then
      echo "worklog-report: claude summarization failed" >&2
      return 1
    fi
    # Written before the file session runs, so a slow file session that hits
    # the unit's TimeoutStartSec can't take the git entry down with it.
    write_output "$summary" "$dry_run"
  fi

  [[ -n "$files" ]] || return 0

  # Best-effort: a failed file session only loses the "Other work" section.
  local file_summary=""
  if ! file_summary="$(call_file_summarizer "$(build_file_prompt "$files" "$summary")")"; then
    echo "worklog-report: file activity summarization failed" >&2
    return 0
  fi
  # Only bullet lines are kept: Haiku sometimes explains its filtering or
  # writes "NONE." instead of NONE, and neither belongs in the log.
  file_summary="$(printf '%s\n' "$file_summary" | grep -E '^[[:space:]]*[-*] ' || true)"
  [[ -n "$file_summary" ]] || return 0

  file_summary="## Other work"$'\n\n'"$file_summary"
  if [[ -n "$summary" ]]; then
    append_section "$file_summary" "$dry_run"
  else
    write_output "$file_summary" "$dry_run"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
