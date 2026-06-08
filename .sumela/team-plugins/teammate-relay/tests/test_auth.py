"""Task 2 — connection auth. Enrollment binding, alg-pinning, revocation, rotation."""
import base64

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from relay_common import crypto
from server.auth import RelayAuth, AuthError


def _identity():
    sk = crypto.generate_identity()
    return sk, crypto.identity_public_bytes(sk)


def test_enroll_then_verify_session():
    auth = RelayAuth()
    _, pub = _identity()
    tok = auth.mint_enrollment_token("onur")
    session = auth.enroll("onur", pub, tok)
    claims = auth.verify_session(session, expected_member="onur")
    assert claims["sub"] == "onur" and "thumb" in claims


def test_wrong_enrollment_token_rejected():
    auth = RelayAuth()
    _, pub = _identity()
    with pytest.raises(AuthError):
        auth.enroll("onur", pub, "not-a-real-token")


def test_enrollment_token_expired(monkeypatch):
    t = [1000.0]
    auth = RelayAuth(now=lambda: t[0])
    _, pub = _identity()
    tok = auth.mint_enrollment_token("onur", ttl=10)
    t[0] = 2000.0  # well past expiry
    with pytest.raises(AuthError):
        auth.enroll("onur", pub, tok)


def test_enrollment_token_bound_per_member_cannot_rebind_different_key():
    # I8: a member's enrollment binds to ONE identity; a second, different key is rejected.
    auth = RelayAuth()
    _, pub1 = _identity()
    _, pub2 = _identity()
    tok1 = auth.mint_enrollment_token("onur")
    auth.enroll("onur", pub1, tok1)
    tok2 = auth.mint_enrollment_token("onur")
    with pytest.raises(AuthError):
        auth.enroll("onur", pub2, tok2)


def test_alg_none_token_rejected():
    # Hand-craft an alg:none token for the right subject; must be rejected (C5).
    auth = RelayAuth()
    _, pub = _identity()
    auth.enroll("onur", pub, auth.mint_enrollment_token("onur"))
    header = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').rstrip(b"=")
    payload = base64.urlsafe_b64encode(b'{"sub":"onur","thumb":"x"}').rstrip(b"=")
    forged = (header + b"." + payload + b".").decode()
    with pytest.raises(AuthError):
        auth.verify_session(forged)


def test_hs256_confusion_token_rejected():
    # Alg-confusion: a valid HS256 token (any secret) must be rejected because decode
    # PINS algorithms=["EdDSA"] — the attacker's chosen alg is never honored (C5).
    auth = RelayAuth()
    _, pub = _identity()
    auth.enroll("onur", pub, auth.mint_enrollment_token("onur"))
    forged = jwt.encode({"sub": "onur", "thumb": "x"}, "attacker-secret", algorithm="HS256")
    with pytest.raises(AuthError):
        auth.verify_session(forged)


def test_revoked_member_rejected_immediately():
    auth = RelayAuth()
    _, pub = _identity()
    session = auth.enroll("onur", pub, auth.mint_enrollment_token("onur"))
    assert auth.verify_session(session)  # ok before
    auth.revoke_member("onur")
    with pytest.raises(AuthError):           # rejected on the very next call (per-message)
        auth.verify_session(session)


def test_identity_rotation_invalidates_outstanding_token():
    auth = RelayAuth()
    _, pub = _identity()
    session = auth.enroll("onur", pub, auth.mint_enrollment_token("onur"))
    _, new_pub = _identity()
    auth.rotate_identity("onur", new_pub)    # thumbprint changes
    with pytest.raises(AuthError):
        auth.verify_session(session)


def test_expired_session_token_rejected():
    # Issue an already-expired token (negative ttl) — PyJWT enforces exp vs wall clock.
    auth = RelayAuth(session_ttl=-10)
    _, pub = _identity()
    session = auth.enroll("onur", pub, auth.mint_enrollment_token("onur"))
    with pytest.raises(AuthError):
        auth.verify_session(session)


def test_subject_mismatch_rejected():
    auth = RelayAuth()
    _, pub = _identity()
    session = auth.enroll("onur", pub, auth.mint_enrollment_token("onur"))
    with pytest.raises(AuthError):
        auth.verify_session(session, expected_member="alice")


def test_refresh_issues_new_valid_token():
    auth = RelayAuth()
    _, pub = _identity()
    session = auth.enroll("onur", pub, auth.mint_enrollment_token("onur"))
    refreshed = auth.refresh(session)
    assert auth.verify_session(refreshed)["sub"] == "onur"


def test_revocation_survives_concurrent_mint(tmp_path):
    # Review fix: a concurrent mint in another process must NOT clobber (un-revoke) a member.
    X = str(tmp_path / "auth-state.json")
    sk = Ed25519PrivateKey.generate()
    serve = RelayAuth(sk, state_path=X)
    cli = RelayAuth(sk, state_path=X)
    _, pub = _identity()
    session = serve.enroll("alice", pub, serve.mint_enrollment_token("alice"))
    cli.revoke_member("alice")              # operator revokes (writes the shared file)
    serve.mint_enrollment_token("bob")      # serve's unrelated write reloads-under-lock first
    reader = RelayAuth(sk, state_path=X)    # a fresh process sees the final state
    with pytest.raises(AuthError):
        reader.verify_session(session)      # alice is still revoked


def test_server_verify_key_is_pinnable_pem():
    auth = RelayAuth()
    pem = auth.server_verify_key_pem()
    assert pem.startswith(b"-----BEGIN PUBLIC KEY-----")
