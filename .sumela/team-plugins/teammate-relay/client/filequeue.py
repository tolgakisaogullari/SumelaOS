"""Task 6/7 — file-queue IPC between the daemon and the agent-facing CLIs.

No localhost port is ever opened (smaller attack surface, cross-platform). The daemon owns
the WSS socket; the CLIs (`ask`/`inbox`/`answer`) only read/write JSON files here:

  .sumela/.relay/outbox/<id>.json   CLI -> daemon  (a question/answer to send)
  .sumela/.relay/inbox/<id>.json    daemon -> CLI  (a received, decrypted, UNTRUSTED-wrapped item)

ALL writes are temp-file + atomic `os.rename` into the watched dir, so a watcher never
observes a half-written file (review I4). Readers only ever pick up `*.json` (never `*.tmp`).
"""

from __future__ import annotations

import json
import os
import tempfile
from typing import Dict, List, Tuple

INBOX = "inbox"
OUTBOX = "outbox"


class FileQueue:
    def __init__(self, base_dir: str):
        self._base = base_dir
        for sub in (INBOX, OUTBOX):
            os.makedirs(os.path.join(base_dir, sub), mode=0o700, exist_ok=True)

    def _dir(self, which: str) -> str:
        return os.path.join(self._base, which)

    def _write_atomic(self, which: str, name: str, obj: dict) -> str:
        d = self._dir(which)
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".wip-", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(obj, fh)
                fh.flush()
                os.fsync(fh.fileno())
            final = os.path.join(d, name + ".json")
            os.replace(tmp, final)   # atomic; watchers never see a partial file
            return final
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

    # -- producers ---------------------------------------------------------------------

    def put_outbox(self, entry_id: str, obj: dict) -> str:
        return self._write_atomic(OUTBOX, entry_id, obj)

    def put_inbox(self, entry_id: str, obj: dict) -> str:
        return self._write_atomic(INBOX, entry_id, obj)

    # -- consumers ---------------------------------------------------------------------

    def _list(self, which: str) -> List[Tuple[str, dict]]:
        d = self._dir(which)
        out: List[Tuple[str, dict]] = []
        for name in sorted(os.listdir(d)):
            if not name.endswith(".json"):
                continue   # skip in-flight .tmp files
            path = os.path.join(d, name)
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    out.append((path, json.load(fh)))
            except (ValueError, OSError):
                continue   # a concurrently-removed/partial file — skip
        return out

    def list_inbox(self) -> List[Tuple[str, dict]]:
        return self._list(INBOX)

    def drain_outbox(self) -> List[Tuple[str, dict]]:
        return self._list(OUTBOX)

    def remove(self, path: str) -> None:
        try:
            os.unlink(path)
        except OSError:
            pass
