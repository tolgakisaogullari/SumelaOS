#!/usr/bin/env bash
# _dispatch.sh — SumelaOS multi-install hook dispatcher (monorepo support).
#
# `core.hooksPath` can hold only ONE path, so when more than one SumelaOS install
# shares a single git repo, setup copies THIS file to
#     <git-root>/.sumela-hooks/{pre-commit,post-merge,post-checkout}
# and points core.hooksPath at .sumela-hooks. On each git event the dispatcher runs
# the same-named hook in every install listed in .sumela-hooks/installs (one
# repo-relative path per line; "." = an install at the repo root), forwarding all
# args. For pre-commit it fails if ANY install's hook fails (so no install's checks
# can be silently skipped); the memory hooks are best-effort and already self-gate.
#
# This script keys off its own basename, so the three copies share one body.
set -uo pipefail

hook="$(basename "$0")"
dispdir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
root="$(cd "$dispdir/.." 2>/dev/null && pwd)" || exit 0   # .sumela-hooks/ lives at the git root
reg="$dispdir/installs"
[ -f "$reg" ] || exit 0

rc=0
while IFS= read -r inst || [ -n "$inst" ]; do
  inst="${inst%%#*}"                                   # strip trailing comments
  inst="$(printf '%s' "$inst" | tr -d '[:space:]')"    # trim whitespace
  [ -n "$inst" ] || continue
  case "$inst" in
    .) h="$root/.sumela/git-hooks/$hook" ;;            # install at the repo root
    *) h="$root/$inst/.sumela/git-hooks/$hook" ;;      # install in a subdir
  esac
  [ -x "$h" ] || continue
  "$h" "$@" || rc=1
done < "$reg"
exit "$rc"
