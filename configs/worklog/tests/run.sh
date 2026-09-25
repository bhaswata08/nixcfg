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

mkdir -p "$tmp/no-email-repo"
git init -q "$tmp/no-email-repo"
echo base > "$tmp/no-email-repo/tracked.txt"
git -c user.email=t@example.com -c user.name=t -C "$tmp/no-email-repo" add tracked.txt
git -c user.email=t@example.com -c user.name=t -C "$tmp/no-email-repo" commit -q -m "base"
echo changed >> "$tmp/no-email-repo/tracked.txt"
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
if HOME="$tmp/fake_home" collect_repo_activity "$tmp/no-email-repo" > /dev/null; then
  echo "PASS: repo with no configured user.email still reports diff activity"
else
  echo "FAIL: repo with no configured user.email still reports diff activity"
  fail=1
fi

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

exit "$fail"
