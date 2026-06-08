"""Task 4 — blind WSS router: routing, spoof guard, limits, revocation, receipts."""
import json

from relay_common import crypto
from server.auth import RelayAuth
from server.presence import PresenceRegistry
from server.queue import FairOfflineQueue
from server.relay_server import RelayRouter, ConnState


def _session(auth, member):
    sk = crypto.generate_identity()
    return auth.enroll(member, crypto.identity_public_bytes(sk), auth.mint_enrollment_token(member))


def _raw(frame):
    return json.dumps(frame).encode("utf-8")


def _auth_frame(member, token):
    return {"v": 1, "type": "auth", "id": "auth-%s" % member,
            "client_id": member, "session_token": token}


def _msg(sender, recipient, mid="m1", ct="Y2lwaGVy", counter=1):
    return {"v": 1, "type": "msg", "id": mid, "from": sender, "to": recipient,
            "session_id": "s1", "ciphertext": ct, "counter": counter}


def _setup():
    auth = RelayAuth()
    presence = PresenceRegistry()
    queue = FairOfflineQueue()
    router = RelayRouter(auth, presence, queue)
    return auth, presence, queue, router


def _connect(router, auth, member, now=0.0):
    conn = ConnState()
    out = router.handle_raw(conn, _raw(_auth_frame(member, _session(auth, member))), now)
    assert any(o.frame["type"] == "ack" for o in out)
    # serve() is what registers the live socket in presence; simulate that here so
    # routing-decision tests see the member as online.
    router._presence.connect(member, conn)
    return conn


# ----------------------------------------------------------------------------- auth gate

def test_auth_frame_authenticates():
    auth, presence, _, router = _setup()
    conn = _connect(router, auth, "onur")
    assert conn.client_id == "onur" and presence.is_online("onur")


def test_unauthenticated_msg_rejected():
    _, _, _, router = _setup()
    conn = ConnState()
    out = router.handle_raw(conn, _raw(_msg("alice", "onur")), 1.0)
    assert out[0].frame["type"] == "error" and out[0].frame["code"] == 401


def test_bad_frame_rejected():
    _, _, _, router = _setup()
    out = router.handle_raw(ConnState(), b"{garbage", 1.0)
    assert out[0].frame["type"] == "error" and out[0].frame["code"] == 400


# ------------------------------------------------------------------- routing (blind/verbatim)

def test_msg_to_online_recipient_routed_verbatim():
    auth, _, _, router = _setup()
    conn_a = _connect(router, auth, "alice")
    _connect(router, auth, "onur")
    frame = _msg("alice", "onur", ct="OPAQUE-CIPHERTEXT==")
    out = router.handle_raw(conn_a, _raw(frame), 1.0)
    assert len(out) == 1
    assert out[0].to == "onur"
    # blind server: ciphertext relayed byte-identical, never decrypted/altered
    assert out[0].frame["ciphertext"] == "OPAQUE-CIPHERTEXT=="
    assert out[0].frame == frame


def test_recipient_scoped_only():
    auth, _, _, router = _setup()
    conn_a = _connect(router, auth, "alice")
    _connect(router, auth, "onur")
    _connect(router, auth, "bob")
    out = router.handle_raw(conn_a, _raw(_msg("alice", "onur")), 1.0)
    assert [o.to for o in out] == ["onur"]   # bob does not receive it


def test_spoof_sending_as_another_identity_rejected():
    auth, _, _, router = _setup()
    conn_a = _connect(router, auth, "alice")
    out = router.handle_raw(conn_a, _raw(_msg("onur", "bob")), 1.0)  # alice claims from=onur
    assert out[0].frame["type"] == "error" and out[0].frame["code"] == 403


# ----------------------------------------------------------------------- offline queue path

def test_offline_recipient_queued_then_delivered_on_connect():
    auth, _, queue, router = _setup()
    conn_a = _connect(router, auth, "alice")
    out = router.handle_raw(conn_a, _raw(_msg("alice", "onur", mid="q1")), 1.0)
    assert out[0].frame["type"] == "ack"          # accepted (not a delivery guarantee)
    assert queue.pending_count("onur") == 1
    # onur comes online -> queued frame drains to him in the auth response
    conn_o = ConnState()
    out2 = router.handle_raw(conn_o, _raw(_auth_frame("onur", _session(auth, "onur"))), 2.0)
    delivered = [o for o in out2 if o.frame.get("id") == "q1"]
    assert delivered and delivered[0].to == "onur"


# --------------------------------------------------------------------- limits + revocation

def test_rate_limit_trips_after_threshold():
    auth, _, _, router = _setup()
    conn_a = _connect(router, auth, "alice")
    _connect(router, auth, "onur")
    last = None
    for i in range(11):                       # spaced 3s apart: within 60s window, no burst
        last = router.handle_raw(conn_a, _raw(_msg("alice", "onur", mid="m%d" % i)), 3.0 * i)
    assert last[0].frame["type"] == "error" and last[0].frame["code"] == 429


def test_burst_loop_guard_trips():
    auth, _, _, router = _setup()
    conn_a = _connect(router, auth, "alice")
    _connect(router, auth, "onur")
    out = None
    for i in range(5):                        # 5 frames at the same instant -> burst > 4
        out = router.handle_raw(conn_a, _raw(_msg("alice", "onur", mid="b%d" % i)), 10.0)
    assert out[0].frame["type"] == "error" and out[0].frame["code"] == 429


def test_per_message_revocation():
    auth, _, _, router = _setup()
    conn_a = _connect(router, auth, "alice")
    _connect(router, auth, "onur")
    assert router.handle_raw(conn_a, _raw(_msg("alice", "onur", mid="ok")), 1.0)[0].to == "onur"
    auth.revoke_member("alice")
    out = router.handle_raw(conn_a, _raw(_msg("alice", "onur", mid="no")), 2.0)
    assert out[0].frame["type"] == "error" and out[0].frame["code"] == 403


# ---------------------------------------------------------------------------- receipts

def test_enroll_over_the_wire_returns_session_token():
    import base64
    auth, _, _, router = _setup()
    pub = crypto.identity_public_bytes(crypto.generate_identity())
    tok = auth.mint_enrollment_token("dana")
    frame = {"v": 1, "type": "enroll", "id": "e1", "client_id": "dana",
             "identity_pub": base64.b64encode(pub).decode(), "enroll_token": tok}
    out = router.handle_raw(ConnState(), _raw(frame), 1.0)
    assert out[0].frame["type"] == "session"
    assert auth.verify_session(out[0].frame["session_token"], expected_member="dana")["sub"] == "dana"


def test_enroll_with_bad_token_rejected():
    import base64
    auth, _, _, router = _setup()
    pub = crypto.identity_public_bytes(crypto.generate_identity())
    frame = {"v": 1, "type": "enroll", "id": "e1", "client_id": "dana",
             "identity_pub": base64.b64encode(pub).decode(), "enroll_token": "bogus"}
    out = router.handle_raw(ConnState(), _raw(frame), 1.0)
    assert out[0].frame["type"] == "error" and out[0].frame["code"] == 401


def test_rate_window_keys_are_gc_d():
    # Review fix: idle rate-window keys must be reclaimed, not grow unbounded.
    _, _, _, router = _setup()
    router._rate_ok("ghost", 0.0)
    assert "ghost" in router._id_events
    router.sweep_rate_windows(1000.0)        # well past RATE_WINDOW
    assert "ghost" not in router._id_events


def test_rate_key_map_is_hard_capped_fail_closed():
    # Review fix: when the distinct-identity cap is hit within one window (sweep reclaims
    # nothing because all keys are fresh), new identities are REJECTED, not admitted.
    auth = RelayAuth()
    router = RelayRouter(auth, PresenceRegistry(), FairOfflineQueue(), max_rate_keys=3)
    now = 1.0
    assert router._rate_ok("a", now)
    assert router._rate_ok("b", now)
    assert router._rate_ok("c", now)         # map now full, all fresh
    assert router._rate_ok("d", now) is False  # 4th distinct identity rejected (fail closed)
    assert "d" not in router._id_events


def test_receipt_relayed_back_to_sender():
    auth, _, _, router = _setup()
    _connect(router, auth, "alice")
    conn_o = _connect(router, auth, "onur")
    receipt = {"v": 1, "type": "receipt", "id": "r1", "ref_id": "m1",
               "from": "onur", "to": "alice", "last_counter": 5, "sig": "b64sig"}
    out = router.handle_raw(conn_o, _raw(receipt), 1.0)
    assert out[0].to == "alice" and out[0].frame["type"] == "receipt"
