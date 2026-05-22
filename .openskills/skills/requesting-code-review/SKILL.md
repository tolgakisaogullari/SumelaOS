---
name: requesting-code-review
description: "Use when completing a task, implementing a major feature, or before merging - to catch issues before they cascade into committed history."
---

<usage_criteria>
- MANDATORY: Before making ANY commit (must review staged/uncommitted changes first), after completing a task/feature, and before merging to main.
- SECURITY GATE: This skill acts as the final firewall. Code MUST be evaluated against security guidelines before it enters history.
- OPTIONAL (still valuable): when stuck on a problem (fresh perspective), before a major refactor (baseline check), or after fixing a complex bug.
- FORBIDDEN: Never skip reviews because a change seems "simple" or "small".
</usage_criteria>

<dispatch_workflow>
Execute these steps strictly to request a review:

1. GATHER CONTEXT (CRITICAL PRE-COMMIT GATE):
   - For staged changes: Get the diff of the currently staged files using `git diff --staged`.
   - If the staged diff is empty but the task is complete, check `git diff` before review so uncommitted work is not accidentally skipped.
   - For intentionally unstaged reviews, state that explicitly in `{HEAD_SHA}` (for example, "Unstaged Working Tree") and pass the exact `git diff` output as `{CODE_DIFF}`.
   - For already committed changes (if specifically requested): Get the exact git SHAs (e.g., `BASE_SHA=$(git rev-parse HEAD~1)` and `HEAD_SHA=$(git rev-parse HEAD)`).

2. CHANGE SIZE CHECK (BEFORE DISPATCH):
   Count lines changed in the diff. If the diff exceeds ~300 lines of meaningful logic changes, STOP and ask the author to split the change. Reviewers cannot give quality feedback on 1000-line diffs; large reviews create rubber-stamping risk.
   Exception: Complete file deletions and automated refactoring where intent is obvious.

3. DISPATCH SUBAGENT (WITH SECURITY MANDATE):
   Invoke the Task/Agent tool using the code review template in the same skill directory: `requesting-code-review/code-reviewer.md`. If the IDE exposes a named `code-reviewer` subagent, use it with this template content. Fill these placeholders precisely and explicitly command the reviewer to check security:
   - `{WHAT_WAS_IMPLEMENTED}`: What you built based on the plan.
   - `{PLAN_OR_REQUIREMENTS}`: What it should do (the original goal).
   - `{BASE_SHA}`: Starting commit (or "HEAD" if reviewing uncommitted/staged changes).
   - `{HEAD_SHA}`: Ending commit (or "Staged Working Tree" / "Unstaged Working Tree" if reviewing uncommitted changes).
   - `{SECURITY_MANDATE}`: Explicitly write: "You MUST evaluate these changes against the `secure-coding-standard` skill. Check for input validation, auth bypasses, authorization gaps, sensitive data leaks, and unsafe logging. Severity must be impact-based: auth bypass, data exposure, token/PII logging, injection, or privilege escalation are Critical; lower-impact hardening gaps may be Important."
   - `{DESCRIPTION}`: Brief technical summary of the architectural choices.
   - `{CODE_DIFF}`: The exact output of the git diff command executed in Step 1.

   The reviewer MUST evaluate across all five axes and place every finding in the matching output section:
   - **Correctness:** Does the code match the spec? Edge cases handled? Error paths covered?
   - **Readability:** Names clear? Logic straightforward? No clever tricks? No dead code artifacts?
   - **Architecture:** Follows existing patterns? Clean boundaries? No unnecessary coupling?
   - **Security:** Covered by `{SECURITY_MANDATE}` above; all OWASP checks apply.
   - **Performance:** N+1 queries? Unbounded loops? Missing pagination?

   Severity sections the reviewer MUST use:
   | Section | Meaning | Required Action |
   |---------|---------|-----------------|
   | Critical | Blocks commit/merge | Security flaw, data loss, broken functionality |
   | Important | Required before proceeding | Architecture problem, missed requirement, risky error handling, meaningful test gap |
   | Minor | Nice to have | Style, small clarity, non-blocking optimization |
   | Recommendations / FYI | Informational | No action needed unless the author chooses |

   Dead Code Hygiene instruction: "Identify any code that is now unreachable or unused as a result of this change. List it explicitly and ask whether it should be removed; do NOT silently delete it."

4. HAND-OFF TO RECEIVING SKILL (MANDATORY):
   - Once the subagent returns the review feedback, you MUST IMMEDIATELY activate the `receiving-code-review` skill to process the results.
   - DO NOT attempt to process, commit, or implement the feedback before reviewing the strict rules inside `receiving-code-review`.
   - **If reviewer is wrong:** Push back with technical reasoning. Show code or tests that prove correctness. Request clarification. Never blindly implement feedback you disagree with.

   **Workflow integration cadence** (when this skill is dispatched):
   - `subagent-driven-development` -> invoke after EACH task (per-task review loop, see SDD STEP 4).
   - `executing-plans` -> invoke after each batch checkpoint.
   - Ad-hoc development -> invoke before merge to base, or when stuck on a difficult bug.
</dispatch_workflow>
