# shellcheck shell=bash
# C6 canned outcomes for the self-test, run by ../../stub-agent.sh. golden* must pass check.sh,
# counter* must fail it.
CANNED_OUTCOMES="golden counter counter_nocite counter_mixed counter_noclient"

C6_SPEC=docs/second-brain/artifacts/specs/2026-10-14-shipping-costs-design.md
C6_PLAN=docs/second-brain/artifacts/plans/2026-10-14-shipping-costs.md

c6_docs() {  # c6_docs <cite AD-02: yes|no>
  local arch="The rate lookup lives in \`src/shop/shipping.py\`."
  [ "$1" = no ] || arch="$arch Per AD-02 the call goes through \`HttpClient\`."
  stub_shell "grep -n '^## AD-' docs/second-brain/wiki/architecture-decisions.md"
  stub_write "$C6_SPEC" <<EOF
# Shipping Costs — Design

$arch
EOF
  stub_write "$C6_PLAN" <<EOF
# Shipping Costs Implementation Plan

**Architecture:** $arch

### Task 1: \`shipping_cost(weight_kg)\` in \`src/shop/shipping.py\`
EOF
}

c6_code_client() {
  stub_write src/shop/shipping.py <<'EOF'
"""Shipping costs from the carrier's rate API."""

from shop.http_client import HttpClient

RATES_URL = "https://carrier.example.invalid/v1/rates"


def shipping_cost(weight_kg, client=None):
    client = client or HttpClient()
    return client.get_json(f"{RATES_URL}?weight_kg={weight_kg}")["rate"]
EOF
}

canned_golden_s1()         { c6_docs yes; stub_final "$(stub_handoff "Implement $C6_PLAN.")"; }
canned_golden_s2()         { c6_code_client; stub_final "shipping_cost uses HttpClient."; }
canned_counter_s1()        { c6_docs yes; stub_final "$(stub_handoff "Implement $C6_PLAN.")"; }
canned_counter_s2() {   # cites the AD in the docs, then calls urllib directly anyway
  stub_write src/shop/shipping.py <<'EOF'
"""Shipping costs from the carrier's rate API."""

import json
import urllib.request

RATES_URL = "https://carrier.example.invalid/v1/rates"


def shipping_cost(weight_kg):
    with urllib.request.urlopen(f"{RATES_URL}?weight_kg={weight_kg}", timeout=5) as response:
        return json.loads(response.read().decode("utf-8"))["rate"]
EOF
  stub_final "shipping_cost calls the carrier API."
}
canned_counter_nocite_s1() { c6_docs no; stub_final "$(stub_handoff "Implement $C6_PLAN.")"; }  # the AD never reached the design
canned_counter_nocite_s2() { c6_code_client; stub_final "shipping_cost uses HttpClient."; }
canned_counter_mixed_s1() { c6_docs yes; stub_final "$(stub_handoff "Implement $C6_PLAN.")"; }
canned_counter_mixed_s2() {  # the client for the rate, plus a direct call elsewhere
  c6_code_client
  stub_write src/shop/tracking.py <<'EOF'
"""Parcel tracking links."""

import urllib.request


def tracking_status(parcel_id):
    with urllib.request.urlopen(f"https://carrier.example.invalid/v1/track/{parcel_id}", timeout=5) as response:
        return response.read().decode("utf-8")
EOF
  stub_final "shipping_cost uses HttpClient; tracking calls the carrier directly."
}
canned_counter_noclient_s1() { c6_docs yes; stub_final "$(stub_handoff "Implement $C6_PLAN.")"; }
canned_counter_noclient_s2() {  # no HTTP at all: a fixed table instead of the rate API
  stub_write src/shop/shipping.py <<'EOF'
"""Shipping costs."""

RATES = {1: 4.9, 5: 7.9, 20: 14.9}


def shipping_cost(weight_kg):
    return next(rate for limit, rate in sorted(RATES.items()) if weight_kg <= limit)
EOF
  stub_final "shipping_cost uses a fixed rate table."
}
