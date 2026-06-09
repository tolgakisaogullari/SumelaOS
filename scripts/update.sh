#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# update.sh — refresh the SumelaOS framework CORE in an adopting project, WITHOUT
# touching the project's OVERLAY.
#
# CORE (refreshed, with per-file diff + consent when locally changed):
#   .sumela/sumela-prompt.md, .sumela/skills/, .sumela/git-hooks/,
#   universal rules (engineering_philosophy, identity_and_behavior,
#   architecture_patterns, audit_and_output, security_protocol,
#   git_workflow_mandatory_review_protocol, self_improvement_protocol),
#   docs/second-brain/template/ (incl. template/wiki/_SCHEMA.md),
#   .sumela/memory-plugins/<plugin>/ (only plugins already installed),
#   scripts/*, .sumela/VERSION
#   Plus a DERIVED pair: the live docs/second-brain/wiki/_SCHEMA.md is refreshed from
#   the updated template (diff + consent) so you don't have to copy it by hand.
#
# OVERLAY (never touched): AGENTS.md, .sumela/RULE_REGISTRY.md,
#   .sumela/SKILL_REGISTRY.md, stack rules (backend/frontend/mobile_standards,
#   operational_excellence_maintenance), docs/second-brain/wiki/* (except the
#   derived _SCHEMA.md above),
#   .sumela/local.md, .gitignore, .gitattributes, IDE pointers, CODEOWNERS, CI workflow.
#
# Usage:
#   bash scripts/update.sh                 # clone latest from --repo and refresh
#   bash scripts/update.sh --source <dir>  # use a local framework checkout (no clone)
#   bash scripts/update.sh --dry-run       # show what would change; change nothing
#   bash scripts/update.sh --yes           # apply all changed core files without prompts
#   bash scripts/update.sh --force         # run even if versions match
# -----------------------------------------------------------------------------
set -uo pipefail

REPO_URL_DEFAULT="https://github.com/tolgakisaogullari/SumelaOS.git"
SOURCE_DIR=""
REPO_URL="$REPO_URL_DEFAULT"
DRY_RUN=false
ASSUME_YES=false
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE_DIR="$2"; shift 2 ;;
    --repo)   REPO_URL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes|-y)  ASSUME_YES=true; shift ;;
    --force)  FORCE=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if command -v tput &>/dev/null && [ -t 1 ]; then
  GREEN=$(tput setaf 2) RED=$(tput setaf 1) YELLOW=$(tput setaf 3) CYAN=$(tput setaf 6) RESET=$(tput sgr0) BOLD=$(tput bold)
else
  GREEN="" RED="" YELLOW="" CYAN="" RESET="" BOLD=""
fi
info() { echo "${CYAN}[INFO]${RESET} $1"; }
ok()   { echo "${GREEN}[OK]${RESET} $1"; }
warn() { echo "${YELLOW}[WARN]${RESET} $1"; }
err()  { echo "${RED}[ERROR]${RESET} $1"; }

# Anchor to the nearest ancestor that actually contains `.sumela/` — NOT the git
# toplevel, so adopting SumelaOS inside a monorepo subdir updates the right install.
ROOT="$(pwd)"
while [ "$ROOT" != "/" ] && [ ! -d "$ROOT/.sumela" ]; do ROOT="$(dirname "$ROOT")"; done
if [ ! -d "$ROOT/.sumela" ]; then
  err "No .sumela/ found from $(pwd) upward — run update.sh inside a SumelaOS project."
  exit 1
fi
cd "$ROOT" || { err "Cannot cd to project root"; exit 1; }

# Single source for the upstream URL (fork-overridable, shared with the pull-time
# update check): honor .sumela/upstream.conf unless --repo/--source was given.
if [ -z "$SOURCE_DIR" ] && [ "$REPO_URL" = "$REPO_URL_DEFAULT" ] && [ -f "$ROOT/.sumela/upstream.conf" ]; then
  _cfg_url="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/.sumela/upstream.conf" 2>/dev/null | head -1 | tr -d '[:space:]')"
  [ -n "$_cfg_url" ] && REPO_URL="$_cfg_url"
fi

# --- Acquire the framework source -------------------------------------------
CLONE_TMP=""
cleanup() { [ -n "$CLONE_TMP" ] && rm -rf "$CLONE_TMP"; }
trap cleanup EXIT

if [ -n "$SOURCE_DIR" ]; then
  SRC="$SOURCE_DIR"
  [ -d "$SRC/.sumela" ] || { err "--source '$SRC' is not a SumelaOS checkout (.sumela/ missing)"; exit 1; }
else
  command -v git >/dev/null 2>&1 || { err "git not found and no --source given"; exit 1; }
  CLONE_TMP="$(mktemp -d)"
  info "Cloning $REPO_URL ..."
  git clone --depth 1 "$REPO_URL" "$CLONE_TMP" >/dev/null 2>&1 || { err "clone failed"; exit 1; }
  SRC="$CLONE_TMP"
fi

# --- Version gate ------------------------------------------------------------
read_ver() { [ -f "$1/.sumela/VERSION" ] && tr -d '[:space:]' < "$1/.sumela/VERSION" || echo "unknown"; }
SRC_VER="$(read_ver "$SRC")"
LOCAL_VER="$(read_ver "$ROOT")"
info "Local core version: ${LOCAL_VER}    Upstream: ${SRC_VER}"
if [ "$SRC_VER" = "$LOCAL_VER" ] && [ "$FORCE" != true ]; then
  ok "Already on core version ${LOCAL_VER}. (Use --force to re-check files anyway.)"
  exit 0
fi

# --- Build the CORE file list (relative paths) -------------------------------
CORE_FILES=(
  ".sumela/sumela-prompt.md"
  ".sumela/rules/engineering_philosophy.md"
  ".sumela/rules/identity_and_behavior.md"
  ".sumela/rules/architecture_patterns.md"
  ".sumela/rules/audit_and_output.md"
  ".sumela/rules/security_protocol.md"
  ".sumela/rules/git_workflow_mandatory_review_protocol.md"
  ".sumela/rules/self_improvement_protocol.md"
)
CORE_DIRS=(
  ".sumela/skills"
  ".sumela/git-hooks"
  ".sumela/memory-plugins"
  ".sumela/rules/templates"
  "docs/second-brain/template"
  "scripts"
)

# Flatten core dirs (from the SOURCE side) into the file list.
candidates=()
for f in ${CORE_FILES[@]+"${CORE_FILES[@]}"}; do
  [ -f "$SRC/$f" ] && candidates+=("$f")
done
for d in ${CORE_DIRS[@]+"${CORE_DIRS[@]}"}; do
  [ -d "$SRC/$d" ] || continue
  while IFS= read -r abs; do
    candidates+=("${abs#"$SRC/"}")
  done < <(find "$SRC/$d" -type f)
done

# Files the updater must NOT overwrite while it is running (self-update hazard).
SELF_DEFER="scripts/update.sh scripts/update.ps1"

# --- Classify ----------------------------------------------------------------
new_list=(); changed_list=(); deferred_list=()
is_self() { case " $SELF_DEFER " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
plugin_absent() {
  # For a file UNDER a plugin dir (.sumela/memory-plugins/<plugin>/...): skip if that
  # plugin isn't installed locally. Top-level files (e.g. memory-plugins/README.md)
  # are NOT plugin-gated — the `*/*` pattern requires at least one nested segment.
  case "$1" in
    .sumela/memory-plugins/*/*)
      local rest="${1#.sumela/memory-plugins/}"; local plugin="${rest%%/*}"
      [ -d "$ROOT/.sumela/memory-plugins/$plugin" ] || return 0 ;;
  esac
  return 1
}
for f in ${candidates[@]+"${candidates[@]}"}; do
  plugin_absent "$f" && continue
  if [ ! -e "$ROOT/$f" ]; then
    new_list+=("$f")
  elif cmp -s "$SRC/$f" "$ROOT/$f"; then
    : # identical — nothing to do
  elif is_self "$f"; then
    deferred_list+=("$f")
  else
    changed_list+=("$f")
  fi
done

# Derived file: the LIVE docs/second-brain/wiki/_SCHEMA.md is generated from the
# template (template/wiki/_SCHEMA.md) at setup. It's framework-authored schema living
# in the overlay zone, so refresh it here too (with consent) rather than leaving the
# user to copy it by hand. Only when the project actually has a live copy.
SCHEMA_LIVE="docs/second-brain/wiki/_SCHEMA.md"
SCHEMA_SRC="docs/second-brain/template/wiki/_SCHEMA.md"
schema_changed=false
if [ -f "$ROOT/$SCHEMA_LIVE" ] && [ -f "$SRC/$SCHEMA_SRC" ] && ! cmp -s "$SRC/$SCHEMA_SRC" "$ROOT/$SCHEMA_LIVE"; then
  schema_changed=true
fi

n_new=${#new_list[@]}; n_changed=${#changed_list[@]}; n_def=${#deferred_list[@]}
echo ""
echo "${BOLD}=== SumelaOS core update: ${LOCAL_VER} → ${SRC_VER} ===${RESET}"
echo "  New core files:      $n_new"
echo "  Changed core files:  $n_changed"
[ "$schema_changed" = true ] && echo "  Derived (live _SCHEMA): 1 (from refreshed template)"
[ "$n_def" -gt 0 ] && echo "  Updater self-changed: $n_def (re-run after this to pick up; not auto-applied)"
echo "  Overlay (AGENTS.md, RULE/SKILL_REGISTRY, stack rules, wiki, governance/CI): left untouched"

if [ "$n_new" -eq 0 ] && [ "$n_changed" -eq 0 ] && [ "$schema_changed" != true ]; then
  ok "No core file changes to apply."
  [ "$n_def" -gt 0 ] && warn "Only the updater itself changed upstream — re-copy scripts/update.* manually."
  # Still advance the version stamp so the gate is satisfied next time.
  [ "$DRY_RUN" != true ] && printf '%s\n' "$SRC_VER" > "$ROOT/.sumela/VERSION"
  exit 0
fi

if [ "$DRY_RUN" = true ]; then
  echo ""; info "--dry-run: the following would change (nothing written):"
  for f in ${new_list[@]+"${new_list[@]}"};     do echo "  + $f (new)"; done
  for f in ${changed_list[@]+"${changed_list[@]}"}; do echo "  ~ $f (changed)"; done
  [ "$schema_changed" = true ] && echo "  ~ $SCHEMA_LIVE (changed; derived from template)"
  exit 0
fi

apply_file() { mkdir -p "$ROOT/$(dirname "$1")"; cp "$SRC/$1" "$ROOT/$1"; }

# New core files are additive — copy them.
for f in ${new_list[@]+"${new_list[@]}"}; do apply_file "$f"; ok "added  $f"; done

# Changed core files — ask once how to handle them.
n_skipped=0
if [ "$n_changed" -gt 0 ]; then
  mode="a"
  if [ "$ASSUME_YES" != true ]; then
    echo ""
    echo "$n_changed core file(s) differ from upstream. [a]pply all / [r]eview each / [s]kip all:"
    read -r ans; mode="${ans:-a}"
  fi
  for f in ${changed_list[@]+"${changed_list[@]}"}; do
    case "$mode" in
      s|S) echo "  skip   $f"; n_skipped=$((n_skipped+1)); continue ;;
      r|R)
        echo ""; echo "${BOLD}--- $f ---${RESET}"
        diff -u "$ROOT/$f" "$SRC/$f" | sed 's/^/  /' || true
        echo "Update this file? [y/N]:"; read -r yn
        case "$yn" in y|Y) apply_file "$f"; ok "updated $f" ;; *) echo "  skip   $f"; n_skipped=$((n_skipped+1)) ;; esac ;;
      *) apply_file "$f"; ok "updated $f" ;;
    esac
  done
fi

# Derived live _SCHEMA.md (sourced from the refreshed template) — diff + consent.
if [ "$schema_changed" = true ]; then
  do_schema=true
  if [ "$ASSUME_YES" != true ]; then
    echo ""; echo "${BOLD}--- $SCHEMA_LIVE (derived from template) ---${RESET}"
    diff -u "$ROOT/$SCHEMA_LIVE" "$SRC/$SCHEMA_SRC" | sed 's/^/  /' || true
    echo "Update your live _SCHEMA from the refreshed template? [Y/n]:"; read -r yn
    case "$yn" in n|N) do_schema=false ;; esac
  fi
  if [ "$do_schema" = true ]; then
    mkdir -p "$ROOT/$(dirname "$SCHEMA_LIVE")"; cp "$SRC/$SCHEMA_SRC" "$ROOT/$SCHEMA_LIVE"; ok "updated $SCHEMA_LIVE (from template)"
  else
    echo "  skip   $SCHEMA_LIVE"; n_skipped=$((n_skipped+1))
  fi
fi

# Skill registry: auto-register any newly-added on-disk skills (with consent);
# orphans are reported, not deleted. Rules are NOT auto-reconciled (they need
# phase/stack metadata) — handled by the reminder below.
if [ -f "$ROOT/scripts/reconcile-registry.py" ] && command -v python3 >/dev/null 2>&1; then
  reg_out="$(python3 "$ROOT/scripts/reconcile-registry.py" --check 2>&1)"; reg_rc=$?
  if [ "$reg_rc" -ne 0 ]; then
    echo ""; printf '%s\n' "$reg_out" | sed 's/^/  /'
    do_reg=true
    if [ "$ASSUME_YES" != true ]; then
      echo "Reconcile SKILL_REGISTRY.md now (register new skills; orphans only reported)? [Y/n]:"
      read -r yn; case "$yn" in n|N) do_reg=false ;; esac
    fi
    [ "$do_reg" = true ] && python3 "$ROOT/scripts/reconcile-registry.py" | sed 's/^/  /'
  fi
fi

# Org-shared rules (monorepo): if .sumela-shared/rules/ exists above this install,
# refresh the synced copies + register new ones (universal). No-op otherwise.
if [ -f "$ROOT/scripts/sync-shared-rules.py" ] && command -v python3 >/dev/null 2>&1; then
  shr_out="$(python3 "$ROOT/scripts/sync-shared-rules.py" --check 2>&1)"; shr_rc=$?
  if [ "$shr_rc" -ne 0 ]; then
    echo ""; printf '%s\n' "$shr_out" | sed 's/^/  /'
    do_shr=true
    if [ "$ASSUME_YES" != true ]; then
      echo "Sync org-shared rules into this install now? [Y/n]:"
      read -r yn; case "$yn" in n|N) do_shr=false ;; esac
    fi
    [ "$do_shr" = true ] && python3 "$ROOT/scripts/sync-shared-rules.py" | sed 's/^/  /'
  fi
fi

# --- Finalize ----------------------------------------------------------------
printf '%s\n' "$SRC_VER" > "$ROOT/.sumela/VERSION"
chmod +x "$ROOT/.sumela/git-hooks/pre-commit" "$ROOT/.sumela/git-hooks/post-merge" "$ROOT/.sumela/git-hooks/post-checkout" "$ROOT/.sumela/git-hooks/post-commit" 2>/dev/null || true

echo ""
if [ -f "$ROOT/scripts/validate-structure.sh" ]; then
  info "Validating structure..."
  bash "$ROOT/scripts/validate-structure.sh" || warn "validate-structure reported issues — review above."
fi

echo ""
ok "Core updated to ${SRC_VER}."
[ "$n_skipped" -gt 0 ] && warn "${n_skipped} changed core file(s) were SKIPPED and still differ from upstream ${SRC_VER}. Re-run with --force to revisit them."
warn "Overlay was untouched. Skills were auto-reconciled into SKILL_REGISTRY.md; if RULES"
warn "changed, reconcile RULE_REGISTRY.md via /initSumela's registry step or /evolve (rules need phase/stack metadata)."
# Domain-scope migration notice: the prompt's STEP 4 (core, just refreshed) reads a
# <domain_scopes> section, but RULE_REGISTRY.md is OVERLAY (untouched). A project from
# before the domain feature won't have it — tell the user how to add it (no auto-edit of
# the overlay). Silent when the section is already present or no registry exists yet.
if [ -f "$ROOT/.sumela/RULE_REGISTRY.md" ] && ! grep -qE '^<domain_scopes>$' "$ROOT/.sumela/RULE_REGISTRY.md" 2>/dev/null; then
  warn "Business-domain support arrived in this core, but your RULE_REGISTRY.md has no <domain_scopes> section yet."
  warn "  To enable domains: add the <domain_scopes> block (see RULE_REGISTRY.md.template) — fastest via /onboardSumela or /evolve. Until then domains are simply inactive (no breakage)."
fi
[ "$n_def" -gt 0 ] && warn "The updater itself changed upstream — re-run 'bash scripts/update.sh' to pick up the new version."
echo "Review changes with 'git diff' before committing."
