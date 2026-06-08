# Teammate Relay — Operator Runbook

One self-hosted relay per team. The server is **blind** (routes E2E ciphertext, never decrypts).
Single instance (presence + the offline queue are in-RAM — see Restart semantics).

## 1. Deploy the server

```bash
cd .sumela/team-plugins/teammate-relay/server
# put your TLS cert chain + key here (see §2):
mkdir -p tls   # tls/fullchain.pem, tls/privkey.pem
docker compose up -d
docker compose logs -f        # first start prints the relay URL hint + the JWT verify-key
```

The container is hardened (non-root, read-only root FS, `cap_drop: ALL`, `no-new-privileges`,
only the WSS port published, the rest of your network egress-denied). The server signing key
persists in the `relay-data` volume — **do not** put it on a tmpfs, or every restart invalidates
all session tokens.

## 2. TLS (required — `ws://` is rejected)

Terminate TLS at the container (mount `tls/fullchain.pem` + `tls/privkey.pem`) or at a reverse
proxy in front of it. With Let's Encrypt/ACME, allow ONLY the ACME endpoints through the
otherwise-egress-denied policy (HTTP-01/TLS-ALPN inbound or DNS-01) — that is the single
documented exception to the server's outbound-deny.

## 3. Publish the verify-key into the project

On first start the server prints its **Ed25519 JWT verify-key (PEM)**. Paste it into the
committed `relay-config.md` (`server_verify_key:`). **v1 scope:** clients authenticate the server
via **WSS/TLS certificate validation**, not this key — it is RESERVED for client-side JWT pinning
(a v2 hardening) and is not yet enforced. Keep it current so pinning works when it lands.
**Server-key rotation** (`/data/server-key.pem`) re-issues session tokens; clients re-enroll/
reconnect transparently in v1 (no client-side pin to update yet).

## 4. Enroll members (one token per teammate)

```bash
docker compose exec relay python -m server.main mint-enrollment <member-id>
```

This shares the `/data` volume with the running server (shared, file-locked auth state), so the
minted token is redeemable over the wire. Give the token to that teammate **out-of-band**
(Slack / password manager — never commit it). They paste it once into `relay_ctl.py up
--enroll-token …`. Enrollment tokens are single-use and TTL'd; revoke a member with the same
state file (server checks the revocation list on connect AND per message).

## 5. Client OS-autostart (so the daemon starts on login — the minimize-manual path)

`relay_ctl.py up …` starts the daemon in the foreground. To make it start on login, register it
once per OS (then it's zero per-session work):

**macOS (launchd)** — `~/Library/LaunchAgents/com.sumela.relay.plist`:
```xml
<plist version="1.0"><dict>
  <key>Label</key><string>com.sumela.relay</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/python3</string>
    <string>PROJECT/.sumela/team-plugins/teammate-relay/client/relay_ctl.py</string>
    <string>up</string><string>--id</string><string>DEV_ID</string>
  </array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>WorkingDirectory</key><string>PROJECT</string>
</dict></plist>
```
`launchctl load ~/Library/LaunchAgents/com.sumela.relay.plist`

**Linux (systemd --user)** — `~/.config/systemd/user/sumela-relay.service`:
```ini
[Service]
WorkingDirectory=PROJECT
ExecStart=/usr/bin/python3 PROJECT/.sumela/team-plugins/teammate-relay/client/relay_ctl.py up --id DEV_ID
Restart=always
[Install]
WantedBy=default.target
```
`systemctl --user enable --now sumela-relay`

**Windows (Task Scheduler)** — trigger "At log on", action `python relay_ctl.py up --id DEV_ID`,
start-in `PROJECT`.

### Platform matrix / caveats

| Env | Keychain | Autostart | Note |
|-----|----------|-----------|------|
| macOS | Keychain | launchd | — |
| Linux desktop | Secret Service (if present) else `0600` | systemd --user | — |
| **WSL2** | usually none → `0600` | older WSL has no systemd-user → start via shell profile / `relay_ctl.py up` | works, just no native autostart |
| **devcontainer** | none → `0600` | none — daemon dies with the container | start it in the container's entrypoint |
| laptop sleep | — | — | presence shows you online until the server TTL; senders fall back to the queue |

## 6. Restart semantics (read this)

Presence + the offline queue are **in-RAM and volatile**: a server restart loses in-flight
queued messages, and askers see the receipt **timeout → human escalation** (by design — the
asker can't distinguish "offline" from "withheld", so it escalates rather than trusting). The
durable parts are the server signing key + the auth state (`/data`). Run a single replica.

## 7. Observability

`docker compose logs` (connection/auth events + message **metadata** only — never plaintext).
A bare `docker compose ps` / the container HEALTHCHECK (a real TLS handshake) tells you it's up.
