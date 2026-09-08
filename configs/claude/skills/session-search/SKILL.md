---
name: session-search
user-invocable: true
description: Search and view past Claude Code session transcripts across all projects
---

# session-search

Full-text search index over past Claude Code session transcripts across all projects.

Claude Code auto-deletes transcript files older than 30 days (`cleanupPeriodDays`). `claude-session-index` provides a persistent, incremental search index over all past sessions, allowing you to recall discussions, architecture decisions, code snippets, and commands discussed across past sessions.

## When to Use This Skill

- **Use when**: The user refers to a past conversation, decision, debugging effort, or experiment not present in the current conversation context or project memory files (e.g. "What was the fix we discussed last week for the data pipeline?", "Find where we benchmarked the token generation").
- **Do NOT use when**:
  - The answer is already in the current session or available in the working tree.
  - The question can be answered by exploring current files, git log, or curated memory (`~/.claude/projects/<slug>/memory/`).

## Scope and Capabilities

- **Historical Coverage**: Preserves everything from when the index was first built forward; it does **not** recover transcripts that Claude Code already deleted before the index was created.
- **Curated Memory Policy**: Does **NOT** auto-promote findings into the curated memory system (`~/.claude/projects/<slug>/memory/`). Surfacing something into curated memory is a deliberate, separate act. If a valuable past decision is found, **offer** to save it to memory; never do so silently.

## Search-Then-Show Workflow

1. **Search across transcripts**:
   ```bash
   claude-session-index search "<query>"
   ```
   Filter options:
   - `--project <slug-substring>`: Limit search to projects matching substring.
   - `--cwd <path-prefix>`: Limit search to working directories starting with path.
   - `--days <N>`: Only search sessions within the last N days.
   - `--since <YYYY-MM-DD>` / `--until <YYYY-MM-DD>`: Date bounds.
   - `--role user|assistant`: Filter by message role.
   - `--tool <name>`: Filter by tool name (e.g. `Bash`, `Edit`).
   - `--substring` / `-s`: Query trigram index directly for substrings/symbols.
   - `--exact`: Query exact unicode61 tokens without trigram escalation.
   - `--json`: Output structured JSON results.
   - `--title`: Search session titles directly (via LIKE scan on sessions table).

2. **Inspect matching session / context**:
   Each search hit outputs an exact `claude-session-index show` command with `--around <uuid>`:
   ```bash
   claude-session-index show <session-id> --around <uuid> --context 5
   ```
   Display options:
   - `--around <uuid>`: Center transcript output around the specific message.
   - `--line <N>`: Center transcript output around line number.
   - `--context <N>`: Number of surrounding messages to show (default: 5).
   - `--include-subagents`: Interleave subagent messages chronologically.
   - `--max-chars <N>`: Cap total output size (default: 8000 characters).

3. **Resuming live sessions**:
   At the footer of `show`:
   - If the original session file is still present on disk, `claude --resume <session-id>` is shown.
   - If the file was cleaned up by Claude Code, it indicates the session is archived and only indexed content is displayed.

## System Commands Reference

- `claude-session-index index [--full] [--wait] [--force-reconcile]`: Incremental indexing pass across `~/.claude/projects/`.
- `claude-session-index stats`: Reports database size, session/message counts, and dates.
- `claude-session-index doctor [--repair]`: Reports diagnostic health, integrity checks, and lock status.
- `claude-session-index snapshot`: Forces snapshot capture and verification.
- `claude-session-index restore [--from <snapshot>] [--rebuild-from-scratch]`: Restores index from snapshot or rebuilds.
- `claude-session-index export --out <path.jsonl.gz>`: Dumps index with provenance metadata.
- `claude-session-index import <path.jsonl.gz>`: Imports previously exported index dump.

## Known Limitations

- **Content modification detection window**: Content modified strictly between byte 4096 and the tail-anchor window start (last 512 bytes), with unchanged size, mtime, and inode, is undetected by either hash. This is an accepted design tradeoff given Claude Code transcripts are append-only in practice.
- **Short queries**: Queries under 3 characters are rejected because neither FTS index (unicode61 token or trigram shingle) can serve them meaningfully.
