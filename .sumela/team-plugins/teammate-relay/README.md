# Teammate Relay

Real-time, **end-to-end-encrypted** question relay so one developer's agent can ask the teammate
who actually owns an answer — regardless of branch, machine, or network — and get a human+agent
co-authored reply back. Opt-in, team mode. See [SKILL.md](SKILL.md) for the agent-facing workflow.

## Architecture (one glance)

```
dev A agent ──ask.py──▶ A's daemon ──WSS (E2E ciphertext)──▶ relay server ──push──▶ X's daemon ──inbox──▶ dev X (+ agent)
                                       (blind: routes, never decrypts)                                   answer.py ◀──┘
```

- **Server** (`server/`): a self-hosted, hardened, **blind** WSS router. It sees only routing
  metadata; message content is end-to-end encrypted between developers. One per team (own data,
  no dependency on the framework authors). Deploy: `server/docker-compose.yml` (operator runbook
  `server/DEPLOY.md` lands with the setup wiring).
- **Client** (`client/`): a small always-on daemon holds the socket and does the crypto; the
  agent talks to it only through a local file-queue (`ask`/`inbox`/`answer` — no localhost port).
- **Identity & trust**: per-developer Ed25519 keypair; **public** keys committed to the repo
  (`keys/<id>.pub`, CODEOWNERS-gated); private keys local (OS keychain / `0600`). Sessions use
  forward-secret ephemeral X25519. The server is authenticated by **WSS/TLS cert validation**
  (v1); per-member enrollment tokens + EdDSA session tokens authenticate the client. (The
  `server_verify_key` in `relay-config.md` is reserved for client-side JWT pinning, a v2 hardening.)

## Security model (summary)

- **Blind server**: content is E2E; a server dump yields only metadata (who↔whom, timing, size).
- **Forward secrecy**: leaking a long-term key does not decrypt recorded ciphertext.
- **No spoofing**: messages are sender-authenticated; the server rejects sending as another id.
- **Untrusted by default**: relayed content reaches the agent as DATA behind a human approval
  gate — it can never trigger a tool/file/shell action on its own (prompt-injection resistance).
- **Delivery integrity**: recipient-signed receipts; on timeout the asker escalates to the human
  rather than trusting a "delivered" claim.

Full threat model: `docs/second-brain/artifacts/specs/2026-06-05-teammate-relay-design.md`.

## Layout

```
teammate-relay/
├── SKILL.md                 agent-facing workflow (ask / answer / safety)
├── PROTOCOL.md              wire contract (frames, replay, receipts, IPC)
├── relay-config.example.md  committed coordinates template (URL + server verify-key)
├── roles.example.json       committed role map (domain -> [member ids])
├── requirements.txt
├── relay_common/            schema, untrusted boundary, crypto, keystore
├── server/                  blind WSS router + auth + presence + queue + Docker
├── client/                  daemon + session + file-queue + ask/inbox/answer CLIs
├── keys/                    committed PUBLIC identity keys, CODEOWNERS-gated (created on onboard)
└── tests/                   unit + integration tests
```
