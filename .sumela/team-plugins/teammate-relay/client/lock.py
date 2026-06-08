"""Task 6 — single-instance daemon lock (review I3: two daemons must not run for one dev).

A second daemon refuses to start, so presence can't flap and the queue can't deliver to a
dead socket. Uses an exclusive non-blocking `flock` on a pidfile under the gitignored
`.sumela/.relay/` runtime dir. Degrades to a no-op if `fcntl` is unavailable (non-POSIX);
the OS-autostart story is documented per-platform in DEPLOY.md.
"""

from __future__ import annotations

import os

try:
    import fcntl as _fcntl
except Exception:  # pragma: no cover - non-POSIX
    _fcntl = None


class AlreadyRunning(Exception):
    pass


class SingleInstanceLock:
    def __init__(self, path: str):
        self._path = path
        self._fh = None

    def acquire(self) -> "SingleInstanceLock":
        os.makedirs(os.path.dirname(self._path) or ".", mode=0o700, exist_ok=True)
        self._fh = open(self._path, "w")
        if _fcntl is not None:
            try:
                _fcntl.flock(self._fh, _fcntl.LOCK_EX | _fcntl.LOCK_NB)
            except OSError:
                self._fh.close()
                self._fh = None
                raise AlreadyRunning("another relay daemon already holds %s" % self._path)
        else:
            # No POSIX locking: single-instance is UNENFORCED. Warn loudly rather than
            # silently allow two daemons (double-delivery / double-receipts) — review I4.
            import sys
            sys.stderr.write(
                "WARNING: fcntl unavailable — relay single-instance lock is NOT enforced on "
                "this platform; do not start more than one daemon.\n")
        self._fh.write(str(os.getpid()))
        self._fh.flush()
        return self

    def release(self) -> None:
        if self._fh is not None:
            try:
                if _fcntl is not None:
                    _fcntl.flock(self._fh, _fcntl.LOCK_UN)
            finally:
                self._fh.close()
                self._fh = None

    def __enter__(self):
        return self.acquire()

    def __exit__(self, *exc):
        self.release()
