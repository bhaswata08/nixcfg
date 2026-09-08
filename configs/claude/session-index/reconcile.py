"""Reconciliation logic for claude-session-index.

Marks files/sessions as no-longer-present without deleting their messages.
"""

from __future__ import annotations

import hashlib
import time
from db import (
    clear_reconcile_pending,
    get_meta,
    iso_now,
    refresh_session,
    set_meta,
)
from extract import parse_ts_epoch


def sha256_text(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def reconcile_absent_files(
    con,
    scan_id: int,
    present_before: int,
    files_found_total: int,
    force_reconcile: bool = False,
    log=None,
) -> bool:
    """Run reconciliation after a full projects walk.

    Returns True if reconciliation completed (or deferred cleanly),
    False if Signal A aborted the step.
    """
    if log is None:
        log = lambda msg: None

    # Fetch newly_absent file_ids: present=1 and last_seen_scan < scan_id
    rows = con.execute(
        "SELECT file_id, session_id FROM session_files "
        "WHERE present=1 AND last_seen_scan < ?",
        (scan_id,),
    ).fetchall()
    newly_absent = [r[0] for r in rows]
    affected_sessions = {r[1] for r in rows}

    def apply_absent(fids: list[int], sessions: set[str]):
        if not fids:
            return
        now = iso_now()
        con.execute("BEGIN IMMEDIATE")
        try:
            placeholders = ",".join("?" * len(fids))
            con.execute(
                f"UPDATE session_files SET present=0, gone_at=? "
                f"WHERE file_id IN ({placeholders})",
                [now] + fids,
            )
            con.execute("COMMIT")
        except Exception:
            con.execute("ROLLBACK")
            raise

        for sess in sessions:
            try:
                refresh_session(con, sess)
            except Exception as e:
                log(f"refresh_session({sess}) during reconcile failed: {e}")

    if force_reconcile:
        log(f"--force-reconcile: marking {len(newly_absent)} file(s) as gone")
        apply_absent(newly_absent, affected_sessions)
        clear_reconcile_pending(con)
        return True

    # Signal A (hard abort, stateless, never sticky)
    if (files_found_total == 0 and present_before > 0) or (
        present_before > 0 and files_found_total < 0.20 * present_before
    ):
        log(
            f"SIGNAL A RECONCILIATION ABORT: files_found_total={files_found_total} "
            f"vs present_before={present_before}. Disk unmounted or tree empty? "
            f"Suppressing all deletions."
        )
        return False

    # Signal B (two-strike confirmation with decay)
    digest = sha256_text(",".join(str(f) for f in sorted(newly_absent)))
    count_absent = len(newly_absent)

    if count_absent <= 10 or (
        present_before > 0 and count_absent <= 0.25 * present_before
    ):
        if count_absent > 0:
            log(f"reconciliation: marking {count_absent} file(s) as gone (under threshold)")
            apply_absent(newly_absent, affected_sessions)
        clear_reconcile_pending(con)
        return True

    # Over threshold: check pending state
    pending_digest = get_meta(con, "reconcile_pending_digest")
    pending_attempts_str = get_meta(con, "reconcile_pending_attempts")
    pending_first_seen_at = get_meta(con, "reconcile_pending_first_seen_at")
    pending_first_scan_id = get_meta(con, "reconcile_pending_first_scan_id")
    pending_last_scan_id = (
        get_meta(con, "reconcile_pending_last_scan_id") or pending_first_scan_id
    )

    now_iso = iso_now()
    if pending_first_seen_at is None:
        attempts = 1
        first_seen_at = now_iso
        set_meta(con, "reconcile_pending_digest", digest)
        set_meta(con, "reconcile_pending_count", str(count_absent))
        set_meta(con, "reconcile_pending_attempts", "1")
        set_meta(con, "reconcile_pending_first_seen_at", first_seen_at)
        set_meta(con, "reconcile_pending_first_scan_id", str(scan_id))
        set_meta(con, "reconcile_pending_last_scan_id", str(scan_id))
    else:
        attempts = int(pending_attempts_str or "1") + 1
        first_seen_at = pending_first_seen_at
        set_meta(con, "reconcile_pending_digest", digest)
        set_meta(con, "reconcile_pending_count", str(count_absent))
        set_meta(con, "reconcile_pending_attempts", str(attempts))
        set_meta(con, "reconcile_pending_last_scan_id", str(scan_id))

    # Check two-strike match
    matched_pending = (
        pending_digest is not None
        and digest == pending_digest
        and pending_last_scan_id is not None
        and str(scan_id) != pending_last_scan_id
    )

    first_seen_epoch = parse_ts_epoch(first_seen_at) or time.time()
    age_days = (time.time() - first_seen_epoch) / 86400.0
    escape_hatch = (attempts >= 3) or (age_days > 7.0)

    if matched_pending or escape_hatch:
        reason = "two-strike match" if matched_pending else f"escape hatch (attempts={attempts}, age_days={age_days:.1f})"
        log(f"reconciliation: {reason} confirmed; marking {count_absent} file(s) as gone")
        apply_absent(newly_absent, affected_sessions)
        clear_reconcile_pending(con)
        return True
    else:
        log(
            f"reconciliation: over-threshold missing set deferred (count={count_absent}, "
            f"attempts={attempts}, first_seen_at={first_seen_at})"
        )
        return True
