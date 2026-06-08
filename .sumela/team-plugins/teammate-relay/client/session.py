"""Task 6 — peer-to-peer E2E session manager (client side).

Establishes a forward-secret session with a teammate by exchanging signed-ephemeral `keyx`
frames (relayed verbatim by the blind server), then seals/opens messages with a per-session
monotonic counter and a durable replay guard, and produces/verifies recipient-signed receipts.

All crypto is delegated to the reviewed `relay_common.crypto` primitives. The signature over
each handshake binds `sender_id ‖ recipient_id ‖ eph_pub ‖ session_id` (closes UKS/KCI/misbinding).
Recipient identity public keys are resolved via an injected `resolve_pubkey` (from `origin/main`
in production — see keystore.resolve_recipient_pubkey).
"""

from __future__ import annotations

import base64
import os
import uuid
from dataclasses import dataclass, field
from typing import Callable, Dict, Optional, Tuple

from nacl import signing
from nacl.exceptions import CryptoError
from nacl.public import PrivateKey, PublicKey

from relay_common import crypto


def _b64(b: bytes) -> str:
    return base64.b64encode(b).decode("ascii")


def _ub64(s: str) -> bytes:
    return base64.b64decode(s)


@dataclass
class _Session:
    session_id: str
    eph_priv: PrivateKey
    peer_eph_pub: Optional[bytes] = None
    key: Optional[bytes] = None
    send_counter: int = 0
    initiator: bool = False


class SessionError(Exception):
    pass


class SessionManager:
    def __init__(self, my_id: str, signing_key: signing.SigningKey,
                 resolve_pubkey: Callable[[str], bytes], replay_path: str):
        self._id = my_id
        self._sk = signing_key
        self._resolve = resolve_pubkey
        self._replay = crypto.ReplayGuard(replay_path)
        self._sessions: Dict[str, _Session] = {}   # peer_id -> session

    def has_session(self, peer_id: str) -> bool:
        s = self._sessions.get(peer_id)
        return bool(s and s.key)

    def _frame(self, ftype: str, **fields) -> dict:
        return {"v": 1, "type": ftype, "id": str(uuid.uuid4()), **fields}

    # -- handshake ---------------------------------------------------------------------

    def initiate(self, peer_id: str) -> dict:
        """Begin a session: return a `keyx` frame to send to `peer_id`."""
        session_id = uuid.uuid4().hex
        eph = crypto.generate_ephemeral()
        self._sessions[peer_id] = _Session(session_id, eph, initiator=True)
        eph_pub = bytes(eph.public_key)
        sig = crypto.sign_handshake(self._sk, self._id, peer_id, eph_pub, session_id)
        return self._frame("keyx", **{"from": self._id, "to": peer_id,
                                      "session_id": session_id,
                                      "eph_pub": _b64(eph_pub), "sig": _b64(sig)})

    def on_keyx(self, frame: dict) -> Optional[dict]:
        """Process an incoming `keyx`. Returns a responding `keyx` to send back if WE are the
        responder (peer initiated); None once our side is established. Raises on bad signature."""
        peer_id = frame["from"]
        session_id = frame["session_id"]
        peer_eph = _ub64(frame["eph_pub"])
        # verify the peer's signature binds (peer -> me, peer_eph, session_id)
        try:
            peer_vk = self._resolve(peer_id)
        except Exception as exc:                 # unknown/unresolvable peer — drop cleanly
            raise SessionError("cannot resolve identity key for %r: %s" % (peer_id, exc))
        if not crypto.verify_handshake(peer_vk, peer_id, self._id, peer_eph, session_id,
                                       _ub64(frame["sig"])):
            raise SessionError("handshake signature failed for peer %r" % peer_id)

        existing = self._sessions.get(peer_id)
        if existing is not None and existing.initiator and existing.session_id == session_id:
            # we initiated; this is the responder's reply — complete our side.
            existing.peer_eph_pub = peer_eph
            existing.key = crypto.derive_session_key(
                existing.eph_priv, PublicKey(peer_eph), session_id, self._id, peer_id)
            return None
        if existing is not None and existing.initiator and not existing.key:
            # we have an in-flight initiator handshake; ignore an unrelated session_id keyx
            # rather than clobbering our pending session (review: peer-triggered reset).
            raise SessionError("conflicting keyx while a handshake to %r is in flight" % peer_id)

        # peer initiated: generate our ephemeral, derive, and reply.
        eph = crypto.generate_ephemeral()
        sess = _Session(session_id, eph, peer_eph_pub=peer_eph, initiator=False)
        sess.key = crypto.derive_session_key(eph, PublicKey(peer_eph), session_id,
                                             self._id, peer_id)
        self._sessions[peer_id] = sess
        eph_pub = bytes(eph.public_key)
        sig = crypto.sign_handshake(self._sk, self._id, peer_id, eph_pub, session_id)
        return self._frame("keyx", **{"from": self._id, "to": peer_id,
                                      "session_id": session_id,
                                      "eph_pub": _b64(eph_pub), "sig": _b64(sig)})

    # -- messaging ---------------------------------------------------------------------

    def seal(self, peer_id: str, plaintext: str) -> dict:
        s = self._sessions.get(peer_id)
        if not s or not s.key:
            raise SessionError("no established session with %r" % peer_id)
        s.send_counter += 1
        sealed = crypto.seal(s.key, plaintext, s.send_counter)
        blob = _b64(_ub64(sealed["nonce"]) + _ub64(sealed["ciphertext"]))  # nonce||ct
        return self._frame("msg", **{"from": self._id, "to": peer_id,
                                     "session_id": s.session_id,
                                     "ciphertext": blob, "counter": s.send_counter})

    def open(self, frame: dict) -> Tuple[int, str]:
        """Decrypt+authenticate an incoming msg, enforce replay. Returns (counter, plaintext)."""
        peer_id = frame["from"]
        s = self._sessions.get(peer_id)
        if not s or not s.key:
            raise SessionError("no established session with %r" % peer_id)
        # the wire `session_id` is NOT authenticated by the AEAD — bind to OUR session's id,
        # so a flipped wire field can't desync the replay-guard bucket (review).
        if frame.get("session_id") != s.session_id:
            raise SessionError("session_id mismatch from %r" % peer_id)
        raw = _ub64(frame["ciphertext"])
        nonce_b64, ct_b64 = _b64(raw[:24]), _b64(raw[24:])
        try:
            counter, plaintext = crypto.open_msg(s.key, nonce_b64, ct_b64)
        except (CryptoError, ValueError) as exc:
            raise SessionError("decrypt/auth failed from %r: %s" % (peer_id, exc))
        # replay defense uses the AUTHENTICATED in-payload counter + OUR bound session_id.
        if not self._replay.check_and_update(peer_id, s.session_id, counter):
            raise SessionError("replay detected from %r (counter %d)" % (peer_id, counter))
        return counter, plaintext

    # -- receipts ----------------------------------------------------------------------

    def make_receipt(self, peer_id: str, session_id: str, ref_id: str, last_counter: int) -> dict:
        sig = self._sk.sign(
            self._receipt_transcript(self._id, peer_id, session_id, last_counter)).signature
        return self._frame("receipt", **{"ref_id": ref_id, "from": self._id, "to": peer_id,
                                         "last_counter": last_counter, "sig": _b64(sig)})

    def verify_receipt(self, frame: dict, session_id: str) -> bool:
        """Verify a receipt against the EXPECTED session_id (bound into the signature), so a
        receipt from one session can't be replayed to ack another (review)."""
        try:
            peer_vk = self._resolve(frame["from"])
            vk = signing.VerifyKey(peer_vk)
            vk.verify(self._receipt_transcript(frame["from"], frame["to"], session_id,
                                               frame["last_counter"]),
                      _ub64(frame["sig"]))
            return True
        except Exception:
            return False

    @staticmethod
    def _receipt_transcript(sender: str, recipient: str, session_id: str, last_counter: int) -> bytes:
        return b"relay-receipt|%s|%s|%s|%d" % (
            sender.encode(), recipient.encode(), session_id.encode(), last_counter)

    def session_id_for(self, peer_id: str):
        s = self._sessions.get(peer_id)
        return s.session_id if s else None
