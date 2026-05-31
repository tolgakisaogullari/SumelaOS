---
name: testing-anti-patterns
description: "Use when writing or modifying tests — before adding mocks, test utilities, or test-only methods to production code."
---

<HARD-GATE>
You are STRICTLY FORBIDDEN from committing any of the following testing anti-patterns. Violating these rules means you are not testing real behavior or secure architecture.
</HARD-GATE>

<anti_patterns>
1. DO NOT TEST MOCK BEHAVIOR: Never assert that a mock was called or rendered (e.g., checking for `sidebar-mock`). You MUST assert on the actual behavior or output of the real component being tested.
2. NO TEST-ONLY METHODS IN PRODUCTION: Never add methods to production classes (e.g., `session.destroy()`) if they are only used for test cleanup. Move all test-specific teardown logic to external test utility functions.
3. DO NOT MOCK BLINDLY: Never mock a dependency without understanding its side effects. If a test relies on a side effect (like writing a config), mock the lowest possible external operation (e.g., network/DB), not the high-level method.
4. DO NOT CREATE PARTIAL MOCKS: When mocking data structures or API responses, you MUST mirror the COMPLETE real-world schema. Do not omit fields just because your current test doesn't use them; downstream code might depend on them.
5. TDD COMPLIANCE ALIGNMENT: Testing is dictated by the user's choice in the `test-driven-development` skill. IF the user explicitly approved TDD, strict adherence is mandatory and tests are not optional follow-ups. IF the user skipped TDD, do not retroactively force tests or complain about missing tests.
6. NO INSECURE MOCKING (SECURITY CRITICAL): Never bypass security layers (authentication, authorization, validation) in tests just to make them pass easily. Unless explicitly testing a public route, tests MUST respect and validate the constraints defined in the `secure-coding-standard`.
</anti_patterns>

<mocking_heuristic>
If your mock setup is longer than your test logic, or if you are mocking "just to be safe" (especially security contexts), you are over-mocking. STOP and use an integration test with real components instead.
</mocking_heuristic>