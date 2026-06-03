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
This skill dispatches a **parallel review panel**: three lane reviewers run concurrently in isolated subagent contexts, each focused on a distinct set of dimensions, then you synthesize their reports into one. Parallel + dimension-focused beats a single generalist reviewer — each lane goes deeper, and the lanes cover failure modes a single pass tends to miss. Execute these steps strictly:

1. GATHER CONTEXT (CRITICAL PRE-COMMIT GATE):
   - For staged changes: Get the diff of the currently staged files using `git diff --staged`.
   - If the staged diff is empty but the task is complete, check `git diff` before review so uncommitted work is not accidentally skipped.
   - For intentionally unstaged reviews, state that explicitly in `{HEAD_SHA}` (for example, "Unstaged Working Tree") and pass the exact `git diff` output as `{CODE_DIFF}`.
   - For already committed changes (if specifically requested): Get the exact git SHAs (e.g., `BASE_SHA=$(git rev-parse HEAD~1)` and `HEAD_SHA=$(git rev-parse HEAD)`).

2. CHANGE SIZE CHECK (BEFORE DISPATCH):
   Count lines changed in the diff. If the diff exceeds ~300 lines of meaningful logic changes, STOP and ask the author to split the change. Reviewers cannot give quality feedback on 1000-line diffs; large reviews create rubber-stamping risk.
   Exception: Complete file deletions and automated refactoring where intent is obvious.

3. PREPARE THE SHARED PAYLOAD (FILL ONCE, PASS TO ALL THREE LANES):
   Fill these placeholders precisely — identical content goes to every lane so their findings are comparable and mergeable:
   - `{WHAT_WAS_IMPLEMENTED}`: What you built based on the plan.
   - `{PLAN_OR_REQUIREMENTS}`: What it should do (the original goal). Include the **TDD Mode** (Enabled/Skipped) so the adaptive testing checks resolve correctly.
   - `{BASE_SHA}`: Starting commit (or "HEAD" if reviewing uncommitted/staged changes).
   - `{HEAD_SHA}`: Ending commit (or "Staged Working Tree" / "Unstaged Working Tree" if reviewing uncommitted changes).
   - `{SECURITY_MANDATE}`: Explicitly write: "You MUST evaluate these changes against the `secure-coding-standard` skill. Check for input validation, auth bypasses, authorization gaps, sensitive data leaks, unsafe logging, and the full auth/credential token lifecycle (issuance → storage → transmission → expiry → refresh → revocation → leakage). Severity must be impact-based: auth bypass, data exposure, token/PII logging, injection, or privilege escalation are Critical; lower-impact hardening gaps may be Important."
   - `{DESCRIPTION}`: Brief technical summary of the architectural choices and the security mitigations applied.
   - `{CODE_DIFF}`: The exact output of the git diff command executed in Step 1.

4. DISPATCH THE PARALLEL REVIEW PANEL (3 LANES, CONCURRENTLY):
   Dispatch all three lane subagents in parallel (one Task/Agent call each, in a single batch so they run concurrently), each with the shared payload from Step 3 and its lane template from this skill directory:
   - **Lane 1 — Correctness & Security:** `requesting-code-review/reviewer-correctness-security.md` — correctness, security, auth/credential token lifecycle, security-boundary tests.
   - **Lane 2 — Design & Contracts:** `requesting-code-review/reviewer-design-contracts.md` — conventions/readability, architecture, API/contract stability, backward compatibility.
   - **Lane 3 — Integration & Operations:** `requesting-code-review/reviewer-integration-ops.md` — cross-module integration/impact (graphify), performance, data/persistence, observability/rollback, general test coverage.

   If the IDE exposes a named `code-reviewer` subagent, dispatch three instances of it, each fed the corresponding lane template content as its prompt.
   Each lane uses the shared severity model and emits a `Lane verdict: Yes / No / With fixes`:
   | Section | Meaning | Required Action |
   |---------|---------|-----------------|
   | Critical | Blocks commit/merge | Security flaw, data loss, broken functionality, exploitable token-lifecycle gap, silent breaking contract change |
   | Important | Required before proceeding | Architecture problem, missed requirement, risky error handling, meaningful test gap |
   | Minor | Nice to have | Style, small clarity, non-blocking optimization |
   | Recommendations / FYI | Informational | No action needed unless the author chooses |

   Dead Code Hygiene (applies to Lane 2): "Identify any code that is now unreachable or unused as a result of this change. List it explicitly and ask whether it should be removed; do NOT silently delete it."

5. SYNTHESIZE THE PANEL INTO ONE REPORT (YOU, the orchestrator — do this inline, do NOT dispatch another subagent):
   - **Dedupe:** When two lanes report the same `File:line` + substantively the same issue, merge into one finding; keep the highest severity and note "(flagged by Lane X & Y)".
   - **Promote cross-lane FYIs:** Fold each lane's `Cross-lane FYI` Criticals into the owning lane's section (de-duplicating against what that lane already raised).
   - **Resolve conflicts:** If lanes disagree on a finding's severity or existence, surface it explicitly as `CONFLICT — Lane X says A, Lane Y says B` and apply your own technical judgment to set the merged severity; do not silently drop either view.
   - **Combined gate (AND):** The panel is `Ready to commit/merge: Yes` ONLY if every lane verdict is `Yes`. If any lane is `No` or `With fixes`, the panel result is `No` / `With fixes`. One lane's Critical blocks the whole panel.
   - Produce a single merged report: `Strengths` (union), `Issues` (Critical / Important / Minor, deduped), `Conflicts` (if any), and `Assessment` with the combined gate + per-lane verdicts listed.

6. HAND-OFF TO RECEIVING SKILL (MANDATORY):
   - Once you have the merged report, you MUST IMMEDIATELY activate the `receiving-code-review` skill to process it.
   - DO NOT attempt to process, commit, or implement the feedback before reviewing the strict rules inside `receiving-code-review`.
   - **If a lane is wrong:** Push back with technical reasoning. Show code or tests that prove correctness. Request clarification. Never blindly implement feedback you disagree with — a single lane's mistaken Critical does not force a change you can technically disprove.

   **Workflow integration cadence** (when this skill is dispatched):
   - `subagent-driven-development` -> invoke as the FINAL comprehensive review after all tasks (SDD STEP 5); SDD keeps its own per-task Stage-1/Stage-2 reviews.
   - `executing-plans` -> invoke after each batch checkpoint.
   - Ad-hoc development -> invoke before merge to base, or when stuck on a difficult bug.
</dispatch_workflow>

<ide_fallback_protocol>
If the current IDE does NOT expose a physical subagent / Task dispatch primitive (so the three lanes cannot run as isolated parallel contexts):

1. NEVER claim "inline execution" is equivalent to the parallel panel.
2. Tell the user that physical context isolation is unavailable in this IDE.
3. Offer two options: `C1` simulate the three lanes as three explicit, sequential single-context passes (one per lane template), each with a fresh "review as if you did not write this" framing and a distinct written report; or `C2` defer the formal panel to a subagent-capable IDE/session.
4. If `C1`: run the lanes in order (Correctness & Security → Design & Contracts → Integration & Operations) using the same lane templates and the same Step 5 synthesis + combined AND-gate, then hand the merged report to `receiving-code-review`.
5. As a last-resort degraded single pass (e.g., a trivially small diff where three lanes are overkill), the legacy single-reviewer template `requesting-code-review/code-reviewer.md` remains available — but prefer the lane simulation; state explicitly that you used the degraded path.
</ide_fallback_protocol>
