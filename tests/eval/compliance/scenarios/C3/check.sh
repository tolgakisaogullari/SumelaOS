#!/usr/bin/env bash
# C3 forked-skill override — check. The consumer kept a v0.19-forked `writing-plans`, which still tells
# the agent to write Task Ground Rules into the plan; a rule ("do not modify src/shop/audit.py") was
# agreed while planning in session 1, and session 2 executed the plan with implementer subagents.
# Pass, new text (the framework ships the task-record tool; the contract's SUPERSEDED clause overrides
#   the fork): `task show --rules` holds the rule AND an implementer dispatch carried it (in its prompt,
#   or read by the subagent itself, e.g. `task show --payload`).
# Pass, old text: the plan's Task Ground Rules block holds the rule.
# Usage: check.sh <meta-dir>. Exit 0 pass, 1 fail, 2 the check could not run.
set -uo pipefail
# shellcheck source=../../lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
m="$1"
TOKEN=audit.py
cmp_need_session "$m" 2

plan_block_rule() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    cmp_section_rule "$f" "$TOKEN" && return 0
  done <<EOF
$(cmp_changed "$m" docs/second-brain/artifacts/plans | cmp_list_files '*.md')
EOF
  return 1
}

if [ "$(cmp_era "$m")" = new ]; then
  cmp_expect "task show --rules holds the audit.py rule" cmp_record_rule "$m" "$TOKEN"
  cmp_expect "an implementer dispatch of session 2 carried the rule" cmp_payload_rule "$m/s2" "$TOKEN"
else
  cmp_expect "the plan's Task Ground Rules block holds the audit.py rule (old text)" plan_block_rule
fi
cmp_verdict
