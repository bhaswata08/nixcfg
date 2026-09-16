#!/usr/bin/env bash
# Claude Code statusLine command — mirrors Starship prompt style (catppuccin mocha)
# Reads JSON from stdin

input=$(cat)

# --- Extract fields ---
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# --- Directory: truncate to 3 levels, replace HOME with ~ ---
if [ -n "$cwd" ]; then
  cwd_display="${cwd/#$HOME/\~}"
  # Count path segments
  depth=$(echo "$cwd_display" | tr -cd '/' | wc -c)
  if [ "$depth" -gt 3 ]; then
    cwd_display="_/$(echo "$cwd_display" | rev | cut -d'/' -f1-3 | rev)"
  fi
else
  cwd_display="?"
fi

# --- Git branch & status (skip optional locks) ---
git_branch=""
git_status_str=""
if git -C "${cwd:-$(pwd)}" rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git -C "${cwd:-$(pwd)}" symbolic-ref --short HEAD 2>/dev/null \
    || git -C "${cwd:-$(pwd)}" rev-parse --short HEAD 2>/dev/null)

  # Count modified, staged, untracked
  git_porcelain=$(git -C "${cwd:-$(pwd)}" status --porcelain 2>/dev/null)
  modified=$(echo "$git_porcelain" | grep -c '^.M' 2>/dev/null || echo 0)
  staged=$(echo "$git_porcelain"   | grep -c '^[MADRC]' 2>/dev/null || echo 0)
  untracked=$(echo "$git_porcelain" | grep -c '^??' 2>/dev/null || echo 0)

  parts=""
  [ "$staged" -gt 0 ]    && parts="${parts}+${staged}"
  [ "$modified" -gt 0 ]  && parts="${parts} ~${modified}"
  [ "$untracked" -gt 0 ] && parts="${parts} ?${untracked}"
  [ -z "$parts" ]        && parts="✓"
  git_status_str="$parts"
fi

# --- ANSI colors (catppuccin mocha-ish, dimmed-friendly) ---
RESET="\033[0m"
BLUE="\033[38;2;137;180;250m"       # blue #89b4fa
PURPLE="\033[38;2;203;166;247m"     # mauve #cba6f7
PEACH="\033[38;2;250;179;135m"      # peach #fab387
GREEN="\033[38;2;166;227;161m"      # green #a6e3a1
RED="\033[38;2;243;139;168m"        # red #f38ba8
SUBTEXT="\033[38;2;166;173;200m"    # subtext0 #a6adc8

# --- Context bar ---
ctx_part=""
if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  if [ "$used_int" -ge 80 ]; then
    ctx_color="$RED"
  elif [ "$used_int" -ge 50 ]; then
    ctx_color="$PEACH"
  else
    ctx_color="$GREEN"
  fi
  ctx_part="${ctx_color}ctx:${used_int}%${RESET}"
fi

# --- Assemble output ---
# Line 1: dir  branch  git_status  |  model  ctx
line=""

# directory
printf "${BLUE}%s${RESET}" "$cwd_display"

# git
if [ -n "$git_branch" ]; then
  printf "  ${PURPLE} %s${RESET}" "$git_branch"
  printf "  ${SUBTEXT}%s${RESET}" "$git_status_str"
fi

# separator
printf "  ${SUBTEXT}|${RESET}"

# model
if [ -n "$model" ]; then
  printf "  ${PEACH}%s${RESET}" "$model"
fi

# context
if [ -n "$ctx_part" ]; then
  printf "  %b" "$ctx_part"
fi

printf "\n"
