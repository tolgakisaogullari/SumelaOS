"""Phase-1 review fix — exercise the real `serve()` glue (`_handle_conn`) with a fake
WebSocket, since the synchronous router unit tests never run it. Covers: presence
registration via the loop, verbatim delivery to an online recipient, send-failure
isolation, displaced-socket close, and enroll-over-the-wire.
"""
import asyncio
import base64
import json

from relay_common import crypto
from server.auth import RelayAuth
from server.presence import PresenceRegistry
from server.queue import FairOfflineQueue
from server.relay_server import RelayRouter, _handle_conn


class FakeWS:
    def __init__(self, incoming=()):
        self._incoming = list(incoming)
        self.sent = []
        self.closed = False
        self.fail_send = False

    def __aiter__(self):
        self._i = 0
        return self

    async def __anext__(self):
        if self._i >= len(self._incoming):
            raise StopAsyncIteration
        v = self._incoming[self._i]
        self._i += 1
        return v

    async def send(self, data):
        if self.fail_send:
            raise RuntimeError("peer dead")
        self.sent.append(data)

    async def close(self):
        self.closed = True


def _setup():
    auth = RelayAuth()
    presence = PresenceRegistry()
    router = RelayRouter(auth, presence, FairOfflineQueue())
    return auth, presence, router


def _raw(frame):
    return json.dumps(frame).encode("utf-8")


def _token(auth, member):
    sk = crypto.generate_identity()
    return auth.enroll(member, crypto.identity_public_bytes(sk), auth.mint_enrollment_token(member))


def _auth_frame(member, token):
    return {"v": 1, "type": "auth", "id": "a", "client_id": member, "session_token": token}


def _msg(sender, recipient, ct):
    return {"v": 1, "type": "msg", "id": "m1", "from": sender, "to": recipient,
            "session_id": "s1", "ciphertext": ct, "counter": 1}


async def _run_and_drain(coro):
    await coro
    await asyncio.sleep(0)  # let fire-and-forget tasks (displaced close) start
    pending = [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]
    if pending:
        await asyncio.gather(*pending, return_exceptions=True)


def test_serve_routes_verbatim_to_online_recipient():
    auth, presence, router = _setup()
    recipient = FakeWS()
    presence.connect("onur", recipient)                 # recipient already online
    sender = FakeWS([_raw(_auth_frame("alice", _token(auth, "alice"))),
                     _raw(_msg("alice", "onur", "OPAQUE-CT=="))])
    asyncio.run(_handle_conn(sender, router))
    got = [json.loads(s) for s in recipient.sent]
    assert any(g["type"] == "msg" and g["ciphertext"] == "OPAQUE-CT==" for g in got)
    assert not presence.is_online("alice")              # cleaned up on disconnect


def test_serve_isolates_send_failure_to_dead_recipient():
    auth, presence, router = _setup()
    dead = FakeWS()
    dead.fail_send = True
    presence.connect("onur", dead)
    sender = FakeWS([_raw(_auth_frame("alice", _token(auth, "alice"))),
                     _raw(_msg("alice", "onur", "CT=="))])
    asyncio.run(_handle_conn(sender, router))            # must NOT raise
    assert not presence.is_online("alice")               # sender still cleaned up


def test_serve_closes_displaced_socket():
    auth, presence, router = _setup()
    old = FakeWS()
    presence.connect("onur", old)                        # an old socket for onur
    new = FakeWS([_raw(_auth_frame("onur", _token(auth, "onur")))])
    asyncio.run(_run_and_drain(_handle_conn(new, router)))
    assert old.closed is True                            # displaced socket was closed


def test_serve_enroll_returns_session_on_same_ws():
    auth, _, router = _setup()
    pub = crypto.identity_public_bytes(crypto.generate_identity())
    tok = auth.mint_enrollment_token("dana")
    ws = FakeWS([_raw({"v": 1, "type": "enroll", "id": "e1", "client_id": "dana",
                       "identity_pub": base64.b64encode(pub).decode(), "enroll_token": tok})])
    asyncio.run(_handle_conn(ws, router))
    assert any(json.loads(s)["type"] == "session" for s in ws.sent)
