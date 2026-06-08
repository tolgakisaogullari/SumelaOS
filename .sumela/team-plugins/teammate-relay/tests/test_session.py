"""Task 6 — peer-to-peer E2E session manager: handshake, messaging, replay, receipts."""
import base64

import pytest

from relay_common import crypto
from client.session import SessionManager, SessionError


def _mgr(my_id, registry, tmp_path):
    sk = crypto.generate_identity()
    registry[my_id] = crypto.identity_public_bytes(sk)
    return SessionManager(my_id, sk, lambda pid: registry[pid],
                          str(tmp_path / ("replay-%s.json" % my_id)))


def _establish(tmp_path):
    reg = {}
    a = _mgr("alice", reg, tmp_path)
    x = _mgr("onur", reg, tmp_path)
    kx = a.initiate("onur")            # alice -> onur
    resp = x.on_keyx(kx)               # onur responds
    assert resp is not None
    assert a.on_keyx(resp) is None     # alice completes
    return a, x


def test_handshake_and_message_roundtrip(tmp_path):
    a, x = _establish(tmp_path)
    assert a.has_session("onur") and x.has_session("alice")
    m = a.seal("onur", "how does partial cancellation work?")
    assert x.open(m) == (1, "how does partial cancellation work?")
    m2 = x.seal("alice", "it splits the order")     # reverse direction
    assert a.open(m2)[1] == "it splits the order"


def test_replay_rejected(tmp_path):
    a, x = _establish(tmp_path)
    m = a.seal("onur", "q1")
    assert x.open(m)[1] == "q1"
    with pytest.raises(SessionError):
        x.open(m)                       # same authenticated counter -> replay


def test_monotonic_counters_accepted(tmp_path):
    a, x = _establish(tmp_path)
    for i in range(3):
        assert x.open(a.seal("onur", "m%d" % i))[1] == "m%d" % i


def test_session_id_mismatch_rejected(tmp_path):
    a, x = _establish(tmp_path)
    m = a.seal("onur", "q")
    m["session_id"] = "someone-elses-session"        # flip the unauthenticated wire field
    with pytest.raises(SessionError):
        x.open(m)


def test_handshake_bad_signature_rejected(tmp_path):
    reg = {}
    a = _mgr("alice", reg, tmp_path)
    x = _mgr("onur", reg, tmp_path)
    kx = a.initiate("onur")
    kx["sig"] = base64.b64encode(b"\x00" * 64).decode()   # forged signature
    with pytest.raises(SessionError):
        x.on_keyx(kx)


def test_tampered_ciphertext_rejected(tmp_path):
    a, x = _establish(tmp_path)
    m = a.seal("onur", "secret")
    raw = bytearray(base64.b64decode(m["ciphertext"]))
    raw[-1] ^= 0x01
    m["ciphertext"] = base64.b64encode(bytes(raw)).decode()
    with pytest.raises(SessionError):
        x.open(m)


def test_seal_without_session_raises(tmp_path):
    reg = {}
    a = _mgr("alice", reg, tmp_path)
    with pytest.raises(SessionError):
        a.seal("stranger", "hi")


def test_receipt_make_and_verify(tmp_path):
    a, x = _establish(tmp_path)
    sid = a.session_id_for("onur")
    assert sid == x.session_id_for("alice")
    r = x.make_receipt("alice", sid, "m1", last_counter=5)
    assert a.verify_receipt(r, sid) is True
    r["last_counter"] = 99               # tamper -> signature no longer matches
    assert a.verify_receipt(r, sid) is False
    # a receipt bound to a DIFFERENT session_id must not verify (no cross-session replay)
    r2 = x.make_receipt("alice", sid, "m1", last_counter=5)
    assert a.verify_receipt(r2, "different-session") is False
