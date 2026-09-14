---
name: secure-coding-owasp-playbook
description: "Reference for secure-coding-standard: per vulnerability class, the control that works and the broken fix that looks like it. Loaded BY the parent skill for categories marked REACHABLE. Private to its parent skill."
---

# OWASP Playbook — the control, and the broken fix that looks like it

Every entry has the same shape: **BROKEN** (the plausible fix that fails review or an attacker), **CONTROL** (what actually holds), **TEST** (the bypass to automate). Read only the sections Step 2 of `SKILL.md` marked REACHABLE.

## Contents

- [A01 Broken Access Control](#a01-broken-access-control) — IDOR/BOLA, multi-tenancy, mass assignment, CSRF, open redirect, path traversal
- [A02 Cryptographic Failures](#a02-cryptographic-failures) — randomness, comparison, encryption, password storage
- [A03 Injection](#a03-injection) — SQL, command, XSS, template
- [A04 Insecure Design](#a04-insecure-design) — race conditions, enumeration, abuse limits
- [A05 Security Misconfiguration](#a05-security-misconfiguration) — CORS, headers, error leakage
- [A06 Vulnerable Components](#a06-vulnerable-components) — CVEs, pinning, install-time execution
- [A07 Identification & Authentication Failures](#a07-identification--authentication-failures) — JWT, session fixation, reset tokens
- [A08 Software & Data Integrity Failures](#a08-software--data-integrity-failures) — deserialization, XXE, zip-slip, ReDoS
- [A09 Security Logging & Monitoring Failures](#a09-security-logging--monitoring-failures)
- [A10 SSRF](#a10-ssrf)

---

## A01 Broken Access Control

### IDOR / BOLA and multi-tenancy
- **BROKEN:** `row = db.get(Order, id)` then `if row.user_id != current_user.id: deny`. It works until one handler forgets the second line — and one always does. It also leaks existence through timing and through a 403-vs-404 difference.
- **CONTROL:** put the caller in the QUERY, not in a check after it: `db.query(Order).filter(id=id, user_id=current_user.id, tenant_id=current_user.tenant_id)` → not found is indistinguishable from not owned. In multi-tenant systems, enforce `tenant_id` in a repository base class or a DB row-level-security policy so no handler CAN forget it. NEVER read the tenant id from the request body, a header, or a JWT claim the client can influence.
- **TEST:** user A, authenticated, requests user B's id → 404. Tenant A requests tenant B's row → 404.

### Function- and field-level authorization
- **BROKEN:** hiding the admin button in the UI; checking the role in one gateway and trusting it everywhere downstream.
- **CONTROL:** every endpoint declares its requirement explicitly (`@requires_role`, policy, guard) and a route with NO declaration is DENIED by default — a framework whose default is "open unless annotated" will eventually ship an unannotated route. Filter response FIELDS by role too: an `is_internal_note` a viewer can read is the same breach as an endpoint they can call.

### Mass assignment / over-posting
- **BROKEN:** `user.update(**request.json)`, `Object.assign(entity, req.body)`, `_ = json.NewDecoder(r.Body).Decode(&user)` straight onto the persisted model. The client sets `role`, `isAdmin`, `balance`, `emailVerified`, `userId`.
- **CONTROL:** decode into an explicit input DTO carrying ONLY the fields this endpoint may change, then map field by field. Reject unknown fields rather than ignoring them, so a rename shows up as a 400 instead of a silent no-op.
- **TEST:** POST the legitimate body plus `"role":"admin"` → 400, and the stored row is unchanged.

### Open redirect
- **BROKEN:** `redirect(request.args["next"])`, with a check like `next.startswith("/")` — `//evil.com` and `/\evil.com` are both protocol-relative and both pass.
- **CONTROL:** allowlist. Preferred: a fixed map of destination NAMES → internal routes, so no URL from the client is ever used as a URL. If you must accept a path, URL-decode it, strip ASCII whitespace and control characters, then require ALL of: empty scheme, empty netloc, empty userinfo, and a path matching `^/[^/\\]` — one leading slash whose next character is neither `/` nor `\`. Both narrower checks fail: `/\evil.com` has an empty host and one leading slash, and `https:/evil.com` has an empty host too — browsers normalise both to `evil.com`. Never accept an absolute URL from a client. This is what turns a phishing link into a credible one and what steals OAuth codes via `redirect_uri`.
- **TEST:** `//evil.com`, `/\evil.com`, `https:/evil.com`, `https://evil.com`, `/%09/evil.com` → all rejected; `/dashboard` → accepted.

### CSRF
- **BROKEN:** `SameSite=Lax` alone — it does not stop a top-level GET that changes state, does not isolate sibling subdomains (`SameSite` is site-scoped, not origin-scoped), and Chrome exempts recently-set cookies from Lax on top-level POSTs. Also broken: a double-submit cookie when an attacker with any subdomain foothold can set the cookie, and a `Referer` check that passes when the header is absent.
- **CONTROL:** a per-session synchroniser token bound server-side, required on EVERY state-changing request, plus `SameSite=Lax|Strict` as defence in depth, plus an `Origin` check that FAILS CLOSED when the header is missing. State changes never happen on GET.
- **TEST:** replay a valid session cookie from a cross-origin form with no token → 403.

### Path traversal
- **BROKEN:** `name.replace("../", "")` (survives `....//`), blocking `..` before URL-decoding, checking the string before symlink resolution, or `os.path.join(base, user_path)` — an absolute `user_path` silently DISCARDS `base`.
- **CONTROL:** resolve, then verify containment against the resolved base:

```python
from pathlib import Path

def safe_open(base_dir: str, user_path: str):
    """Resolve first, then prove containment. Never inspect the raw string."""
    base = Path(base_dir).resolve(strict=True)
    # `base / user_path` DISCARDS base when user_path is absolute — the same trap as
    # os.path.join. That is safe only because the containment check below catches it;
    # never copy this join into code without the check. strict=False: the file may not
    # exist yet (uploads), and symlinks in existing components still resolve.
    target = (base / user_path).resolve(strict=False)
    if not target.is_relative_to(base):        # Python 3.9+; else compare parts
        raise PermissionError(f"path escapes base: {user_path!r}")
    return target.open("rb")
```

- **LIMITS — state them, do not over-claim.** This proves containment AT CHECK TIME. It does not close the TOCTOU window between the check and `open()`: an attacker who can create symlinks inside `base` — exactly an upload or extraction directory — can swap a component in between, and the race is winnable in a handful of attempts. Where that is possible, open relative to a directory file descriptor you already hold (`os.open(..., dir_fd=)`), use `O_NOFOLLOW` per component, and keep the directory unwritable by the request path. On Windows it also does not stop reserved device names (`CON`, `NUL`, `COM1`) or NTFS alternate data streams (`good.txt::$DATA`), both of which pass containment.
- **TEST:** `../../etc/passwd`, `/etc/passwd`, and a symlink inside `base` pointing out → `PermissionError`. `....//....//etc/passwd` and `%2e%2e%2f…` resolve INSIDE `base` and simply do not exist — that is the check working, not a bypass. Assert that no input ever OPENS a file outside `base`.

---

## A02 Cryptographic Failures

- **Randomness — BROKEN:** `Math.random()`, `rand()`, `uuid1()`, `time.time()`, or an incrementing id for a reset token, session id, API key, invite code, or OTP. These are predictable: V8's `Math.random()` state is recoverable from a handful of observed outputs, which makes every later token derivable. **CONTROL:** a CSPRNG — `secrets.token_urlsafe(32)`, `crypto.randomBytes(32)`, `RandomNumberGenerator`. 128 bits minimum for anything that authenticates.
- **Comparison — BROKEN:** `if token == stored`, `hmac_digest == signature`. Early-exit comparison leaks the correct prefix through timing. **CONTROL:** constant-time / timing-safe compare (`hmac.compare_digest`, `crypto.timingSafeEqual`).
- **Encryption — BROKEN:** AES-ECB (patterns survive), AES-CBC with no MAC (padding-oracle, bit-flipping), a hardcoded or reused IV/nonce, a key in source or in the same store as the ciphertext. **CONTROL:** AEAD only — AES-GCM or ChaCha20-Poly1305 — with a UNIQUE nonce per message (random 96-bit is safe to ~2^32 messages per key — rotate before that, or use XChaCha20-Poly1305 whose 192-bit nonce removes the limit; or a counter you can prove never repeats. Nonce reuse under GCM destroys both confidentiality and authenticity). Keys come from a KMS/secret manager and are rotatable.
- **Password storage — BROKEN:** MD5, SHA-1, SHA-256, "salted SHA-256", a homemade stretch loop. Fast hashes are the point of GPU cracking rigs. **CONTROL:** Argon2id (preferred), scrypt, or bcrypt with a work factor tuned to ~250ms on production hardware, re-tuned yearly. Cap bcrypt input at 72 bytes deliberately, never silently — and if you pre-hash to lift the cap, hex- or base64-encode the digest first: a raw digest containing `\x00` truncates the password in C implementations.
- **In transit:** TLS verification is never disabled — not in a test, not behind a feature flag, not "because the cert is self-signed". Pin the CA or add the internal root instead.

---

## A03 Injection

- **SQL — BROKEN:** f-strings, `+`, `%`, or an ORM's `raw()`/`text()` with interpolation. A value read back from your own database is still untrusted (second-order injection). Identifiers (table/column/sort direction) cannot be parameterized — **CONTROL:** map them through a fixed allowlist dict; never pass a client string into `ORDER BY`.
- **Command — BROKEN:** `os.system`, `subprocess.run(cmd, shell=True)`, backticks with any interpolated value; "escaping quotes" by hand. **CONTROL:** argv arrays with `shell=False`, absolute binary paths, and an allowlist for any user-influenced argument. Watch for arguments that begin with `-`. On Windows, argv is NOT sufficient for `.bat`/`.cmd` targets — those still route through `cmd.exe` (BatBadBut, CVE-2024-1874 and siblings); avoid invoking batch files with untrusted arguments at all.
- **XSS — BROKEN:** a regex "sanitizer", escaping once for HTML then placing the value inside an attribute, `href={userUrl}` (allows `javascript:`), `innerHTML`, `dangerouslySetInnerHTML`, `v-html`. **CONTROL:** encode at the SINK with the sink's own rules; render user HTML only through a maintained sanitizer (DOMPurify) with an allowlist config; validate URL schemes against `https|http|mailto`; add CSP as defense in depth, never as the primary control.
- **NoSQL / operator injection — BROKEN:** passing a parsed request field straight into a query document (`{email: body.email, password: body.password}`). No string is concatenated, so "parameterized queries" does not apply — there is nothing to parameterize. `{"$ne":null}`, `{"$gt":""}` and `{"$regex":"^a"}` turn equality into match-anything, and `$where`/`mapReduce` are server-side JS execution. **CONTROL:** validate the body against a strict schema first, CAST each value to its expected scalar (`String(body.email)`), reject any value that is an object or an array, and disable `$where`/`mapReduce`. **TEST:** log in with `{"email":{"$gt":""},"password":{"$ne":null}}` → 400, never 200.
- **Template / expression injection — BROKEN:** `render_template_string(user_input)`, building a Jinja/Handlebars/Thymeleaf template from user data, or passing user data into a spreadsheet cell (`=cmd|…` CSV injection). **CONTROL:** templates are static; user data is only ever a VARIABLE passed to them. Prefix CSV cells starting with `= + - @` with `'`.

---

## A04 Insecure Design

- **Race conditions (TOCTOU) — BROKEN:** `if balance >= amount:` then a separate `update`. Two concurrent requests both read the old balance. Rate limits, coupon redemption, invite acceptance, and "one vote per user" all fail the same way. **CONTROL:** a single atomic statement (`UPDATE … SET balance = balance - :amt WHERE id = :id AND balance >= :amt` and check the affected-row count), a `SELECT … FOR UPDATE` inside a transaction, or a UNIQUE constraint that makes the second attempt impossible. Make retried mutations idempotent with a client-supplied idempotency key.
- **Account enumeration — BROKEN:** "No account with that email", a 404 on reset, a different response TIME because the found branch hashes a password and the not-found branch returns immediately. **CONTROL:** identical body, identical status, and comparable timing on both branches — do the dummy hash work in the not-found branch. Signup, reset, login, and invite all need this. Stack-specific detail (including the frontend counterpart) lives in `.sumela/rules/security_protocol.md` → Anti-Enumeration Pattern; do not restate it here.
- **Abuse limits:** design them before the endpoint exists. Anything anonymous, expensive (report generation, search, export), or enumerable needs a limit keyed on identity or a VERIFIED client IP — the left-most `X-Forwarded-For` entry is attacker-supplied; take the hop your proxy actually sets.

---

## A05 Security Misconfiguration

- **CORS — BROKEN:** `Access-Control-Allow-Origin: *` with `Allow-Credentials: true` (browsers reject it, so someone "fixes" it by reflecting), reflecting `Origin` unvalidated, or matching with `origin.endsWith("example.com")` — `evil-example.com` and `notexample.com` pass; `example.com.evil.com` passes the equally common `origin.includes("example.com")`. **CONTROL:** an exact-match allowlist of full origins including scheme and port, from config.
- **Headers:** CSP (no `unsafe-inline`/`unsafe-eval`; use nonces), HSTS with a long max-age, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY` or `frame-ancestors`, `Referrer-Policy`. Mark N/A honestly when there is no HTTP surface — a CLI does not need CSP, and pretending otherwise teaches false ticking.
- **Error leakage — BROKEN:** returning the exception, the stack trace, the ORM's generated SQL, or an internal id. **CONTROL:** log the detail server-side with a correlation id; return an opaque message plus that id. Disable debug/dev error pages by default, so a missing env var fails CLOSED.

---

## A06 Vulnerable Components

- Run the audit and PASTE its output (`npm audit`, `pip-audit`, `dotnet list package --vulnerable`, `cargo audit`, `govulncheck`). "I intended to run it" is not evidence.
- Pin versions and commit the lockfile: a floating range makes the build non-reproducible and lets a compromised patch release land silently.
- Install-time execution is code execution: prefer `npm ci --ignore-scripts` in CI, and treat a new package's postinstall script as a change that needs review.
- Before adding ANY dependency you did not verify exists, read `agent-specific-threats.md` — package names you recall are not package names that exist.

---

## A07 Identification & Authentication Failures

- **JWT — BROKEN:** `jwt.decode(token, verify=False)`, decoding without an explicit `algorithms=[...]`, or accepting whatever the token's header declares. That is `alg: none` (no signature at all) and algorithm confusion (an RS256 public key — which is public — used as an HS256 shared secret). Both are complete authentication bypasses. **CONTROL:** pass an explicit single-algorithm allowlist, validate issuer, audience, expiry, and not-before, and use a key resolved by `kid` from YOUR key set — never from a URL in the token.
- **Storage:** a JWT in `localStorage` is readable by any XSS. Prefer `HttpOnly; Secure; SameSite` cookies plus CSRF defense; keep access-token TTL short and make refresh tokens rotating and replay-detecting.
- **Session fixation — BROKEN:** keeping the same session id across login. **CONTROL:** rotate the session id on login AND on any privilege change; bind the session to a server-side record you can revoke.
- **Reset & verification tokens:** single-use (deleted on use, inside the same transaction), 15–60 minute TTL, stored HASHED so a database read cannot impersonate anyone, invalidating all other sessions on password change.
- **Logout & revocation:** must invalidate server-side. Removing the token from the client while the signature stays valid for an hour is not logout.

---

## A08 Software & Data Integrity Failures

- **Deserialization — BROKEN:** `pickle.loads`, `yaml.load` without `SafeLoader`, Java `ObjectInputStream`, .NET `BinaryFormatter`, `eval`/`Function` on untrusted input, `JSON.parse` into a prototype-polluting merge (`__proto__`, `constructor.prototype`). The first four are remote code execution, not data bugs; prototype pollution is a privilege-escalation and auth-bypass primitive that reaches RCE only through a library-specific gadget. **CONTROL:** a data-only format (JSON) parsed into a declared schema; `yaml.safe_load`; null-prototype objects or a merge that skips `__proto__`/`constructor`/`prototype`.
- **XXE — BROKEN:** any default XML parser on untrusted input; SVG, DOCX, XLSX and SOAP are all XML. **CONTROL:** disable external entities and DTD processing explicitly (`defusedxml`, `XmlResolver = null`, `FEATURE_SECURE_PROCESSING`).
- **Zip-slip / decompression bombs — BROKEN:** `zipfile.extractall()`, `tar -x` on an uploaded archive. An entry named `../../etc/cron.d/x` writes outside the target, and a 42 KB zip expands to gigabytes in one pass, and to petabytes if you recurse into nested archives. **CONTROL:** iterate entries; apply the containment check above to EVERY resolved entry path; reject symlink/device entries; cap entry count, per-entry size, and TOTAL uncompressed size while streaming.
- **ReDoS — BROKEN:** nested quantifiers on user input (`(a+)+$`, `(\w+\s?)*`), an unanchored email/URL regex, catastrophic backtracking on a 50 KB string. **CONTROL:** bound input length BEFORE matching (the only control that always works), eliminate nested or ambiguous quantifiers, prefer a parser or a linear-time engine (RE2), and apply a match timeout where the runtime offers one. Anchoring only prevents the restart-at-every-offset cost — it does NOT fix catastrophic backtracking: `^(a+)+$` is anchored and still exponential.
- **Integrity of what you fetch:** verify checksums or signatures for downloaded artifacts; use Subresource Integrity for third-party scripts; never pipe a remote script straight into a shell in a build you control.

---

## A09 Security Logging & Monitoring Failures

The category most often missing entirely — including from the previous version of this skill.

- **LOG:** authentication success and failure (with the account identifier, not the credential), authorization denial, privilege/role change, password/MFA/email change, admin action, token issuance and revocation, rate-limit trips, input-validation rejections at a security boundary. Each with actor, action, target, timestamp, source, and outcome.
- **NEVER LOG:** passwords, tokens of any kind, session ids, API keys, full card numbers, raw request or response bodies, authorization headers, PII beyond the identifier the record needs. Enforce with an ALLOWLIST serializer plus a redaction filter — a denylist misses the field added next sprint.
- **Make it usable:** structured fields, a correlation id that survives across services, tamper-evident retention, and clocks in UTC. An audit log an attacker can edit or that nobody alerts on is decoration.
- **TEST:** assert the log line exists for a failed authz attempt, and assert the credential does NOT appear anywhere in captured log output.

---

## A10 SSRF

- **BROKEN:** fetching a user-supplied URL after checking a blocklist of strings, or validating the hostname and then following redirects. A DNS name that resolves to `169.254.169.254` passes every string check; a `302` to a link-local address passes a first-hop-only check; `http://[::ffff:169.254.169.254]`, `http://2852039166/`, and DNS rebinding all defeat naive parsing.
- **CONTROL, in order:** (1) allowlist the destination HOST — an allowlist is the only control that holds; (2) allow only `http`/`https`; (3) RESOLVE the host and reject — for EVERY address it resolves to, not just the first — link-local (`169.254.0.0/16`, `fe80::/10`), loopback (`127.0.0.0/8`, `::1`), unspecified (`0.0.0.0/8`, `::` — `http://0/` reaches localhost on Linux), private (`10/8`, `172.16/12`, `192.168/16`, `fc00::/7`), CGNAT (`100.64.0.0/10` — Alibaba metadata lives at `100.100.100.200`), and every cloud-metadata address — then connect to the RESOLVED IP so the name cannot change between check and use; (4) re-apply every rule after EACH redirect, or disable redirect following; (5) set timeouts and a response-size cap; (6) strip credentials from the URL and never forward the caller's auth headers outbound.
- **Defense in depth:** egress via a dedicated proxy or a network policy that can reach only the allowlisted hosts, and require IMDSv2 so a single request cannot mint cloud credentials.
- **TEST:** `http://169.254.169.254/latest/meta-data/`, a host that 302s to it, `http://localhost:22`, and a decimal-encoded IP → all rejected.
