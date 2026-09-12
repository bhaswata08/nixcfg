"""Cross-process advisory locking for claude-session-index.

A cross-process advisory lock via fcntl.flock(LOCK_EX, ...) on a separate
index.lock file, held for the whole duration of an indexing pass (not held by readers):
- Hook-invoked indexing: LOCK_EX | LOCK_NB; on failure to acquire, exit 0
  immediately and silently (another pass already covers this).
- Search-invoked indexing (the pre-query index-on-query-time pass, unless --no-index
  is passed): blocking acquire with a 3000ms deadline; on timeout, skip indexing
  and search anyway, printing one stderr line noting results may be stale.
- index --wait: blocking acquire, no deadline, for manual full rebuilds.
- Lock file records pid + start time for doctor to report a stale/stuck holder.
  flock releases automatically on process death.
"""

from __future__ import annotations

import fcntl
import os
import time


class IndexLock:
    def __init__(self, lock_path: str):
        self.lock_path = lock_path
        self.fd: int | None = None

    def acquire(self, mode: str = "wait") -> bool:
        """Acquire the lock.

        mode:
          hook: LOCK_EX | LOCK_NB, returns False immediately on contention.
          search: blocking with 3000ms deadline, returns False on timeout.
          wait: blocking LOCK_EX, no deadline.
          nowait: LOCK_EX | LOCK_NB, returns False on contention.
        """
        os.makedirs(os.path.dirname(os.path.abspath(self.lock_path)), exist_ok=True)
        self.fd = os.open(self.lock_path, os.O_RDWR | os.O_CREAT, 0o644)

        if mode in ("hook", "nowait"):
            try:
                fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except (BlockingIOError, OSError):
                os.close(self.fd)
                self.fd = None
                return False
        elif mode == "search":
            deadline = time.time() + 3.0
            acquired = False
            while time.time() < deadline:
                try:
                    fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    acquired = True
                    break
                except (BlockingIOError, OSError):
                    time.sleep(0.05)
            if not acquired:
                os.close(self.fd)
                self.fd = None
                return False
        elif mode == "wait":
            fcntl.flock(self.fd, fcntl.LOCK_EX)
        else:
            raise ValueError(f"Unknown lock mode: {mode}")

        try:
            os.ftruncate(self.fd, 0)
            os.lseek(self.fd, 0, os.SEEK_SET)
            payload = f"{os.getpid()} {int(time.time())}\n".encode("utf-8")
            os.write(self.fd, payload)
            os.fsync(self.fd)
        except OSError:
            pass
        return True

    def release(self) -> None:
        if self.fd is not None:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_UN)
            except OSError:
                pass
            try:
                os.close(self.fd)
            except OSError:
                pass
            self.fd = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.release()


def inspect_lock(lock_path: str) -> dict | None:
    """Inspect index.lock to check if it is currently held."""
    if not os.path.exists(lock_path):
        return None
    try:
        fd = os.open(lock_path, os.O_RDWR)
    except OSError:
        return None

    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(fd, fcntl.LOCK_UN)
            return None
        except (BlockingIOError, OSError):
            pass

        pid = None
        start_time = None
        duration = None
        try:
            os.lseek(fd, 0, os.SEEK_SET)
            data = os.read(fd, 256).decode("utf-8", errors="ignore").strip()
            parts = data.split()
            if len(parts) >= 2:
                pid = int(parts[0])
                start_time = int(parts[1])
                duration = max(0.0, time.time() - start_time)
            elif len(parts) == 1:
                pid = int(parts[0])
        except Exception:
            pass

        return {
            "held": True,
            "pid": pid,
            "start_time": start_time,
            "duration": duration,
        }
    finally:
        os.close(fd)
