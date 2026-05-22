---
name: test-driven-development
description: "Use when about to start implementation of any feature or bug fix — before writing any production code."
---

<HARD-GATE>
USER CONFIRMATION REQUIRED: You MUST explicitly ask the user "Should we use TDD for this task?" before writing any tests or production code. 
- IF YES: NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST. You must follow the strict workflow below.
- IF NO: Exit this skill immediately, announce that TDD is skipped, and transition smoothly to implementation (e.g., `executing-plans`). You MUST still enforce `requesting-code-review` and `secure-coding-standard` during the standard execution.
</HARD-GATE>

<tdd_workflow>
If the user approved TDD, execute this cycle strictly in order for EVERY behavior change or bugfix:

1. RED (Write Failing Test): Write a single, minimal test demonstrating the desired behavior or reproducing the bug. Test actual behavior, not mock behavior. Where applicable, include tests for security constraints and edge cases based on the `secure-coding-standard`.
2. VERIFY RED (Watch It Fail): Run the test. You MUST verify that it fails specifically because the feature is missing or the bug exists (not due to syntax or setup errors).
3. GREEN (Minimal Code): Write the absolute minimum implementation code required to make the test pass. Actively apply `secure-coding-standard` principles while writing this code. Do not over-engineer or add unrequested features (YAGNI).
4. VERIFY GREEN (Watch It Pass): Run the test suite. Ensure the new test passes and no existing tests are broken.
5. REFACTOR (Clean Up): Only after the test is green, refactor the code to remove duplication and improve names. Tests must remain green.
</tdd_workflow>

<testing_constraints>
- CONDITIONAL RATIONALIZATION: If the user opted INTO TDD, do not skip it for "simple" changes, emergencies, or refactoring. Strict compliance is required.
- AVOID MOCKS: Test real logic whenever possible.
- NO TEST POLLUTION: Never add test-only methods or variables to production code.
- SECURITY COVERAGE: Ensure authentication, input validation, and boundary limits are tested if writing tests for secure features.
- REFERENCE: Consult `./testing-anti-patterns.md` before adding mocks or complex test utilities.
</testing_constraints>