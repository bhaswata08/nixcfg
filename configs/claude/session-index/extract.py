"""Per-line extraction and per-file byte-resume indexing.

Only type == "user" / "assistant" produce messages rows; only
type == "ai-title" produces session_titles rows. Every other record type
(attachment, tool_result blocks, queue-operation, system, mode,
permission-mode, file-history-snapshot, ...) is skipped entirely.

Known accepted limitation (do NOT try to fix): content modified strictly
between byte 4096 and the tail-anchor window start, with unchanged
size/mtime/inode, is undetected by either hash. Acceptable given Claude Code
transcripts are append-only in practice.
"""

from __future__ import annotations

import datetime
import hashlib
import json
import os
import sqlite3

from db import get_meta, refresh_session, set_meta, iso_now

# json.dumps(tool_use input) is truncated to 16 KiB with truncated=1.
TOOL_INPUT_LIMIT = 16 * 1024
# Free-text blocks (user/assistant text, thinking) are truncated to 64 KiB
# with truncated=1. This keeps the DB bounded: single lines can reach ~2.2MB
# (large tool outputs inline), and FTS needs only the head to rank well.
TEXT_LIMIT = 64 * 1024

HEAD_HASH_LEN = 4096
TAIL_ANCHOR_LEN = 512

# Flush cadence: commit and advance bytes_indexed every 2000 messages OR 4MB
# of consumed bytes, so a full rebuild is many short transactions, not one
# long-held lock.
CHUNK_MESSAGES = 2000
CHUNK_BYTES = 4 * 1024 * 1024

READ_CHUNK = 1024 * 1024


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def parse_ts_epoch(ts) -> float | None:
    if not ts or not isinstance(ts, str):
        return None
    try:
        s = ts
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        return datetime.datetime.fromisoformat(s).timestamp()
    except Exception:
        return None


def _bool01(v) -> int:
    return 1 if v else 0


def _truncate(text: str, limit: int) -> tuple[str, int]:
    if len(text.encode("utf-8")) <= limit:
        return text, 0
    # Cut on a char boundary working backwards from an approximate byte cut.
    raw = text.encode("utf-8")[:limit]
    cut = raw.decode("utf-8", errors="ignore")
    return cut, 1


def record_to_messages(rec: dict, file_ctx: dict, line_no: int, byte_off: int):
    """Map one parsed JSONL record to (message_rows, title_row).

    message_rows: list of dicts ready for INSERT into messages.
    title_row: dict ready for INSERT into session_titles, or None.
    """
    rtype = rec.get("type")
    file_session = file_ctx["session_id"]
    sess = rec.get("sessionId") or rec.get("session_id") or file_session
    if rtype == "ai-title":
        title = rec.get("aiTitle") or rec.get("title")
        if not title:
            return [], None
        return [], {
            "session_id": sess,
            "line_no": line_no,
            "title": title,
            # ts_epoch stamped by the caller from carry_ts_epoch.
            "ts_epoch": None,
        }
    if rtype not in ("user", "assistant"):
        return [], None

    uuid = rec.get("uuid")
    parent_uuid = rec.get("parentUuid") or rec.get("parent_uuid")
    agent_id = (
        rec.get("agentId") or rec.get("agent_id") or file_ctx.get("agent_id")
    )
    ts = rec.get("timestamp")
    ts_epoch = parse_ts_epoch(ts)
    cwd = rec.get("cwd")
    git_branch = rec.get("gitBranch") or rec.get("git_branch")
    is_sidechain = _bool01(rec.get("isSidechain"))
    is_meta = _bool01(rec.get("isMeta"))

    msg = rec.get("message")
    if not isinstance(msg, dict):
        return [], None
    content = msg.get("content")

    blocks: list[tuple[str, str | None, str]] = []  # (kind, tool_name, text)
    if isinstance(content, str):
        blocks.append(("user", None, content))
    elif isinstance(content, list):
        for b in content:
            if not isinstance(b, dict):
                continue
            btype = b.get("type")
            if btype == "text":
                t = b.get("text")
                if isinstance(t, str):
                    blocks.append((rtype, None, t))
            elif btype == "thinking":
                t = b.get("thinking")
                if isinstance(t, str):
                    blocks.append(("thinking", None, t))
            elif btype == "tool_use":
                name = b.get("name")
                try:
                    dumped = json.dumps(b.get("input"), ensure_ascii=False)
                except Exception:
                    dumped = "{}"
                blocks.append(("tool_use", name, dumped))
            # tool_result / image blocks are skipped entirely, never indexed.
            else:
                continue
    else:
        return [], None

    rows = []
    # One row per non-skipped block. UNIQUE(file_id, uuid) would collapse
    # multi-block records (e.g. [thinking, text]) to their first block under
    # INSERT OR IGNORE, silently dropping real content — so multi-block
    # records get deterministic per-block uuid suffixes ("<uuid>#<i>").
    # Single-block records keep the raw uuid, and both sides of an
    # export/import round-trip derive identical suffixes.
    multi = len(blocks) > 1
    for i, (kind, tool_name, text) in enumerate(blocks):
        limit = TOOL_INPUT_LIMIT if kind == "tool_use" else TEXT_LIMIT
        if len(text.encode("utf-8")) > limit:
            text, trunc = _truncate(text, limit)
        else:
            trunc = 0
        row_uuid = f"{uuid}#{i}" if (multi and uuid) else uuid
        rows.append(
            {
                "session_id": sess,
                "uuid": row_uuid,
                "parent_uuid": parent_uuid,
                "agent_id": agent_id,
                "line_no": line_no,
                "byte_off": byte_off,
                "ts": ts if isinstance(ts, str) else None,
                "ts_epoch": ts_epoch,
                "kind": kind,
                "tool_name": tool_name,
                "is_sidechain": is_sidechain,
                "is_meta": is_meta,
                "truncated": trunc,
                "cwd": cwd,
                "git_branch": git_branch,
                "text": text,
            }
        )
    return rows, None


MESSAGE_COLUMNS = (
    "file_id, session_id, uuid, parent_uuid, agent_id, line_no, byte_off,"
    " ts, ts_epoch, kind, tool_name, is_sidechain, is_meta, truncated,"
    " cwd, git_branch, text"
)
MESSAGE_PLACEHOLDERS = ",".join(["?"] * 17)


def _insert_message_rows(con, file_id: int, rows: list[dict]) -> None:
    con.executemany(
        f"INSERT OR IGNORE INTO messages({MESSAGE_COLUMNS}) "
        f"VALUES ({MESSAGE_PLACEHOLDERS})",
        [
            (
                file_id, r["session_id"], r["uuid"], r["parent_uuid"],
                r["agent_id"], r["line_no"], r["byte_off"], r["ts"],
                r["ts_epoch"], r["kind"], r["tool_name"], r["is_sidechain"],
                r["is_meta"], r["truncated"], r["cwd"], r["git_branch"],
                r["text"],
            )
            for r in rows
        ],
    )


def _insert_title_row(con, file_id: int, row: dict) -> None:
    con.execute(
        "INSERT OR IGNORE INTO session_titles"
        "(file_id, line_no, session_id, title, ts_epoch) "
        "VALUES (?,?,?,?,?)",
        (
            file_id, row["line_no"], row["session_id"], row["title"],
            row["ts_epoch"],
        ),
    )


def _head_hash_of(path: str, size: int) -> str:
    n = min(HEAD_HASH_LEN, size)
    with open(path, "rb") as fh:
        return sha256_bytes(fh.read(n))


def _tail_bytes(path: str, end: int) -> bytes:
    start = max(0, end - TAIL_ANCHOR_LEN)
    with open(path, "rb") as fh:
        fh.seek(start)
        return fh.read(end - start)


def _count_newlines_before(path: str, offset: int) -> int:
    """Number of b'\\n' in bytes[0:offset] — the 1-based line number base."""
    count = 0
    with open(path, "rb") as fh:
        remaining = offset
        while remaining > 0:
            chunk = fh.read(min(READ_CHUNK, remaining))
            if not chunk:
                break
            count += chunk.count(b"\n")
            remaining -= len(chunk)
    return count


def _last_title_for_file(con, file_id: int) -> str | None:
    row = con.execute(
        "SELECT title FROM session_titles WHERE file_id=? "
        "ORDER BY line_no DESC LIMIT 1",
        (file_id,),
    ).fetchone()
    return row[0] if row else None


def _latest_msg_ts_for_file(con, file_id: int) -> float | None:
    row = con.execute(
        "SELECT ts_epoch FROM messages WHERE file_id=? AND ts_epoch IS NOT NULL "
        "ORDER BY line_no DESC LIMIT 1",
        (file_id,),
    ).fetchone()
    return row[0] if row else None


def ensure_file_row(con, info, scan_id: int, log=None):
    """Fetch or create the session_files row for a discovered file.

    Implements the scanner reclaim rule: if the realpath matches an existing
    row with origin='import', that row is renamed to its sentinel form and a
    fresh origin='scan' row is created. Imported messages stay in the DB under
    the sentinel path; search/show dedupe them at query time.
    """
    row = con.execute(
        "SELECT * FROM session_files WHERE path=?", (info.path,)
    ).fetchone()
    if row is None:
        return None
    d = dict(zip([c[0] for c in con.execute(
        "SELECT * FROM session_files LIMIT 0").description], row))
    if d.get("origin") == "import":
        head = d.get("head_hash") or "none"
        sentinel = info.path + "\x00reclaimed:" + head[:12]
        try:
            con.execute(
                "UPDATE session_files SET path=? WHERE file_id=?",
                (sentinel, d["file_id"]),
            )
        except sqlite3.IntegrityError:
            # A previous reclaim already occupied the sentinel; make it unique.
            sentinel = (
                info.path + "\x00reclaimed:" + head[:12]
                + ":" + str(d["file_id"])
            )
            con.execute(
                "UPDATE session_files SET path=? WHERE file_id=?",
                (sentinel, d["file_id"]),
            )
        if log:
            log(f"reclaimed import row for {info.path} -> sentinel")
        return None
    return d


def _create_file_row(con, info, st, head_hash: str, origin: str = "scan"):
    now = iso_now()
    cur = con.execute(
        """INSERT INTO session_files(path, session_id, path_session_id, kind,
               agent_id, project_slug, size, mtime_ns, inode, head_hash,
               tail_anchor, bytes_indexed, present, gone_at, last_seen_scan,
               origin, first_indexed_at, last_indexed_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            info.path, info.session_id, info.path_session_id, info.kind,
            info.agent_id, info.project_slug, st.st_size, st.st_mtime_ns,
            st.st_ino, head_hash, sha256_bytes(b""), 0, 1, None, 0,
            origin, now, now,
        ),
    )
    return cur.lastrowid


def _read_lines_from(path: str, start: int):
    """Yield (line_no_base_index, byte_off, raw_bytes) for complete lines.

    Only yields b'\\n'-terminated lines; a trailing unterminated tail is
    returned separately as leftover so the caller can hold bytes_indexed back.
    Streaming/chunked: safe for ~2.2MB single lines.
    """
    with open(path, "rb") as fh:
        fh.seek(start)
        offset = start
        buf = b""
        idx = 0
        while True:
            chunk = fh.read(READ_CHUNK)
            if not chunk:
                break
            buf += chunk
            *complete, buf = buf.split(b"\n")
            for line in complete:
                yield idx, offset, line
                offset += len(line) + 1
                idx += 1
        # buf now holds the trailing unterminated tail (possibly b"").
        yield None, offset, buf  # sentinel: (None, end_offset, leftover)


def index_file(con, info, scan_id: int, force_full: bool = False, log=None):
    """Index one discovered file. Returns (messages_added, touched_sessions).

    Implements the byte-resume continuity ladder. Wrap writes in chunked
    BEGIN IMMEDIATE transactions (2000 msgs / 4MB).
    """
    try:
        st = os.stat(info.path)
    except FileNotFoundError:
        return 0, set()
    size, mtime_ns, inode = st.st_size, st.st_mtime_ns, st.st_ino

    d = ensure_file_row(con, info, scan_id, log=log)
    if d is None:
        head = _head_hash_of(info.path, size)
        file_id = _create_file_row(con, info, st, head)
        d = {
            "file_id": file_id, "size": size, "mtime_ns": mtime_ns,
            "inode": inode, "head_hash": head,
            "tail_anchor": sha256_bytes(b""), "bytes_indexed": 0,
            "present": 1, "origin": "scan",
        }
        full = True
        start = 0
        line_base = 0
    else:
        file_id = d["file_id"]
        stored_size = d.get("size")
        stored_mtime = d.get("mtime_ns")
        stored_inode = d.get("inode")
        bytes_indexed = d.get("bytes_indexed") or 0
        if (
            not force_full
            and d.get("present") == 1
            and stored_size == size
            and stored_mtime == mtime_ns
            and stored_inode == inode
        ):
            # Fast path: nothing changed; just stamp last_seen_scan.
            con.execute(
                "UPDATE session_files SET last_seen_scan=?, present=1,"
                " gone_at=NULL WHERE file_id=?",
                (scan_id, file_id),
            )
            # Reappearance via fast path still clears a stale gone flag.
            return 0, set()
        head_now = _head_hash_of(info.path, size)
        if (
            force_full
            or stored_inode != inode
            or (d.get("head_hash") != head_now)
            or size < bytes_indexed
        ):
            full = True
        else:
            # Tail-anchor check against current file bytes.
            current_tail = sha256_bytes(_tail_bytes(info.path, bytes_indexed))
            full = current_tail != d.get("tail_anchor")
            if not full and bytes_indexed == size:
                # Tail matches and nothing new; refresh mtime/hash stamp.
                con.execute(
                    "UPDATE session_files SET last_seen_scan=?, present=1,"
                    " gone_at=NULL, mtime_ns=?, size=?, inode=?,"
                    " head_hash=?, last_indexed_at=? WHERE file_id=?",
                    (scan_id, mtime_ns, size, inode, head_now, iso_now(),
                     file_id),
                )
                return 0, set()
        if full:
            start = 0
            line_base = 0
        else:
            start = bytes_indexed
            line_base = _count_newlines_before(info.path, start)
        head = head_now

    touched: set[str] = set()
    touched.add(info.session_id)
    file_ctx = {"session_id": info.session_id, "agent_id": info.agent_id}

    if full:
        # Full reindex: drop messages (titles cascade via FK), reset anchors.
        # Done inside the first chunk transaction below.
        pass

    # Seed carry_ts_epoch: on a resumed read, from the latest stored message
    # so ai-title stamps reflect true prior context, not just the resumed
    # region. On full reindex the table is empty and this returns None.
    carry_ts_epoch = None if full else _latest_msg_ts_for_file(con, file_id)
    if full:
        # Titles were/will be deleted; spam-guard state resets too.
        last_title = None
    else:
        last_title = _last_title_for_file(con, file_id)

    mtime_fallback_epoch = (mtime_ns / 1e9) if mtime_ns else None

    con.execute("BEGIN IMMEDIATE")
    try:
        if full:
            con.execute("DELETE FROM messages WHERE file_id=?", (file_id,))
            con.execute(
                "DELETE FROM session_titles WHERE file_id=?", (file_id,)
            )
            carry_ts_epoch = None
            last_title = None
            bytes_done = 0
        else:
            bytes_done = start

        pending_msgs: list[dict] = []
        pending_titles: list[dict] = []
        chunk_bytes = 0
        total_added = 0
        end_offset = start
        gen = _read_lines_from(info.path, start)

        def flush():
            nonlocal pending_msgs, pending_titles, chunk_bytes, total_added
            nonlocal end_offset, carry_ts_epoch, last_title
            if pending_msgs:
                _insert_message_rows(con, file_id, pending_msgs)
                total_added += len(pending_msgs)
                pending_msgs = []
            if pending_titles:
                for t in pending_titles:
                    _insert_title_row(con, file_id, t)
                pending_titles = []
            # Advance the resume anchor to the last complete line, then commit
            # and immediately reopen the write txn.
            tail = sha256_bytes(_tail_bytes(info.path, end_offset))
            con.execute(
                "UPDATE session_files SET bytes_indexed=?, tail_anchor=?,"
                " size=?, mtime_ns=?, inode=?, head_hash=?,"
                " last_seen_scan=?, present=1, gone_at=NULL,"
                " last_indexed_at=? WHERE file_id=?",
                (end_offset, tail, size, mtime_ns, inode, head,
                 scan_id, iso_now(), file_id),
            )
            con.execute("COMMIT")
            con.execute("BEGIN IMMEDIATE")
            chunk_bytes = 0

        line_idx = 0
        leftover = b""
        for item_idx, off, raw in gen:
            if item_idx is None:
                leftover = raw
                end_offset = off
                break
            line_no = line_base + item_idx + 1  # 1-based file ordinal
            byte_off = off
            end_offset = off + len(raw) + 1
            chunk_bytes += len(raw) + 1
            line_idx += 1
            if not raw.strip():
                continue
            try:
                rec = json.loads(raw.decode("utf-8"))
            except Exception as e:
                if log:
                    log(f"{info.path}:{line_no}: malformed JSON, skip ({e})")
                continue
            if not isinstance(rec, dict):
                continue
            # Log layout/record session mismatch; record wins for rows.
            rec_sess = rec.get("sessionId") or rec.get("session_id")
            if rec_sess and rec_sess != info.session_id:
                if log:
                    log(
                        f"{info.path}:{line_no}: record sessionId {rec_sess} "
                        f"!= path session {info.session_id}; record wins"
                    )
            rows, title = record_to_messages(rec, file_ctx, line_no, byte_off)
            for r in rows:
                touched.add(r["session_id"])
                pending_msgs.append(r)
                if r["ts_epoch"] is not None:
                    carry_ts_epoch = r["ts_epoch"]
            if title is not None:
                touched.add(title["session_id"])
                title["ts_epoch"] = (
                    carry_ts_epoch
                    if carry_ts_epoch is not None
                    else mtime_fallback_epoch
                )
                # Skip repeated-title spam: same as highest-line_no row.
                if last_title is None or title["title"] != last_title:
                    pending_titles.append(title)
                    last_title = title["title"]
            if len(pending_msgs) >= CHUNK_MESSAGES or chunk_bytes >= CHUNK_BYTES:
                flush()

        # Final flush of this file's transaction (also persists when idle).
        if pending_msgs:
            _insert_message_rows(con, file_id, pending_msgs)
            total_added += len(pending_msgs)
            pending_msgs = []
        if pending_titles:
            for t in pending_titles:
                _insert_title_row(con, file_id, t)
            pending_titles = []
        tail = sha256_bytes(_tail_bytes(info.path, end_offset))
        con.execute(
            "UPDATE session_files SET bytes_indexed=?, tail_anchor=?,"
            " size=?, mtime_ns=?, inode=?, head_hash=?, last_seen_scan=?,"
            " present=1, gone_at=NULL, last_indexed_at=? WHERE file_id=?",
            (end_offset, tail, size, mtime_ns, inode, head, scan_id,
             iso_now(), file_id),
        )
        con.execute("COMMIT")
    except Exception:
        try:
            con.execute("ROLLBACK")
        except Exception:
            pass
        raise

    # Refresh every touched session OUTSIDE the file txn (short autocommit
    # writes). Order irrelevant: full recompute per session.
    for sess in touched:
        try:
            refresh_session(con, sess)
        except Exception as e:
            if log:
                log(f"refresh_session({sess}) failed: {e}")
    return total_added, touched
