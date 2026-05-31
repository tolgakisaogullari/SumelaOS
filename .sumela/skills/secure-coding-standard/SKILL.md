---
name: secure-coding-standard
description: "Use whenever the task touches user input, forms, APIs, database queries, authentication, authorization, passwords, file uploads, permissions, secrets, CORS, rate limiting, or any external/untrusted data — load before planning or coding, not after."
---

<activation_rules>
- NEVER wait for a security review to load this skill. Load it DURING `brainstorming`, `writing-plans`, `executing-plans`, or `test-driven-development` if the task touches external data or state changes.
- This skill acts as a permanent constraint layer over your standard coding skills.
</activation_rules>

<human_confirmation_required>
STOP and get explicit user approval before proceeding with any of the following. These are security-boundary changes that cannot be automatically verified:
- Adding new authentication flows or modifying existing auth logic
- Introducing a new category of sensitive data storage (PII, payment info, health data)
- Adding a new external service integration or third-party API
- Modifying CORS configuration or adding new allowed origins
- Introducing new file upload endpoints or handlers
- Changing rate limiting policies or account lockout thresholds
- Granting elevated permissions, new roles, or new admin capabilities
</human_confirmation_required>

<execution_workflow>
Execute these security constraints strictly. NEVER trust user input. Security overrides all other implementation preferences.

1. THREAT BOUNDARY ANALYSIS (Pre-computation):
   - Identify ALL external inputs (API payloads, URLs, headers, file uploads, query parameters).
   - Identify ALL sensitive data flows (PII, credentials, API keys, financial data).

2. STRICT IMPLEMENTATION CONSTRAINTS (OWASP Mitigation):
   - Injection & Path Traversal: MUST use parameterized queries/ORMs. String concatenation for queries/commands is FORBIDDEN. ALWAYS sanitize file paths and names.
   - XSS & CSRF: MUST encode/sanitize all outputs. MUST enforce anti-CSRF tokens or SameSite cookies for cookie/session-based state-changing actions. For bearer-token mobile/API flows, document why CSRF is not the active threat and verify token validation, CORS, and origin assumptions instead.
   - Access Control & IDOR (BOLA): MUST verify both AuthZ (is admin/user?) AND Ownership (does this user own resource ID X?). Default to 'deny'.
   - SSRF & CORS: NEVER blindly fetch user-supplied URLs; use strict allowlisting. NEVER configure CORS to wildcard `*` in production.
   - File Uploads: MUST validate strict MIME-types (not just extensions), enforce size limits, and store uploaded files outside the web root.
   - Data & Crypto: NEVER log sensitive data: passwords, JWT, refresh, ID token, FCM token, raw search query text, raw request bodies, SMTP credentials, report descriptions, or any PII. NEVER hardcode secrets. MUST use strong, modern cryptography (e.g., bcrypt/Argon2 for passwords).
   - Abuse Prevention: MUST implement strict rate limiting, throttling, or account lockout mechanisms on sensitive/auth endpoints to prevent brute-force attacks.
   - Business Logic & Concurrency: MUST prevent race conditions (TOCTOU) using database locks (e.g., `SELECT FOR UPDATE`) or atomic operations on financial/state-changing endpoints.
   - Supply Chain & Headers: NEVER introduce third-party dependencies with known CVEs. MUST configure secure HTTP headers (CSP, HSTS).

3. VALIDATION RULES (Zero Trust):
   - Implement strict type checking and schema validation at the earliest system boundary (e.g., using Zod, Joi, or equivalent).
   - Reject invalid data immediately with safe error codes. Do NOT attempt to "fix" or "guess" malformed payloads.

4. SECURITY VERIFICATION & ADAPTIVE TESTING (CRITICAL):
   - Verify error handling does NOT leak internal stack traces, framework versions, or database structures to the client.
   - TDD EXCEPTION FOR SECURITY: Even if the user explicitly skipped the `test-driven-development` workflow for this task, if you are modifying AuthZ/AuthN logic, access controls, or critical boundaries, you MUST write an automated failing test attempting to bypass the logic (e.g., "User A attempts to delete User B's profile") to mathematically prove the system is secure.

5. CODE REVIEW PREPARATION:
   - When you are finished and about to invoke `requesting-code-review`, you MUST explicitly list the security mitigations you implemented in the `{DESCRIPTION}` parameter so the reviewer can verify them.
   - Classify each security finding using this severity model and structured format:

   **Severity Levels (aligned with review skills: Critical / Important / Minor / Recommendations-FYI):**
   - Critical: Immediately exploitable or high-impact — blocks merge (e.g., auth bypass, privilege escalation, injection, hardcoded secrets, token/PII logging, data exposure, exploitable IDOR).
   - Important: Significant exploitable path or missing required control (e.g., missing rate limiting on auth endpoints, weak ownership checks, unsafe CORS in a reachable environment).
   - Minor: Limited scope, requires specific conditions, or low-impact hardening gap (e.g., verbose internal error detail in non-production, missing non-critical security header).
   - Recommendations-FYI: Defense-in-depth or advisory-only improvement with no immediate exploitable path.

   **Finding Structure (one entry per issue):**
   - **Location:** File path + line number
   - **Description:** What the vulnerability is
   - **Impact:** What an attacker could do if exploited
   - **Remediation:** Specific fix, with code example where applicable

   **Principle:** Prioritize practical, exploitable vulnerabilities over theoretical risks. A Critical IDOR is more urgent than a Minor missing header.
   **Positive Observations:** When reviewing, explicitly acknowledge security constraints that are correctly implemented — this reinforces good patterns alongside gaps.

6. SECURITY REVIEW CHECKLIST (Pre-commit gate):
   Before invoking `requesting-code-review`, verify each item. Stack-specific commands and framework names live in project rules under `.sumela/rules/` (e.g., `backend_standards.md`, `mobile_app_development_standards.md`); this skill defines the universal categories.

   **Authentication & Sessions:**
   - [ ] Passwords hashed via a memory-hard algorithm (bcrypt / Argon2 / scrypt). NEVER plaintext, MD5, or SHA1.
   - [ ] Auth tokens validated strictly (issuer, audience, expiry, signing key).
   - [ ] Login and password-reset endpoints carry rate limiting / lockout.

   **Authorization:**
   - [ ] Every endpoint either requires auth or has an explicit allow-anonymous declaration.
   - [ ] Ownership check performed (user accesses only THEIR resource, not any resource by ID).
   - [ ] Admin-only actions require an explicit role/claim check.

   **Input & Output:**
   - [ ] All request DTOs validated at the API boundary via the project's chosen validation library.
   - [ ] Parameterized queries used — no raw query string concatenation.
   - [ ] Error responses do NOT expose stack traces, internal IDs, or DB schema.

   **Secrets & Config:**
   - [ ] No secrets in committed config files.
   - [ ] Pre-review secret check: both `git diff --cached` and `git diff` reviewed for API keys, passwords, tokens, credentials, and sensitive sample data.
   - [ ] Environment secrets use the platform's secret manager (Azure Key Vault, AWS Secrets Manager, env vars, etc.).

   **Infrastructure:**
   - [ ] Security headers configured (CSP, HSTS, X-Frame-Options).
   - [ ] CORS restricted to known origins (no wildcard `*` in production).
   - [ ] Dependency audit clean (`npm audit`, `pip-audit`, `dotnet list package --vulnerable`, etc., per project rules).
</execution_workflow>

<common_rationalizations>
| Rationalization | Reality |
|---|---|
| "This is an internal tool, security doesn't matter" | Internal tools get compromised. Attackers target the weakest link. |
| "We'll add security later" | Security retrofitting is 10x harder than building it in from day one. |
| "No one would try to exploit this" | Automated scanners will find it. Security by obscurity is not security. |
| "The framework handles security" | Frameworks provide tools, not guarantees. You must use them correctly. |
| "It's just a prototype" | Prototypes become production. Security habits must start on day one. |
</common_rationalizations>
