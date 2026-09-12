"""Transcript viewer for claude-session-index.

Reads ONLY from the messages table (joined to session_files), never re-reads
source files — works after files are cleaned up.
"""

from __future__ import annotations

import sqlite3
import sys


def run_show(con: sqlite3.Connection, session_id: str, args) -> None:
    """Format and display transcript messages for session_id."""
    # Support prefix lookup for session_id
    srow = con.execute(
        "SELECT session_id, main_files_present, title FROM sessions "
        "WHERE session_id = ? OR session_id LIKE ? LIMIT 1",
        (session_id, f"{session_id}%"),
    ).fetchone()

    full_session_id = srow[0] if srow else session_id
    main_files_present = srow[1] if srow else 0
    session_title = srow[2] if srow else None

    # Fetch messages joined with session_files
    cur = con.execute("""
        SELECT m.id, m.file_id, m.session_id, m.uuid, m.parent_uuid, m.agent_id,
               m.line_no, m.byte_off, m.ts, m.ts_epoch, m.kind, m.tool_name,
               m.is_sidechain, m.is_meta, m.truncated, m.cwd, m.git_branch, m.text,
               sf.kind AS sf_kind, sf.agent_id AS sf_agent_id, sf.present, sf.origin
          FROM messages m
          JOIN session_files sf USING (file_id)
         WHERE m.session_id = ?
         ORDER BY m.ts_epoch IS NULL, m.ts_epoch ASC, m.line_no ASC, m.id ASC
    """, (full_session_id,))

    rows = []
    for r in cur:
        rows.append({
            "id": r[0],
            "file_id": r[1],
            "session_id": r[2],
            "uuid": r[3],
            "parent_uuid": r[4],
            "agent_id": r[5],
            "line_no": r[6],
            "byte_off": r[7],
            "ts": r[8],
            "ts_epoch": r[9],
            "kind": r[10],
            "tool_name": r[11],
            "is_sidechain": r[12],
            "is_meta": r[13],
            "truncated": r[14],
            "cwd": r[15],
            "git_branch": r[16],
            "text": r[17],
            "sf_kind": r[18],
            "sf_agent_id": r[19],
            "present": r[20],
            "origin": r[21],
        })

    if not rows:
        sys.stderr.write(f"No indexed messages found for session: {full_session_id}\n")
        return

    # Filter subagents unless requested
    include_subagents = getattr(args, "include_subagents", False)
    if not include_subagents:
        rows = [r for r in rows if r["is_sidechain"] == 0]

    # Filter agent if specified
    target_agent = getattr(args, "agent", None)
    if target_agent:
        rows = [
            r for r in rows
            if r["agent_id"] == target_agent or r["sf_agent_id"] == target_agent
        ]

    # Deduplicate by uuid: prefer origin='scan' over origin='import'
    deduped: dict[str, dict] = {}
    for r in rows:
        ukey = r["uuid"] or f"msg_id_{r['id']}"
        if ukey not in deduped:
            deduped[ukey] = r
        else:
            existing = deduped[ukey]
            if existing["origin"] != "scan" and r["origin"] == "scan":
                deduped[ukey] = r

    final_msgs = list(deduped.values())
    final_msgs.sort(key=lambda m: (m["ts_epoch"] is None, m["ts_epoch"] or 0, m["line_no"] or 0, m["id"]))

    # Windowing: --around <uuid> or --line <line_no>
    around_uuid = getattr(args, "around", None)
    line_no = getattr(args, "line", None)
    context_n = getattr(args, "context", 5) or 5

    if around_uuid:
        # Find match by uuid
        target_idx = None
        for idx, m in enumerate(final_msgs):
            if m["uuid"] and (m["uuid"] == around_uuid or m["uuid"].startswith(around_uuid)):
                target_idx = idx
                break
        if target_idx is not None:
            s_idx = max(0, target_idx - context_n)
            e_idx = min(len(final_msgs), target_idx + context_n + 1)
            final_msgs = final_msgs[s_idx:e_idx]
    elif line_no is not None:
        target_idx = None
        for idx, m in enumerate(final_msgs):
            if m["line_no"] == line_no:
                target_idx = idx
                break
        if target_idx is not None:
            s_idx = max(0, target_idx - context_n)
            e_idx = min(len(final_msgs), target_idx + context_n + 1)
            final_msgs = final_msgs[s_idx:e_idx]

    max_chars = getattr(args, "max_chars", 8000) or 8000
    total_chars = 0

    print(f"Session: {full_session_id}")
    if session_title:
        print(f"Title:   {session_title}")
    print("=" * 70)

    for m in final_msgs:
        role = m["kind"].upper()
        if m["tool_name"]:
            role = f"TOOL_USE: {m['tool_name']}"
        agent_str = f" [Agent: {m['agent_id']}]" if m.get("agent_id") else ""
        ts_str = m["ts"][:19] if m["ts"] else "no-ts"
        header = f"--- [{role}]{agent_str} {ts_str} (line {m['line_no']}) ---"
        text = m["text"]

        needed = len(header) + len(text) + 2
        if total_chars + needed > max_chars:
            allowed = max(0, max_chars - total_chars - len(header) - 50)
            if allowed > 0:
                print(header)
                print(text[:allowed] + "... [message truncated]")
            print(f"\n[... transcript truncated at {max_chars} max chars ...]")
            break

        print(header)
        print(text)
        print()
        total_chars += needed

    print("=" * 70)
    if main_files_present > 0:
        print(f"claude --resume {full_session_id}")
    else:
        print("archived — original transcript file(s) no longer present, showing indexed content only.")
