"""Shared path resolution for claude-session-index.

DB path resolution, in order:
  1. $CLAUDE_SESSION_INDEX_DB env var
  2. <realpath of the resolved config dir's projects/ directory's parent>/session-index/index.db

Rule 2 is what makes the two profiles converge: ~/.claude-personal/projects is
a symlink to ~/.claude/projects, so realpath() collapses both to
~/.claude/session-index/index.db automatically.
"""

from __future__ import annotations

import os

SESSION_INDEX_DIRNAME = "session-index"
DB_FILENAME = "index.db"
LOCK_FILENAME = "index.lock"
LOG_FILENAME = "index.log"
SNAPSHOTS_DIRNAME = "snapshots"


def resolve_config_dir() -> str:
    """Config dir: $CLAUDE_CONFIG_DIR or ~/.claude."""
    d = os.environ.get("CLAUDE_CONFIG_DIR")
    if d:
        return os.path.expanduser(d)
    return os.path.expanduser("~/.claude")


def resolve_projects_dir() -> str:
    return os.path.join(resolve_config_dir(), "projects")


def resolve_db_path() -> str:
    env = os.environ.get("CLAUDE_SESSION_INDEX_DB")
    if env:
        return os.path.expanduser(env)
    projects = resolve_projects_dir()
    # realpath() first so a symlinked projects dir (e.g. ~/.claude-personal)
    # converges on the same parent as the canonical tree.
    parent = os.path.dirname(os.path.realpath(projects))
    return os.path.join(parent, SESSION_INDEX_DIRNAME, DB_FILENAME)


def index_dir_for(db_path: str) -> str:
    return os.path.dirname(os.path.abspath(db_path))


def lock_path_for(db_path: str) -> str:
    return os.path.join(index_dir_for(db_path), LOCK_FILENAME)


def log_path_for(db_path: str) -> str:
    return os.path.join(index_dir_for(db_path), LOG_FILENAME)


def snapshots_dir_for(db_path: str) -> str:
    return os.path.join(index_dir_for(db_path), SNAPSHOTS_DIRNAME)


def settings_path_default() -> str:
    """Canonical settings.json location (NOT realpath'd by callers that need
    the symlink guard to see the link itself)."""
    return os.path.expanduser("~/.claude/settings.json")
