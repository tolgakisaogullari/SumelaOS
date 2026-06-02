# shellcheck shell=bash
# _lib.sh — shared logic for SumelaOS memory-sync git hooks.
#
# Re-ingests CHANGED session summaries into the developer's LOCAL Qdrant so that
# decisions a teammate committed become semantically searchable right after a
# `git pull`. The markdown summaries in git are the shared source of truth; each
# developer's Qdrant is a derived local cache, and these hooks are the
# cache-invalidation step ("source changed in my worktree -> refresh my cache").
#
# Design contract (all four must hold):
#   * incremental    — only summaries that changed in the pulled/checked-out range
#   * non-blocking    — ingestion runs in the background; never delays git
#   * best-effort     — missing plugin / down Qdrant -> skip silently, exit 0,
#                       never fail a git operation (the data stays in git)
#   * path-scoped     — fires only when files under the summaries dir changed
#
# Opt out per developer: export SUMELA_DISABLE_MEMORY_SYNC=1
# Override paths/endpoints: SUMELA_SUMMARIES_DIR, WIKI_PATH, QDRANT_HOST, QDRANT_PORT

# Git's well-known empty-tree object (lets us diff a fresh clone's HEAD against
# "nothing", so every existing summary counts as added on first checkout).
SUMELA_EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"

# The SumelaOS install may live in a monorepo SUBDIR, not at the git root. Resolve
# the install root ONCE from this file's own location (it lives at
# <install>/.sumela/git-hooks/_lib.sh), independent of cwd or the git root — so a
# subpackage install syncs its OWN summaries, not paths under the repo root.
if [ -z "${SUMELA_INSTALL_ROOT:-}" ]; then
  _sumela_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  SUMELA_INSTALL_ROOT="$(cd "$_sumela_lib_dir/../.." 2>/dev/null && pwd)"
fi

sumela_memory_sync() {
  # $1 = "from" ref, $2 = "to" ref. Ingests summaries changed in from..to.
  local from="$1" to="$2"

  [ -n "${SUMELA_DISABLE_MEMORY_SYNC:-}" ] && return 0

  local repo
  repo="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$repo" ] || return 0

  # Install dir (absolute) and its path within the repo (empty when at the root).
  # Derive install_rel via git, NOT a prefix-strip of pwd vs the resolved root — those
  # differ under a symlinked root (e.g. /tmp -> /private/tmp, /var -> /private/var) and
  # would silently degrade the diff pathspec to root-relative, skipping a subdir's summaries.
  local install="${SUMELA_INSTALL_ROOT:-$repo}"
  local install_rel
  install_rel="$(git -C "$install" rev-parse --show-prefix 2>/dev/null)"
  install_rel="${install_rel%/}"

  # Qdrant plugin not installed in this project -> nothing to sync.
  local ingest="$install/.sumela/memory-plugins/qdrant-session-memory/scripts/session-ingest.py"
  [ -f "$ingest" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  local summaries_dir="${SUMELA_SUMMARIES_DIR:-${WIKI_PATH:-docs/second-brain/wiki}/session-summaries}"
  [ -d "$install/$summaries_dir" ] || return 0

  # The diff runs at the git root, so the pathspec must be root-relative: prefix the
  # install's in-repo path when SumelaOS lives in a subdir.
  local pathspec="${install_rel:+$install_rel/}$summaries_dir"

  # Which summaries were Added/Modified in this range? (Deletes are ignored —
  # removing a summary file does not retract a past decision from memory.)
  # core.quotePath=false: keep non-ASCII paths raw (Turkish/Unicode filenames)
  # instead of git's default octal-escaped, double-quoted form — otherwise the
  # file-existence guard below would silently skip them. (Newline-in-filename
  # is still unsupported — unrealistic for committed summary slugs.)
  local changed
  changed="$(git -C "$repo" -c core.quotePath=false diff --name-only --diff-filter=AM "$from" "$to" -- "$pathspec" 2>/dev/null)" || return 0
  [ -n "$changed" ] || return 0

  # Prereq gate: Qdrant must be reachable. If not, skip silently — the summaries
  # are safely in git and the next pull (or a manual re-ingest) will catch up.
  local qhost="${QDRANT_HOST:-localhost}" qport="${QDRANT_PORT:-6333}"
  if ! command -v curl >/dev/null 2>&1 || \
     ! curl -fsS --max-time 2 "http://${qhost}:${qport}/readyz" >/dev/null 2>&1; then
    echo "sumela: memory sync skipped (Qdrant not reachable at ${qhost}:${qport})"
    return 0
  fi

  local count
  count="$(printf '%s\n' "$changed" | grep -c .)"
  local log="$install/.sumela/.memory-sync.log"
  # Keep the per-developer log bounded (truncate past ~512 KB).
  [ -f "$log" ] && [ "$(wc -c <"$log" 2>/dev/null || echo 0)" -gt 524288 ] && : >"$log"
  echo "sumela: syncing ${count} changed session summary file(s) to local Qdrant in background (log: .sumela/.memory-sync.log)"

  # Background subshell so the git operation returns immediately. stdin/stdout/
  # stderr are detached (to a log) so git does not wait on the descriptors.
  (
    cd "$repo" || exit 0
    echo "===== memory-sync: ${count} file(s) ====="
    printf '%s\n' "$changed" | while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ ! -f "$repo/$f" ]; then
        echo "WARN: changed summary not found on disk, skipping: $f"
        continue
      fi
      python3 "$ingest" "$repo/$f" || echo "WARN: ingest failed for $f"
    done
    echo "===== memory-sync: done ====="
  ) >>"$log" 2>&1 </dev/null &

  return 0
}
