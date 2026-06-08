"""Task 6 — always-on client daemon (thin async network wrapper around DaemonCore).

Holds the single WSS connection to the relay, authenticates (enroll first time -> cache the
session token; auth thereafter), then runs three concurrent loops: receive->core.on_incoming,
poll outbox->core.process_outbox, and periodic delivery-timeout checks. Reconnects with
backoff. A single-instance lock prevents two daemons for one developer.

This module is the network glue (like the server's serve()); its orchestration brain
(DaemonCore) and crypto (SessionManager) are unit-tested. End-to-end coverage lands in Task 11.
Config comes from the committed relay-config.md (server URL, server JWT verify-key) + the
per-developer keystore (identity key, cached enrollment/session token); see onboard-sumela.
"""

from __future__ import annotations

import base64
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # plugin root

from client.daemon_core import DaemonCore
from client.filequeue import FileQueue
from client.lock import SingleInstanceLock
from client.session import SessionManager
from relay_common import crypto

OUTBOX_POLL = 1.0
TIMEOUT_POLL = 15.0
BACKOFF_START = 1.0
BACKOFF_MAX = 30.0


class DaemonConfig:
    def __init__(self, my_id, server_url, runtime_dir, signing_key,
                 resolve_pubkey, enroll_token=None, session_token=None):
        self.my_id = my_id
        self.server_url = server_url
        self.runtime_dir = runtime_dir
        self.signing_key = signing_key
        self.resolve_pubkey = resolve_pubkey
        self.enroll_token = enroll_token        # used on first connect only
        self.session_token = session_token      # cached after enrollment


def _frame(ftype, **fields):
    import uuid
    return {"v": 1, "type": ftype, "id": str(uuid.uuid4()), **fields}


class RelayDaemon:
    def __init__(self, cfg: DaemonConfig):
        self._cfg = cfg
        self._fq = FileQueue(cfg.runtime_dir)
        sm = SessionManager(cfg.my_id, cfg.signing_key, cfg.resolve_pubkey,
                            os.path.join(cfg.runtime_dir, "replay.json"))
        self._core = DaemonCore(cfg.my_id, sm, self._fq,
                                awaiting_path=os.path.join(cfg.runtime_dir, "awaiting.json"))
        self._session_token = cfg.session_token
        self._token_cache = os.path.join(cfg.runtime_dir, "session-token")

    # -- authentication handshake ------------------------------------------------------

    async def _authenticate(self, ws) -> None:
        if self._session_token:
            await ws.send(json.dumps(_frame("auth", client_id=self._cfg.my_id,
                                            session_token=self._session_token)))
            return
        # first connect: enroll, then cache the returned session token.
        pub = crypto.identity_public_bytes(self._cfg.signing_key)
        await ws.send(json.dumps(_frame("enroll", client_id=self._cfg.my_id,
                                        identity_pub=base64.b64encode(pub).decode(),
                                        enroll_token=self._cfg.enroll_token)))

    def _on_control_frame(self, frame: dict):
        """Handle auth/session/ack/error frames the core doesn't.
        Returns (consumed: bool, followup_frame_or_None). On a `session` (enroll reply) we cache
        the token AND emit an `auth` follow-up so THIS connection actually authenticates — without
        it the first-ever connect would enroll but never become authenticated (review C2)."""
        t = frame.get("type")
        if t == "session":
            self._session_token = frame["session_token"]
            try:
                fd = os.open(self._token_cache, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w") as fh:
                    fh.write(self._session_token)
            except OSError:
                pass
            return True, _frame("auth", client_id=self._cfg.my_id,
                                session_token=self._session_token)
        return t in ("ack", "error"), None

    # -- run loop ----------------------------------------------------------------------

    async def run(self) -> None:
        import asyncio
        import websockets

        backoff = BACKOFF_START
        while True:
            try:
                async with websockets.connect(self._cfg.server_url) as ws:  # wss:// (TLS)
                    backoff = BACKOFF_START
                    await self._authenticate(ws)
                    tasks = [asyncio.ensure_future(self._recv_loop(ws)),
                             asyncio.ensure_future(self._outbox_loop(ws)),
                             asyncio.ensure_future(self._timeout_loop())]
                    # FIRST_COMPLETED so a CLEAN recv close (normal return, not exception)
                    # also tears the others down and reconnects — gather() would hang (review I1).
                    done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
                    for t in pending:
                        t.cancel()
                    await asyncio.gather(*pending, return_exceptions=True)
                    for t in done:
                        exc = t.exception()
                        if exc is not None:
                            raise exc                      # -> reconnect with backoff
            except Exception:
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2, BACKOFF_MAX)

    async def _send_all(self, ws, frames) -> None:
        for f in frames:
            await ws.send(json.dumps(f))

    async def _recv_loop(self, ws) -> None:
        async for raw in ws:
            try:
                frame = json.loads(raw)
            except ValueError:
                continue
            consumed, followup = self._on_control_frame(frame)
            if followup is not None:
                await ws.send(json.dumps(followup))   # send the auth follow-up after enroll
            if consumed:
                continue
            await self._send_all(ws, self._core.on_incoming(frame, time.time()))

    async def _outbox_loop(self, ws) -> None:
        import asyncio
        while True:
            for work in self._core.process_outbox(time.time()):
                await ws.send(json.dumps(work.frame))   # send FIRST
                self._core.commit(work)                 # ...then remove file / track delivery
            await asyncio.sleep(OUTBOX_POLL)

    async def _timeout_loop(self) -> None:
        import asyncio
        while True:
            self._core.check_timeouts(time.time())
            await asyncio.sleep(TIMEOUT_POLL)


def parse_server_url(relay_config_path: str):
    """Read `server_url:` out of the committed relay-config.md (no YAML dep)."""
    if not os.path.exists(relay_config_path):
        return None
    for line in open(relay_config_path, encoding="utf-8"):
        m = re.match(r'\s*server_url:\s*(\S+)\s*$', line)
        if m:
            return m.group(1)
    return None


def build_config(*, runtime, my_id, server_url, repo_root, enroll_token=None):
    """Build a DaemonConfig from the project layout (keystore identity + cached session)."""
    if not (server_url or "").startswith("wss://"):
        raise ValueError("WSS only: server_url must be wss:// (got %r) — no plaintext transport"
                         % server_url)   # secure-by-default, criterion 5
    from relay_common.keystore import RelayKeystore, resolve_recipient_pubkey
    ks = RelayKeystore(runtime, backend="auto")
    signing_key = ks.load_private_key(my_id)
    session_token = None
    cache = os.path.join(runtime, "session-token")
    if os.path.exists(cache):
        with open(cache) as fh:
            session_token = fh.read().strip()
    return DaemonConfig(
        my_id, server_url, runtime, signing_key,
        resolve_pubkey=lambda pid: resolve_recipient_pubkey(pid, repo_root),
        enroll_token=enroll_token, session_token=session_token)


def run_from_env() -> int:
    """Entrypoint: build config from env + keystore + relay-config and run under the lock."""
    import asyncio
    runtime = os.environ.get("RELAY_RUNTIME", os.path.join(".sumela", ".relay"))
    cfg = build_config(
        runtime=runtime,
        my_id=os.environ["RELAY_MY_ID"],
        server_url=os.environ["RELAY_SERVER_URL"],
        repo_root=os.environ.get("RELAY_REPO_ROOT", "."),
        enroll_token=os.environ.get("RELAY_ENROLL_TOKEN"))
    with SingleInstanceLock(os.path.join(runtime, "daemon.pid")):
        asyncio.run(RelayDaemon(cfg).run())
    return 0


if __name__ == "__main__":
    raise SystemExit(run_from_env())
