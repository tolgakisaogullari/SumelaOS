"""Task 3 — per-(sender, recipient) FAIR, bounded, TTL offline queue (M2).

The server holds only ciphertext frames + routing metadata — it cannot read content.
Fairness: the cap is PER (sender, recipient) pair, so one spammy sender filling its own
queue to `recipient` can NEVER evict another sender's legitimate queued items to the same
recipient. Expired items are surfaced (not silently dropped) so the asker can be told the
question expired unanswered.
"""

from __future__ import annotations

from collections import deque
from typing import Deque, Dict, List, Tuple

DEFAULT_TTL = 7 * 24 * 3600   # 7 days
DEFAULT_MAX_PER_PAIR = 100


class FairOfflineQueue:
    def __init__(self, ttl: int = DEFAULT_TTL, max_per_pair: int = DEFAULT_MAX_PER_PAIR):
        self._ttl = ttl
        self._max_per_pair = max_per_pair
        self._pairs: Dict[Tuple[str, str], Deque[Tuple[int, float, dict]]] = {}
        self._seq = 0

    def enqueue(self, sender: str, recipient: str, frame: dict, now: float):
        """Queue a ciphertext frame for an offline recipient. Returns the dropped
        (overflow) entry frame if the per-pair cap was exceeded, else None."""
        self._seq += 1
        dq = self._pairs.setdefault((sender, recipient), deque())
        dq.append((self._seq, now + self._ttl, frame))
        if len(dq) > self._max_per_pair:
            _, _, dropped = dq.popleft()   # oldest of THIS pair only — fairness
            return dropped
        return None

    def drain(self, recipient: str, now: float) -> List[dict]:
        """Remove and return all NON-expired frames for `recipient`, in global arrival
        order across senders. Expired entries are discarded here (purge surfaces them)."""
        collected: List[Tuple[int, dict]] = []
        for (sender, rcpt), dq in self._pairs.items():
            if rcpt != recipient:
                continue
            for seq, expires, frame in dq:
                if expires < now:
                    continue
                collected.append((seq, frame))
            dq.clear()
        self._gc_empty()
        collected.sort(key=lambda x: x[0])
        return [frame for _, frame in collected]

    def purge_expired(self, now: float) -> List[Tuple[str, str, dict]]:
        """Remove expired entries and return [(sender, recipient, frame)] so the asker
        can be told 'expired unanswered'. Run periodically by the server."""
        expired: List[Tuple[str, str, dict]] = []
        for (sender, recipient), dq in self._pairs.items():
            keep: Deque[Tuple[int, float, dict]] = deque()
            for seq, expires, frame in dq:
                if expires < now:
                    expired.append((sender, recipient, frame))
                else:
                    keep.append((seq, expires, frame))
            self._pairs[(sender, recipient)] = keep
        self._gc_empty()
        return expired

    def pending_count(self, recipient: str) -> int:
        return sum(len(dq) for (s, r), dq in self._pairs.items() if r == recipient)

    def _gc_empty(self) -> None:
        for key in [k for k, dq in self._pairs.items() if not dq]:
            del self._pairs[key]
