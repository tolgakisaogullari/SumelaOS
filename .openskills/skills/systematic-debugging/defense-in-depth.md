---
name: defense-in-depth
description: "Use when fixing a bug caused by invalid data that can enter the system through multiple code paths or be bypassed by mocks and refactoring."
---

<core_principle>
Assume every validation layer can and will be bypassed by direct internal calls, mocks, or future refactoring. You MUST validate data at EVERY boundary it crosses. Do not rely on a single check.
</core_principle>

<validation_workflow>
When fixing a bug caused by invalid data, trace the data flow and implement these 4 layers of defense using the current TDD mode:

1. ENTRY POINT VALIDATION: Reject structurally invalid input at the outermost API boundary (e.g., throw errors for nulls, empty strings, or non-existent files).
2. BUSINESS LOGIC VALIDATION: Enforce domain-specific constraints right before the operation (e.g., "Is this operation valid for the current state?").
3. ENVIRONMENT GUARDS: Prevent destructive operations based on context. (e.g., If `NODE_ENV=test`, strictly block `git init` or file writes outside of the temporary directory).
4. DEBUG INSTRUMENTATION: Inject context-rich logging (relevant variables, `process.cwd()`, and `new Error().stack`) immediately prior to critical or dangerous execution points. Note: These logs must be removed before staging.
</validation_workflow>

<execution_constraints>
- ADAPTIVE TDD & NEGATIVE TESTING (CRITICAL): 
  - IF TDD Mode is Enabled: For every guard or validation layer added in Steps 1-3, you MUST write a corresponding test that intentionally passes invalid data to verify the system fails safely.
  - IF TDD Mode is Skipped: Do NOT force tests for general logic. HOWEVER, if the guard is a security measure (e.g., preventing injection, fixing Auth bypass, or IDOR), you MUST write the corresponding negative test regardless of the TDD mode.
- SECURITY SYNERGY: You MUST strictly adhere to the `secure-coding-standard` skill rules for sanitization and zero-trust at every layer.
- STAGED WORKFLOW: After implementing and verifying the defense layers, ONLY stage your changes (`git add <files>`). DO NOT commit. This ensures the orchestrator can review the uncommitted work before invoking `requesting-code-review`.
</execution_constraints>