#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/test_setup_without_python.sh — the bash installer must not require python3.
#
# README.md promises the core framework needs "only git and any AI coding agent —
# nothing else", and that declining the optional plugins adds no prerequisites.
# That promise was false: setup.sh's render_template() called `python3 -c` with no
# guard, on the CORE path (AGENTS.md, .sumela/RULE_REGISTRY.md, every rule template),
# so a machine without python3 got a bare
#
#     scripts/setup.sh: line 139: python3: command not found
#
# Every OTHER python caller in the repo is guarded and degrades silently
# (update.sh, validate-structure.sh, the git hooks) — the install was the one
# unguarded caller, and it is the one a first-time user hits.
#
# PowerShell already renders these same templates with literal .Replace() and no
# python at all (scripts/setup.ps1), so the dependency was an implementation
# choice on the bash side, not a necessity.
#
# What this pins:
#   1. `setup.sh --non-interactive` SUCCEEDS with python3 absent from PATH.
#   2. The python-free render is BYTE-IDENTICAL to the python render. This is the
#      assertion that keeps the fallback honest: a second code path that merely
#      "works" drifts, and template values here carry the hazards that break naive
#      shell substitution — multi-line command blocks, `|`, `&`, backticks,
#      backslashes, `→`/`↑`, and glob metacharacters.
#   3. `--hooks-only` (the /onboardSumela teammate path) stays python-free. It was
#      ALREADY python-free by virtue of exiting before any render; a preflight
#      placed at the top of the file would have newly broken it.
#
# Dependency-free (bash + git; python3 only to produce the comparison baseline —
# the test SKIPs that one assertion when python3 is genuinely unavailable).
# Run from anywhere:  bash tests/test_setup_without_python.sh
# Exit 0 = all assertions passed, 1 = a failure (printed above).
# -----------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A PATH shim whose `python3` behaves exactly like an absent interpreter.
mkdir -p "$WORK/nopy"
cat > "$WORK/nopy/python3" <<'STUB'
#!/bin/sh
echo "python3: command not found" >&2
exit 127
STUB
chmod +x "$WORK/nopy/python3"

# Seed a throwaway project from the framework tree. `git clone` keeps this test
# from touching the real working copy at all.
seed() {
  local dst="$1"
  git -C "$REPO_ROOT" clone --quiet --no-hardlinks . "$dst" 2>/dev/null || return 1
  ( cd "$dst" && git checkout --quiet -- . ) || return 1
  # Carry uncommitted framework changes in, so the test exercises the CURRENT
  # installer rather than the last commit's. docs/second-brain/template is in the
  # list because the installer COPIES from it: omitting it meant a new wiki template
  # plus its validate-structure.sh requirement landed here half-applied, and every
  # seeded install failed structure validation for a file the test itself withheld.
  ( cd "$REPO_ROOT" && git ls-files -m -o --exclude-standard -- \
      scripts .sumela AGENTS.md.template docs/second-brain/template 2>/dev/null ) \
    | while IFS= read -r f; do
        [ -f "$REPO_ROOT/$f" ] || continue
        mkdir -p "$dst/$(dirname "$f")"
        cp "$REPO_ROOT/$f" "$dst/$f"
      done
  return 0
}

run_setup() {   # $1 = project dir, $2 = "nopy" | "py", rest = extra args
  local dir="$1" mode="$2"; shift 2
  local path="$PATH"
  [ "$mode" = "nopy" ] && path="$WORK/nopy:$PATH"
  # SUMELA_RENDER_TRACE makes render_template announce which implementation ran.
  # Without it this file's central assertion is unfalsifiable: if the python
  # renderer breaks, `render_template` falls through to bash on BOTH sides and
  # `cmp` then compares bash to bash and always matches. Proven: injecting a
  # syntax error into the python heredoc left every byte-identity assertion green.
  ( cd "$dir" && PATH="$path" SUMELA_RENDER_TRACE=1 bash scripts/setup.sh \
      --non-interactive --project-name "BudgetProbe" "$@" ) >"$dir/.setup.log" 2>&1
}

echo "setup.sh without python3"

# --- 1. Full install completes with python3 absent -------------------------
P_NOPY="$WORK/nopy-install"
if seed "$P_NOPY"; then
  if run_setup "$P_NOPY" nopy; then
    ok "setup.sh --non-interactive succeeds with python3 absent"
  else
    bad "setup.sh failed without python3 (exit $?)"
    sed 's/^/        /' "$P_NOPY/.setup.log" | tail -15
  fi
  for f in AGENTS.md .sumela/RULE_REGISTRY.md; do
    if [ -s "$P_NOPY/$f" ]; then ok "generated $f"; else bad "missing or empty: $f"; fi
  done
  # A rendered file must carry NO unreplaced placeholder. A MISSING file is a
  # failure here, not a vacuous pass — the original draft of this check reported
  # "no unrendered placeholders" for a file the install never produced.
  if [ ! -f "$P_NOPY/AGENTS.md" ]; then
    bad "AGENTS.md absent — cannot check placeholders"
  elif grep -q '{{[a-z_]*}}' "$P_NOPY/AGENTS.md"; then
    bad "AGENTS.md still contains unrendered {{placeholders}}"
    grep -o '{{[a-z_]*}}' "$P_NOPY/AGENTS.md" | sort -u | sed 's/^/        /'
  else
    ok "AGENTS.md has no unrendered placeholders"
  fi
else
  bad "could not seed the no-python project"
fi

# --- 2. The two renders must be byte-identical -----------------------------
if command -v python3 >/dev/null 2>&1; then
  P_PY="$WORK/py-install"
  if seed "$P_PY" && run_setup "$P_PY" py; then
    for f in AGENTS.md .sumela/RULE_REGISTRY.md .sumela/rules/operational_excellence_maintenance.md; do
      if [ ! -f "$P_PY/$f" ] || [ ! -f "$P_NOPY/$f" ]; then
        bad "cannot compare $f (missing on one side)"
      elif cmp -s "$P_PY/$f" "$P_NOPY/$f"; then
        ok "python and python-free renders are byte-identical: $f"
      else
        bad "render drift in $f"
        diff "$P_PY/$f" "$P_NOPY/$f" 2>&1 | head -12 | sed 's/^/        /'
      fi
    done
  else
    bad "baseline (with-python) install failed — cannot compare renders"
    [ -f "$P_PY/.setup.log" ] && tail -10 "$P_PY/.setup.log" | sed 's/^/        /'
  fi
else
  echo "  SKIP  byte-identical comparison (python3 unavailable to build a baseline)"
fi

# --- 2b. The baseline must actually have used python -----------------------
# This is what makes case 2 mean anything.
if command -v python3 >/dev/null 2>&1 && [ -f "$P_PY/.setup.log" ]; then
  if grep -q 'render: python' "$P_PY/.setup.log"; then
    ok "baseline install really used the python renderer"
  else
    bad "baseline install never took the python path — the byte-identity check above compared bash to bash"
  fi
  if grep -q 'render: bash' "$P_PY/.setup.log"; then
    bad "baseline install fell back to bash mid-run (python present but failing)"
    grep -n 'render: bash' "$P_PY/.setup.log" | head -3 | sed 's/^/        /'
  else
    ok "baseline install never fell back"
  fi
fi
if [ -f "$P_NOPY/.setup.log" ]; then
  if grep -q 'render: bash' "$P_NOPY/.setup.log" && ! grep -q 'render: python' "$P_NOPY/.setup.log"; then
    ok "python-free install used only the bash renderer"
  else
    bad "python-free install did not take the bash path exclusively"
  fi
fi

# --- 2c. Team mode: the branch where slugify's fallback actually runs -------
# The original version of this test only ever passed --non-interactive
# --project-name, so slugify's python-free branch and the plugin-registry
# fallback had ZERO coverage — and both shipped broken.
for loc in "en_US.UTF-8" "C"; do
  P_TEAM="$WORK/team-${loc//./-}"
  if ! seed "$P_TEAM"; then bad "could not seed team project ($loc)"; continue; fi
  if ( cd "$P_TEAM" && PATH="$WORK/nopy:$PATH" LC_ALL="$loc" LANG="$loc" \
         bash scripts/setup.sh --non-interactive --project-name "TeamProbe" \
         --governance team --domains "Payments,Ödeme,Логистика Ops" ) >"$P_TEAM/.setup.log" 2>&1; then
    ok "team mode + non-ASCII domain installs without python3 (LC_ALL=$loc)"
  else
    bad "team-mode install failed without python3 (LC_ALL=$loc)"
    tail -6 "$P_TEAM/.setup.log" | sed 's/^/        /'
  fi
  # `Логистика Ops` is deliberately unmappable-but-sluggable: the table cannot
  # transliterate Cyrillic, so the warning legitimately fires and `slugify`'s stdout
  # is under test — without it, fixing the spurious-warning bug would silently make
  # the warn-on-stdout guard below unfalsifiable. A PURE Cyrillic name would not work:
  # the slug comes out empty and setup aborts on "no usable characters".
  for want in payments.md odeme.md ops.md; do
    if [ -f "$P_TEAM/.sumela/rules/domains/$want" ]; then
      ok "domain rule generated with the expected slug: $want (LC_ALL=$loc)"
    else
      bad "missing .sumela/rules/domains/$want (LC_ALL=$loc)"
      ls "$P_TEAM/.sumela/rules/domains/" 2>/dev/null | sed 's/^/        got: /'
    fi
  done
  # A warning must never end up INSIDE a generated path or registry row.
  if [ -f "$P_TEAM/.sumela/RULE_REGISTRY.md" ] && grep -q '\[WARN\]' "$P_TEAM/.sumela/RULE_REGISTRY.md"; then
    bad "RULE_REGISTRY.md contains warning text — a helper wrote to stdout inside \$( ) (LC_ALL=$loc)"
    grep -n '\[WARN\]' "$P_TEAM/.sumela/RULE_REGISTRY.md" | head -2 | sed 's/^/        /'
  else
    ok "RULE_REGISTRY.md free of warning-text pollution (LC_ALL=$loc)"
  fi
done

# --- 2c-bis. The plugin-registry append has its own python-free branch --------
# Both existing suites that pass --plugins run WITH python3, so this branch was never
# entered: sabotaging it entirely left smoke.sh and this file fully green.
if command -v python3 >/dev/null 2>&1; then
  P_PLG_N="$WORK/plugins-nopy"; P_PLG_P="$WORK/plugins-py"
  # The shipped SKILL_REGISTRY.md already lists this plugin, so setup.sh takes its
  # idempotent "already registered" path and PLUGIN_ENTRIES stays EMPTY — the append
  # branch is never entered. Sabotaging it left this case green until the entry was
  # removed first. Strip it so the branch actually runs, which is also the real
  # first-install shape.
  _strip_plugin() {
    python3 - "$1" <<'STRIP'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1]) / ".sumela/SKILL_REGISTRY.md"
t = p.read_text(encoding="utf-8")
t = re.sub(r'<skill[^>]*>\s*<name>qdrant-session-memory</name>.*?</skill>\s*', '', t, flags=re.S)
p.write_text(t, encoding="utf-8")
STRIP
  }
  if seed "$P_PLG_N" && seed "$P_PLG_P" \
     && _strip_plugin "$P_PLG_N" && _strip_plugin "$P_PLG_P" \
     && run_setup "$P_PLG_N" nopy --plugins qdrant-session-memory \
     && run_setup "$P_PLG_P" py   --plugins qdrant-session-memory; then
    ok "plugin install completes without python3"
    if grep -q "<name>qdrant-session-memory</name>" "$P_PLG_N/.sumela/SKILL_REGISTRY.md"; then
      ok "plugin re-appended by the python-free path (the branch actually ran)"
    else
      bad "plugin missing from the registry — the append branch did not run or failed"
    fi
    if cmp -s "$P_PLG_N/.sumela/SKILL_REGISTRY.md" "$P_PLG_P/.sumela/SKILL_REGISTRY.md"; then
      ok "plugin registry append is byte-identical across both renderers"
    else
      bad "plugin registry append drifted between the python and bash paths"
      diff "$P_PLG_P/.sumela/SKILL_REGISTRY.md" "$P_PLG_N/.sumela/SKILL_REGISTRY.md" | head -10 | sed 's/^/        /'
    fi
  else
    bad "plugin install failed"
    [ -f "$P_PLG_N/.setup.log" ] && tail -6 "$P_PLG_N/.setup.log" | sed 's/^/        /'
  fi
else
  echo "  SKIP  plugin-append comparison (no python3 for a baseline)"
fi

# --- 2d. A run WITHOUT the trace variable must still work -------------------
# The blind spot that let a `set -e` abort ship: every other case here exports
# SUMELA_RENDER_TRACE=1, so `[ -n "$VAR" ] && echo ...` was always TRUE. With the
# variable unset that idiom returns 1, and as render_template's last command it
# aborted the whole install under `set -euo pipefail` — in every real run.
P_NOTRACE="$WORK/no-trace"
if seed "$P_NOTRACE"; then
  if ( cd "$P_NOTRACE" && bash scripts/setup.sh --non-interactive --project-name "NoTrace" ) \
       >"$P_NOTRACE/.setup.log" 2>&1 && [ -s "$P_NOTRACE/AGENTS.md" ]; then
    ok "install succeeds with SUMELA_RENDER_TRACE unset (the default)"
  else
    bad "install broke when the trace variable is unset"
    tail -6 "$P_NOTRACE/.setup.log" | sed 's/^/        /'
  fi
else
  bad "could not seed the no-trace project"
fi

# --- 3. --hooks-only stays python-free -------------------------------------
# It already was, by exiting before any render. Pinned so a future preflight is
# not placed at the top of the file, which would newly break /onboardSumela.
P_HOOKS="$WORK/hooks-only"
if seed "$P_HOOKS"; then
  if ( cd "$P_HOOKS" && PATH="$WORK/nopy:$PATH" bash scripts/setup.sh --hooks-only ) \
       >"$P_HOOKS/.hooks.log" 2>&1; then
    ok "--hooks-only succeeds with python3 absent"
  else
    bad "--hooks-only failed without python3"
    tail -10 "$P_HOOKS/.hooks.log" | sed 's/^/        /'
  fi
else
  bad "could not seed the hooks-only project"
fi

echo
echo "setup-without-python: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
