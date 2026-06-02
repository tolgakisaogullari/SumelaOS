#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# status.sh — SumelaOS health report (read-only).
#
# One command that answers "is my SumelaOS install healthy, and what (if
# anything) needs attention?" It NEVER modifies anything — every finding routes
# to the automated fixer that resolves it (update.sh, setup, or /evolve), so the
# developer runs one diagnosis and then one fixer, no manual editing.
#
# Usage:   bash scripts/status.sh
# Exit:    0 = all healthy, 1 = one or more items need attention
# -----------------------------------------------------------------------------
set -uo pipefail

# --- Anchor to the nearest .sumela/ (works from any subdir; monorepo-safe) ---
ROOT="$(pwd)"
while [ "$ROOT" != "/" ] && [ ! -d "$ROOT/.sumela" ]; do ROOT="$(dirname "$ROOT")"; done
[ -d "$ROOT/.sumela" ] || { echo "status: no .sumela/ found from $(pwd) upward."; exit 0; }
cd "$ROOT"

SCRIPTS_DIR="$ROOT/scripts"
WIKI_PATH="${WIKI_PATH:-docs/second-brain/wiki}"

# --- Colors (plain if no tput / non-terminal) ---
if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
  GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); CYAN=$(tput setaf 6); BOLD=$(tput bold); RESET=$(tput sgr0)
else
  GREEN="" YELLOW="" CYAN="" BOLD="" RESET=""
fi

ATTENTION=0
ok()        { echo "  ${GREEN}ok${RESET}        $1"; }
info()      { echo "  ${CYAN}info${RESET}      $1"; }
attention() { echo "  ${YELLOW}attention${RESET} $1"; ATTENTION=$((ATTENTION + 1)); }
section()   { echo ""; echo "${BOLD}$1${RESET}"; }

HAVE_PY3=false; command -v python3 >/dev/null 2>&1 && HAVE_PY3=true

echo "${BOLD}SumelaOS status${RESET}  ($ROOT)"

# --- 1. Version + governance ------------------------------------------------
section "Framework"
if [ -f "$ROOT/.sumela/VERSION" ]; then
  ver="$(head -1 "$ROOT/.sumela/VERSION" | tr -d ' \t\r\n')"
  info "version ${ver:-unknown}  (check for upgrades: bash scripts/update.sh)"
else
  attention ".sumela/VERSION missing — reinstall the core (bash scripts/setup.sh) or run update.sh"
fi
if [ -f "$ROOT/AGENTS.md" ]; then
  gov="$(grep -ioE '^[[:space:]]*governance:[[:space:]]*(solo|team)' "$ROOT/AGENTS.md" 2>/dev/null | head -1 | awk -F: '{gsub(/ /,"",$2); print $2}')"
  [ -n "$gov" ] && info "governance: $gov  (AGENTS.md §8)" || info "governance mode not declared in AGENTS.md §8"
fi

# --- 2. Structure -----------------------------------------------------------
section "Structure"
if [ -f "$SCRIPTS_DIR/validate-structure.sh" ]; then
  struct_out="$(bash "$SCRIPTS_DIR/validate-structure.sh" 2>&1)"; struct_rc=$?
  summary="$(printf '%s\n' "$struct_out" | grep -E 'All .* checks passed|check.* failed|FAIL' | tail -1)"
  if [ "$struct_rc" -eq 0 ]; then
    ok "${summary:-structure valid}"
  else
    attention "${summary:-structure invalid} — see: bash scripts/validate-structure.sh  (fix: bash scripts/update.sh)"
  fi
else
  info "validate-structure.sh not present — skipped"
fi

# --- 3. Skill registry drift ------------------------------------------------
section "Skill registry"
if [ -f "$SCRIPTS_DIR/reconcile-registry.py" ] && [ "$HAVE_PY3" = true ]; then
  reg_out="$(python3 "$SCRIPTS_DIR/reconcile-registry.py" --check 2>&1)"; reg_rc=$?
  if [ "$reg_rc" -eq 0 ]; then
    ok "SKILL_REGISTRY.md in sync with skills on disk"
  else
    printf '%s\n' "$reg_out" | grep -E 'unregistered|ORPHAN' | sed 's/^ */  /'
    attention "registry out of sync — fix: python3 scripts/reconcile-registry.py  (also run by update.sh)"
  fi
else
  info "reconcile-registry.py / python3 unavailable — skipped"
fi

# --- Shared rules (monorepo / org) ------------------------------------------
section "Shared rules"
if [ -f "$SCRIPTS_DIR/sync-shared-rules.py" ] && [ "$HAVE_PY3" = true ]; then
  shr_out="$(python3 "$SCRIPTS_DIR/sync-shared-rules.py" --check 2>&1)"; shr_rc=$?
  case "$shr_out" in
    *"no .sumela-shared/rules"*) info "no org-shared rules configured (.sumela-shared/rules/ above this install)" ;;
    *)
      if [ "$shr_rc" -eq 0 ]; then
        ok "in sync with .sumela-shared/rules/"
      else
        printf '%s\n' "$shr_out" | grep -E 'out of date|not registered|ORPHAN' | sed 's/^ */  /'
        attention "org-shared rules drifted — fix: python3 scripts/sync-shared-rules.py"
      fi ;;
  esac
else
  info "sync-shared-rules.py / python3 unavailable — skipped"
fi

# --- 4. IDE mirror drift ----------------------------------------------------
section "IDE mirrors"
if [ -f "$ROOT/.sumela/mirrors.conf" ] && [ -f "$SCRIPTS_DIR/sync-mirrors.sh" ]; then
  if bash "$SCRIPTS_DIR/sync-mirrors.sh" --check >/dev/null 2>&1; then
    ok "all configured mirrors match .sumela/sumela-prompt.md"
  else
    attention "a mirror has drifted — fix: bash scripts/sync-mirrors.sh  (also enforced by pre-commit)"
  fi
else
  info "no .sumela/mirrors.conf — no IDE mirrors configured"
fi

# --- 5. Improvement queue ---------------------------------------------------
section "Improvement queue"
QDIR="$ROOT/$WIKI_PATH/_improvement-queue"
if [ -d "$QDIR" ]; then
  pending="$(find "$QDIR" -maxdepth 1 -name 'IMP-*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${pending:-0}" -gt 0 ]; then
    attention "$pending pending signal(s) — review with /evolve"
  else
    ok "no pending signals"
  fi
else
  info "no _improvement-queue/ under $WIKI_PATH — second-brain not initialized here"
fi

# --- 6. Git hooks -----------------------------------------------------------
section "Git hooks"
if [ -d "$ROOT/.git" ] || git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  hp="$(git -C "$ROOT" config --get core.hooksPath 2>/dev/null || true)"
  if [ "$hp" = ".sumela/git-hooks" ]; then
    ok "core.hooksPath = .sumela/git-hooks (validation + memory-sync active)"
  elif [ -d "$ROOT/.sumela/git-hooks" ]; then
    attention "hooks not wired — fix: git config core.hooksPath .sumela/git-hooks  (or rerun setup)"
  else
    info "no .sumela/git-hooks present — skipped"
  fi
else
  info "not a git repository — hooks skipped"
fi

# --- 7. Secret scanning -----------------------------------------------------
section "Secret scanning"
if command -v gitleaks >/dev/null 2>&1; then
  ok "gitleaks installed — pre-commit scans staged changes for secrets"
else
  info "no secret scanner — install gitleaks to auto-scan commits (see .sumela/rules/security_protocol.md)"
fi

# --- 8. Memory plugins ------------------------------------------------------
section "Memory plugins"
if [ -d "$ROOT/.sumela/memory-plugins" ]; then
  found=""
  for p in "$ROOT"/.sumela/memory-plugins/*/; do
    [ -d "$p" ] || continue
    found="$found $(basename "$p")"
  done
  [ -n "$found" ] && info "installed:$found" || info "no memory plugins installed (optional)"
else
  info "no memory-plugins directory (optional)"
fi

# --- Summary ----------------------------------------------------------------
echo ""
if [ "$ATTENTION" -eq 0 ]; then
  echo "${GREEN}${BOLD}Healthy.${RESET} Nothing needs attention."
  exit 0
else
  echo "${YELLOW}${BOLD}$ATTENTION item(s) need attention${RESET} — each line above lists the one command that fixes it."
  exit 1
fi
