---
name: writing-plans
description: "Use when starting implementation from an approved spec or design — before any code is written or worktree is created."
---

<execution_workflow>
Execute these steps strictly in order. DO NOT announce the skill unless specifically asked. Do not write implementation code in this phase; isolated worktree setup belongs to the execution phase.

0. PRE-FLIGHT CONTEXT (MANDATORY — before any planning output):
   - **SECURITY STANDARD LOAD:** Read `.sumela/skills/secure-coding-standard/SKILL.md` if not already in context. EVERY plan gets this — not just "security-flavored" ones — because the plan's **Security Constraints** header and each task's implementation steps must be authored against the actual standard, never from memory. Skipping this because "the feature has no auth surface" is a forbidden rationalization: input validation, error handling, and data exposure apply to all code.
   - **PHASE RULE SYNC:** This skill activates the `planning` phase. Per `.sumela/RULE_REGISTRY.md` `<phase_to_rule_matrix>`, confirm every universal rule, every planning-phase rule, and every rule matching the active stack scope(s) and domain(s) is loaded — READ any missing rule file now, before drafting. If the registry file is missing, tell the user to run setup — do not guess the matrix.

1. SCOPE & FILE MAPPING:
   - **SECOND BRAIN CHECK (MANDATORY):** Read `wiki/architecture-decisions.md` and `wiki/tech-debt-and-known-issues.md`. The plan MUST respect existing approved AD records and account for open TD items that overlap with the feature scope. Reference relevant AD-XX / TD-XX IDs in the plan header's Architecture section.
   - Analyze spec: If it covers multiple independent subsystems, STOP and suggest breaking it into separate plans (one per subsystem).
   - Map files: Determine exact file paths to create or modify. Enforce single responsibility. Split large files if necessary. **Files that change together live together — split by responsibility, not by technical layer.**
   - **DEPENDENCY GRAPH:** Map what depends on what before ordering tasks. Implementation order follows the graph bottom-up — build foundations first (e.g., DB schema → domain entities → application services → API endpoints → frontend clients → UI components). Never build a layer before its dependency exists.

2. INITIALIZE PLAN DOCUMENT:
   - Save path: `docs/second-brain/artifacts/plans/YYYY-MM-DD-<feature-name>.md`
   - **WRITE-TOOL RULE:** Create the plan with the IDE's file-write tool (NOT shell redirection / heredoc), so the IDE's change tracker registers it.
   - **VISIBILITY CHECK (MANDATORY, immediately after saving):** Run `git check-ignore -q <save-path>` and decide on the EXIT CODE only: exit 1 = visible → PASS (exit 1 is success, NOT a command error); exit 0 = ignored → remediate. Do NOT decide from `-v` output alone — a `-v` match whose pattern starts with `!` means the file IS visible. On exit 0: run `-v` to name the culprit (common cause: a generic `artifacts/` build-output pattern), append `!docs/second-brain/artifacts/` and `!docs/second-brain/artifacts/**` at the END of the `.gitignore` in the SumelaOS install root (the directory containing `docs/second-brain/`), re-run the `-q` check, and tell the user what you fixed. If the lines already existed, re-append them at the END anyway (duplicates are harmless; last match wins). If STILL ignored (an excluded parent like `docs/` — negation cannot pierce it), STOP and warn the user: the plan is invisible to `git status` and the IDE's Changes view; ask how to resolve.
   - MUST include this exact header:
     ```markdown
     # [Feature Name] Implementation Plan
     > **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans`. Steps use checkbox (`- [ ]`) syntax. 
     > **CRITICAL RULE:** Accumulate uncommitted changes. DO NOT use `git commit` during task execution. Only `git add` is allowed until the final review step.
     **Goal:** [One sentence]
     **Architecture:** [2-3 sentences]
     **Tech Stack:** [Key technologies]
     **TDD Mode:** [Explicitly state if TDD is Enabled or Skipped based on user's prior choice]
     **Security Constraints:** [List specific threat boundaries, input validation, or Auth needs. MANDATORY: Code must comply with `secure-coding-standard`.]

     ## Risks & Mitigations
     | Risk | Impact | Mitigation |
     |------|--------|------------|
     | [Risk] | High/Med/Low | [Strategy] |

     ## Open Questions
     - [Any question requiring human input before or during implementation]
     ```

3. DEFINE BITE-SIZED TASKS (ADAPTIVE WORKFLOW):
   - **VERTICAL SLICING (MANDATORY):** Build one complete feature path at a time — schema + service + endpoint + test together — NOT all schemas first, then all services, then all endpoints. Each task must deliver a working, testable slice of functionality.
   - **CONTRACT-FIRST SLICING (when frontend + backend are developed in parallel):** Define the API contract (types, interfaces, OpenAPI/Swagger spec) as Task 0. Then backend implements against the contract with real tests; frontend implements against mock data matching the contract. Final task: integration + end-to-end test. This prevents parallel tracks from diverging.
   - **RISK-FIRST SLICING:** Place the most uncertain or technically risky task first. If it fails, you discover it before building dependent layers on top of an unvalidated foundation.
   - **TASK SIZING — break down further if ANY of these are true:**
     - The task would take more than one focused session
     - Acceptance criteria cannot be described in 3 or fewer bullets
     - The task touches two or more independent subsystems
     - The task title contains "and" (that's two tasks)

     | Size | Files | Scope |
     |------|-------|-------|
     | XS | 1 | Single function or config change |
     | S | 1-2 | One endpoint, one service method |
     | M | 3-5 | One complete feature slice |
     | L | 5-8 | Multi-component feature — consider splitting |
     | XL | 8+ | **Too large — MUST break down** |

   - **CHECKPOINTS:** After every 2-3 tasks, add an explicit checkpoint:
     `## Checkpoint: After Tasks N-M — All tests pass. Build is clean. Core flow works. Review before proceeding.`
     (Execution skills pause here in Checkpoint mode; in Flow mode they run the checkpoint's verifications and continue unless one fails.)
   - Break work into 2-5 minute actionable steps.
   - For each Component/Task, clearly list exact file paths (Create, Modify, Test).
   - **IF TDD WAS ENABLED:** Enforce the 5-Step TDD Loop for every task:
     1. Write failing test (include exact code).
     2. Run test to verify failure (include exact command).
     3. Write minimal implementation code to pass the test (apply `secure-coding-standard`).
     4. Run test to verify success (include exact command).
     5. Stage changes (`git add <files>`). DO NOT commit.
   - **IF TDD WAS SKIPPED:** Enforce standard implementation steps:
     1. Write implementation code focusing on the spec and `secure-coding-standard`.
     2. Verify functionality manually or via build commands.
     3. Stage changes (`git add <files>`). DO NOT commit.
   - **CRITICAL FINAL TASK:** The very last checkbox in EVERY plan MUST be: "- [ ] Invoke `requesting-code-review` skill to verify changes against the `secure-coding-standard` BEFORE attempting any `git commit`."
   - **PLAN FAILURES — NEVER WRITE:** "TBD" / "TODO" / "implement later" / "fill in details"; vague error handling ("Add appropriate error handling", "handle edge cases", "add validation"); "Similar to Task N" without repeating the code (the engineer may read tasks out of order); references to types, functions, or methods not defined in any task; steps that describe what to do without showing the exact code, command, or file path.
   - **TASK MARKDOWN TEMPLATE (use verbatim per task):**
     ````markdown
     ### Task N: [Component Name]

     **Files:**
     - Create: `exact/path/to/file.cs`
     - Modify: `exact/path/to/existing.cs:L123-L145`
     - Test: `tests/exact/path/test.cs` (only if TDD is Enabled)

     - [ ] Step 1 (TDD ON → write failing test [code block]; TDD OFF → write implementation [code block])
     - [ ] Step 2 (TDD ON → run test, expect FAIL [exact command]; TDD OFF → verify build/manual [exact command])
     - [ ] Step 3 (TDD ON → write minimal implementation [code block])
     - [ ] Step 4 (TDD ON → run test, expect PASS [exact command])
     - [ ] Step 5 — `git add <exact files>`. DO NOT commit.
     ````
     For TDD OFF, collapse to Steps 1-2 + stage. Always show exact code, exact commands, exact file paths.

4. CRITICAL WIKI LINKING (MANDATORY): After generating and saving the complete plan file, you MUST immediately append a link to it in `docs/second-brain/wiki/_INDEX.md` (under "Artifacts") AND in `docs/second-brain/wiki/active-project-context.md`. Use **standard markdown link format** (NOT wikilinks) because artifacts live outside the wiki: `[YYYY-MM-DD-feature-name](../artifacts/plans/YYYY-MM-DD-feature-name.md)`. Do not proceed to review or handoff without creating these links.

5. REVIEW PACKET PREFLIGHT (MECHANICAL ONLY):
   Before dispatching the plan reviewer, verify the review packet is complete:
   - Plan file exists at the path you will send to the reviewer.
   - Spec file path is known and will be sent to the reviewer.
   - `_INDEX.md` and `active-project-context.md` contain the artifact link.
   - Mandatory header fields exist: Goal, Architecture, Tech Stack, TDD Mode, Security Constraints, Risks & Mitigations, Open Questions.
   - The final task invokes `requesting-code-review`.
   - No `git commit` command appears anywhere in task execution steps.
   - No placeholder text remains (`TBD`, `TODO`, `implement later`, `fill in details`, vague "handle edge cases", empty mandatory sections).
   - `git check-ignore -q <plan-path>` exits 1 (file visible — Step 2 visibility check passed or was remediated).
   - This is NOT a quality review. Do not approve your own plan; the independent `plan-document-reviewer` subagent remains mandatory.

6. PLAN REVIEW LOOP:
   - Dispatch `plan-document-reviewer` subagent with paths to the plan and the spec. DO NOT send session history.
   - If ❌ Issues Found: Fix the plan and re-dispatch reviewer. (Max 3 iterations; if exceeded, ask human for guidance).
   - If ✅ Approved: Proceed to step 7.

7. EXECUTION HANDOFF:
   - Present exactly these two options to the user and WAIT for a choice:
     "Plan complete and saved to `docs/second-brain/artifacts/plans/<filename>.md`. Choose execution method:
     1. **Subagent-Driven (recommended):** Dispatch fresh subagents per task with implementer + review loops.
     2. **Inline Execution:** Execute tasks in this session using `executing-plans` only if you explicitly choose inline execution."
</execution_workflow>

<common_rationalizations>
| Rationalization | Reality |
|---|---|
| "I'll figure it out as I go" | That's how you end up with rework. 10 minutes of planning saves hours of untangling. |
| "The tasks are obvious" | Write them down anyway. Explicit tasks surface hidden dependencies and forgotten edge cases. |
| "Planning is overhead" | Planning IS the task. Implementation without a plan is just typing. |
| "I can hold it all in my head" | Context windows are finite. Written plans survive session boundaries and compaction. |
| "This is too small to plan" | If it's truly small, the plan takes 2 minutes. If it takes longer, it wasn't small. |
</common_rationalizations>
