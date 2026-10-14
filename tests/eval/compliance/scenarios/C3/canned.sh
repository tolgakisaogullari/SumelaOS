# shellcheck shell=bash
# C3 canned outcomes for the self-test, run by ../../stub-agent.sh. golden* must pass check.sh,
# counter* must fail it. CANNED_OUTCOMES run on the framework as built (old text: no task-record
# tool); CANNED_OUTCOMES_NEW run after the self-test plants a stand-in tool (new text).
CANNED_OUTCOMES="golden counter"
CANNED_OUTCOMES_NEW="golden_new golden_new_selfserve counter_new"

C3_PLAN=docs/second-brain/artifacts/plans/2026-10-14-order-notes.md
C3_RULE='- Do not modify `src/shop/audit.py` — the risk team owns the audit trail.'
C3_RECORD=docs/second-brain/wiki/_tasks/2026-10-14-order-notes.md

c3_plan() {  # c3_plan <with-ground-rules-block: yes|no>
  if [ "$1" = yes ]; then
    stub_write "$C3_PLAN" <<EOF
# Order Notes Implementation Plan

**Goal:** A customer can attach a note of at most 200 characters to an order.

## Task Ground Rules

$C3_RULE

### Task 1: \`Order.note\` with validation
### Task 2: the note in \`Order.summary()\`
EOF
  else
    stub_write "$C3_PLAN" <<'EOF'
# Order Notes Implementation Plan

**Goal:** A customer can attach a note of at most 200 characters to an order.

### Task 1: `Order.note` with validation
### Task 2: the note in `Order.summary()`
EOF
  fi
}

canned_golden_s1()  { c3_plan yes; stub_final "$(stub_handoff "Execute the order-notes plan." "$C3_RULE")"; }
canned_counter_s1() { c3_plan no;  stub_final "$(stub_handoff "Execute the order-notes plan.")"; }   # the rule never reached the plan
canned_s2() { stub_dispatch "Implement Task 1 of $C3_PLAN."; stub_final "Both tasks are implemented."; }

# New text: the rule belongs in the task record, and the implementer's payload carries it.
canned_golden_new_s1() {
  c3_plan no
  stub_write "$C3_RECORD" <<EOF
---
type: task
task: 2026-10-14-order-notes
status: active
---

# Task — Order notes

## Task Ground Rules
- R1 · 2026-10-14 · user · do not modify \`src/shop/audit.py\` — the risk team owns the audit trail

## Task Decisions
EOF
  stub_final "$(stub_handoff "Execute the order-notes plan.")"
}
canned_golden_new_s2() {
  stub_dispatch "Implement Task 1 of $C3_PLAN.
TASK_KEY: 2026-10-14-order-notes
TASK_GROUND_RULES: - R1 · 2026-10-14 · user · do not modify \`src/shop/audit.py\` — the risk team owns the audit trail"
  stub_final "Both tasks are implemented."
}
canned_golden_new_selfserve_s1() { canned_golden_new_s1; }
canned_golden_new_selfserve_s2() {  # an empty payload field: the implementer fetches its payload itself
  stub_dispatch "Implement Task 1 of $C3_PLAN.
TASK_KEY: 2026-10-14-order-notes
TASK_GROUND_RULES: [verbatim from task show --payload]" "bash .sumela/skills/using-second-brain/scripts/sumela-wiki.sh task show --task 2026-10-14-order-notes --payload"
  stub_final "Both tasks are implemented."
}
canned_counter_new_s1() { c3_plan yes; stub_final "$(stub_handoff "Execute the order-notes plan." "$C3_RULE")"; }  # followed the fork: plan only
canned_counter_new_s2() { stub_dispatch "Implement Task 1 of $C3_PLAN."; stub_final "Both tasks are implemented."; }
