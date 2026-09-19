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
# NOTE: upstream.conf is NOT a CORE file, so once a fork sets it, updates never
# overwrite it — to re-sync to the original upstream, edit/delete it manually.
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
  # Restrict transports so a poisoned .sumela/upstream.conf can't run code via git's
  # ext::/file:: transport (the framework is only ever fetched over https/ssh/git).
  GIT_ALLOW_PROTOCOL=https:ssh:git git clone --depth 1 "$REPO_URL" "$CLONE_TMP" >/dev/null 2>&1 || { err "clone failed"; exit 1; }
  SRC="$CLONE_TMP"
fi

# --- Version gate ------------------------------------------------------------
read_ver() { [ -f "$1/.sumela/VERSION" ] && tr -d '[:space:]' < "$1/.sumela/VERSION" || echo "unknown"; }
SRC_VER="$(read_ver "$SRC")"
LOCAL_VER="$(read_ver "$ROOT")"
info "Local core version: ${LOCAL_VER}    Upstream: ${SRC_VER}"
# --- Reconcile the SumelaOS-managed .gitignore patterns ----------------------
# Runs BEFORE the version gate, so even an already-current install backfills any
# newly-shipped managed pattern. .gitignore is OVERLAY (never overwritten), so new
# managed runtime-artifact patterns would otherwise reach only FRESH installs, not
# projects that upgrade via this script (the gap that left .sumela/.update-check
# untracked on upgrade from <0.7.1). Backfill from the SINGLE SOURCE that setup.sh
# also uses (scripts/lib/sumela-gitignore.sh, taken from the new $SRC). Idempotent:
# only ADDS patterns absent anywhere in .gitignore; never duplicates an existing
# entry and never touches the user's own lines.
reconcile_gitignore() {
  local lib="$SRC/scripts/lib/sumela-gitignore.sh"
  [ -f "$lib" ] || return 0
  # shellcheck disable=SC1090
  . "$lib"
  command -v sumela_gitignore_lines >/dev/null 2>&1 || return 0

  local gi="$ROOT/.gitignore" ln yn=""
  local -a missing=()
  while IFS= read -r ln; do
    [ -n "$ln" ] || continue
    if [ -f "$gi" ] && grep -qxF "$ln" "$gi" 2>/dev/null; then continue; fi
    missing+=( "$ln" )
  done <<EOF
$(sumela_gitignore_lines)
EOF

  [ "${#missing[@]}" -gt 0 ] || return 0

  echo ""
  info ".gitignore is missing ${#missing[@]} SumelaOS runtime-artifact pattern(s):"
  for ln in ${missing[@]+"${missing[@]}"}; do echo "  + $ln"; done

  if [ "$DRY_RUN" = true ]; then warn "--dry-run: would add the above to $gi (nothing written)"; return 0; fi
  if [ "$ASSUME_YES" != true ]; then
    printf "Add these to .gitignore? [Y/n]: "
    read -r yn || yn=""; case "$yn" in n|N) info "skipped .gitignore reconcile"; return 0 ;; esac
  fi

  {
    [ -s "$gi" ] && echo ""
    echo "# SumelaOS — runtime artifacts (reconciled by update.sh)"
    for ln in ${missing[@]+"${missing[@]}"}; do echo "$ln"; done
  } >> "$gi"
  ok ".gitignore reconciled (+${#missing[@]} entr$([ "${#missing[@]}" -eq 1 ] && echo y || echo ies))"
}
reconcile_gitignore

# --- Migrate Qdrant memory collections to per-project namespacing ------------
# Runs BEFORE the version gate so an already-current install still migrates (the
# namespacing change can ship without a version bump that the gate would otherwise
# skip). Best-effort + idempotent: the script records its per-(instance,slug)
# decisions and no-ops on re-run; it does NOTHING unless the qdrant-session-memory
# plugin is installed AND a local Qdrant is reachable. Honors --dry-run.
migrate_qdrant_collections() {
  local mig="$ROOT/.sumela/memory-plugins/qdrant-session-memory/scripts/migrate-collections.py"
  [ -f "$mig" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local qhost="${QDRANT_HOST:-localhost}" qport="${QDRANT_PORT:-6333}"
  command -v curl >/dev/null 2>&1 || return 0
  curl -fsS --max-time 2 "http://${qhost}:${qport}/readyz" >/dev/null 2>&1 || return 0
  local -a margs=()
  [ "$DRY_RUN" = true ] && margs+=(--dry-run)
  echo ""
  info "Checking Qdrant memory collections for per-project namespacing…"
  python3 "$mig" ${margs[@]+"${margs[@]}"} 2>&1 | sed 's/^/  /'
}
migrate_qdrant_collections

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
  # NOT covered by CORE_DIRS: that entry is .sumela/rules/templates/, one level
  # BELOW this file. init-sumela copies it to a LIVE rule, so an edit here only
  # reaches an existing install if it is named explicitly.
  ".sumela/rules/operational_excellence_maintenance.md.template"
  # The same trap one directory up: .sumela/ itself is not a CORE_DIR, so anything shipped at
  # its ROOT reaches fresh installs only. This template is framework-authored (init-sumela
  # renders it into the OVERLAY RULE_REGISTRY.md) and it carried the anti-fork guidance added
  # in v0.9.0 — which therefore never reached a single upgrading install. The RENDERED
  # RULE_REGISTRY.md stays OVERLAY and is still never overwritten.
  ".sumela/RULE_REGISTRY.md.template"
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
[ "$n_def" -gt 0 ] && echo "  Updater self-changed: $n_def (installed during this run; re-run with --force to finish)"
echo "  Overlay (AGENTS.md, RULE/SKILL_REGISTRY, stack rules, wiki, governance/CI): left untouched"

prior_vendored() {
  # Paths a PREVIOUS PASS OF THIS SAME UPGRADE vendored — nothing else.
  #
  # The two-pass flow (updater-only pass, then the forced re-run) must not lose scripts/update.*
  # from the record. But carrying every past record forward unconditionally is worse than losing
  # it: a file vendored once would satisfy the self-modification guard forever, so a later
  # hand-edit of e.g. security_protocol.md would be announced as a verified upgrade. Version
  # numbers cannot tell the two cases apart either — both passes of one upgrade can share a
  # version, and two upgrades can too. So the FIRST pass marks the record explicitly, and only a
  # record carrying that mark is merged. The mark is cleared by the pass that consumes it.
  local rec="$ROOT/.sumela/.last-update.json"
  [ -f "$rec" ] || return 0
  grep -q '"pending_rerun": true' "$rec" 2>/dev/null || return 0
  sed -n 's/^    "\(.*\)".*$/\1/p' "$rec"
}

write_provenance() {   # $1 = version, $2 = pending_rerun (true|false), rest = paths
  [ "$DRY_RUN" = true ] && return 0
  # Read the prior list BEFORE opening the redirect: `> $rec` truncates at redirect time,
  # i.e. before the brace group's body runs, so reading it inside would always see nothing.
  _ver="$1"; _pending="$2"; shift 2
  _prior="$(prior_vendored)"
  {
    printf '{\n'
    printf '  "version": "%s",\n' "$_ver"
    printf '  "updated_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "pending_rerun": %s,\n' "$_pending"
    printf '  "files": [\n'
    printf '%s\n' "$@" ${_prior:+$_prior} | sort -u | while IFS= read -r _p; do
      [ -n "$_p" ] && printf '    "%s"\n' "$_p"
    done | sed '$!s/$/,/'
    printf '  ]\n}\n'
  } > "$ROOT/.sumela/.last-update.json" 2>/dev/null || true
  unset _prior _ver _pending
}

# Install the new updater over the old one. An updater only knows the CORE list IT shipped
# with, so when scripts/update.{sh,ps1} change upstream this run may have silently skipped
# files that became CORE after this copy was written — that is how
# operational_excellence_maintenance.md.template stayed frozen through a 0.15 -> 0.17 upgrade.
# Echoes each installed path so the caller can fold them into the provenance record.
install_self() {
  [ "$n_def" -gt 0 ] || return 0
  [ "$DRY_RUN" = true ] && return 0
  # "[s]kip all" is a statement about vendored overwrites in general; silently replacing a
  # fork's patched updater would contradict it. Honour the same answer here.
  case "${mode:-a}" in s|S) return 0 ;; esac
  # ...and so is reviewing each file and declining all of them.
  if [ "${n_changed:-0}" -gt 0 ] && [ -z "${applied_changed:-}" ]; then return 0; fi
  for _self in $SELF_DEFER; do
    [ -f "$SRC/$_self" ] || continue
    # Only the ones that actually differ — otherwise an unchanged twin gets a .bak and is
    # recorded as vendored when nothing about it changed.
    cmp -s "$SRC/$_self" "$ROOT/$_self" 2>/dev/null && continue
    _tmp="$ROOT/$_self.sumela-new.$$"
    # Keep the outgoing copy: this is the one file the user cannot diff during the run.
    [ -f "$ROOT/$_self" ] && cp "$ROOT/$_self" "$ROOT/$_self.bak" 2>/dev/null || true
    if cp "$SRC/$_self" "$_tmp" 2>/dev/null && mv -f "$_tmp" "$ROOT/$_self" 2>/dev/null; then
      printf '%s\n' "$_self"
    else
      rm -f "$_tmp" 2>/dev/null || true
      # A '!' prefix marks a failure. Swallowing it meant installing update.ps1 but not
      # update.sh read as success: VERSION stamped, old updater stranded, log claiming
      # "the NEW scripts/update.sh has been installed".
      printf '!%s\n' "$_self"
    fi
  done
  unset _self _tmp
}

if [ "$n_new" -eq 0 ] && [ "$n_changed" -eq 0 ] && [ "$schema_changed" != true ]; then
  ok "No core file changes to apply."
  if [ "$n_def" -gt 0 ]; then
    # Updater-only release. This used to exit here telling the user to copy the files by
    # hand — and the version stamp below then made a re-run report "Already on core version",
    # stranding the old updater permanently. Install it here instead; nothing else changed,
    # so no re-run is needed.
    _installed="$(install_self)"
    if [ -n "$_installed" ]; then
      ok "Updater refreshed: $(printf '%s' "$_installed" | tr '\n' ' ')"
      # Record it, or the self-modification guard sees changed scripts/ paths that no record
      # explains and classifies this vendored upgrade as developer-authored.
      # Stamp the version still in .sumela/VERSION, not SRC_VER: this branch deliberately
      # leaves VERSION alone, and the guard requires record.version == VERSION to validate.
      write_provenance "$LOCAL_VER" true $_installed
      # Deliberately do NOT stamp VERSION here. "No core changes" was computed from the OLD
      # updater's CORE list, which is the thing we just replaced because it cannot be trusted
      # to be complete — a release that changes the updater AND adds a root-level CORE entry
      # would lose that file forever if we declared the install current. Leaving the stamp
      # behind makes the next plain re-run do a real pass with the NEW updater.
      warn "Version NOT stamped: the new updater must re-check the file set it knows about."
      warn "  RE-RUN NOW to finish:  bash scripts/update.sh"
      [ "$DRY_RUN" != true ] && rm -f "$ROOT/.sumela/.update-check"
      exit 0
    elif [ "$DRY_RUN" != true ]; then
      # The copy failed (permissions, read-only checkout, disk). Stamping VERSION here would
      # declare the install current and strand the old updater permanently, silently.
      warn "Could not install the new updater. Version NOT stamped — fix the cause and re-run."
      warn "  Expected to replace: $SELF_DEFER"
      exit 1
    fi
    unset _installed
  fi
  # Nothing changed at all — advance the version stamp so the gate is satisfied next time.
  if [ "$DRY_RUN" != true ]; then
    # Re-stamp any record an earlier updater-only pass left at the OLD version: advancing
    # VERSION without it would break `record.version == VERSION` and make the vendored
    # scripts/update.* read as developer-authored on the next review.
    _carry="$(prior_vendored)"
    printf '%s\n' "$SRC_VER" > "$ROOT/.sumela/VERSION"
    [ -n "$_carry" ] && write_provenance "$SRC_VER" false $_carry
    unset _carry
    rm -f "$ROOT/.sumela/.update-check"
  fi
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
applied_changed=""   # only these go into the provenance record
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
        case "$yn" in y|Y) apply_file "$f"; applied_changed="$applied_changed $f"; ok "updated $f" ;; *) echo "  skip   $f"; n_skipped=$((n_skipped+1)) ;; esac ;;
      *) apply_file "$f"; applied_changed="$applied_changed $f"; ok "updated $f" ;;
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
# Install the new updater BEFORE the version stamp and before the record below. Before the
# STAMP because a failed install must not be locked in behind the version gate — the same
# reason the updater-only branch above refuses to stamp. Before the RECORD because those
# paths are vendored content too, and `requesting-code-review`'s self-modification guard
# treats any changed path ABSENT from the record as developer-authored, which would force a
# Deep-tier review and a false self-modification banner on the very next review.
SELF_RESULT="$(install_self)"
SELF_INSTALLED="$(printf '%s\n' "$SELF_RESULT" | grep -v '^!' || true)"
SELF_UNINSTALLED="$(printf '%s\n' "$SELF_RESULT" | grep '^!' | sed 's/^!//' || true)"

if [ "$n_def" -gt 0 ] && [ -n "${SELF_UNINSTALLED:-}" ] && \
   ! { [ "${mode:-a}" = "s" ] || [ "${mode:-a}" = "S" ] || \
       { [ "${n_changed:-0}" -gt 0 ] && [ -z "${applied_changed:-}" ]; }; }; then
  # A real failure, not a declined install: leave VERSION alone so a re-run retries. The
  # file changes this run applied are already on disk and re-applying them is idempotent.
  warn "Could not install: $(printf '%s' "$SELF_UNINSTALLED" | tr '\n' ' ')"
  warn "  VERSION left at ${LOCAL_VER} so a re-run retries."
  RECORD_VER="$LOCAL_VER"
else
  printf '%s\n' "$SRC_VER" > "$ROOT/.sumela/VERSION"
  RECORD_VER="$SRC_VER"
fi
# The update-check cache still holds the version we were BEFORE this run, so the next pull
# would announce an upgrade that already happened. Delete rather than rewrite: _lib.sh owns
# the "<epoch>\t<remote_ver>" format and re-probes whenever the file is missing.
rm -f "$ROOT/.sumela/.update-check"

# Record what THIS run vendored, plus anything a pending first pass left (see prior_vendored,
# which keys on the record's own pending_rerun marker rather than on version numbers).
# Record that THIS run vendored these files. `requesting-code-review`'s
# self-modification guard has to tell a framework upgrade (vendored content the
# developer did not write) from a hand-edited rule, and it cannot do that from the
# diff's shape: bumping VERSION is what a normal commit does, and CORE_FILES contains
# security_protocol.md. Without a record the guard has no executable test — $SRC is a
# local here and CLONE_TMP is trapped away on exit, so nothing survives to compare
# against. Per-developer state; gitignored alongside the other runtime artifacts.
_derived=""
[ "${do_schema:-false}" = true ] && _derived="$SCHEMA_LIVE"
write_provenance "$RECORD_VER" false ${new_list[@]+"${new_list[@]}"} ${applied_changed:-} \
                 ${_derived:+"$_derived"} ${SELF_INSTALLED:+$SELF_INSTALLED}
unset _derived
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
if [ "$n_def" -gt 0 ] && [ -n "${SELF_UNINSTALLED:-}" ]; then
  case "${mode:-a}" in
    s|S) warn "The updater also changed upstream; left in place because you chose [s]kip all."
         warn "  Apply it when you want to:  bash scripts/update.sh --force" ;;
    r|R) if [ "${n_changed:-0}" -gt 0 ] && [ -z "${applied_changed:-}" ]; then
           warn "The updater also changed upstream; left in place because you declined every file."
           warn "  Apply it when you want to:  bash scripts/update.sh --force"
         else
           warn "The updater changed upstream but could NOT be installed — replace scripts/update.sh"
           warn "  by hand from the source clone, then re-run:  bash scripts/update.sh --force"
         fi ;;
    *)   warn "The updater changed upstream but could NOT be installed — replace scripts/update.sh"
         warn "  by hand from the source clone, then re-run:  bash scripts/update.sh --force" ;;
  esac
elif [ "$n_def" -gt 0 ]; then
  # Already installed above (before the provenance record). Say so loudly — one line at the
  # end of a long log was not enough to get anyone to re-run it.
  warn "The updater itself changed upstream. The NEW scripts/update.sh has been installed."
  warn "  This run was executed by the OLD one, which cannot know about files that became"
  warn "  CORE in a release between your previous version and ${SRC_VER}."
  warn "  RE-RUN NOW to finish the upgrade:  bash scripts/update.sh --force"
  warn "  (--force is required: this run already stamped VERSION, so a plain re-run would"
  warn "   stop at the version gate without applying anything.)"
fi
echo "Review changes with 'git diff' before committing."
