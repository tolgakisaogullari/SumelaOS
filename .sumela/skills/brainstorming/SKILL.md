---
name: brainstorming
description: "Use when starting a new feature, system, or architectural change that is already chosen and clear enough to design — to produce approved design options and a saved spec, before any code is written, implementation skills are invoked, or project scaffolding begins. A highly detailed task description is INPUT to this skill (it speeds the design loop), never a reason to skip it. If the idea is still open-ended or the user wants help deciding WHAT to build or what would add value, start with idea-explore first."
---

<HARD-GATE>
DO NOT write code, invoke implementation skills, or scaffold projects until a design is fully presented and explicitly approved by the user. "Simple" projects are not exempt.
</HARD-GATE>

<anti_pattern_too_simple>
Every project — including "simple" utilities, todo lists, config changes — goes through this loop. The design can be 3 sentences for trivial tasks, but it MUST exist and be approved. Skipping this is where unexamined assumptions cause the most wasted work. (Sole exemption: a user-requested trivial direct edit — typo/config one-liner — per the sumela-prompt DEVELOPMENT GATE condition (c).)
</anti_pattern_too_simple>

<workflow>
Execute these steps in strict sequential order:

0. PRE-FLIGHT CONTEXT (MANDATORY):
   - **SECURITY STANDARD LOAD:** Read `.sumela/skills/secure-coding-standard/SKILL.md` if not already in context — Step 4's per-option **Security Impact** analysis and the spec's **Security Considerations** section must reference the actual standard, not memory.
   - **PHASE RULE SYNC:** This skill activates the `specification` phase. Per `.sumela/RULE_REGISTRY.md` `<phase_to_rule_matrix>`, confirm every universal rule, every specification-phase rule, and every rule matching the active stack scope(s) and domain(s) is loaded — READ any missing rule file now. If the registry file is missing, tell the user to run setup — do not guess the matrix.

1. EXPLORE CONTEXT: Read relevant files, docs, and recent commits to understand the current state. Avoid scoping too broadly; decompose large requests into sub-projects.
   - **DECOMPOSITION RULE:** If the request describes multiple independent subsystems (e.g., "platform with chat + billing + analytics"), flag this immediately and decompose. Each sub-project gets its OWN spec → plan → implementation cycle; do NOT try to fit them into one spec.
   - **SECOND BRAIN CHECK (MANDATORY):** Before proposing any architecture, read `wiki/_INDEX.md` to locate relevant pages, then read `wiki/architecture-decisions.md` (existing AD records) and `wiki/tech-debt-and-known-issues.md` (open debt). Your proposals MUST NOT contradict existing approved decisions unless explicitly superseding them. This prevents the wiki's compounded knowledge from being ignored.

2. VISUAL COMPANION CHECK (RICH MENU): If the task requires UI/diagrams or complex state flows, present this choice clearly to the user:
   "This task involves visual/architectural complexities. How would you like to proceed?
   1. **Use Visual Companion (Recommended):** I will generate visual diagrams/UI previews in the browser. (Note: Token-intensive, but prevents design blind spots).
   2. **Text-Only Mode:** Let's stick to markdown and text descriptions. (Faster, best if you already have a clear visual in mind)."
   Wait for reply. If Option 1, consult `./visual-companion.md`.

3. CLARIFY: Before asking any questions, first list your explicit assumptions:
   ```
   ASSUMPTIONS I'M MAKING:
   1. [e.g., This targets web, not native mobile]
   2. [e.g., Auth uses JWT, based on existing middleware]
   3. [e.g., PostgreSQL, based on existing ORM/migration config]
   → Correct me now or I'll proceed with these.
   ```
   Then ask clarifying questions ONE AT A TIME. Prefer multiple-choice. Focus on purpose, constraints, and **security/data-privacy requirements** (referencing the `secure-coding-standard` loaded in Step 0).
   **Reframe vague requirements as measurable success criteria:**
   - "Make it faster" → "API p95 < 200ms, LCP < 2.5s — are these the right targets?"
   - "Improve security" → "Specific threat: IDOR on resource X — is that the concern?"
   Confirm reframed criteria with the user before proceeding.

4. PROPOSE ARCHITECTURE (DEEP OPTIONS): Present 2-3 distinct architectural/design approaches. You MUST format your proposals using this deep-context structure and actively consider the `secure-coding-standard`:
   - **Option A [Name]:** [Brief 1-sentence description]
     - **Pros:** [What do we gain?]
     - **Cons/Risks:** [What are the trade-offs or technical debt?]
     - **Security Impact:** [How does this handle data? Any attack vectors mitigated or exposed?]
     - **Best For:** [When is this the right choice?]
   - Clearly state your expert recommendation at the end and wait for the user to select an approach.

5. PRESENT DESIGN: Break the system into small, single-responsibility units. Present design in chunks. Get user approval after each section. Follow existing codebase patterns.
   - **EXISTING CODEBASE RULE:** Where existing code blocks the current goal (oversized files, tangled responsibilities, unclear boundaries), include targeted improvements as part of the design. Do NOT propose unrelated refactoring — stay focused on what serves the current goal.

6. DOCUMENT & SAVE (NO COMMITS): Write the approved design to `docs/second-brain/artifacts/specs/YYYY-MM-DD-<topic>-design.md` and save the file. The spec MUST include these sections:
   - **Objective** — What we're building, why, and who it's for
   - **Success Criteria** — Specific, measurable, testable conditions (not vague goals)
   - **Tech Stack** — Framework, language, key dependencies
   - **Commands** — Full executable commands: build, test, lint, run (not just tool names)
   - **Architecture** — Component breakdown and data flow
   - **Security Considerations** — Threat boundaries, AuthN/AuthZ, input validation (MANDATORY)
   - **Boundaries** — Three-tier project rules:
     - *Always:* (e.g., run the project's verification commands before staging, validate all request DTOs at the boundary using the project's chosen validator)
     - *Ask first:* (e.g., DB schema changes, new third-party dependencies, CORS changes)
     - *Never:* (e.g., commit secrets, bypass auth/permission decorators, remove failing tests without approval)
   - **Open Questions** — Anything unresolved requiring human input before planning
   CRITICAL: DO NOT use `git commit` here. The worktree and branch haven't been created yet.
   - **WRITE-TOOL RULE:** Create the spec with the IDE's file-write tool (NOT shell redirection / heredoc), so the IDE's change tracker registers it.
   - **VISIBILITY CHECK (MANDATORY, immediately after saving):** Run `git check-ignore -q docs/second-brain/artifacts/specs/<filename>.md`. Decide on the EXIT CODE only: exit 1 = file is visible → PASS (exit 1 here is success, NOT a command error); exit 0 = file is ignored → remediate below. Do NOT decide from `-v` output alone — `-v` also prints negation (`!…`) patterns, and a match whose pattern starts with `!` means the file IS visible.
     REMEDIATION (only on exit 0): run `git check-ignore -v <path>` to name the culprit pattern (common cause: a generic `artifacts/` build-output pattern, e.g. the standard VisualStudio template), then append these two lines at the END of the `.gitignore` in the SumelaOS install root (the directory containing `docs/second-brain/` — not necessarily the git toplevel) and re-run the `-q` check:
     ```
     !docs/second-brain/artifacts/
     !docs/second-brain/artifacts/**
     ```
     If the lines already exist but the path is still ignored (a later pattern outranks them), re-append them at the END anyway — duplicates are harmless; last match wins. Tell the user what was matched and what you fixed. If STILL ignored (e.g. a parent like `docs/` is itself ignored — negation cannot pierce an excluded parent), STOP and warn the user explicitly: the spec is invisible to `git status` and the IDE's Changes view, and will not be committed; ask how they want to resolve it.

7. CRITICAL WIKI LINKING (MANDATORY): After generating and saving the spec file, you MUST immediately append a link to it in `docs/second-brain/wiki/_INDEX.md` (under "Artifacts") AND in `docs/second-brain/wiki/active-project-context.md`. Use **standard markdown link format** (NOT wikilinks) because artifacts live outside the wiki: `[YYYY-MM-DD-topic-design](../artifacts/specs/YYYY-MM-DD-topic-design.md)`. Do not proceed to review or handoff without creating these links.

8. REVIEW PACKET PREFLIGHT (MECHANICAL ONLY): Before dispatching the spec reviewer, verify the review packet is complete:
   - Spec file exists at the path you will send to the reviewer.
   - `_INDEX.md` and `active-project-context.md` contain the artifact link.
   - Mandatory sections exist: Objective, Success Criteria, Tech Stack, Commands, Architecture, Security Considerations, Boundaries, Open Questions.
   - No placeholder text remains (`TBD`, `TODO`, `fill later`, empty mandatory sections).
   - `git check-ignore -q <spec-path>` exits 1 (file visible — Step 6 visibility check passed or was remediated).
   - This is NOT a quality review. Do not approve your own spec; the independent `spec-document-reviewer-prompt` subagent remains mandatory.

9. SPEC REVIEW LOOP: Dispatch the `spec-document-reviewer-prompt`(./spec-document-reviewer-prompt.md) subagent. Fix issues and re-dispatch until approved (Max 3 iterations, then ask human).

10. FINAL APPROVAL & HANDOFF (RICH MENU): Once the spec is approved by the subagent, present these detailed next steps to the user:
   "The design spec is finalized and saved to `docs/second-brain/artifacts/specs/<filename>.md`. What is our next move?
   1. **Approve & Plan (Proceed to execution):** I will invoke the `writing-plans` skill to break this spec into actionable, bite-sized tasks. We will also determine if we are using the TDD workflow for implementation.
   2. **Revise Spec:** I want to make some manual changes or adjustments to the markdown file before we plan.
   3. **Hold/Discard:** Let's pause here. Do not proceed to planning."

11. TERMINAL STATE: If the user chooses Option 1, invoke the `writing-plans` skill immediately. DO NOT invoke any other skill.
</workflow>

<principles>
- 1 message = 1 question.
- Ruthless YAGNI (You Aren't Gonna Need It).
- Modular design: Units must be independently understandable and testable.
- Security by Design: Architecture must proactively prevent vulnerabilities.
- Never mix unrelated refactoring with current goals.
- The spec is a living document: update it when decisions change during implementation, not just at creation time. An outdated spec is still better than no spec — but a current spec is the goal.
</principles>
