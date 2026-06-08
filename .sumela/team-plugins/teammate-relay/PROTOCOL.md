# Teammate Relay — Wire Protocol (v1)

The authoritative contract between the client daemon, the relay server, and the agent-facing
file-queue. Frozen in Phase 0; everything downstream depends on it.

## Transport

- **WSS only** (TLS 1.2+). Plain `ws://` is rejected at config-load — there is no plaintext mode.
- All frames are UTF-8 JSON objects, **≤ 16 KiB serialized** (`MAX_FRAME_BYTES = 16384`).
- Every frame is validated by `relay_common.schema.validate_raw()` at *both* ends before use.
  Unknown top-level fields, missing required fields, wrong types, control characters in text
  fields, or oversize → hard reject (fail closed).

## Frame envelope

Every frame carries:

| field | type | meaning |
|-------|------|---------|
| `v`    | int    | protocol version (currently `1`) |
| `type` | string | one of the frame types below |
| `id`   | string | UUIDv4 — unique per frame |

## Frame types

| `type`   | direction | required fields (beyond envelope) | purpose |
|----------|-----------|-----------------------------------|---------|
| `hello`    | client→server | `client_id`, `eph_pub`, `sig`            | Noise-IK handshake init; ephemeral pubkey signed by identity key (sig binds `sender‖recipient‖eph_pub‖session_id`). |
| `enroll`   | client→server | `client_id`, `identity_pub`, `enroll_token` | First connect: bind a per-member enrollment token to the member's identity pubkey. |
| `auth`     | client→server | `client_id`, `session_token`             | Subsequent connects: present the server-signed session JWT (EdDSA, verify-key pinned client-side). |
| `msg`      | client↔server | `from`, `to`, `session_id`, `ciphertext`, `counter` | E2E payload. `ciphertext` = base64. `counter` = signed monotonic per-`session_id` replay guard (see below). |
| `ack`      | both          | `ref_id`                                 | Acknowledge receipt of a frame by its `id`. |
| `receipt`  | client↔server | `ref_id`, `from`, `to`, `last_counter`, `sig` | **Recipient-signed E2E delivery receipt.** Sequence-numbered (`last_counter`) → detects drop/reorder. Relayed to the asker. |
| `presence` | server→client | `client_id`, `state`                     | `state` ∈ {`online`, `offline`}. |
| `error`    | server→client | `code`, `message`                        | `ref_id` optional. |

## Replay defense (counter)

- The replay guard is a **signed monotonic counter inside the encrypted payload**, scoped to the
  ephemeral `session_id`. The recipient tracks a per-`(sender, session_id)` high-water mark and
  rejects any `counter ≤ last_seen`.
- A **"session" = one ephemeral key epoch.** Frames bearing an unknown/expired `session_id` are rejected.
- The high-water store is persisted with **temp-file + atomic `os.rename` + `fsync`** so a crash
  mid-update can never roll it backward and re-open the replay window. Server-side `id`-dedup is a
  convenience only; the counter is the trusted defense (the server is not trusted).

## Delivery integrity (receipts)

- Receipts are recipient-signed end-to-end (the server cannot forge them).
- A **sequence-numbered receipt chain** (recipient periodically signs `last_counter` seen from a peer)
  detects server drop/reorder.
- **Delivery-timeout escalation:** if the asker gets neither a receipt nor a definitive failure within
  the default timeout, it **escalates to the human** — *regardless of any server "offline/queued" claim*,
  because the asker cannot cryptographically distinguish "genuinely offline" from "server withheld."
  Defaults (v1): delivery timeout = **120 s**; receipt-chain cadence = **every 30 s while connected**.
  Documented residual: indefinite server "offline" lying is bounded, not prevented, by this timeout.

## File-queue IPC (agent ↔ daemon)

- The daemon and the agent-facing CLIs (`ask`/`inbox`/`answer`) communicate via
  `.sumela/.relay/inbox/` and `.sumela/.relay/outbox/` — **no localhost port is ever opened.**
- **All writes are temp-file + atomic `os.rename` into the watched dir.** A watcher never observes a
  half-written file. Filenames: `<frame-id>.json`.
- Relayed content reaching the agent is always wrapped by `relay_common.untrusted` (see Task 0b):
  it is **data, never instructions**, and can never trigger a side effect without a human approval gate.
