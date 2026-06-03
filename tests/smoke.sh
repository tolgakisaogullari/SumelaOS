#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/smoke.sh — end-to-end smoke test for the SumelaOS setup pipeline.
#
# The script layer (setup.sh self-modifies the project: renders templates,
# registers plugins, edits SKILL_REGISTRY.md, wires hooks) is the highest-risk,
# previously-untested code in the framework — CI only parse-checked it. This test
# runs setup against a throwaway COPY of the repo and asserts the contract:
#
#   1. setup --non-interactive succeeds
#   2. AGENTS.md + every selected IDE pointer (incl. .opencode) is generated
#   3. a selected plugin is registered EXACTLY once
#   4. validate-structure + reconcile --check pass on the result
#   5. a SECOND setup run is idempotent (no duplicate plugin entry, still valid)
#
# Dependency-free (bash + coreutils + python3 for reconcile). Run from anywhere:
#   bash tests/smoke.sh
# Exit 0 = all assertions passed, 1 = a failure (printed above).
# -----------------------------------------------------------------------------
set -uo pipefail

# Keep the smoke test hermetic: setup wires the memory plugins, but we don't want
# it to pip-install / start Docker / pull models here. (setup-memory.sh is covered
# by its own checks.)
export SUMELA_SKIP_MEMORY_SETUP=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0 FAIL=0
ok()   { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
# assert_file <path> <label>
assert_file() { if [ -f "$WORK/$1" ]; then ok "$2"; else bad "$2 (missing: $1)"; fi; }
# assert_count <needle> <file> <expected> <label>
assert_count() {
  local n; n="$(grep -cF "$1" "$WORK/$2" 2>/dev/null || echo 0)"
  if [ "$n" = "$3" ]; then ok "$4 (=$3)"; else bad "$4 (expected $3, got $n)"; fi
}

echo "SumelaOS smoke test"
echo "  repo:  $REPO_ROOT"
echo "  work:  $WORK"

# --- Stage a clean copy (no .git, no nested temp/test output) ----------------
# Copy tracked + untracked source but exclude .git so setup's git wiring starts fresh.
( cd "$REPO_ROOT" && tar --exclude='./.git' --exclude='./tests/.out' -cf - . ) | ( cd "$WORK" && tar -xf - )
( cd "$WORK" && git init -q && git add -A && git -c user.email=smoke@test -c user.name=smoke commit -qm init ) || true

run_setup() {
  ( cd "$WORK" && bash scripts/setup.sh --non-interactive \
      --project-name "SmokeProj" \
      --project-purpose "smoke test fixture" \
      --stacks "backend" \
      --plugins "qdrant-session-memory" \
      --ides "claude,cursor,opencode" \
      --governance "solo" ) >"$WORK/setup.log" 2>&1
}

echo ""
echo "Run 1 — fresh setup"
if run_setup; then ok "setup.sh --non-interactive exited 0"; else bad "setup.sh exited non-zero"; sed 's/^/    /' "$WORK/setup.log" | tail -25; fi

assert_file "AGENTS.md"                    "AGENTS.md generated"
assert_file "CLAUDE.md"                     "Claude pointer generated"
assert_file ".cursor/rules/00-agent.md"     "Cursor pointer generated"
assert_file ".opencode/AGENTS.md"           "OpenCode pointer generated"
assert_file ".sumela/RULE_REGISTRY.md"      "RULE_REGISTRY.md generated"
assert_count "<name>qdrant-session-memory</name>" ".sumela/SKILL_REGISTRY.md" 1 "plugin registered once"

# No unrendered placeholders should survive in the generated overlay.
if grep -rqF '{{' "$WORK/AGENTS.md" "$WORK/.opencode/AGENTS.md" 2>/dev/null; then
  bad "unrendered {{placeholder}} left in generated files"
else
  ok "no unrendered placeholders in generated files"
fi

echo ""
echo "Structure + registry validation"
if ( cd "$WORK" && bash scripts/validate-structure.sh --check-placeholders --post-setup ) >"$WORK/validate.log" 2>&1; then
  ok "validate-structure.sh passed (incl. --post-setup: hooks + gitignore + gitattributes landed)"
else
  bad "validate-structure.sh failed"; sed 's/^/    /' "$WORK/validate.log" | tail -20
fi
if command -v python3 >/dev/null 2>&1; then
  if ( cd "$WORK" && python3 scripts/reconcile-registry.py --check ) >"$WORK/reconcile.log" 2>&1; then
    ok "reconcile-registry --check in sync"
  else
    bad "reconcile-registry --check reported drift"; sed 's/^/    /' "$WORK/reconcile.log" | tail -10
  fi
else
  echo "  SKIP  reconcile-registry (python3 unavailable)"
fi

echo ""
echo "Run 2 — idempotency (re-run must not duplicate)"
if run_setup; then ok "second setup.sh run exited 0"; else bad "second setup.sh run exited non-zero"; sed 's/^/    /' "$WORK/setup.log" | tail -25; fi
assert_count "<name>qdrant-session-memory</name>" ".sumela/SKILL_REGISTRY.md" 1 "plugin still registered exactly once after re-run"

echo ""
echo "-------------------------------------------"
echo "smoke: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
