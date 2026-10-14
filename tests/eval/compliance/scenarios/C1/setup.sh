#!/usr/bin/env bash
# C1 rule carried — setup: the shared consumer fixture and nothing else; session 1 agrees the rule.
# Usage: setup.sh <fixture-root>   (needs CMP_TREE: see lib.sh cmp_prepare_framework)
set -euo pipefail
# shellcheck source=../../lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
cmp_build_consumer "$1"
