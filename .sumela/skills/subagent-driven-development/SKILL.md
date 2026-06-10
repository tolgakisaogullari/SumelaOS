---
name: subagent-driven-development
description: "Use when executing an implementation plan with independent tasks in the current session — preferred over executing-plans for quality and context isolation."
---

<execution_workflow>
Execute tasks sequentially. DO NOT start implementation on main/master branch without explicit user consent. Use `using-git-worktrees` first.

0. REVIEW MODE OPT-IN (ask ONCE, before dispatching the first task — STOP and wait for the answer):
   - **PHASE RULE SYNC (silent, before asking):** This skill activates the `implementation` phase. Per `.sumela/RULE_REGISTRY.md` `<phase_to_rule_matrix>`, confirm every universal rule, every implementation-phase rule, and every rule matching the active stack scope(s) and domain(s) is loaded — READ any missing rule file now; if the registry file is missing, tell the user to run setup — do not guess the matrix. Also confirm `secure-coding-standard` is in context.
   - Present exactly this choice:
     "How do you want reviews and task gates during execution?
     1. **Checkpoint mode (recommended):** After EVERY task — Stage-1 spec review + Stage-2 quality/security review, then I stop for your approval before the next task. Maximum control, more interruptions.
     2. **Flow mode:** Tasks run back-to-back with no per-task reviewer dispatch and no per-task stop. ONE comprehensive review (`requesting-code-review`) covers all accumulated changes at the end — that final review is mandatory and cannot be skipped. Best for small/mechanical tasks when you'd rather review once."
   - Record the choice for the whole run. The user may switch modes at any task boundary by saying so. NEVER assume Flow mode silently — it requires this explicit opt-in; if the user gives no clear answer, default to Checkpoint mode.

For EVERY task in the plan, follow this strict loop:

1. PREPARE: Read the plan, extract the full text and context for the current task. Note the **TDD Mode** (Enabled/Skipped) and **Security Constraints** from the plan header. Do NOT make the subagent read the plan file itself.

2. IMPLEMENTATION (STRICTLY NO COMMITS): Dispatch the Implementer subagent (`./implementer-prompt.md`). Match model to task complexity: mechanical implementation → fastest model; integration work → standard model; architecture or security boundaries → most capable model. 
   - Provide the full task text. 
   - Instruct it to follow the plan's **TDD Mode** (strict Red-Green-Refactor if Enabled; standard implementation if Skipped, but enforcing the automated test rule for Auth/Security boundaries).
   - EXPLICITLY command it to comply with the `secure-coding-standard` constraints.
   - Instruct it to ONLY stage its changes using `git add`. It MUST NOT use `git commit`.
   - If Implementer returns `NEEDS_CONTEXT`: Provide the missing context and re-dispatch with the same model.
   - If Implementer returns `BLOCKED`: Assess and act per this matrix — do NOT force the same model to retry without changes:
     - **(a) Context problem** (subagent missing info): provide more context, re-dispatch with same model.
     - **(b) Needs more reasoning** (model under-powered for the judgment required): re-dispatch with a more capable model.
     - **(c) Task too large** (subagent cannot hold the scope): break the task into smaller pieces, re-dispatch each.
     - **(d) Plan itself wrong** (architectural decision unguided, spec contradicts itself): escalate to the human; do NOT proceed.
   - If Implementer asks questions: Answer them fully before allowing implementation.
   - If Implementer returns `DONE` or `DONE_WITH_CONCERNS`: Proceed to Step 3 (Checkpoint mode) or to the FLOW MODE SHORT-CIRCUIT below (Flow mode).

FLOW MODE SHORT-CIRCUIT: If the user chose Flow mode in Step 0, skip Steps 3-4 — mark the task complete in Todo/Checklist, give a one-line progress note (task name + files touched, no stop), and proceed directly to the next task's Step 1; if no task remains, proceed to Step 5. The code stays STAGED; all review weight shifts to the MANDATORY Step 5. Plan `## Checkpoint:` blocks: run their verifications, but do not stop unless a verification fails. EXCEPTION: if the Implementer returns `DONE_WITH_CONCERNS` or the task touches an auth/security boundary, run Stage-1 + Stage-2 AND stop at the per-task approval gate for THAT task even in Flow mode. (`NEEDS_CONTEXT`/`BLOCKED` handling in Step 2 is identical in both modes.)

3. SPEC REVIEW (STAGE 1 — Checkpoint mode): Dispatch Spec Reviewer subagent (`./spec-reviewer-prompt.md`).
   - CRITICAL: Pass the output of `git diff --staged` into the `[STAGED_DIFF_OUTPUT]` placeholder.
   - Does the staged code match the spec exactly (no missing/extra features)?
   - If NO: Implementer MUST fix and re-stage. Re-dispatch Spec Reviewer.
   - If YES: Proceed to Step 4.

4. QUALITY & SECURITY REVIEW (STAGE 2 — Checkpoint mode): Dispatch Code Quality Reviewer subagent (`./code-quality-reviewer-prompt.md`).
   - CRITICAL: Pass the output of `git diff --staged` into the `[STAGED_DIFF_OUTPUT]` placeholder. Ensure the reviewer checks for vulnerabilities against the `secure-coding-standard`.
   - If Issues Found: Implementer MUST fix and re-stage. Re-dispatch Quality Reviewer.
   - If Approved: Mark task complete in Todo/Checklist. The code remains STAGED (uncommitted).
   - PER-TASK USER APPROVAL GATE (Checkpoint mode): Before dispatching the next task's Implementer, STOP and ask the user for explicit approval. Summarize the completed task, describe the next task, and offer: (1) continue to next task, (2) request independent review of completed work, (3) prepare handoff prompt, (4) pause/other. Auto-advancing to the next task is forbidden. If there is no next task, proceed to Step 5.
   - INDEPENDENT REVIEW OPTION: If the user selects option (2), dispatch an independent review subagent (using `requesting-code-review` skill's code-reviewer template) to evaluate the staged diff. If the reviewer finds issues: dispatch Implementer to fix, re-stage, then re-dispatch reviewer until approved. Once approved, re-present the 4 approval options. This review is in addition to the mandatory Stage-1/Stage-2 reviews — it provides a third-party quality check when the user wants extra assurance.

5. FINAL COMPREHENSIVE REVIEW (MANDATORY GATE — BOTH MODES, NEVER SKIPPED): 
   - After ALL tasks in the plan are complete and all changes are accumulated in the Git staging area, you MUST invoke the `requesting-code-review` skill. In Flow mode this is the ONLY full review the changes receive — treat findings with proportionally higher scrutiny.
   - When preparing the review payload, explicitly list the security mitigations applied by the subagents in the `{DESCRIPTION}` field.
   - Wait for the comprehensive review of all uncommitted work.
   - If issues are found, create a focused final-review fix task containing the review findings and relevant staged diff. Dispatch the Implementer to fix and re-stage, then loop back to Step 5. If the fix changes a previously approved task's behavior, re-run Stage 1 and Stage 2 for that affected task before repeating the final review (Checkpoint mode; in Flow mode the repeated Step 5 review itself covers the fix).

6. COMPLETION & INTEGRATION: 
   - ONLY AFTER the final code review is approved, invoke the `finishing-a-development-branch` skill to handle the final commit, merge/PR options, and cleanup.
</execution_workflow>

<critical_constraints>
- STRICT ORDER: Never start Quality & Security Review (Stage 2) until Spec Review (Stage 1) is 100% approved.
- NO PARALLEL IMPLEMENTERS: Never dispatch multiple implementation subagents simultaneously.
- NO MANUAL FIXES: If a subagent fails, dispatch a fix subagent. Do not pollute your own context by fixing it manually.
- ZERO PREMATURE COMMITS: Enforce that all subagents only stage (`git add`) their work. Commits only happen in Step 6.
- REVIEW MODE IS THE USER'S CHOICE: Checkpoint mode (per-task Stage-1/Stage-2 + approval gate) is the DEFAULT. Flow mode (no per-task reviews/stops, single comprehensive final review) is valid ONLY via the user's explicit Step 0 opt-in — never self-selected to "save time". The Step 5 final review is mandatory in BOTH modes. This constraint travels with the skill even when project rules are not loaded.
- PER-TASK USER APPROVAL (Checkpoint mode): After every task passes Implementer + Stage-1 Spec Review + Stage-2 Quality/Security Review, STOP and wait for explicit user approval before starting the next task.
- NO "CLOSE ENOUGH": If the Spec Reviewer or Quality Reviewer flags issues, the task is NOT done — dispatch the Implementer to fix and re-review. Never accept partial compliance to move on.
- NEVER LET SELF-REVIEW REPLACE REVIEWER DISPATCH: Implementer's own self-review is a quality floor, NOT a substitute for Stage-1/Stage-2 reviewer subagents. Both passes are required whenever Stage-1/Stage-2 apply (Checkpoint mode, and Flow-mode exception tasks); in plain Flow mode the mandatory Step 5 comprehensive review is the reviewer dispatch that self-review never replaces.
</critical_constraints>

<ide_fallback_protocol>
If the current IDE does not expose a physical subagent or Task dispatch primitive:

1. NEVER claim "inline execution" as an equivalent substitute for the skill.
2. Tell the user that physical context isolation is unavailable in the current IDE.
3. Offer two explicit options before continuing:
   - `C1`: same-context role simulation in the current session
   - `C2`: defer formal subagent review to a compatible IDE/session
4. If the user chooses `C1`, run three explicit passes in strict sequence:
   - Implementer
   - Stage-1 Spec Review
   - Stage-2 Quality/Security Review
5. Before each pass, use an explicit bias-mitigation framing (for example: "re-read the spec fresh" or "review as if you did not write the code").
6. Produce a distinct written report for each pass so the user can audit the simulated separation.
7. Preserve all normal task gates: staged diff review, user approval boundaries, and final branch-finishing workflow still apply.
</ide_fallback_protocol>
