---
name: lane-composition-reference
description: "Dimension catalog and task-specific lane authoring for requesting-code-review. Load ONLY when Step 3 selects the Deep tier (a 4th, task-composed lane). Private to its parent skill."
---

<when_to_load>
Load this at Step 3 only if the tier is **Deep**. Focused and Standard tiers use the fixed
lane templates and never need it.
</when_to_load>

<dimension_catalog>
Lane 1 (Correctness & Security) permanently owns: correctness, security, auth/credential
token lifecycle, scope discipline. Those are never reassigned.

Assign every OTHER dimension the diff actually touches to exactly one lane — do not drop a
relevant dimension just because it does not fit a standard lane:

conventions/readability · architecture · API/contract stability · backward-compat ·
reuse/simplification · integration/impact (graphify) · performance · data/persistence &
migrations · observability/rollback · testing (adaptive to TDD mode) · concurrency/async/state ·
error-handling/resilience · i18n & accessibility · prompt/LLM-cost · infra/IaC blast-radius

A dedicated lane for concurrency or error-handling on a relevant change DEEPENS the facet
Lane 1 already checks. That overlap is intentional, not a double-assignment.
</dimension_catalog>

<task_lane_examples>
| Change | 4th lane |
|---|---|
| schema / DB migration | Data & Migration Safety |
| heavy threading / async | Concurrency & State |
| AI / LLM feature | Prompt & Token-Cost |
| pure UI | UX, i18n & Accessibility |
| infra / Terraform | Infra & Blast-Radius |
</task_lane_examples>

<authoring_contract>
A task-specific lane prompt MUST mirror the standard templates, or its output will not merge
in Step 6:

1. `<system_role>` — name the lane; state that two-plus sibling lanes cover other areas
   independently; "stay in your lane, and put any clear Critical you notice OUTSIDE it under
   CROSS-LANE FYI".
2. `<review_context>` — the Step 4 payload placeholders, verbatim and complete:
   `{WHAT_WAS_IMPLEMENTED}` `{PLAN_OR_REQUIREMENTS}` `{DESCRIPTION}` `{BASE_SHA}` `{HEAD_SHA}`
   `{SECURITY_MANDATE}` `{CHANGED_FILES}` `{VERIFICATION_EVIDENCE}` `{PRIOR_ROUNDS}`
   `{SLICE_INFO}` `{CODE_DIFF}`.
3. `<review_criteria>` — numbered, built from the dimensions you assigned this lane.
4. `<execution_rules>` — **copy the shared block from `reviewer-correctness-security.md`
   verbatim** (SCOPE vs EVIDENCE, READING BUDGET, ATTRIBUTION, ZERO FINDINGS, COVERAGE LINE,
   FAILURE-CHAIN GATE, author's-claims, `{PRIOR_ROUNDS}`), then add one lane-specific
   `SEVERITY STRICTNESS` calibration line. Do NOT restate the severity model — it is canonical
   in `receiving-code-review` → `<severity_model>`. Rewriting the shared block from memory is
   how a custom lane silently loses false-positive control; copy it.
5. `<output_format>` — identical sections and order: Lane header, Strengths, Issues by
   severity, Cross-lane FYI, Coverage, Assessment (Lane verdict + Reasoning).
</authoring_contract>
