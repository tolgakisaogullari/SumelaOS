#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# validate-structure.sh — SumelaOS Template Structure Validator
# -----------------------------------------------------------------------------
# Validates that all required skill directories, rule files, wiki templates,
# rule templates, and memory plugin structures exist. Optionally checks for
# unreplaced {{placeholders}} in generated files.
#
# Usage:   bash scripts/validate-structure.sh [--check-placeholders] [--post-setup]
#          --post-setup: extra hygiene guard run by setup.sh / setup.ps1 / /initSumela
#                        right after a setup (verifies hooks + gitignore + gitattributes
#                        landed). NOT used by framework CI / pre-commit.
# Exit:    0 = all pass, 1 = any fail
# -----------------------------------------------------------------------------

set -euo pipefail

CHECK_PLACEHOLDERS=false
POST_SETUP=false
FAILURES=0
PASSES=0

# Parse all flags (order-independent) so callers can combine them, e.g.
# `validate-structure.sh --check-placeholders --post-setup`.
for arg in "$@"; do
  case "$arg" in
    --check-placeholders) CHECK_PLACEHOLDERS=true ;;
    --post-setup)         POST_SETUP=true ;;
  esac
done

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
  "onboard-sumela"
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
  "domain_standards.md.empty"
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
# 6b. Rule registry <-> file parity (generated projects only). Three checks:
#   (i)   FORWARD — every registered <path>.sumela/rules/...</path> in RULE_REGISTRY.md
#         must exist on disk (catches a registered stack/operational/domain rule whose
#         file was never written, e.g. a typo'd --rule-variant).
#   (ii)  REVERSE (domains) — every .sumela/rules/domains/*.md must be registered
#         (the domains/ prefix is exclusive to domain rules; universal/stack files are
#         always present + registered, so the reverse check is scoped to domains).
#   (iii) TAXONOMY — every <domain_scopes> row must have a matching domain-conditional
#         rule (else a "phantom" domain the agent treats as valid but loads nothing).
#   Template example comments use <stack>/<slug> placeholders (the `<` stops the
#   [^<]+ match), so samples are excluded. Skipped on the framework SOURCE repo.
#   `|| true`: grep exits 1 on no-match, which under `set -euo pipefail` would abort.
# -----------------------------------------------------------------------------
if [ -f ".sumela/RULE_REGISTRY.md" ]; then
  ALL_REG_RULE_PATHS="$(grep -oE '<path>\.sumela/rules/[^<]+</path>' .sumela/RULE_REGISTRY.md 2>/dev/null | sed 's#<path>##; s#</path>##' | sort -u || true)"
  DOMAIN_DISK_PATHS=""
  if [ -d ".sumela/rules/domains" ]; then
    DOMAIN_DISK_PATHS="$(find .sumela/rules/domains -maxdepth 1 -type f -name '*.md' | sort -u || true)"
  fi
  # Domain NAMES declared in <domain_scopes> rows (first `code`-quoted cell), excluding
  # the `(none)` placeholder. Used for the taxonomy<->rule check.
  # Anchor the section tags at line-start: the literal `<domain_scopes>` also appears
  # inline in <usage> prose ("see `<domain_scopes>`"), so an unanchored match would
  # scoop up <phase_definitions>/<stack_scopes> rows (ideation, backend, …).
  DOMAIN_SCOPE_NAMES="$(awk '/^<domain_scopes>$/{f=1} /^<\/domain_scopes>$/{f=0} f' .sumela/RULE_REGISTRY.md 2>/dev/null \
    | grep -oE '^\| `[^`]+`' | sed 's/^| `//; s/`$//' | grep -vx '(none)' | sort -u || true)"
  RULE_PARITY_OK=true
  RULE_PARITY_MSG=""
  # (i) forward
  for p in $ALL_REG_RULE_PATHS; do
    [ -z "$p" ] && continue
    [ -f "$p" ] || { RULE_PARITY_OK=false; RULE_PARITY_MSG="$RULE_PARITY_MSG registered-but-missing:$p"; }
  done
  # (ii) reverse (domains only)
  for p in $DOMAIN_DISK_PATHS; do
    [ -z "$p" ] && continue
    printf '%s\n' "$ALL_REG_RULE_PATHS" | grep -Fxq "$p" || { RULE_PARITY_OK=false; RULE_PARITY_MSG="$RULE_PARITY_MSG on-disk-but-unregistered:$p"; }
  done
  # (iii) taxonomy: each domain-scope name must have a domain-conditional rule entry
  while IFS= read -r dname; do
    [ -z "$dname" ] && continue
    if ! grep -qE "activation=\"domain-conditional\"[^>]*domain=\"$dname\"" .sumela/RULE_REGISTRY.md 2>/dev/null; then
      RULE_PARITY_OK=false
      RULE_PARITY_MSG="$RULE_PARITY_MSG taxonomy-row-without-rule:$dname"
    fi
  done <<EOF
$DOMAIN_SCOPE_NAMES
EOF
  if [ "$RULE_PARITY_OK" = true ]; then
    pass "Rule registry parity (registered rules exist; domain files + taxonomy rows backed)"
  else
    fail "Rule registry parity —$RULE_PARITY_MSG (fix RULE_REGISTRY.md entries / <domain_scopes> rows / the .sumela/rules/ files)"
  fi
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
# 8b. Teammate relay (team-plugins) — validated ONLY when the relay is CONFIGURED.
#     Predicate: relay-config.md present. Absent/declined => silent no-op, so teams
#     without relay (and the framework SOURCE repo) are unaffected. When configured,
#     the key-trust surface MUST be CODEOWNERS-gated (keys/** + relay-config.md) or an
#     identity public key could be swapped in an unreviewed change (key-substitution).
# -----------------------------------------------------------------------------
RELAY_DIR=".sumela/team-plugins/teammate-relay"
if [ -f "$RELAY_DIR/relay-config.md" ]; then
  if [ -f "$RELAY_DIR/SKILL.md" ]; then
    pass "Relay configured: SKILL.md present"
  else
    fail "Relay configured but $RELAY_DIR/SKILL.md missing"
  fi
  # Check the file GitHub actually enforces FIRST (.github/ takes precedence over root).
  RELAY_CO=""
  for c in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
    [ -f "$c" ] && RELAY_CO="$c" && break
  done
  if [ -z "$RELAY_CO" ] || ! grep -q "teammate-relay/keys" "$RELAY_CO" || ! grep -q "teammate-relay/relay-config.md" "$RELAY_CO" || ! grep -q "teammate-relay/roles.json" "$RELAY_CO"; then
    fail "Relay configured but CODEOWNERS does not gate teammate-relay/keys/** + relay-config.md + roles.json (key-substitution / routing-redirect risk)"
  elif grep -q "@REPLACE-WITH-RELAY-OWNERS" "$RELAY_CO"; then
    fail "Relay CODEOWNERS still has the @REPLACE-WITH-RELAY-OWNERS placeholder — set real owners (the gate is unenforced until you do)"
  else
    pass "Relay key-trust surface CODEOWNERS-gated ($RELAY_CO)"
  fi
fi

# -----------------------------------------------------------------------------
# 9. Doc skill-count drift guard (framework repo only — README isn't copied into
#    user projects, so this is a silent no-op there). The README carries a marker:
#      <!-- sumela:skill-count workflows=22 loadable=27 ... -->
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
# 10. Post-setup hygiene guard (ONLY with --post-setup). Run by setup.sh /
#     setup.ps1 / `/initSumela` right after a setup to PROVE the repo-hygiene and
#     hook-wiring steps actually landed — so a half-finished setup cannot pass
#     silently. Gated behind the flag because the framework SOURCE repo (and a
#     plain CI checkout) legitimately lack the generated overlay; default runs
#     (CI, pre-commit) never execute this and are unaffected.
# -----------------------------------------------------------------------------
if [ "$POST_SETUP" = true ]; then
  # .gitignore baselines — setup writes both unconditionally, so absence = real gap.
  if [ -f .gitignore ] && grep -qxF ".sumela/local.md" .gitignore; then
    pass "post-setup: .gitignore per-developer/runtime baseline present"
  else
    fail "post-setup: .gitignore per-developer/runtime baseline missing (.sumela/local.md not ignored) — re-run setup"
  fi
  if [ -f .gitignore ] && grep -qF "# SumelaOS — common secret files" .gitignore; then
    pass "post-setup: .gitignore secret baseline present"
  else
    fail "post-setup: .gitignore secret baseline missing — re-run setup"
  fi
  # .gitattributes union-merge for the append-only log.
  if [ -f .gitattributes ] && grep -qF "docs/second-brain/wiki/_LOG.md merge=union" .gitattributes; then
    pass "post-setup: .gitattributes union-merge present"
  else
    fail "post-setup: .gitattributes union-merge rule missing — re-run setup"
  fi
  # Git hooks wired. Only meaningful in a git repo; a non-SumelaOS hooksPath may be
  # an intentional override (setup.sh does not clobber one), so that case WARNs.
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    HP="$(git config --get core.hooksPath 2>/dev/null || true)"
    if [ -z "$HP" ]; then
      fail "post-setup: git hooks not wired (core.hooksPath unset) — run: git config core.hooksPath .sumela/git-hooks"
    elif printf '%s' "$HP" | grep -qE '\.sumela[/-]'; then
      # Matches both the single install (.sumela/git-hooks) and the monorepo
      # dispatcher (.sumela-hooks); a stray path that merely contains "sumela"
      # (e.g. /home/sumela/.githooks) does NOT match.
      pass "post-setup: git hooks wired (core.hooksPath = $HP)"
    else
      warn "post-setup: core.hooksPath = '$HP' (not a SumelaOS path) — OK if you intentionally use your own hooks, else wire .sumela/git-hooks"
    fi
  else
    warn "post-setup: not a git repository — skipping hook-wiring check"
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
