"""Strict wire-frame validation for the Teammate Relay protocol (v1).

This is the single boundary every frame passes through, at BOTH ends, before any
other code touches it. Fail closed: unknown fields, missing required fields, wrong
types, control characters in text fields, or oversize all raise SchemaError.

Pure standard-library (no third-party dep) so it can run anywhere the daemon/server
runs and be imported by the agent-facing CLIs without pulling in crypto/network deps.

See PROTOCOL.md for the authoritative contract this enforces.
"""

from __future__ import annotations

import json
import re
from typing import Any, Dict, Mapping, Tuple

PROTOCOL_VERSION = 1
MAX_FRAME_BYTES = 16 * 1024  # 16 KiB hard cap (anti-DoS); see PROTOCOL.md

# Control chars are forbidden in text fields (injection / framing hygiene). Tab,
# newline and CR are also rejected — relay text fields are single-line identifiers,
# tokens, or base64; multi-line human content travels inside `ciphertext` (base64).
_CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f]")

# Envelope fields present on every frame.
_ENVELOPE = ("v", "type", "id")

# Per-type required fields (beyond the envelope). Anything not listed here (or in
# _OPTIONAL) is an unknown field and rejected.
_REQUIRED: Dict[str, Tuple[str, ...]] = {
    "hello":    ("client_id", "eph_pub", "sig"),
    "enroll":   ("client_id", "identity_pub", "enroll_token"),
    "auth":     ("client_id", "session_token"),
    "session":  ("ref_id", "session_token"),
    "keyx":     ("from", "to", "session_id", "eph_pub", "sig"),
    "msg":      ("from", "to", "session_id", "ciphertext", "counter"),
    "ack":      ("ref_id",),
    "receipt":  ("ref_id", "from", "to", "last_counter", "sig"),
    "presence": ("client_id", "state"),
    "error":    ("code", "message"),
}

# Optional fields permitted per type.
_OPTIONAL: Dict[str, Tuple[str, ...]] = {
    "error": ("ref_id",),
}

# Fields whose value is an integer (everything else is a string unless noted).
_INT_FIELDS = {"v", "counter", "last_counter", "code"}

# Fields exempt from the control-char / length text check (base64 or long blobs).
_BLOB_FIELDS = {"ciphertext", "sig", "eph_pub", "identity_pub", "session_token", "enroll_token"}

_PRESENCE_STATES = {"online", "offline"}

# Generous per-text-field length cap (the 16 KiB frame cap is the real bound; this
# just stops a single pathological field from being silly).
_MAX_TEXT_LEN = 4096


class SchemaError(ValueError):
    """Raised when a frame violates the wire contract."""


def _check_text(name: str, value: Any) -> None:
    if not isinstance(value, str):
        raise SchemaError("field %r must be a string" % name)
    if len(value) > _MAX_TEXT_LEN:
        raise SchemaError("field %r exceeds %d chars" % (name, _MAX_TEXT_LEN))
    if name not in _BLOB_FIELDS and _CONTROL_CHARS.search(value):
        raise SchemaError("field %r contains control characters" % name)


def _check_int(name: str, value: Any) -> None:
    # bool is a subclass of int — reject it explicitly.
    if isinstance(value, bool) or not isinstance(value, int):
        raise SchemaError("field %r must be an integer" % name)
    if name in ("counter", "last_counter", "code") and value < 0:
        raise SchemaError("field %r must be non-negative" % name)


def validate_frame(frame: Mapping[str, Any]) -> Dict[str, Any]:
    """Validate a parsed frame dict. Returns it (as a plain dict) or raises SchemaError."""
    if not isinstance(frame, Mapping):
        raise SchemaError("frame must be a JSON object")

    for f in _ENVELOPE:
        if f not in frame:
            raise SchemaError("missing envelope field %r" % f)

    _check_int("v", frame["v"])
    if frame["v"] != PROTOCOL_VERSION:
        raise SchemaError("unsupported protocol version %r" % frame["v"])

    ftype = frame["type"]
    if not isinstance(ftype, str) or ftype not in _REQUIRED:
        raise SchemaError("unknown frame type %r" % (ftype,))

    _check_text("id", frame["id"])

    required = _REQUIRED[ftype]
    allowed = set(_ENVELOPE) | set(required) | set(_OPTIONAL.get(ftype, ()))

    for f in required:
        if f not in frame:
            raise SchemaError("frame %r missing required field %r" % (ftype, f))

    for key, value in frame.items():
        if key not in allowed:
            raise SchemaError("frame %r has unknown field %r" % (ftype, key))
        if key in _ENVELOPE:
            continue
        if key in _INT_FIELDS:
            _check_int(key, value)
        else:
            _check_text(key, value)

    if ftype == "presence" and frame["state"] not in _PRESENCE_STATES:
        raise SchemaError("invalid presence state %r" % (frame["state"],))

    return dict(frame)


def validate_raw(raw: bytes) -> Dict[str, Any]:
    """Validate a raw wire frame: size cap → JSON parse → schema. Fail closed."""
    if isinstance(raw, str):
        raw = raw.encode("utf-8")
    if not isinstance(raw, (bytes, bytearray)):
        raise SchemaError("raw frame must be bytes")
    if len(raw) > MAX_FRAME_BYTES:
        raise SchemaError("frame exceeds %d bytes" % MAX_FRAME_BYTES)
    try:
        parsed = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SchemaError("frame is not valid UTF-8 JSON: %s" % exc)
    return validate_frame(parsed)
