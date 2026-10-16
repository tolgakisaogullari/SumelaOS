#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/test_env_tables.sh — the configuration surface stays documented and pinned.
#
#   t_every_env_var_documented         every SUMELA_* variable that code under .sumela/ or
#                                      scripts/ reads has a row in the ONE central table
#                                      (.sumela/git-hooks/README.md, "Configuration"), and
#                                      every row has a Scope of hook, setup, plugin or tool
#   t_hook_vars_in_lib_header          every SUMELA_* variable a hook reads is also in the
#                                      .sumela/git-hooks/_lib.sh header list
#   t_gitignore_list_has_runtime_dirs  .sumela/.wiki/, .sumela/.upgrade/ and .sumela/.handoff/
#                                      are managed gitignore entries (the single-source list
#                                      AND this repository's .gitignore), and a .gitignore
#                                      built from the list, as setup seeds it, ignores them
#   t_gitattributes_pins_lf            a script, a hook and a template resolve to eol=lf, and
#                                      no tracked file under an eol=lf rule is stored with
#                                      CRLF (so `git add --renormalize .` stages nothing)
#   t_self_test                        the scanner reports exactly the drift planted in a
#                                      synthetic tree
#
# What counts as a read: a SUMELA_* name in a CODE file, meaning *.sh *.bash *.ps1 *.psm1
# *.py *.js *.cjs *.mjs *.ts *.cmd *.bat, or any file whose first two bytes are `#!` (the
# extension-less hooks). Markdown is documentation, not a read. A name glued to a word
# character (`_SUMELA_GI_DIR`) is a private shell variable, and a name ending in `_` is a
# family mention in prose (`SUMELA_EMBED_*`); neither counts. Files come from
# `git ls-files --cached --others --exclude-standard`: ignored local output is skipped,
# and a new file that is not committed yet is scanned.
#
# Dependency-free (bash 3.2 + git + coreutils). Run from anywhere:
#   bash tests/test_env_tables.sh
# Exit 0 = all assertions passed, 1 = a failure (printed above).
# -----------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
README="$REPO_ROOT/.sumela/git-hooks/README.md"
LIB="$REPO_ROOT/.sumela/git-hooks/_lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE   # when run from inside a git hook

PASS=0 FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
indent() { sed 's/^/        /'; }
TAB="$(printf '\t')"

if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: $REPO_ROOT is not a git work tree (these checks read git's file list and attributes)"
  exit 1
fi

# Internal plumbing that nobody sets by hand: exempt from both lists. Anything else a
# script reads needs a central-table row (and, when a hook reads it, a _lib.sh header line).
#   SUMELA_EMPTY_TREE      _lib.sh: git's empty-tree object id
#   SUMELA_INSTALL_ROOT    _lib.sh: the install root, derived from the hook's own path
#   SUMELA_RENDER_TRACE    setup.sh: template-render debug trace
#   SUMELA_PY              setup.sh: python probe cache
#   SUMELA_UPDATER_SCHEMA  the updater's provenance-record schema (v0.20.0+)
#   SUMELA_MIGRATE_SRC     the migration runner's source clone (v0.20.0+)
#   SUMELA_MIGRATE_ROOT    the migration runner's install root (v0.20.0+)
# Planned plumbing, registered ahead of the tasks whose exact code the Release-1 plan
# carries: an inline assignment that hands one value to the awk or python3 child it
# starts (`SUMELA_X="$v" awk '... ENVIRON["SUMELA_X"] ...'`). Nobody sets them by hand.
#   SUMELA_PATH SUMELA_DESC        R1-07: scripts/lib/sumela-registry.sh (description rewrite)
#   SUMELA_H SUMELA_L SUMELA_B     R1-19: the wiki tool's lib/wiki-task.sh (section writes)
#   SUMELA_RULE                    R1-30: scripts/sumela-claude-settings.sh (the allow rule)
INTERNAL=" SUMELA_EMPTY_TREE SUMELA_INSTALL_ROOT SUMELA_RENDER_TRACE SUMELA_PY \
SUMELA_UPDATER_SCHEMA SUMELA_MIGRATE_SRC SUMELA_MIGRATE_ROOT \
SUMELA_PATH SUMELA_DESC SUMELA_H SUMELA_L SUMELA_B SUMELA_RULE "

is_code() {  # $1 = file → 0 for a code file (see the header)
  case "$1" in
    *.sh|*.bash|*.ps1|*.psm1|*.py|*.js|*.cjs|*.mjs|*.ts|*.cmd|*.bat) return 0 ;;
  esac
  [ "$(head -c 2 "$1" 2>/dev/null)" = '#!' ]
}

# names_in <file|-> → the SUMELA_* names it mentions, one per line, sorted, unique.
names_in() {
  LC_ALL=C grep -oE '(^|[^A-Za-z0-9_])SUMELA_[A-Z0-9_]+' "$@" 2>/dev/null \
    | LC_ALL=C sed -e 's/^[^A-Z]//' | LC_ALL=C grep -v '_$' | LC_ALL=C sort -u
}

# reads <root> <pathspec>... → "NAME<TAB>path" for every name a code file mentions.
reads() {
  local root="$1" f v; shift
  git -C "$root" -c core.quotePath=false ls-files -z --cached --others --exclude-standard -- "$@" |
  while IFS= read -r -d '' f; do
    [ -f "$root/$f" ] && is_code "$root/$f" || continue
    names_in "$root/$f" | while IFS= read -r v; do printf '%s\t%s\n' "$v" "$f"; done
  done | LC_ALL=C sort -u
}

# table_names <README> → the SUMELA_* names in the FIRST cell of each row of the table
# under "## Configuration". Mentions in other cells or other sections document nothing.
table_names() {
  LC_ALL=C awk '{ sub(/\r$/, "") }
    /^## / { sec = ($0 ~ /^## Configuration/); next }
    sec && /^\|/ { n = split($0, cell, "|"); first = cell[2]
      while (match(first, /`SUMELA_[A-Z0-9_]+`/)) {
        print substr(first, RSTART + 1, RLENGTH - 2); first = substr(first, RSTART + RLENGTH) } }' "$1" \
    | LC_ALL=C sort -u
}

# bad_scopes <README> → rows of the Configuration table whose Scope cell is not a comma
# list of hook|setup|plugin|tool, plus a line when the header row has no Scope column.
bad_scopes() {
  LC_ALL=C awk '{ sub(/\r$/, "") }
    function trim(s) { gsub(/^ +| +$/, "", s); return s }
    /^## / { sec = ($0 ~ /^## Configuration/); next }
    sec && /^\|/ {
      n = split($0, cell, "|")
      if (!seen_header) { seen_header = 1
        if (trim(cell[3]) != "Scope") print "header row: second column is \"" trim(cell[3]) "\", not \"Scope\""
        next }
      if ($0 ~ /^\|[-:| ]+\|$/) next
      s = trim(cell[3]); m = split(s, part, ",")
      okrow = (m > 0)
      for (i = 1; i <= m; i++) if (trim(part[i]) !~ /^(hook|setup|plugin|tool)$/) okrow = 0
      if (!okrow) print trim(cell[2]) ": scope \"" s "\"" }
    END { if (!seen_header) print "no table under ## Configuration" }' "$1"
}

# header_names <_lib.sh> → the SUMELA_* names in its leading comment block.
header_names() {
  LC_ALL=C awk '{ sub(/\r$/, "") } /^#/ { print; next } { exit }' "$1" | names_in -
}

# undocumented <reads> <documented names> → "NAME (read in: a, b)" per name that is
# read, not internal and not documented.
undocumented() {
  local v
  printf '%s\n' "$1" | cut -f1 | LC_ALL=C sort -u | while IFS= read -r v; do
    [ -n "$v" ] || continue
    case "$INTERNAL" in *" $v "*) continue ;; esac
    printf '%s\n' "$2" | grep -qxF "$v" && continue
    printf '%s (read in: %s)\n' "$v" \
      "$(printf '%s\n' "$1" | LC_ALL=C awk -F'\t' -v v="$v" '$1 == v { printf "%s%s", sep, $2; sep = ", " }')"
  done
}

echo "Configuration surface: env-var tables, gitignore entries, eol pins"

echo "== t_every_env_var_documented =="
READS="$(reads "$REPO_ROOT" .sumela scripts)"
TABLE="$(table_names "$README")"
nreads="$(printf '%s\n' "$READS" | cut -f1 | LC_ALL=C sort -u | grep -c .)"
if printf '%s\n' "$READS" | grep -qxF "SUMELA_DISABLE_SECRET_SCAN${TAB}.sumela/git-hooks/pre-commit"; then
  ok "the scanner reads the extension-less hooks ($nreads SUMELA_* names read under .sumela/ and scripts/)"
else
  bad "the scanner reads the extension-less hooks (SUMELA_DISABLE_SECRET_SCAN not found in .sumela/git-hooks/pre-commit)"
fi
missing="$(undocumented "$READS" "$TABLE")"
if [ -z "$missing" ]; then
  ok "every SUMELA_* variable read under .sumela/ and scripts/ has a row in the central table"
else
  bad "SUMELA_* variables read but missing from the Configuration table in .sumela/git-hooks/README.md"
  printf '%s\n' "$missing" | indent
  echo "        Add a row (with its Scope), or, for plumbing nobody sets by hand, extend INTERNAL here."
fi
scopes="$(bad_scopes "$README")"
if [ -z "$scopes" ]; then ok "every central-table row has a Scope of hook, setup, plugin or tool"
else bad "every central-table row has a Scope of hook, setup, plugin or tool"; printf '%s\n' "$scopes" | indent; fi

echo "== t_hook_vars_in_lib_header =="
HOOK_READS="$(reads "$REPO_ROOT" .sumela/git-hooks)"
HEADER="$(header_names "$LIB")"
missing="$(undocumented "$HOOK_READS" "$HEADER")"
if [ -n "$HEADER" ] && [ -z "$missing" ]; then
  ok "every SUMELA_* variable a hook reads is in the _lib.sh header ($(printf '%s\n' "$HEADER" | grep -c .) listed)"
else
  bad "SUMELA_* variables a hook reads but the _lib.sh header list does not name"
  printf '%s\n' "${missing:-(the header lists no SUMELA_* name at all)}" | indent
fi

echo "== t_gitignore_list_has_runtime_dirs =="
RUNTIME_DIRS=".sumela/.wiki/ .sumela/.upgrade/ .sumela/.handoff/"
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/sumela-gitignore.sh"
LIST_LINES="$(sumela_gitignore_lines)"
GI="$WORK/gi"; mkdir -p "$GI"; git -c init.defaultBranch=main -C "$GI" init -q
printf '%s\n' "$LIST_LINES" > "$GI/.gitignore"
for d in $RUNTIME_DIRS; do
  if printf '%s\n' "$LIST_LINES" | grep -qxF "$d"; then ok "$d is in scripts/lib/sumela-gitignore.list"
  else bad "$d is in scripts/lib/sumela-gitignore.list"; fi
  if tr -d '\r' < "$REPO_ROOT/.gitignore" | grep -qxF "$d"; then ok "$d is in this repository's .gitignore"
  else bad "$d is in this repository's .gitignore"; fi
  if git -C "$GI" check-ignore -q "${d}x"; then ok "a .gitignore seeded from the list ignores ${d}x"
  else bad "a .gitignore seeded from the list ignores ${d}x"; fi
done
if git -C "$GI" check-ignore -q ".sumela/skills/x/SKILL.md"; then
  bad "the runtime entries must not ignore tracked framework files (.sumela/skills/x/SKILL.md is ignored)"
else ok "the seeded .gitignore still tracks .sumela/skills/"; fi

echo "== t_gitattributes_pins_lf =="
for p in scripts/setup.sh .sumela/git-hooks/post-merge docs/second-brain/template/wiki/_SCHEMA.md; do
  if [ ! -f "$REPO_ROOT/$p" ]; then bad "sample $p exists (pick another script, hook or template)"; continue; fi
  eol="$(git -C "$REPO_ROOT" check-attr eol -- "$p" | LC_ALL=C sed 's/.*: eol: //')"
  if [ "$eol" = "lf" ]; then ok "git check-attr eol $p → lf"
  else bad "git check-attr eol $p → lf (got: $eol)"; fi
done
# `git add --renormalize .` would restage any file an eol=lf rule covers whose blob holds
# CRLF (i/crlf, i/mixed); a binary blob (i/-text) under a text rule is wrong too.
# `ls-files --eol` rows are "i/<x> w/<y> attr/<attrs><TAB><path>": match the attributes
# before the TAB only, so a path containing "eol=lf" cannot count.
EOLS="$(git -C "$REPO_ROOT" -c core.quotePath=false ls-files --eol)"
crlf="$(printf '%s\n' "$EOLS" | LC_ALL=C awk '{ split($0, part, "\t") }
  index(part[1], "eol=lf") && $1 != "i/lf" && $1 != "i/none"')"
pinned="$(printf '%s\n' "$EOLS" | LC_ALL=C awk '{ split($0, part, "\t") } index(part[1], "eol=lf") { n++ }
  END { print n + 0 }')"
if [ -z "$crlf" ] && [ "$pinned" -gt 0 ]; then
  ok "all $pinned tracked files under an eol=lf rule are stored with LF (renormalize stages nothing)"
else
  bad "tracked files under an eol=lf rule are stored with LF ($pinned pinned)"
  printf '%s\n' "${crlf:-(no tracked file is under an eol=lf rule)}" | indent
fi

echo "== t_self_test =="
# A synthetic install with planted drift. The scanner must report exactly the planted
# names: proof that a regression in it cannot pass silently above.
ST="$WORK/self"
mkdir -p "$ST/.sumela/git-hooks" "$ST/scripts"
git -c init.defaultBranch=main -C "$ST" init -q
printf 'scripts/ignored.sh\n' > "$ST/.gitignore"
cat > "$ST/.sumela/git-hooks/_lib.sh" <<'EOF'
# shellcheck shell=bash
# Opt out: export SUMELA_HOOK_DOC=1   (every SUMELA_* knob is in the README)

: "${SUMELA_HOOK_DOC:-}${SUMELA_HOOK_UNDOC:-}${SUMELA_EMPTY_TREE:-}"
EOF
printf '#!/usr/bin/env bash\n: "${SUMELA_HOOK_DOC:-}"\n' > "$ST/.sumela/git-hooks/pre-commit"
cat > "$ST/.sumela/git-hooks/README.md" <<'EOF'
# Hooks

## Configuration (environment variables)

| Var | Scope | Default | Purpose |
|---|---|---|---|
| `SUMELA_HOOK_DOC` | hook | (unset) | documented |
| `SUMELA_TOOL_DOC` | tool, hook | (unset) | mentions `SUMELA_IN_PURPOSE_ONLY`, which documents nothing |
| `SUMELA_BAD_SCOPE` | cli | (unset) | an unknown scope |

## Elsewhere

| `SUMELA_OUTSIDE_SECTION` | tool | (unset) | a row outside the section documents nothing |
EOF
cat > "$ST/scripts/tool.py" <<'EOF'
import os
os.getenv("SUMELA_TOOL_DOC"); os.getenv("SUMELA_IN_PURPOSE_ONLY"); os.getenv("SUMELA_OUTSIDE_SECTION")
_SUMELA_PRIVATE = 1  # a private name, and a family mention: SUMELA_FAMILY_*
EOF
printf '#!/bin/sh\necho "$SUMELA_SHEBANG_READ"\n' > "$ST/scripts/run"
printf 'Set SUMELA_DOC_ONLY in prose.\n' > "$ST/scripts/notes.md"
printf 'SUMELA_DATA_ONLY\n' > "$ST/scripts/data.txt"
printf 'echo "$SUMELA_IGNORED_FILE"\n' > "$ST/scripts/ignored.sh"
got="$(undocumented "$(reads "$ST" .sumela scripts)" "$(table_names "$ST/.sumela/git-hooks/README.md")" | cut -d' ' -f1 | tr '\n' ' ')"
want="SUMELA_HOOK_UNDOC SUMELA_IN_PURPOSE_ONLY SUMELA_OUTSIDE_SECTION SUMELA_SHEBANG_READ "
if [ "$got" = "$want" ]; then ok "table check reports exactly the planted undocumented reads"
else bad "table check reports exactly the planted undocumented reads (want: $want; got: $got)"; fi
got="$(undocumented "$(reads "$ST" .sumela/git-hooks)" "$(header_names "$ST/.sumela/git-hooks/_lib.sh")" | cut -d' ' -f1 | tr '\n' ' ')"
if [ "$got" = "SUMELA_HOOK_UNDOC " ]; then ok "header check reports exactly the planted hook read"
else bad "header check reports exactly the planted hook read (want: SUMELA_HOOK_UNDOC; got: $got)"; fi
got="$(bad_scopes "$ST/.sumela/git-hooks/README.md" | tr '\n' ' ')"
if [ "$got" = '`SUMELA_BAD_SCOPE`: scope "cli" ' ]; then ok "scope check reports exactly the planted bad scope"
else bad "scope check reports exactly the planted bad scope (got: $got)"; fi

echo ""
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
