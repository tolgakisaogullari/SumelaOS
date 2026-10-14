# shellcheck shell=bash
# C2 canned outcomes for the self-test, run by ../../stub-agent.sh. golden* must pass check.sh,
# counter* must fail it.
CANNED_OUTCOMES="golden golden_staged golden_branch counter counter_both counter_handrolled counter_noexport"

C2_SUMMARIES=docs/second-brain/wiki/session-summaries

c2_json_export() {  # c2_json_export <relpath>: the JSON Lines export the newer decision asks for
  stub_write "$1" <<'EOF'
"""Order export for the analytics pipeline: JSON Lines, one object per order."""

import json


def export_orders(orders, path):
    with open(path, "w", encoding="utf-8") as out:
        for order in orders:
            row = {"order_id": order.order_id, "total": order.total(), "item_count": order.item_count()}
            out.write(json.dumps(row) + "\n")
EOF
}

canned_s1() {
  stub_write "$C2_SUMMARIES/2026-10-14-order-export-plan.md" <<'EOF'
# Session summary — order export plan

## Decisions Made
- The export format is CSV: one row per order with order_id, total and item_count.
EOF
  stub_final "$(stub_handoff "Implement export_orders(orders, path) in src/shop/export.py.")"
}

canned_s2() {
  stub_write "$C2_SUMMARIES/2026-10-14-order-export-format.md" <<'EOF'
# Session summary — order export format changed

## Decisions Made
- The export format is JSON Lines, one object per order per line; it supersedes the CSV decision of the
  previous session (the analytics pipeline ingests JSONL).
EOF
  stub_final "$(stub_handoff "Implement export_orders(orders, path) in src/shop/export.py, as JSON Lines.")"
}

canned_golden_s3() {   # reads both summaries and follows the newer decision
  stub_shell "ls $C2_SUMMARIES"
  stub_read "$C2_SUMMARIES/2026-10-14-order-export-format.md"
  c2_json_export src/shop/export.py
  stub_final "export_orders writes JSON Lines, as decided for this task."
}

canned_golden_staged_s3() {  # the same export, staged with git add: found in the index, no longer an untracked file
  canned_golden_s3
  stub_shell "git add src/shop/export.py"
}

canned_golden_branch_s3() {  # the same export, committed on a branch whose worktree is then removed: found on the branch only
  stub_read "$C2_SUMMARIES/2026-10-14-order-export-format.md"
  stub_shell "git worktree add -q .worktrees/order-export -b feat/order-export"
  c2_json_export .worktrees/order-export/src/shop/export.py
  stub_shell "git -C .worktrees/order-export add src/shop/export.py && git -C .worktrees/order-export commit -q --no-verify -m 'feat: order export as JSON Lines' && git worktree remove --force .worktrees/order-export"
  stub_final "export_orders writes JSON Lines, committed on feat/order-export."
}

canned_counter_s3() {  # follows the superseded decision
  stub_read "$C2_SUMMARIES/2026-10-14-order-export-plan.md"
  stub_write src/shop/export.py <<'EOF'
"""Order export for the analytics pipeline."""

import csv


def export_orders(orders, path):
    with open(path, "w", newline="", encoding="utf-8") as out:
        writer = csv.writer(out)
        writer.writerow(["order_id", "total", "item_count"])
        for order in orders:
            writer.writerow([order.order_id, order.total(), order.item_count()])
EOF
  stub_final "export_orders writes CSV."
}

canned_counter_both_s3() {  # the new format, plus the superseded one "for compatibility"
  c2_json_export src/shop/export.py
  stub_write src/shop/export_csv.py <<'EOF'
"""Legacy CSV export."""

import csv


def export_orders_csv(orders, path):
    with open(path, "w", newline="", encoding="utf-8") as out:
        csv.writer(out).writerows([o.order_id, o.total(), o.item_count()] for o in orders)
EOF
  stub_final "export_orders writes JSON Lines; export_orders_csv keeps CSV."
}

canned_counter_handrolled_s3() {  # neither JSON nor the csv module: comma-separated text by hand
  stub_write src/shop/export.py <<'EOF'
"""Order export."""


def export_orders(orders, path):
    with open(path, "w", encoding="utf-8") as out:
        for order in orders:
            out.write(f"{order.order_id},{order.total()},{order.item_count()}\n")
EOF
  stub_final "export_orders writes one line per order."
}

canned_counter_noexport_s3() {  # JSON Lines, but not the function that was asked for
  stub_write src/shop/export.py <<'EOF'
"""Order export."""

import json


def dump_orders(orders, path):
    with open(path, "w", encoding="utf-8") as out:
        for order in orders:
            out.write(json.dumps({"order_id": order.order_id}) + "\n")
EOF
  stub_final "dump_orders writes JSON Lines."
}
