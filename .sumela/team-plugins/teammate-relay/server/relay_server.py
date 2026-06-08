"""Task 4 (+ Phase-1 review hardening) — blind WSS relay router.

The router wires auth + presence + queue + schema and enforces transport policy. It is
BLIND: it reads only routing metadata (`from`, `to`, `id`, `type`, `client_id`) and relays
the opaque `ciphertext` verbatim — there is no decryption path anywhere in this module.

Security/correctness properties (test-backed):
  * authed `msg` to an online recipient is routed VERBATIM (ciphertext byte-identical);
  * a client cannot send `from` another id (spoof guard) — bound to the authed session;
  * recipient-scoped delivery only;
  * per-IDENTITY sliding-window rate limit + per-conn burst loop-guard (reconnect can't
    reset the identity window — review fix);
  * per-message revocation (a revoked member is rejected on the very next frame);
  * `enroll` is reachable over the wire and returns a `session` token (review fix);
  * recipient-signed `receipt` frames are relayed back to the original sender;
  * the serve loop registers the live WebSocket in presence, closes a DISPLACED socket,
    isolates per-frame errors, and runs a periodic TTL purge (review fixes).

`handle_raw()` is synchronous and returns `Outbound` directives; the thin async `serve()`
loop owns the websocket<->client_id mapping and applies them.
"""

from __future__ import annotations

import uuid
from collections import deque
from dataclasses import dataclass, field
from typing import Deque, Dict, List, Optional

from relay_common import schema
from relay_common.schema import SchemaError
from server.auth import AuthError

# Policy defaults (PROTOCOL.md / spec §Security).
RATE_LIMIT_PER_MIN = 10
RATE_WINDOW = 60.0
BURST_LIMIT = 4          # loop-guard: at most N frames within BURST_WINDOW
BURST_WINDOW = 2.0
PURGE_INTERVAL = 300.0   # seconds between offline-queue TTL sweeps
MAX_RATE_KEYS = 10000    # soft cap on distinct rate-window keys (anti unbounded-growth)


@dataclass
class ConnState:
    """Per-connection state the serve loop keeps; passed back into handle_raw()."""
    client_id: Optional[str] = None
    burst: Deque[float] = field(default_factory=deque)   # per-conn burst backstop


@dataclass
class Outbound:
    """A directive from the router. `to=None` => reply on the current connection;
    otherwise route to that client_id if online."""
    to: Optional[str]
    frame: dict


def _frame(ftype: str, **fields) -> dict:
    return {"v": schema.PROTOCOL_VERSION, "type": ftype, "id": str(uuid.uuid4()), **fields}


def _error(code: int, message: str, ref_id: Optional[str] = None) -> dict:
    f = _frame("error", code=code, message=message)
    if ref_id is not None:
        f["ref_id"] = ref_id
    return f


class RelayRouter:
    def __init__(self, auth, presence, queue, *, max_rate_keys: int = MAX_RATE_KEYS):
        self._auth = auth
        self._presence = presence
        self._queue = queue
        self._max_rate_keys = max_rate_keys
        # identity-keyed rate window (survives reconnects — review fix).
        self._id_events: Dict[str, Deque[float]] = {}

    # -- rate / burst limiting ---------------------------------------------------------

    def _burst_ok(self, conn: ConnState, now: float) -> bool:
        b = conn.burst
        b.append(now)
        while b and b[0] < now - BURST_WINDOW:
            b.popleft()
        return len(b) <= BURST_LIMIT

    def _rate_ok(self, identity: str, now: float) -> bool:
        ev = self._id_events.get(identity)
        if ev is None:
            # HARD-bound the map: attacker-chosen pre-auth keys (enroll:/auth:<id>) cannot
            # grow it without limit. Sweep aged keys first; if still at the cap, FAIL CLOSED
            # (reject the new identity) rather than admit it unconditionally (review fix).
            if len(self._id_events) >= self._max_rate_keys:
                self.sweep_rate_windows(now)
                if len(self._id_events) >= self._max_rate_keys:
                    return False
            ev = self._id_events.setdefault(identity, deque())
        ev.append(now)
        while ev and ev[0] < now - RATE_WINDOW:
            ev.popleft()
        return len(ev) <= RATE_LIMIT_PER_MIN

    def sweep_rate_windows(self, now: float) -> None:
        """Prune aged-out rate windows and DROP keys whose deque emptied (GC, review #2).
        Called periodically by the serve loop and opportunistically at the soft cap."""
        for k in list(self._id_events.keys()):
            ev = self._id_events[k]
            while ev and ev[0] < now - RATE_WINDOW:
                ev.popleft()
            if not ev:
                del self._id_events[k]

    # -- main dispatch -----------------------------------------------------------------

    def handle_raw(self, conn: ConnState, raw, now: float) -> List[Outbound]:
        try:
            frame = schema.validate_raw(raw)
        except SchemaError as exc:
            return [Outbound(None, _error(400, "bad frame: %s" % exc))]

        ftype = frame["type"]

        # per-conn burst backstop applies to EVERY frame (incl. pre-auth flooding).
        if not self._burst_ok(conn, now):
            return [Outbound(None, _error(429, "burst limit exceeded", frame["id"]))]

        if ftype == "enroll":
            return self._handle_enroll(conn, frame, now)
        if ftype == "auth":
            return self._handle_auth(conn, frame, now)

        if conn.client_id is None:
            return [Outbound(None, _error(401, "not authenticated", frame["id"]))]

        # per-message revocation (I-2): a revoked member is cut off on the next frame.
        if self._auth.is_revoked(conn.client_id):
            return [Outbound(None, _error(403, "member revoked"))]

        # per-identity rate limit (survives reconnects).
        if not self._rate_ok(conn.client_id, now):
            return [Outbound(None, _error(429, "rate limit exceeded", frame["id"]))]

        if ftype in ("msg", "receipt", "keyx"):
            return self._handle_relayed(conn, frame, now)
        if ftype == "ack":
            return self._route_or_drop(frame, now)

        return [Outbound(None, _error(400, "unexpected frame type %r" % ftype, frame["id"]))]

    def _handle_enroll(self, conn: ConnState, frame: dict, now: float) -> List[Outbound]:
        # rate-limit enrollment attempts per claimed member (anti auth-flood).
        if not self._rate_ok("enroll:" + frame["client_id"], now):
            return [Outbound(None, _error(429, "enrollment rate exceeded", frame["id"]))]
        try:
            import base64
            pub = base64.b64decode(frame["identity_pub"])
            token = self._auth.enroll(frame["client_id"], pub, frame["enroll_token"])
        except (AuthError, ValueError) as exc:
            return [Outbound(None, _error(401, "enroll failed: %s" % exc, frame["id"]))]
        return [Outbound(None, _frame("session", ref_id=frame["id"], session_token=token))]

    def _handle_auth(self, conn: ConnState, frame: dict, now: float) -> List[Outbound]:
        client_id = frame["client_id"]
        if not self._rate_ok("auth:" + client_id, now):
            return [Outbound(None, _error(429, "auth rate exceeded", frame["id"]))]
        if conn.client_id is not None and conn.client_id != client_id:
            return [Outbound(None, _error(403, "connection already authenticated", frame["id"]))]
        try:
            self._auth.verify_session(frame["session_token"], expected_member=client_id)
        except Exception as exc:
            return [Outbound(None, _error(401, "auth failed: %s" % exc, frame["id"]))]
        conn.client_id = client_id   # serve() registers the ws in presence after this returns
        out = [Outbound(None, _frame("ack", ref_id=frame["id"]))]
        for queued in self._queue.drain(client_id, now):
            out.append(Outbound(client_id, queued))
        return out

    def _handle_relayed(self, conn: ConnState, frame: dict, now: float) -> List[Outbound]:
        if frame.get("from") != conn.client_id:
            return [Outbound(None, _error(403, "cannot send as another identity", frame["id"]))]
        return self._route_or_queue(frame, now)

    def _route_or_queue(self, frame: dict, now: float) -> List[Outbound]:
        to = frame["to"]
        if self._presence.is_online(to):
            return [Outbound(to, frame)]                     # VERBATIM — ciphertext untouched
        self._queue.enqueue(frame["from"], to, frame, now)
        return [Outbound(None, _frame("ack", ref_id=frame["id"]))]

    def _route_or_drop(self, frame: dict, now: float) -> List[Outbound]:
        to = frame.get("to")
        if to and self._presence.is_online(to):
            return [Outbound(to, frame)]
        return []

    def purge(self, now: float) -> List[Outbound]:
        """Sweep expired offline items; best-effort notify any ONLINE sender (the asker's
        client-side delivery-timeout is the real escalation; see PROTOCOL.md)."""
        out: List[Outbound] = []
        for sender, recipient, frame in self._queue.purge_expired(now):
            if self._presence.is_online(sender):
                out.append(Outbound(sender, _error(410, "queued message expired unanswered",
                                                    frame.get("id"))))
        return out


# --------------------------------------------------------------------------- serve loop

async def serve(host: str, port: int, router: "RelayRouter", *, ssl_context):
    """Thin asyncio/websockets glue. WSS only — `ssl_context` is REQUIRED (no plaintext).

    Owns the websocket<->client_id mapping (presence stores live WebSockets, NOT ConnState),
    closes displaced sockets, isolates per-frame errors, and runs a periodic TTL purge.
    Imported lazily so unit tests don't need `websockets`. Exercised in tests via a fake ws.
    """
    if ssl_context is None:
        raise ValueError("WSS only: an SSL context is required (no plaintext ws://)")
    import asyncio
    import time

    import websockets

    stop = asyncio.get_event_loop().create_future()

    async def purge_loop():
        while True:
            await asyncio.sleep(PURGE_INTERVAL)
            now = time.time()
            router.sweep_rate_windows(now)          # GC idle rate-window keys
            for out in router.purge(now):
                ws = router._presence.get(out.to)
                if ws is not None:
                    await _safe_send(ws, out.frame)

    purger = asyncio.create_task(purge_loop())
    try:
        async with websockets.serve(lambda ws: _handle_conn(ws, router), host, port, ssl=ssl_context):
            await stop
    finally:
        purger.cancel()


async def _safe_send(ws, frame: dict) -> None:
    import json
    try:
        await ws.send(json.dumps(frame))
    except Exception:
        pass  # a dead/slow peer must never tear down an unrelated sender's loop


async def _handle_conn(ws, router: "RelayRouter") -> None:
    import asyncio
    import time

    conn = ConnState()
    try:
        async for raw in ws:
            before = conn.client_id
            try:
                outs = router.handle_raw(conn, raw, time.time())
            except Exception:
                outs = []  # never let a router bug kill the connection silently-crash the loop
            if conn.client_id and before is None:           # just authenticated
                displaced = router._presence.connect(conn.client_id, ws)
                if displaced is not None and displaced is not ws:
                    asyncio.create_task(_safe_close(displaced))
            for out in outs:
                target = ws if out.to is None else router._presence.get(out.to)
                if target is not None:
                    await _safe_send(target, out.frame)
    finally:
        if conn.client_id:
            router._presence.disconnect(conn.client_id, ws)


async def _safe_close(ws) -> None:
    try:
        await ws.close()
    except Exception:
        pass
