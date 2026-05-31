---
name: executing-plans
description: "Use when executing a written implementation plan inline after the user chooses not to use subagent-driven-development."
---

<workflow>
Execute these steps strictly in order. This is the inline/fallback execution path; when subagent dispatch is available and the user has not explicitly chosen inline execution, prefer `subagent-driven-development`.

1. PREPARATION:
   - Invoke `using-git-worktrees` to set up an isolated workspace. NEVER start implementation on the main/master branch without explicit user consent.
   - If the IDE supports subagent dispatch, STOP before executing and tell the user that `subagent-driven-development` is preferred for quality, context isolation, and staged review gates. Continue with this skill only if the user explicitly chooses inline execution.

2. PLAN REVIEW & CONTEXT LOADING:
   - Read the implementation plan (`docs/second-brain/artifacts/plans/...`).
   - Review the plan critically before executing. Identify unclear instructions, missing files, unsafe assumptions, impossible verification steps, scope gaps, or conflicts with Second Brain state.
   - Note the **TDD Mode** (Enabled or Skipped) from the header.
   - Note the **Security Constraints**. If the plan involves external data, auth, APIs, file uploads, permissions, or any untrusted input, verify that `secure-coding-standard` is loaded before writing code.
   - If there are gaps, ambiguities, or concerns, STOP and ask the user. If clear, initialize a Todo/Checklist.

3. EXECUTION (NO COMMITS ALLOWED):
   For each task sequentially:
   - Mark the task `in_progress`.
   - Execute exactly as written, adapting to the **TDD Mode**:
     - If TDD is Enabled: follow strict Red-Green-Refactor.
     - If TDD is Skipped: write implementation directly, but security-boundary changes still require automated validation.
   - Actively apply `secure-coding-standard` principles during all coding.
   - Run required verifications and tests for the task.
   - Stage successful changes only when the active workflow or user explicitly expects staged output. If staging, use `git add <exact-file-path>` only.
   - CRITICAL: DO NOT use `git commit` during this phase. The review agent must see the full uncommitted diff.
   - Mark the task `completed`.
   - STOP after each task. Summarize what changed, verification run, staged/unstaged state, and the next task. Ask the user whether to continue, prepare a handoff prompt, or pause. Do not auto-advance.

4. MANDATORY CODE REVIEW PREPARATION & DISPATCH:
   - After the final task is complete and the user approves moving to review, invoke `requesting-code-review`.
   - When preparing the payload for the review subagent, explicitly detail the security mitigations applied in `{DESCRIPTION}`.
   - Ensure `{SECURITY_MANDATE}` instructs the reviewer to enforce `secure-coding-standard`.
   - Wait for the code reviewer to inspect the uncommitted changes and provide feedback. Apply fixes via `receiving-code-review`, then stage fixes only when the active workflow expects staged output.

5. COMPLETION & FINISHING:
   - ONLY AFTER code review is approved and the user approves branch completion, invoke `finishing-a-development-branch` to handle commit, merge, cleanup, and Second Brain updates.
</workflow>

<execution_constraints>
- ZERO PREMATURE COMMITS: You are strictly forbidden from running `git commit` during execution. The code reviewer MUST see the uncommitted changes.
- SECURITY FIRST: Never trust user input. Prioritize secure coding standards over speed or feature completeness.
- NO GUESSING: If blocked by a failing test, missing dependency, unclear instruction, or stale plan state, STOP IMMEDIATELY and ask the user.
- REVISIT REVIEW WHEN NEEDED: Return to plan review if the user updates the plan, critical context changes, or the implementation approach needs rethinking.
- STRICT ADHERENCE: Never skip verification steps.
- USER VISIBILITY: Follow the project communication protocol. Give concise Turkish progress updates and task-boundary choices; do not hide material decisions behind "silent" execution.
</execution_constraints>
