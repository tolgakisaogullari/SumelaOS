#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# validate-structure.sh — SumelaOS Template Structure Validator
# -----------------------------------------------------------------------------
# Validates that all required skill directories, rule files, wiki templates,
# rule templates, and memory plugin structures exist. Optionally checks for
# unreplaced {{placeholders}} in generated files.
#
# Usage:   bash scripts/validate-structure.sh [--check-placeholders]
# Exit:    0 = all pass, 1 = any fail
# -----------------------------------------------------------------------------

set -euo pipefail

CHECK_PLACEHOLDERS=false
FAILURES=0
PASSES=0

if [[ "${1:-}" == "--check-placeholders" ]]; then
  CHECK_PLACEHOLDERS=true
fi

# --- Colors (fallback to plain if no tput / non-terminal) ---
if command -v tput &>/dev/null && [ -t 1 ]; then
  GREEN=$(tput setaf 2)
  RED=$(tput setaf 1)
  YELLOW=$(tput setaf 3)
  RESET=$(tput sgr0)
else
  GREEN="" RED="" YELLOW="" RESET=""
fi

pass() {
  echo "${GREEN}[PASS]${RESET} $1"
  PASSES=$((PASSES + 1))
}

fail() {
  echo "${RED}[FAIL]${RESET} $1"
  FAILURES=$((FAILURES + 1))
}

warn() {
  echo "${YELLOW}[WARN]${RESET} $1"
}

# -----------------------------------------------------------------------------
# 1. Skill directories
# -----------------------------------------------------------------------------
EXPECTED_SKILLS=(
  "brainstorming"
  "context-handoff"
  "dispatching-parallel-agents"
  "executing-plans"
  "finishing-a-development-branch"
  "init-sumela"
  "performance-optimization"
  "receiving-code-review"
  "requesting-code-review"
  "secure-coding-standard"
  "self-improvement-curator"
  "shipping-and-launch"
  "subagent-driven-development"
  "systematic-debugging"
  "test-driven-development"
  "using-git-worktrees"
  "using-second-brain"
  "using-superpowers"
  "verification-before-completion"
  "writing-plans"
  "writing-skills"
)

SKILL_FOUND=0
SKILL_MISSING=""
for skill in "${EXPECTED_SKILLS[@]}"; do
  if [ -d ".sumela/skills/$skill" ]; then
    SKILL_FOUND=$((SKILL_FOUND + 1))
  else
    SKILL_MISSING="$SKILL_MISSING .sumela/skills/$skill"
  fi
done

if [ -z "$SKILL_MISSING" ]; then
  pass "Skill directories ($SKILL_FOUND/${#EXPECTED_SKILLS[@]})"
else
  fail "Skill directories ($SKILL_FOUND/${#EXPECTED_SKILLS[@]}) — missing:$SKILL_MISSING"
fi

# -----------------------------------------------------------------------------
# 2. SKILL_REGISTRY.md path validity
# -----------------------------------------------------------------------------
if [ -f ".sumela/SKILL_REGISTRY.md" ]; then
  MISSING_PATHS=""
  PATH_COUNT=0
  FOUND_PATHS=0
  while IFS= read -r line; do
    # Extract <path>...</path> content
    if [[ "$line" =~ \<path\>(.+)\<\/path\> ]]; then
      skill_path="${BASH_REMATCH[1]}"
      PATH_COUNT=$((PATH_COUNT + 1))
      if [ -f "$skill_path" ]; then
        FOUND_PATHS=$((FOUND_PATHS + 1))
      else
        MISSING_PATHS="$MISSING_PATHS $skill_path"
      fi
    fi
  done < ".sumela/SKILL_REGISTRY.md"

  if [ -z "$MISSING_PATHS" ]; then
    pass "SKILL_REGISTRY.md paths valid ($FOUND_PATHS/$PATH_COUNT)"
  else
    fail "SKILL_REGISTRY.md paths valid ($FOUND_PATHS/$PATH_COUNT) — missing:$MISSING_PATHS"
  fi
else
  fail "SKILL_REGISTRY.md exists — file not found"
fi

# -----------------------------------------------------------------------------
# 3. Universal rules
# -----------------------------------------------------------------------------
REQUIRED_RULES=(
  "engineering_philosophy.md"
  "identity_and_behavior.md"
  "architecture_patterns.md"
  "audit_and_output.md"
  "security_protocol.md"
  "git_workflow_mandatory_review_protocol.md"
  "self_improvement_protocol.md"
  "operational_excellence_maintenance.md.template"
)

RULES_FOUND=0
RULES_MISSING=""
for rule in "${REQUIRED_RULES[@]}"; do
  if [ -f ".sumela/rules/$rule" ]; then
    RULES_FOUND=$((RULES_FOUND + 1))
  else
    RULES_MISSING="$RULES_MISSING $rule"
  fi
done

if [ -z "$RULES_MISSING" ]; then
  pass "Universal rules ($RULES_FOUND/${#REQUIRED_RULES[@]})"
else
  fail "Universal rules ($RULES_FOUND/${#REQUIRED_RULES[@]}) — missing:$RULES_MISSING"
fi

# -----------------------------------------------------------------------------
# 4. Unreplaced {{placeholders}} in generated files
# -----------------------------------------------------------------------------
check_placeholders() {
  local file="$1"
  local label="$2"
  if [ ! -f "$file" ]; then
    warn "$label — file not found, skipping placeholder check"
    return
  fi
  if grep -qE '\{\{[a-z_]+\}\}' "$file" 2>/dev/null; then
    local found
    found=$(grep -oE '\{\{[a-z_]+\}\}' "$file" | sort -u | tr '\n' ' ')
    fail "$label — unreplaced placeholders: $found"
  else
    pass "$label — no unreplaced placeholders"
  fi
}

if [ "$CHECK_PLACEHOLDERS" = true ]; then
  check_placeholders "AGENTS.md" "AGENTS.md"
  check_placeholders ".sumela/RULE_REGISTRY.md" "RULE_REGISTRY.md"
fi

# -----------------------------------------------------------------------------
# 5. Wiki templates
# -----------------------------------------------------------------------------
EXPECTED_WIKI_TEMPLATES=(
  "_INDEX.md.template"
  "_LOG.md.template"
  "_SEARCH_INDEX.md.template"
  "_SCHEMA.md"
  "active-project-context.md.template"
  "_improvement-queue/README.md"
)

WIKI_FOUND=0
WIKI_MISSING=""
for tmpl in "${EXPECTED_WIKI_TEMPLATES[@]}"; do
  if [ -f "docs/second-brain/template/wiki/$tmpl" ]; then
    WIKI_FOUND=$((WIKI_FOUND + 1))
  else
    WIKI_MISSING="$WIKI_MISSING $tmpl"
  fi
done

if [ -z "$WIKI_MISSING" ]; then
  pass "Wiki templates ($WIKI_FOUND/${#EXPECTED_WIKI_TEMPLATES[@]})"
else
  fail "Wiki templates ($WIKI_FOUND/${#EXPECTED_WIKI_TEMPLATES[@]}) — missing:$WIKI_MISSING"
fi

# -----------------------------------------------------------------------------
# 6. Rule templates
# -----------------------------------------------------------------------------
EXPECTED_RULE_TEMPLATES=(
  "backend_standards.md.empty"
  "backend_standards.md.best-practice"
  "frontend_standards.md.empty"
  "frontend_standards.md.best-practice"
  "mobile_standards.md.empty"
  "mobile_standards.md.best-practice"
  "operational_excellence_maintenance.md.empty"
  "operational_excellence_maintenance.md.best-practice"
)

RTMPL_FOUND=0
RTMPL_MISSING=""
for tmpl in "${EXPECTED_RULE_TEMPLATES[@]}"; do
  if [ -f ".sumela/rules/templates/$tmpl" ]; then
    RTMPL_FOUND=$((RTMPL_FOUND + 1))
  else
    RTMPL_MISSING="$RTMPL_MISSING $tmpl"
  fi
done

if [ -z "$RTMPL_MISSING" ]; then
  pass "Rule templates ($RTMPL_FOUND/${#EXPECTED_RULE_TEMPLATES[@]})"
else
  fail "Rule templates ($RTMPL_FOUND/${#EXPECTED_RULE_TEMPLATES[@]}) — missing:$RTMPL_MISSING"
fi

# -----------------------------------------------------------------------------
# 7. Memory plugins README
# -----------------------------------------------------------------------------
if [ -f ".sumela/memory-plugins/README.md" ]; then
  pass "Memory plugins README"
else
  fail "Memory plugins README — .sumela/memory-plugins/README.md not found"
fi

# -----------------------------------------------------------------------------
# 8. Plugin SKILL.md files
# -----------------------------------------------------------------------------
for plugin in qdrant-session-memory graphify-code-graph; do
  if [ -f ".sumela/memory-plugins/$plugin/SKILL.md" ]; then
    pass "Plugin skill: $plugin"
  else
    fail "Plugin skill: $plugin — SKILL.md not found"
  fi
done

# -----------------------------------------------------------------------------
# 9. Doc skill-count drift guard (framework repo only — README isn't copied into
#    user projects, so this is a silent no-op there). The README carries a marker:
#      <!-- sumela:skill-count workflows=21 loadable=26 ... -->
#    whose numbers MUST match reconcile-registry.py --stats (the source of truth),
#    so the headline count can never silently drift when a skill is added/removed.
# -----------------------------------------------------------------------------
MARKER_LINE="$(grep -m1 'sumela:skill-count' README.md 2>/dev/null || true)"
if [ -n "$MARKER_LINE" ] && command -v python3 &>/dev/null && [ -f scripts/reconcile-registry.py ]; then
  STATS="$(python3 scripts/reconcile-registry.py --stats 2>/dev/null || true)"
  real_wf="$(printf '%s\n' "$STATS"   | sed -n 's/^skill_workflows=//p')"
  real_load="$(printf '%s\n' "$STATS" | sed -n 's/^loadable_skills=//p')"
  doc_wf="$(printf '%s\n'   "$MARKER_LINE" | sed -n 's/.*workflows=\([0-9][0-9]*\).*/\1/p')"
  doc_load="$(printf '%s\n' "$MARKER_LINE" | sed -n 's/.*loadable=\([0-9][0-9]*\).*/\1/p')"
  if [ -z "$real_wf" ] || [ -z "$real_load" ]; then
    warn "Skill-count guard — reconcile-registry.py --stats produced no counts, skipping"
  elif [ "$doc_wf" = "$real_wf" ] && [ "$doc_load" = "$real_load" ]; then
    pass "README skill count in sync (workflows=$real_wf, loadable=$real_load)"
  else
    fail "README skill count DRIFTED — marker says workflows=$doc_wf/loadable=$doc_load, on-disk is workflows=$real_wf/loadable=$real_load (fix README.md marker + prose)"
  fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
TOTAL=$((PASSES + FAILURES))
echo "---"
if [ "$FAILURES" -eq 0 ]; then
  echo "${GREEN}All $TOTAL checks passed${RESET}"
  exit 0
else
  echo "${RED}$FAILURES of $TOTAL checks failed${RESET}"
  exit 1
fi
