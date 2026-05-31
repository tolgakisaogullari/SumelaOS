---
name: dispatching-parallel-agents
description: "Use when facing 2+ independent tasks or failures with no shared state - to investigate or fix them concurrently without blocking each other."
---

<usage_criteria>
- ALLOWED: 2+ independent test failures, bugs, research questions, or implementation tasks across completely different files/subsystems.
- ALLOWED: Read-only parallel research when each agent has a clearly separated question and no write scope.
- FORBIDDEN: Related failures, sequential dependencies, overlapping files, or tasks modifying the same configuration files (for example, both editing `package.json`).
- FORBIDDEN: Exploratory debugging where the root-cause domain is unknown; investigate sequentially first, then parallelize only after the failure surface is mapped.
</usage_criteria>

<dispatch_workflow>
Execute parallel dispatch using these strict steps:

1. IDENTIFY & ISOLATE DOMAINS:
   - Group work by strictly independent file paths, subsystems, or read-only questions.
   - If two agents might touch the same file, shared type, generated artifact, migration, lockfile, or config, DO NOT run them in parallel.
   - Decide per agent whether the task is read-only or write-capable before dispatch.

2. CRAFT SAFE & COMPLIANT PROMPTS:
   Create one highly focused, self-contained task prompt per domain. Every prompt MUST include:
   - Specific scope: the exact file, subsystem, or question.
   - Clear goal: exact failing tests, error messages, or research output required.
   - Required context: paste the minimum plan/spec/error details needed so the agent does not rely on hidden session history.
   - Ownership: exact files the agent owns, or state "read-only; do not edit files."
   - TDD & security mandate: "Follow the current TDD Mode: [Enabled/Skipped]. HOWEVER, if your fix touches AuthN, AuthZ, security boundaries, sensitive data, or input parsing, you MUST write a failing test first regardless of mode. You MUST strictly adhere to `secure-coding-standard`."
   - Concurrency safety: "You are not alone in the codebase. Do not revert edits made by others. Do not change unrelated code. Run ONLY isolated checks for your scope. Do NOT run the global test suite. Do NOT run `git commit`."
   - Staging rule: "If you changed files, stage ONLY your exact owned files using `git add <exact-file-path>`. If this is read-only, do not stage anything and return findings only."
   - Output requirement: "Return root cause/findings, security considerations, verification run, and exact files changed/staged or confirm read-only."

3. DISPATCH:
   - Launch all task agents concurrently only after every prompt has disjoint ownership and self-contained context.

4. INTEGRATE & GLOBAL VERIFY (ORCHESTRATOR'S JOB):
   - Wait for ALL agents to return `DONE`.
   - Read every agent summary and confirm changed files match assigned ownership.
   - Run `git diff --staged` and/or `git diff` to review the combined changes.
   - Spot-check the combined diff for systematic errors; parallel agents can each pass isolated checks while their combined changes interfere with each other.
   - Invoke `verification-before-completion` to run the full global verification safely in a single thread.

5. COMPREHENSIVE REVIEW HANDOFF (MANDATORY GATE):
   - Once global verification passes, invoke `requesting-code-review` to evaluate the combined changes for quality and `secure-coding-standard` compliance before moving to completion.
</dispatch_workflow>
