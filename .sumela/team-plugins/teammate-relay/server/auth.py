"""Task 2 — connection auth: per-member enrollment + pinned-EdDSA session tokens.

Security properties (test-backed):

  * **Per-member enrollment token** (I8): the operator mints one short token per teammate.
    On first connect it BINDS to that member's identity public-key thumbprint; a leaked token
    is contained to one member and revocable per-member. Tokens carry a TTL.
  * **Session token = EdDSA JWT** signed by the server key, **alg pinned** (`algorithms=["EdDSA"]`
    on every decode → `alg:none`/HS confusion rejected, C5). The server's verify key is exported
    for the client to PIN (committed in relay-config.md).
  * **Thumbprint binding** (I-3): the token carries the member's identity thumbprint; rotating the
    identity invalidates outstanding tokens.
  * **Revocation on connect AND per-message** (I-2): `verify_session()` consults the revocation set
    on every call (it is invoked both at connect and per relayed frame); a revoked member's still-
    valid cached token is rejected immediately, and live sessions can be force-dropped by the router.

A `now` callable is injectable for deterministic tests (enrollment-TTL logic). JWT `exp` is enforced
by PyJWT against real wall-clock, so expiry tests issue an already-expired token.
"""

from __future__ import annotations

import contextlib
import json
import os
import secrets
import tempfile
import time
from typing import Callable, Dict, Optional

try:  # POSIX file locking for cross-process mutual exclusion on the shared state file.
    import fcntl as _fcntl
except Exception:  # pragma: no cover - non-POSIX
    _fcntl = None

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)

from relay_common.crypto import fingerprint

DEFAULT_SESSION_TTL = 3600        # 1h
DEFAULT_ENROLL_TTL = 86400        # 24h


class AuthError(Exception):
    """Any authentication/enrollment failure. Fail closed."""


class RelayAuth:
    def __init__(
        self,
        server_signing_key: Optional[Ed25519PrivateKey] = None,
        *,
        now: Callable[[], float] = time.time,
        session_ttl: int = DEFAULT_SESSION_TTL,
        state_path: Optional[str] = None,
    ):
        self._sk = server_signing_key or Ed25519PrivateKey.generate()
        self._pk = self._sk.public_key()
        self._now = now
        self._session_ttl = session_ttl
        self._state_path = state_path
        self._enrollments: Dict[str, dict] = {}   # token -> {member_id, expires, bound}
        self._bindings: Dict[str, str] = {}        # member_id -> identity thumbprint
        self._revoked_members: set = set()
        self._revoked_jti: set = set()
        self._load_state()

    # ---- shared/durable state (so the operator CLI and the serve process agree) -------

    def _load_state(self) -> None:
        self._state_mtime = None
        if not self._state_path or not os.path.exists(self._state_path):
            return
        try:
            self._state_mtime = os.path.getmtime(self._state_path)
            with open(self._state_path, "r", encoding="utf-8") as fh:
                s = json.load(fh)
        except (ValueError, OSError):
            return
        self._enrollments = s.get("enrollments", {})
        self._bindings = s.get("bindings", {})
        self._revoked_members = set(s.get("revoked_members", []))
        self._revoked_jti = set(s.get("revoked_jti", []))

    @contextlib.contextmanager
    def _locked(self):
        """Exclusive cross-process lock around a load-mutate-persist of the shared state,
        so a concurrent writer (e.g. the mint CLI) can never clobber a revocation (review #1).
        No-op when there is no state file or no fcntl (in-memory / non-POSIX)."""
        if not self._state_path or _fcntl is None:
            yield
            return
        lock = open(self._state_path + ".lock", "w")
        try:
            _fcntl.flock(lock, _fcntl.LOCK_EX)
            self._load_state()      # re-read the latest committed state UNDER the lock
            yield
        finally:
            try:
                _fcntl.flock(lock, _fcntl.LOCK_UN)
            finally:
                lock.close()

    def _maybe_reload(self) -> None:
        """Re-read shared state if another process (e.g. the mint/revoke CLI) changed it,
        so a freshly-minted enrollment is redeemable and a revocation takes effect live."""
        if not self._state_path:
            return
        try:
            mtime = os.path.getmtime(self._state_path)
        except OSError:
            return
        if mtime != getattr(self, "_state_mtime", None):
            self._load_state()

    def _persist(self) -> None:
        if not self._state_path:
            return
        s = {
            "enrollments": self._enrollments,
            "bindings": self._bindings,
            "revoked_members": sorted(self._revoked_members),
            "revoked_jti": sorted(self._revoked_jti),
        }
        d = os.path.dirname(self._state_path) or "."
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".auth-", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(s, fh)
                fh.flush()
                os.fsync(fh.fileno())
            os.replace(tmp, self._state_path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

    # ---- key pinning -----------------------------------------------------------------

    def server_verify_key_pem(self) -> bytes:
        """The server's Ed25519 public key (PEM) — clients PIN this in relay-config.md."""
        return self._pk.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )

    # ---- enrollment ------------------------------------------------------------------

    def mint_enrollment_token(self, member_id: str, ttl: int = DEFAULT_ENROLL_TTL) -> str:
        token = secrets.token_urlsafe(32)
        with self._locked():       # load+mutate+persist atomically (no lost update)
            self._enrollments[token] = {
                "member_id": member_id,
                "expires": self._now() + ttl,
                "bound": None,
            }
            self._persist()
        return token

    def enroll(self, member_id: str, identity_pub_bytes: bytes, enroll_token: str) -> str:
        thumb = fingerprint(identity_pub_bytes)
        with self._locked():       # _locked re-reads the latest state under the lock
            rec = self._enrollments.get(enroll_token)
            if not rec or rec["member_id"] != member_id:
                raise AuthError("invalid enrollment token")
            if self._now() > rec["expires"]:
                raise AuthError("enrollment token expired")
            if rec["bound"] is not None:
                raise AuthError("enrollment token already used (single-use)")  # M-4
            existing = self._bindings.get(member_id)
            if existing is not None and existing != thumb:
                raise AuthError("member already bound to a different identity key")
            self._bindings[member_id] = thumb
            rec["bound"] = thumb
            self._persist()
        return self._issue(member_id, thumb)

    # ---- session tokens --------------------------------------------------------------

    def _issue(self, member_id: str, thumb: str) -> str:
        if member_id in self._revoked_members:
            raise AuthError("member revoked")
        now = int(self._now())
        claims = {
            "sub": member_id,
            "thumb": thumb,
            "iat": now,
            "exp": now + self._session_ttl,
            "jti": secrets.token_urlsafe(12),
        }
        return jwt.encode(claims, self._sk, algorithm="EdDSA")

    def verify_session(self, token: str, *, expected_member: Optional[str] = None) -> dict:
        """Verify a session token. Raises AuthError on ANY problem (fail closed).

        Called both at connect and per relayed frame, so revocation + thumbprint checks
        take effect immediately.
        """
        self._maybe_reload()
        try:
            claims = jwt.decode(
                token, self._pk, algorithms=["EdDSA"],            # alg PINNED
                options={"require": ["exp", "iat", "sub", "thumb", "jti"]},  # review M-2
            )
        except jwt.PyJWTError as exc:
            raise AuthError("invalid session token: %s" % exc)
        sub = claims.get("sub")
        if sub in self._revoked_members:
            raise AuthError("member revoked")
        if claims.get("jti") in self._revoked_jti:
            raise AuthError("token revoked")
        if expected_member is not None and sub != expected_member:
            raise AuthError("token subject does not match claimed sender")
        if self._bindings.get(sub) != claims.get("thumb"):
            raise AuthError("identity rotated or unbound; token is stale")
        return claims

    def refresh(self, token: str) -> str:
        claims = self.verify_session(token)
        return self._issue(claims["sub"], claims["thumb"])

    # ---- revocation / rotation -------------------------------------------------------

    def revoke_member(self, member_id: str) -> None:
        with self._locked():       # reload-under-lock so a concurrent mint can't un-revoke
            self._revoked_members.add(member_id)
            self._persist()

    def revoke_token(self, jti: str) -> None:
        """Revoke a single leaked session token without revoking the whole member (M-3)."""
        with self._locked():
            self._revoked_jti.add(jti)
            self._persist()

    def is_revoked(self, member_id: str) -> bool:
        """Cheap per-message revocation check used by the router on every relayed frame."""
        self._maybe_reload()
        return member_id in self._revoked_members

    def rotate_identity(self, member_id: str, new_identity_pub_bytes: bytes) -> None:
        """Admin: rebind a member to a new identity key (invalidates outstanding tokens)."""
        thumb = fingerprint(new_identity_pub_bytes)
        with self._locked():
            self._bindings[member_id] = thumb
            self._persist()
