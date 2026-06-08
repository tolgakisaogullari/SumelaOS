"""Task 1 (cont.) — keystore: 0600-fallback safety, TOFU fail-closed, origin/main resolution."""
import base64
import os
import stat

import pytest

from relay_common import crypto
from relay_common.keystore import (
    RelayKeystore,
    KeystoreError,
    resolve_recipient_pubkey,
)


def _relay_dir(tmp_path):
    # must contain a `.relay` segment or the file fallback refuses to write
    d = tmp_path / ".sumela" / ".relay"
    return str(d)


# ------------------------------------------------------------- private key (file fallback)

def test_store_and_load_private_key_roundtrip(tmp_path):
    ks = RelayKeystore(_relay_dir(tmp_path), backend="file")
    sk = crypto.generate_identity()
    ks.store_private_key("alice", sk)
    loaded = ks.load_private_key("alice")
    assert bytes(loaded) == bytes(sk)


def test_private_key_file_is_0600(tmp_path):
    d = _relay_dir(tmp_path)
    ks = RelayKeystore(d, backend="file")
    ks.store_private_key("alice", crypto.generate_identity())
    path = os.path.join(d, "alice.identity.key")
    mode = stat.S_IMODE(os.stat(path).st_mode)
    assert mode & 0o077 == 0  # no group/other access


def test_refuses_to_write_private_key_outside_relay_dir(tmp_path):
    bad = str(tmp_path / "tracked" / "keys")  # no `.relay` segment
    with pytest.raises(KeystoreError):
        RelayKeystore(bad, backend="file")


def test_load_missing_key_raises(tmp_path):
    ks = RelayKeystore(_relay_dir(tmp_path), backend="file")
    with pytest.raises(KeystoreError):
        ks.load_private_key("nobody")


def test_loading_world_readable_key_fails_closed(tmp_path):
    d = _relay_dir(tmp_path)
    ks = RelayKeystore(d, backend="file")
    ks.store_private_key("alice", crypto.generate_identity())
    path = os.path.join(d, "alice.identity.key")
    os.chmod(path, 0o644)  # someone loosened perms
    with pytest.raises(KeystoreError):
        ks.load_private_key("alice")


# --------------------------------------------------------------------------- TOFU pinning

def test_tofu_new_then_ok(tmp_path):
    ks = RelayKeystore(_relay_dir(tmp_path), backend="file")
    fp = crypto.fingerprint(crypto.identity_public_bytes(crypto.generate_identity()))
    assert ks.check_pin("onur", fp) == "new"
    ks.confirm_pin("onur", fp)            # first contact
    assert ks.check_pin("onur", fp) == "ok"


def test_tofu_change_is_detected_and_fails_closed(tmp_path):
    ks = RelayKeystore(_relay_dir(tmp_path), backend="file")
    fp1 = crypto.fingerprint(crypto.identity_public_bytes(crypto.generate_identity()))
    fp2 = crypto.fingerprint(crypto.identity_public_bytes(crypto.generate_identity()))
    ks.confirm_pin("onur", fp1)
    assert ks.check_pin("onur", fp2) == "changed"
    # silent re-pin is refused (I-1)
    with pytest.raises(KeystoreError):
        ks.confirm_pin("onur", fp2)
    # the original pin is intact
    assert ks.check_pin("onur", fp1) == "ok"


def test_tofu_change_replaced_only_with_explicit_confirmation(tmp_path):
    ks = RelayKeystore(_relay_dir(tmp_path), backend="file")
    fp1 = crypto.fingerprint(crypto.identity_public_bytes(crypto.generate_identity()))
    fp2 = crypto.fingerprint(crypto.identity_public_bytes(crypto.generate_identity()))
    ks.confirm_pin("onur", fp1)
    ks.confirm_pin("onur", fp2, replace_changed=True)  # human approved
    assert ks.check_pin("onur", fp2) == "ok"


def test_pins_persist_across_instances(tmp_path):
    d = _relay_dir(tmp_path)
    fp = crypto.fingerprint(crypto.identity_public_bytes(crypto.generate_identity()))
    RelayKeystore(d, backend="file").confirm_pin("onur", fp)
    assert RelayKeystore(d, backend="file").check_pin("onur", fp) == "ok"


# ------------------------------------------------------- recipient key from origin/main (I7)

def test_resolve_recipient_pubkey_reads_origin_main():
    real = crypto.identity_public_bytes(crypto.generate_identity())  # 32 bytes
    calls = {}

    def fake_runner(cmd):
        calls["cmd"] = cmd
        return base64.b64encode(real)

    out = resolve_recipient_pubkey("onur", "/repo", runner=fake_runner)
    assert out == real
    # must read from origin/main, not the working tree
    assert calls["cmd"][:2] == ["git", "show"]
    assert calls["cmd"][2].startswith("origin/main:")
    assert calls["cmd"][2].endswith("keys/onur.pub")


def test_resolve_recipient_pubkey_rejects_malformed():
    with pytest.raises(KeystoreError):
        resolve_recipient_pubkey("onur", "/repo", runner=lambda cmd: b"not-a-key")
