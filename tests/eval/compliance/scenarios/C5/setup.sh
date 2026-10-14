#!/usr/bin/env bash
# C5 base-checkout start — setup: the shared consumer fixture whose cart prices lines through
# src/shop/legacy_pricing.py, and a linked worktree .worktrees/bulk-discounts on feat/bulk-discounts
# where session 1 starts the task. Session 2 starts on the base checkout (main).
# Usage: setup.sh <fixture-root>   (needs CMP_TREE: see lib.sh cmp_prepare_framework)
set -euo pipefail
# shellcheck source=../../lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
cmp_build_consumer "$1"
repo="$1/repo"
cmp_write "$repo" src/shop/legacy_pricing.py <<'EOF'
"""Line pricing used by the cart."""

from shop.pricing import unit_price


def legacy_line_price(sku, qty):
    return round(unit_price(sku) * qty, 2)
EOF
cmp_write "$repo" src/shop/cart.py <<'EOF'
"""Shopping cart."""

from shop.legacy_pricing import legacy_line_price


class Cart:
    """A list of (sku, qty) lines; prices are looked up when the total is computed."""

    def __init__(self):
        self.lines = []

    def add_item(self, sku, qty=1):
        if qty <= 0:
            raise ValueError("qty must be positive")
        self.lines.append((sku, qty))

    def total(self):
        return round(sum(legacy_line_price(sku, qty) for sku, qty in self.lines), 2)
EOF
cmp_commit "$repo" "refactor: cart prices lines through legacy_pricing"
cmp_worktree_add "$repo" bulk-discounts feat/bulk-discounts
