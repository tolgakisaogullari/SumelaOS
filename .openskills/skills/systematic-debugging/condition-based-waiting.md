---
name: condition-based-waiting
description: "Use when tests use arbitrary delays or are flaky due to race conditions in async operations."
---

<HARD-GATE>
NEVER use arbitrary delays (e.g., `setTimeout`, `sleep`, `time.sleep`) to guess when an async operation will complete. You MUST wait for the actual condition or state change.
</HARD-GATE>

<implementation_rules>
When fixing or writing async tests, apply these strict polling rules:

1. FRAMEWORK-FIRST APPROACH: Before writing custom `while`/`Promise` loops, you MUST use the testing framework's native polling utilities if available (e.g., `waitFor` in React Testing Library, `expect.poll` in Vitest/Playwright, or `Awaitility` in Java).
2. CONDITION POLLING: If a custom loop is necessary, implement a mechanism that checks the exact condition (e.g., event fired, state changed, file created) at short intervals (e.g., 10ms - 50ms).
3. FRESH DATA: Always fetch the latest state/data INSIDE the polling loop. Do not evaluate stale or cached variables from outside the loop.
4. TIMEOUT FALLBACK & SECURE TRACEABILITY (CRITICAL): Your polling mechanism MUST include a maximum timeout threshold (e.g., 5000ms) to prevent infinite loops. If the timeout is reached, it MUST throw a highly descriptive error containing the exact technical context. 
   - **SECURITY RULE:** Ensure the descriptive error does NOT leak sensitive data (API keys, PII, passwords) into the test logs, as per `secure-coding-standard`.
</implementation_rules>

<exceptions>
You may ONLY use arbitrary delays (`setTimeout`) when explicitly testing strictly timed behavior (e.g., debounce/throttle intervals, fixed tick-based systems, or **security rate-limiting tests**). If you use a hardcoded timeout, you MUST add an inline comment explaining the exact reasoning/math behind that specific value.
</exceptions>

<execution_constraints>
- VERIFICATION: Prove your polling works by running the test suite multiple times. It must pass consistently without race conditions.
- STAGED WORKFLOW: After applying this pattern and verifying the fix, ONLY stage the changes using `git add <files>`. DO NOT commit. 
- REVIEW HANDOFF: When invoking `requesting-code-review`, explicitly explain in the `{DESCRIPTION}` why this condition-based approach was necessary and how it prevents flakiness.
</execution_constraints>