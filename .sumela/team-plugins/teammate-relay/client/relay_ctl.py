#!/usr/bin/env python3
"""relay-ctl — operational CLI for the relay client.

  status            daemon up? inbox/outbox counts   (exit 0 = running, 3 = stopped)
  keygen <id>       create this developer's identity keypair (private -> keychain/0600;
                    PUBLIC -> keys/<id>.pub for committing)
  up [--id <id>] [--enroll-token <t>]
                    start the always-on client daemon (reads server_url from
                    relay-config.md; identity from the keystore). Runs under a
                    single-instance lock. This is the explicit start command;
                    OS-autostart (so it starts on login) is set up per server/DEPLOY.md.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # plugin root

from client.filequeue import FileQueue  # noqa: E402
from client.lock import _fcntl  # noqa: E402

PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _runtime() -> str:
    return os.environ.get("RELAY_RUNTIME", os.path.join(".sumela", ".relay"))


def _daemon_running(runtime: str) -> bool:
    """Liveness WITHOUT side effects: a running daemon holds an exclusive flock on the
    pidfile. Absent pidfile => stopped; we never create the runtime dir here."""
    pid = os.path.join(runtime, "daemon.pid")
    if not os.path.exists(pid) or _fcntl is None:
        return os.path.exists(pid)  # best-effort on non-POSIX
    fh = open(pid, "r")
    try:
        _fcntl.flock(fh, _fcntl.LOCK_EX | _fcntl.LOCK_NB)
        _fcntl.flock(fh, _fcntl.LOCK_UN)
        return False                # we got the lock => no daemon holds it
    except OSError:
        return True                 # locked => a daemon is running
    finally:
        fh.close()


def cmd_status() -> int:
    runtime = _runtime()
    if not os.path.isdir(runtime):
        print("relay: not configured (no runtime dir at %s)" % runtime)
        return 3
    running = _daemon_running(runtime)
    fq = FileQueue(runtime)
    print("relay daemon: %s" % ("RUNNING" if running else "stopped"))
    print("inbox:  %d pending" % len(fq.list_inbox()))
    print("outbox: %d queued" % len(fq.drain_outbox()))
    return 0 if running else 3      # non-zero when stopped so status.sh can flag it


def cmd_keygen(dev_id: str, force: bool = False) -> int:
    from relay_common import crypto
    from relay_common.keystore import RelayKeystore
    runtime = _runtime()
    os.makedirs(runtime, mode=0o700, exist_ok=True)
    keys_dir = os.environ.get("RELAY_KEYS_DIR", os.path.join(PLUGIN_ROOT, "keys"))
    import base64
    pub_path = os.path.join(keys_dir, "%s.pub" % dev_id)
    if os.path.exists(pub_path) and not force:
        # Overwriting silently rotates the identity: teammates pin the OLD pubkey from
        # origin/main, so inbound traffic fails until a reviewed .pub commit lands. Refuse.
        print("error: identity for %r already exists (%s). Re-run with --force to ROTATE "
              "(coordinate the new .pub commit with your team first)." % (dev_id, pub_path),
              file=sys.stderr)
        return 2
    ks = RelayKeystore(runtime, backend="auto")
    sk = crypto.generate_identity()
    ks.store_private_key(dev_id, sk)
    os.makedirs(keys_dir, exist_ok=True)
    with open(pub_path, "w", encoding="utf-8") as fh:
        fh.write(base64.b64encode(crypto.identity_public_bytes(sk)).decode())
    print("identity created for %r" % dev_id)
    print("  private: stored in keychain/0600 (runtime)")
    print("  public:  %s  — COMMIT this (CODEOWNERS-gated) so teammates can reach you" % pub_path)
    return 0


def cmd_up(dev_id, enroll_token) -> int:
    import asyncio
    from client.lock import SingleInstanceLock
    from client.relay_daemon import RelayDaemon, build_config, parse_server_url
    runtime = _runtime()
    dev_id = dev_id or os.environ.get("RELAY_MY_ID")
    if not dev_id:
        print("error: --id <dev-id> (or RELAY_MY_ID) required", file=sys.stderr)
        return 2
    cfg_path = os.path.join(PLUGIN_ROOT, "relay-config.md")
    server_url = parse_server_url(cfg_path)
    if not server_url:
        print("error: no server_url in %s — enable the relay first (setup-relay)" % cfg_path, file=sys.stderr)
        return 2
    repo_root = os.environ.get("RELAY_REPO_ROOT") or os.getcwd()
    cfg = build_config(runtime=runtime, my_id=dev_id, server_url=server_url,
                       repo_root=repo_root, enroll_token=enroll_token)
    try:
        with SingleInstanceLock(os.path.join(runtime, "daemon.pid")):
            print("relay daemon up for %r -> %s" % (dev_id, server_url))
            asyncio.run(RelayDaemon(cfg).run())
    except Exception as exc:  # AlreadyRunning etc.
        print("relay daemon not started: %s" % exc, file=sys.stderr)
        return 1
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Relay client control.")
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("status")
    kg = sub.add_parser("keygen"); kg.add_argument("dev_id"); kg.add_argument("--force", action="store_true")
    up = sub.add_parser("up"); up.add_argument("--id"); up.add_argument("--enroll-token")
    a = ap.parse_args(argv)
    if a.cmd == "keygen":
        return cmd_keygen(a.dev_id, a.force)
    if a.cmd == "up":
        return cmd_up(a.id, a.enroll_token)
    return cmd_status()


if __name__ == "__main__":
    raise SystemExit(main())
