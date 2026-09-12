"""File discovery: walk the projects tree and classify the two known layouts.

Layouts (relative to <config>/projects/):
  <slug>/<session-id>.jsonl
      kind='main', session_id = filename stem, project_slug = slug
  <slug>/<session-id>/subagents/agent-<agent-id>.jsonl
      kind='subagent', session_id = parent directory name,
      agent_id = id from filename, project_slug = slug

Anything else is logged and skipped (not fatal). Every discovered path is
canonicalised with os.path.realpath() so that ~/.claude/projects/... and
~/.claude-personal/projects/... (a symlink to the same tree) collapse to one
session_files row instead of double-indexing.
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass


@dataclass
class DiscoveredFile:
    path: str  # realpath-canonicalised absolute path
    session_id: str  # inferred from directory layout
    path_session_id: str  # same; mismatch vs record sessionId is logged, record wins
    kind: str  # 'main' | 'subagent'
    agent_id: str | None
    project_slug: str


def classify(relpath: str) -> DiscoveredFile | None:
    """Classify a path relative to the projects root. None = unrecognized."""
    parts = relpath.split(os.sep)
    if len(parts) == 2 and parts[1].endswith(".jsonl"):
        slug, fname = parts
        stem = fname[: -len(".jsonl")]
        if not stem or not slug:
            return None
        return DiscoveredFile(
            path="",  # filled in by discover()
            session_id=stem,
            path_session_id=stem,
            kind="main",
            agent_id=None,
            project_slug=slug,
        )
    if (
        len(parts) == 4
        and parts[2] == "subagents"
        and parts[3].startswith("agent-")
        and parts[3].endswith(".jsonl")
    ):
        slug, parent, _, fname = parts
        agent_id = fname[len("agent-") : -len(".jsonl")]
        if not agent_id or not parent or not slug:
            return None
        return DiscoveredFile(
            path="",
            session_id=parent,
            path_session_id=parent,
            kind="subagent",
            agent_id=agent_id,
            project_slug=slug,
        )
    return None


def discover(projects_dir: str, log=None) -> list[DiscoveredFile]:
    """Walk the projects tree and return classified files."""
    found: list[DiscoveredFile] = []
    skipped = 0
    root = os.path.realpath(projects_dir)
    if not os.path.isdir(root):
        if log:
            log(f"projects dir missing: {projects_dir}")
        return found
    for dirpath, _dirnames, filenames in os.walk(root, followlinks=True):
        for fn in filenames:
            if not fn.endswith(".jsonl"):
                continue
            abspath = os.path.join(dirpath, fn)
            rel = os.path.relpath(abspath, root)
            info = classify(rel)
            if info is None:
                skipped += 1
                if log:
                    log(f"skip unrecognized layout: {rel}")
                continue
            info.path = os.path.realpath(abspath)
            found.append(info)
    # Deterministic order keeps passes reproducible and logs diffable.
    found.sort(key=lambda f: f.path)
    if log and skipped:
        log(f"skipped {skipped} file(s) with unrecognized layout")
    return found


def run_index_pass(
    con,
    db_path: str,
    force_full: bool = False,
    force_reconcile: bool = False,
    quiet: bool = False,
    log=None,
) -> dict:
    """Run an indexing pass across all projects files."""
    if log is None:
        log = (lambda msg: None) if quiet else (lambda msg: print(f"[{iso_now()}] {msg}", file=sys.stderr))

    from backup import attempt_snapshot, check_and_run_daily_integrity
    from db import get_meta, iso_now, set_meta
    from extract import index_file
    from paths import resolve_projects_dir
    from reconcile import reconcile_absent_files

    # 1. Daily integrity check
    check_and_run_daily_integrity(con, db_path, log=log)

    # 2. Track present count before walk
    present_before = con.execute(
        "SELECT COUNT(*) FROM session_files WHERE present=1"
    ).fetchone()[0]

    # 3. Monotonic scan counter
    scan_id = int(get_meta(con, "scan_counter") or "0") + 1
    set_meta(con, "scan_counter", str(scan_id))

    # 4. File discovery
    projects_dir = resolve_projects_dir()
    discovered = discover(projects_dir, log=log)
    files_found = len(discovered)

    # 5. Ingestion
    total_added = 0
    touched_all: set[str] = set()
    files_indexed = 0

    for info in discovered:
        try:
            added, touched = index_file(
                con, info, scan_id, force_full=force_full, log=log
            )
        except Exception as e:
            # One bad file never crashes the pass; reconcile still runs.
            log(f"index_file({info.path}) FAILED: {e}")
            continue
        total_added += added
        touched_all.update(touched)
        if added > 0:
            files_indexed += 1

    # 6. Reconciliation
    reconcile_ok = reconcile_absent_files(
        con, scan_id, present_before, files_found, force_reconcile=force_reconcile, log=log
    )

    # 7. Snapshots
    attempt_snapshot(con, db_path, rows_ingested_this_pass=total_added, force=False, log=log)

    # 8. Update pass timestamp
    set_meta(con, "last_pass_at", iso_now())

    return {
        "scan_id": scan_id,
        "files_found": files_found,
        "files_indexed": files_indexed,
        "messages_added": total_added,
        "touched_sessions": len(touched_all),
        "reconcile_ok": reconcile_ok,
    }

