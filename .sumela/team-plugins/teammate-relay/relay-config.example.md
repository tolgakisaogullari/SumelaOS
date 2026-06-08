# Teammate Relay — project configuration (COMMITTED, team-wide)

> Copy to `relay-config.md` (no `.example`) when enabling the relay. `/initSumela` writes this
> for you. This file is COMMITTED and **CODEOWNERS-gated** — it contains NO secrets (only the
> public server URL and the server's public JWT verify-key). The per-member enrollment token and
> private identity key are NEVER committed.

```yaml
# WSS URL of the team's self-hosted relay server (TLS required; ws:// is rejected).
server_url: wss://relay.example.com:8765

# The relay server's Ed25519 JWT verify-key (PEM). In v1 the server is authenticated by
# WSS/TLS certificate validation (the daemon connects only over wss://); this committed key is
# RESERVED for client-side JWT pinning (a v2 hardening) and is not yet enforced by the client.
# Printed by the server on first start (see server/DEPLOY.md).
server_verify_key: |
  -----BEGIN PUBLIC KEY-----
  MCowBQYDK2VwAyEA<...>=
  -----END PUBLIC KEY-----
```

The committed role map lives alongside this file as `roles.json` (see `roles.example.json`):
it maps a domain to the member ids that own it, for `ask.py --domain <d>` routing. Only this
committed, reviewed map is authoritative — never self-declared local domains.
