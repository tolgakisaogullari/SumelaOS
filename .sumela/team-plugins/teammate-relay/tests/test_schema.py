"""Task 0 — wire-frame schema validation. Fail-closed boundary tests."""
import json

import pytest

from relay_common import schema
from relay_common.schema import SchemaError, MAX_FRAME_BYTES, PROTOCOL_VERSION


def _msg(**over):
    base = {
        "v": PROTOCOL_VERSION,
        "type": "msg",
        "id": "11111111-1111-4111-8111-111111111111",
        "from": "alice",
        "to": "onur",
        "session_id": "sess-abc",
        "ciphertext": "Zm9vYmFy",  # base64
        "counter": 7,
    }
    base.update(over)
    return base


# ---- valid frames of each type parse -------------------------------------------------

def test_valid_msg_frame():
    out = schema.validate_frame(_msg())
    assert out["type"] == "msg" and out["counter"] == 7


@pytest.mark.parametrize("frame", [
    {"v": 1, "type": "hello", "id": "i", "client_id": "a", "eph_pub": "b64", "sig": "b64"},
    {"v": 1, "type": "enroll", "id": "i", "client_id": "a", "identity_pub": "b64", "enroll_token": "tok"},
    {"v": 1, "type": "auth", "id": "i", "client_id": "a", "session_token": "jwt"},
    {"v": 1, "type": "ack", "id": "i", "ref_id": "x"},
    {"v": 1, "type": "receipt", "id": "i", "ref_id": "x", "from": "a", "to": "b", "last_counter": 3, "sig": "b64"},
    {"v": 1, "type": "presence", "id": "i", "client_id": "a", "state": "online"},
    {"v": 1, "type": "error", "id": "i", "code": 4, "message": "nope"},
    {"v": 1, "type": "error", "id": "i", "code": 4, "message": "nope", "ref_id": "x"},  # optional field
])
def test_each_frame_type_valid(frame):
    assert schema.validate_frame(frame)["type"] == frame["type"]


# ---- malformed / hostile frames are rejected ----------------------------------------

def test_missing_required_field():
    f = _msg()
    del f["ciphertext"]
    with pytest.raises(SchemaError):
        schema.validate_frame(f)


def test_unknown_field_rejected():
    with pytest.raises(SchemaError):
        schema.validate_frame(_msg(evil="surprise"))


def test_unknown_type_rejected():
    with pytest.raises(SchemaError):
        schema.validate_frame(_msg(type="exec"))


def test_wrong_version_rejected():
    with pytest.raises(SchemaError):
        schema.validate_frame(_msg(v=2))


def test_non_object_rejected():
    with pytest.raises(SchemaError):
        schema.validate_frame(["not", "an", "object"])


def test_counter_must_be_nonneg_int():
    with pytest.raises(SchemaError):
        schema.validate_frame(_msg(counter=-1))
    with pytest.raises(SchemaError):
        schema.validate_frame(_msg(counter="7"))
    with pytest.raises(SchemaError):
        schema.validate_frame(_msg(counter=True))  # bool is not int here


def test_control_chars_rejected_in_text_field():
    with pytest.raises(SchemaError):
        schema.validate_frame(_msg(**{"from": "ali\x00ce"}))
    with pytest.raises(SchemaError):
        schema.validate_frame(_msg(**{"to": "onur\ninjected"}))


def test_control_chars_allowed_nowhere_but_blob_is_exempt():
    # ciphertext is a blob field — base64 has no control chars, but the exemption
    # means a long opaque value passes the control-char gate.
    assert schema.validate_frame(_msg(ciphertext="A" * 1000))


def test_invalid_presence_state():
    with pytest.raises(SchemaError):
        schema.validate_frame(
            {"v": 1, "type": "presence", "id": "i", "client_id": "a", "state": "lurking"}
        )


# ---- raw-bytes path: size cap + JSON parse ------------------------------------------

def test_validate_raw_ok():
    raw = json.dumps(_msg()).encode("utf-8")
    assert schema.validate_raw(raw)["type"] == "msg"


def test_oversize_frame_rejected():
    huge = _msg(ciphertext="A" * (MAX_FRAME_BYTES + 100))
    raw = json.dumps(huge).encode("utf-8")
    assert len(raw) > MAX_FRAME_BYTES
    with pytest.raises(SchemaError):
        schema.validate_raw(raw)


def test_non_json_rejected():
    with pytest.raises(SchemaError):
        schema.validate_raw(b"{not json")


def test_non_utf8_rejected():
    with pytest.raises(SchemaError):
        schema.validate_raw(b"\xff\xfe\x00bad")
