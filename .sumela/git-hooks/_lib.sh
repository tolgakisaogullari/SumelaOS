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
# This file also provides sumela_graph_sync (below): a best-effort, non-blocking
# refresh of the LOCAL graphify code graph after a pull, so dependency/impact
# queries reflect the code that just arrived. It writes ONLY the gitignored graph
# dir (never the tracked tree).
#
# Opt out per developer: export SUMELA_DISABLE_MEMORY_SYNC=1 (summaries) and/or
#                        export SUMELA_DISABLE_GRAPH_SYNC=1  (code graph)
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

# Best-effort: read a single frontmatter scalar (first match) from a summary file.
# Only scans the leading `---`…`---` block so body text can't shadow a key.
# awk (not sed) for portability — BSD/macOS sed mishandles a one-line `{ s///p }`.
_sumela_fm() {  # $1 = file, $2 = key  → prints the value (may be empty)
  [ -f "$1" ] || return 0
  awk -v key="$2" '
    NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }     # no frontmatter block
    NR>1  && $0 ~  /^---[[:space:]]*$/ { exit }     # end of frontmatter
    $0 ~ "^[[:space:]]*" key "[[:space:]]*:" {
      sub("^[[:space:]]*" key "[[:space:]]*:[[:space:]]*", ""); print; exit
    }
  ' "$1" 2>/dev/null
}

# Build one human-readable "who / when / what" line for a changed summary, so the
# pull log tells the user WHOSE work and WHICH tasks just became searchable.
#   who   = git author of the commit that brought this change in (from..to)
#   when  = frontmatter session_date, else the commit's short date
#   what  = filename (session id) + frontmatter session_topics
_sumela_summary_desc() {  # $1=repo $2=from $3=to $4=relpath
  local repo="$1" from="$2" to="$3" f="$4" full="$1/$4"
  local id who when topics
  id="$(basename "$f" .md)"
  who="$(git -C "$repo" log -1 --format='%an' "$from..$to" -- "$f" 2>/dev/null)"
  when="$(_sumela_fm "$full" session_date)"
  [ -z "$when" ] && when="$(git -C "$repo" log -1 --format='%ad' --date=short "$from..$to" -- "$f" 2>/dev/null)"
  topics="$(_sumela_fm "$full" session_topics | tr -d "[]\"'" )"
  local line="  • ${who:-unknown}"
  [ -n "$when" ]   && line="$line  ${when}"
  line="$line  ${id}"
  [ -n "$topics" ] && line="$line  [${topics}]"
  printf '%s\n' "$line"
}

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

  # Describe WHO and WHICH tasks each arriving summary belongs to (best-effort,
  # cheap for a normal pull). Built once; reused for the inline heads-up and the log.
  local details
  details="$(printf '%s\n' "$changed" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    _sumela_summary_desc "$repo" "$from" "$to" "$f"
  done)"

  # Inline heads-up: header + up to 10 descriptors; the rest (and the ingest
  # results) go to the background log so git is never delayed.
  echo "sumela: ${count} session summary file(s) arrived in this pull — ingesting into local Qdrant in background:"
  printf '%s\n' "$details" | head -10
  [ "$count" -gt 10 ] && echo "  … and $((count - 10)) more — full list + ingest results: .sumela/.memory-sync.log"
  [ "$count" -le 10 ] && echo "  (ingest results: .sumela/.memory-sync.log)"

  # Background subshell so the git operation returns immediately. stdin/stdout/
  # stderr are detached (to a log) so git does not wait on the descriptors.
  (
    cd "$repo" || exit 0
    echo "===== memory-sync: ${count} file(s) @ $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) ====="
    echo "Source (who / when / task):"
    printf '%s\n' "$details"
    echo "-----"
    printf '%s\n' "$changed" | while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ ! -f "$repo/$f" ]; then
        echo "WARN: changed summary not found on disk, skipping: $f"
        continue
      fi
      echo ">>> ingesting: $f"
      python3 "$ingest" "$repo/$f" || echo "WARN: ingest failed for $f"
    done
    echo "===== memory-sync: done ====="
  ) >>"$log" 2>&1 </dev/null &

  return 0
}

# Refresh the LOCAL code graph (graphify) after a pull/checkout, so dependency &
# impact queries reflect the code that just arrived (teammates' work AND your own
# merged branch). Design contract (mirrors sumela_memory_sync):
#   * incremental  — only when actual CODE changed in the range (a doc/agent-only
#                    pull is skipped; the graph is unaffected by docs/ or .sumela/)
#   * non-blocking — graphify runs in the background; never delays git
#   * best-effort  — no plugin / no `graphify` CLI / no python3 -> skip silently, exit 0
#   * clean tree   — runs `auto-update-memory.py --graph-only`, which writes ONLY the
#                    gitignored graph dir (NO wiki sync, NO _LOG append), so a pull
#                    NEVER dirties the working tree
sumela_graph_sync() {
  # $1 = "from" ref, $2 = "to" ref.
  local from="$1" to="$2"

  [ -n "${SUMELA_DISABLE_GRAPH_SYNC:-}" ] && return 0

  local repo
  repo="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$repo" ] || return 0

  # Resolve the install (may be a monorepo subdir) the same way memory-sync does.
  local install="${SUMELA_INSTALL_ROOT:-$repo}"

  # Self-gate: graphify plugin + CLI + python3 + the updater must all be present.
  [ -d "$install/.sumela/memory-plugins/graphify-code-graph" ] || return 0
  command -v graphify >/dev/null 2>&1 || return 0
  command -v python3  >/dev/null 2>&1 || return 0
  local updater="$install/scripts/auto-update-memory.py"
  [ -f "$updater" ] || return 0

  # Install path within the repo (root-relative; "" at the repo root), for scoping.
  local install_rel
  install_rel="$(git -C "$install" rev-parse --show-prefix 2>/dev/null)"
  install_rel="${install_rel%/}"
  local scope="${install_rel:+$install_rel/}"

  # Did real CODE change in this range? Limit to this install's subtree and exclude
  # the agent/wiki layer (docs/, .sumela/) via git pathspec. If nothing else changed,
  # the graph is unchanged — skip the rebuild.
  local changed_code
  changed_code="$(git -C "$repo" diff --name-only "$from" "$to" -- \
      "${install_rel:-.}" ":(exclude)${scope}docs" ":(exclude)${scope}.sumela" 2>/dev/null | head -1)"
  [ -n "$changed_code" ] || return 0

  local log="$install/.sumela/.graph-sync.log"
  [ -f "$log" ] && [ "$(wc -c <"$log" 2>/dev/null || echo 0)" -gt 524288 ] && : >"$log"
  echo "sumela: code changed in this pull — refreshing local code graph (graphify) in background (log: .sumela/.graph-sync.log)"

  # Background + detached so git returns immediately (graphify can be slow on a big repo).
  (
    cd "$install" || exit 0
    echo "===== graph-sync @ $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) ====="
    python3 "$updater" --project-root "$install" --graph-only || echo "WARN: graph refresh failed"
    echo "===== graph-sync: done ====="
  ) >>"$log" 2>&1 </dev/null &

  return 0
}
