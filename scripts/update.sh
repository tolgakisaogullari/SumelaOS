#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# update.sh — refresh the SumelaOS framework CORE in an adopting project, WITHOUT
# touching the project's OVERLAY, and without ever overwriting a locally modified
# ("forked") CORE file unless you decide so (v0.20.0+).
#
# CORE (refreshed by a three-way merge, see below):
#   .sumela/sumela-prompt.md, .sumela/skills/, .sumela/git-hooks/,
#   universal rules (engineering_philosophy, identity_and_behavior,
#   architecture_patterns, audit_and_output, security_protocol,
#   git_workflow_mandatory_review_protocol, self_improvement_protocol),
#   docs/second-brain/template/ (incl. template/wiki/_SCHEMA.md),
#   .sumela/memory-plugins/<plugin>/ (only plugins already installed),
#   scripts/*, .sumela/VERSION
#   Plus a DERIVED file: the live docs/second-brain/wiki/_SCHEMA.md is merged against the
#   template like any CORE file, so your own edits to it survive.
#
# OVERLAY (never touched): AGENTS.md, .sumela/RULE_REGISTRY.md,
#   .sumela/SKILL_REGISTRY.md, stack rules (backend/frontend/mobile_standards,
#   operational_excellence_maintenance), docs/second-brain/wiki/* (except the
#   derived _SCHEMA.md above),
#   .sumela/local.md, .gitignore, .gitattributes, IDE pointers, CODEOWNERS, CI workflow.
#
# How each CORE file is decided. Three trees are read from git, never from a working tree, and a
# tree that cannot be read in full is never used:
#   THEIRS  the new release: the source's release tag v<version>;
#   BASE    upstream at the installed version: the provenance record's upstream_commit
#           (.sumela/.last-update.json), else the tag v<installed>. It counts only when its own
#           .sumela/VERSION is the installed version;
#   LOCAL   your file. Right after an older updater overwrote files and stamped VERSION without
#           a commit (the "self-heal"), HEAD's copy is LOCAL wherever the working copy is a version
#           upstream committed (what that updater wrote). A working copy with changes of yours stays
#           LOCAL; where it may also hold that updater's write, its row waits for your decision, with
#           HEAD's copy in .sumela/.upgrade/<path>.head, in this run and every later one.
# A line-ending difference never counts as a change.
#   add, readd   LOCAL is absent (readd: you deleted it)         -> upstream's file; a file you
#                                                                    deleted comes back only on your
#                                                                    yes in a terminal
#   apply        LOCAL = BASE: nothing of yours to lose           -> upstream's file
#   keep         upstream did not change the file                 -> yours, untouched
#   merge        both changed, `git merge-file` is clean and the release's merge pins
#                (scripts/lib/sumela-merge-pins/) hold             -> the merge: your lines stay
#   conflict     the changes overlap, or the merge breaks a pin   -> yours; the merge is in
#                                                                    .sumela/.upgrade/<path>.merge
#   collision    yours sits at a path upstream newly ships        -> yours; upstream's copy is in
#                                                                    .sumela/.upgrade/<path>.theirs
#   review       no valid BASE, a binary file, an ambiguous base  -> as for collision
#                tag, a merge error, a working copy changed after an older updater wrote it
#   remove, keep-removed, carry   a path scripts/lib/sumela-removed-files.list retires: removed
#                only when LOCAL = BASE, otherwise kept; when a successor is named, your hunks go
#                to .sumela/.upgrade/<path>.carry, to move into the successor
#   schema       the live _SCHEMA.md, when it is still the installed template: the new template
#   floor        an updater (scripts/update.sh, update.ps1) older than v0.20.0 is never installed
# conflict, collision, review and carry rows wait for YOUR decision. In a terminal the updater
# asks; --yes and an unanswered prompt decide nothing, and never take upstream's copy of a fork.
# VERSION is stamped only when no row waits; until then the record says partial_upgrade and a
# plain re-run resumes. Installed and merged files take the release's git mode (a merged hook
# stays executable), and a file already identical to the release's regains its executable bit;
# kept files keep yours.
#
# Usage:
#   bash scripts/update.sh                 # clone the newest release tag from --repo and refresh
#   bash scripts/update.sh --source <dir>  # use a local framework git checkout (no clone)
#   bash scripts/update.sh --dry-run       # show what would happen; write nothing anywhere
#   bash scripts/update.sh --yes           # apply what needs no decision, without prompts
#   bash scripts/update.sh --force         # run even if versions match
#   --allow-dirty-source                   # maintainer tests only: accept a --source with
#                                          # uncommitted CORE changes (they are never installed)
#   --allow-untagged-source                # maintainer tests only: accept a --source whose HEAD
#                                          # is not a release tag (that commit is then installed)
#
# Exit: 0 updated, already current, or --dry-run;
#       1 error (usage, no install, bad, dirty, untagged or older source, clone failure, a tree
#         that cannot be read in full, a failed write);
#       3 partial upgrade: file(s) wait for a decision and VERSION is unchanged;
#       6 re-run pending: this run installed a new scripts/update.sh, which must finish the
#         upgrade (VERSION is unchanged; run the command printed last).
# -----------------------------------------------------------------------------
set -uo pipefail
# A hook's git layout is not this install's: every git call below names its repository.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_PREFIX

REPO_URL_DEFAULT="https://github.com/tolgakisaogullari/SumelaOS.git"
SOURCE_DIR=""
REPO_URL="$REPO_URL_DEFAULT"
REPO_GIVEN=false
DRY_RUN=false
ASSUME_YES=false
FORCE=false
ALLOW_DIRTY_SOURCE=false
ALLOW_UNTAGGED_SOURCE=false

need_value() { [ "$2" -ge 2 ] || { echo "$1 needs a value" >&2; exit 1; }; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) need_value "$1" $#; SOURCE_DIR="$2"; shift 2 ;;
    --repo)   need_value "$1" $#; REPO_URL="$2"; REPO_GIVEN=true; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes|-y)  ASSUME_YES=true; shift ;;
    --force)  FORCE=true; shift ;;
    --allow-dirty-source) ALLOW_DIRTY_SOURCE=true; shift ;;         # maintainer tests only [RU-I8]
    --allow-untagged-source) ALLOW_UNTAGGED_SOURCE=true; shift ;;   # maintainer tests only [RU-I6]
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
TAB="$(printf '\t')"

# The libraries come from the running updater's own release (resolved before any cd), never
# from the install or the source: their functions must match this file.
UPDATER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || UPDATER_DIR=""
UPDATER_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
if [ -z "$UPDATER_DIR" ] || [ ! -f "$UPDATER_DIR/lib/sumela-provenance.sh" ]; then
  err "Missing ${UPDATER_DIR:-<updater dir>}/lib/sumela-provenance.sh: this updater needs the library of its own release."
  err "  Run the release's own updater: bash <release clone>/scripts/update.sh --source <release clone>"
  exit 1
fi
# shellcheck source=lib/sumela-provenance.sh
. "$UPDATER_DIR/lib/sumela-provenance.sh"
command -v git >/dev/null 2>&1 || { err "git not found: the updater reads every tree with git"; exit 1; }

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

# --- The CORE file list (relative paths) -------------------------------------
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
# The top-level paths materialized from each tree (every CORE file lives under one of them).
CORE_PATHS=".sumela scripts docs/second-brain/template"
# Derived file: the LIVE docs/second-brain/wiki/_SCHEMA.md is generated from the template at
# setup. It is framework-authored schema living in the overlay zone, so it is classified like a
# CORE file with BASE and THEIRS taken from the template [RU-M12]. Only when a live copy exists.
SCHEMA_LIVE="docs/second-brain/wiki/_SCHEMA.md"
SCHEMA_SRC="docs/second-brain/template/wiki/_SCHEMA.md"
# The updater and the library it sources: applied last, so a run cut short never leaves a new
# updater beside an old library. A consumer's patched updater is merged like any other file.
UPDATER_FILES="scripts/update.ps1 scripts/lib/sumela-provenance.sh scripts/lib/sumela-provenance.ps1 scripts/update.sh"
# Every updater from v0.20.0 on writes the v2 record through these functions. An older one
# overwrites forks on an empty answer, so it is never installed (kept: updater-floor).
UPDATER_MARK_SH="sumela_record_write"
UPDATER_MARK_PS1="Write-SumelaRecord"
# Tags that sit on a later commit than their VERSION bump; used only when the source's history
# is too shallow to find the bump (see setup_ambiguity).
KNOWN_AMBIGUOUS_TAGS=" 0.6.0 0.11.0 0.12.1 0.13.0 "

# --- Working directories -------------------------------------------------------
CLONE_TMP="" WORK="" CUR_TMP=""
REC="$ROOT/.sumela/.last-update.json"
cleanup() {
  [ -n "$CUR_TMP" ] && rm -f "$CUR_TMP"
  rm -f "$REC.sumela-tmp.$$"   # the record library's temporary file, when a cut came mid-write
  [ -n "$CLONE_TMP" ] && rm -rf "$CLONE_TMP"
  [ -n "$WORK" ] && rm -rf "$WORK"
}
trap cleanup EXIT
# An explicit template: macOS mktemp ignores TMPDIR without one.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sumela-update.XXXXXX")" || { err "cannot create a temporary directory"; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { err "cannot create a temporary directory"; exit 1; }
# Every later template-less "mktemp -d" in this process, the sourced record library's included,
# lands inside $WORK, so a run cut short (a signal mid-write) leaves no directory behind.
mktemp() { if [ "$#" -eq 1 ] && [ "$1" = -d ]; then command mktemp -d "$WORK/tmp.XXXXXX"; else command mktemp "$@"; fi; }
UPG="$ROOT/.sumela/.upgrade"   # what you inspect and edit: .merge, .theirs, .carry, .pin, .head
STAGE="$WORK/upg"              # where classification writes them first (a dry run publishes nothing)
THEIRS_DIR="$WORK/theirs"
ABSENT="$WORK/absent"          # never created: LOCAL is "no file"
mkdir -p "$STAGE" || { err "cannot create $STAGE"; exit 1; }
# The running updater's bytes as they were when it started: this run may replace its own file.
cp "$UPDATER_DIR/$UPDATER_NAME" "$WORK/running-updater" || { err "cannot read the running updater"; exit 1; }

# --- Tree helpers -----------------------------------------------------------------
child_of() { case "$1" in *:) printf '%s%s' "$1" "$2" ;; *:*) printf '%s/%s' "${1%/}" "$2" ;; *) printf '%s:%s' "$1" "$2" ;; esac; }
present_paths() {  # <top> <tree-ish> <path>... -> the paths the tree has, space-separated
  local top="$1" t="$2" p out=""
  shift 2
  for p in "$@"; do git -C "$top" cat-file -e "$(child_of "$t" "$p")" 2>/dev/null && out="$out $p"; done
  printf '%s' "$out"
}
tree_list() {  # <top> <tree-ish> <list> <path>...: "<mode><TAB><path>" per file; the raw listing in <list>.z
  local top="$1" t="$2" list="$3"
  shift 3
  git -C "$top" ls-tree -r -z "$t" -- "$@" > "$list.z" || return 1
  tr '\000' '\n' < "$list.z" | LC_ALL=C awk -F '\t' '{ split($1, m, " ") } NF == 2 && m[2] == "blob" { print m[1] "\t" $2 }' > "$list"
}
verify_tree() {  # <out-dir> <list>: every listed file was written; prints the first that was not
  local m p
  while IFS="$TAB" read -r m p; do
    [ -e "$1/$p" ] || [ -L "$1/$p" ] || { printf '%s\n' "$p"; return 1; }
  done < "$2"
}
# materialize <git-dir> <tree-ish> <out-dir> <path>... -> 0 complete, 1 unknown tree-ish,
# 2 not readable in full. <out-dir>.ls lists the tree's files ("<mode><TAB><path>").
materialize() {
  local g="$1" t="$2" out="$3" present top miss
  shift 3
  # "$t", not "$t^{tree}": peeling is not parsed after a path ("HEAD:<prefix>/^{tree}" fails)
  git -C "$g" rev-parse -q --verify "$t" >/dev/null || return 1
  # From the top of the work tree: run in a monorepo subdirectory, git would prefix the
  # pathspecs with that subdirectory, and ".sumela" would never match inside HEAD:<prefix>.
  top="$(git -C "$g" rev-parse --show-toplevel)" || return 2
  present="$(present_paths "$top" "$t" "$@")"
  mkdir -p "$out" || return 2
  : > "$out.ls"
  [ -n "$present" ] || return 0
  # shellcheck disable=SC2086  # $present: CORE paths, which hold no spaces
  tree_list "$top" "$t" "$out.ls" $present || return 2
  # Never pipe a blob: the PowerShell twin cannot, and both twins must see the same bytes.
  # shellcheck disable=SC2086
  { git -C "$top" archive --format=tar -o "$WORK/t.tar" "$t" -- $present && tar -xf "$WORK/t.tar" -C "$out" && rm -f "$WORK/t.tar"; } || return 2
  # git archive honors the tree's export-ignore attributes: a tree it cannot reproduce in full is not used.
  if ! miss="$(verify_tree "$out" "$out.ls")"; then err "git archive left $miss out of $t (an export-ignore attribute?)"; return 2; fi
}
# materialize_index: the same, through a temporary index and checkout-index, so attributes of the
# tree itself (export-ignore, export-subst, which git archive honors) never apply. Used for HEAD,
# whose .gitattributes is the project's own. The real index is never touched.
materialize_index() {
  local g="$1" t="$2" out="$3" present top miss idx="$WORK/head.index"
  shift 3
  git -C "$g" rev-parse -q --verify "$t" >/dev/null || return 1
  top="$(git -C "$g" rev-parse --show-toplevel)" || return 2
  present="$(present_paths "$top" "$t" "$@")"
  mkdir -p "$out" || return 2
  : > "$out.ls"
  [ -n "$present" ] || return 0
  # shellcheck disable=SC2086
  tree_list "$top" "$t" "$out.ls" $present || return 2
  rm -f "$idx"
  GIT_INDEX_FILE="$idx" git -C "$top" update-index -z --index-info < "$out.ls.z" || return 2
  GIT_INDEX_FILE="$idx" git -C "$top" checkout-index -a -f --prefix="$out/" || return 2
  if ! miss="$(verify_tree "$out" "$out.ls")"; then err "could not read $miss from $t"; return 2; fi
}
listed() { p="$2" LC_ALL=C awk -F '\t' 'BEGIN { p = ENVIRON["p"] } $2 == p { f = 1; exit } END { exit !f }' "$1"; }   # <list> <path>
have_rev() { git -C "$SRC" rev-parse -q --verify "$1^{commit}" >/dev/null; }
rev_of() { git -C "$SRC" rev-parse -q --verify "$1^{commit}"; }
read_ver() { [ -f "$1/.sumela/VERSION" ] && tr -d '[:space:]' < "$1/.sumela/VERSION" || echo "unknown"; }
same() { cmp -s "$1" "$2"; }
same_text() {  # equal once CR bytes are dropped: a CRLF checkout of an unmodified file is not a fork
  [ -f "$1" ] && [ -f "$2" ] || return 1
  same "$1" "$2" && return 0
  tr -d '\r' < "$1" > "$WORK/a" && tr -d '\r' < "$2" > "$WORK/b" && same "$WORK/a" "$WORK/b"
}
# git's own test (numstat "-"), against an empty file: on Windows a /dev/null argument reaches
# the native git.exe through MSYS path conversion.
is_binary() { : > "$WORK/empty" && [ "$(git diff --no-index --numstat -- "$WORK/empty" "$1" | cut -f1)" = "-" ]; }
ver_gt() {  # ver_gt <a> <b>: a > b for X.Y.Z versions; anything else is false
  LC_ALL=C awk -v a="$1" -v b="$2" 'BEGIN {
    if (a !~ /^[0-9]+\.[0-9]+\.[0-9]+$/ || b !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) exit 1
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
    exit 1 }'
}
newest_release_tag() {  # `git ls-remote --tags --refs` on stdin -> the highest vX.Y.Z; never a release candidate [RU-I6]
  LC_ALL=C awk '{ sub(/\r$/, ""); r = $2; sub(/^refs\/tags\//, "", r); if (r ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/) print substr(r, 2) }' |
    LC_ALL=C sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | LC_ALL=C sed 's/^./v&/'
}
# udiff <label-a> <file-a> <label-b> <file-b> <rel>: a unified diff with stable labels, CRs
# dropped and git's diff settings pinned, so both twins write the same bytes. A missing file
# reads as empty.
udiff() {
  local d="$WORK/udiff" a="$1/$5" b="$3/$5"
  rm -rf "$d"; mkdir -p "$(dirname "$d/$a")" "$(dirname "$d/$b")" || return 1
  if [ -f "$2" ]; then tr -d '\r' < "$2" > "$d/$a"; else : > "$d/$a"; fi
  if [ -f "$4" ]; then tr -d '\r' < "$4" > "$d/$b"; else : > "$d/$b"; fi
  chmod 644 "$d/$a" "$d/$b"
  git -C "$d" -c core.quotepath=off -c diff.noprefix=false -c diff.mnemonicPrefix=false \
    -c diff.suppressBlankEmpty=false -c diff.algorithm=myers -c diff.interHunkContext=0 -c color.diff=never \
    diff --no-index --no-color --no-ext-diff --no-textconv --no-prefix -U3 -- "$a" "$b"
  return 0
}

# --- Acquire the framework source -------------------------------------------
# The source is a git checkout: THEIRS is its release tag's tree, never its working tree.
SRC_FROM_CLONE=false SRC_TAG=""
if [ -n "$SOURCE_DIR" ]; then
  SRC="$(cd "$SOURCE_DIR" 2>/dev/null && pwd)" || { err "--source '$SOURCE_DIR' is not a directory"; exit 1; }
  [ -d "$SRC/.sumela" ] || { err "--source '$SRC' is not a SumelaOS checkout (.sumela/ missing)"; exit 1; }
  if ! git -C "$SRC" rev-parse --git-dir >/dev/null; then
    err "--source '$SRC' is not a git checkout: the updater installs a release tag's tree, never a working tree."
    exit 1
  fi
  if [ -n "$(git -C "$SRC" rev-parse --show-prefix)" ]; then
    err "--source '$SRC' must be the top directory of a SumelaOS git checkout."
    exit 1
  fi
else
  CLONE_TMP="$(mktemp -d)" || { err "cannot create a temporary directory"; exit 1; }
  info "Finding the newest release of $REPO_URL ..."
  # Restrict transports so a poisoned .sumela/upstream.conf can't run code via git's
  # ext::/file:: transport (the framework is only ever fetched over https/ssh/git).
  _tags="$(GIT_ALLOW_PROTOCOL=https:ssh:git git ls-remote --tags --refs "$REPO_URL")" || { err "could not list the tags of $REPO_URL"; exit 1; }
  SRC_TAG="$(printf '%s\n' "$_tags" | newest_release_tag)"
  [ -n "$SRC_TAG" ] || { err "no release tag (vX.Y.Z) at $REPO_URL"; exit 1; }
  info "Cloning $REPO_URL at $SRC_TAG ..."
  GIT_ALLOW_PROTOCOL=https:ssh:git git clone --quiet --depth 1 --branch "$SRC_TAG" "$REPO_URL" "$CLONE_TMP" || { err "clone failed"; exit 1; }
  SRC="$CLONE_TMP"; SRC_FROM_CLONE=true
fi
SRC_SHALLOW="$(git -C "$SRC" rev-parse --is-shallow-repository)"

# fetch_into_src <what> <refspec>: best effort, and only into a clone this updater made or a
# shallow one (the clone a pre-0.20 updater left), never during --dry-run: a full checkout of
# yours is never fetched into.
fetch_into_src() {
  if [ "$SRC_FROM_CLONE" != true ]; then
    [ "$DRY_RUN" != true ] && [ "$SRC_SHALLOW" = true ] || return 1
  fi
  git -C "$SRC" remote get-url origin >/dev/null 2>&1 || return 1
  info "Fetching $1 from the source's origin (best effort) ..."
  GIT_ALLOW_PROTOCOL=https:ssh:git git -C "$SRC" fetch --quiet --depth 1 --no-tags origin "$2" || { warn "could not fetch $1"; return 1; }
}

# SRC_REF: the commit THEIRS comes from. A clone sits on its tag. A --source checkout gives the tag
# of the version its HEAD carries; a shallow one without that tag (the depth-1 clone of the
# default branch a pre-0.20 updater made) gives the newest release tag of its origin; anything
# else is refused, unless --allow-untagged-source (maintainer tests) installs the HEAD commit.
if [ "$SRC_FROM_CLONE" = true ]; then
  SRC_REF="$(rev_of HEAD)"; SRC_LABEL="$SRC_TAG"
else
  _v="$(git -C "$SRC" show HEAD:.sumela/VERSION | tr -d '[:space:]')"
  [ -n "$_v" ] || { err "the source's HEAD commit has no .sumela/VERSION"; exit 1; }
  have_rev "refs/tags/v$_v" || fetch_into_src "tag v$_v" "refs/tags/v$_v:refs/tags/v$_v" || true
  if have_rev "refs/tags/v$_v"; then
    SRC_REF="$(rev_of "refs/tags/v$_v")"; SRC_LABEL="v$_v"
    [ "$SRC_REF" = "$(rev_of HEAD)" ] || info "The source's HEAD is not v$_v: installing the tag's tree, not HEAD's."
  elif [ "$SRC_SHALLOW" = true ] && git -C "$SRC" remote get-url origin >/dev/null 2>&1; then
    if [ "$DRY_RUN" = true ]; then
      err "The source is a shallow clone whose HEAD (v$_v) is not a release, and --dry-run fetches nothing into it."
      err "  Run without --dry-run, or point --source at a release clone (git clone --branch v<X.Y.Z>)."
      exit 1
    fi
    _t="$(GIT_ALLOW_PROTOCOL=https:ssh:git git -C "$SRC" ls-remote --tags --refs origin | newest_release_tag)"
    [ -n "$_t" ] || { err "the source's origin has no release tag (vX.Y.Z)"; exit 1; }
    have_rev "refs/tags/$_t" || fetch_into_src "the newest release, $_t" "refs/tags/$_t:refs/tags/$_t" || true
    have_rev "refs/tags/$_t" || { err "could not fetch $_t into the source"; exit 1; }
    SRC_REF="$(rev_of "refs/tags/$_t")"; SRC_LABEL="$_t"
    info "The source is a shallow clone at v$_v, which is not a release: installing the newest release, $_t."
  elif [ "$ALLOW_UNTAGGED_SOURCE" = true ]; then
    SRC_REF="$(rev_of HEAD)"; SRC_LABEL="HEAD"
    warn "--allow-untagged-source: v$_v is not tagged in the source; installing its HEAD commit (committed content only)."
  else
    err "The source's HEAD carries v$_v, which is not a release tag there: the updater installs releases only."
    err "  Use a release clone (git clone --branch v<X.Y.Z>), fetch the tags (git fetch --tags), or pass"
    err "  --allow-untagged-source (maintainer tests only)."
    exit 1
  fi
  # A dirty source would have its uncommitted changes silently ignored [RU-I8]: refuse it.
  _dirty="$(git -C "$SRC" --no-optional-locks status --porcelain=v1 --untracked-files=all -- "${CORE_FILES[@]}" "${CORE_DIRS[@]}")" ||
    { err "git cannot read the status of the source"; exit 1; }
  if [ -n "$_dirty" ]; then
    if [ "$ALLOW_DIRTY_SOURCE" = true ]; then
      warn "--allow-dirty-source: the source has uncommitted CORE changes; they are NOT installed (THEIRS is $SRC_LABEL)."
    else
      err "The source has uncommitted or untracked changes under the CORE paths:"
      printf '%s\n' "$_dirty" | head -20 | sed 's/^/  /'
      err "  Commit them (and tag the release), or pass --allow-dirty-source (maintainer tests only)."
      exit 1
    fi
  fi
fi
[ -n "$SRC_REF" ] || { err "cannot resolve the source's commit"; exit 1; }
# shellcheck disable=SC2086
materialize "$SRC" "$SRC_REF" "$THEIRS_DIR" $CORE_PATHS || { err "cannot read $SRC_LABEL's tree from the source in full: nothing was changed"; exit 1; }
SRC_VER="$(read_ver "$THEIRS_DIR")"
LOCAL_VER="$(read_ver "$ROOT")"
[ "$SRC_VER" != unknown ] || { err "$SRC_LABEL of the source has no .sumela/VERSION"; exit 1; }
info "Local core version: ${LOCAL_VER}    Upstream: ${SRC_VER} ($SRC_LABEL, ${SRC_REF:0:12})"
# The running updater knows the new CORE list exactly when it is the release's own updater.
RUNNING_IS_THEIRS=false
same_text "$WORK/running-updater" "$THEIRS_DIR/scripts/update.sh" && RUNNING_IS_THEIRS=true

# --- The provenance record and the self-heal check ---------------------------------
REC_OK=false
if [ -f "$REC" ]; then
  _rc=0; sumela_record_get version "$REC" >/dev/null || _rc=$?
  if [ "$_rc" -eq 3 ]; then warn "$REC is unreadable (the reason is above): treated as absent."; else REC_OK=true; fi
fi
rec_get() { [ "$REC_OK" = true ] || return 0; sumela_record_get "$1" "$REC" || true; }   # <key> -> value or nothing
REC_SCHEMA="$(rec_get updater_schema)"; REC_VER="$(rec_get version)"
REC_OPEN=false   # an unfinished run (partial, or waiting for its re-run) wrote the record
[ "$(rec_get partial_upgrade)" = true ] || [ "$(rec_get pending_rerun)" = true ] && REC_OPEN=true

IN_GIT=false PREFIX=""
# Expected to fail for an install outside git: the self-heal and the HEAD probes are then off.
if PREFIX="$(git -C "$ROOT" rev-parse --show-prefix 2>/dev/null)"; then IN_GIT=true; else PREFIX=""; fi
HEAD_VER=""
[ "$IN_GIT" = true ] && HEAD_VER="$(git -C "$ROOT" show "HEAD:./.sumela/VERSION" 2>/dev/null | tr -d '[:space:]')"
# Self-heal: HEAD's VERSION differs from the working tree's and no v2 record vouches for the
# working tree. An older updater overwrote files and stamped VERSION, uncommitted: the forks are
# rebuilt from what is committed.
SELF_HEAL=false
if [ -n "$HEAD_VER" ] && [ "$HEAD_VER" != "$LOCAL_VER" ]; then
  if [ "$REC_SCHEMA" = 2 ] && [ "$REC_VER" = "$LOCAL_VER" ]; then :; else SELF_HEAL=true; fi
fi
BASE_VER="$LOCAL_VER"
[ "$SELF_HEAL" = true ] && BASE_VER="$HEAD_VER"

# Never downgrade by accident: an older --source is refused before anything is written.
if ver_gt "$BASE_VER" "$SRC_VER"; then
  err "The source is v$SRC_VER, older than this install (v$BASE_VER): refusing to downgrade."
  err "  Point --source at a release checkout of v$BASE_VER or newer. Nothing was changed."
  exit 1
fi

# --- Reconcile the SumelaOS-managed .gitignore patterns ----------------------
# Runs BEFORE the version gate, so even an already-current install backfills any
# newly-shipped managed pattern. .gitignore is OVERLAY (never overwritten), so new
# managed runtime-artifact patterns would otherwise reach only FRESH installs, not
# projects that upgrade via this script (the gap that left .sumela/.update-check
# untracked on upgrade from <0.7.1). Backfill from the SINGLE SOURCE that setup.sh
# also uses (scripts/lib/sumela-gitignore.sh, taken from the release's tree). Idempotent:
# only ADDS patterns absent anywhere in .gitignore; never duplicates an existing
# entry and never touches the user's own lines. An unanswered prompt adds nothing.
reconcile_gitignore() {
  local lib="$THEIRS_DIR/scripts/lib/sumela-gitignore.sh"
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
    if ! read -r yn; then echo ""; info "no answer (end of input): .gitignore left as it is"; return 0; fi
    case "$yn" in n|N) info "skipped .gitignore reconcile"; return 0 ;; esac
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

# --- Version gate ------------------------------------------------------------
if [ "$SRC_VER" = "$LOCAL_VER" ] && [ "$FORCE" != true ] && [ "$SELF_HEAL" != true ]; then
  ok "Already on core version ${LOCAL_VER}. (Use --force to re-check files anyway.)"
  exit 0
fi

: > "$WORK/oldpass"; : > "$WORK/head.ls"; : > "$WORK/heal"
OLDPASS_KNOWN=false
if [ "$SELF_HEAL" = true ]; then
  # HEAD's copy through a temporary index: complete whatever the project's .gitattributes says.
  # shellcheck disable=SC2086
  if materialize_index "$ROOT" "HEAD:$PREFIX" "$WORK/head" $CORE_PATHS "$SCHEMA_LIVE"; then
    warn "VERSION says $LOCAL_VER but HEAD says $HEAD_VER, and no record vouches for the change: an older updater"
    warn "  overwrote files without a commit. Your forks are taken from HEAD (v$HEAD_VER) and merged again."
    # The paths that older updater's own (pre-0.20) record lists: it wrote them.
    if [ "$REC_SCHEMA" != 2 ] && [ "$REC_VER" = "$LOCAL_VER" ]; then sumela_record_files "$REC" > "$WORK/oldpass"; OLDPASS_KNOWN=true; fi
  else
    err "VERSION says $LOCAL_VER but HEAD says $HEAD_VER (an older updater's uncommitted pass?), and HEAD's copy cannot be read in full."
    err "  Restore the files (git checkout -- .sumela scripts) or commit them, then re-run. Nothing was changed."
    exit 1
  fi
fi
OURS="$WORK/head"   # HEAD's copy of the install (self-heal only); its file list is $WORK/head.ls
# Rows an earlier run left waiting for your decision: its record lists them as "kept: pending". They
# wait again, whatever .sumela/.upgrade/ still holds, until you decide; HEAD's current copy of each
# ($WORK/pend) is what a working copy that settled them must equal, and what .head offers again.
: > "$WORK/pending"
if [ "$REC_OK" = true ]; then
  { sumela_record_get kept "$REC" || true; } | LC_ALL=C awk -F '\t' '$2 == "pending" && $1 != "" { print $1 }' > "$WORK/pending"
fi
if [ -s "$WORK/pending" ] && [ "$IN_GIT" = true ]; then
  _pend_paths=()
  while IFS= read -r _p; do _pend_paths+=("$_p"); done < "$WORK/pending"
  materialize_index "$ROOT" "HEAD:$PREFIX" "$WORK/pend" "${_pend_paths[@]}" ||
    warn "HEAD's copies of the rows still waiting for your decision cannot be read; they wait all the same."
fi

# --- The candidates: every CORE file of the release's tree (git ls-tree, never find) ----------
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
is_updater() { case " $UPDATER_FILES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
is_core_path() {  # <rel>: a CORE file path, relative and without "." or ".." segments
  local d
  case "/$1/" in */../*|*/./*|//*) return 1 ;; esac
  for d in "${CORE_FILES[@]}"; do [ "$1" = "$d" ] && return 0; done
  for d in "${CORE_DIRS[@]}"; do case "$1" in "$d"/?*) return 0 ;; esac; done
  return 1
}
git -C "$SRC" ls-tree -r -z "$SRC_REF" -- "${CORE_FILES[@]}" "${CORE_DIRS[@]}" > "$WORK/cand.lsz" ||
  { err "git cannot list $SRC_LABEL's tree"; exit 1; }
# A path the record could not hold (a quote, a backslash, a control character) is named and
# skipped, and so is a symlink or submodule.
tr '\000' '\n' < "$WORK/cand.lsz" | LC_ALL=C awk -F '\t' '
  { split($1, m, " ") }
  m[2] != "blob" || (m[1] != "100644" && m[1] != "100755") { print "skipped (not a regular file): " $2 > "/dev/stderr"; next }
  NF != 2 || $2 ~ /[[:cntrl:]"\\]/ { print "skipped (unsupported characters in the path): " $0 > "/dev/stderr"; next }
  { print $2 }' > "$WORK/cand.all"
: > "$WORK/cand"; : > "$WORK/cand.updater"
while IFS= read -r f; do
  plugin_absent "$f" && continue
  if is_updater "$f"; then printf '%s\n' "$f" >> "$WORK/cand.updater"; else printf '%s\n' "$f" >> "$WORK/cand"; fi
done < "$WORK/cand.all"

# --- BASE: selection and validation [RU-C1] ---------------------------------------------------
BASE_REF="" BASE_LABEL="" BASE_COMMIT="" BASE_NOTE="" BASE_FROM="" HAVE_BASE=false
select_base() {  # the record's upstream_commit for this version, else the tag v<BASE_VER>, else none
  local uc
  uc="$(rec_get upstream_commit)"
  if [ "$REC_VER" = "$BASE_VER" ] && [ -n "$uc" ] && [ -z "$(printf '%s' "$uc" | tr -d '0-9a-f')" ]; then
    have_rev "$uc" || fetch_into_src "the recorded base commit ${uc:0:12}" "$uc" || true
    if have_rev "$uc"; then BASE_REF="$(rev_of "$uc")"; BASE_LABEL="the recorded commit ${uc:0:12}"; BASE_FROM=record; return 0; fi
    warn "The record's base commit ${uc:0:12} is not in the source: using the tag v$BASE_VER instead."
  fi
  [ "$BASE_VER" != unknown ] || return 0
  have_rev "refs/tags/v$BASE_VER" || fetch_into_src "tag v$BASE_VER" "refs/tags/v$BASE_VER:refs/tags/v$BASE_VER" || true
  if have_rev "refs/tags/v$BASE_VER"; then BASE_REF="$(rev_of "refs/tags/v$BASE_VER")"; BASE_LABEL="v$BASE_VER"; BASE_FROM=tag; fi
}
# --- Self-heal: whose bytes are in the working tree? ---------------------------------------
# heal_class <rel> <tree-rel> -> one word, decided once per path from the state before this run:
#   same       the working copy is HEAD's (or neither has the file)
#   written    HEAD has the file and the working copy is a version upstream committed: an older
#              updater wrote it. LOCAL is HEAD's copy, which goes back before any question.
#   afterpass  HEAD has the file, the working copy is no upstream version, and that updater may
#              have written the file (its record lists it, or it left no record): a change on top of
#              its write, whose parts nobody can tell apart. LOCAL is the working copy, which stays;
#              HEAD's copy is offered as .sumela/.upgrade/<path>.head, and the row waits for your
#              decision in this run and in every later one while that .head exists.
#   yours      HEAD has the file, the working copy is no upstream version, and that updater's record
#              does not list it: your uncommitted change. LOCAL is the working copy.
#   deleted    HEAD has the file and the working copy is gone: your deletion.
#   added      HEAD has no such file and does not ignore the path, the working copy is a version
#              upstream committed, and that updater wrote it (its record) or you had deleted the file
#              (HEAD's history): LOCAL is "no file".
#   untracked  HEAD has no such file otherwise (a host file, a gitignored live file): LOCAL is the
#              working copy, and its absence from HEAD decides nothing.
# upstream_versions: "$WORK/upstream.blobs", "<path><TAB><blob>" for every version upstream committed
# between BASE and THEIRS (both included): what an older updater upgrading this install could have
# written. An older version is yours to have chosen (a revert), never taken for that updater's write.
upstream_versions() {
  local z
  [ -f "$WORK/upstream.blobs" ] && return 0
  { if [ "$HAVE_BASE" = true ]; then
      git -C "$SRC" -c core.quotepath=off log -m --no-renames --format= --raw --no-abbrev "$BASE_REF..$SRC_REF" \
        -- "${CORE_FILES[@]}" "${CORE_DIRS[@]}" |
        LC_ALL=C awk -F '\t' '/^:/ { split($1, f, " "); print $2 "\t" f[3]; print $2 "\t" f[4] }'
    fi
    for z in "$THEIRS_DIR.ls.z" "$WORK/base.ls.z"; do
      [ -f "$z" ] && tr '\000' '\n' < "$z" | LC_ALL=C awk -F '\t' '{ split($1, m, " "); print $2 "\t" m[3] }'
    done; } | LC_ALL=C sort -u > "$WORK/upstream.blobs"
}
is_upstream_version() {  # <tree-rel> <file>: the file, as is or with its CRs dropped, is a version upstream committed
  local h1 h2
  upstream_versions
  h1="$(git -C "$SRC" hash-object --no-filters -- "$2")" || return 1
  tr -d '\r' < "$2" > "$WORK/hob" && h2="$(git -C "$SRC" hash-object --no-filters -- "$WORK/hob")" || return 1
  p="$1" a="$h1" b="$h2" LC_ALL=C awk -F '\t' 'BEGIN { p = ENVIRON["p"]; a = ENVIRON["a"]; b = ENVIRON["b"] }
    $1 == p && ($2 == a || $2 == b) { f = 1; exit } END { exit !f }' "$WORK/upstream.blobs"
}
ignored_path() { git -C "$ROOT" check-ignore -q -- "$1" 2>/dev/null; }    # <rel>: gitignored (a probe: 1 = no)
deleted_before() { [ -n "$(git -C "$ROOT" log -1 --format=%H --diff-filter=D HEAD -- "$1")" ]; }   # <rel>: HEAD's history deleted it
heal_class() {  # <rel> <tree-rel> -> the class above (cached)
  local f="$1" tf="${2:-$1}" W="$ROOT/$1" c
  c="$(p="$f" LC_ALL=C awk -F '\t' 'BEGIN { p = ENVIRON["p"] } $1 == p { print $2; exit }' "$WORK/heal")"
  if [ -z "$c" ]; then
    if listed "$WORK/head.ls" "$f"; then
      if [ ! -e "$W" ] && [ ! -L "$W" ]; then c=deleted
      elif same_text "$W" "$OURS/$f"; then c=same
      elif [ -f "$W" ] && is_upstream_version "$tf" "$W"; then c=written
      elif [ "$OLDPASS_KNOWN" = true ] && ! LC_ALL=C grep -qxF -- "$f" "$WORK/oldpass"; then c=yours
      else c=afterpass; fi
    elif [ -f "$W" ] && ! ignored_path "$f" && is_upstream_version "$tf" "$W" &&
         { LC_ALL=C grep -qxF -- "$f" "$WORK/oldpass" || deleted_before "$f"; }; then c=added
    elif [ -e "$W" ] || [ -L "$W" ]; then c=untracked
    else c=same; fi
    printf '%s\t%s\n' "$f" "$c" >> "$WORK/heal"
  fi
  printf '%s' "$c"
}
local_of() {  # <rel> [<tree-rel>] -> the file that is LOCAL: the working copy, except in a self-heal (above)
  [ "$SELF_HEAL" = true ] || { printf '%s' "$ROOT/$1"; return; }
  case "$(heal_class "$1" "${2:-$1}")" in
    written) printf '%s' "$OURS/$1" ;;
    added)   printf '%s/%s' "$ABSENT" "$1" ;;
    *)       printf '%s' "$ROOT/$1" ;;
  esac
}
# waits_for_you <rel> <tree-rel>: the row waits for your decision whatever else holds: a self-heal
# "afterpass" copy, or one an earlier run left undecided (its record says "kept: pending", or its
# .head is still there), until the working copy is HEAD's current copy or the .head again.
waits_for_you() {
  local w="$ROOT/$1"
  if [ "$SELF_HEAL" = true ] && [ "$(heal_class "$1" "$2")" = afterpass ]; then return 0; fi
  [ -f "$UPG/$1.head" ] || LC_ALL=C grep -qxF -- "$1" "$WORK/pending" || return 1
  [ -f "$w" ] || return 1
  if [ -f "$WORK/pend/$1" ] && same_text "$w" "$WORK/pend/$1"; then return 1; fi
  if [ -f "$UPG/$1.head" ] && same_text "$w" "$UPG/$1.head"; then return 1; fi
  return 0
}
validate_base() {  # sets HAVE_BASE and BASE_NOTE [RU-C1]
  local p bv L n=0 bad=0 names="" rc=0 hint=""
  HAVE_BASE=false
  [ "$BASE_VER" != unknown ] || { BASE_NOTE="the install has no .sumela/VERSION: merging disabled"; return 0; }
  [ "$DRY_RUN" = true ] && [ "$SRC_FROM_CLONE" != true ] && hint=" (--dry-run fetches nothing into --source; a real run fetches it)"
  [ -n "$BASE_REF" ] || { BASE_NOTE="no base for v$BASE_VER in the source: merging disabled$hint"; return 0; }
  # shellcheck disable=SC2086
  materialize "$SRC" "$BASE_REF" "$WORK/base" $CORE_PATHS || rc=$?
  [ "$rc" -eq 0 ] || { BASE_NOTE="the base tree ($BASE_LABEL) cannot be read in full: merging disabled"; return 0; }
  bv="$(read_ver "$WORK/base")"
  [ "$bv" = "$BASE_VER" ] || { BASE_NOTE="the base tree ($BASE_LABEL) says v${bv}, the install says v$BASE_VER: merging disabled"; return 0; }
  HAVE_BASE=true
  BASE_COMMIT="$BASE_REF"
  # A v1 record vouches for nothing: it lists files re-forked by hand inside the upgrade commit.
  [ "$REC_SCHEMA" = 2 ] && [ "$REC_VER" = "$BASE_VER" ] || return 0
  # Only a FINISHED run vouches for its files: an unfinished one (partial, or waiting for its
  # re-run) has already written the new release's bytes into the files it lists.
  [ "$REC_OPEN" = true ] && return 0
  while IFS= read -r p; do
    [ -n "$p" ] && [ -f "$ROOT/$p" ] && [ -f "$WORK/base/$p" ] || continue
    L="$(local_of "$p")"
    if same_text "$L" "$WORK/base/$p"; then n=$((n + 1)); continue; fi
    # Already the new release's bytes: no evidence about the base either way.
    [ -f "$THEIRS_DIR/$p" ] && same_text "$L" "$THEIRS_DIR/$p" && continue
    n=$((n + 1)); bad=$((bad + 1)); names="$names $p"   # a fork for this file only
  done <<EOF
$(sumela_record_files "$REC")
EOF
  if [ "$n" -gt 0 ] && [ $((bad * 2)) -gt "$n" ]; then
    HAVE_BASE=false; BASE_COMMIT=""
    BASE_NOTE="$bad of $n vouched files differ from base v$BASE_VER (wrong base?):$names"
  fi
}
AMBIG_ALL=false
setup_ambiguity() {  # the tag sits on a later commit than its VERSION bump: those files are ambiguous
  local bump rc=0
  : > "$WORK/ambiguous"
  # Only a tag can sit after its bump: a recorded upstream_commit is the exact commit installed.
  [ "$HAVE_BASE" = true ] && [ "$BASE_FROM" = tag ] || return 0
  if [ "$SRC_SHALLOW" = true ]; then
    # The bump is not in a shallow history. For the tags known to sit after it, treat every file
    # as ambiguous: it applies only when it is still the tag's copy, otherwise it is reviewed.
    case "$KNOWN_AMBIGUOUS_TAGS" in *" $BASE_VER "*) AMBIG_ALL=true ;; esac
    return 0
  fi
  bump="$(git -C "$SRC" log --format=%H -S"$BASE_VER" "$BASE_REF" -- .sumela/VERSION | tail -1)"
  [ -n "$bump" ] && [ "$bump" != "$BASE_REF" ] || return 0
  # shellcheck disable=SC2086
  git -C "$SRC" -c core.quotepath=off diff --name-only "$bump" "$BASE_REF" -- $CORE_PATHS > "$WORK/ambiguous" || AMBIG_ALL=true
  # shellcheck disable=SC2086
  if [ -s "$WORK/ambiguous" ]; then materialize "$SRC" "$bump" "$WORK/bump" $CORE_PATHS || rc=$?; fi
  [ "$rc" -eq 0 ] || AMBIG_ALL=true   # no full copy of the bump: nothing can be matched against it
  return 0
}
is_ambiguous() { [ "$AMBIG_ALL" = true ] || LC_ALL=C grep -qxF -- "$1" "$WORK/ambiguous"; }

select_base
validate_base
setup_ambiguity

# --- Classification and merge ------------------------------------------------------------
classify() {  # classify <rel> [<tree-rel>] -> "<action>[<TAB><note>]" on stdout
  local f="$1" tf="${2:-$1}" L T B
  T="$THEIRS_DIR/$tf"; B="$WORK/base/$tf"; L="$(local_of "$f" "$tf")"
  if waits_for_you "$f" "$tf"; then
    printf 'review\tchanged after an older updater wrote it; HEAD'"'"'s copy (your fork) is .head\n'; return
  fi
  if [ ! -e "$L" ] && [ ! -L "$L" ]; then if [ "$HAVE_BASE" = true ] && [ -f "$B" ]; then echo readd; else echo add; fi; return; fi
  if [ -L "$L" ] || [ ! -f "$L" ]; then printf 'review\tnot a regular file\n'; return; fi
  same_text "$L" "$T" && { echo same; return; }
  [ "$HAVE_BASE" = true ] || { printf 'review\tmerging disabled\n'; return; }   # no valid BASE: never guess
  [ -f "$B" ] || { echo collision; return; }                 # host file at a newly CORE path
  same_text "$L" "$B" && { echo apply; return; }             # no local content to lose
  if is_ambiguous "$tf"; then
    if [ -f "$WORK/bump/$tf" ] && same_text "$L" "$WORK/bump/$tf"; then echo apply
    else printf 'review\tthe v%s tag sits after its version bump and this file changed in between\n' "$BASE_VER"; fi
    return
  fi
  same_text "$T" "$B" && { echo keep; return; }              # fork; upstream did not touch it
  if is_binary "$L" || is_binary "$T"; then printf 'review\tbinary file\n'; return; fi
  echo merge3
}
pins_ok() {  # pins_ok <rel> <merged-file>: each require literal present, no forbid literal; prints the first violation [RQ-21]
  local pf line kind lit n
  for pf in "$THEIRS_DIR"/scripts/lib/sumela-merge-pins/*.pins; do
    [ -f "$pf" ] && [ "$(LC_ALL=C sed -n 's/^# path: //p' "$pf" | tr -d '\r')" = "$1" ] || continue
    n=0
    while IFS= read -r line || [ -n "$line" ]; do
      n=$((n + 1)); line="${line%$'\r'}"
      case "$line" in ''|'#'*) continue ;; esac
      kind="${line%%"$TAB"*}"; lit="${line#*"$TAB"}"
      # A row this updater cannot read is a violation, never a pass: the pin exists for safety.
      if [ "$kind" = "$line" ] || [ -z "$lit" ]; then printf 'pin: unreadable row %s:%s\n' "${pf##*/}" "$n"; return 1; fi
      case "$kind" in
        require) LC_ALL=C grep -qF -- "$lit" "$2" || { printf 'pin: missing %s\n' "$lit"; return 1; } ;;
        forbid)  LC_ALL=C grep -qF -- "$lit" "$2" && { printf 'pin: forbidden %s\n' "$lit"; return 1; } ;;
        *) printf 'pin: unknown kind "%s" at %s:%s\n' "$kind" "${pf##*/}" "$n"; return 1 ;;
      esac
    done < "$pf"
  done
  return 0
}
try_merge() {  # try_merge <rel> [<tree-rel>] -> merge | conflict[<TAB>pin: ...] | review<TAB>...; result left in $STAGE
  local f="$1" tf="${2:-$1}" d="$WORK/m" out="$STAGE/$1" rc v
  mkdir -p "$d" "$(dirname "$out")"
  if ! { tr -d '\r' < "$(local_of "$f" "$tf")" > "$d/local" && tr -d '\r' < "$WORK/base/$tf" > "$d/base" &&
         tr -d '\r' < "$THEIRS_DIR/$tf" > "$d/theirs"; }; then
    printf 'review\tcannot read the three versions\n'; return
  fi
  git merge-file -L local -L "base v$BASE_VER" -L "upstream v$SRC_VER" "$d/local" "$d/base" "$d/theirs" >&2; rc=$?
  if [ "$rc" -eq 0 ]; then
    if v="$(pins_ok "$f" "$d/local")"; then mv -f "$d/local" "$out.merged"; echo merge
    else mv -f "$d/local" "$out.merge"; printf '%s\n' "$v" > "$out.pin"; printf 'conflict\t%s\n' "$v"; fi   # clean, but it breaks a merge pin [RQ-21]
  elif [ "$rc" -gt 0 ] && [ "$rc" -lt 128 ]; then mv -f "$d/local" "$out.merge"; echo conflict
  else printf 'review\tgit merge-file failed (exit %s)\n' "$rc"   # merge-file error (exit 255): never guess
  fi
}
row_of() {  # row_of <rel> <tree-rel> -> appends "<action><TAB><rel><TAB><tree-rel><TAB><note>" to the rows
  local r a note=""
  r="$(classify "$1" "$2")"
  [ "${r%%"$TAB"*}" = merge3 ] && r="$(try_merge "$1" "$2")"
  a="${r%%"$TAB"*}"; [ "$a" = "$r" ] || note="${r#*"$TAB"}"
  printf '%s\t%s\t%s\t%s\n' "$a" "$1" "$2" "$note" >> "$WORK/rows"
}
floored() {  # <rel>: the release's copy of an updater twin predates v0.20.0 [updater-floor]
  case "$1" in
    scripts/update.sh)  [ -f "$THEIRS_DIR/$1" ] && ! LC_ALL=C grep -qF "$UPDATER_MARK_SH" "$THEIRS_DIR/$1" ;;
    scripts/update.ps1) [ -f "$THEIRS_DIR/$1" ] && ! LC_ALL=C grep -qF "$UPDATER_MARK_PS1" "$THEIRS_DIR/$1" ;;
    *) return 1 ;;
  esac
}
carry_row() {  # carry_row <rel> <successor> <local>: the hunks LOCAL adds to BASE, for the successor
  mkdir -p "$(dirname "$STAGE/$1")"
  udiff "v$BASE_VER" "$WORK/base/$1" yours "$3" "$1" > "$STAGE/$1.carry"
  printf 'carry\t%s\t%s\t%s\n' "$1" "$1" "$2" >> "$WORK/rows"
}
removal_rows() {  # rows for the paths scripts/lib/sumela-removed-files.list retires in (BASE_VER, SRC_VER] [RU-I10]
  local list="$THEIRS_DIR/scripts/lib/sumela-removed-files.list" v p s L B
  [ -f "$list" ] || return 0
  LC_ALL=C awk '{ sub(/\r$/, "") } /^[ \t]*(#|$)/ { next } { print }' "$list" > "$WORK/removed.rows"
  while IFS="$TAB" read -r v p s <&3; do
    if [ -z "$p" ] || [ -z "$s" ] || ! printf '%s\n' "$p" | LC_ALL=C grep -qv '[[:cntrl:]"\\]' ||
       ! is_core_path "$p" || { [ "$s" != "-" ] && ! is_core_path "$s"; }; then
      warn "sumela-removed-files.list: row skipped (not a CORE path, or unreadable): $v $p $s"; continue
    fi
    ver_gt "$v" "$BASE_VER" && ! ver_gt "$v" "$SRC_VER" || continue
    [ -e "$THEIRS_DIR/$p" ] && continue          # shipped again by this release: an ordinary row
    plugin_absent "$p" && continue
    L="$(local_of "$p")"; B="$WORK/base/$p"
    [ -f "$L" ] || continue                      # nothing (or no regular file) left to remove
    if waits_for_you "$p" "$p"; then carry_row "$p" "$s" "$ROOT/$p"; continue; fi   # whose change? you decide
    if [ "$HAVE_BASE" = true ] && [ -f "$B" ] && same_text "$L" "$B"; then
      printf 'remove\t%s\t%s\t\n' "$p" "$p" >> "$WORK/rows"
    elif [ "$s" = "-" ]; then
      printf 'keep-removed\t%s\t%s\t\n' "$p" "$p" >> "$WORK/rows"
    else
      carry_row "$p" "$s" "$L"
    fi
  done 3< "$WORK/removed.rows"
}

# Rows in apply order: files, removals, the live schema, then the updater files last.
: > "$WORK/rows"
while IFS= read -r f <&3; do row_of "$f" "$f"; done 3< "$WORK/cand"
removal_rows
if [ -f "$ROOT/$SCHEMA_LIVE" ] && [ -f "$THEIRS_DIR/$SCHEMA_SRC" ]; then
  row_of "$SCHEMA_LIVE" "$SCHEMA_SRC"
  # Its own consent class: the copy of a still-unmodified template is the "schema" action.
  LC_ALL=C awk -F '\t' -v OFS='\t' -v p="$SCHEMA_LIVE" '$2 == p && $1 == "apply" { $1 = "schema" } { print }' "$WORK/rows" > "$WORK/rows.t" &&
    mv -f "$WORK/rows.t" "$WORK/rows"
fi
while IFS= read -r f <&3; do
  row_of "$f" "$f"
  # A pre-0.20 updater is never installed, whatever the row: it would overwrite forks again.
  if floored "$f"; then
    LC_ALL=C awk -F '\t' -v OFS='\t' -v p="$f" '$2 == p && $1 != "same" && $1 != "keep" { $1 = "floor"; $4 = "the release'"'"'s copy predates v0.20.0" } { print }' \
      "$WORK/rows" > "$WORK/rows.t" && mv -f "$WORK/rows.t" "$WORK/rows"
  fi
done 3< "$WORK/cand.updater"

# --- Summary -------------------------------------------------------------------------------
waits() { case "$1" in conflict|collision|review|carry) return 0 ;; *) return 1 ;; esac; }
artifact_of() {  # artifact_of <action> <rel> -> the file under .sumela/.upgrade/ that row offers
  case "$1" in
    conflict) printf '.sumela/.upgrade/%s.merge' "$2" ;;
    collision|review) printf '.sumela/.upgrade/%s.theirs' "$2" ;;
    carry) printf '.sumela/.upgrade/%s.carry' "$2" ;;
  esac
}
echo ""
echo "${BOLD}=== SumelaOS core update: ${BASE_VER} → ${SRC_VER} ===${RESET}"
if [ "$HAVE_BASE" = true ]; then echo "  Base:     $BASE_LABEL (${BASE_COMMIT:0:12})"; else warn "Base: $BASE_NOTE"; fi
echo "  Overlay (AGENTS.md, RULE/SKILL_REGISTRY, stack rules, wiki, governance/CI): left untouched"
echo "  Files:    $(LC_ALL=C awk -F '\t' '$1 != "same" { n[$1]++; if (!($1 in o)) { o[$1] = ++k; w[k] = $1 } }
  END { for (i = 1; i <= k; i++) s = s (i > 1 ? " · " : "") n[w[i]] " " w[i]; print (k ? s : "no change") }' "$WORK/rows")"
LC_ALL=C awk -F '\t' -v all="$DRY_RUN" '$1 == "same" { next } all != "true" && ($1 == "add" || $1 == "apply") { next }
  { printf "    %-12s %s%s\n", $1, $2, ($4 != "" ? "  (" $4 ")" : "") }' "$WORK/rows"
N_WAIT="$(LC_ALL=C awk -F '\t' '$1 == "conflict" || $1 == "collision" || $1 == "review" || $1 == "carry"' "$WORK/rows" | wc -l | tr -d ' ')"

if [ "$DRY_RUN" = true ]; then
  echo ""; info "--dry-run: nothing written."
  [ "$N_WAIT" -gt 0 ] && info "  $N_WAIT file(s) would wait for your decision; their merges and previews would go to .sumela/.upgrade/."
  exit 0
fi

# --- Publish what a decision needs ------------------------------------------------------------
has_markers() { tr -d '\r' < "$1" | LC_ALL=C grep -nE '^(<<<<<<< |=======$|>>>>>>> |\|\|\|\|\|\|\| )' | head -1 | cut -d: -f1; }
free_prev() {  # <file> -> <file>.prev, else <file>.prev.2, ...: the first free name, so no earlier copy is lost
  local c="$1.prev" n=2
  while [ -e "$c" ]; do c="$1.prev.$n"; n=$((n + 1)); done
  printf '%s' "$c"
}
# publish <src> <artifact>: into .sumela/.upgrade/. What differs and may be yours (a .merge you
# resolved, an earlier .head) first moves to a free .prev name; an untouched .merge (its conflict
# markers still in it) is simply replaced.
publish() {
  local dst="$UPG/$2" keep
  mkdir -p "$(dirname "$dst")" || return 1
  if [ -f "$dst" ] && ! same "$1" "$dst"; then
    case "$2" in
      *.merge) if [ -z "$(has_markers "$dst")" ]; then
                 keep="$(free_prev "$dst")"; mv -f "$dst" "$keep" || return 1
                 warn "  your earlier edit of .sumela/.upgrade/$2 is now ${keep#"$UPG/"}"
               fi ;;
      *.head|*.working) keep="$(free_prev "$dst")"; mv -f "$dst" "$keep" || return 1 ;;
    esac
  fi
  cp "$1" "$dst"
}
retire() {  # retire <artifact>: a preview this run does not offer is never offered again; a .merge you edited moves to a free .prev name
  local dst="$UPG/$1" keep
  [ -f "$dst" ] || return 0
  case "$1" in
    *.merge) if [ -n "$(has_markers "$dst")" ]; then rm -f "$dst"
             else keep="$(free_prev "$dst")"; mv -f "$dst" "$keep" || return 1
                  warn "  a .merge you edited in an earlier run is now ${keep#"$UPG/"} (never offered as [m]erged)"; fi ;;
    *) rm -f "$dst" ;;
  esac
}
FAILED=false
if [ "$N_WAIT" -gt 0 ]; then
  while IFS="$TAB" read -r a f tf note; do
    case "$a" in
      conflict)
        publish "$STAGE/$f.merge" "$f.merge" || FAILED=true
        if [ -f "$STAGE/$f.pin" ]; then publish "$STAGE/$f.pin" "$f.pin" || FAILED=true; else retire "$f.pin" || FAILED=true; fi
        retire "$f.theirs" && retire "$f.carry" || FAILED=true ;;
      collision|review)
        publish "$THEIRS_DIR/$tf" "$f.theirs" || FAILED=true
        retire "$f.merge" && retire "$f.pin" && retire "$f.carry" || FAILED=true ;;
      carry)
        publish "$STAGE/$f.carry" "$f.carry" || FAILED=true
        retire "$f.merge" && retire "$f.pin" && retire "$f.theirs" || FAILED=true ;;
    esac
    # A row still waiting from an earlier run gets HEAD's copy offered again, if it was cleaned away.
    case "$a" in review|carry)
      if [ ! -f "$UPG/$f.head" ] && [ -f "$WORK/pend/$f" ] && LC_ALL=C grep -qxF -- "$f" "$WORK/pending"; then
        publish "$WORK/pend/$f" "$f.head" || FAILED=true
      fi ;;
    esac
  done < "$WORK/rows"
  [ "$FAILED" = true ] && { err "could not write the previews under .sumela/.upgrade/; no CORE file was changed"; exit 1; }
fi

# --- Install helpers ---------------------------------------------------------------------------
theirs_mode() {  # <tree-rel> -> 755 or 644, from THEIRS' git mode [RU-I7]
  local m
  m="$(p="$1" LC_ALL=C awk -F '\t' 'BEGIN { p = ENVIRON["p"] } $2 == p { print $1; exit }' "$THEIRS_DIR.ls")"
  if [ "$m" = 100755 ]; then echo 755; else echo 644; fi
}
head_mode() {  # <rel> -> 755 or 644, from HEAD's git mode of the install's file
  local m
  m="$(p="$1" LC_ALL=C awk -F '\t' 'BEGIN { p = ENVIRON["p"] } $2 == p { print $1; exit }' "$WORK/head.ls")"
  if [ "$m" = 100755 ]; then echo 755; else echo 644; fi
}
install_file() {  # install_file <src-file> <rel> <mode>: a temp file beside the target, then a rename; re-read
  local dst="$ROOT/$2"
  [ -d "$dst" ] && { err "$2 is a directory: not replaced"; return 1; }
  mkdir -p "$(dirname "$dst")" || { err "cannot create the directory of $2"; return 1; }
  case "$2" in   # the one file you cannot diff during the run: keep the outgoing copy (gitignored)
    scripts/update.sh|scripts/update.ps1)
      if [ -f "$dst" ]; then
        # The backup of an earlier run moves into .sumela/.upgrade/ instead of being overwritten.
        if [ -f "$dst.bak" ] && ! same "$dst" "$dst.bak"; then
          mkdir -p "$UPG/scripts" && mv -f "$dst.bak" "$UPG/$2.bak.prev" || warn "could not keep the earlier $2.bak"
        fi
        cp "$dst" "$dst.bak" || warn "could not keep $2.bak"
      fi ;;
  esac
  CUR_TMP="$dst.sumela-tmp.$$"
  if cp "$1" "$CUR_TMP" && chmod "$3" "$CUR_TMP" && mv -f "$CUR_TMP" "$dst"; then CUR_TMP=""
  else rm -f "$CUR_TMP"; CUR_TMP=""; err "could not write $2"; return 1; fi
  same "$1" "$dst" || { err "$2 does not hold what was written"; return 1; }
}
remove_file() {  # <rel>, then the directories it leaves empty
  local d
  rm -f -- "$ROOT/$1"
  [ ! -e "$ROOT/$1" ] || { err "could not remove $1"; return 1; }
  d="$(dirname "$1")"
  while [ "$d" != . ] && [ "$d" != / ] && rmdir -- "$ROOT/$d" 2>/dev/null; do d="$(dirname "$d")"; done
  return 0
}
restore_local() {  # <rel> <tree-rel>: put LOCAL back in the working tree (self-heal)
  local L; L="$(local_of "$1" "$2")"
  [ "$L" = "$ROOT/$1" ] && return 0
  case "$L" in
    "$ABSENT"/*) { [ -e "$ROOT/$1" ] || [ -L "$ROOT/$1" ]; } || return 0
                 remove_file "$1" && ok "removed $1 again (HEAD has no such file; an older updater had added it)" ;;
    *) same_text "$ROOT/$1" "$L" && return 0      # restored before the questions already
       install_file "$L" "$1" "$(head_mode "$1")" && ok "restored $1 (HEAD's copy; an older updater had overwritten it)" ;;
  esac
}
# Self-heal, before any question: HEAD's copy goes back wherever an older updater wrote upstream's
# bytes over it (a row that installs upstream's file or a merge writes it anyway). Where the working
# copy may hold both that updater's write and changes of yours, it stays, and HEAD's copy is
# offered as .head: the questions and [d]iff then show both.
heal_working_tree() {
  local a f tf note
  while IFS="$TAB" read -r a f tf note <&3; do
    case "$(heal_class "$f" "$tf")" in
      afterpass)
        publish "$OURS/$f" "$f.head" || return 1
        warn "  $f changed after an older updater wrote it: your working copy stays; HEAD's copy (your fork) is .sumela/.upgrade/$f.head" ;;
      written)
        # The bytes this replaces are upstream's, yet maybe nowhere else on this machine: kept.
        publish "$ROOT/$f" "$f.working" || return 1
        case "$a" in add|readd|apply|schema|merge|remove) ;; *)
          install_file "$OURS/$f" "$f" "$(head_mode "$f")" || return 1
          ok "restored $f (HEAD's copy; an older updater had overwritten it; that copy is .sumela/.upgrade/$f.working)" ;;
        esac ;;
    esac
  done 3< "$WORK/rows"
}
if [ "$SELF_HEAL" = true ]; then
  heal_working_tree || { err "could not restore HEAD's copies (above); fix the cause and re-run"; exit 1; }
fi

# --- Decisions (conflict, collision, review, carry) -----------------------------------------
: > "$WORK/decisions"   # "<rel><TAB>keep|merged|theirs|drop|skip"
decide() { printf '%s\t%s\n' "$1" "$2" >> "$WORK/decisions"; }
decision_of() { p="$1" LC_ALL=C awk -F '\t' 'BEGIN { p = ENVIRON["p"] } $1 == p { d = $2 } END { print d }' "$WORK/decisions"; }
merged_ok() {  # merged_ok <rel>: the .merge this run published, edited, may be installed
  local m="$UPG/$1.merge" line v
  [ -f "$m" ] || { echo "  There is no .merge file for this row: edit $1 itself and choose [k]eep, or choose [t]heirs."; return 1; }
  line="$(has_markers "$m")"
  if [ -n "$line" ]; then
    echo "  .sumela/.upgrade/$1.merge still has a conflict marker at line $line: edit it first."
    [ -f "$m.prev" ] && [ -z "$(has_markers "$m.prev")" ] &&
      echo "  Your earlier edit is in .sumela/.upgrade/$1.merge.prev: copy it over the .merge file to use it."
    return 1
  fi
  v="$(tr -d '\r' < "$m" > "$WORK/merge.check" && pins_ok "$1" "$WORK/merge.check")" ||
    { echo "  .sumela/.upgrade/$1.merge breaks a merge pin of v$SRC_VER ($v): edit it, or keep yours."; return 1; }
  return 0
}
show_diff() {  # show_diff <rel> <tree-rel>: yours against upstream's, and HEAD's copy (.head) against yours
  udiff yours "$ROOT/$1" "upstream-v$SRC_VER" "$THEIRS_DIR/$2" "$1" | sed 's/^/  /'
  if [ -f "$UPG/$1.head" ]; then
    echo "  HEAD's copy (your fork, .sumela/.upgrade/$1.head) against yours:"
    udiff head "$UPG/$1.head" yours "$ROOT/$1" "$1" | sed 's/^/  /'
  fi
}
EOF_SEEN=false
ask_row() {  # ask_row <action> <rel> <tree-rel> <note>
  local a="$1" f="$2" tf="$3" note="$4" ans p bad=0
  echo ""
  echo "${BOLD}--- $a: $f ---${RESET}"
  case "$a" in
    conflict)
      case "$note" in
        pin:*) echo "  Your changes and upstream v$SRC_VER's merge cleanly, but the result breaks a merge pin ($note)." ;;
        *)     echo "  You and upstream v$SRC_VER both changed this file since v$BASE_VER, and the changes overlap." ;;
      esac
      echo "  The merge: $(artifact_of "$a" "$f")" ;;
    collision) echo "  v$SRC_VER ships a file at this path that v$BASE_VER did not: yours is a host file."
               echo "  Upstream's copy: $(artifact_of "$a" "$f")" ;;
    review)    echo "  Not merged: ${note:-review}."
               [ -f "$UPG/$f.head" ] && echo "  Yours is the working copy; HEAD's copy (your fork) is .sumela/.upgrade/$f.head: combine what you keep into $f, then [k]eep."
               echo "  Upstream's copy: $(artifact_of "$a" "$f")" ;;
    carry)     if [ "$note" = "-" ]; then echo "  v$SRC_VER retires this file (nothing replaces it). Your changes to it (against v$BASE_VER):"
               else echo "  v$SRC_VER retires this file; its successor is $note. Your changes to it (against v$BASE_VER):"; fi
               sed 's/^/    /' "$UPG/$f.carry"
               [ -f "$UPG/$f.head" ] && echo "  Yours is the working copy; HEAD's copy (your fork) is .sumela/.upgrade/$f.head"
               echo "  Move the hunks you still want, then drop the orphan, or keep it." ;;
  esac
  while :; do
    if [ "$a" = carry ]; then printf '[k]eep the orphan / [d]rop it after moving the hunks / [s]kip: '
    else printf '[k]eep / [m]erged (after editing .merge) / [t]heirs (type the path to confirm) / [d]iff / [s]kip: '; fi
    if ! read -r ans; then EOF_SEEN=true; echo ""; info "no answer (end of input): $f skipped"; decide "$f" skip; return; fi
    ans="${ans%$'\r'}"
    case "$a:$ans" in
      *:k|*:K) decide "$f" keep; return ;;
      *:s|*:S) decide "$f" skip; return ;;
      carry:d|carry:D)
        printf 'Remove %s? Its hunks stay in %s. [y/N]: ' "$f" "$(artifact_of carry "$f")"
        if ! read -r ans; then EOF_SEEN=true; echo ""; decide "$f" skip; return; fi
        case "${ans%$'\r'}" in y|Y) decide "$f" drop; return ;; esac ;;
      carry:*) invalid_answer bad && { decide "$f" skip; return; }; echo "  Answer k, d or s." ;;
      *:m|*:M) merged_ok "$f" && { decide "$f" merged; return; } ;;
      *:t|*:T)
        printf 'Type the path to replace it with upstream'"'"'s copy (%s): ' "$f"
        if ! read -r p; then EOF_SEEN=true; echo ""; decide "$f" skip; return; fi
        if [ "${p%$'\r'}" = "$f" ]; then decide "$f" theirs; return; fi
        echo "  Not confirmed: the path did not match." ;;
      *:d|*:D) show_diff "$f" "$tf" ;;
      *) invalid_answer bad && { decide "$f" skip; return; }; echo "  Answer k, m, t, d or s." ;;
    esac
  done
}
# invalid_answer <counter-var>: counts one more answer that is no choice. The third in a row is taken
# as the end of input (as `yes | update.sh` would loop forever): nothing more is decided.
invalid_answer() {
  eval "$1=\$((\$$1 + 1))"
  if [ "$(eval "printf '%s' \"\$$1\"")" -ge 3 ]; then
    EOF_SEEN=true; info "three answers that are none of the choices: taken as no answer, so nothing more is decided"
    return 0
  fi
  return 1
}
if [ "$N_WAIT" -gt 0 ]; then
  if [ "$ASSUME_YES" = true ]; then
    echo ""; warn "--yes never decides these $N_WAIT file(s): each keeps your copy and waits for a decision."
  else
    echo ""
    _ans="" _bad=0
    while :; do
      printf '%s file(s) need your decision. [r]eview each / [s]kip all (VERSION stays %s until each is decided): ' "$N_WAIT" "$BASE_VER"
      if ! read -r _ans; then EOF_SEEN=true; echo ""; info "no answer (end of input): every decision deferred"; break; fi
      _ans="${_ans%$'\r'}"
      case "$_ans" in
        ''|r|R|s|S) break ;;
        *) invalid_answer _bad && break; echo "  Answer r or s." ;;
      esac
    done
    if [ "$EOF_SEEN" != true ] && [ "$_ans" != s ] && [ "$_ans" != S ]; then
      while IFS="$TAB" read -r a f tf note <&3; do
        waits "$a" || continue
        [ "$EOF_SEEN" = true ] && { decide "$f" skip; continue; }
        ask_row "$a" "$f" "$tf" "$note"
      done 3< "$WORK/rows"
    fi
  fi
fi

# A file you deleted comes back only on your explicit yes, in a terminal: --yes, an unanswered
# prompt and [s]kip all keep it deleted (kept: declined).
ask_readd() {  # <rel>
  local ans
  printf 'You deleted %s; v%s still ships it. Re-add it? [y/N]: ' "$1" "$SRC_VER"
  if ! read -r ans; then EOF_SEEN=true; echo ""; return 1; fi
  case "${ans%$'\r'}" in y|Y|yes|Yes|YES) return 0 ;; esac
  return 1
}
if [ "$ASSUME_YES" != true ] && [ "$EOF_SEEN" != true ] && [ "${_ans:-}" != s ] && [ "${_ans:-}" != S ]; then
  while IFS="$TAB" read -r a f tf note <&3; do
    [ "$a" = readd ] || continue
    [ "$EOF_SEEN" = true ] && break
    if ask_readd "$f"; then decide "$f" readd; fi
  done 3< "$WORK/rows"
fi

# --- Apply -------------------------------------------------------------------------------
: > "$WORK/cls.files"; : > "$WORK/cls.merged"; : > "$WORK/cls.kept"; : > "$WORK/cls.theirs"; : > "$WORK/cls.removed"; : > "$WORK/unresolved"
cls() { if [ $# -ge 3 ]; then printf '%s\t%s\n' "$2" "$3" >> "$WORK/cls.$1"; else printf '%s\n' "$2" >> "$WORK/cls.$1"; fi; }
# Paths an earlier pass of this upgrade vendored (a re-run is pending), or the run that installed
# the release being re-checked (--force) did: still upstream's bytes, so still vouched for.
PRIOR=""
if [ "$(rec_get pending_rerun)" = true ] || { [ "$REC_SCHEMA" = 2 ] && [ "$REC_VER" = "$SRC_VER" ]; }; then
  PRIOR="$(sumela_record_files "$REC")"
fi
in_prior() { [ -n "$PRIOR" ] && printf '%s\n' "$PRIOR" | LC_ALL=C grep -qxF -- "$1"; }
apply_row() {  # apply_row <action> <rel> <tree-rel> <note>
  local a="$1" f="$2" tf="$3" d settled=true
  case "$a" in
    same)
      if in_prior "$f"; then cls files "$f"
      # ...and it gets back the executable bit the release's file has: git ignores a hook that
      # lost it [RU-I7]. The file is then upstream's in content and mode, so it is vouched for.
      elif [ "$(theirs_mode "$tf")" = 755 ] && [ ! -x "$ROOT/$f" ]; then
        chmod 755 "$ROOT/$f" && [ -x "$ROOT/$f" ] || { err "could not make $f executable"; return 1; }
        cls files "$f"; ok "made    $f executable again (as the release ships it)"
      fi ;;
    readd)
      # You deleted it: it comes back only on your yes, in a terminal.
      if [ "$(decision_of "$f")" = readd ]; then
        install_file "$THEIRS_DIR/$tf" "$f" "$(theirs_mode "$tf")" || return 1
        cls files "$f"; ok "re-added $f (your decision)"
      else
        restore_local "$f" "$tf" || return 1
        cls kept "$f" declined; info "not re-added $f (you deleted it; only your yes in a terminal re-adds it)"
      fi ;;
    add|apply|schema)
      install_file "$THEIRS_DIR/$tf" "$f" "$(theirs_mode "$tf")" || return 1
      cls files "$f"
      case "$a" in add) ok "added   $f" ;; *) ok "updated $f" ;; esac ;;
    merge)
      install_file "$STAGE/$f.merged" "$f" "$(theirs_mode "$tf")" || return 1
      cls merged "$f"; ok "merged  $f (your lines kept)" ;;
    keep)         restore_local "$f" "$tf" || return 1; cls kept "$f" fork ;;
    keep-removed) restore_local "$f" "$tf" || return 1; cls kept "$f" removed-upstream; info "kept    $f (retired upstream; you changed it)" ;;
    floor)        restore_local "$f" "$tf" || return 1; cls kept "$f" updater-floor
                  warn "kept    $f: the release's copy predates v0.20.0, and an updater that old is never installed" ;;
    remove)       remove_file "$f" || return 1; cls removed "$f"; ok "removed $f (retired upstream)" ;;
    conflict|collision|review|carry)
      d="$(decision_of "$f")"
      case "$d" in
        keep)
          restore_local "$f" "$tf" || return 1
          if [ "$a" = carry ]; then cls kept "$f" removed-upstream; else cls kept "$f" conflict:local; fi
          ok "kept    $f (your decision)" ;;
        merged)
          install_file "$UPG/$f.merge" "$f" "$(theirs_mode "$tf")" || return 1
          cls merged "$f"; ok "merged  $f (your edited merge)" ;;
        theirs)
          install_file "$THEIRS_DIR/$tf" "$f" "$(theirs_mode "$tf")" || return 1
          cls theirs "$f"; ok "replaced $f with upstream's copy (your decision)" ;;
        drop)
          remove_file "$f" || return 1; cls removed "$f"; ok "removed $f (your decision; its hunks stay in $(artifact_of carry "$f"))" ;;
        *)
          settled=false
          restore_local "$f" "$tf" || return 1
          # A row that waits whatever its classification is recorded, so a later run still waits
          # for it even when .sumela/.upgrade/ was cleaned away.
          if waits_for_you "$f" "$tf"; then cls kept "$f" pending; fi
          printf '%s\t%s\t%s\n' "$a" "$f" "$(artifact_of "$a" "$f")" >> "$WORK/unresolved" ;;
      esac ;;
    *) err "unknown action '$a' for $f"; return 1 ;;   # never guess on a row
  esac
  # A row settled now no longer waits: HEAD's copy offered for it earlier is not needed again.
  if [ "$settled" = true ]; then rm -f "$UPG/$f.head"; fi
  return 0
}
apply_rows() {  # apply_rows updater|other
  local a f tf note
  while IFS="$TAB" read -r a f tf note <&3; do
    if is_updater "$f"; then [ "$1" = updater ] || continue; else [ "$1" = other ] || continue; fi
    apply_row "$a" "$f" "$tf" "$note" || { FAILED=true; printf 'failed\t%s\t-\n' "$f" >> "$WORK/unresolved"; }
  done 3< "$WORK/rows"
}
echo ""
apply_rows other

# Skill registry: auto-register any newly-added on-disk skills (with consent);
# orphans are reported, not deleted. Rules are NOT auto-reconciled (they need
# phase/stack metadata) — handled by the reminder below. An unanswered prompt changes nothing.
if [ -f "$ROOT/scripts/reconcile-registry.py" ] && command -v python3 >/dev/null 2>&1; then
  reg_out="$(python3 "$ROOT/scripts/reconcile-registry.py" --check 2>&1)"; reg_rc=$?
  if [ "$reg_rc" -ne 0 ]; then
    echo ""; printf '%s\n' "$reg_out" | sed 's/^/  /'
    do_reg=true
    if [ "$ASSUME_YES" != true ]; then
      echo "Reconcile SKILL_REGISTRY.md now (register new skills; orphans only reported)? [Y/n]:"
      if read -r yn; then case "$yn" in n|N) do_reg=false ;; esac
      else do_reg=false; info "no answer (end of input): SKILL_REGISTRY.md left as it is"; fi
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
      if read -r yn; then case "$yn" in n|N) do_shr=false ;; esac
      else do_shr=false; info "no answer (end of input): org-shared rules left as they are"; fi
    fi
    [ "$do_shr" = true ] && python3 "$ROOT/scripts/sync-shared-rules.py" | sed 's/^/  /'
  fi
fi

# The updater and its library, last: before the stamp, so a failed install is never locked in
# behind the version gate, and before the record, because those paths are vendored too.
_inst="$ROOT/scripts/update.sh"
if [ -f "$_inst" ]; then cp "$_inst" "$WORK/installed-updater.before" || exit 1; fi
apply_rows updater
# A new scripts/update.sh defers the stamp unless this run is that updater, or the release's own:
# an older updater used its own CORE list. The deferral lasts until the installed updater runs: an
# older updater's pass never clears it. A pre-0.20 updater is never waited for.
UPDATER_CHANGED=false
if [ -f "$_inst" ] && [ "$RUNNING_IS_THEIRS" != true ] && ! same_text "$WORK/running-updater" "$_inst" &&
   LC_ALL=C grep -qF "$UPDATER_MARK_SH" "$_inst"; then
  if ! same "$WORK/installed-updater.before" "$_inst" || [ "$(rec_get pending_rerun)" = true ]; then UPDATER_CHANGED=true; fi
fi

# --- Finalize: the stamp rule ------------------------------------------------------------------
# VERSION moves only when every CORE file is current, merged, or kept by decision. A new
# scripts/update.sh defers the stamp too (exit 6) unless this run IS the release's updater: an
# older one used its own CORE list, so files that became CORE since may be missing; the re-run
# with the new updater (VERSION unchanged) does a real pass.
write_version() {  # <version>: temp-then-rename, then re-read
  local v="$ROOT/.sumela/VERSION"
  CUR_TMP="$v.sumela-tmp.$$"
  if printf '%s\n' "$1" > "$CUR_TMP" && mv -f "$CUR_TMP" "$v"; then CUR_TMP=""; else rm -f "$CUR_TMP"; CUR_TMP=""; fi
  [ "$(read_ver "$ROOT")" = "$1" ] || { err "could not write .sumela/VERSION ($1)"; return 1; }
}
write_record() {  # write_record <version> complete|partial [--pending-rerun]
  local ver="$1" state="$2" uc
  shift 2
  if [ "$ver" = "$SRC_VER" ] && [ "$state" = complete ]; then uc="$SRC_REF"; else uc="$BASE_COMMIT"; fi
  sumela_record_write "$ver" "$state" "$@" --record "$REC" --base-version "$BASE_VER" --upstream-commit "$uc" \
    --files "$(cat "$WORK/cls.files")" --merged "$(cat "$WORK/cls.merged")" --kept "$(cat "$WORK/cls.kept")" \
    --theirs-over-fork "$(cat "$WORK/cls.theirs")" --removed "$(cat "$WORK/cls.removed")" ||
    { err "could not write the provenance record $REC (the reason is above)"; return 1; }
}
N_UNRES="$(LC_ALL=C awk 'END { print NR }' "$WORK/unresolved")"
EXIT=0 NOTHING=false
_pend=""; [ "$UPDATER_CHANGED" = true ] && _pend="--pending-rerun"
# How to run an updater again, by absolute path from the install root. Never a bare
# "bash scripts/update.sh" when another updater ran: until its row is settled, the install's own
# copy may still be a pre-0.20 updater, which overwrites forks on an empty answer.
_args=""
if [ -n "$SOURCE_DIR" ]; then _args=" --source $(printf '%q' "$SRC")"
elif [ "$REPO_GIVEN" = true ]; then _args=" --repo $(printf '%q' "$REPO_URL")"; fi
RERUN="cd $(printf '%q' "$ROOT") && bash $(printf '%q' "$UPDATER_DIR/$UPDATER_NAME")$_args"
RERUN_NEW="cd $(printf '%q' "$ROOT") && bash $(printf '%q' "$ROOT/scripts/update.sh")$_args"
if [ "$FAILED" = true ] || [ "$N_UNRES" -gt 0 ]; then
  # An older updater's stamp is withdrawn too: the upgrade is not done.
  [ "$SELF_HEAL" = true ] && { write_version "$BASE_VER" || EXIT=1; }
  # shellcheck disable=SC2086
  write_record "$BASE_VER" partial $_pend || EXIT=1
  [ "$EXIT" -eq 0 ] && EXIT=3
elif [ "$UPDATER_CHANGED" = true ]; then
  [ "$SELF_HEAL" = true ] && { write_version "$BASE_VER" || EXIT=1; }
  write_record "$BASE_VER" complete --pending-rerun || EXIT=1
  rm -f "$ROOT/.sumela/.update-check"
  [ "$EXIT" -eq 0 ] && EXIT=6
elif [ "$(LC_ALL=C awk -F '\t' '$1 != "same"' "$WORK/rows" | wc -l | tr -d ' ')" -eq 0 ] && [ ! -s "$WORK/cls.files" ] &&
     [ "$LOCAL_VER" = "$SRC_VER" ] && [ "$REC_SCHEMA" = 2 ] && [ "$REC_VER" = "$SRC_VER" ] && [ "$REC_OPEN" != true ]; then
  NOTHING=true   # a forced re-check that found nothing: the record of the run that installed this version stays
else
  write_version "$SRC_VER" || EXIT=1
  [ "$EXIT" -eq 0 ] && { write_record "$SRC_VER" complete || EXIT=1; }
  # The update-check cache still holds the version we were BEFORE this run, so the next pull
  # would announce an upgrade that already happened. Delete rather than rewrite: _lib.sh owns
  # the "<epoch>\t<remote_ver>" format and re-probes whenever the file is missing.
  rm -f "$ROOT/.sumela/.update-check"
fi

echo ""
if [ -f "$ROOT/scripts/validate-structure.sh" ]; then
  info "Validating structure..."
  bash "$ROOT/scripts/validate-structure.sh" || warn "validate-structure reported issues — review above."
fi

echo ""
if [ "$FAILED" = true ]; then
  err "Some files could not be written (above). VERSION stays $BASE_VER; fix the cause and re-run."
elif [ "$N_UNRES" -gt 0 ]; then
  warn "Partial upgrade: $N_UNRES file(s) wait for your decision; VERSION stays $BASE_VER:"
  LC_ALL=C awk -F '\t' '{ printf "  %-10s %s   (%s)\n", $1, $2, $3 }' "$WORK/unresolved"
  warn "  Each keeps your copy until you decide. To decide them, re-run in a terminal:"
  if [ "$UPDATER_CHANGED" = true ]; then warn "    $RERUN_NEW   (the new updater this run installed)"; else warn "    $RERUN"; fi
elif [ "$UPDATER_CHANGED" = true ]; then
  warn "The updater itself changed upstream, and the NEW scripts/update.sh is installed. This run used an"
  warn "  older one, which cannot know about files that became CORE since. VERSION stays $BASE_VER until the"
  warn "  new updater finishes the upgrade. RE-RUN NOW:"
  warn "    $RERUN_NEW"
elif [ "$NOTHING" = true ]; then
  ok "Nothing to update: the core is current at ${SRC_VER}."
elif [ "$EXIT" -eq 0 ]; then
  ok "Core updated to ${SRC_VER}."
fi
# Keeping a pre-0.20 updater keeps its flaw: it overwrites forks on an empty answer.
if [ -f "$ROOT/scripts/update.sh" ] && LC_ALL=C grep -q "^scripts/update\.sh$TAB" "$WORK/cls.kept" &&
   ! LC_ALL=C grep -qF "$UPDATER_MARK_SH" "$ROOT/scripts/update.sh"; then
  warn "Your scripts/update.sh predates v0.20.0: run with no terminal, it overwrites forks."
  warn "  Install a v0.20.0 or later updater: bash <release clone>/scripts/update.sh --source <release clone>"
fi
# The self-heal fixed the working tree, not the index: what was staged before still commits.
if [ "$SELF_HEAL" = true ] && [ "$IN_GIT" = true ]; then
  _staged="$(git -C "$ROOT" diff --cached --name-only --relative -- .sumela scripts docs/second-brain)"
  if [ -n "$_staged" ]; then
    warn "These paths have changes staged before this run (likely the older updater's); a commit takes the staged copy:"
    printf '%s\n' "$_staged" | head -20 | sed 's/^/  /'
    warn "  Stage this run's result (git add) or unstage them (git restore --staged) before you commit."
  fi
fi
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
echo "Review changes with 'git diff' before committing."
[ "$FAILED" = true ] && EXIT=1
exit "$EXIT"
