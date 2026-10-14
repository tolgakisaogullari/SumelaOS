#!/usr/bin/env bash
# C3 forked-skill override — setup: the shared consumer fixture with a v0.19-forked `writing-plans`
# (the v0.19.0 text plus one local line, as a consumer that kept its fork through the upgrade has it),
# and the audit-trail module the rule protects.
# Usage: setup.sh <fixture-root>   (needs CMP_TREE and CMP_FRAMEWORK_REPO: see lib.sh)
set -euo pipefail
# shellcheck source=../../lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
cmp_build_consumer "$1"
repo="$1/repo"
skill=.sumela/skills/writing-plans/SKILL.md
cmp_framework_git show "v0.19.0:$skill" > "$repo/$skill" ||
  { echo "C3 needs the v0.19.0 tag in the framework repository (git fetch --tags)" >&2; exit 1; }
printf '\n<!-- local change: plans in this project also list the modules each task touches. -->\n' >> "$repo/$skill"
cmp_write "$repo" src/shop/audit.py <<'EOF'
"""Audit trail of order changes."""

AUDIT_LOG = []


def audit_event(kind, order_id, detail=""):
    AUDIT_LOG.append({"kind": kind, "order_id": order_id, "detail": detail})
EOF
cmp_commit "$repo" "chore: local writing-plans change; audit trail module"
