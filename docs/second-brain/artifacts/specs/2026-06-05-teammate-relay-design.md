---
type: spec
tags: [teammate-relay, real-time, team-coordination, security, websocket, e2e]
date_created: 2026-06-05
date_updated: 2026-06-05
status: draft-pending-approval
---

# Teammate Relay — Design Spec

_Decisions locked by Claude under delegated authority (2026-06-05), then hardened against an independent adversarial security review (6 Critical + 8 Important findings folded in; the "(Cn/In/Mn fix)" tags throughout cite which). Pending human sign-off before implementation._

## Objective

Give a SumelaOS team an **optional, real-time, cross-developer question channel**. When a developer's agent hits an ambiguity whose real owner is a *different* teammate (e.g. an analyst, a domain expert), the agent can route the question to that teammate — regardless of which git branch, machine, or network each person is on — and the teammate answers with their *own* agent's help (human + agent co-author the answer). The answer flows back and unblocks the original task.

This closes a structural gap: today an agent's only escalation target is the developer in the room, even when that person is the wrong respondent.

**Who it's for:** teams running SumelaOS in `team` governance mode who want live cross-developer/agent coordination. It is strictly opt-in and the framework is fully functional without it (mirrors the memory-plugin model).

## Success Criteria

1. **Cross-network real-time:** With the relay server reachable, a question sent by dev A reaches online dev X in < 2 s, irrespective of either party's git branch or LAN. Verified by an integration test measuring round-trip on two clients against a live server.
2. **Graceful async fallback:** If X is offline, the question is queued server-side (bounded, TTL) and delivered on X's next connect; A is told "queued, X offline." No message is silently dropped. Verified by an offline-delivery test.
3. **Blind server (content) + bounded metadata:** Message *content* is end-to-end encrypted; a full packet capture at the server (or a dump of server memory/disk) yields only routing metadata — never plaintext. Verified by a test asserting the server never holds a decryptable payload. **Honest, widened residual (round-2):** the server unavoidably learns the social-graph + per-pair message **count, timing, and (16 KiB-capped) size** — i.e. who asks whom and how often. We do NOT claim size-padding hides content length in v1 (no padding mechanism is specified); this is an *accepted, documented* residual, not a "the server learns nothing" claim.
9. **Forward secrecy:** Recorded ciphertext is not retroactively decryptable if a developer's long-term key later leaks. Verified by a test: decrypting an old captured frame with a leaked static key fails because session keys were ephemeral. (Defends against the "blind server quietly archives ciphertext, then a laptop is stolen" chain.)
10. **End-to-end delivery integrity (scoped honestly, round-2):** Recipient-signed receipts let the asker detect a server that drops/withholds a message it *claimed* to deliver. **Known residual it does NOT close:** a server that lies "X is offline, queued" can withhold indefinitely (the asker was told not to expect a receipt). Mitigation: a **sequence-numbered receipt chain** (recipient periodically signs "last counter seen from A = N") + a **"should-have-been-delivered" timeout that escalates to the human** rather than trusting "queued — offline." Verified by tests for drop-after-claimed-delivery (caught) and the timeout escalation; presence-lying is documented as a residual a single self-hosted team accepts.
4. **Authenticated identity, no spoofing:** A client cannot send *as* another developer, nor read a message addressed to someone else. Sender authenticity is cryptographically verifiable by the recipient. Verified by a spoof-attempt test that must fail closed.
5. **Secure-by-default, hard to misconfigure:** There is no plaintext-transport mode, no auth-disabled mode, no "trust all" mode. TLS (WSS) and per-developer auth are mandatory and on by default. Verified by config-validation rejecting `ws://` and missing-credential states.
6. **Prompt-injection-*resistant* (round-2 reframe — honesty fix):** We do NOT claim an LLM that must *read* a question to answer it can be architecturally prevented from "noticing" injected instructions — that would be a false guarantee. The **load-bearing control is the human approval gate**: no incoming message (question OR answer) can cause *any side effect* — tool call, file write, shell — **without explicit human approval**. Defense-in-depth on top: content reaches the agent as a quoted data value (not spliced into system/instructions), schema/size-validated, and the answer-side agent runs with no relay-write capability. The genuinely dangerous side is the **asker** resuming a real task with hot tools after ingesting an attacker-influenced answer — so the gate applies symmetrically. Verified by a red-team test measuring "no side-effect without human approval" in **both** directions (not "the model ignored the payload").
7. **Zero manual homework:** A developer joining a relay-enabled repo runs `/onboardSumela` and the client self-configures from repo-committed coordinates; the only manual action is pasting the team join-secret once (cached thereafter). Verified by an onboarding dry-run.
8. **Decline = nothing:** A team that declines the relay installs and runs nothing extra; `validate-structure.sh`, pre-commit, and CI all pass with the feature absent or present-but-unconfigured.

## Tech Stack

- **Language:** Python 3.10+ (consistent with the existing memory plugins; one runtime to support cross-platform).
- **Server:** `asyncio` + [`websockets`](https://pypi.org/project/websockets/) (WSS). Packaged as a Docker image + `docker-compose.yml`. Stateless except in-memory presence and a bounded, TTL'd offline queue (ciphertext only).
- **Crypto/identity:** [`PyNaCl`](https://pypi.org/project/PyNaCl/) (libsodium) — Curve25519 keypairs, authenticated `Box` encryption (sender-auth + confidentiality), per-message nonce for replay defense.
- **Client daemon:** Python long-running process; WSS connection + presence heartbeat; **file-queue IPC** (`.sumela/.relay/inbox|outbox/`) to talk to the agent — no localhost port opened (smaller attack surface, cross-platform, no Unix-socket dependency).
- **Notifications:** best-effort OS notification (`plyer`, **pinned + soft-imported so a missing/broken notifier never crashes the daemon — M4 fix**); always also writes the inbox file (notification is a convenience, the file is the source of truth).
- **Token auth:** short-lived signed session tokens (JWT via `PyJWT`) issued by the server after join-secret + public-key challenge; refreshed before expiry.
- **Setup:** bash + PowerShell parity (`scripts/setup-relay.sh` / `.ps1`), mirroring `setup-memory.*`.

## Commands

```bash
# Server (one-time, by the team's relay operator, on their box)
docker compose -f .sumela/team-plugins/teammate-relay/server/docker-compose.yml up -d   # start
docker compose ... logs -f                                                              # tail
# First start prints: relay URL + team join-secret (copy both)

# Install / wire (per team, run by setup)
bash scripts/setup-relay.sh --server-url wss://relay.example.com:8765   # Linux/macOS
powershell scripts/setup-relay.ps1 -ServerUrl wss://relay.example.com:8765   # Windows

# Client daemon (per developer; started by onboard, restartable)
python .sumela/team-plugins/teammate-relay/client/relay-daemon.py            # foreground/bg
python .sumela/team-plugins/teammate-relay/client/relay-ctl.py status        # health

# Agent-facing CLIs (invoked by the teammate-relay skill, talk to the daemon via file-queue)
python .sumela/team-plugins/teammate-relay/client/ask.py "<question>" --to @onur            # send
python .sumela/team-plugins/teammate-relay/client/ask.py "<question>" --domain payments     # route by domain
python .sumela/team-plugins/teammate-relay/client/inbox.py list                             # pending questions
python .sumela/team-plugins/teammate-relay/client/answer.py <message-id> "<answer text>"    # reply

# Tests (opt-in; not in default CI because they need a live server)
bash .sumela/team-plugins/teammate-relay/tests/run.sh
```

## Architecture

### Component map

```
.sumela/team-plugins/teammate-relay/          ← NEW optional-plugin category (parallel to memory-plugins/)
├── README.md
├── SKILL.md                                   ← skill: teammate-relay (lazy)
├── requirements.txt                           ← websockets, PyNaCl, PyJWT, plyer
├── relay-config.example.md                    ← committed coordinates template
├── server/
│   ├── relay_server.py                        ← asyncio WSS router (blind)
│   ├── auth.py                                 ← join-secret + pubkey challenge → session JWT
│   ├── presence.py                            ← who's connected
│   ├── queue.py                               ← bounded TTL offline queue (ciphertext)
│   ├── Dockerfile
│   └── docker-compose.yml
├── client/
│   ├── relay-daemon.py                        ← WSS connection, presence, inbox/outbox watcher
│   ├── crypto.py                              ← keypair gen, Box encrypt/decrypt, nonce
│   ├── ask.py / answer.py / inbox.py / relay-ctl.py   ← agent-facing CLIs (file-queue IPC)
│   └── keystore.py                            ← private key in OS keychain; pubkey to repo
├── keys/                                       ← committed PUBLIC keys: <dev-id>.pub  (safe to commit)
└── tests/
    └── run.sh + test_*.py
```

### Identity & trust model (the core decision — hardened after adversarial review)

- Each developer has a long-term **Ed25519 identity keypair** (signing) plus per-session **X25519 ephemeral keys** (encryption). Private keys are **local only** (OS keychain; gitignored `0600` fallback). The **long-term public identity key is committed to the repo** (`keys/<dev-id>.pub`).
- **Forward secrecy — concrete handshake (C1/C2 fix, round-2):** do NOT hand-roll. Adopt the **Noise `IK` pattern** (or libsodium `crypto_kx` with a signed prologue) for a mutually-authenticated ephemeral key agreement. The identity (Ed25519) signature MUST cover **`sender_id ‖ recipient_id ‖ ephemeral_pub ‖ session_id`** — binding all four closes unknown-key-share, identity-misbinding, and KCI (mutual ephemerals, not one-shot-to-static). A **"session" = one ephemeral key epoch**; the replay counter is **durable across daemon restarts and scoped to `session_id`** (a restart must not reset it to 0 and re-accept old frames); frames from an unknown/expired `session_id` are rejected. Recorded ciphertext stays undecryptable on later long-term-key leak. *(Exact transcript + KCI/UKS/replay-across-restart tests are locked in Task 1.)*
- **Anti key-substitution (C2/C3 fix):** committing a `.pub` is necessary but not sufficient trust. Three additions:
  1. A **`CODEOWNERS` entry gates `**/teammate-relay/keys/**`** so any add/swap/remove of a key is a reviewed change. This file is *shipped by the feature*, not assumed — `validate-structure.sh` asserts it exists whenever relay is configured.
  2. **Fingerprint confirmation on first contact (TOFU):** the first time A talks to X, A's daemon shows X's key fingerprint and pins it locally; a later fingerprint change forces a manual re-confirm (catches a silent swap even by someone with merge access).
  3. **Recipient keys are resolved from `origin/main`, never the working branch (I7 fix)** — a dev on a stale/hostile branch can't be tricked into encrypting to an attacker key planted on that branch, and a rotation on main takes effect without a rebase.
- **Two credentials, two jobs (I8 reconciliation — keeps the "paste once" UX you chose):**
  1. **Per-member enrollment token** (not a single shared secret): authenticates a client's right to *connect*. The operator mints one short token per teammate; on first connect it is **bound to that member's identity public key**, then cached locally. UX is still "paste once," but a leaked token is contained to one member and revocable per-member — a single laptop theft does not hand an attacker the whole team's connect access. **Never committed.**
  2. **Identity keypair** (per-developer): authenticates + (via ephemeral session keys) encrypts messages E2E. Revoked by removing the dev's `.pub` (reviewed PR) **and** a server-side revocation that force-disconnects any live session (M5 fix).
- Net property: a malicious/compromised **server** can neither read content (no private keys, ephemeral FS) nor forge a sender (no signing keys) nor *silently* drop/lie about delivery (E2E receipts, below). It *can* still see routing metadata (accepted residual, criterion 3).

### Message flow (online)

```
Dev A agent                A's daemon            Relay server            X's daemon              Dev X
  │  ask.py "Q" --to @onur    │                      │                       │                      │
  │ ──(file: outbox/)────────▶│                      │                       │                      │
  │                           │ Box.encrypt(Q, X.pub)│                       │                      │
  │                           │ ──WSS {to:X, ct}────▶│ (routes; cannot read) │                      │
  │                           │                      │ ──push {from:A, ct}──▶│                      │
  │                           │                      │                       │ decrypt(A.pub, priv) │
  │                           │                      │                       │ ──notify + inbox/───▶│ "A asks: Q"
  │                           │                      │                       │   (Window 1) discuss with agent
  │                           │                      │                       │   (Window 2) answer.py <id> "Ans"
  │                           │                      │ ◀──WSS {to:A, ct'}────│ Box.encrypt(Ans,A.pub)│
  │ ◀──inbox/ answer──────────│ ◀──push──────────────│                       │                      │
  │  resume blocked task      │                      │                       │                      │
```

If X is offline at the routing step, the server enqueues `{to:X, ct}` (TTL, bounded) and tells A "queued — X offline." On X's reconnect, the queue drains.

### Routing (target resolution — never guess silently)

1. **Explicit** — `--to @onur` or the agent parsed "ask Onur / @onur". Highest priority.
2. **By role/domain** — `--domain payments` resolved **only against the committed, CODEOWNERS-gated team role map** (NOT self-asserted `local.md` domains — I2 fix). If multiple developers hold the role, fan out to all; **the asker explicitly accepts one answer to close the question (I1 fix)** — arrival order does not auto-resolve, and all received answers are shown before the asker's task resumes, so an early/wrong answer can't silently win.
3. **Ambiguous / no holder** — ask the asking developer to pick a target; if none exists, fail gracefully ("no teammate owns this — answer locally or assign an owner").

### Framework integration points

| Area | Change |
|---|---|
| `init-sumela` | New opt-in step after memory-plugin selection (team mode only): "Enable teammate relay?" → capture server URL → write committed `relay-config.md` (URL + public team id; **no secrets**) → call `setup-relay.*`. |
| `onboard-sumela` | New step: detect committed `relay-config.md` → generate this dev's keypair, commit `.pub`, store private key in keychain → prompt join-secret **once** (cached) → set role/domains for routing (reuses existing domain prompt) → start daemon. |
| `SKILL_REGISTRY.md` | Register `teammate-relay` (activation `lazy`). |
| `scripts/setup-relay.{sh,ps1}` | New, mirrors `setup-memory.*`: deps → optional local server via Docker (confirm) → register skill → start daemon (confirm). Idempotent. |
| `.gitignore` | Add private-key file, join-secret cache, `.sumela/.relay/` runtime dir. |
| `sumela-prompt.md` | Session bootstrap: if relay configured, daemon-health check (warn once if offline). Information-gap routing: explicit "ask a teammate" trigger. |
| `validate-structure.sh` / `reconcile-registry.py` | Recognize the new `team-plugins/` category; skill-file ↔ registry parity. Must pass whether or not relay is configured. |
| Docs | This spec + the plan; a `team-plugins/README.md`; wiki links. |

## Security Considerations

This is internet-facing infrastructure each team self-operates; the relay server **is** the attack surface. Designed secure-by-default per `security_protocol.md` + `secure-coding-standard`. Defense in depth:

| Layer | Control |
|---|---|
| **Transport** | WSS / TLS 1.2+ only. `ws://` rejected at config-load. Valid cert (operator provides; docs cover Let's Encrypt + reverse proxy). |
| **AuthN (connection)** | Per-member enrollment token (bound to identity pubkey on first connect) + signed challenge → server issues a short-lived session token. **JWT alg is pinned (EdDSA); `algorithms=` is always passed on verify and `none` is rejected (C5 fix)** — guards alg-confusion/`none` forgery. Full lifecycle: issuance → keychain storage → WSS-only transmission → expiry → proactive refresh → per-member revocation **with force-disconnect of any live session (M5 fix)**. |
| **Confidentiality (E2E + forward secrecy)** | Per-session ephemeral X25519 → shared secret; ephemeral keys signed by the long-term identity key (C1 fix). Server is blind: ciphertext + metadata only, and recorded ciphertext is not retro-decryptable on later key leak. |
| **Sender authenticity** | Authenticated encryption + identity-key signature over the ephemeral handshake → recipient verifies origin against the `origin/main` key set; spoofing fails closed. |
| **AuthZ / isolation** | Each company runs its own server (physical tenant isolation). Server enforces: client may only act as its authenticated id; may only receive messages addressed to it. **Routing roles come only from the committed, CODEOWNERS-gated team role map — never from self-asserted `local.md` domains (I2 fix)**, so a member can't claim a role to harvest others' questions. |
| **Delivery integrity (anti-malicious-server)** | **Recipient-signed E2E delivery/read receipts surfaced to the asker (I5 fix)** — a server that drops/withholds/lies-about-presence while ACKing is detectable end-to-end, not just trusted. |
| **Prompt-injection (agent-specific, the standout threat — now architected, not asserted)** | **Enforced boundary, both directions (C6 fix):** relayed content (question *and* answer) is only ever handed to an agent as a **tool result / data parameter — never concatenated into system/instruction context**. Answer-side investigation runs in a session with **no relay-write capability**. The skill renders content as an inert quoted block behind the 2-window human gate; it can never, by itself, trigger a tool call, file write, or shell. Schema validation rejects oversized/malformed/control-char payloads. Red-teamed in **both** directions in Phase 0. |
| **Server hardening** | Container runs non-root, read-only FS, only the WSS port exposed, **outbound-deny** to the rest of the operator's network (no pivot). No SSH on the public interface. |
| **DoS / abuse** | Per-identity rate limit (default 10 msg/min), max message size (default 16 KiB), auth before any processing, **relay loop-guard** (max auto-relay depth + cooldown). Offline queue is **per-(sender,recipient) fair-shared, not a single per-recipient deque (M2 fix)** — one spammy sender can't evict a victim's legitimate queued questions. |
| **Replay** | **Signed monotonic counter + timestamp inside the encrypted payload; recipient tracks a per-sender high-water mark and rejects counter ≤ last-seen (C4 fix)** — bounded client-side state, robust to late async delivery, and independent of the (untrusted) server's id-dedup. |
| **Audit** | Connection/auth events + message *metadata* logged for incident response; **plaintext content is never logged** (`audit_and_output`). |
| **Secrets** | Private key + join-secret cache + session token are gitignored and stored in keychain where available; pre-commit `gitleaks` (if present) + `.gitignore` patterns prevent commits. Only *public* keys and the *server URL* are tracked. |

### Edge cases (explicitly handled)

- **Target offline** → queue + notify asker; **TTL expiry** → asker notified "question expired unanswered."
- **Asker disconnects before answer** → answer queued for asker too; delivered on reconnect.
- **Multiple role-holders** → fan-out; first authoritative answer closes; others see "answered by @x."
- **No role-holder / unknown target** → fail gracefully, suggest local answer or owner assignment.
- **Server unreachable** → skill degrades: warn "relay offline," offer to proceed with a flagged best-effort assumption or park the task; never block.
- **Dev leaves / key compromise** → revoke = remove `.pub` (PR) + rotate join-secret; server honors a revocation list.
- **Clock skew** → small leeway on token expiry + proactive refresh.
- **Notification fatigue** → presence-aware; file inbox is canonical so missed notifications are never lost; quiet-hours deferred to v2.
- **Daemon not running on receiver** → sender still queues server-side; receiver drains on next daemon start (so "agent isn't a daemon" never loses a message).
- **Two daemons for one developer (I3 fix)** → single-active-daemon lock (pidfile/`flock`); a second instance refuses to start, so presence can't flap and the queue can't deliver to a dead socket.
- **Crash between server-ACK and local write (I3 fix)** → the client acks a message to the server **only after a durable local write**, and keeps a persistent dedup set, so an ack-then-crash re-delivers rather than loses (upholds "no message silently dropped").
- **File-queue IPC race (I4 fix)** → all inbox/outbox writes are write-to-temp + atomic `os.rename` into the watched dir; a watcher never sees a half-written file.
- **CI** → relay tests are opt-in (need a live server/Docker); structure validation + pre-commit pass with relay absent or unconfigured.

## Boundaries

**Always:**
- WSS + per-developer auth + E2E on, by default. Validate every inbound message against a strict schema at the server boundary and at the client before it reaches the agent.
- Treat all relayed content as untrusted data; route answer-side actions through the human 2-window gate.
- Run `validate-structure.sh` + the relay test suite before staging; keep bash/PowerShell setup at parity.

**Ask first:**
- Any change that would let the server see plaintext, any new transport mode, any relaxation of auth, adding a third-party managed-pubsub backend, opening a localhost port for IPC, schema/DB persistence on the server beyond the bounded queue.

**Never:**
- Commit private keys, join-secrets, or tokens. Add a plaintext-`ws://` or auth-off mode. Log plaintext message content. Let an incoming message trigger autonomous tool/file/shell execution without a human gate. Bundle managed-pubsub in v1.

## Round-2 Review Hardening Log (two independent reviewers, 2026-06-05)

After the first review, two more independent subagents reviewed the hardened docs from distinct lenses (a crypto/security adversary and a framework-integration/ops lens). Both returned **REVISE**. The inline edits above resolve the headline crypto/agent claims (handshake spec, injection reframe, delivery scoping, padding-claim drop, daemon lifecycle). The remaining material findings, folded with their owning task:

**Security/crypto (reviewer A):**
- **JWT trust chain (I-3):** session JWT is **server-signed** (EdDSA, alg-pinned on the server's own verify); tokens carry the member-pubkey thumbprint so identity rotation invalidates them. → Task 2. **v1 scope (final-review honesty fix):** the *client* does not verify the session JWT — it presents the token back and the **server is authenticated to the client by WSS/TLS certificate validation**. The `server_verify_key` committed in `relay-config.md` is RESERVED for client-side JWT pinning (a v2 hardening) and is not yet enforced; the docs say so rather than overclaiming a pinning defense.
- **Revocation race (I-2):** server checks the revocation list **on connect AND per-message** (not only force-disconnect); enrollment tokens get a **TTL + rotation**; an **emergency server-side block** works independent of the (slower) `.pub`-removal PR. Documented residual: the `origin/main` key-propagation window. → Task 2.
- **TOFU pin integrity (I-1):** the fingerprint pinstore lives in the **OS keychain (or is identity-signed)**, fails closed on missing/mismatch, and is **never silently re-pinned**. → Task 1.
- **Fan-out confidentiality (I-4):** default to **asker-selects-one holder before send**; fan-out is opt-in; every holder seeing the question is a documented residual. → Task 7 / Routing.
- **Keystore safety (M-2):** refuse to *write* a `0600` fallback key into a non-gitignored / wrong-permission location. → Task 1.
- **Loop-guard clarity (M-3):** v1 has **no autonomous auto-relay** (all asks are human/agent-initiated); the guard caps rapid repeated asks. → Task 4 / PROTOCOL.

**Framework integration / ops (reviewer B):**
- **`memory-plugins/` is hardcoded in ~9 files, not one classifier (C1):** Task 0c is rewritten with an explicit per-file change list (`setup.{sh,ps1}`, `status.sh`, `update.{sh,ps1}`, `auto-update-memory.py`, `reconcile-registry.py` ×2, `validate-structure.sh`). → Task 0c.
- **`update.{sh,ps1}` never ships/patches the in-repo server (C2):** add `team-plugins` to `CORE_DIRS` **and** extend the `plugin_absent()` opt-in gate to `team-plugins/*/*` so decliners don't receive it. Critical for a security server that needs patching. → new Task 0d.
- **Conditional registration (I4):** register `teammate-relay` in `SKILL_REGISTRY.md` **only when enabled** (via `setup-relay`, like `register_plugin()`); `init-sumela` strips it when declined — otherwise a declining team ships a dangling skill and `validate-structure` path-check fails. → Task 8 / Task 10.
- **"Relay configured" predicate (I2):** define a machine-detectable signal (presence of `relay-config.md`) so `validate-structure.sh` can branch; test all three states (absent / present-unconfigured / configured). → Task 0c / Task 9.
- **`reconcile-registry.py` orphan/stats (I3):** teach it that `team-plugins/*/SKILL.md` is a conditional entry (exclude from orphan-deletion, classify in `--stats`); update README skill-count markers. → Task 0c.
- **`.gitignore` (I6):** add `!keys/*.pub` so committed public keys are trackable under the existing `*.key`/`*.pem` secret baseline while private keys stay ignored; test it. → Task 10.
- **`init-sumela` exact phase + scripted path (I5):** specify the new PHASE and decide relay = agent-driven install only (state it) or also wire `setup.{sh,ps1}` `--relay`. → Task 10.
- **`status.sh` relay awareness (M1):** add a relay daemon/health section so onboard can truthfully report state. → Task 10.
- **Server restart = volatile-queue loss (M3):** document that the in-RAM presence/queue is lost on server bounce (askers see TTL-expiry), and add a minimal operator health/metrics surface to `DEPLOY.md`. → Task 12.
- **Cross-platform matrix (M2):** add a per-platform autostart/keychain matrix incl. **WSL2 (no systemd-user) / devcontainer (no keychain, daemon dies with container) / laptop-sleep (stale presence until TTL)**. → Task 12.
- **Parity assertions (M4):** name concrete bash/PowerShell parity checks (same flags, idempotent registration, exit contract). → Task 9.

## Out of Scope (v1)

- Managed pub/sub backend (Ably/Pusher) — kept behind a clean transport interface for a future v2; v1 is self-host only.
- Rich GUI / dedicated 2-window app — v1 uses the IDE agent session + CLIs + OS notification + file inbox. (The "2 windows" are: the agent chat about the question, and the answer CLI.)
- Group/broadcast threads, attachments, voice. Quiet-hours / do-not-disturb. Web dashboard.
- Federated cross-company relays (each company is an isolated tenant by design).

## Resolved Decisions (signed off 2026-06-05)

1. **Relay-server home:** ✅ **In this repo** under `team-plugins/teammate-relay/server/` for v1. Extract to its own repo only if it outgrows this.
2. **Daemon lifecycle:** ✅ **Near-zero manual, but NOT a silent session-spawn (round-2 correction).** The ops review correctly flagged that `sumela-prompt.md` is a read-only, consent-gated instruction list executed by the agent — silently spawning a long-running process from it on *every* session (including CI runs and review subagents) would violate that contract and surprise users. So:
   - The "auto" path is **OS-level autostart (launchd / systemd-user / Task Scheduler), offered-and-confirmed ONCE at the end of `onboard-sumela`.** After that single confirm, the daemon starts on login with **zero per-session action** — this is the minimize-manual win, done honestly.
   - At session start, `sumela-prompt.md` only does a **health check that warns once if the daemon is down** (exactly the memory-plugin degrade pattern) and offers to start it — it never spawns silently.
   - The single-instance lock still prevents duplicates; `relay-ctl status` is for diagnostics.
   - Net manual cost to a developer: **one confirm at onboard.** That is the irreducible minimum given the consent contract.
3. **Keychain breadth:** ✅ **OS keychain when available, `0600` file fallback** on headless Linux — documented; the fallback path is gitignored and permission-checked at daemon start.
