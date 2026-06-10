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
This skill dispatches a **parallel review panel**: a small set of lane reviewers run concurrently in isolated subagent contexts, each owning a distinct set of dimensions, then you synthesize their reports into one. Parallel + dimension-focused beats a single generalist reviewer — each lane goes deeper, and the lanes cover failure modes a single pass tends to miss. The panel is **task-scoped** (Step 3): a mandatory Correctness + Security floor ALWAYS runs, and you compose the remaining lanes to fit the change. Execute these steps strictly:

1. GATHER CONTEXT (CRITICAL PRE-COMMIT GATE):
   - For staged changes: Get the diff of the currently staged files using `git diff --staged`.
   - If the staged diff is empty but the task is complete, check `git diff` before review so uncommitted work is not accidentally skipped.
   - For intentionally unstaged reviews, state that explicitly in `{HEAD_SHA}` (for example, "Unstaged Working Tree") and pass the exact `git diff` output as `{CODE_DIFF}`.
   - For already committed changes (if specifically requested): Get the exact git SHAs (e.g., `BASE_SHA=$(git rev-parse HEAD~1)` and `HEAD_SHA=$(git rev-parse HEAD)`).

2. CHANGE SIZE CHECK (BEFORE DISPATCH):
   Count lines changed in the diff. If the diff exceeds ~300 lines of meaningful logic changes, STOP and ask the author to split the change. Reviewers cannot give quality feedback on 1000-line diffs; large reviews create rubber-stamping risk.
   Exception: Complete file deletions and automated refactoring where intent is obvious.

3. SCOPE THE PANEL (choose the lanes to fit THIS change):
   - **MANDATORY FLOOR — never skip:** Lane 1 **Correctness & Security** ALWAYS runs (`requesting-code-review/reviewer-correctness-security.md`). Security is non-negotiable regardless of how "trivial" or "docs-only" the change looks — a tiny change can still commit a secret, weaken auth, or break a contract. Do NOT drop this lane for any task.
   - **COMPOSE the remaining 1–3 lanes** to fit the change, drawing from the dimension catalog below. Total panel = **2–4 lanes (default 3)**. For a GENERAL code change, default to Lane 1 PLUS the two standard lanes (3 total: `reviewer-design-contracts.md` + `reviewer-integration-ops.md`). For a SPECIALIZED change, replace or add a task-specific lane (author its prompt — see Step 5).
   - **Dimension catalog** — the starred (\*) dimensions are ALWAYS Lane 1's, non-negotiable; the "relevance" filter applies only to the NON-starred ones: assign every non-starred dimension relevant to the diff to exactly one lane (don't drop a relevant one just because it doesn't fit a standard lane):
     correctness\*, security\*, auth/credential-token-lifecycle\*, conventions/readability, architecture, API/contract stability, backward-compat, integration/impact (graphify), performance, data/persistence & migrations, observability/rollback, testing (adaptive to TDD mode), concurrency/async/state, error-handling/resilience, i18n & accessibility (UI), prompt/LLM-cost (AI features), infra/IaC blast-radius. *(\* = the floor — always covered by Lane 1.)*
     - Note: Lane 1 already inspects the *correctness facet* of `concurrency/async/state` and `error-handling/resilience` (race conditions, error paths). Spinning up a dedicated lane for these on a relevant change is fine — it DEEPENS that facet; the overlap with the floor is intentional, not an "exactly one lane" violation.
   - **Example task-specific lanes:** schema/DB change → a "Data & Migration Safety" lane; heavy threading/async → a "Concurrency & State" lane; an AI/LLM feature → a "Prompt & Token-Cost" lane; pure UI → a "UX, i18n & Accessibility" lane; infra/Terraform → an "Infra & Blast-Radius" lane.
   - Keep it 2–4 lanes: more fragments attention, fewer loses the cross-check. State the chosen lanes in one line so the user sees the composition (e.g., *"Panel: Correctness & Security · Data & Migration Safety · Integration & Ops"*).

4. PREPARE THE SHARED PAYLOAD (FILL ONCE, PASS TO ALL LANES):
   Fill these placeholders precisely — identical content goes to every lane so their findings are comparable and mergeable:
   - `{WHAT_WAS_IMPLEMENTED}`: What you built based on the plan.
   - `{PLAN_OR_REQUIREMENTS}`: What it should do (the original goal). Include the **TDD Mode** (Enabled/Skipped) so the adaptive testing checks resolve correctly.
   - `{BASE_SHA}`: Starting commit (or "HEAD" if reviewing uncommitted/staged changes).
   - `{HEAD_SHA}`: Ending commit (or "Staged Working Tree" / "Unstaged Working Tree" if reviewing uncommitted changes).
   - `{SECURITY_MANDATE}`: Explicitly write: "You MUST evaluate these changes against the `secure-coding-standard` skill. Check for input validation, auth bypasses, authorization gaps, sensitive data leaks, unsafe logging, and the full auth/credential token lifecycle (issuance → storage → transmission → expiry → refresh → revocation → leakage). Severity must be impact-based: auth bypass, data exposure, token/PII logging, injection, or privilege escalation are Critical; lower-impact hardening gaps may be Important."
   - `{DESCRIPTION}`: Brief technical summary of the architectural choices and the security mitigations applied.
   - `{CODE_DIFF}`: The exact output of the git diff command executed in Step 1.

5. DISPATCH THE SCOPED PANEL (ALL CHOSEN LANES, CONCURRENTLY):
   Dispatch the lanes chosen in Step 3 in parallel (one Task/Agent call each, in a single batch so they run concurrently), each with the shared payload from Step 4.
   - **Standard lanes** use their templates from this skill directory: Correctness & Security → `reviewer-correctness-security.md` (always); Design & Contracts → `reviewer-design-contracts.md`; Integration & Operations → `reviewer-integration-ops.md`.
   - **A task-specific lane** (composed in Step 3): author its prompt following the SAME structure as the templates — a `system_role` that names the lane and says "stay in your lane (flag clear cross-lane Criticals under CROSS-LANE FYI)", the shared `review_context` placeholders, lane-specific `review_criteria` built from the dimensions you assigned it, and the SAME `output_format` (Lane header, Strengths, Issues by severity, Cross-lane FYI, Lane verdict, Reasoning). This keeps every lane's output mergeable in Step 6.
   - If the IDE exposes a named `code-reviewer` subagent, dispatch one instance per lane, each fed the corresponding prompt.
   Each lane uses the shared severity model and emits a `Lane verdict: Yes / No / With fixes`:
   | Section | Meaning | Required Action |
   |---------|---------|-----------------|
   | Critical | Blocks commit/merge | Security flaw, data loss, broken functionality, exploitable token-lifecycle gap, silent breaking contract change |
   | Important | Required before proceeding | Architecture problem, missed requirement, risky error handling, meaningful test gap |
   | Minor | Nice to have | Style, small clarity, non-blocking optimization |
   | Recommendations / FYI | Informational | No action needed unless the author chooses |

   Dead Code Hygiene (assign to whichever lane owns conventions/architecture — Design & Contracts by default): "Identify any code that is now unreachable or unused as a result of this change. List it explicitly and ask whether it should be removed; do NOT silently delete it."

6. SYNTHESIZE THE PANEL INTO ONE REPORT (YOU, the orchestrator — do this inline, do NOT dispatch another subagent):
   - **Dedupe:** When two lanes report the same `File:line` + substantively the same issue, merge into one finding; keep the highest severity and note "(flagged by Lane X & Y)".
   - **Promote cross-lane FYIs:** Fold each lane's `Cross-lane FYI` Criticals into the owning lane's section (de-duplicating against what that lane already raised).
   - **Resolve conflicts:** If lanes disagree on a finding's severity or existence, surface it explicitly as `CONFLICT — Lane X says A, Lane Y says B` and apply your own technical judgment to set the merged severity; do not silently drop either view. **Verify, don't blindly apply:** a lane finding can be wrong or even hallucinated — confirm each Critical/Important against the actual code before acting (e.g., a prior real review flagged a tag mismatch that did not exist).
   - **Combined gate (AND):** The panel is `Ready to commit/merge: Yes` ONLY if every lane verdict is `Yes`. If any lane is `No` or `With fixes`, the panel result is `No` / `With fixes`. One lane's Critical blocks the whole panel.
   - Produce a single merged report: `Strengths` (union), `Issues` (Critical / Important / Minor, deduped), `Conflicts` (if any), and `Assessment` with the combined gate + per-lane verdicts listed.

7. HAND-OFF TO RECEIVING SKILL (MANDATORY):
   - Once you have the merged report, you MUST IMMEDIATELY activate the `receiving-code-review` skill to process it.
   - DO NOT attempt to process, commit, or implement the feedback before reviewing the strict rules inside `receiving-code-review`.
   - **If a lane is wrong:** Push back with technical reasoning. Show code or tests that prove correctness. Request clarification. Never blindly implement feedback you disagree with — a single lane's mistaken Critical does not force a change you can technically disprove.

8. RE-REVIEW LOOP (gate on the panel VERDICT — ASK, do NOT silently proceed):
   - **If the panel's combined verdict was NOT `Ready: Yes`** — i.e. findings remained, WHETHER you fixed them via `receiving-code-review` OR technically disproved/declined them — then before returning to the calling workflow, STOP and ASK the user:
     *"Panel found {N} finding(s) ({fixed} fixed, {disproved} disproven/deferred). Re-review the updated code, or proceed to the next step?"* — offer: **(1) re-review** · **(2) proceed**.
     (Keying on the VERDICT, not on "were fixes applied", is deliberate: an outstanding Critical the author declined to fix must NOT slip past silently just because nothing was edited.)
     - If **re-review**: loop back to **Step 1** on the NEW diff — re-gather, **re-scope the panel** (the change may now warrant different lanes), re-dispatch, re-synthesize. Fixes shift the code and a fix can introduce a new issue (a real re-review here caught a secret-leak the first pass's fix had exposed), so re-scope from scratch — though on a SMALL fix delta you MAY re-run only the lane(s) that owned the changed dimensions, while ALWAYS keeping the mandatory Correctness & Security floor.
     - If **proceed**: return control to the calling workflow.
     - The user may run as many rounds as they want — user-driven, no automatic cap. Rounds should converge (each finding fewer/smaller issues); a round that returns `Ready: Yes` ends the loop.
   - **If the panel verdict was `Ready: Yes`** (no outstanding findings): do NOT ask — proceed directly to the calling workflow. (No value in asking to re-review clean code.)
   - **SCOPE:** this loop applies when the FULL panel was dispatched (SDD Step 5 final review / executing-plans checkpoints / ad-hoc). It does NOT govern SDD Step-4 option-(2), which runs its own template-based review-until-approved loop.

   **Workflow integration cadence** (when this skill is dispatched):
   - `subagent-driven-development` -> invoke as the FINAL comprehensive review after all tasks (SDD STEP 5); in Checkpoint mode SDD also keeps its own per-task Stage-1/Stage-2 reviews and the Step 8 re-review loop runs BEFORE control returns to SDD's next-task gate; in Flow mode this final review is the only full review pass and there is no next-task gate.
   - `executing-plans` -> invoke after each batch checkpoint.
   - Ad-hoc development -> invoke before merge to base, or when stuck on a difficult bug.
</dispatch_workflow>

<ide_fallback_protocol>
If the current IDE does NOT expose a physical subagent / Task dispatch primitive (so the scoped lanes cannot run as isolated parallel contexts):

1. NEVER claim "inline execution" is equivalent to the parallel panel.
2. Tell the user that physical context isolation is unavailable in this IDE.
3. Offer two options: `C1` simulate the scoped lanes (from Step 3) as explicit, sequential single-context passes (one per lane), each with a fresh "review as if you did not write this" framing and a distinct written report; or `C2` defer the formal panel to a subagent-capable IDE/session.
4. If `C1`: run the chosen lanes in order (Correctness & Security FIRST — it is the mandatory floor — then the task-composed lanes) using the lane prompts and the same Step 6 synthesis + combined AND-gate, then hand the merged report to `receiving-code-review`. The Step 8 re-review loop still applies (ask the user to re-review or proceed after fixes).
5. As a last-resort degraded single pass (e.g., a trivially small diff where multiple lanes are overkill), the legacy single-reviewer template `requesting-code-review/code-reviewer.md` remains available — but prefer the lane simulation; state explicitly that you used the degraded path.
</ide_fallback_protocol>
