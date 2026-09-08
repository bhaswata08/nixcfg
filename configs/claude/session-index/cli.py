"""CLI entry point for claude-session-index."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time

from backup import (
    attempt_snapshot,
    check_and_run_daily_integrity,
    export_data,
    import_data,
    restore_from_snapshot,
)
from db import connect, get_meta, init_db, iso_now
from doctor import run_doctor
from locking import IndexLock, inspect_lock
from paths import (
    lock_path_for,
    log_path_for,
    resolve_db_path,
)
from search import execute_search, format_search_hit, search_titles
from show import run_show
from walk import run_index_pass


def cmd_hook(db_path: str) -> None:
    """Detached double-fork hook execution for SessionStart."""
    # First fork: parent exits immediately (< 50ms)
    try:
        pid = os.fork()
        if pid > 0:
            sys.exit(0)
    except OSError as e:
        sys.exit(0)

    # Decouple from parent environment
    os.setsid()

    # Second fork: prevent zombie processes
    try:
        pid = os.fork()
        if pid > 0:
            sys.exit(0)
    except OSError:
        sys.exit(0)

    # Detached child: redirect output to log file with simple rotation
    log_path = log_path_for(db_path)
    os.makedirs(os.path.dirname(os.path.abspath(log_path)), exist_ok=True)
    try:
        if os.path.exists(log_path) and os.path.getsize(log_path) > 5 * 1024 * 1024:
            rot_path = log_path + ".1"
            if os.path.exists(rot_path):
                os.remove(rot_path)
            os.rename(log_path, rot_path)
    except OSError:
        pass

    try:
        log_fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
        os.dup2(log_fd, sys.stdout.fileno())
        os.dup2(log_fd, sys.stderr.fileno())
        devnull = os.open(os.devnull, os.O_RDONLY)
        os.dup2(devnull, sys.stdin.fileno())
    except OSError:
        pass

    # Acquire lock non-blocking; exit silently if another pass is running
    lock = IndexLock(lock_path_for(db_path))
    if not lock.acquire(mode="hook"):
        sys.exit(0)

    try:
        con = connect(db_path)
        init_db(con)
        run_index_pass(con, db_path, quiet=True)
        con.close()
    except Exception as e:
        print(f"[{iso_now()}] Hook error: {e}", file=sys.stderr)
    finally:
        lock.release()
    sys.exit(0)


def cmd_index(con, db_path: str, args) -> None:
    lock = IndexLock(lock_path_for(db_path))
    mode = "wait" if getattr(args, "wait", False) else "nowait"
    if not lock.acquire(mode=mode):
        sys.stderr.write("Another indexing pass is currently running. Use --wait to block.\n")
        sys.exit(1)

    try:
        t0 = time.time()
        res = run_index_pass(
            con, db_path,
            force_full=getattr(args, "full", False),
            force_reconcile=getattr(args, "force_reconcile", False),
            quiet=getattr(args, "quiet", False),
        )
        elapsed = time.time() - t0
        if not getattr(args, "quiet", False):
            print(
                f"Indexing complete in {elapsed:.2f}s: "
                f"{res['files_found']} files found, {res['files_indexed']} files updated, "
                f"{res['messages_added']} messages added ({res['touched_sessions']} sessions touched)."
            )
    finally:
        lock.release()


def cmd_search(con, db_path: str, args) -> None:
    # Pre-query indexing unless --no-index
    if not getattr(args, "no_index", False):
        lock = IndexLock(lock_path_for(db_path))
        if lock.acquire(mode="search"):
            try:
                run_index_pass(con, db_path, quiet=True)
            finally:
                lock.release()
        else:
            sys.stderr.write("Search: indexing lock timeout (3s), proceeding with existing index (results may be stale).\n")

    if getattr(args, "title", False):
        hits = search_titles(con, args.query, limit=getattr(args, "limit", 10))
        if getattr(args, "json", False):
            print(json.dumps(hits, indent=2))
        else:
            if not hits:
                print(f"No sessions matching title: {args.query}")
            for r in hits:
                print(f"- {r['session_id']}  {r['title']}  ({r.get('project_slug') or 'no-project'})")
        return

    hits = execute_search(con, args.query, args)
    if getattr(args, "json", False):
        print(json.dumps(hits, indent=2))
    else:
        if not hits:
            print(f"No results found for query: {args.query}")
            return
        for i, hit in enumerate(hits, 1):
            print(format_search_hit(i, hit))
            print()


def cmd_stats(con, db_path: str) -> None:
    db_size = os.path.getsize(db_path) if os.path.exists(db_path) else 0
    wal_path = db_path + "-wal"
    wal_size = os.path.getsize(wal_path) if os.path.exists(wal_path) else 0

    sess_count = con.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
    archived_sess = con.execute("SELECT COUNT(*) FROM sessions WHERE main_files_present=0").fetchone()[0]
    msg_count = con.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
    file_count = con.execute("SELECT COUNT(*) FROM session_files").fetchone()[0]
    present_files = con.execute("SELECT COUNT(*) FROM session_files WHERE present=1").fetchone()[0]

    cur = con.execute("SELECT kind, COUNT(*) FROM messages GROUP BY kind")
    kinds = dict(cur.fetchall())
    subagent_msgs = con.execute("SELECT COUNT(*) FROM messages WHERE is_sidechain=1").fetchone()[0]

    date_row = con.execute("SELECT MIN(first_ts), MAX(last_ts) FROM sessions").fetchone()
    first_date = date_row[0][:10] if date_row and date_row[0] else "none"
    last_date = date_row[1][:10] if date_row and date_row[1] else "none"

    last_pass = get_meta(con, "last_pass_at") or "never"
    last_snap = get_meta(con, "last_snapshot_at") or "never"

    print("claude-session-index statistics")
    print("=" * 60)
    print(f"Database:         {db_path}")
    print(f"Size:             {db_size / 1024 / 1024:.2f} MB (WAL: {wal_size / 1024 / 1024:.2f} MB)")
    print(f"Date Range:       {first_date} -> {last_date}")
    print(f"Sessions:         {sess_count} ({archived_sess} archived / source files gone)")
    print(f"Files Tracked:    {file_count} ({present_files} present on disk)")
    print(f"Messages:         {msg_count}")
    print(f"  User:           {kinds.get('user', 0)}")
    print(f"  Assistant:      {kinds.get('assistant', 0)}")
    print(f"  Tool Use:       {kinds.get('tool_use', 0)}")
    print(f"  Thinking:       {kinds.get('thinking', 0)}")
    print(f"  Subagent msgs:  {subagent_msgs}")
    print(f"Last Pass:        {last_pass}")
    print(f"Last Snapshot:    {last_snap}")


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="claude-session-index",
        description="Full-text search index over Claude Code session transcripts.",
    )
    parser.add_argument(
        "--db",
        dest="db_path",
        help="Path to database file (defaults to ~/.claude/session-index/index.db)",
    )

    subparsers = parser.add_subparsers(dest="subcommand")

    # index
    p_index = subparsers.add_parser("index", help="Index transcript files")
    p_index.add_argument("--full", action="store_true", help="Force full reindex of all files")
    p_index.add_argument("--wait", action="store_true", help="Wait indefinitely for lock")
    p_index.add_argument("--force-reconcile", action="store_true", help="Bypass reconciliation signals and delete absent files immediately")
    p_index.add_argument("--quiet", action="store_true", help="Suppress progress output")

    # search
    p_search = subparsers.add_parser("search", help="Search transcripts")
    p_search.add_argument("query", help="Query string")
    p_search.add_argument("--substring", "-s", action="store_true", help="Search trigram index directly")
    p_search.add_argument("--exact", action="store_true", help="FTS exact token match only (no trigram escalation)")
    p_search.add_argument("--escalate-threshold", type=int, default=3, help="Escalate to trigram if FTS hit count < threshold (default: 3)")
    p_search.add_argument("--limit", type=int, default=10, help="Max results to return (default: 10)")
    p_search.add_argument("--days", type=float, help="Only return results within last N days")
    p_search.add_argument("--since", help="ISO date lower bound")
    p_search.add_argument("--until", help="ISO date upper bound")
    p_search.add_argument("--project", help="Filter by project slug substring")
    p_search.add_argument("--cwd", help="Filter by cwd prefix")
    p_search.add_argument("--role", choices=["user", "assistant"], help="Filter by message role")
    p_search.add_argument("--tool", help="Filter by tool name")
    p_search.add_argument("--session", help="Filter by session ID prefix")
    p_search.add_argument("--include-thinking", action="store_true", help="Include thinking blocks in results")
    p_search.add_argument("--include-subagents", action="store_true", help="Include subagent transcripts in results")
    p_search.add_argument("--include-meta", action="store_true", help="Include meta messages in results")
    p_search.add_argument("--no-index", action="store_true", help="Skip pre-query indexing pass")
    p_search.add_argument("--json", action="store_true", help="Output results as JSON")
    p_search.add_argument("--title", action="store_true", help="Search session titles directly via LIKE")

    # show
    p_show = subparsers.add_parser("show", help="Display session transcript")
    p_show.add_argument("session_id", help="Session ID or prefix")
    p_show.add_argument("--around", help="Message UUID to center display around")
    p_show.add_argument("--line", type=int, help="Line number to center display around")
    p_show.add_argument("--context", type=int, default=5, help="Number of context messages around target (default: 5)")
    p_show.add_argument("--agent", help="Filter by subagent ID")
    p_show.add_argument("--include-subagents", action="store_true", help="Interleave subagent messages chronologically")
    p_show.add_argument("--max-chars", type=int, default=8000, help="Max total characters to output (default: 8000)")

    # stats
    subparsers.add_parser("stats", help="Show index statistics")

    # doctor
    p_doc = subparsers.add_parser("doctor", help="Run diagnostic health checks")
    p_doc.add_argument("--repair", action="store_true", help="Attempt recovery from snapshot on integrity failure")

    # snapshot
    subparsers.add_parser("snapshot", help="Create a database snapshot")

    # restore
    p_rest = subparsers.add_parser("restore", help="Restore database from snapshot")
    p_rest.add_argument("--from", dest="from_snap", help="Path to snapshot candidate (.db.gz)")
    p_rest.add_argument("--rebuild-from-scratch", action="store_true", help="Initialize empty DB and reindex from disk")

    # export
    p_exp = subparsers.add_parser("export", help="Export index contents to gzipped JSONL")
    p_exp.add_argument("--out", required=True, help="Output file path (.jsonl.gz)")

    # import
    p_imp = subparsers.add_parser("import", help="Import data from gzipped JSONL")
    p_imp.add_argument("path", help="Path to input .jsonl.gz")

    # hook
    subparsers.add_parser("hook", help="SessionStart background hook entrypoint")

    args = parser.parse_args()
    if not args.subcommand:
        parser.print_help()
        sys.exit(1)

    db_path = args.db_path or resolve_db_path()

    # The hook subcommand handles its own backgrounding before DB open
    if args.subcommand == "hook":
        cmd_hook(db_path)
        return

    # Ensure parent directory exists for DB
    os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)

    if args.subcommand == "restore":
        ok = restore_from_snapshot(
            db_path, candidate_path=args.from_snap,
            rebuild_from_scratch=args.rebuild_from_scratch, log=print
        )
        if not ok:
            sys.stderr.write("Restore failed. No valid snapshots found. Consider --rebuild-from-scratch.\n")
            sys.exit(1)
        if args.rebuild_from_scratch:
            # Rebuild created an empty DB; the full walk from scratch is
            # part of the rebuild (this full reindex is NEVER automatic).
            print("Rebuilt empty DB; running full index pass from disk...")
            lock = IndexLock(lock_path_for(db_path))
            if not lock.acquire(mode="wait"):
                sys.stderr.write("Could not acquire index lock.\n")
                sys.exit(1)
            try:
                con_r = connect(db_path)
                init_db(con_r)
                try:
                    run_index_pass(con_r, db_path, force_full=True)
                finally:
                    con_r.close()
            finally:
                lock.release()
        print("Restore successful.")
        return

    con = connect(db_path)
    init_db(con)

    try:
        if args.subcommand == "index":
            cmd_index(con, db_path, args)
        elif args.subcommand == "search":
            cmd_search(con, db_path, args)
        elif args.subcommand == "show":
            run_show(con, args.session_id, args)
        elif args.subcommand == "stats":
            cmd_stats(con, db_path)
        elif args.subcommand == "doctor":
            ok = run_doctor(con, db_path, repair=args.repair)
            if not ok:
                sys.exit(1)
        elif args.subcommand == "snapshot":
            ok = attempt_snapshot(con, db_path, force=True, log=print)
            if not ok:
                sys.stderr.write("Snapshot failed.\n")
                sys.exit(1)
        elif args.subcommand == "export":
            export_data(con, args.out, log=print)
        elif args.subcommand == "import":
            import_data(con, args.path, log=print)
    finally:
        con.close()


if __name__ == "__main__":
    main()
