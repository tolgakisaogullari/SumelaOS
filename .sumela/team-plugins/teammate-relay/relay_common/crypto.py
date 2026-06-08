"""Task 1 — E2E crypto core for the Teammate Relay.

Security properties (all test-backed, see tests/test_crypto.py):

  * **Identity** = long-term Ed25519 signing keypair. Public part is committed to the repo
    (`keys/<id>.pub`); private stays local (see keystore.py).
  * **Forward secrecy** = each session uses a fresh ephemeral X25519 keypair. The symmetric
    session key derives ONLY from the ephemeral DH — never from the identity key. So leaking a
    long-term key gives zero ability to decrypt recorded ciphertext.
  * **Mutual authentication + anti-substitution** = each side signs a transcript binding
    `sender_id ‖ recipient_id ‖ ephemeral_pub ‖ session_id` with its identity key. Changing ANY
    bound field invalidates the signature → closes unknown-key-share, identity-misbinding, and
    (via mutual ephemerals) KCI.
  * **Replay defense** = a signed monotonic counter rides INSIDE the authenticated ciphertext;
    the recipient tracks a per-(sender, session_id) high-water mark, persisted atomically
    (see ReplayGuard) so a crash can't roll it back and re-open the window.

We use only PyNaCl high-level primitives + HKDF-SHA256 (stdlib hmac). No hand-rolled crypto.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import tempfile
from typing import Tuple

from nacl import bindings, secret, signing
from nacl.exceptions import BadSignatureError, CryptoError
from nacl.public import PrivateKey, PublicKey

_LABEL = b"teammate-relay/v1"
_NONCE_BYTES = secret.SecretBox.NONCE_SIZE  # 24
_KEY_BYTES = secret.SecretBox.KEY_SIZE      # 32


# ----------------------------------------------------------------------------- identity

def generate_identity() -> signing.SigningKey:
    """A fresh long-term Ed25519 identity signing key."""
    return signing.SigningKey.generate()


def identity_public_bytes(sk: signing.SigningKey) -> bytes:
    return bytes(sk.verify_key)


def fingerprint(verify_key_bytes: bytes) -> str:
    """Stable, human-comparable fingerprint of a public identity key (for TOFU pinning)."""
    digest = hashlib.sha256(verify_key_bytes).hexdigest()
    return ":".join(digest[i:i + 4] for i in range(0, 32, 4))  # first 8 groups (128 bits)


# --------------------------------------------------------------------------- handshake

def _transcript(sender_id: str, recipient_id: str, eph_pub: bytes, session_id: str) -> bytes:
    parts = [_LABEL, sender_id.encode(), recipient_id.encode(), eph_pub, session_id.encode()]
    # length-prefix each part so concatenation is unambiguous (no field-boundary confusion).
    out = b""
    for p in parts:
        out += len(p).to_bytes(4, "big") + p
    return out


def sign_handshake(sk: signing.SigningKey, sender_id: str, recipient_id: str,
                   eph_pub: bytes, session_id: str) -> bytes:
    """Sign the bound transcript. Returns the detached signature bytes."""
    return sk.sign(_transcript(sender_id, recipient_id, eph_pub, session_id)).signature


def verify_handshake(verify_key_bytes: bytes, sender_id: str, recipient_id: str,
                     eph_pub: bytes, session_id: str, sig: bytes) -> bool:
    """Verify a handshake signature. False on any mismatch (fail closed)."""
    vk = signing.VerifyKey(verify_key_bytes)
    try:
        vk.verify(_transcript(sender_id, recipient_id, eph_pub, session_id), sig)
        return True
    except BadSignatureError:
        return False


def generate_ephemeral() -> PrivateKey:
    """A fresh per-session ephemeral X25519 key. Its private part must be discarded after use."""
    return PrivateKey.generate()


def derive_session_key(my_eph_priv: PrivateKey, their_eph_pub: PublicKey,
                       session_id: str, id_a: str, id_b: str) -> bytes:
    """HKDF-SHA256 over the raw X25519 shared secret. Identity keys are NOT inputs (FS)."""
    shared = bindings.crypto_scalarmult(bytes(my_eph_priv), bytes(their_eph_pub))
    # info binds both participant ids (order-independent) and the session.
    info = b"|".join(sorted([id_a.encode(), id_b.encode()])) + b"|" + session_id.encode()
    return _hkdf(ikm=shared, salt=session_id.encode(), info=info, length=_KEY_BYTES)


def _hkdf(ikm: bytes, salt: bytes, info: bytes, length: int) -> bytes:
    prk = hmac.new(salt, ikm, hashlib.sha256).digest()
    okm, block, counter = b"", b"", 0
    while len(okm) < length:
        counter += 1
        block = hmac.new(prk, block + info + bytes([counter]), hashlib.sha256).digest()
        okm += block
    return okm[:length]


# --------------------------------------------------------------------------- encryption

def seal(session_key: bytes, plaintext: str, counter: int) -> dict:
    """Authenticated-encrypt `plaintext` with the per-message counter bound INSIDE the ciphertext."""
    box = secret.SecretBox(session_key)
    envelope = json.dumps({"c": counter, "b": plaintext}, separators=(",", ":")).encode("utf-8")
    nonce = os.urandom(_NONCE_BYTES)
    ct = box.encrypt(envelope, nonce).ciphertext  # store nonce separately
    return {
        "nonce": base64.b64encode(nonce).decode("ascii"),
        "ciphertext": base64.b64encode(ct).decode("ascii"),
    }


def open_msg(session_key: bytes, nonce_b64: str, ciphertext_b64: str) -> Tuple[int, str]:
    """Decrypt + authenticate. Returns (counter, plaintext). Raises CryptoError on tamper."""
    box = secret.SecretBox(session_key)
    nonce = base64.b64decode(nonce_b64)
    ct = base64.b64decode(ciphertext_b64)
    envelope = box.decrypt(ct, nonce)
    obj = json.loads(envelope.decode("utf-8"))
    return int(obj["c"]), obj["b"]


# ------------------------------------------------------------------------- replay guard

class ReplayGuard:
    """Per-(sender, session_id) high-water counter, persisted atomically across restarts."""

    def __init__(self, path: str):
        self._path = path
        self._hw = {}
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    self._hw = json.load(fh)
            except (ValueError, OSError):
                self._hw = {}  # corrupt store → start empty (counters only ever go up)

    @staticmethod
    def _key(sender_id: str, session_id: str) -> str:
        return "%s\x1f%s" % (sender_id, session_id)

    def check_and_update(self, sender_id: str, session_id: str, counter: int) -> bool:
        """True if `counter` is fresh (strictly greater than the high-water mark); else False.

        On accept, durably persists the new mark BEFORE returning, so a crash can never
        roll the mark backward and re-accept an old frame.
        """
        k = self._key(sender_id, session_id)
        last = self._hw.get(k, -1)
        if counter <= last:
            return False
        self._hw[k] = counter
        self._persist()
        return True

    def _persist(self) -> None:
        d = os.path.dirname(self._path) or "."
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".rg-", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(self._hw, fh)
                fh.flush()
                os.fsync(fh.fileno())
            os.replace(tmp, self._path)  # atomic
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
