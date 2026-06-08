"""Task 3 — presence registry: who is connected right now.

One live connection per client (the client enforces a single-instance daemon lock; the
server additionally displaces an older connection if the same id reconnects, so presence
can't be split-brained). The server NEVER reads message content — presence is pure
connection state.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional


class PresenceRegistry:
    def __init__(self):
        self._conns: Dict[str, Any] = {}

    def connect(self, client_id: str, conn: Any) -> Optional[Any]:
        """Register a connection. If the id was already online, return the DISPLACED
        connection so the caller can close it (no split-brain)."""
        displaced = self._conns.get(client_id)
        self._conns[client_id] = conn
        return displaced

    def disconnect(self, client_id: str, conn: Any = None) -> None:
        """Remove the client's connection. If `conn` is given, only remove it when it is
        still the current one (a stale disconnect from a displaced socket is ignored)."""
        cur = self._conns.get(client_id)
        if cur is None:
            return
        if conn is not None and cur is not conn:
            return
        del self._conns[client_id]

    def is_online(self, client_id: str) -> bool:
        return client_id in self._conns

    def get(self, client_id: str) -> Optional[Any]:
        return self._conns.get(client_id)

    def online_ids(self) -> List[str]:
        return sorted(self._conns.keys())
