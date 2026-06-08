"""Task 1 (cont.) — local key storage + TOFU fingerprint pinning.

Three security jobs (all test-backed):

  * **Private identity key** lives in the OS keychain when available; otherwise a `0600`
    file in the fully-gitignored `.sumela/.relay/` runtime dir. The file fallback REFUSES to
    write anywhere that isn't a `.relay` runtime dir (M-2 — never drop a private key into a
    tracked/insecure location).
  * **TOFU fingerprint pinning** (I-1): first contact pins a peer's identity fingerprint;
    a later *change* fails closed and is NEVER silently re-pinned — only an explicit
    `confirm_pin()` (which represents a human decision) may replace it.
  * **Recipient key resolution from `origin/main`** (I7), not the working branch, so a dev on a
    stale/hostile branch can't be tricked into encrypting to a planted key.

`keyring` is soft-imported; absence just forces the file fallback.
"""

from __future__ import annotations

import base64
import json
import os
import stat
import subprocess
from typing import Callable, Optional

from nacl import signing

try:  # soft import — never required
    import keyring as _keyring
except Exception:  # pragma: no cover - environment dependent
    _keyring = None

_KEYCHAIN_SERVICE = "sumela-teammate-relay"


class KeystoreError(Exception):
    pass


def _assert_relay_dir(path: str) -> None:
    """Refuse to use the file fallback outside a `.relay` runtime dir (M-2)."""
    parts = os.path.normpath(os.path.abspath(path)).split(os.sep)
    if ".relay" not in parts:
        raise KeystoreError(
            "refusing to store a private key outside a .relay runtime dir: %r" % path
        )


class RelayKeystore:
    def __init__(self, relay_dir: str, backend: str = "auto"):
        """backend: 'auto' (keychain if available else file), 'file', or 'keychain'."""
        self._dir = relay_dir
        if backend not in ("auto", "file", "keychain"):
            raise ValueError("bad backend %r" % backend)
        if backend == "keychain" and _keyring is None:
            raise KeystoreError("keychain backend requested but `keyring` is unavailable")
        use_keychain = (_keyring is not None) if backend == "auto" else (backend == "keychain")
        self._use_keychain = use_keychain
        if not use_keychain:
            _assert_relay_dir(relay_dir)
            os.makedirs(relay_dir, mode=0o700, exist_ok=True)

    # ---------------------------------------------------------------- private identity key

    def store_private_key(self, client_id: str, sk: signing.SigningKey) -> None:
        seed_b64 = base64.b64encode(bytes(sk)).decode("ascii")
        if self._use_keychain:
            _keyring.set_password(_KEYCHAIN_SERVICE, client_id, seed_b64)
            return
        path = self._key_path(client_id)
        # write 0600, atomically
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(seed_b64)
        os.chmod(path, 0o600)
        self._assert_mode_0600(path)

    def load_private_key(self, client_id: str) -> signing.SigningKey:
        if self._use_keychain:
            seed_b64 = _keyring.get_password(_KEYCHAIN_SERVICE, client_id)
            if seed_b64 is None:
                raise KeystoreError("no stored key for %r" % client_id)
        else:
            path = self._key_path(client_id)
            if not os.path.exists(path):
                raise KeystoreError("no stored key for %r" % client_id)
            self._assert_mode_0600(path)
            with open(path, "r", encoding="utf-8") as fh:
                seed_b64 = fh.read().strip()
        return signing.SigningKey(base64.b64decode(seed_b64))

    def _key_path(self, client_id: str) -> str:
        safe = "".join(c for c in client_id if c.isalnum() or c in "-_")
        return os.path.join(self._dir, "%s.identity.key" % safe)

    @staticmethod
    def _assert_mode_0600(path: str) -> None:
        mode = stat.S_IMODE(os.stat(path).st_mode)
        if mode & 0o077:
            raise KeystoreError("private key %r has unsafe permissions %o" % (path, mode))

    # -------------------------------------------------------------------- TOFU pinning

    def _pins(self) -> dict:
        if self._use_keychain:
            raw = _keyring.get_password(_KEYCHAIN_SERVICE, "__pins__")
            return json.loads(raw) if raw else {}
        path = os.path.join(self._dir, "pins.json")
        if not os.path.exists(path):
            return {}
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)

    def _save_pins(self, pins: dict) -> None:
        if self._use_keychain:
            _keyring.set_password(_KEYCHAIN_SERVICE, "__pins__", json.dumps(pins))
            return
        path = os.path.join(self._dir, "pins.json")
        tmp = path + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(pins, fh)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)

    def check_pin(self, peer_id: str, fingerprint: str) -> str:
        """Return 'ok' (matches pin), 'new' (no pin yet), or 'changed' (MISMATCH — fail closed)."""
        pinned = self._pins().get(peer_id)
        if pinned is None:
            return "new"
        return "ok" if pinned == fingerprint else "changed"

    def confirm_pin(self, peer_id: str, fingerprint: str, *, replace_changed: bool = False) -> None:
        """Pin a fingerprint. Represents an explicit human decision.

        A first-time pin ('new') is allowed. Replacing an existing, DIFFERENT pin requires
        `replace_changed=True` (the caller must have surfaced the change to a human). This
        guarantees a changed key is never silently re-pinned (I-1).
        """
        status = self.check_pin(peer_id, fingerprint)
        if status == "ok":
            return
        if status == "changed" and not replace_changed:
            raise KeystoreError(
                "fingerprint for %r CHANGED — refusing to re-pin without explicit confirmation" % peer_id
            )
        pins = self._pins()
        pins[peer_id] = fingerprint
        self._save_pins(pins)


def resolve_recipient_pubkey(
    client_id: str,
    repo_root: str,
    *,
    runner: Optional[Callable[[list], bytes]] = None,
) -> bytes:
    """Read a recipient's committed public key from `origin/main` (NOT the working tree, I7).

    `runner` is injectable for testing; defaults to a real `git show`.
    """
    ref = "origin/main:.sumela/team-plugins/teammate-relay/keys/%s.pub" % client_id
    if runner is None:
        def runner(cmd):  # pragma: no cover - exercised via integration, not unit
            return subprocess.check_output(cmd, cwd=repo_root)
    raw = runner(["git", "show", ref])
    data = raw.strip()
    # accept raw 32-byte key or base64-encoded
    if len(data) == 32:
        return data
    try:
        decoded = base64.b64decode(data, validate=True)
    except Exception as exc:
        raise KeystoreError("recipient pubkey for %r is malformed: %s" % (client_id, exc))
    if len(decoded) != 32:
        raise KeystoreError("recipient pubkey for %r is not 32 bytes" % client_id)
    return decoded
