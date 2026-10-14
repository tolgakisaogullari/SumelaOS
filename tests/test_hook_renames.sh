#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/test_hook_renames.sh — the pull-time sync diffs see a MOVE as delete + add.
#
# git detects renames by default (diff.renames), and a moved file is then ONE `R`
# entry, which neither --diff-filter=AM nor --diff-filter=D selects. Before v0.20.0 a
# moved wiki page or code file therefore kept its OLD path's Qdrant points forever (no
# prune), and the move alone never ingested the NEW path; a moved session summary was
# never ingested at its new path. Every diff in .sumela/git-hooks/_lib.sh now runs with
# --no-renames.
#
# The REAL sync functions run against a throwaway repo whose install holds empty
# plugin scripts. `python3` and `curl` are stubs on PATH (as
# tests/test_setup_memory_graph_gate.sh stubs graphify): python3 records every call and
# the contents of a --changed-file list, curl reports Qdrant as up. So nothing touches
# Qdrant, Ollama or the network. Each case waits for the functions' background jobs
# before it asserts.
#
# Each stub call writes its record to a file of its own. sumela_code_sync runs its
# prune and its ingest as two background jobs at once, and two stubs appending to one
# shared file can interleave their writes under CPU load: a record split across lines
# made this suite fail on a busy runner although _lib.sh was right.
#
# Dependency-free (bash 3.2 + git). Run from anywhere:  bash tests/test_hook_renames.sh
# Exit 0 = all assertions passed, 1 = a failure (printed above).
# -----------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/.sumela/git-hooks/_lib.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB is missing"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0 FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

# Hermetic: a developer's exported opt-outs and overrides (or a git hook's GIT_DIR, when
# this runs from one) must not change the outcome.
for v in $(env | LC_ALL=C sed -n 's/^\(SUMELA_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset WIKI_PATH QDRANT_HOST QDRANT_PORT GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# --- stubs: python3 records its arguments; curl says Qdrant is up ----------------------
STUBS="$WORK/bin"
mkdir -p "$STUBS"
CALLS="$WORK/python3-calls.tsv"; : > "$CALLS"     # the last run_sync's calls, gathered
CALLS_DIR="$WORK/python3-calls"; mkdir -p "$CALLS_DIR"   # one file per stub call
export HOOK_TEST_CALLS_DIR="$CALLS_DIR" HOOK_TEST_EXTRA_DIRS=""
cat > "$STUBS/python3" <<'STUB'
#!/usr/bin/env bash
# One file per call, never a shared append (see the header). Its first line holds the
# arguments, TAB-separated; a --changed-file list is copied in as CHANGED<TAB><path>
# lines (the hook deletes the list when its background job ends).
rec="$(mktemp "$HOOK_TEST_CALLS_DIR/call.XXXXXX")" || exit 1
{ first=1; for a in "$@"; do
    if [ "$first" = 1 ]; then printf '%s' "$a"; first=0; else printf '\t%s' "$a"; fi
  done; printf '\n'
  prev=""
  for a in "$@"; do
    if [ "$prev" = "--changed-file" ] && [ -f "$a" ]; then
      while IFS= read -r line || [ -n "$line" ]; do printf 'CHANGED\t%s\n' "$line"; done < "$a"
    fi
    prev="$a"
  done; } > "$rec"
# The extra-ingest-dirs resolver prints the configured dirs, one per line.
case "${1:-}" in *resolve-ingest-dirs.py) [ -n "$HOOK_TEST_EXTRA_DIRS" ] && printf '%s\n' "$HOOK_TEST_EXTRA_DIRS" ;; esac
exit 0
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBS/curl"
chmod +x "$STUBS/python3" "$STUBS/curl"

# --- fixture: an install at the repo root, with the REAL _lib.sh -----------------------
PROJ="$WORK/proj"
PLUG="$PROJ/.sumela/memory-plugins/qdrant-session-memory/scripts"
WIKI="docs/second-brain/wiki"
mkdir -p "$PROJ/.sumela/git-hooks" "$PLUG" "$PROJ/$WIKI/concepts" "$PROJ/$WIKI/session-summaries" \
         "$PROJ/src" "$PROJ/notes" "$WORK/nohooks"
cp "$LIB" "$PROJ/.sumela/git-hooks/_lib.sh"
for s in session-ingest.py ingest-wiki-to-qdrant.py ingest-code-to-qdrant.py delete-from-qdrant.py; do
  : > "$PLUG/$s"
done
git -c init.defaultBranch=main -C "$PROJ" init -q
# Repo-local config wins over the developer's global one: rename detection ON (git's
# default, and the case under test), no signing, no inherited hooks.
git -C "$PROJ" config user.email test@example.com
git -C "$PROJ" config user.name  Test
git -C "$PROJ" config commit.gpgsign false
git -C "$PROJ" config core.hooksPath "$WORK/nohooks"
git -C "$PROJ" config diff.renames true

printf '# Retry policy\n\nBack off exponentially; cap at five attempts.\n' > "$PROJ/$WIKI/concepts/retry-policy.md"
printf -- '---\nsession_date: 2026-01-05\n---\n# Session\n\nDecided the retry cap.\n' \
  > "$PROJ/$WIKI/session-summaries/2026-01-05-retry-cap.md"
printf 'def backoff(n):\n    return min(2 ** n, 30)\n' > "$PROJ/src/old_name.py"
printf 'def keep():\n    return 1\n' > "$PROJ/src/keep.py"
printf '# Runbook\n\nRestart the worker, then check the queue depth.\n' > "$PROJ/notes/runbook.md"
git -C "$PROJ" add -A && git -C "$PROJ" commit -qm "c0: initial"
C0="$(git -C "$PROJ" rev-parse HEAD)"

move_commit() {  # $1 = old path, $2 = new path → prints the new commit
  mkdir -p "$PROJ/$(dirname "$2")"
  git -C "$PROJ" mv "$1" "$2" && git -C "$PROJ" commit -qm "move $1" && git -C "$PROJ" rev-parse HEAD
}
C1="$(move_commit "$WIKI/concepts/retry-policy.md" "$WIKI/patterns/retry-policy.md")"
C2="$(move_commit "src/old_name.py" "src/new_name.py")"
C3="$(move_commit "$WIKI/session-summaries/2026-01-05-retry-cap.md" "$WIKI/session-summaries/2026/2026-01-05-retry-cap.md")"
C4="$(move_commit "notes/runbook.md" "notes/ops/runbook.md")"

# run_sync <function> <from> <to> → its stdout+stderr, after its background jobs finish;
# their stub calls are then gathered into $CALLS. A fresh subshell per case: the stubs
# lead PATH, and _lib.sh derives the install root from its own location, so every log
# and path stays inside the fixture.
run_sync() {
  local f
  rm -f "$CALLS_DIR"/call.*
  ( cd "$PROJ" || exit 1
    PATH="$STUBS:$PATH"
    . "$PROJ/.sumela/git-hooks/_lib.sh"
    "$1" "$2" "$3"
    wait ) 2>&1
  # `wait` has returned, so every stub call has written and closed its file.
  : > "$CALLS"
  for f in "$CALLS_DIR"/call.*; do [ -f "$f" ] && cat "$f" >> "$CALLS"; done
  return 0
}

# has_call <substring>... → 0 when ONE recorded call line contains every substring.
has_call() {
  awk -v n="$#" 'BEGIN { for (i = 1; i < ARGC; i++) want[i] = ARGV[i]; ARGC = 1 }
    { hit = 1; for (i = 1; i <= n; i++) if (index($0, want[i]) == 0) { hit = 0; break }
      if (hit) { found = 1; exit } }
    END { exit found ? 0 : 1 }' "$@" < "$CALLS"
}
TAB="$(printf '\t')"
show_calls() { sed 's/^/        | /' "$CALLS"; }

echo "Pull-time sync: a moved file is a delete plus an add"

echo "== precondition: git reports every fixture move as a rename =="
for r in "$C0 $C1" "$C1 $C2" "$C2 $C3" "$C3 $C4"; do
  # shellcheck disable=SC2086  # two SHAs, split on purpose
  st="$(git -C "$PROJ" diff --name-status $r | cut -c1)"
  if [ "$st" = "R" ]; then ok "rename detected for $(git -C "$PROJ" log -1 --format=%s ${r#* })"
  else bad "the fixture no longer exercises rename detection ($r gave: $st)"; fi
done

echo "== t_move_within_wiki_prunes_old_and_ingests_new =="
out="$(run_sync sumela_wiki_sync "$C0" "$C1")"
if has_call "delete-from-qdrant.py${TAB}--collection${TAB}wiki_pages${TAB}--key${TAB}page_path${TAB}--value${TAB}$WIKI/concepts/retry-policy.md"; then
  ok "the old page path is pruned from wiki_pages"
else bad "the old page path is pruned from wiki_pages"; show_calls; fi
if has_call "ingest-wiki-to-qdrant.py"; then ok "the wiki ingest runs for the new page path"
else bad "the wiki ingest runs for the new page path"; show_calls; fi
if has_call "delete-from-qdrant.py" "--value${TAB}$WIKI/patterns/retry-policy.md"; then
  bad "the new page path must not be pruned"; show_calls
else ok "the new page path is not pruned"; fi
case "$out" in *"(1 updated, 1 removed)"*) ok "the pull notice counts 1 updated, 1 removed" ;;
  *) bad "the pull notice counts 1 updated, 1 removed (got: $out)" ;; esac

echo "== t_move_in_extra_ingest_dir_prunes_old_and_ingests_new =="
HOOK_TEST_EXTRA_DIRS="notes"
: > "$PLUG/resolve-ingest-dirs.py"
out="$(run_sync sumela_wiki_sync "$C3" "$C4")"
if has_call "delete-from-qdrant.py${TAB}--collection${TAB}wiki_pages${TAB}--key${TAB}page_path${TAB}--value${TAB}notes/runbook.md"; then
  ok "the old path in an extra ingest dir is pruned"
else bad "the old path in an extra ingest dir is pruned"; show_calls; fi
if has_call "ingest-wiki-to-qdrant.py"; then ok "the wiki ingest runs for the extra dir's new path"
else bad "the wiki ingest runs for the extra dir's new path"; show_calls; fi
rm -f "$PLUG/resolve-ingest-dirs.py"; HOOK_TEST_EXTRA_DIRS=""

echo "== t_move_in_code_prunes_old_chunks =="
out="$(run_sync sumela_code_sync "$C1" "$C2")"
if has_call "delete-from-qdrant.py${TAB}--collection${TAB}code_chunks${TAB}--key${TAB}file_path${TAB}--value${TAB}src/old_name.py"; then
  ok "the old code path's chunks are pruned from code_chunks"
else bad "the old code path's chunks are pruned from code_chunks"; show_calls; fi
if has_call "ingest-code-to-qdrant.py${TAB}--changed-file"; then ok "the incremental code ingest runs"
else bad "the incremental code ingest runs"; show_calls; fi
changed="$(LC_ALL=C sed -n "s/^CHANGED${TAB}//p" "$CALLS")"
if [ "$changed" = "src/new_name.py" ]; then ok "the changed list is exactly the new path"
else bad "the changed list is exactly the new path (got: $(printf '%s' "$changed" | tr '\n' ' '))"; fi

echo "== t_move_summary_ingests_new_path =="
out="$(run_sync sumela_memory_sync "$C2" "$C3")"
if has_call "session-ingest.py${TAB}" "/$WIKI/session-summaries/2026/2026-01-05-retry-cap.md"; then
  ok "a moved session summary is ingested at its new path"
else bad "a moved session summary is ingested at its new path"; show_calls; fi
if has_call "delete-from-qdrant.py"; then bad "chat_history is never pruned (a delete ran)"; show_calls
else ok "chat_history is never pruned"; fi

echo "== t_every_name_only_diff_in_lib_has_no_renames =="
# The graph-sync diff has no --diff-filter, so a rename cannot change its answer and no
# fixture can tell; this pins the rule _lib.sh states for every name-only diff, which
# also covers the diffs later releases add to the file.
missing="$(LC_ALL=C awk '{ sub(/\r$/, "") } /^[[:space:]]*#/ { next }
  /[[:space:]]diff[[:space:]]/ && /--name-only/ && !/--no-renames/ { printf "        line %d: %s\n", NR, $0 }' "$LIB")"
total="$(LC_ALL=C awk '/^[[:space:]]*#/ { next } /[[:space:]]diff[[:space:]]/ && /--name-only/ { n++ } END { print n + 0 }' "$LIB")"
if [ -z "$missing" ] && [ "$total" -ge 8 ]; then
  ok "all $total name-only diffs in _lib.sh run with --no-renames"
else
  bad "every name-only diff in _lib.sh runs with --no-renames (found $total; without it:)"
  [ -n "$missing" ] && printf '%s\n' "$missing"
fi

echo ""
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
