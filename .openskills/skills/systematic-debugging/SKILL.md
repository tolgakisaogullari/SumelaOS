---
name: systematic-debugging
description: "Use when encountering a bug, test failure, or unexpected behavior — before attempting any fix."
---

<HARD-GATE>
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST. Proposing solutions or guessing before completing Phase 1 is strictly forbidden.
</HARD-GATE>

<debugging_workflow>
Execute these 4 phases sequentially:

1. ROOT CAUSE INVESTIGATION:
   - **SECOND BRAIN CHECK:** Before deep-diving, scan `wiki/tech-debt-and-known-issues.md` for related TD entries — the bug may already be documented as known debt. Also check `wiki/architecture-decisions.md` for constraints that may explain the behavior. This prevents re-discovering problems the wiki already tracks.
   - Read full error messages and stack traces.
   - Reproduce the issue consistently in the current state.
   - For multi-layer systems: Add diagnostic logs at component boundaries to isolate the failing layer.
   - Trace data flow backward to find where the bad value originated (see `./root-cause-tracing.md`).

2. PATTERN ANALYSIS:
   - Find similar working code in the codebase as a reference.
   - Identify exact differences between the working reference and the broken code.

3. HYPOTHESIS & ISOLATION:
   - Formulate a single, specific hypothesis.
   - Make the SMALLEST possible isolated change to test it. Do not bundle multiple fixes.

4. IMPLEMENTATION & VERIFICATION (ADAPTIVE TDD & STAGED WORKFLOW):
   - Check the `TDD Mode`. 
     - IF Enabled: Create a failing test case first that reproduces the issue. 
     - IF Skipped: Proceed to fix directly, UNLESS the bug involves AuthN, AuthZ, or security boundaries. Security bugs ALWAYS require a failing test to prove the vulnerability before fixing.
   - Implement the single fix. You MUST ensure the fix strictly adheres to the `secure-coding-standard`. Never bypass security layers (e.g., wildcards, disabling auth) just to make a bug disappear.
   - MANDATORY: Invoke the `verification-before-completion` skill to strictly verify the fix works and no regressions occurred.
   - Once verified, ONLY stage the fixed files (`git add <files>`). DO NOT use `git commit`.
   - Inform the orchestrator/user that the fix is STAGED and ready for the `requesting-code-review` skill.
</debugging_workflow>

<architectural_escalation>
CRITICAL RULE: If your fix does not work, REVERT IT safely before trying another. Do not pile fixes on top of failed fixes.
- SAFE REVERT: Use `git restore <file>` or `git checkout -- <file>` to discard unstaged failed attempts. NEVER use `git reset --hard` as it will destroy other successfully staged work.

If you attempt 3 separate isolated fixes and ALL fail:
- STOP IMMEDIATELY. Do not attempt a 4th fix.
- Revert your last failed attempt to keep the working tree clean.
- This is an architectural problem, not a simple bug. 
- Escalate to the human partner to rethink the fundamental architecture or pattern.
</architectural_escalation>

<supporting_techniques>
Reference these if applicable:
- `./defense-in-depth.md` (Add validation at multiple layers)
- `./condition-based-waiting.md` (Replace arbitrary timeouts with condition polling)
</supporting_techniques>