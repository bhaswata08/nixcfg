"""Atomic settings.json updater with flock, symlink guard, and race retry.

Shared helper for home-manager activation scripts modifying ~/.claude/settings.json.
"""

from __future__ import annotations

import datetime
import fcntl
import json
import os
import sys
import time
from typing import Callable


def atomic_modify_settings(modifier_fn: Callable[[dict], None]) -> None:
    """Apply modifier_fn to ~/.claude/settings.json safely.

    Guarantees:
    1. Symlink guard: refuses to write if ~/.claude/settings.json is a symlink.
    2. Cross-activation serialization via flock on ~/.claude/.settings.json.hm-lock.
    3. Re-stat race check up to 5 attempts with 200ms backoff.
    4. Preserves file mode (st_mode).
    5. Atomic replace via temporary file in the same directory.
    """
    target_path = os.path.expanduser("~/.claude/settings.json")
    claude_dir = os.path.dirname(target_path)
    os.makedirs(claude_dir, exist_ok=True)

    # 1. Symlink guard: check un-realpath'd path BEFORE reading.
    if os.path.islink(target_path):
        sys.stderr.write(
            "~/.claude/settings.json is a symlink; refusing to write through it to "
            "avoid silently replacing the link — resolve this manually\n"
        )
        sys.exit(1)

    target_path = os.path.realpath(target_path)
    claude_dir = os.path.dirname(target_path)

    # 2. Acquire flock on separate lockfile to serialize home-manager activations
    lock_path = os.path.join(claude_dir, ".settings.json.hm-lock")
    lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o644)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)

    try:
        max_attempts = 5
        for attempt in range(1, max_attempts + 1):
            file_existed = os.path.exists(target_path)
            orig_mode = 0o644
            mtime_ns = None
            size = None
            settings: dict = {}

            if file_existed:
                st = os.stat(target_path)
                orig_mode = st.st_mode
                mtime_ns = st.st_mtime_ns
                size = st.st_size
                try:
                    with open(target_path, "r", encoding="utf-8") as f:
                        settings = json.load(f)
                    if not isinstance(settings, dict):
                        settings = {}
                except Exception:
                    # Unparseable JSON: backup broken original to settings.json.bak-<ISO8601>
                    iso_str = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
                    bak_path = f"{target_path}.bak-{iso_str}"
                    sys.stderr.write(f"Warning: {target_path} was unparseable; backing up to {bak_path}\n")
                    try:
                        os.rename(target_path, bak_path)
                    except OSError:
                        pass
                    settings = {}
                    file_existed = False

            # Mutate in memory
            modifier_fn(settings)

            # Race check: re-stat the file
            # Code comment: this narrows but does NOT fully close the race against
            # Claude Code's own concurrent writes (it doesn't honor flock) — a write
            # landing between the final check and the atomic replace is still possible
            # and accepted as a bounded risk.
            if file_existed:
                if not os.path.exists(target_path):
                    time.sleep(0.2)
                    continue
                st_now = os.stat(target_path)
                if st_now.st_mtime_ns != mtime_ns or st_now.st_size != size:
                    time.sleep(0.2)
                    continue
            else:
                if os.path.exists(target_path):
                    time.sleep(0.2)
                    continue

            # Write to temp file in SAME directory
            tmp_path = os.path.join(claude_dir, f"settings.json.hm-tmp.{os.getpid()}")
            try:
                with open(tmp_path, "w", encoding="utf-8") as f:
                    json.dump(settings, f, indent=2)
                    f.write("\n")
                    f.flush()
                    os.fsync(f.fileno())

                os.chmod(tmp_path, orig_mode)
                os.replace(tmp_path, target_path)
                return
            finally:
                if os.path.exists(tmp_path):
                    try:
                        os.remove(tmp_path)
                    except OSError:
                        pass

        sys.stderr.write(
            "Warning: failed to update ~/.claude/settings.json after 5 attempts due to "
            "concurrent writes; leaving file untouched.\n"
        )
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except OSError:
            pass
        os.close(lock_fd)


def update_hook(stable_path: str) -> None:
    """Ensure claude-session-index hook is registered in hooks.SessionStart."""
    sentinel = "claude-session-index hook"

    def modifier(settings: dict) -> None:
        if "hooks" not in settings or not isinstance(settings["hooks"], dict):
            settings["hooks"] = {}
        if "SessionStart" not in settings["hooks"] or not isinstance(settings["hooks"]["SessionStart"], list):
            settings["hooks"]["SessionStart"] = []

        new_groups = []
        for group in settings["hooks"]["SessionStart"]:
            if isinstance(group, dict) and "hooks" in group and isinstance(group["hooks"], list):
                # Filter out entries matching sentinel
                kept_hooks = [
                    h for h in group["hooks"]
                    if not (isinstance(h, dict) and sentinel in h.get("command", ""))
                ]
                if kept_hooks:
                    group["hooks"] = kept_hooks
                    new_groups.append(group)
            else:
                new_groups.append(group)

        # Append exactly one new group without matcher (fires on every SessionStart source)
        new_groups.append({
            "hooks": [
                {
                    "type": "command",
                    "command": f"{stable_path} hook",
                    "timeout": 5,
                }
            ]
        })
        settings["hooks"]["SessionStart"] = new_groups

    atomic_modify_settings(modifier)


def update_plugin(plugin_name: str) -> None:
    """Ensure plugin is enabled in enabledPlugins."""
    def modifier(settings: dict) -> None:
        if "enabledPlugins" not in settings or not isinstance(settings["enabledPlugins"], dict):
            settings["enabledPlugins"] = {}
        settings["enabledPlugins"][plugin_name] = True

    atomic_modify_settings(modifier)


def main() -> None:
    if len(sys.argv) < 2:
        sys.stderr.write("Usage: settings_updater.py <hook|enable-plugin> [args...]\n")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "hook":
        if len(sys.argv) < 3:
            sys.stderr.write("Usage: settings_updater.py hook <stable_path>\n")
            sys.exit(1)
        update_hook(sys.argv[2])
    elif cmd == "enable-plugin":
        if len(sys.argv) < 3:
            sys.stderr.write("Usage: settings_updater.py enable-plugin <plugin_name>\n")
            sys.exit(1)
        update_plugin(sys.argv[2])
    else:
        sys.stderr.write(f"Unknown command: {cmd}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
