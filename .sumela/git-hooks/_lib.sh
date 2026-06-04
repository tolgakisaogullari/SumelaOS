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
# This file also provides three more best-effort, non-blocking pull-time refreshers
# of LOCAL derived caches (so a teammate's pulled work becomes searchable/queryable
# on your machine) — none of which touch the tracked tree:
#   * sumela_graph_sync — graphify code graph (gitignored graph dir)
#   * sumela_wiki_sync  — Qdrant `wiki_pages` (re-ingest changed pages; prune removed)
#   * sumela_code_sync  — Qdrant `code_chunks` (prune removed always; heavy whole-tree
#                         re-embed only when stale -> approval prompt / notice)
# All four prune orphans for files deleted upstream EXCEPT chat_history, where a
# removed summary is intentionally retained (deleting a file does not retract a
# past decision from memory).
#
# Opt out / tune per developer:
#   export SUMELA_DISABLE_MEMORY_SYNC=1   # session summaries -> chat_history (default on)
#   export SUMELA_DISABLE_GRAPH_SYNC=1    # graphify code graph              (default on)
#   export SUMELA_DISABLE_WIKI_SYNC=1     # Qdrant wiki_pages                (default on)
#   export SUMELA_DISABLE_CODE_SYNC=1     # Qdrant code_chunks: off entirely (no prune/prompt)
#   export SUMELA_PULL_CODE_REINGEST=1    # Qdrant code_chunks: always re-embed on code change
#   export SUMELA_CODE_REINGEST_DAYS=N    # code_chunks staleness threshold for the prompt (default 14)
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
      # Attribution fallback: if the summary's frontmatter has no `developer`/`session_date`,
      # stamp the commit's git author + date (the work this summary records arrived in this
      # range). Frontmatter, when present, always wins inside session-ingest.py.
      fa="$(git -C "$repo" log -1 --format='%an' "$from..$to" -- "$f" 2>/dev/null)" || fa=""
      fd="$(git -C "$repo" log -1 --format='%ad' --date=short "$from..$to" -- "$f" 2>/dev/null)" || fd=""
      ingest_args=("$repo/$f")
      [ -n "$fa" ] && ingest_args+=(--fallback-developer "$fa")
      [ -n "$fd" ] && ingest_args+=(--fallback-date "$fd")
      python3 "$ingest" "${ingest_args[@]}" || echo "WARN: ingest failed for $f"
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

# Is the local Qdrant reachable? (cheap pre-check so we don't background an ingest
# that would just fail). Returns 0 if readyz responds within 2s, else 1.
_sumela_qdrant_up() {
  local qhost="${QDRANT_HOST:-localhost}" qport="${QDRANT_PORT:-6333}"
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsS --max-time 2 "http://${qhost}:${qport}/readyz" >/dev/null 2>&1
}

# Delete Qdrant points for files that were DELETED upstream (orphan cleanup). The
# ingest scripts only re-upsert files they still see on disk, so a removed file's
# embedding lingers and keeps surfacing in search — this drops it by payload key.
# Call from inside the background subshell (it shells out to python3 per file).
#   $1=install  $2=collection  $3=key field  $4=mode (path|basename-md)  $5=newline list
_sumela_delete_orphans() {
  local install="$1" collection="$2" keyfield="$3" mode="$4" list="$5"
  local del="$install/.sumela/memory-plugins/qdrant-session-memory/scripts/delete-from-qdrant.py"
  [ -f "$del" ] || return 0
  printf '%s\n' "$list" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    local val="$f"
    [ "$mode" = "basename-md" ] && { val="$(basename "$f")"; val="${val%.md}"; }
    python3 "$del" --collection "$collection" --key "$keyfield" --value "$val" \
      || echo "WARN: orphan delete failed for $f"
  done
}

# Refresh the Qdrant `wiki_pages` collection after a pull, so semantic search over
# curated wiki pages reflects teammates' just-pulled updates. The tracked markdown
# is already current (git), but its LOCAL embedding is not — this re-ingests it.
# Same contract: incremental (only when a curated page changed — session-summaries
# and the underscore-special/derived files are excluded), non-blocking, best-effort,
# and it writes ONLY to Qdrant (a local cache), never the tracked tree.
sumela_wiki_sync() {  # $1 = "from" ref, $2 = "to" ref
  local from="$1" to="$2"
  [ -n "${SUMELA_DISABLE_WIKI_SYNC:-}" ] && return 0

  local repo; repo="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$repo" ] || return 0
  local install="${SUMELA_INSTALL_ROOT:-$repo}"
  local ingest="$install/.sumela/memory-plugins/qdrant-session-memory/scripts/ingest-wiki-to-qdrant.py"
  [ -f "$ingest" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  local install_rel; install_rel="$(git -C "$install" rev-parse --show-prefix 2>/dev/null)"; install_rel="${install_rel%/}"
  local scope="${install_rel:+$install_rel/}"
  local wikidir="${WIKI_PATH:-docs/second-brain/wiki}"

  # Which CURATED wiki pages changed / were removed? Drop session-summaries
  # (-> chat_history, handled by memory-sync) and the underscore-special/derived
  # files (_LOG/_INDEX/_SEARCH_INDEX/_SCHEMA) the ingest script itself excludes —
  # so e.g. a union-merged _LOG.md alone never triggers a pointless re-ingest.
  local changed deleted
  changed="$(git -C "$repo" -c core.quotePath=false diff --name-only --diff-filter=AM "$from" "$to" -- "${scope}${wikidir}" 2>/dev/null \
    | grep -vE '/session-summaries/' | grep -vE '/_[^/]*\.md$' | grep -E '\.md$')"
  deleted="$(git -C "$repo" -c core.quotePath=false diff --name-only --diff-filter=D "$from" "$to" -- "${scope}${wikidir}" 2>/dev/null \
    | grep -vE '/session-summaries/' | grep -vE '/_[^/]*\.md$' | grep -E '\.md$')"
  [ -n "$changed$deleted" ] || return 0

  _sumela_qdrant_up || { echo "sumela: wiki_pages sync skipped (Qdrant not reachable)"; return 0; }

  local log="$install/.sumela/.memory-sync.log"
  local n_chg n_del
  n_chg="$(printf '%s\n' "$changed" | grep -c .)"; n_del="$(printf '%s\n' "$deleted" | grep -c .)"
  echo "sumela: wiki changed in this pull (${n_chg} updated, ${n_del} removed) — syncing Qdrant wiki_pages in background (log: .sumela/.memory-sync.log)"
  (
    cd "$install" || exit 0
    echo "===== wiki-sync @ $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) ====="
    # Removed pages: drop their orphaned embeddings (page_path = repo-relative path).
    [ -n "$deleted" ] && { echo "Pruning removed pages:"; _sumela_delete_orphans "$install" wiki_pages page_path path "$deleted"; }
    # Added/modified pages: re-ingest (whole-wiki walk; idempotent per-page upsert).
    [ -n "$changed" ] && { echo ">>> re-ingesting wiki pages"; python3 "$ingest" || echo "WARN: wiki ingest failed"; }
    echo "===== wiki-sync: done ====="
  ) >>"$log" 2>&1 </dev/null &
  return 0
}

# Maintain the Qdrant `code_chunks` collection after a pull. Two parts with very
# different costs, so they're gated differently:
#   * PRUNE (cheap) — drop orphaned points for code files removed in this pull;
#     runs whenever code was deleted and Qdrant is up.
#   * RE-EMBED (heavy) — re-ingest the WHOLE source tree via Ollama. NOT run on
#     every pull (graph-sync already refreshes the structural code view). Instead:
#       - SUMELA_PULL_CODE_REINGEST=1 -> always re-embed on a code change (power user)
#       - else, only when code_chunks is STALE (no refresh for > SUMELA_CODE_REINGEST_DAYS,
#         default 14): PROMPT for approval on an interactive pull (default No, 30s
#         timeout), or print a non-blocking notice on a non-interactive pull.
#   Disable everything (no prune, no prompt, no re-embed): SUMELA_DISABLE_CODE_SYNC=1
sumela_code_sync() {  # $1 = "from" ref, $2 = "to" ref
  local from="$1" to="$2"
  [ -n "${SUMELA_DISABLE_CODE_SYNC:-}" ] && return 0

  local repo; repo="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$repo" ] || return 0
  local install="${SUMELA_INSTALL_ROOT:-$repo}"
  local ingest="$install/.sumela/memory-plugins/qdrant-session-memory/scripts/ingest-code-to-qdrant.py"
  [ -f "$ingest" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  local install_rel; install_rel="$(git -C "$install" rev-parse --show-prefix 2>/dev/null)"; install_rel="${install_rel%/}"
  local scope="${install_rel:+$install_rel/}"

  # Code added/modified vs removed in this range (exclude docs/ + .sumela/).
  local changed deleted
  changed="$(git -C "$repo" diff --name-only --diff-filter=AM "$from" "$to" -- \
      "${install_rel:-.}" ":(exclude)${scope}docs" ":(exclude)${scope}.sumela" 2>/dev/null)"
  deleted="$(git -C "$repo" diff --name-only --diff-filter=D "$from" "$to" -- \
      "${install_rel:-.}" ":(exclude)${scope}docs" ":(exclude)${scope}.sumela" 2>/dev/null)"
  [ -n "$changed$deleted" ] || return 0

  _sumela_qdrant_up || { echo "sumela: code_chunks sync skipped (Qdrant not reachable)"; return 0; }

  local log="$install/.sumela/.memory-sync.log"
  local marker="$install/.sumela/.code-chunks-synced"

  # PRUNE removed code files (cheap) — always, in the background.
  if [ -n "$deleted" ]; then
    echo "sumela: $(printf '%s\n' "$deleted" | grep -c .) code file(s) removed in this pull — pruning Qdrant code_chunks orphans in background"
    ( cd "$install" || exit 0
      echo "===== code-sync(prune) @ $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) ====="
      _sumela_delete_orphans "$install" code_chunks file_path path "$deleted"
    ) >>"$log" 2>&1 </dev/null &
  fi

  # RE-EMBED (heavy) — only when code was added/modified.
  [ -n "$changed" ] || return 0
  local do_ingest=false
  if [ -n "${SUMELA_PULL_CODE_REINGEST:-}" ]; then
    do_ingest=true                                          # power user: always
  else
    local threshold="${SUMELA_CODE_REINGEST_DAYS:-14}" now last days
    now="$(date +%s 2>/dev/null || echo 0)"
    if [ -f "$marker" ]; then
      last="$(tr -dc '0-9' <"$marker" 2>/dev/null)"; [ -n "$last" ] || last=0
      days=$(( (now - last) / 86400 ))
    else
      days=-1                                               # never ingested
    fi
    if [ "$days" -lt 0 ] || [ "$days" -ge "$threshold" ]; then
      local since; [ "$days" -lt 0 ] && since="has never been built" || since="hasn't refreshed in ${days}d"
      if [ -t 1 ] && [ -r /dev/tty ]; then
        # Interactive pull -> ASK (default No, 30s timeout). Briefly pauses the pull.
        printf 'sumela: Qdrant code_chunks (semantic code search) %s and code changed in this pull.\n        Re-embed the whole source tree now? It can be slow. [y/N] ' "$since" >/dev/tty
        local ans=""; read -t 30 -r ans </dev/tty 2>/dev/null || ans=""
        case "$ans" in
          y|Y|yes|YES) do_ingest=true ;;
          *) echo "sumela: code_chunks refresh skipped — run later: python3 .sumela/memory-plugins/qdrant-session-memory/scripts/ingest-code-to-qdrant.py (or export SUMELA_PULL_CODE_REINGEST=1)" >/dev/tty ;;
        esac
      else
        # Non-interactive (CI / scripted / IDE) -> notice only; never block or prompt.
        echo "sumela: Qdrant code_chunks ${since}; refresh with 'python3 .sumela/memory-plugins/qdrant-session-memory/scripts/ingest-code-to-qdrant.py' or set SUMELA_PULL_CODE_REINGEST=1."
      fi
    fi
    # under threshold -> stay silent
  fi
  [ "$do_ingest" = true ] || return 0

  echo "sumela: re-embedding code into Qdrant code_chunks in background (log: .sumela/.memory-sync.log)"
  ( cd "$install" || exit 0
    echo "===== code-sync(ingest) @ $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) ====="
    if python3 "$ingest"; then date +%s >"$marker" 2>/dev/null; else echo "WARN: code ingest failed"; fi
    echo "===== code-sync: done ====="
  ) >>"$log" 2>&1 </dev/null &
  return 0
}
