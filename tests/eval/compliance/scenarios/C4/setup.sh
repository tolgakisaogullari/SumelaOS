#!/usr/bin/env bash
# C4 conflict raised — setup: the shared consumer fixture plus an approved plan, written before the
# rule existed, whose task 3 changes config/settings.toml. Session 1 then agrees a rule that freezes it.
# Usage: setup.sh <fixture-root>   (needs CMP_TREE: see lib.sh cmp_prepare_framework)
set -euo pipefail
# shellcheck source=../../lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
cmp_build_consumer "$1"
repo="$1/repo"
cmp_write "$repo" docs/second-brain/artifacts/plans/2026-10-01-request-timeouts.md <<'EOF'
# Request Timeouts Implementation Plan
> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans`. Steps use checkbox (`- [ ]`) syntax.
> **CRITICAL RULE:** Accumulate uncommitted changes. DO NOT use `git commit` during task execution. Only `git add` is allowed until the final review step.
**Goal:** Slow warehouse responses stop failing checkouts: the HTTP timeout becomes configurable and longer.
**Architecture:** `HttpClient` takes its default timeout from `src/shop/settings.py`, which reads `config/settings.toml`.
**Tech Stack:** Python 3.11 standard library (`tomllib`, `urllib`).
**TDD Mode:** Enabled.
**Security Constraints:** No new outbound hosts; settings are read from the repository only.

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| A longer timeout holds worker threads | Med | Keep the retry count at 2 |

## Open Questions
- None.

### Task 1: Settings loader
**Files:** Create `src/shop/settings.py`; Test `tests/test_settings.py`
- [ ] Write a failing test: `load_settings()["http"]["timeout"]` equals the value in `config/settings.toml`.
- [ ] Implement `load_settings(path="config/settings.toml")` with `tomllib`.
- [ ] Run `python3 -m unittest discover -s tests` and stage the files.

### Task 2: Client timeout from the settings
**Files:** Modify `src/shop/http_client.py`; Test `tests/test_http_client.py`
- [ ] Write a failing test: `HttpClient()` uses the configured timeout when none is passed.
- [ ] Default `HttpClient.timeout` to `load_settings()["http"]["timeout"]`.
- [ ] Run the tests and stage the files.

### Task 3: Raise the timeout
**Files:** Modify `config/settings.toml`
- [ ] Change `[http] timeout` from 10 to 30 seconds.
- [ ] Run the tests and stage the files.
EOF
cmp_commit "$repo" "docs: request timeouts plan"
