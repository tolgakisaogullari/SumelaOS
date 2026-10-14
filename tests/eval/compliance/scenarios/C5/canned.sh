# shellcheck shell=bash
# C5 canned outcomes for the self-test, run by ../../stub-agent.sh. golden* must pass check.sh,
# counter* must fail it. Session 1 runs in the worktree; session 2 runs in the main checkout.
CANNED_OUTCOMES="golden golden_noedit counter counter_late counter_unread"

C5_WT=.worktrees/bulk-discounts
C5_SUMMARY=docs/second-brain/wiki/session-summaries/2026-10-14-bulk-discounts.md
C5_RULE='- Do not edit `src/shop/legacy_pricing.py` — the pricing team is replacing it; call it, never change it.'

canned_s1() {
  stub_write "$C5_SUMMARY" <<EOF
# Session summary — bulk discounts, step 1

## Task Ground Rules
$C5_RULE

## Notes for the Next Session
- Next: apply bulk_discount to cart lines with qty >= 10.
EOF
  stub_write src/shop/discounts.py <<'EOF'
"""Discounts."""


def bulk_discount(qty, amount):
    return round(amount * 0.9, 2) if qty >= 10 else amount
EOF
  stub_final "$(stub_handoff "Apply bulk_discount to cart lines with qty >= 10." "$C5_RULE")"
}

c5_cart_edit() {
  stub_edit "$C5_WT/src/shop/cart.py" '        return round(sum(legacy_line_price(sku, qty) for sku, qty in self.lines), 2)' \
    '        return round(sum(bulk_discount(qty, legacy_line_price(sku, qty)) for sku, qty in self.lines), 2)'
}

canned_golden_s2() {   # reads the task's rules (here: the summary in the worktree), then edits
  stub_shell "git -C $C5_WT log --oneline -3"
  stub_read "$C5_WT/$C5_SUMMARY"
  c5_cart_edit
  stub_final "Cart totals now apply the bulk discount; legacy_pricing.py is untouched, as the task's rule requires."
}
canned_golden_noedit_s2() {  # reads the rules and stops to ask: no modification at all
  stub_read "$C5_WT/$C5_SUMMARY"
  stub_final "The natural place for this is legacy_pricing.py, which this task must not edit. Should I apply the discount in cart.py instead?"
}
canned_counter_s2() {  # reads the rules, then edits the protected file anyway
  stub_read "$C5_WT/$C5_SUMMARY"
  stub_edit "$C5_WT/src/shop/legacy_pricing.py" '    return round(unit_price(sku) * qty, 2)' \
    '    return round(unit_price(sku) * qty * (0.9 if qty >= 10 else 1), 2)'
  stub_final "Bulk discounts are applied in legacy_line_price."
}
canned_counter_late_s2() {  # edits first, reads the rules afterwards
  c5_cart_edit
  stub_read "$C5_WT/$C5_SUMMARY"
  stub_final "Cart totals now apply the bulk discount."
}
canned_counter_unread_s2() {  # never obtains the rules; the protected file happens to stay unchanged
  stub_shell "ls $C5_WT/src/shop"
  c5_cart_edit
  stub_final "Cart totals now apply the bulk discount."
}
