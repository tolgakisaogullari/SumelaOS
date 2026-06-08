"""Task 1 — E2E crypto core. Security-property tests (fail closed)."""
import os

import pytest
from nacl.exceptions import CryptoError

from relay_common import crypto


def _session(id_a="alice", id_b="onur", sid="s1"):
    """Run the full mutual handshake; return (key_a, key_b, eph_a, eph_b)."""
    a_sk = crypto.generate_identity()
    b_sk = crypto.generate_identity()
    eph_a = crypto.generate_ephemeral()
    eph_b = crypto.generate_ephemeral()

    sig_a = crypto.sign_handshake(a_sk, id_a, id_b, bytes(eph_a.public_key), sid)
    sig_b = crypto.sign_handshake(b_sk, id_b, id_a, bytes(eph_b.public_key), sid)

    # each side verifies the other's bound handshake
    assert crypto.verify_handshake(crypto.identity_public_bytes(a_sk), id_a, id_b,
                                   bytes(eph_a.public_key), sid, sig_a)
    assert crypto.verify_handshake(crypto.identity_public_bytes(b_sk), id_b, id_a,
                                   bytes(eph_b.public_key), sid, sig_b)

    key_a = crypto.derive_session_key(eph_a, eph_b.public_key, sid, id_a, id_b)
    key_b = crypto.derive_session_key(eph_b, eph_a.public_key, sid, id_a, id_b)
    return key_a, key_b, a_sk, b_sk


# ----------------------------------------------------------------- key agreement + AEAD

def test_both_sides_derive_same_key():
    key_a, key_b, _, _ = _session()
    assert key_a == key_b and len(key_a) == 32


def test_roundtrip_encrypt_decrypt():
    key_a, key_b, _, _ = _session()
    msg = crypto.seal(key_a, "how does cancellation work for partial orders?", counter=1)
    counter, body = crypto.open_msg(key_b, msg["nonce"], msg["ciphertext"])
    assert counter == 1 and body.startswith("how does cancellation")


def test_tamper_detected():
    key_a, key_b, _, _ = _session()
    msg = crypto.seal(key_a, "secret", counter=1)
    import base64
    ct = bytearray(base64.b64decode(msg["ciphertext"]))
    ct[-1] ^= 0x01  # flip a bit
    tampered = base64.b64encode(bytes(ct)).decode()
    with pytest.raises(CryptoError):
        crypto.open_msg(key_b, msg["nonce"], tampered)


def test_wrong_recipient_cannot_decrypt():
    key_a, _, _, _ = _session()
    other_key_a, _, _, _ = _session()  # a different session => different key
    msg = crypto.seal(key_a, "secret", counter=1)
    with pytest.raises(CryptoError):
        crypto.open_msg(other_key_a, msg["nonce"], msg["ciphertext"])


# ------------------------------------------------------------------------ forward secrecy

def test_forward_secrecy_session_key_independent_of_identity_keys():
    # derive_session_key takes NO identity key — so leaking the long-term key can't
    # produce the session key. Two sessions with fresh ephemerals must differ.
    key1, _, _, _ = _session()
    key2, _, _, _ = _session()
    assert key1 != key2  # fresh ephemerals => unrelated keys


def test_forward_secrecy_identity_compromise_does_not_reveal_message():
    # Attacker captures ciphertext + both PUBLIC ephemerals + both identity signing keys,
    # but the ephemeral PRIVATES were discarded. They cannot recompute the session key.
    id_a, id_b, sid = "alice", "onur", "s1"
    eph_a = crypto.generate_ephemeral()
    eph_b = crypto.generate_ephemeral()
    key = crypto.derive_session_key(eph_a, eph_b.public_key, sid, id_a, id_b)
    msg = crypto.seal(key, "top secret", counter=1)
    # Attacker forced to use a NEW ephemeral (no access to eph_a/eph_b private) => wrong key.
    attacker_eph = crypto.generate_ephemeral()
    forged = crypto.derive_session_key(attacker_eph, eph_b.public_key, sid, id_a, id_b)
    with pytest.raises(CryptoError):
        crypto.open_msg(forged, msg["nonce"], msg["ciphertext"])


# --------------------------------------------------------------- handshake binding (UKS)

def test_handshake_signature_binds_every_field():
    sk = crypto.generate_identity()
    vk = crypto.identity_public_bytes(sk)
    eph = crypto.generate_ephemeral()
    pub = bytes(eph.public_key)
    sig = crypto.sign_handshake(sk, "alice", "onur", pub, "s1")

    assert crypto.verify_handshake(vk, "alice", "onur", pub, "s1", sig)          # baseline
    assert not crypto.verify_handshake(vk, "mallory", "onur", pub, "s1", sig)    # sender swap
    assert not crypto.verify_handshake(vk, "alice", "yusuf", pub, "s1", sig)     # recipient swap
    assert not crypto.verify_handshake(vk, "alice", "onur", os.urandom(32), "s1", sig)  # eph swap
    assert not crypto.verify_handshake(vk, "alice", "onur", pub, "s2", sig)      # session swap


def test_kci_cannot_forge_peer_without_their_identity_key():
    # Compromising X's signing key must NOT let an attacker impersonate A to X.
    a_sk = crypto.generate_identity()
    x_sk = crypto.generate_identity()  # "compromised"
    eph = crypto.generate_ephemeral()
    pub = bytes(eph.public_key)
    # Attacker signs an "A" handshake with X's key...
    forged = crypto.sign_handshake(x_sk, "alice", "onur", pub, "s1")
    # ...but it does NOT verify against A's real identity key.
    assert not crypto.verify_handshake(crypto.identity_public_bytes(a_sk),
                                       "alice", "onur", pub, "s1", forged)


# ------------------------------------------------------------------- replay across restart

def test_replay_guard_monotonic_and_durable(tmp_path):
    path = str(tmp_path / "hw.json")
    g = crypto.ReplayGuard(path)
    assert g.check_and_update("alice", "s1", 1)
    assert g.check_and_update("alice", "s1", 2)
    assert not g.check_and_update("alice", "s1", 2)  # replay
    assert not g.check_and_update("alice", "s1", 1)  # old
    assert g.check_and_update("alice", "s1", 3)

    # simulate daemon restart: a fresh guard must load the persisted high-water mark
    g2 = crypto.ReplayGuard(path)
    assert not g2.check_and_update("alice", "s1", 3)  # still a replay after restart
    assert g2.check_and_update("alice", "s1", 4)

    # different session_id is an independent counter space
    assert g2.check_and_update("alice", "s2", 1)


# ----------------------------------------------------------------------------- fingerprint

def test_fingerprint_stable_and_distinct():
    sk = crypto.generate_identity()
    vk = crypto.identity_public_bytes(sk)
    fp1 = crypto.fingerprint(vk)
    fp2 = crypto.fingerprint(vk)
    assert fp1 == fp2 and ":" in fp1
    other = crypto.fingerprint(crypto.identity_public_bytes(crypto.generate_identity()))
    assert fp1 != other
