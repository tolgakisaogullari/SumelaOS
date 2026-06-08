"""Phase-4 review fix — relay_ctl keygen + config parse + status exit code."""
import base64
import os

from client import relay_ctl
from client.relay_daemon import parse_server_url
from relay_common.keystore import RelayKeystore


def test_keygen_creates_committable_pubkey_and_retrievable_private(tmp_path, monkeypatch):
    runtime = str(tmp_path / ".relay")
    keys = str(tmp_path / "keys")
    monkeypatch.setenv("RELAY_RUNTIME", runtime)
    monkeypatch.setenv("RELAY_KEYS_DIR", keys)
    assert relay_ctl.cmd_keygen("alice") == 0
    pub = os.path.join(keys, "alice.pub")
    assert os.path.exists(pub)
    raw = base64.b64decode(open(pub).read())
    assert len(raw) == 32                                   # Ed25519 public key
    # the private key is retrievable from the keystore (so the daemon can load it)
    sk = RelayKeystore(runtime, backend="file").load_private_key("alice")
    from relay_common import crypto
    assert crypto.identity_public_bytes(sk) == raw          # pub matches the stored private


def test_keygen_refuses_overwrite_without_force(tmp_path, monkeypatch):
    monkeypatch.setenv("RELAY_RUNTIME", str(tmp_path / ".relay"))
    monkeypatch.setenv("RELAY_KEYS_DIR", str(tmp_path / "keys"))
    assert relay_ctl.cmd_keygen("alice") == 0
    pub = (tmp_path / "keys" / "alice.pub").read_text()
    assert relay_ctl.cmd_keygen("alice") == 2                # refuses silent rotation
    assert (tmp_path / "keys" / "alice.pub").read_text() == pub   # key untouched
    assert relay_ctl.cmd_keygen("alice", force=True) == 0    # explicit rotation allowed
    assert (tmp_path / "keys" / "alice.pub").read_text() != pub


def test_parse_server_url(tmp_path):
    cfg = tmp_path / "relay-config.md"
    cfg.write_text("# config\n```yaml\nserver_url: wss://relay.example:8765\n```\n")
    assert parse_server_url(str(cfg)) == "wss://relay.example:8765"
    assert parse_server_url(str(tmp_path / "absent.md")) is None


def test_build_config_rejects_plaintext_ws():
    from client.relay_daemon import build_config
    import pytest
    with pytest.raises(ValueError):
        build_config(runtime="/tmp/x/.relay", my_id="a", server_url="ws://evil:8765", repo_root=".")


def test_session_frame_emits_auth_followup(tmp_path):
    # First-connect fix: receiving a `session` (enroll reply) must emit an `auth` follow-up so
    # THIS connection authenticates (else the daemon enrolls but never goes online).
    from client.relay_daemon import RelayDaemon, DaemonConfig
    from relay_common import crypto
    cfg = DaemonConfig("alice", "wss://x:8765", str(tmp_path / ".relay"),
                       crypto.generate_identity(), lambda p: b"", enroll_token="tok")
    d = RelayDaemon(cfg)
    consumed, followup = d._on_control_frame({"type": "session", "session_token": "JWT"})
    assert consumed is True
    assert followup["type"] == "auth" and followup["client_id"] == "alice"
    assert followup["session_token"] == "JWT"


def test_status_exit_code_when_not_configured(tmp_path, monkeypatch):
    monkeypatch.setenv("RELAY_RUNTIME", str(tmp_path / "nope" / ".relay"))
    assert relay_ctl.cmd_status() == 3                      # stopped/unconfigured -> non-zero


def test_status_exit_code_stopped_with_runtime(tmp_path, monkeypatch):
    runtime = str(tmp_path / ".relay")
    os.makedirs(runtime + "/inbox"); os.makedirs(runtime + "/outbox")
    monkeypatch.setenv("RELAY_RUNTIME", runtime)
    assert relay_ctl.cmd_status() == 3                      # no daemon holding the lock -> stopped
