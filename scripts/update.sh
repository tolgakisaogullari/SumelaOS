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
#
# OVERLAY (never touched): AGENTS.md, .sumela/RULE_REGISTRY.md,
#   .sumela/SKILL_REGISTRY.md, stack rules (backend/frontend/mobile_standards,
#   operational_excellence_maintenance), docs/second-brain/wiki/* (except _SCHEMA.md),
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

n_new=${#new_list[@]}; n_changed=${#changed_list[@]}; n_def=${#deferred_list[@]}
echo ""
echo "${BOLD}=== SumelaOS core update: ${LOCAL_VER} → ${SRC_VER} ===${RESET}"
echo "  New core files:      $n_new"
echo "  Changed core files:  $n_changed"
[ "$n_def" -gt 0 ] && echo "  Updater self-changed: $n_def (re-run after this to pick up; not auto-applied)"
echo "  Overlay (AGENTS.md, RULE/SKILL_REGISTRY, stack rules, wiki, governance/CI): left untouched"

if [ "$n_new" -eq 0 ] && [ "$n_changed" -eq 0 ]; then
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

# --- Finalize ----------------------------------------------------------------
printf '%s\n' "$SRC_VER" > "$ROOT/.sumela/VERSION"
chmod +x "$ROOT/.sumela/git-hooks/pre-commit" "$ROOT/.sumela/git-hooks/post-merge" "$ROOT/.sumela/git-hooks/post-checkout" 2>/dev/null || true

echo ""
if [ -f "$ROOT/scripts/validate-structure.sh" ]; then
  info "Validating structure..."
  bash "$ROOT/scripts/validate-structure.sh" || warn "validate-structure reported issues — review above."
fi

echo ""
ok "Core updated to ${SRC_VER}."
[ "$n_skipped" -gt 0 ] && warn "${n_skipped} changed core file(s) were SKIPPED and still differ from upstream ${SRC_VER}. Re-run with --force to revisit them."
warn "Overlay was untouched. If this update ADDED or REMOVED skills/rules, reconcile the"
warn "registries by hand (or re-run /initSumela's registry step): SKILL_REGISTRY.md / RULE_REGISTRY.md."
warn "Wiki _SCHEMA: the template was refreshed; to update your live copy, diff/copy"
warn "docs/second-brain/template/wiki/_SCHEMA.md → docs/second-brain/wiki/_SCHEMA.md."
[ "$n_def" -gt 0 ] && warn "The updater itself changed upstream — re-run 'bash scripts/update.sh' to pick up the new version."
echo "Review changes with 'git diff' before committing."
