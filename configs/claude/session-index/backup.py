"""Backup, snapshots, integrity checks, restore, export, and import."""

from __future__ import annotations

import datetime
import gzip
import json
import os
import shutil
import sqlite3
import sys
import time

from db import (
    clear_reconcile_pending,
    connect,
    get_meta,
    init_db,
    iso_now,
    refresh_session,
    set_meta,
)
from extract import parse_ts_epoch, sha256_bytes
from paths import snapshots_dir_for


def run_integrity_checks(con: sqlite3.Connection) -> tuple[bool, list[str]]:
    """Run the 4 standard integrity checks.

    1. PRAGMA quick_check
    2. PRAGMA foreign_key_check
    3. messages_fts integrity-check
    4. messages_tri integrity-check
    """
    errors: list[str] = []
    try:
        rows = con.execute("PRAGMA quick_check").fetchall()
        for r in rows:
            if r[0] != "ok":
                errors.append(f"quick_check error: {r[0]}")
    except Exception as e:
        errors.append(f"quick_check failed: {e}")

    try:
        fk_rows = con.execute("PRAGMA foreign_key_check").fetchall()
        if fk_rows:
            errors.append(f"foreign_key_check reported {len(fk_rows)} violation(s)")
    except Exception as e:
        errors.append(f"foreign_key_check failed: {e}")

    for target in ("messages_fts", "messages_tri"):
        try:
            con.execute(f"INSERT INTO {target}({target}) VALUES('integrity-check')")
        except Exception as e:
            errors.append(f"{target} integrity-check failed: {e}")

    return (len(errors) == 0, errors)


def check_and_run_daily_integrity(con: sqlite3.Connection, db_path: str, log=None) -> bool:
    """Run daily integrity check if meta.last_integrity_check is >24h old.

    On failure, moves DB aside and restores from snapshot.
    """
    if log is None:
        log = lambda msg: None

    last_check = get_meta(con, "last_integrity_check")
    now_epoch = time.time()
    needs_check = False
    if last_check is None:
        needs_check = True
    else:
        dt = parse_ts_epoch(last_check)
        if dt is None or (now_epoch - dt > 86400.0):
            needs_check = True

    if not needs_check:
        return True

    log("running periodic (24h) database integrity checks...")
    ok, errors = run_integrity_checks(con)
    if ok:
        set_meta(con, "last_integrity_check", iso_now())
        log("periodic integrity checks passed")
        return True

    log(f"PERIODIC INTEGRITY CHECK FAILED: {errors}")
    recover_corrupt_db(db_path, log=log)
    return False


def recover_corrupt_db(db_path: str, log=None) -> None:
    """Move aside corrupt DB and restore newest verified snapshot."""
    if log is None:
        log = lambda msg: None

    corrupt_name = f"{db_path}.corrupt-{iso_now().replace(':', '-')}"
    log(f"moving corrupt database to {corrupt_name}")
    try:
        if os.path.exists(db_path):
            os.rename(db_path, corrupt_name)
        for ext in ("-wal", "-shm"):
            if os.path.exists(db_path + ext):
                os.rename(db_path + ext, corrupt_name + ext)
    except OSError as e:
        log(f"error moving corrupt files aside: {e}")

    log("restoring newest verified snapshot...")
    success = restore_from_snapshot(db_path, log=log)
    if not success:
        log("snapshot restore failed; database left unpopulated. Run index --full or restore --rebuild-from-scratch.")


def prune_snapshot_retention(snap_dir: str, log=None) -> None:
    """Keep 7 most recent daily + 4 weekly (Sunday's), prune oldest first."""
    if log is None:
        log = lambda msg: None
    if not os.path.isdir(snap_dir):
        return

    files = [
        f for f in os.listdir(snap_dir)
        if f.startswith("snapshot-") and f.endswith(".db.gz")
    ]
    files.sort(reverse=True)

    kept: set[str] = set()
    daily_dates: set[str] = set()
    weekly_sundays: set[str] = set()

    for fn in files:
        # Expected pattern: snapshot-YYYYMMDD-HHMMSS.db.gz
        parts = fn[len("snapshot-") : -len(".db.gz")].split("-")
        if len(parts) >= 2 and len(parts[0]) == 8:
            date_str = parts[0]
            try:
                dt = datetime.datetime.strptime(date_str, "%Y%m%d")
            except ValueError:
                continue
            if len(daily_dates) < 7 and date_str not in daily_dates:
                daily_dates.add(date_str)
                kept.add(fn)
            # Check Sunday (weekday() == 6)
            if dt.weekday() == 6 and len(weekly_sundays) < 4 and date_str not in weekly_sundays:
                weekly_sundays.add(date_str)
                kept.add(fn)

    for fn in files:
        if fn not in kept:
            try:
                os.remove(os.path.join(snap_dir, fn))
                log(f"pruned expired snapshot: {fn}")
            except OSError:
                pass


def cleanup_stale_tmps(snap_dir: str) -> None:
    if not os.path.isdir(snap_dir):
        return
    now = time.time()
    for fn in os.listdir(snap_dir):
        if fn.endswith(".tmp") or ".tmp." in fn:
            p = os.path.join(snap_dir, fn)
            try:
                if now - os.path.getmtime(p) > 86400:
                    os.remove(p)
            except OSError:
                pass


def attempt_snapshot(
    con: sqlite3.Connection,
    db_path: str,
    rows_ingested_this_pass: int = 0,
    force: bool = False,
    log=None,
) -> bool:
    """Create a snapshot if conditions or force are met."""
    if log is None:
        log = lambda msg: None

    snap_dir = snapshots_dir_for(db_path)
    os.makedirs(snap_dir, exist_ok=True)
    cleanup_stale_tmps(snap_dir)

    now_epoch = time.time()
    last_snap_at = get_meta(con, "last_snapshot_at")
    last_snap_epoch = parse_ts_epoch(last_snap_at) if last_snap_at else None

    cond_daily = (
        rows_ingested_this_pass > 0
        and (last_snap_epoch is None or (now_epoch - last_snap_epoch > 86400.0))
    )
    msg_count = con.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
    cond_weekly = (
        (last_snap_epoch is None or (now_epoch - last_snap_epoch > 7 * 86400.0))
        and msg_count > 0
    )

    if not (force or cond_daily or cond_weekly):
        return False

    set_meta(con, "last_snapshot_attempt_at", iso_now())

    # Pre-flight free-space check via os.statvfs
    try:
        st_vfs = os.statvfs(snap_dir)
        free_bytes = st_vfs.f_bavail * st_vfs.f_frsize
        db_size = os.path.getsize(db_path)
        wal_path = db_path + "-wal"
        if os.path.exists(wal_path):
            db_size += os.path.getsize(wal_path)
        required_bytes = int(1.5 * db_size)
        if free_bytes < required_bytes:
            log(
                f"snapshot skipped: insufficient free space in {snap_dir} "
                f"({free_bytes // 1024 // 1024}MB free < {required_bytes // 1024 // 1024}MB required)"
            )
            return False
    except OSError as e:
        log(f"statvfs pre-flight check failed: {e}")

    timestamp_str = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    temp_vac = os.path.join(snap_dir, f"vac-{timestamp_str}-{os.getpid()}.tmp")
    final_snap = os.path.join(snap_dir, f"snapshot-{timestamp_str}.db.gz")

    try:
        log(f"capturing snapshot via VACUUM INTO {temp_vac}...")
        con.execute(f"VACUUM INTO '{temp_vac}'")

        # Verify temp file opened read-write
        vac_con = sqlite3.connect(temp_vac)
        try:
            ok, errors = run_integrity_checks(vac_con)
        finally:
            vac_con.close()

        if not ok:
            log(f"SNAPSHOT VERIFICATION FAILED: {errors}")
            set_meta(con, "last_snapshot_verify_failed_at", iso_now())
            try:
                os.remove(temp_vac)
            except OSError:
                pass
            return False

        # Gzip to final snapshot
        temp_gz = temp_vac + ".gz"
        with open(temp_vac, "rb") as f_in:
            with gzip.open(temp_gz, "wb") as f_out:
                shutil.copyfileobj(f_in, f_out)

        os.replace(temp_gz, final_snap)
        set_meta(con, "last_snapshot_at", iso_now())
        log(f"snapshot created successfully: {final_snap}")
        prune_snapshot_retention(snap_dir, log=log)
        return True
    except Exception as e:
        log(f"snapshot capture failed: {e}")
        return False
    finally:
        if os.path.exists(temp_vac):
            try:
                os.remove(temp_vac)
            except OSError:
                pass
        temp_gz = temp_vac + ".gz"
        if os.path.exists(temp_gz):
            try:
                os.remove(temp_gz)
            except OSError:
                pass


def restore_from_snapshot(
    db_path: str, candidate_path: str | None = None, rebuild_from_scratch: bool = False, log=None
) -> bool:
    """Restore the database from a snapshot candidate."""
    if log is None:
        log = lambda msg: None

    if rebuild_from_scratch:
        log("rebuilding empty database from scratch...")
        for ext in ("", "-wal", "-shm"):
            p = db_path + ext
            if os.path.exists(p):
                os.remove(p)
        con = connect(db_path)
        init_db(con)
        con.close()
        return True

    snap_dir = snapshots_dir_for(db_path)
    candidates: list[str] = []
    if candidate_path:
        candidates = [candidate_path]
    elif os.path.isdir(snap_dir):
        for f in os.listdir(snap_dir):
            if f.startswith("snapshot-") and f.endswith(".db.gz"):
                candidates.append(os.path.join(snap_dir, f))
        candidates.sort(reverse=True)

    for cand in candidates:
        log(f"testing snapshot candidate: {cand}...")
        tmp_unpacked = os.path.join(snap_dir, f"restore-test-{os.getpid()}.tmp")
        try:
            with gzip.open(cand, "rb") as f_in:
                with open(tmp_unpacked, "wb") as f_out:
                    shutil.copyfileobj(f_in, f_out)

            test_con = sqlite3.connect(tmp_unpacked)
            try:
                ok, errors = run_integrity_checks(test_con)
                msg_cnt = test_con.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
            finally:
                test_con.close()

            if ok and msg_cnt > 0:
                log(f"snapshot candidate {cand} verified ({msg_cnt} msgs); restoring to {db_path}...")
                for ext in ("-wal", "-shm"):
                    p = db_path + ext
                    if os.path.exists(p):
                        try:
                            os.remove(p)
                        except OSError:
                            pass
                os.replace(tmp_unpacked, db_path)
                return True
            else:
                log(f"candidate {cand} rejected: ok={ok}, msgs={msg_cnt}, errors={errors}")
        except Exception as e:
            log(f"candidate {cand} failed unpack/test: {e}")
        finally:
            if os.path.exists(tmp_unpacked):
                try:
                    os.remove(tmp_unpacked)
                except OSError:
                    pass

    return False


def export_data(con: sqlite3.Connection, out_path: str, log=None) -> None:
    """Export all messages and session_titles rows with _file provenance."""
    if log is None:
        log = lambda msg: None

    log(f"exporting data to {out_path}...")
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)

    # Export messages joined with session_files
    msg_cur = con.execute("""
        SELECT m.uuid, m.parent_uuid, m.agent_id, m.line_no, m.byte_off,
               m.ts, m.ts_epoch, m.kind, m.tool_name, m.is_sidechain,
               m.is_meta, m.truncated, m.cwd, m.git_branch, m.text,
               sf.path, sf.head_hash, sf.kind as sf_kind, sf.agent_id as sf_agent_id,
               sf.session_id as sf_session_id, sf.path_session_id, sf.project_slug
          FROM messages m JOIN session_files sf USING(file_id)
         ORDER BY m.file_id, m.line_no
    """)

    title_cur = con.execute("""
        SELECT st.line_no, st.session_id, st.title, st.ts_epoch,
               sf.path, sf.head_hash, sf.kind as sf_kind, sf.agent_id as sf_agent_id,
               sf.session_id as sf_session_id, sf.path_session_id, sf.project_slug
          FROM session_titles st JOIN session_files sf USING(file_id)
         ORDER BY st.file_id, st.line_no
    """)

    count = 0
    with gzip.open(out_path, "wt", encoding="utf-8") as f:
        for row in msg_cur:
            rec = {
                "type": "message",
                "uuid": row[0],
                "parent_uuid": row[1],
                "agent_id": row[2],
                "line_no": row[3],
                "byte_off": row[4],
                "ts": row[5],
                "ts_epoch": row[6],
                "kind": row[7],
                "tool_name": row[8],
                "is_sidechain": row[9],
                "is_meta": row[10],
                "truncated": row[11],
                "cwd": row[12],
                "git_branch": row[13],
                "text": row[14],
                "_file": {
                    "path": row[15],
                    "head_hash": row[16],
                    "kind": row[17],
                    "agent_id": row[18],
                    "session_id": row[19],
                    "path_session_id": row[20],
                    "project_slug": row[21],
                },
            }
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            count += 1

        for row in title_cur:
            rec = {
                "type": "title",
                "line_no": row[0],
                "session_id": row[1],
                "title": row[2],
                "ts_epoch": row[3],
                "_file": {
                    "path": row[4],
                    "head_hash": row[5],
                    "kind": row[6],
                    "agent_id": row[7],
                    "session_id": row[8],
                    "path_session_id": row[9],
                    "project_slug": row[10],
                },
            }
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            count += 1

    log(f"exported {count} records to {out_path}")


def import_data(con: sqlite3.Connection, in_path: str, log=None) -> None:
    """Import messages and titles from export file with file_id resolution."""
    if log is None:
        log = lambda msg: None

    log(f"importing data from {in_path}...")
    file_id_cache: dict[tuple[str, str], int] = {}
    touched_sessions: set[str] = set()

    def resolve_file_id(prov: dict) -> int:
        p = prov["path"]
        h = prov["head_hash"] or ""
        key = (p, h)
        if key in file_id_cache:
            return file_id_cache[key]

        # 1. Exact match on path AND head_hash
        r = con.execute(
            "SELECT file_id FROM session_files WHERE path=? AND head_hash=?",
            (p, h),
        ).fetchone()
        if r:
            file_id_cache[key] = r[0]
            return r[0]

        # 2. Match on head_hash alone if unique across session_files
        matches = con.execute(
            "SELECT file_id FROM session_files WHERE head_hash=?", (h,)
        ).fetchall()
        if len(matches) == 1:
            file_id_cache[key] = matches[0][0]
            return matches[0][0]

        # 3. Create new session_files row from _file
        # Check path collision with different head_hash
        target_path = p
        coll = con.execute("SELECT file_id FROM session_files WHERE path=?", (p,)).fetchone()
        if coll:
            target_path = p + "\x00import:" + h[:12]

        now = iso_now()
        cur = con.execute("""
            INSERT INTO session_files(path, session_id, path_session_id, kind,
                   agent_id, project_slug, head_hash, bytes_indexed, present,
                   gone_at, origin, first_indexed_at, last_indexed_at)
            VALUES (?,?,?,?,?,?,?,0,0,?,?,?,?)
        """, (
            target_path, prov["session_id"], prov.get("path_session_id"),
            prov["kind"], prov.get("agent_id"), prov.get("project_slug"),
            h, now, "import", now, now
        ))
        fid = cur.lastrowid
        file_id_cache[key] = fid
        return fid

    msg_count = 0
    title_count = 0
    con.execute("BEGIN IMMEDIATE")
    try:
        with gzip.open(in_path, "rt", encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                rec = json.loads(line)
                rtype = rec.get("type")
                prov = rec.get("_file", {})
                file_id = resolve_file_id(prov)
                sess = rec.get("session_id") or prov.get("session_id")
                if sess:
                    touched_sessions.add(sess)

                if rtype == "message":
                    con.execute("""
                        INSERT OR IGNORE INTO messages(
                            file_id, session_id, uuid, parent_uuid, agent_id,
                            line_no, byte_off, ts, ts_epoch, kind, tool_name,
                            is_sidechain, is_meta, truncated, cwd, git_branch, text
                        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    """, (
                        file_id, sess, rec.get("uuid"), rec.get("parent_uuid"),
                        rec.get("agent_id"), rec.get("line_no"), rec.get("byte_off"),
                        rec.get("ts"), rec.get("ts_epoch"), rec.get("kind"),
                        rec.get("tool_name"), rec.get("is_sidechain", 0),
                        rec.get("is_meta", 0), rec.get("truncated", 0),
                        rec.get("cwd"), rec.get("git_branch"), rec.get("text", "")
                    ))
                    msg_count += 1
                elif rtype == "title":
                    con.execute("""
                        INSERT OR IGNORE INTO session_titles(
                            file_id, line_no, session_id, title, ts_epoch
                        ) VALUES (?,?,?,?,?)
                    """, (
                        file_id, rec.get("line_no"), sess,
                        rec.get("title"), rec.get("ts_epoch")
                    ))
                    title_count += 1
        con.execute("COMMIT")
    except Exception:
        con.execute("ROLLBACK")
        raise

    log(f"imported {msg_count} messages and {title_count} titles; refreshing {len(touched_sessions)} sessions...")
    for sess in touched_sessions:
        try:
            refresh_session(con, sess)
        except Exception as e:
            log(f"refresh_session({sess}) failed: {e}")
