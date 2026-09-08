"""Search engine and FTS query routing for claude-session-index.

No LIKE-scan fallback exists in this design — only the two FTS tables.
"""

from __future__ import annotations

import json
import os
import shlex
import sqlite3
import sys
import time
from extract import parse_ts_epoch


KIND_WEIGHTS = {
    "user": 1.0,
    "assistant": 0.9,
    "tool_use": 0.6,
    "thinking": 0.4,
}


def build_fts_query(user_query: str) -> str:
    """Format user query for unicode61 FTS5 table."""
    raw = user_query.strip()
    try:
        tokens = shlex.split(raw)
    except Exception:
        tokens = raw.split()
    if not tokens:
        return '""'
    escaped = []
    for t in tokens:
        clean = t.replace('"', '""')
        escaped.append(f'"{clean}"')
    return " ".join(escaped)


def build_tri_query(user_query: str) -> str:
    """Format user query for trigram FTS5 table."""
    clean = user_query.replace('"', '""')
    return f'"{clean}"'


def build_filter_clause(args) -> tuple[str, list]:
    """Compile filters once into a single WHERE clause applied identically to both FTS tables."""
    conds = []
    params = []

    # Exclusions by default
    if not getattr(args, "include_thinking", False):
        conds.append("m.kind != 'thinking'")
    if not getattr(args, "include_subagents", False):
        conds.append("m.is_sidechain = 0")
    if not getattr(args, "include_meta", False):
        conds.append("m.is_meta = 0")

    # Days / Since / Until
    now_epoch = time.time()
    if getattr(args, "days", None) is not None:
        min_epoch = now_epoch - float(args.days) * 86400.0
        conds.append("m.ts_epoch >= ?")
        params.append(min_epoch)
    if getattr(args, "since", None):
        e = parse_ts_epoch(args.since)
        if e is not None:
            conds.append("m.ts_epoch >= ?")
            params.append(e)
    if getattr(args, "until", None):
        e = parse_ts_epoch(args.until)
        if e is not None:
            conds.append("m.ts_epoch <= ?")
            params.append(e)

    # Project
    if getattr(args, "project", None):
        conds.append("sf.project_slug LIKE ?")
        params.append(f"%{args.project}%")

    # Cwd
    if getattr(args, "cwd", None):
        conds.append("m.cwd LIKE ?")
        params.append(f"{args.cwd}%")

    # Role
    if getattr(args, "role", None):
        conds.append("m.kind = ?")
        params.append(args.role)

    # Tool
    if getattr(args, "tool", None):
        conds.append("m.tool_name = ?")
        params.append(args.tool)

    # Session
    if getattr(args, "session", None):
        conds.append("(m.session_id = ? OR m.session_id LIKE ?)")
        params.extend([args.session, f"{args.session}%"])

    if not conds:
        return "", []
    return " AND " + " AND ".join(conds), params


def query_fts_table(
    con: sqlite3.Connection,
    fts_table: str,
    match_expr: str,
    where_clause: str,
    params: list,
    open_tag: str,
    close_tag: str,
    fetch_limit: int,
    escalated: bool = False,
) -> list[dict]:
    """Execute FTS query against messages_fts or messages_tri."""
    sql = f"""
        SELECT
            m.id,
            m.file_id,
            m.session_id,
            m.uuid,
            m.line_no,
            m.ts,
            m.ts_epoch,
            m.kind,
            m.tool_name,
            m.is_sidechain,
            m.is_meta,
            m.cwd,
            m.git_branch,
            sf.project_slug,
            sf.origin,
            s.title,
            bm25({fts_table}) AS bm25_score,
            snippet({fts_table}, 0, ?, ?, '...', 32) AS snippet_text
        FROM {fts_table}
        JOIN messages m ON m.id = {fts_table}.rowid
        JOIN session_files sf ON sf.file_id = m.file_id
        LEFT JOIN sessions s ON s.session_id = m.session_id
        WHERE {fts_table} MATCH ?
          {where_clause}
        ORDER BY bm25_score ASC
        LIMIT ?
    """
    all_params = [open_tag, close_tag, match_expr] + params + [fetch_limit]
    try:
        cur = con.execute(sql, all_params)
    except sqlite3.OperationalError as e:
        # e.g. syntax error in MATCH query
        return []

    hits = []
    now_epoch = time.time()
    for row in cur:
        d = {
            "id": row[0],
            "file_id": row[1],
            "session_id": row[2],
            "uuid": row[3],
            "line_no": row[4],
            "ts": row[5],
            "ts_epoch": row[6],
            "kind": row[7],
            "tool_name": row[8],
            "is_sidechain": row[9],
            "is_meta": row[10],
            "cwd": row[11],
            "git_branch": row[12],
            "project_slug": row[13],
            "origin": row[14],
            "title": row[15],
            "bm25_score": row[16],
            "snippet": row[17],
            "escalated": escalated,
        }
        # Ranking formula: -bm25 * kind_weight * recency_boost
        relevance = -d["bm25_score"] if d["bm25_score"] is not None else 0.0
        kw = KIND_WEIGHTS.get(d["kind"], 0.5)
        ts_epoch = d["ts_epoch"] or 0
        age_days = max(0.0, (now_epoch - ts_epoch) / 86400.0)
        recency_boost = 1.0 + 0.15 * max(0.0, 1.0 - (age_days / 90.0))
        d["score"] = relevance * kw * recency_boost
        hits.append(d)
    return hits


def execute_search(con: sqlite3.Connection, query: str, args) -> list[dict]:
    """Execute routed search with deduplication and ranking."""
    raw_query = query.strip()
    if len(raw_query) < 3:
        sys.stderr.write("Error: search query must be at least 3 characters long.\n")
        sys.exit(1)

    where_clause, params = build_filter_clause(args)
    limit = getattr(args, "limit", 10) or 10
    fetch_limit = limit * 5  # fetch extra for deduplication

    is_tty = sys.stdout.isatty() and not getattr(args, "json", False)
    open_tag = "\033[1;33m" if is_tty else "["
    close_tag = "\033[0m" if is_tty else "]"

    hits: list[dict] = []

    if getattr(args, "substring", False):
        # Query trigram directly
        tri_expr = build_tri_query(raw_query)
        hits = query_fts_table(
            con, "messages_tri", tri_expr, where_clause, params,
            open_tag, close_tag, fetch_limit, escalated=False
        )
    elif getattr(args, "exact", False):
        # Query FTS only, no escalation
        fts_expr = build_fts_query(raw_query)
        hits = query_fts_table(
            con, "messages_fts", fts_expr, where_clause, params,
            open_tag, close_tag, fetch_limit, escalated=False
        )
    else:
        # Default routing: FTS first, escalate to trigram if total hit
        # count < threshold (count, not fetched rows, drives the decision).
        escalate_thresh = getattr(args, "escalate_threshold", 3) or 3
        fts_expr = build_fts_query(raw_query)
        hits = query_fts_table(
            con, "messages_fts", fts_expr, where_clause, params,
            open_tag, close_tag, fetch_limit, escalated=False
        )
        try:
            fts_total = con.execute(
                "SELECT COUNT(*) FROM messages_fts "
                "JOIN messages m ON m.id = messages_fts.rowid "
                "JOIN session_files sf ON sf.file_id = m.file_id "
                f"WHERE messages_fts MATCH ?{where_clause}",
                [fts_expr] + params,
            ).fetchone()[0]
        except sqlite3.OperationalError:
            fts_total = len(hits)
        if fts_total < escalate_thresh:
            tri_expr = build_tri_query(raw_query)
            tri_hits = query_fts_table(
                con, "messages_tri", tri_expr, where_clause, params,
                open_tag, close_tag, fetch_limit, escalated=True
            )
            # Merge and deduplicate by message id
            existing_ids = {h["id"] for h in hits}
            for th in tri_hits:
                if th["id"] not in existing_ids:
                    hits.append(th)
                    existing_ids.add(th["id"])

    # Deduplicate by uuid, preferring origin='scan' over origin='import'
    deduped: dict[tuple[str, str], dict] = {}
    for hit in hits:
        uuid_key = hit["uuid"] or f"msg_id_{hit['id']}"
        key = (hit["session_id"], uuid_key)
        if key not in deduped:
            deduped[key] = hit
        else:
            existing = deduped[key]
            if existing["origin"] != "scan" and hit["origin"] == "scan":
                deduped[key] = hit
            elif existing["origin"] == hit["origin"]:
                if hit["score"] > existing["score"]:
                    deduped[key] = hit

    final_hits = list(deduped.values())
    final_hits.sort(key=lambda h: h["score"], reverse=True)
    return final_hits[:limit]


def search_titles(con: sqlite3.Connection, query: str, limit: int = 10) -> list[dict]:
    """Search session titles directly via LIKE scan."""
    cur = con.execute("""
        SELECT session_id, title, project_slug, cwd, first_ts, last_ts,
               msg_count, main_files_present
          FROM sessions
         WHERE title LIKE ?
         ORDER BY last_ts DESC
         LIMIT ?
    """, (f"%{query}%", limit))
    results = []
    for r in cur:
        results.append({
            "session_id": r[0],
            "title": r[1],
            "project_slug": r[2],
            "cwd": r[3],
            "first_ts": r[4],
            "last_ts": r[5],
            "msg_count": r[6],
            "main_files_present": r[7],
        })
    return results


def format_search_hit(rank: int, hit: dict) -> str:
    date_str = hit["ts"][:10] if hit["ts"] else "unknown date"
    proj = ""
    if hit.get("cwd"):
        proj = os.path.basename(hit["cwd"])
    if not proj:
        proj = hit.get("project_slug") or "unknown"
    short_sess = hit["session_id"][:8]
    title = hit.get("title") or "(no title)"
    role = hit["kind"]
    if hit.get("tool_name"):
        role = f"tool:{hit['tool_name']}"
    esc_tag = " [escalated: substring]" if hit.get("escalated") else ""

    lines = [
        f"#{rank}  {date_str}  {proj} ({short_sess})  [{role}]{esc_tag}",
        f"    Title: {title}",
        f"    {hit['snippet']}",
    ]
    expand_cmd = f"claude-session-index show {hit['session_id']}"
    if hit.get("uuid"):
        expand_cmd += f" --around {hit['uuid']}"
    elif hit.get("line_no"):
        expand_cmd += f" --line {hit['line_no']}"
    lines.append(f"    Expand: {expand_cmd}")
    return "\n".join(lines)
