"""Task 5 — relay server entrypoint + operator CLI.

Subcommands:
  serve              run the WSS relay (WSS only — TLS cert/key required)
  mint-enrollment    operator: mint a per-member enrollment token (prints it once)

Config via env:
  RELAY_HOST            default 0.0.0.0
  RELAY_PORT            default 8765
  RELAY_TLS_CERT        path to the TLS certificate chain (PEM)   [required for serve]
  RELAY_TLS_KEY         path to the TLS private key (PEM)         [required for serve]
  RELAY_SERVER_KEY      path to the server's Ed25519 signing key  [persisted; auto-generated 0600]

The server signing key MUST persist across restarts (else every client's session token is
invalidated on a bounce). The presence map + offline queue are intentionally in-RAM and
volatile — a restart loses in-flight queued items and askers see receipt-timeout escalation
(documented residual; see DEPLOY.md / spec §Success Criteria 2).
"""

from __future__ import annotations

import os
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from server.auth import RelayAuth
from server.presence import PresenceRegistry
from server.queue import FairOfflineQueue
from server.relay_server import RelayRouter, serve


def _load_or_create_server_key(path: str) -> Ed25519PrivateKey:
    if os.path.exists(path):
        with open(path, "rb") as fh:
            return serialization.load_pem_private_key(fh.read(), password=None)
    sk = Ed25519PrivateKey.generate()
    pem = sk.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    # O_EXCL closes the first-boot race (two processes/replicas): the loser gets
    # FileExistsError and reads the winner's key instead of clobbering it (review I3).
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        with open(path, "rb") as fh:
            return serialization.load_pem_private_key(fh.read(), password=None)
    with os.fdopen(fd, "wb") as fh:
        fh.write(pem)
    os.chmod(path, 0o600)
    return sk


def _build_auth() -> RelayAuth:
    key_path = os.environ.get("RELAY_SERVER_KEY", "/data/server-key.pem")
    # Shared, durable auth state so `mint-enrollment` (a separate process) and `serve`
    # agree on enrollments/bindings/revocations (review I5).
    state_path = os.environ.get("RELAY_AUTH_STATE", "/data/auth-state.json")
    return RelayAuth(_load_or_create_server_key(key_path), state_path=state_path)


def cmd_mint_enrollment(member_id: str) -> int:
    auth = _build_auth()
    token = auth.mint_enrollment_token(member_id)
    # Persisted to the shared RELAY_AUTH_STATE file, so the running `serve` process picks it
    # up (it reloads state) and the token is redeemable over the wire via an `enroll` frame.
    # In the container, run this as `docker compose exec relay python -m server.main
    # mint-enrollment <member>` so it shares the same /data volume (see DEPLOY.md).
    sys.stdout.write(token + "\n")
    return 0


def cmd_serve() -> int:
    import asyncio
    import ssl

    cert = os.environ.get("RELAY_TLS_CERT")
    key = os.environ.get("RELAY_TLS_KEY")
    if not cert or not key:
        sys.stderr.write("ERROR: WSS only — set RELAY_TLS_CERT and RELAY_TLS_KEY.\n")
        return 2
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(certfile=cert, keyfile=key)

    auth = _build_auth()
    router = RelayRouter(auth, PresenceRegistry(), FairOfflineQueue())
    host = os.environ.get("RELAY_HOST", "0.0.0.0")
    port = int(os.environ.get("RELAY_PORT", "8765"))
    sys.stderr.write("teammate-relay listening on wss://%s:%d (TLS 1.2+)\n" % (host, port))
    asyncio.run(serve(host, port, router, ssl_context=ctx))
    return 0


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        sys.stderr.write("usage: main.py {serve|mint-enrollment <member>}\n")
        return 2
    cmd, rest = argv[0], argv[1:]
    if cmd == "serve":
        return cmd_serve()
    if cmd == "mint-enrollment":
        if not rest:
            sys.stderr.write("usage: main.py mint-enrollment <member_id>\n")
            return 2
        return cmd_mint_enrollment(rest[0])
    sys.stderr.write("unknown command %r\n" % cmd)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
