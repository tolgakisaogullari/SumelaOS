---
name: requesting-code-review
description: "Use when completing a task, implementing a major feature, or before merging — and whenever the user asks to review code, a diff, a PR, staged changes, or a branch — to catch issues before they cascade into committed history."
---

<usage_criteria>
- MANDATORY before ANY commit (review staged/uncommitted changes first), after a task/feature, and before merging to main.
- SECURITY GATE: the final firewall — code MUST be evaluated against security guidelines before entering history.
- OPTIONAL but valuable: when stuck, before a major refactor, after a complex bug fix.
- FORBIDDEN: never skip a review because a change seems "simple". The panel SCALES DOWN for small changes (Step 3) — it never disappears.
</usage_criteria>

<dispatch_workflow>
Lane reviewers run concurrently in isolated subagent contexts, each owning distinct dimensions; you synthesize their reports. Dimension-focused lanes go deeper than one generalist pass and cover failure modes it misses. The panel is task-scoped: a mandatory Correctness & Security floor always runs, the rest is sized to the change.

1. GATHER CONTEXT & CLEAR PRECONDITIONS:
   - Staged: `git diff --staged`. If empty but the task is done, check `git diff` so uncommitted work is not skipped. For a deliberate unstaged review set `{HEAD_SHA}` = "Unstaged Working Tree".
   - Committed: `BASE_SHA=$(git rev-parse HEAD~1)`, `HEAD_SHA=$(git rev-parse HEAD)`. For a multi-commit branch use `git merge-base`, not `HEAD~1`.
   - `{CHANGED_FILES}`: `git diff --staged --name-only` (or matching) — lanes open files by path, not by parsing hunk headers.
   - **VERIFICATION PRECONDITION — clear it here, never let it become a finding.** If `verification-before-completion` has not run on this tree this session, run it, or tell the user the tree is UNVERIFIED. Fill `{VERIFICATION_EVIDENCE}` with its evidence block (command, cwd, exit code, failure count, summary) or the literal `NOT RUN`. It is ONE fact about the tree: as a lane finding, every lane in every slice re-reports it and every verdict becomes `With fixes` forever.
   - **PRIOR ROUNDS:** read the newest `.sumela/reviews/` report for this branch (Step 6c). If its `reviewed_state` covers the same work, seed `{PRIOR_ROUNDS}` from its `Rejected on verification`, `Unproven` and outcome ledger — each as `<id> | <outcome> | <the finding in one line> | <reason>`, since a bare id means nothing to a lane — and set round = its round + 1. Else `none (round 1)`. This is what makes rounds CONVERGE, including when an outer workflow re-invokes this skill from the top.
     - **Unproven staleness:** an UNPROVEN finding surviving two rounds with no new evidence and no edit to its cited file becomes `UNPROVEN — stale`: it STOPS blocking and is listed for the author's decision. Without it the loop cannot terminate, and a user trained to dismiss blocks ignores the real ones.
   - **SELF-MODIFICATION:** if `{CHANGED_FILES}` touches `.sumela/` (except `reviews/` and `_migration/`), `scripts/`, `AGENTS.md`, an IDE pointer, `.github/workflows/`, or `.github/CODEOWNERS`, read `requesting-code-review/self-modification-guard.md` and follow it — this diff can loosen its own review.

2. SIZE & SLICE (MECHANICAL — never estimate):
   - Run `git diff --numstat` and **print the raw added+removed total**.
   - You MAY exclude lockfiles, generated/vendored files and mechanical renames — but MUST print each excluded path with its line count and reason. An exclusion you did not print did not happen.
   - `<= 300` lines → one slice. `> 300` → **do NOT refuse.** Slice into coherent groups of <= 300 (by module/feature/layer; a change and its tests stay together; never split one function) and run the panel per slice, merging in Step 6. Announce: *"N lines of logic → K slices. A change this size is also a signal the commit should be split; that is your call, not a blocker."*
   - WHY THIS IS NOT A GATE: refusing a large diff produces ZERO review, and since the "author" is usually you, a refusal can only deadlock or be rationalized around. 300 is a slicing unit, not a stop sign.
   - After merging, check explicitly for issues visible only ACROSS slices (a contract changed in slice A whose consumer lives in slice B).

3. SCOPE THE PANEL (tier first, mechanically):
   Grep `{CHANGED_FILES}` and the diff body for:
   `auth|login|logout|session|token|secret|credential|password|crypt|migration|schema|ALTER |DROP |payment|billing|invoice|pii|\.tf$|\.tfvars$|iam|policy\.json|Dockerfile|\.github/workflows`

   | Tier | Rule | Panel |
   |---|---|---|
   | **Deep** | ANY hit | Lane 1 + Design & Contracts + Integration & Ops + 1 task-specific lane |
   | **Focused** | NO hit AND Step 2 count <= 40 | Lane 1 + Design & Contracts (2) |
   | **Standard** | everything else | Lane 1 + Design & Contracts + Integration & Ops |

   Print the grep output and the tier. **Judgment may ESCALATE a tier, NEVER de-escalate one** — a self-scored discount on the mandatory gate is the failure mode this closes.
   - **MANDATORY FLOOR:** Lane 1 (`reviewer-correctness-security.md`) runs at EVERY tier; Design & Contracts joins it even at Focused, because a tiny change can silently break a contract and that is Lane 2's, not Lane 1's. Standard lanes: `reviewer-design-contracts.md`, `reviewer-integration-ops.md`. A dimension the diff clearly touches must be owned by some lane, at any tier. **Deep only:** `requesting-code-review/lane-composition.md` for the dimension catalog and the task-lane contract.
   - State tier + composition in one line: *"Deep (grep hit: `token` in auth/session.py) — Panel: Correctness & Security · Data & Migration Safety · Design & Contracts · Integration & Ops"*.

4. PREPARE THE SHARED PAYLOAD — **this step is the SINGLE filling authority.** Callers never fill fields; every field gets a value HERE or an explicit default, because an unfilled `{PLACEHOLDER}` reaches a lane as literal text it cannot distinguish from real content.
   - `{WHAT_WAS_IMPLEMENTED}` · `{PLAN_OR_REQUIREMENTS}` incl. **TDD Mode** (Enabled/Skipped), so the adaptive testing checks resolve · `{BASE_SHA}`/`{HEAD_SHA}` · `{CHANGED_FILES}` · `{VERIFICATION_EVIDENCE}` or `NOT RUN` · `{PRIOR_ROUNDS}` or `none (round 1)` · `{SLICE_INFO}` = `slice K of N — <paths>` or `single slice` · `{CODE_DIFF}` for this slice.
   - `{DESCRIPTION}`: architectural choices and the security mitigations applied. Lanes treat this as a CLAIM to verify, not context to trust.
   - `{SECURITY_MANDATE}`: "Evaluate against the `secure-coding-standard` skill: input validation, auth bypasses, authorization gaps, sensitive-data leaks, unsafe logging, and the full auth/credential token lifecycle (issuance → storage → transmission → expiry → refresh → revocation → leakage). Severity is impact-based per the canonical model."

5. DISPATCH ALL CHOSEN LANES CONCURRENTLY — one Task/Agent call each, in a single batch, every lane getting the identical Step 4 payload so findings are mergeable. If the IDE exposes a named `code-reviewer` subagent, dispatch one per lane. No subagent primitive → read `requesting-code-review/ide-fallback.md`, whose last resort is `requesting-code-review/code-reviewer.md`.
   - **Severity model:** canonical in `receiving-code-review` → `<severity_model>`. Do NOT restate the TABLE; one lane-specific strictness line is calibration, not redefinition. For the gate you need only: **any Critical or Important blocks; Minor and FYI do not; a finding labelled `(unproven)` keeps its severity.**
   - **Dead Code Hygiene** (Design & Contracts): "List code this change makes unreachable or unused and ask whether to remove it; never silently delete it."

6. SYNTHESIZE (YOU, inline — do NOT dispatch a subagent for this):

   **6a. VERIFY EVERY CRITICAL AND IMPORTANT BEFORE IT ENTERS THE REPORT.** A lane finding can be wrong or hallucinated (a prior real review flagged a tag mismatch that did not exist). You have repo access and no stake in any lane's framing — re-derive each from the code rather than adopting the lane's wording, and write exactly one line per finding:

   ```
   <File:line> | CONFIRMED — <the exact line or grep output that proves it>
              | REJECTED  — <the exact line or grep output that disproves it>
              | UNPROVEN  — <what evidence would settle it, and why you could not get it>
   ```

   REJECTED stands on three grounds only: quoted contradicting code; a diff comment documenting the behaviour as deliberate; or **a scoped negative search** (pattern, where run, `0 hits`) — that IS evidence, and without it no absence-of-control finding could ever be rejected. Anything less certain is UNPROVEN, never deleted.

   No evidence line → the finding does not enter the report. `CONFIRMED` reports as-is. **`UNPROVEN` reports at its ORIGINAL severity**, labelled `(unproven)`: verification that could not settle a finding is a gap in the verification, not evidence the finding is weak — and the hardest findings to settle are the absence-of-control ones (no revocation path, no boundary test, no rollback) that the security floor exists to catch. `REJECTED` moves to a `Rejected on verification` appendix — visible, not actionable, carried into the next round's `{PRIOR_ROUNDS}`.

   **6b. MERGE.**
   - Dedupe: same `File:line` + substantively the same issue → one finding, highest severity, "(flagged by Lane X & Y)".
   - Fold each lane's Cross-lane FYI Criticals into the owning section, de-duplicated.
   - Disagreement → surface as `CONFLICT — Lane X says A, Lane Y says B`, then apply your own technical judgment. Never silently drop either view.
   - **Check the coverage lines.** Zero findings with a thin or missing one means the lane did not review — re-dispatch it, don't count it clean.
   - **Aggregate, then id:** one root cause at several sites is ONE finding listing every location (severity = worst site's); otherwise a 3-slice panel reports it 12 times. Ids `r<round>.F<n>` are assigned here, after aggregation — never in a lane (slices collide), never severity-coded (dedupe raises severity and orphans the last ledger).
   - **GAP SWEEP:** the lanes are partitioned, so some defects belong to no lane. Run `requesting-code-review/gap-sweep.md` — four diff-derived searches, each printed with its hit count. Its findings go through 6a too.
   - **Combined gate (AND):** `Ready: Yes` only if every lane in every slice returned `Yes` AND `{VERIFICATION_EVIDENCE}` covers this diff. With `NOT RUN`, the best available verdict is `With fixes` — a panel cannot certify a tree nothing executed.
   - Section order: see `review-report.md` → `<body>`. Do not restate it — an order written from memory dropped `Unproven`, which Step 1 reads back.

   **6c. WRITE THE ARTIFACT — this is what downstream gates check; a report that lives only in chat is not evidence.** Format, location, the pre-write `git check-ignore` guard, and how a gate validates it are defined ONCE in `requesting-code-review/review-report.md`. Follow it; do not restate the field list here or in a gate.

7. HAND-OFF:
   - `Ready: Yes`, no outstanding findings → nothing to receive; go to the calling workflow.
   - Otherwise activate `receiving-code-review` IMMEDIATELY. Do not process, commit, or implement feedback before reading its rules.
   - **If a lane is wrong:** push back with technical reasoning — show the code or test that proves correctness. A mistaken Critical does not force a change you can disprove.

8. RE-REVIEW LOOP (gate on the VERDICT — ASK, never silently proceed):
   - **Verdict NOT `Ready: Yes`** — whether you fixed the findings or disproved/declined them — STOP and ASK: *"Panel found {N} finding(s) ({fixed} fixed, {disproved} disproven/deferred). Re-review, or proceed?"* — offer **(1) re-review** · **(2) proceed**. Keying on the VERDICT rather than "were fixes applied" is deliberate: an outstanding Critical the author declined must not slip past because nothing was edited.
     - re-review → Step 1 on the NEW diff: re-gather, re-size, re-scope (the tier may change), re-dispatch, re-synthesize. `{PRIOR_ROUNDS}` travels, so settled findings do not return. On a small fix delta you MAY re-run only the lanes owning the changed dimensions, ALWAYS keeping the floor.
     - proceed → record `user_decision: proceed` in the 6c artifact (this stops a downstream gate re-blocking a choice the user already made), then return control.
     - No cap; rounds should converge. `Ready: Yes` ends the loop.
   - **Verdict `Ready: Yes`** → proceed without asking.
   - SCOPE: applies when the panel was dispatched. Does NOT govern SDD Step-4 option-(2), which runs its own review-until-approved loop.

</dispatch_workflow>
