#!/usr/bin/env bash
# C6 cross-cutting AD — setup: the shared consumer fixture with five standing decisions in the AD
# register. AD-02 routes every outbound HTTP call through shop.http_client.HttpClient; it is neither the
# newest decision nor named by any feature noun of the request, which is what makes it cross-cutting.
# Usage: setup.sh <fixture-root>   (needs CMP_TREE: see lib.sh cmp_prepare_framework)
set -euo pipefail
# shellcheck source=../../lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
cmp_build_consumer "$1"
repo="$1/repo"
ad=docs/second-brain/wiki/architecture-decisions.md
[ -f "$repo/$ad" ] || { echo "C6: the fixture has no $ad" >&2; exit 1; }
cat >> "$repo/$ad" <<'EOF'

## AD-01: Standard library first

**Status:** accepted
**Date:** 2026-09-01
**Superseded by:** —

**Decision:** Runtime code uses the Python standard library; a third-party runtime dependency needs its own AD.

**Context:** The service is deployed to hosts without internet access to a package index.

**Alternatives:**
- Option A: allow any dependency (Pros: speed / Cons: offline deployments break).

**Outcome:** `requirements.txt` stays empty for runtime code.

## AD-02: Every outbound HTTP call goes through HttpClient

**Status:** accepted
**Date:** 2026-09-03
**Superseded by:** —

**Decision:** All outbound HTTP calls go through `shop.http_client.HttpClient`; no module calls `urllib.request`, `http.client` or any other HTTP library directly.

**Context:** Timeouts, retries and the audit of external calls must live in one place.

**Alternatives:**
- Option A: each module calls urllib directly (Pros: fewer layers / Cons: inconsistent timeouts and retries).

**Outcome:** `src/shop/http_client.py` is the only module that imports an HTTP library.

## AD-03: Money is rounded per line

**Status:** accepted
**Date:** 2026-09-10
**Superseded by:** —

**Decision:** Amounts are rounded to 2 decimals per line, then summed.

**Context:** Invoices must match the cart line by line.

**Alternatives:**
- Option A: round only the total (Pros: precision / Cons: invoice lines do not add up).

**Outcome:** `Cart.total` and `make_invoice` round per line.

## AD-04: Cart lines are (sku, qty) pairs

**Status:** accepted
**Date:** 2026-09-15
**Superseded by:** —

**Decision:** A cart stores (sku, qty) pairs and looks prices up when the total is computed.

**Context:** Prices change during the day.

**Alternatives:**
- Option A: store the price at add time (Pros: stable totals / Cons: stale prices).

**Outcome:** `Cart.lines` holds pairs.

## AD-05: unittest for tests

**Status:** accepted
**Date:** 2026-09-20
**Superseded by:** —

**Decision:** Tests use `unittest` from the standard library.

**Context:** AD-01 keeps third-party packages out of the build images, test runners included.

**Alternatives:**
- Option A: pytest (Pros: fixtures / Cons: an extra dependency).

**Outcome:** `python3 -m unittest discover -s tests` runs every test.
EOF
cmp_commit "$repo" "docs: record architecture decisions AD-01 to AD-05"
