---
name: verification-before-completion
description: "Use when about to claim work is complete, fixed, or passing - before task completion, moving to the next task, code review, or committing any changes."
---

<execution_workflow>
Execute these steps strictly in order. NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.

**Spirit over letter:** Violating the letter of this rule is violating the spirit. Different words for the same claim ("seems ready", "looks good", "should work") do not exempt you from running verification.

1. IDENTIFY VERIFICATION COMMAND:
   - Determine the exact, full command required to prove the claim and its scope (e.g., test suite, build command, linter, requirements checklist).
   - Never rely on partial checks, assumptions, or alternative agent success reports.

2. EXECUTE & ANALYZE (SAFE STATE):
   - Run the FULL command in the current working directory containing the STAGED changes.
   - CRITICAL SAFETY WARNING: "Clean state" means no interfering background processes or dirty caches. It DOES NOT mean resetting git. DO NOT run destructive commands like `git reset`, `git clean`, or `git checkout .` that would wipe out the uncommitted/staged work.
   - Read the entire output, checking exit codes and counting failures explicitly.

3. APPLY STRICT VERIFICATION RULES (ADAPTIVE):
   - Build: Must return 'exit 0' (A passing linter is NOT sufficient for build verification).
   - Adaptive Testing (TDD):
     - IF TDD Mode was Enabled: Must verify the full Red-Green cycle and output exactly '0 failures'. Red-Green sequence is mandatory: Write test -> Run (pass on fixed code) -> safely recreate the broken state -> Run (MUST fail) -> restore the fix -> Run (pass). Use targeted temporary edits, test harness toggles, or another non-destructive rollback. NEVER use destructive git commands (`git reset`, `git clean`, `git checkout .`) to prove red-green. Without this safe broken-state check, you only proved the test passes once - not that it would catch the regression.
     - IF TDD Mode was Skipped: Must verify that the code compiles/builds correctly without forcing the Red-Green evidence.
   - Security Verification (CRITICAL): Regardless of TDD mode, if the task involved modifying AuthN, AuthZ, or critical boundaries, you MUST verify that the explicit negative tests (security checks) pass with '0 failures'.
   - Requirements: Must be verified line-by-line against a strict checklist.
   - VCS/Agent Delegation: Must independently verify VCS diffs using strictly `git diff --staged` (or `git status`). Do NOT blindly trust subagent completion reports.

4. VERIFY & REPORT:
   - Does the exact output confirm the claim?
   - If NO: Report the actual current status with the failure evidence and STOP. Do not proceed to code review or the next task.
   - If YES: State the completion claim WITH the fresh evidence attached. Include: command run, working directory, exit code, failure count, and the relevant output summary. Explicitly announce that the STAGED changes are now ready for the `requesting-code-review` skill or the next gated workflow step.
   - FORBIDDEN BEHAVIORS:
     - Hypothetical/paraphrase wording ("should work", "probably", "seems to", "looks correct", "ready") before fresh evidence.
     - Premature satisfaction ("Done!", "Great!", "Perfect!") before verification output is read.
     - Trusting an agent's success report without independently checking `git diff --staged` and re-running the verification command.
     - Partial verification - linter passing does not prove build passing; build passing does not prove tests passing; one test file passing does not prove full-suite passing.
     - Skipping steps due to fatigue, haste, or "just this once" - exhaustion is not an exemption.
</execution_workflow>
