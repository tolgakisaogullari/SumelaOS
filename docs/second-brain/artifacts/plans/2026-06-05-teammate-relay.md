# Teammate Relay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans`. Steps use checkbox (`- [ ]`) syntax.
> **CRITICAL RULE:** Accumulate uncommitted changes. DO NOT use `git commit` during task execution. Only `git add` is allowed until the final review step.
> **BRANCH:** All work on `feat/teammate-relay` (per user instruction + `git_workflow_mandatory_review_protocol`). Never touch `master` directly.

**Goal:** Add an opt-in, real-time, end-to-end-encrypted cross-developer question relay to SumelaOS (server + client daemon + agent skill + init/onboard wiring), so an agent can route a question to the right teammate on any branch/network and get a human+agent co-authored answer back.
**Architecture:** Self-hosted blind WSS relay server (Python/asyncio); per-developer client daemon holding the socket + file-queue IPC to the agent; NaCl E2E with repo-committed public keys; opt-in plugin under `.sumela/team-plugins/teammate-relay/` mirroring the memory-plugin model. See spec: [2026-06-05-teammate-relay-design](../specs/2026-06-05-teammate-relay-design.md).
**Tech Stack:** Python 3.10+, `websockets`, `PyNaCl`, `PyJWT`, `plyer`; Docker; bash + PowerShell setup.
**TDD Mode:** Enabled — security-critical (crypto, auth, routing) demands test-first.
**Security Constraints:** WSS-only; per-dev auth lifecycle; blind server (E2E); incoming = untrusted data (no side effects without human gate); server hardening + rate-limit + loop-guard; no committed secrets. MANDATORY compliance with `secure-coding-standard` + `security_protocol.md`.

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| E2E crypto implemented incorrectly (the classic footgun) | High | Use PyNaCl high-level `Box` only (no custom crypto); test-first; dispatch the Correctness & Security review lane on every crypto/auth task. |
| "Agent isn't a daemon" → real-time receive impossible | High | Split: always-on dumb daemon holds the socket + writes a canonical file inbox; agent reads on-demand. Server queues for offline receivers so nothing is lost. |
| Prompt injection via relayed content reaching an agent | High | Phase 5 hardening: content rendered as quoted untrusted data; no autonomous side effects; human 2-window gate; schema + size validation. Red-team test. |
| Server becomes a network pivot if breached | High | Hardened container: non-root, read-only FS, only WSS port, outbound-deny. |
| Feature breaks default CI / structure validation for teams that decline it | Med | Relay tests opt-in; `validate-structure.sh` + `reconcile-registry.py` must pass with relay absent/unconfigured (Task 9). |
| bash/PowerShell setup drift | Med | Author both in the same task; parity check in the test suite. |

## Resolved Decisions (see spec §Resolved Decisions — locked 2026-06-05)
- Relay-server home: **in this repo** (`team-plugins/teammate-relay/server/`) for v1.
- Daemon lifecycle: **OS-autostart offered-and-confirmed ONCE at onboard** (then zero per-session action); session start only health-checks + warns, never silently spawns (read-only/consent contract). Net manual cost: one confirm.
- Keychain with `0600` fallback.

## Round-2 folded findings (two independent reviewers, both REVISE)
The spec's **§Round-2 Review Hardening Log** is the authoritative list. Task-level deltas below already incorporate: concrete Noise-`IK` handshake + KCI/UKS/restart-replay tests (Task 1); server-signed/pinned JWT + thumbprint + revocation-on-connect-and-per-message + token TTL (Task 2); injection reframed to *human-gate-load-bearing, both directions* (Task 0b/11); per-file `memory-plugins/`-hardcode fixes + "relay configured" predicate + conditional registration (Task 0c); `update.{sh,ps1}` server patching (new Task 0d); `!keys/*.pub` + `status.sh` relay + init phase (Task 10); server-restart-volatility + platform matrix + operator health (Task 12).

---

## Phase 0 — Contract, crypto & safety boundaries (RISK-FIRST)

### Task 0: Wire protocol + message schema (contract-first)
**Files:**
- Create: `.sumela/team-plugins/teammate-relay/PROTOCOL.md` (frame types `hello`, `enroll`, `auth`, `msg`, `ack`, `receipt`, `presence`, `error`; JSON schema each; field constraints; **in-payload signed counter+timestamp** rule; **atomic write-to-temp+rename** rule for file-queue)
- Create: `.sumela/team-plugins/teammate-relay/requirements.txt` (`websockets`, `pynacl`, `pyjwt`, `plyer` — all pinned; `plyer` soft-imported)
- Test: `tests/test_schema.py`
- [ ] Step 1 (TDD): failing tests — valid frames parse; malformed/oversized/control-char frames rejected at the boundary.
- [ ] Step 2: run, expect FAIL.
- [ ] Step 3: implement `schema.py` (strict validators; max 16 KiB; reject unknown fields).
- [ ] Step 4: run, expect PASS.
- [ ] Step 5: `git add`. DO NOT commit.

### Task 0b: Injection-safety boundary (C6 — moved to Phase 0; highest agent-specific risk)
**Files:** Create `client/untrusted.py` (the ONE function that wraps relayed content as inert, quoted, schema-checked data); Test `tests/test_injection.py`
- [ ] Step 1 (TDD): red-team tests — payloads ("ignore previous instructions", fake tool-call JSON, control chars, 10 MB blob) come out as inert quoted data; oversized rejected; the wrapper exposes content ONLY as a data value, never a string spliced into instructions. Test **both** directions (question and answer).
- [ ] Step 2: run, expect FAIL.
- [ ] Step 3: implement the boundary; document the hard rule "relayed content reaches an agent only as a tool result/data param" in PROTOCOL.md.
- [ ] Step 4: run, expect PASS.
- [ ] Step 5: `git add`.

### Task 0c: Trust anchors — CODEOWNERS + `team-plugins/` recognition across ALL hardcoded sites (C3/I6 + ops-C1/I2/I3 — prerequisite)
> Ops review: `memory-plugins/` is hardcoded in ~9 places, NOT one classifier. This task covers every site.
**Files:** Create `CODEOWNERS`; Modify `scripts/reconcile-registry.py` (×2: `--stats` count L~146 + orphan exclusion L~13/184), `scripts/validate-structure.sh` (§7 README assert, §8 two-name plugin loop, §9 skill-count drift), `scripts/status.sh` (L~175 plugin loop), `scripts/setup.sh` (L~912) / `scripts/setup.ps1` (L~840), `scripts/auto-update-memory.py` (L~213)
- [ ] Step 1: add CODEOWNERS gating `**/teammate-relay/keys/**`, **`**/teammate-relay/relay-config.md` (it pins the server JWT verify-key — R3-sec-I1)**, + the skill surface; define the machine-detectable **"relay configured" predicate = presence of `.sumela/team-plugins/teammate-relay/relay-config.md`**.
- [ ] Step 2: at each hardcoded `memory-plugins/` site, decide + implement whether relay shares the behavior; in `reconcile-registry.py` the only real change is **`--stats`: classify `team-plugins/*/SKILL.md` as a conditional/plugin entry EXCLUDED from the `loadable_skills` core count** (else enabling relay trips `validate-structure.sh` §9 drift) — orphan detection is already report-only/skills-dir-only, no change needed there; update README skill-count markers.
- [ ] Step 3: `validate-structure.sh` asserts CODEOWNERS exists **when relay configured**; parity + structure pass in ALL THREE static states — **absent / present-unconfigured / configured** — AND the **register-then-decline transition** (enable then decline must leave no dangling registry entry → no §2 path-check failure) (R3-fw-I2, tested).
- [ ] Step 4: run `reconcile-registry.py --check` + `validate-structure.sh --post-setup` in all three states, expect PASS.
- [ ] Step 5: `git add`.

### Task 0d: `update.{sh,ps1}` must ship + patch the in-repo server, gated for decliners (ops-C2)
> Critical: a security server that `update.*` never refreshes is unpatchable. But naive inclusion pushes relay onto teams that declined.
**Files:** Modify `scripts/update.sh` (`CORE_DIRS` L~107-117, `plugin_absent()` L~139-141), `scripts/update.ps1` (L~107-110)
- [ ] Step 1: add `team-plugins` to `CORE_DIRS` AND extend the `plugin_absent()` opt-in gate to `.sumela/team-plugins/*/*` so a declining team is NOT given relay code on update.
- [ ] Step 2: test — update on a relay-enabled clone refreshes the server; update on a decliner does NOT introduce `team-plugins/`.
- [ ] Step 5: `git add`.

### Task 1: Crypto module — E2E identity WITH forward secrecy (C1) + replay defense (C4)
**Files:** Create `client/crypto.py`, `client/keystore.py`; Test `tests/test_crypto.py`
- [ ] Step 1 (TDD): tests — Ed25519 identity sign/verify; **Noise-`IK` (or `crypto_kx`+signed-prologue) handshake where the identity signature covers `sender_id‖recipient_id‖eph_pub‖session_id`**; **KCI + unknown-key-share + identity-misbinding tests must fail closed**; round-trip + tamper + wrong-recipient; **forward-secrecy test (old frame undecryptable with leaked long-term key)**; **replay-across-restart test — durable per-`session_id` high-water counter; a restart must NOT reset to 0 and re-accept old frames**; frames from unknown/expired `session_id` rejected.
- [ ] Step 2: run, expect FAIL.
- [ ] Step 3: implement with vetted primitives only (NO hand-rolled crypto); private key → OS keychain (`keyring`), `0600` fallback **that refuses to write into a non-gitignored / wrong-perm path (M-2)**; identity pubkey → `keys/<dev-id>.pub`; **recipient keys resolved from `origin/main` (I7)**; **TOFU fingerprint pin stored in the keychain (or identity-signed), fails closed, never silently re-pinned (I-1)**; **the per-session_id high-water counter is persisted with temp+rename+fsync atomicity (R3-M1) so a crash mid-update can never roll it backward and re-open the replay window**.
- [ ] Step 4: run, expect PASS.
- [ ] Step 5: `git add`.

## Checkpoint: After Tasks 0-1 — schema, injection boundary, trust anchors, crypto(+FS+replay) tests green. Contract + safety frozen. Review (Correctness & Security lane) before building on it.

---

## Phase 1 — Relay server (blind router)

### Task 2: Auth — per-member enrollment tokens + pinned-alg session JWT (C5/I8/M5)
**Files:** Create `server/auth.py`; Test `tests/test_auth.py`
- [ ] Step 1 (TDD): tests — valid enrollment token (with **TTL + rotation**, I-2) bound to pubkey on first connect ⇒ session token; **token forged with `alg:none`/confused alg ⇒ REJECT (C5)**; **session JWT is server-signed and the server verify-key is pinned client-side; a token from an unpinned key ⇒ REJECT (I-3)**; token carries member-pubkey thumbprint so **identity rotation invalidates old tokens (I-3)**; wrong/leaked-other-member token ⇒ reject (I8); expired ⇒ reject; refresh works; **revocation checked on connect AND per-message, not only force-disconnect; revoked member's still-valid cached JWT rejected on fresh connect (I-2)**; emergency server-side block works independent of the `.pub`-removal PR; clock-skew leeway does not widen the in-payload replay window (M3).
- [ ] Step 2: run, expect FAIL.
- [ ] Step 3: implement: enrollment→pubkey binding + TTL; **server-signed JWT, pin EdDSA, always pass `algorithms=`, reject `none`, pin server verify-key, embed pubkey thumbprint**; full lifecycle (issue/expiry/refresh/per-member + emergency revocation, revocation-list consulted on connect + per-message + force-disconnect).
- [ ] Step 4: run, expect PASS.
- [ ] Step 5: `git add`.

### Task 3: Presence + per-(sender,recipient) fair offline queue (I3/M2)
**Files:** Create `server/presence.py`, `server/queue.py`; Test `tests/test_queue.py`
- [ ] Step 1 (TDD): tests — connect/disconnect updates presence; offline recipient ⇒ enqueue (ciphertext only); reconnect drains in order; TTL expiry drops + emits "expired"; **bound is per-(sender,recipient) fair-shared so one spammy sender can't evict a victim's queued items (M2)**; client acks only after durable local write, ack-then-crash re-delivers (I3); queue never stores plaintext.
- [ ] Step 2: run, expect FAIL.
- [ ] Step 3: implement in-memory presence + per-pair bounded TTL queues.
- [ ] Step 4: run, expect PASS.
- [ ] Step 5: `git add`.

### Task 4: WSS router core + rate-limit + loop-guard + E2E delivery receipts (I5)
**Files:** Create `server/relay_server.py`; Test `tests/test_router.py`
- [ ] Step 1 (TDD): tests — authed `msg` to online recipient routed verbatim (ciphertext untouched); **no decryption path exists** (blind-server property); rate limit trips; loop-guard (v1: no autonomous auto-relay — caps rapid repeated asks, M-3); client cannot send as another id; recipient-scoped delivery only; **drop-after-claimed-delivery caught by missing recipient-signed `receipt`; sequence-numbered receipt chain detects reorder; a "should-have-been-delivered" timeout escalates to the human (C-4/I5)**. (Documented residual: a server lying "offline, queued" indefinitely — covered by the timeout escalation, not fully prevented.)
- [ ] Step 2: run, expect FAIL.
- [ ] Step 3: implement asyncio WSS server wiring auth + presence + per-pair queue + schema; reject `ws://`; enforce limits; relay recipient-signed sequenced receipts + the delivery-timeout escalation. **Pin the parameters in PROTOCOL.md (R3-sec-I2): default delivery timeout, receipt-chain cadence, and the explicit honest rule — "the asker cannot distinguish genuinely-offline from server-withheld, so it escalates to the human on timeout regardless of the server's offline claim."** (No size-padding in v1 — metadata residual documented in spec criterion 3.)
- [ ] Step 4: run, expect PASS.
- [ ] Step 5: `git add`.

### Task 5: Container + compose (hardened) + first-run bootstrap
**Files:** Create `server/Dockerfile`, `server/docker-compose.yml`, `server/entrypoint.sh`
- [ ] Step 1: non-root, read-only FS, only WSS port, healthcheck; first run generates + prints relay URL hint + team join-secret.
- [ ] Step 2: verify `docker compose up` starts and healthcheck passes; `ws://` config refused.
- [ ] Step 5: `git add`.

## Checkpoint: After Tasks 2-5 — server unit tests green; container boots hardened; blind-server property test passes. Review before client work.

---

## Phase 2 — Client daemon + agent CLIs

### Task 6: Client daemon (socket + presence + atomic file-queue IPC + single-instance lock)
**Files:** Create `client/relay-daemon.py`, `client/relay-ctl.py`; Test `tests/test_daemon.py` (against a stub server)
- [ ] Step 1 (TDD): tests — daemon connects + authenticates + heartbeats; incoming `msg` decrypted, **durably written then acked** (I3), routed through the Task-0b untrusted wrapper into `.sumela/.relay/inbox/<id>.json` via **write-temp+atomic rename (I4)** + notification fired; outbox watcher only reads atomically-renamed files; reconnect/backoff on drop; **second daemon instance refuses to start (pidfile/`flock`, I3)**; `relay-ctl status` reports state. No localhost port opened.
- [ ] Step 2: run, expect FAIL.
- [ ] Step 3: implement; inbox is canonical (notification best-effort, soft-import).
- [ ] Step 4: run, expect PASS.
- [ ] Step 5: `git add`.

### Task 7: Agent-facing CLIs (ask / inbox / answer) — committed-role routing + explicit accept (I1/I2)
**Files:** Create `client/ask.py`, `client/inbox.py`, `client/answer.py`; Test `tests/test_cli.py`
- [ ] Step 1 (TDD): tests — `ask --to`/`--domain` writes a well-formed outbox entry (atomic); **`--domain` resolves ONLY against the committed CODEOWNERS-gated role map, never self-asserted `local.md` domains (I2)**; **default = asker selects ONE holder before send; fan-out is opt-in (`--fanout`) and documents that every holder then sees the question (I-4)**; on fan-out, **the asker must explicitly accept one answer to close; all received answers shown before resume; arrival order never auto-resolves (I1)**; ambiguous/no-holder ⇒ actionable error; `inbox list` shows pending; `answer <id>` writes reply; unknown id ⇒ error.
- [ ] Step 2: run, expect FAIL.
- [ ] Step 3: implement (CLIs only touch file-queue atomically; never the socket directly).
- [ ] Step 4: run, expect PASS.
- [ ] Step 5: `git add`.

## Checkpoint: After Tasks 6-7 — end-to-end on two local daemons against the real server: A asks, X receives, X answers, A receives. Online + offline paths verified. Review before framework wiring.

---

## Phase 3 — Skill + routing

### Task 8: `teammate-relay` skill + registry
**Files:** Create `.sumela/team-plugins/teammate-relay/SKILL.md`, `README.md`, `relay-config.example.md`; Modify `.sumela/SKILL_REGISTRY.md`
- [ ] Step 1: write SKILL.md (frontmatter `name`/`description` advertising the user-intent trigger; body: ask-side workflow [detect ambiguity → resolve target → ask → park → resume], answer-side workflow [surface inbox → discuss in Window 1 → `answer` in Window 2], **human-gate-load-bearing injection rule + no side effect without approval (both directions)**, offline/degrade behavior).
- [ ] Step 2: **register `teammate-relay` in `SKILL_REGISTRY.md` CONDITIONALLY — only when relay is enabled (via `setup-relay`, mirroring `register_plugin()`); `init-sumela` strips it when declined (I4)** so a declining team ships no dangling skill. Then `reconcile-registry.py --check` passes in all three states.
- [ ] Step 5: `git add`.

## Phase 4 — Setup + init/onboard wiring (cross-platform)

### Task 9: `setup-relay.{sh,ps1}` + structure-validation awareness
**Files:** Create `scripts/setup-relay.sh`, `scripts/setup-relay.ps1`; Modify `scripts/validate-structure.sh`, `scripts/reconcile-registry.py`
- [ ] Step 1: setup mirrors `setup-memory.*` (deps → optional local Docker server [confirm] → register skill → start daemon [confirm]); idempotent; both shells at parity.
- [ ] Step 2: the `team-plugins/` classifier awareness is built in Task 0c — here just confirm `setup-relay` registers/deregisters cleanly and parity holds **with relay absent AND present-but-unconfigured**.
- [ ] Step 3: verify `bash scripts/validate-structure.sh --post-setup` passes in both states.
- [ ] Step 5: `git add`.

### Task 10: `init-sumela` + `onboard-sumela` + `.gitignore` + `sumela-prompt.md` + `status.sh`
**Files:** Modify `.sumela/skills/init-sumela/SKILL.md`, `.sumela/skills/onboard-sumela/SKILL.md`, `.sumela/sumela-prompt.md`, `.gitignore`, `scripts/status.sh`/`.ps1`
- [ ] Step 0 (R3-I1 secret-exposure fix): **the `0600` keychain-fallback private key lives in the fully-gitignored `.sumela/.relay/` runtime dir — NOT in `keys/`.** `keys/` holds ONLY public `<dev-id>.pub` (already trackable — no `*.pub` ignore exists, so the previously-planned `!keys/*.pub` was a no-op and is dropped). Verify with a test: a generated fallback private key is git-ignored AND a `.pub` is trackable. Gitignore the enrollment-token cache + `.sumela/.relay/`. Also add a relay section to `status.sh`/`.ps1` (daemon up? config present?) so onboard reports true state (M1).
- [ ] Step 1: init — **define the exact new team-only PHASE after memory-plugin selection** (state explicitly that relay is agent-driven-install only, or also wire `setup.{sh,ps1}` `--relay` — I5); capture URL + **server JWT verify-key**; write committed `relay-config.md` (no secrets); call setup-relay.
- [ ] Step 2: onboard — detect `relay-config.md` → keygen + commit `.pub` + keychain private → **per-member enrollment token** prompt once (cached, bound to pubkey on first connect — not a shared secret) → role/domains → start daemon.
- [ ] Step 3: **`sumela-prompt.md` session-start = health-check + warn-once-if-down + OFFER to start — NEVER auto-spawn (R3-C1 fix; matches spec Resolved Decision #2 + the read-only/consent contract; a silent per-session spawn would fire in CI runs and review subagents).** The single "auto" path is the **OS-autostart offered-and-confirmed ONCE at onboard** (launchd/systemd-user/Task Scheduler). Add the "ask a teammate" routing trigger. (Net per-session manual cost: zero after the one onboard confirm.)
- [ ] Step 5: `git add`.

## Phase 5 — Security hardening + docs

### Task 11: End-to-end adversarial integration red-team (both directions)
> The injection *boundary* is built + unit-tested in Task 0b. This task is the full-system adversarial pass once all pieces exist.
**Files:** Create `tests/test_e2e_redteam.py`
- [ ] Step 1 (TDD): with the real server + two daemons — malicious **question** with injection reaching the answerer's agent; malicious **answer** with injection reaching the asker's agent on resume. **Asker-resume oracle made explicit (R3-M2): assert the answer content cannot, without human approval, alter which tools the resumed task invokes — not merely "no crash."** Key-substitution (swapped `.pub`) caught by fingerprint pin; server-drop caught by missing recipient receipt. All must fail closed, no side effect.
- [ ] Step 2: run, expect FAIL.
- [ ] Step 3: close any wiring gap surfaced (boundary already enforced in 0b).
- [ ] Step 4: run, expect PASS.
- [ ] Step 5: `git add`.

### Task 12: Docs + team-plugins README + ops runbook + platform matrix + wiki links
**Files:** Create `.sumela/team-plugins/README.md`, `server/DEPLOY.md`; Modify `docs/second-brain/wiki/_INDEX.md`, `active-project-context.md`
- [ ] Step 1: operator deploy guide — TLS/reverse-proxy/Let's Encrypt (**note the ACME inbound/outbound exception to outbound-deny, M-4**), hardening checklist, enrollment-token + identity-key rotation, **server JWT signing-key rotation procedure (clients re-pin the new verify-key via a reviewed `relay-config.md` change — without it a server key-roll fail-closes every client with no recovery path; R3-sec-I1)**, revocation; **document server-restart semantics: in-RAM presence/queue is volatile → in-flight lost, askers see TTL-expiry (M3); add a minimal operator health/metrics surface**.
- [ ] Step 2: **per-platform autostart/keychain matrix — macOS launchd / Linux systemd-user / Windows Task Scheduler, and the WSL2 (no systemd-user) / devcontainer (no keychain → 0600, daemon dies with container) / laptop-sleep (stale presence until TTL) rows (M2)**; category README mirroring memory-plugins/README.md; link artifacts in wiki.
- [ ] Step 5: `git add`.

### Task 13 (FINAL): Secret scan + code review gate
- [ ] Step 1 (M6): run `gitleaks` (or `git diff --staged` secret grep) over the staged set BEFORE review — the "accumulate, don't commit" rule means everything lands in one blob, so verify no private key / enrollment token / `.relay/` runtime file is staged and every `.pub` is CODEOWNERS-gated.
- [ ] Step 2: Invoke `requesting-code-review` skill to verify all changes against `secure-coding-standard` (mandatory Correctness & Security lane + a dedicated Data/Crypto lane) BEFORE any `git commit`.

## Checkpoint: After Tasks 11-13 — full suite green; red-team passes; review approved. Ready for human sign-off → commit → PR.
