"""Doctor health check for claude-session-index."""

from __future__ import annotations

import os
import sqlite3
import time
from backup import recover_corrupt_db, run_integrity_checks
from db import get_meta
from extract import parse_ts_epoch
from locking import inspect_lock
from paths import lock_path_for


def run_doctor(con: sqlite3.Connection, db_path: str, repair: bool = False) -> bool:
    """Run system health checks and report diagnostics."""
    print("claude-session-index doctor")
    print("=" * 60)

    # 1. Database size and basic counts
    db_size = os.path.getsize(db_path) if os.path.exists(db_path) else 0
    wal_path = db_path + "-wal"
    wal_size = os.path.getsize(wal_path) if os.path.exists(wal_path) else 0
    print(f"Database Path: {db_path}")
    print(f"DB File Size:  {db_size / 1024 / 1024:.2f} MB (WAL: {wal_size / 1024 / 1024:.2f} MB)")

    sess_count = con.execute("SELECT COUNT(*) FROM sessions").fetchone()[0]
    archived_sess = con.execute("SELECT COUNT(*) FROM sessions WHERE main_files_present=0").fetchone()[0]
    msg_count = con.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
    file_count = con.execute("SELECT COUNT(*) FROM session_files").fetchone()[0]
    present_files = con.execute("SELECT COUNT(*) FROM session_files WHERE present=1").fetchone()[0]

    print(f"Sessions:      {sess_count} total ({archived_sess} archived / source files gone)")
    print(f"Files Tracked: {file_count} total ({present_files} currently present on disk)")
    print(f"Messages:      {msg_count} total")

    # Messages by kind
    cur = con.execute("SELECT kind, COUNT(*) FROM messages GROUP BY kind")
    kinds = dict(cur.fetchall())
    print(f"  User:        {kinds.get('user', 0)}")
    print(f"  Assistant:   {kinds.get('assistant', 0)}")
    print(f"  Tool Use:    {kinds.get('tool_use', 0)}")
    print(f"  Thinking:    {kinds.get('thinking', 0)}")

    # 2. Timestamps and staleness checks
    now_epoch = time.time()
    last_pass = get_meta(con, "last_pass_at")
    last_snap = get_meta(con, "last_snapshot_at")
    last_snap_attempt = get_meta(con, "last_snapshot_attempt_at")
    last_snap_verify_fail = get_meta(con, "last_snapshot_verify_failed_at")

    print("\nActivity & Snapshots:")
    print(f"  Last Pass:             {last_pass or 'never'}")
    print(f"  Last Snapshot:         {last_snap or 'never'}")
    if last_snap_attempt:
        print(f"  Last Snapshot Attempt: {last_snap_attempt}")
    if last_snap_verify_fail:
        print(f"  Last Verify Failure:   {last_snap_verify_fail}")

    # Check for stale passes vs snapshots
    if last_pass:
        pass_epoch = parse_ts_epoch(last_pass) or 0
        if now_epoch - pass_epoch > 7 * 86400:
            print("  [WARN] No indexing pass has completed in over 7 days.")
        if last_snap:
            snap_epoch = parse_ts_epoch(last_snap) or 0
            if (pass_epoch - snap_epoch > 3 * 86400) and msg_count > 0:
                print("  [WARN] Indexing passes are running but snapshots aren't advancing!")
        elif msg_count > 0:
            print("  [WARN] Database has indexed messages but no snapshots have succeeded.")

    # 3. Lock status
    lpath = lock_path_for(db_path)
    lock_info = inspect_lock(lpath)
    if lock_info and lock_info.get("held"):
        pid = lock_info.get("pid")
        dur = lock_info.get("duration") or 0.0
        print(f"\nLock Status: HELD by PID {pid} for {dur:.1f}s")
        if dur > 600:
            print("  [WARN] Lock held for > 10 minutes — holder may be hung or dead.")
    else:
        print("\nLock Status: Unlocked (idle)")

    # 4. Pending reconciliation
    pending_digest = get_meta(con, "reconcile_pending_digest")
    if pending_digest:
        p_cnt = get_meta(con, "reconcile_pending_count")
        p_att = get_meta(con, "reconcile_pending_attempts")
        p_first = get_meta(con, "reconcile_pending_first_seen_at")
        print("\nReconciliation Pending:")
        print(f"  Count: {p_cnt} files, Attempts: {p_att}, First seen: {p_first}")

    # 5. Integrity checks
    print("\nRunning integrity checks...")
    ok, errors = run_integrity_checks(con)
    if ok:
        print("  [PASS] All integrity checks passed (quick_check, FK check, FTS5 unicode61, FTS5 trigram).")
        return True
    else:
        print("  [FAIL] Integrity check failures:")
        for err in errors:
            print(f"    - {err}")
        if repair:
            print("\n--repair requested: initiating recovery from snapshot...")
            con.close()
            recover_corrupt_db(db_path, log=print)
        else:
            print("\nRun with --repair to attempt automatic recovery from the latest snapshot.")
        return False
