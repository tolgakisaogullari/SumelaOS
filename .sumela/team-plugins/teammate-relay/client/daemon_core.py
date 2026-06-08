"""Task 6 — transport-agnostic daemon core (the testable brain of the client daemon).

Synchronous; returns work to send and performs file-queue side effects. The async WSS loop
(relay_daemon.py) sends each work item and then calls `commit()` — so an outbox entry is
removed ONLY after its frame is confirmed on the wire (no remove-before-send data loss, review
C1/C2). The outbox files ARE the durable send queue: anything not yet sealed-and-sent survives
a daemon restart. Delivery-tracking (`_awaiting`) is persisted too, so the timeout->human
escalation guarantee survives restart (review I3).

Wire payload is a small JSON envelope {kind, body, ref?, mid} so the recipient knows
question-vs-answer and can dedupe by `mid` (idempotent inbox under at-least-once delivery).
Receipts and the replay guard are bound to the session_id (review).
"""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import dataclass
from typing import Dict, List, Optional

from client.session import SessionError, SessionManager
from client.filequeue import FileQueue
from relay_common.untrusted import wrap_untrusted

DELIVERY_TIMEOUT = 120.0   # seconds; matches PROTOCOL.md


@dataclass
class Work:
    frame: dict
    path: Optional[str] = None          # outbox file to remove on confirmed send
    track: Optional[dict] = None        # {peer, session_id, counter, deadline, msg_id}


def _akey(peer: str, session_id: str) -> str:
    return "%s\x1f%s" % (peer, session_id)


class DaemonCore:
    def __init__(self, my_id: str, session_mgr: SessionManager, fq: FileQueue,
                 *, deliver_timeout: float = DELIVERY_TIMEOUT,
                 awaiting_path: Optional[str] = None):
        self._id = my_id
        self._sm = session_mgr
        self._fq = fq
        self._deliver_timeout = deliver_timeout
        self._awaiting_path = awaiting_path
        self._initiated: set = set()                   # peers we've sent a keyx to this run
        self._awaiting: Dict[str, List[dict]] = {}     # (peer,session_id) -> [tracking dicts]
        self._load_awaiting()

    # -- durable delivery-tracking -----------------------------------------------------

    def _load_awaiting(self) -> None:
        if self._awaiting_path and os.path.exists(self._awaiting_path):
            try:
                with open(self._awaiting_path, "r", encoding="utf-8") as fh:
                    self._awaiting = json.load(fh)
            except (ValueError, OSError):
                self._awaiting = {}

    def _persist_awaiting(self) -> None:
        if not self._awaiting_path:
            return
        d = os.path.dirname(self._awaiting_path) or "."
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".aw-", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(self._awaiting, fh)
                fh.flush()
                os.fsync(fh.fileno())
            os.replace(tmp, self._awaiting_path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

    # -- outbox (CLI -> daemon -> wire) ------------------------------------------------

    def process_outbox(self, now: float) -> List[Work]:
        """Build work WITHOUT removing files or advancing tracking — that happens in commit()
        after a confirmed send. Files stay until sealed+sent (durable across restart)."""
        work: List[Work] = []
        for path, entry in self._fq.drain_outbox():
            peer = entry.get("to")
            kind = entry.get("kind")
            if kind == "ask":
                payload = {"kind": "question", "body": entry.get("question", ""),
                           "mid": os.path.basename(path)}
            elif kind == "answer":
                payload = {"kind": "answer", "ref": entry.get("ref_id"),
                           "body": entry.get("text", ""), "mid": os.path.basename(path)}
            else:
                self._fq.remove(path)          # malformed; nothing to send
                continue
            if self._sm.has_session(peer):
                frame = self._sm.seal(peer, json.dumps(payload, separators=(",", ":")))
                sid = self._sm.session_id_for(peer)
                work.append(Work(frame=frame, path=path, track={
                    "peer": peer, "session_id": sid, "counter": frame["counter"],
                    "deadline": now + self._deliver_timeout, "msg_id": frame["id"]}))
            elif peer not in self._initiated:
                self._initiated.add(peer)      # one keyx per peer; leave the file for next poll
                work.append(Work(frame=self._sm.initiate(peer)))
        return work

    def commit(self, work: Work) -> None:
        """Call ONLY after the work's frame was successfully sent."""
        if work.path:
            self._fq.remove(work.path)
        if work.track:
            key = _akey(work.track["peer"], work.track["session_id"])
            self._awaiting.setdefault(key, []).append(
                {k: work.track[k] for k in ("counter", "deadline", "msg_id")})
            self._persist_awaiting()

    # -- incoming (wire -> daemon) -----------------------------------------------------

    def on_incoming(self, frame: dict, now: float) -> List[dict]:
        t = frame.get("type")
        if t == "keyx":
            return self._on_keyx(frame)
        if t == "msg":
            return self._on_msg(frame)
        if t == "receipt":
            self._on_receipt(frame)
            return []
        return []

    def _on_keyx(self, frame: dict) -> List[dict]:
        try:
            resp = self._sm.on_keyx(frame)
        except SessionError:
            return []
        return [resp] if resp is not None else []

    def _on_msg(self, frame: dict) -> List[dict]:
        try:
            counter, plaintext = self._sm.open(frame)   # decrypt + replay-check (authenticated)
        except SessionError:
            return []
        try:
            payload = json.loads(plaintext)
            kind = payload.get("kind", "question")
            body = payload.get("body", "")
            mid = payload.get("mid") or frame["id"]
            ref = payload.get("ref")
        except (ValueError, AttributeError):
            kind, body, mid, ref = "question", plaintext, frame["id"], None
        peer = frame["from"]
        entry = {
            "kind": kind, "id": mid, "from": peer, "ref": ref,
            "untrusted": wrap_untrusted(body, source=peer, direction=kind).as_data_param(),
        }
        self._fq.put_inbox(mid, entry)                   # idempotent by mid (dedupes resends)
        sid = self._sm.session_id_for(peer)
        return [self._sm.make_receipt(peer, sid, frame["id"], counter)]  # authenticated counter

    def _on_receipt(self, frame: dict) -> None:
        peer = frame["from"]
        sid = self._sm.session_id_for(peer)
        if sid is None or not self._sm.verify_receipt(frame, sid):
            return                                       # forged/unscoped/stale — ignore
        key = _akey(peer, sid)
        n = frame["last_counter"]
        before = self._awaiting.get(key, [])
        self._awaiting[key] = [a for a in before if a["counter"] > n]
        if self._awaiting[key] != before:
            self._persist_awaiting()

    # -- delivery-timeout escalation ---------------------------------------------------

    def check_timeouts(self, now: float) -> None:
        changed = False
        for key, items in list(self._awaiting.items()):
            peer = key.split("\x1f", 1)[0]
            still = []
            for a in items:
                if now >= a["deadline"]:
                    changed = True
                    self._fq.put_inbox(
                        "timeout-" + a["msg_id"],
                        {"kind": "delivery-timeout", "id": "timeout-" + a["msg_id"],
                         "from": peer, "untrusted": wrap_untrusted(
                             "No delivery receipt from @%s within %ds — the relay may be down "
                             "or the message was withheld. Decide how to proceed."
                             % (peer, int(self._deliver_timeout)),
                             source="relay-daemon", direction="answer").as_data_param()})
                else:
                    still.append(a)
            self._awaiting[key] = still
        if changed:
            self._persist_awaiting()
