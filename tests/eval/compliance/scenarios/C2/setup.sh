#!/usr/bin/env bash
# C2 superseded decision — setup: the shared consumer fixture; sessions 1 and 2 make the decisions.
# Usage: setup.sh <fixture-root>   (needs CMP_TREE: see lib.sh cmp_prepare_framework)
set -euo pipefail
# shellcheck source=../../lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
cmp_build_consumer "$1"
