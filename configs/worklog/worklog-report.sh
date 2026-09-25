#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${watch_dirs+x}" ]]; then
  watch_dirs=("$HOME/self_projects" "$HOME/work")
fi
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "worklog-report: not fully implemented yet" >&2
  exit 1
fi
