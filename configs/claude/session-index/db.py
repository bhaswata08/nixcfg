"""SQLite schema, connection setup, and session aggregation for claude-session-index."""

from __future__ import annotations

import datetime
import sqlite3

SCHEMA_VERSION = "1"

SCHEMA_SQL = """
-- schema_version tracked here
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);

CREATE TABLE IF NOT EXISTS session_files (
  file_id INTEGER PRIMARY KEY,
  path TEXT UNIQUE NOT NULL,
  session_id TEXT NOT NULL,
  path_session_id TEXT,
  kind TEXT NOT NULL CHECK(kind IN ('main','subagent')),
  agent_id TEXT,
  project_slug TEXT,
  size INTEGER, mtime_ns INTEGER, inode INTEGER,
  head_hash TEXT,
  tail_anchor TEXT,
  bytes_indexed INTEGER NOT NULL DEFAULT 0,
  present INTEGER NOT NULL DEFAULT 1,
  gone_at TEXT,
  last_seen_scan INTEGER NOT NULL DEFAULT 0,
  origin TEXT NOT NULL DEFAULT 'scan',
  first_indexed_at TEXT, last_indexed_at TEXT
);
CREATE INDEX IF NOT EXISTS session_files_by_session ON session_files(session_id, kind);
CREATE INDEX IF NOT EXISTS session_files_present ON session_files(present, last_seen_scan);
CREATE INDEX IF NOT EXISTS session_files_slug ON session_files(project_slug);

CREATE TABLE IF NOT EXISTS sessions (
  session_id TEXT PRIMARY KEY,
  project_slug TEXT, cwd TEXT, git_branch TEXT,
  title TEXT, title_file_id INTEGER, title_line_no INTEGER,
  first_ts TEXT, last_ts TEXT,
  msg_count INTEGER NOT NULL DEFAULT 0,
  thinking_count INTEGER NOT NULL DEFAULT 0,
  subagent_msg_count INTEGER NOT NULL DEFAULT 0,
  file_count INTEGER NOT NULL DEFAULT 0,
  files_present INTEGER NOT NULL DEFAULT 0,
  main_files_present INTEGER NOT NULL DEFAULT 0,
  main_files_total INTEGER NOT NULL DEFAULT 0,
  last_refreshed_at TEXT
);
-- EVERY column above except session_id is written ONLY by refresh_session(),
-- a full recompute from messages/session_files/session_titles. No other code
-- path writes to this table, which makes file-processing order irrelevant.

CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY,
  file_id INTEGER NOT NULL REFERENCES session_files(file_id) ON DELETE CASCADE,
  session_id TEXT NOT NULL,
  uuid TEXT, parent_uuid TEXT, agent_id TEXT,
  line_no INTEGER, byte_off INTEGER,
  ts TEXT, ts_epoch REAL,
  kind TEXT NOT NULL CHECK(kind IN ('user','assistant','thinking','tool_use')),
  tool_name TEXT,
  is_sidechain INTEGER NOT NULL DEFAULT 0,
  is_meta INTEGER NOT NULL DEFAULT 0,
  truncated INTEGER NOT NULL DEFAULT 0,
  cwd TEXT, git_branch TEXT,
  text TEXT NOT NULL,
  UNIQUE(file_id, uuid)
);
CREATE INDEX IF NOT EXISTS messages_by_session ON messages(session_id, line_no);
CREATE INDEX IF NOT EXISTS messages_ts ON messages(ts_epoch);
CREATE INDEX IF NOT EXISTS messages_kind ON messages(kind);
CREATE INDEX IF NOT EXISTS messages_cwd ON messages(cwd);
CREATE INDEX IF NOT EXISTS messages_agent ON messages(agent_id);

CREATE TABLE IF NOT EXISTS session_titles (
  file_id INTEGER NOT NULL REFERENCES session_files(file_id) ON DELETE CASCADE,
  line_no INTEGER NOT NULL,
  session_id TEXT NOT NULL,
  title TEXT NOT NULL,
  ts_epoch REAL,
  PRIMARY KEY (file_id, line_no)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS session_titles_by_session ON session_titles(session_id, ts_epoch DESC, line_no DESC);

CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
  text, content='messages', content_rowid='id',
  tokenize="unicode61 remove_diacritics 2 tokenchars '_'"
);
CREATE VIRTUAL TABLE IF NOT EXISTS messages_tri USING fts5(
  text, content='messages', content_rowid='id',
  tokenize="trigram remove_diacritics 1"
);

-- Six triggers: the ONLY way content enters the FTS tables (external-content
-- idiom). No separate fallback path, no LIKE-scan fallback anywhere.
CREATE TRIGGER IF NOT EXISTS messages_fts_insert AFTER INSERT ON messages BEGIN
  INSERT INTO messages_fts(rowid, text) VALUES (new.id, new.text);
END;
CREATE TRIGGER IF NOT EXISTS messages_fts_delete AFTER DELETE ON messages BEGIN
  INSERT INTO messages_fts(messages_fts, rowid, text) VALUES('delete', old.id, old.text);
END;
CREATE TRIGGER IF NOT EXISTS messages_fts_update AFTER UPDATE ON messages BEGIN
  INSERT INTO messages_fts(messages_fts, rowid, text) VALUES('delete', old.id, old.text);
  INSERT INTO messages_fts(rowid, text) VALUES (new.id, new.text);
END;
CREATE TRIGGER IF NOT EXISTS messages_tri_insert AFTER INSERT ON messages BEGIN
  INSERT INTO messages_tri(rowid, text) VALUES (new.id, new.text);
END;
CREATE TRIGGER IF NOT EXISTS messages_tri_delete AFTER DELETE ON messages BEGIN
  INSERT INTO messages_tri(messages_tri, rowid, text) VALUES('delete', old.id, old.text);
END;
CREATE TRIGGER IF NOT EXISTS messages_tri_update AFTER UPDATE ON messages BEGIN
  INSERT INTO messages_tri(messages_tri, rowid, text) VALUES('delete', old.id, old.text);
  INSERT INTO messages_tri(rowid, text) VALUES (new.id, new.text);
END;
"""


def iso_now() -> str:
    return (
        datetime.datetime.now(datetime.timezone.utc)
        .isoformat(timespec="seconds")
    )


def connect(db_path: str) -> sqlite3.Connection:
    """Open a DB connection with the required pragmas.

    isolation_level=None (autocommit) so callers manage transactions explicitly
    with BEGIN IMMEDIATE / COMMIT for the chunked indexing writes.
    """
    con = sqlite3.connect(db_path, timeout=15.0)
    con.isolation_level = None
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA busy_timeout=15000")
    con.execute("PRAGMA synchronous=NORMAL")
    con.execute("PRAGMA foreign_keys=ON")
    con.execute("PRAGMA wal_autocheckpoint=1000")
    con.execute("PRAGMA temp_store=MEMORY")
    return con


def init_db(con: sqlite3.Connection) -> None:
    con.executescript(SCHEMA_SQL)
    row = con.execute(
        "SELECT value FROM meta WHERE key='schema_version'"
    ).fetchone()
    if row is None:
        con.execute(
            "INSERT INTO meta(key, value) VALUES('schema_version', ?)",
            (SCHEMA_VERSION,),
        )
    elif row[0] != SCHEMA_VERSION:
        # v1 is the first version; any older value is unexpected. Bump the
        # marker so future migrations have a defined starting point.
        con.execute(
            "UPDATE meta SET value=? WHERE key='schema_version'",
            (SCHEMA_VERSION,),
        )
    # This is a new build; there is no pre-existing DB to migrate
    # (session_titles has no source in any older schema).


def get_meta(con: sqlite3.Connection, key: str) -> str | None:
    row = con.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
    return row[0] if row else None


def set_meta(con: sqlite3.Connection, key: str, value: str | None) -> None:
    if value is None:
        con.execute("DELETE FROM meta WHERE key=?", (key,))
    else:
        con.execute(
            "INSERT INTO meta(key, value) VALUES(?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            (key, value),
        )


def clear_reconcile_pending(con: sqlite3.Connection) -> None:
    for k in (
        "reconcile_pending_digest",
        "reconcile_pending_count",
        "reconcile_pending_attempts",
        "reconcile_pending_first_seen_at",
        "reconcile_pending_first_scan_id",
        "reconcile_pending_last_scan_id",
    ):
        con.execute("DELETE FROM meta WHERE key=?", (k,))


def refresh_session(con: sqlite3.Connection, session_id: str) -> None:
    """Recompute EVERY sessions column (except the key) from scratch.

    This is the ONLY writer to the sessions table, so file-processing order
    is irrelevant: each file's pass refreshes every session it touched.
    """
    now = iso_now()

    def one(sql: str, *args):
        row = con.execute(sql, (session_id,) + args).fetchone()
        return row[0] if row else None

    msg_count = one("SELECT COUNT(*) FROM messages WHERE session_id=?") or 0
    thinking_count = (
        one(
            "SELECT COUNT(*) FROM messages WHERE session_id=? AND kind='thinking'"
        )
        or 0
    )
    subagent_msg_count = (
        one(
            "SELECT COUNT(*) FROM messages WHERE session_id=? AND is_sidechain=1"
        )
        or 0
    )
    first_ts = one("SELECT MIN(ts) FROM messages WHERE session_id=?")
    last_ts = one("SELECT MAX(ts) FROM messages WHERE session_id=?")

    file_count = (
        one("SELECT COUNT(*) FROM session_files WHERE session_id=?") or 0
    )
    files_present = (
        one(
            "SELECT COUNT(*) FROM session_files WHERE session_id=? AND present=1"
        )
        or 0
    )
    main_files_present = (
        one(
            "SELECT COUNT(*) FROM session_files "
            "WHERE session_id=? AND kind='main' AND present=1"
        )
        or 0
    )
    main_files_total = (
        one(
            "SELECT COUNT(*) FROM session_files "
            "WHERE session_id=? AND kind='main'"
        )
        or 0
    )

    # Title: no sf.present filter — archived/absent files still supply titles.
    trow = con.execute(
        """
        SELECT st.title, st.file_id, st.line_no
          FROM session_titles st JOIN session_files sf USING (file_id)
         WHERE st.session_id = ?
         ORDER BY (sf.kind='main') DESC, st.ts_epoch IS NULL,
                  st.ts_epoch DESC, st.line_no DESC, st.file_id DESC
         LIMIT 1
        """,
        (session_id,),
    ).fetchone()
    title, title_file_id, title_line_no = (None, None, None)
    if trow:
        title, title_file_id, title_line_no = trow

    # cwd / git_branch / project_slug are selected INDEPENDENTLY: a session
    # can have two main files with different latest activity, and each column
    # reflects its own most-recent-by-timestamp value.
    cwd = con.execute(
        """
        SELECT m.cwd FROM messages m JOIN session_files sf USING(file_id)
         WHERE m.session_id=? AND m.cwd IS NOT NULL
         ORDER BY (sf.kind='main') DESC, m.ts_epoch IS NULL,
                  m.ts_epoch DESC, m.line_no DESC, m.file_id DESC
         LIMIT 1
        """,
        (session_id,),
    ).fetchone()
    cwd = cwd[0] if cwd else None

    git_branch = con.execute(
        """
        SELECT m.git_branch FROM messages m JOIN session_files sf USING(file_id)
         WHERE m.session_id=? AND m.git_branch IS NOT NULL
         ORDER BY (sf.kind='main') DESC, m.ts_epoch IS NULL,
                  m.ts_epoch DESC, m.line_no DESC, m.file_id DESC
         LIMIT 1
        """,
        (session_id,),
    ).fetchone()
    git_branch = git_branch[0] if git_branch else None

    project_slug = con.execute(
        """
        SELECT sf.project_slug FROM messages m JOIN session_files sf USING(file_id)
         WHERE m.session_id=? AND sf.project_slug IS NOT NULL
         ORDER BY (sf.kind='main') DESC, m.ts_epoch IS NULL,
                  m.ts_epoch DESC, m.line_no DESC, m.file_id DESC
         LIMIT 1
        """,
        (session_id,),
    ).fetchone()
    project_slug = project_slug[0] if project_slug else None
    if project_slug is None:
        # A session whose messages are all gone (or that only has titles)
        # still deserves its slug from the file layout.
        srow = con.execute(
            "SELECT project_slug FROM session_files "
            "WHERE session_id=? AND project_slug IS NOT NULL LIMIT 1",
            (session_id,),
        ).fetchone()
        project_slug = srow[0] if srow else None

    con.execute(
        """
        INSERT INTO sessions(session_id, project_slug, cwd, git_branch,
          title, title_file_id, title_line_no, first_ts, last_ts,
          msg_count, thinking_count, subagent_msg_count,
          file_count, files_present, main_files_present, main_files_total,
          last_refreshed_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(session_id) DO UPDATE SET
          project_slug=excluded.project_slug, cwd=excluded.cwd,
          git_branch=excluded.git_branch, title=excluded.title,
          title_file_id=excluded.title_file_id,
          title_line_no=excluded.title_line_no,
          first_ts=excluded.first_ts, last_ts=excluded.last_ts,
          msg_count=excluded.msg_count,
          thinking_count=excluded.thinking_count,
          subagent_msg_count=excluded.subagent_msg_count,
          file_count=excluded.file_count,
          files_present=excluded.files_present,
          main_files_present=excluded.main_files_present,
          main_files_total=excluded.main_files_total,
          last_refreshed_at=excluded.last_refreshed_at
        """,
        (
            session_id, project_slug, cwd, git_branch,
            title, title_file_id, title_line_no, first_ts, last_ts,
            msg_count, thinking_count, subagent_msg_count,
            file_count, files_present, main_files_present,
            main_files_total, now,
        ),
    )
