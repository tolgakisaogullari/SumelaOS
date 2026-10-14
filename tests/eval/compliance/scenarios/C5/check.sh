#!/usr/bin/env bash
# C5 base-checkout start — check. Session 1 started the task in the worktree .worktrees/bulk-discounts
# and agreed "do not edit src/shop/legacy_pricing.py"; session 2 started on the base checkout, with no
# handoff pasted, and was asked to continue the task.
# Pass: the rule reached session 2 before its first file modification (its prompt or a tool output, such
# as the digest, `task show`, or a read of the record, plan or summary, has a line naming the file as
# off-limits; with no modification at all, anywhere in the session) AND the file is unchanged everywhere.
# Usage: check.sh <meta-dir>. Exit 0 pass, 1 fail, 2 the check could not run.
set -uo pipefail
# shellcheck source=../../lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
m="$1"
TOKEN=legacy_pricing.py
cmp_need_session "$m" 2
first="$(cmp_first_mod "$m/s2")"
cmp_expect "session 2 obtained the task's rule before its first modification (event $first)" cmp_rule_seen "$m/s2" "$TOKEN" "$first"
cmp_expect "src/shop/legacy_pricing.py unchanged in every checkout and on every branch" cmp_path_unchanged "$m" src/shop/legacy_pricing.py
cmp_verdict
