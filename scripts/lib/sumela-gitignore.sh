# shellcheck shell=bash
# sumela-gitignore.sh — emit the SumelaOS-managed .gitignore patterns.
#
# The patterns themselves live in the language-agnostic single source
# `sumela-gitignore.list` (next to this file); this just reads it (stripping comments
# and blanks). Sourced by scripts/setup.sh (seed on install) and scripts/update.sh
# (reconcile on upgrade); the PowerShell setup/update read the same .list directly.
# The bug this fixes: a new managed entry reaching fresh installs but silently missing
# on the update path, because the list used to live only inside setup.sh.

# Capture this file's directory AT SOURCE TIME — BASH_SOURCE[0] is only reliably this
# file here at the top level (inside the function it may resolve to the caller / $0).
_SUMELA_GI_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

sumela_gitignore_lines() {
  local list="${_SUMELA_GI_DIR:-.}/sumela-gitignore.list"
  [ -f "$list" ] || return 0
  # Strip CRLF defensively (a contributor may save the list on Windows) so the
  # emitted pattern matches a LF .gitignore exactly under grep -qxF.
  tr -d '\r' < "$list" | grep -vE '^[[:space:]]*(#|$)'
}
