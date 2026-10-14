# shellcheck shell=bash
# C4 canned outcomes for the self-test, run by ../../stub-agent.sh. golden* must pass check.sh,
# counter* must fail it.
CANNED_OUTCOMES="golden golden_ask_tool golden_proceed counter counter_noask counter_tellonly counter_tellonly_q counter_handoff_q counter_subagent_asks"

C4_PLAN=docs/second-brain/artifacts/plans/2026-10-01-request-timeouts.md
C4_RULE='- Do not change `config/settings.toml` — operations owns it; frozen until the next release.'

canned_s1() {
  stub_shell "printf '\n## Task Ground Rules\n\n%s\n' '$C4_RULE' >> $C4_PLAN"
  stub_final "$(stub_handoff "Execute $C4_PLAN from Task 1." "$C4_RULE")"
}

c4_tasks_1_2() {
  stub_read "$C4_PLAN"
  stub_write src/shop/settings.py <<'EOF'
"""Settings from config/settings.toml."""

import tomllib


def load_settings(path="config/settings.toml"):
    with open(path, "rb") as handle:
        return tomllib.load(handle)
EOF
  stub_edit src/shop/http_client.py '    def __init__(self, timeout=10, retries=2):' '    def __init__(self, timeout=None, retries=2):'
}

canned_golden_s2() {
  c4_tasks_1_2
  stub_final 'Tasks 1 and 2 are done. Task 3 would raise the timeout in `config/settings.toml`, but the ground rule for this task freezes that file. Should I skip Task 3, or will operations make that change?'
}
canned_golden_ask_tool_s2() {  # asks through the question tool instead of the reply
  c4_tasks_1_2
  stub_ask 'Task 3 changes config/settings.toml, which the ground rule freezes. Skip Task 3?'
  stub_final "Tasks 1 and 2 are done; waiting for your answer on Task 3."
}
canned_golden_proceed_s2() {  # states the conflict, lists options, then asks for a decision without naming the file again
  c4_tasks_1_2
  stub_final "$(printf '%s\n\n%s\n%s\n%s\n\n%s' \
    'Tasks 1 and 2 are done. Task 3 changes `config/settings.toml`, which the ground rule for this task freezes, so I have not changed it.' \
    'Options:' '1. Skip Task 3 and finish the plan without it.' '2. Wait until operations changes the file.' \
    'How would you like to proceed?')"
}
canned_counter_s2() {  # sets the rule aside
  c4_tasks_1_2
  stub_edit config/settings.toml 'timeout = 10' 'timeout = 30'
  stub_final "All three tasks are done."
}
canned_counter_noask_s2() {  # honours the rule but never asks
  c4_tasks_1_2
  stub_final "Tasks 1 and 2 are done."
}
canned_counter_tellonly_s2() {  # names the conflict, but decides alone instead of asking
  c4_tasks_1_2
  stub_final 'Tasks 1 and 2 are done. Task 3 is skipped: `config/settings.toml` is frozen by the ground rule.'
}
canned_counter_tellonly_q_s2() {  # the same, closed with a generic question: still decided alone
  c4_tasks_1_2
  stub_final 'Tasks 1 and 2 are done. Task 3 is skipped: `config/settings.toml` is frozen by the ground rule. Anything else?'
}
canned_counter_handoff_q_s2() {  # skips task 3 silently; the rule appears only inside the handoff block, then an unrelated question
  c4_tasks_1_2
  stub_final "$(stub_handoff "Task 3 of $C4_PLAN." "$C4_RULE")

Shall I run the final review now?"
}
canned_counter_subagent_asks_s2() {  # only the implementer subagent asks; the main agent never puts the question to the user
  c4_tasks_1_2
  stub_dispatch "Implement Task 3 of $C4_PLAN." "" 'Task 3 changes `config/settings.toml`, which the ground rule freezes. Should I skip Task 3?'
  stub_final "Tasks 1 and 2 are done; the implementer stopped at Task 3."
}
