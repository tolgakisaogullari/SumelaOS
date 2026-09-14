---
name: secure-coding-standard
description: "Use whenever the task involves planning, writing, or reviewing code — load at spec/plan time (brainstorming and writing-plans count), not first-code time — and unconditionally when it touches user input, forms, APIs, database queries, authentication, authorization, passwords, file uploads, permissions, secrets, CORS, rate limiting, or any external/untrusted data."
---

<activation_rules>
- NEVER wait for a security review to load this skill. Load it DURING `brainstorming`, `writing-plans`, `executing-plans`, or `test-driven-development` if the task touches external data or state changes.
- This skill acts as a permanent constraint layer over your standard coding skills. It is a RIGID skill: follow it exactly, do not adapt away discipline.
- Two sibling references, read on the branch that needs them — never preemptively, never instead of this file:
  - `owasp-playbook.md` — per vulnerability class: the control that works, and the broken fix that looks like it. Read the sections for every category Step 2 marks REACHABLE, before writing that code.
  - `agent-specific-threats.md` — failure modes that exist because an LLM, not a human, is writing this code. Read once per task that adds a dependency, calls a model at runtime, or generates infrastructure, CI, container, or IAM configuration.
</activation_rules>

<human_confirmation_required>
STOP and get explicit user approval before proceeding with any of the following. These are security-boundary changes that cannot be automatically verified:
- **WEAKENING OR REMOVING AN EXISTING CONTROL.** Deleting or bypassing an auth/authz check, `verify=False`, `NODE_TLS_REJECT_UNAUTHORIZED=0`, `rejectUnauthorized: false`, `--no-verify`, `SUMELA_DISABLE_SECRET_SCAN=1`, `# nosec`, `eslint-disable security/*`, widening a permission or an allowlist, loosening a validator, commenting out a guard "to see the test pass". This is the single most frequent way an agent introduces a vulnerability, and it never looks like a security change — it looks like unblocking yourself. There is no "temporary": the commit is permanent the moment it lands. Step 7 makes you grep for it, because this block is at the top of a file you loaded hours ago.
- Adding new authentication flows or modifying existing auth logic
- Introducing a new category of sensitive data storage (PII, payment info, health data)
- Adding a new external service integration, third-party API, or ANY new outbound egress that sends data across a trust boundary
- Modifying CORS configuration or adding new allowed origins
- Introducing new file upload endpoints or handlers
- Changing rate limiting policies or account lockout thresholds
- Granting elevated permissions, new roles, or new admin capabilities
- Choosing or changing a cryptographic primitive, a key, or how a secret is stored

HOW TO ASK — one short block, never a paragraph of hedging:
`WHAT changes` · `BLAST RADIUS if it is wrong` · `the safer alternative you rejected, and why`. Then STOP and wait.

If the user is unreachable, you do NOT have approval. Implement the safe alternative, and record the deferred decision in the plan. Silence is never consent.
</human_confirmation_required>

<execution_workflow>
Execute these security constraints strictly. NEVER trust user input. Security overrides all other implementation preferences.

1. THREAT BOUNDARY ANALYSIS — produce it, do not merely think it.
   - Identify ALL external inputs: API payloads, URLs, headers, cookies, query parameters, file uploads, webhooks, queue messages, and any config or env value read at runtime.
   - Identify ALL sensitive data flows (PII, credentials, API keys, financial/health data) and every place they are stored, logged, cached, or leave the process.
   - Identify the TRUST BOUNDARIES the change crosses, and name the attacker at each one: anonymous internet, authenticated user of ANOTHER tenant/account, insider, compromised dependency.
   - **WRITE IT DOWN**, using the section the receiving skill already requires: the spec's **Security Considerations** section (`brainstorming`) or the plan's **Security Constraints** header (`writing-plans`). With no spec and no plan — a direct fix, `executing-plans` on an existing plan, `test-driven-development` — put it in the commit body and at the top of `{DESCRIPTION}` at review time. An analysis that lives only in this context window is gone by review time, and `requesting-code-review` fills `{SECURITY_MANDATE}` with a GENERIC mandate: your written block is the only thing that makes the review specific to THIS change.
   - REDACT while you write. A stack trace or sample record pasted into a spec, plan, or review report carries the connection string or the real PII with it, into a file nobody re-reads.

2. SCOPE THE SURFACE (mechanical — before writing code, then AGAIN before Step 7).
   For each row, decide REACHABLE or N/A, and **PRINT the verdict for all twelve rows**: `<category> — REACHABLE: <file:line in this change that triggers it>` or `<category> — N/A: <what you checked, and why nothing in this change reaches it>`. An unprinted triage did not happen, and an N/A with no reason is a skip, not an answer.

   | Category is REACHABLE when the change… | Example trigger |
   |---|---|
   | Injection / deserialization / parsing | builds a query, command, or template, or parses untrusted bytes |
   | Output rendering / XSS | returns, renders, or templates data into HTML, a document, or a CSV |
   | Access control | reads or writes a record identified by a client-supplied id |
   | Mass assignment | binds a request body to a persisted model or entity |
   | AuthN / session / crypto | issues, validates, stores, or compares a credential |
   | State & concurrency | mutates a balance, counter, quota, or a row two requests could touch at once |
   | File handling | accepts, writes, reads, or extracts a path or archive |
   | Outbound requests | fetches a URL, redirects, or calls a third party |
   | Abuse prevention | adds an endpoint that is expensive, anonymous, or enumerable |
   | Transport / headers / CORS | adds or changes an HTTP surface |
   | Supply chain | adds, upgrades, or pins a dependency |
   | Logging / monitoring | handles a security-relevant event or writes a log line |

   Then re-check any Step 3 bullet no row names. Marking a category N/A is not permission to skip it — it is what makes the REACHABLE ones non-negotiable. A checklist that claims to apply everywhere is one you learn to tick without reading. Re-run this after implementation: the code you wrote may have reached a category the plan did not.

3. STRICT IMPLEMENTATION CONSTRAINTS (details and the broken-fix traps: `owasp-playbook.md`)
   - **Injection:** MUST use parameterized queries / prepared statements / ORM bindings. Concatenating or interpolating a value into SQL, shell, template, or LDAP syntax is FORBIDDEN — including a value that came from your own database (second-order injection). For subprocesses, pass an argv array; never a built string through a shell. For document stores, parameterization does not exist: CAST every value to its expected scalar type and reject objects/arrays, or `{"$ne":null}` becomes a login bypass.
   - **Path traversal:** NEVER "sanitize" a path by stripping `..` — strip-based fixes are bypassable (`....//`, encodings, unicode, symlinks) and are the classic vulnerable pattern. RESOLVE the final path (`realpath`/`Path.resolve`) and VERIFY CONTAINMENT under an allowlisted base directory before opening it. Same rule for every archive entry (zip-slip).
   - **XSS:** encode at the SINK, context-aware (HTML body vs attribute vs JS vs URL vs CSS). NEVER build markup by concatenation; never pass untrusted data to `innerHTML` / `dangerouslySetInnerHTML` / `v-html`. Sanitize HTML only with a maintained library, NEVER with a regex.
   - **CSRF:** for cookie/session-based state-changing actions, MUST use a per-session synchroniser token bound server-side, PLUS `SameSite` and an `Origin` check that fails closed. `SameSite=Lax` alone is not the control — it does not cover top-level GET state changes or a sibling subdomain. For bearer-token mobile/API flows, document why CSRF is not the active threat and verify token validation, CORS, and origin assumptions instead.
   - **Access control & IDOR (BOLA):** MUST verify both AuthZ (role/claim) AND ownership (does this caller own resource X?). Scope the query BY the caller's identity and tenant in the `WHERE` clause — do not fetch-by-id then compare, and never trust a tenant id sent by the client. Enforce at object, field, and function level. Default to deny: an endpoint with no explicit rule is closed.
   - **Mass assignment:** bind requests to an explicit DTO/allowlist. NEVER bind a request body straight onto an entity/model — that is how `isAdmin`, `role`, `balance`, and `userId` get set by the client.
   - **SSRF & CORS:** NEVER blindly fetch a user-supplied URL — allowlist by host, re-validate after every redirect, and block loopback, link-local/metadata, and private ranges for EVERY address the name resolves to. NEVER reflect the `Origin` header back, match origins by exact string (never `endsWith`/`includes`), never `*` with credentials, and no wildcard CORS in ANY environment reachable from the internet.
   - **File uploads:** the multipart `Content-Type` and the filename extension are attacker-supplied and prove nothing — but neither does a magic-byte prefix alone (a GIF header in front of PHP is a valid GIF). Magic bytes are the minimum filter; CONTAINMENT is the control: re-encode images through a decoder, generate the stored filename server-side, cap size while streaming, store outside the web root or in a non-executable bucket, and serve with `Content-Disposition: attachment` + `X-Content-Type-Options: nosniff`.
   - **Secrets & logging:** NEVER hardcode a secret. NEVER log credentials, tokens of any kind, session ids, raw request bodies, or PII. Build an ALLOWLIST of fields that may be logged — a denylist silently misses the next field someone adds.
   - **Crypto:** passwords → a tuned slow KDF: Argon2id or scrypt (memory-hard), or bcrypt with a tuned cost factor (bcrypt is CPU-hard, not memory-hard). Tokens, ids, and reset codes → a CSPRNG (`secrets`, `crypto.randomBytes`); NEVER `Math.random()`, `rand()`, a timestamp, or a sequential id. Secret comparison → constant-time. Encryption → AEAD (AES-GCM, ChaCha20-Poly1305) with a unique nonce per message. Never roll your own, never disable certificate verification.
   - **Session & token lifecycle:** pin the accepted signing ALGORITHM explicitly — reject `alg: none` and never let the token pick its own algorithm (algorithm confusion is a full auth bypass). Validate issuer, audience, expiry, and signature. Rotate the session id on login and on privilege change (session fixation). Make logout and revocation actually invalidate server-side. Password-reset tokens: single-use, short TTL, stored hashed.
   - **Abuse prevention:** rate limiting / throttling / lockout on authentication, password reset, signup, and any expensive or enumerable endpoint. Key it on something the attacker cannot spoof — a raw `X-Forwarded-For` is attacker-supplied. Anti-enumeration: responses MUST NOT differ in body, status, or TIMING between "account exists" and "does not".
   - **Business logic & concurrency:** MUST prevent race conditions (TOCTOU) with database locks (`SELECT … FOR UPDATE`), atomic operations, or unique constraints on financial/state-changing endpoints. Make retryable mutations idempotent.
   - **Deserialization & parsers:** NEVER deserialize untrusted data with a format that can construct objects (`pickle`, PyYAML `load`, Java serialization, `eval`). Disable external entities in XML parsers (XXE). Bound size and nesting depth of anything you parse. Bound input length BEFORE applying a regex to it, and avoid nested quantifiers (ReDoS — anchoring does NOT fix catastrophic backtracking).
   - **Redirects:** never redirect to a user-supplied URL; allowlist destination names or known internal routes (open redirect powers phishing and OAuth code theft).
   - **Supply chain & headers:** NEVER introduce a dependency with known CVEs, and never one you have not verified EXISTS and is the package you mean (`agent-specific-threats.md`). Commit the lockfile, pin versions. Where an HTTP surface exists, configure CSP, HSTS, `X-Content-Type-Options`, and `X-Frame-Options`.
   - **Security logging & monitoring:** log security-relevant events — auth success and failure, authz denial, privilege change, admin action, credential or 2FA change — with who, what, and when, and WITHOUT the credential itself. An attack nobody can see is one nobody can respond to.

4. VALIDATION RULES (Zero Trust):
   - Validate at the EARLIEST system boundary with a schema (Zod, Joi, Pydantic, FluentValidation, or the project's equivalent) that also REJECTS unknown fields — strict mode, not "ignore extras".
   - Allowlist what is permitted; never denylist what is forbidden. Canonicalize (decode, normalize, resolve) BEFORE validating, then use the canonical value — validating one form and using another is how filters get bypassed.
   - Reject invalid data immediately with a safe error code. Do NOT attempt to "fix" or "guess" a malformed payload.

5. SECURITY VERIFICATION & ADAPTIVE TESTING (CRITICAL):
   - Verify error handling does NOT leak stack traces, framework versions, internal ids, or database structure to the client. Log the detail server-side; return an opaque message plus a correlation id.
   - **TDD EXCEPTION FOR SECURITY:** even if the user explicitly skipped `test-driven-development` for this task, if you are modifying AuthZ/AuthN logic, access controls, or any security boundary, you MUST write an automated test that ATTEMPTS THE BYPASS ("User A deletes User B's resource", "tenant A reads tenant B's row", "expired token is accepted"). The test MUST fail against the unfixed code — a test that passes before your fix proves nothing and is worse than none, because it is evidence that is not evidence.

6. CODE REVIEW PREPARATION:
   - Before invoking `requesting-code-review`, list in `{DESCRIPTION}` every security mitigation you implemented, each with its `file:line` AND the line's actual text. A mitigation you cannot quote is one the reviewer will find missing — claiming it costs you a Critical finding, not a pass.
   - Summarize the Step 1 block at the top of `{DESCRIPTION}` too. Do NOT fill `{SECURITY_MANDATE}` yourself: `requesting-code-review` Step 4 is the single filling authority for that field and supplies a generic mandate. `{DESCRIPTION}` and the plan are the channels your change-specific threat model actually travels through.
   - **The severity model is canonical in `receiving-code-review` → `<severity_model>`** (Critical / Important / Minor / Recommendations-FYI); the review lanes add the failure-chain gate that every Critical and Important must survive. Use those; do not restate or re-invent them here — a second copy drifts from the skill that owns it.
   - Prioritize practical, exploitable vulnerabilities over theoretical risk, and explicitly acknowledge controls that are correctly implemented — reinforcing a good pattern is cheaper than re-teaching it later.

7. SECURITY REVIEW CHECKLIST (pre-commit gate).
   **Control-weakening sweep first (mechanical, always — this is what makes the confirmation gate fire mid-task):**
   ```
   git diff -U0 | grep -nE 'verify=False|rejectUnauthorized|NODE_TLS_REJECT|--no-verify|nosec|eslint-disable|SuppressWarnings|type: ignore'
   git diff -U0 | grep '^-' | grep -iE 'auth|permission|validate|verify|guard|assert|policy|@requires'
   ```
   Paste both outputs. Any hit is a `<human_confirmation_required>` item: stop and ask before committing.

   Then answer EVERY `·`-separated clause below on its OWN row, in one of exactly three forms. A bare tick is not an answer, and one row per bold heading is not an answer either:
   - `- [x] <clause> — <file:line + the line's text>` or `<command + its verbatim output>`
   - `- [~] <clause> — N/A: <what you checked, and why this change cannot reach it>`
   - `- [ ] <clause> — NOT DONE: <what is missing>` ← the only honest form for a real gap. Never launder a gap into N/A.

   Stack-specific commands and framework names live in project rules under `.sumela/rules/` (e.g. `backend_standards.md`, `mobile_standards.md`); this skill defines the universal categories.

   **Authentication & Sessions:** password hashing uses a tuned slow KDF (Argon2id/scrypt/bcrypt — never plaintext, MD5, SHA1, or a bare SHA-256) · token validation pins algorithm, issuer, audience, expiry, signature · session id rotates on login and privilege change · reset tokens single-use, short-TTL, hashed · login/reset/signup carry rate limiting or lockout and are enumeration-safe in body, status, and timing · cookie/session state-changing endpoints carry a synchroniser token, or the bearer-only rationale is stated.
   **Authorization:** every endpoint requires auth or carries an explicit allow-anonymous declaration · ownership AND tenant scoping enforced inside the query, not after it · admin actions check an explicit role/claim · request bodies bind to a DTO, not to an entity.
   **Input & Output:** request DTOs validated at the boundary with unknown fields rejected · parameterized queries only, and document-store values cast to scalars · untrusted paths and archive entries resolved and containment-verified · uploads typed from content and stored non-executable outside the web root · output encoded at the sink · untrusted payloads parsed with a safe loader, bounded in size and depth · outbound URLs host-allowlisted and re-validated after redirects · error responses expose no stack trace, internal id, or schema.
   **Secrets & Config:** no secrets in committed files · `git diff --cached` AND `git diff` both reviewed for keys, tokens, passwords, and sensitive sample data · specs, plans, and review reports written this task checked for pasted credentials or real PII · runtime secrets come from a secret manager or env · no credential, token, session id, raw body, or PII reaches a log.
   **Infrastructure & Supply Chain:** security headers configured where an HTTP surface exists · CORS restricted to exact-match known origins · every dependency added in this change verified to exist and pinned, lockfile committed · dependency audit run and clean (`npm audit`, `pip-audit`, `dotnet list package --vulnerable`, per project rules) — paste the result, not the intent.
   **Logging & Monitoring:** security-relevant events are logged with actor, action, and time, and without the credential.

   A reference with no quoted text is not evidence. An item you cannot evidence is NOT done: use the third form and say so in `{DESCRIPTION}`. A reviewer finding a gap is cheap; a user finding it is not.
</execution_workflow>

<common_rationalizations>
| Rationalization | Reality |
|---|---|
| "This is an internal tool, security doesn't matter" | Internal tools get compromised. Attackers target the weakest link. |
| "We'll add security later" | Security retrofitting is 10x harder than building it in from day one. |
| "No one would try to exploit this" | Automated scanners will find it. Security by obscurity is not security. |
| "The framework handles security" | Frameworks provide tools, not guarantees. You must use them correctly. |
| "It's just a prototype" | Prototypes become production. Security habits must start on day one. |
| "It's only the dev/staging config — prod will be different" | Dev config ships. The two diverge exactly once: the day the wildcard reaches production. |
| "This value comes from our own database, so it's trusted" | It was user input before it was a row. Second-order injection is the same injection, delayed. |
| "I'll disable the check just to get the test green, then restore it" | You will not. The commit is permanent the moment it lands, and nobody reviews a line that was already there. |
| "This item doesn't really apply here" (about an item you simply skipped) | N/A means the change cannot REACH it, and you say what you checked. A gap marked N/A is a lie with a checkbox; use the NOT DONE form. |
| "I'll tick the checklist now and verify right after committing" | The gate exists because "right after" is where verification goes to die. Evidence, N/A with a reason, or NOT DONE — nothing else counts. |
| "The user asked for this quickly" | Speed is a scope decision, not a control decision. Cut features, never controls — and say which you cut. |
</common_rationalizations>
