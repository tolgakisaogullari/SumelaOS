# SECURITY & INTEGRITY PROTOCOL (MANDATORY)

## 🛡️ THE WHITE HAT GUARDIAN
* **Proactive Vulnerability Hunting:** During the `superpowers:brainstorming` and `superpowers:writing-plans` phases, assume the persona of a Lead Security Researcher. You must actively scan for and mitigate:
    * **IDOR (Insecure Direct Object Reference):** Ensure users can only access/modify their own resources and profile data.
    * **Race Conditions:** Implement thread-safe logic and DB constraints for high-frequency operations like point distribution and vote counting.
    * **SQLi & XSS Protection:** Leverage your ORM's parameterized queries and strict input encoding/sanitization for any user-generated content.
    * **Mass Assignment:** Use strict DTO-to-Entity mapping; never expose internal Entities directly to the API.

## 🚧 DEFENSIVE DESIGN & VALIDATION
* **Malicious Input Assumption:** Treat all incoming data as potentially harmful. 
    * Mandatory use of **FluentValidation** for all Request DTOs.
    * Use strong **Guard Clauses** to enforce business invariants at the service layer.
* **Security vs. Convenience:** If a requested feature introduces a security gap (e.g., exposing sensitive user IDs or bypassing Rate Limits), you **MUST** proactively secure it or warn the user immediately with a technical risk assessment.

## 🔐 AUTHENTICATION & DATA INTEGRITY
* **JWT & Session Security:** Ensure strict validation of JWT claims. Use `[Authorize]` attributes precisely and implement Role-Based Access Control (RBAC) where necessary.
* **Rate Limiting Enforcement:** Adhere to the `Rate Limiting` policies defined in project configuration. Ensure heavy queries (e.g., aggregated reports, leaderboards) are protected against DDoS-like patterns.
* **Data Privacy:** Ensure sensitive data (Passwords, Tokens) is never logged or returned in API responses. Use `[JsonIgnore]` or dedicated Response DTOs.

## 🛠️ SUPERPOWERS INTEGRATION
* **Verification Skill:** During the `superpowers:verification-before-completion` phase, perform a final "Security Sanity Check" to ensure no new endpoints are accidentally left open (Anonymous) or vulnerable to basic exploits.
* **Systematic Debugging:** If a security-related bug is found, use `superpowers:systematic-debugging` to trace the vulnerability to its root cause before applying a fix.

# Security: Anti-Enumeration Pattern (Forgot Password)

## Rule

For any **"Forgot Password"** screen or endpoint, always implement the **anti-enumeration pattern**:

- Show a **success message** (e.g., "Email sent. Please check your inbox.") regardless of whether the submitted email exists in the system.
- On the **frontend**, trigger the success state in **both** the success and error callbacks — never reveal which branch was taken to the user.
- On the **backend**, return `200 OK` for both found and not-found emails (log the not-found case internally but do not expose it in the response).

## Why

Without this pattern, an attacker can probe which email addresses are registered by observing different responses for found vs. not-found accounts.

**Reference:** [OWASP Testing Guide — Account Enumeration](https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/03-Identity_Management_Testing/04-Testing_for_Account_Enumeration_and_Guessable_User_Account)

## Frontend Implementation Pattern

```tsx
// Both callbacks transition to the same UI state — anti-enumeration
const { mutate: forgotPassword, isPending } = useForgotPassword({
  onSuccess: () => setCompleted(true),
  onError: () => setCompleted(true), // intentional — never reveal if email exists
})
```
