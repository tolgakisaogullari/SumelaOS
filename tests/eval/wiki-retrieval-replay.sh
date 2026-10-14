#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/eval/wiki-retrieval-replay.sh — retrieval replay (A14 / Q5). Source-only, maintainer-run.
#
# For each of the newest N specs merged into a base branch, it asks: of the prior specs, plans
# and AD/TD IDs that the spec cites, how many would the second brain's read path have put in
# front of the agent, given only the spec's title, at the commit the spec was written on?
#
#   --path old   (v0.20.0 baseline, R1-15): a fixed-string, case-insensitive grep of the three
#                boot files (_INDEX.md, active-project-context.md, _SEARCH_INDEX.md), lines ranked
#                by how many distinct terms they match; candidates are the spec and plan links and
#                the AD/TD IDs on the ranked lines.
#   --path new   (v0.20.1 gate, R1-33): `sumela-wiki.sh catalog specs|plans --match` and
#                `search`, run against the same extracted tree.
#
# It prints one line of aggregates on stdout and nothing else:
#   recall@20=<x> crosscut_recall@20=<y> specs=<n> path=<old|new>
#
# Read-only: nothing is written to the clone. Each parent commit's files reach a temp
# directory through `git archive` (git cat-file fills in what an export-ignore attribute hides;
# committed symlinks are left out, since they may point anywhere); every git call runs with
# optional locks and auto-gc off, and shallow or partial clones are refused.
#
# Definitions, the scoring formula and how to run it for a release: --help and
# tests/eval/README.md. Self-test: tests/test_replay_harness.sh (synthetic fixtures).
# Exit codes: 0 ok · 1 error (git or the wiki tool failed) · 2 usage · 3 precondition refused.
# -----------------------------------------------------------------------------
set -uo pipefail

PROG="wiki-retrieval-replay"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

K=20               # recall@K: the candidate slots an agent is assumed to follow
CROSSCUT_MIN=3     # an AD cited by at least this many of the N specs is cross-cutting [RQ-22]
MAX_H1_TERMS=8     # at most this many H1 words per spec
MIN_TERM_LEN=3     # in characters: shorter words match almost every line

usage() {
  cat <<'EOF'
Usage: wiki-retrieval-replay.sh --repo <clone> [--n 30] [--path old|new] [--base <ref>]
                                [--terms-file <f>] [--wiki-dir <path>] [--wiki-tool <path>]

Retrieval replay (A14 / Q5). For each of the newest N specs merged into the base, it measures
how many of the prior specs, plans and AD/TD IDs the spec cites the second brain's read path
would have surfaced from the spec's title alone, at the commit the spec was written on.

Options
  --repo <clone>      The top level of a full git clone (work tree or bare). Never written to.
  --n <N>             How many of the newest merged specs to replay (default 30).
  --path old|new      old: grep the three boot files (default). new: sumela-wiki.sh
                      `catalog specs|plans --match` and `search` (v0.20.1 and later).
  --base <ref>        The base branch whose first-parent history holds the merged specs
                      (default: origin/HEAD; else HEAD, with a note in a non-bare clone, where
                      HEAD may be a feature branch). Pass a commit SHA to pin the window, so an
                      old-path and a new-path run replay exactly the same specs.
  --terms-file <f>    Extra query terms. A line "<words>" adds them for every spec, a line
                      "<spec-file-name><TAB><words>" adds them for that spec only, a line
                      "-<words>" drops those words from every spec's title words, "#" starts
                      a comment.
  --wiki-dir <path>   The repo-relative wiki directory (default: $WIKI_PATH, else
                      docs/second-brain/wiki). Specs and plans are read from the sibling
                      artifacts/ directory.
  --wiki-tool <path>  The sumela-wiki.sh to run for --path new (default: this checkout's
                      .sumela/skills/using-second-brain/scripts/sumela-wiki.sh).
  -h, --help          This text.

What it measures
  Specs        The newest N *.md files added under <artifacts>/specs/ on the base's
               first-parent history (a merge counts at the merge). Its parent commit P is the
               first parent of the commit that added the file: the tree the author worked on.
  Cited set    The spec and plan files the spec references (links, wikilinks or bare paths)
               plus the AD-n and TD-n IDs it names, kept only when they already existed at P
               (its own new IDs and its own later plan cannot be retrieved by anything).
  Cross-cut    ADs that at least 3 of the N specs cite as prior context: an AD counts for a
               spec only if it existed at that spec's P, so an AD that one of the N specs
               introduces counts only its later citers. crosscut_recall@20 is the recall of
               those alone, because a grep on feature nouns misses them.
  Terms        The H1 words of the spec (or its file name's, without an H1): Latin letters
               folded to ASCII and lower-cased, other scripts kept as written; non-ASCII
               punctuation separates words (U+0080-00BF, U+00D7, U+00F7, U+2000-2BFF,
               U+2E00-2E7F, the CJK punctuation of U+3000-303F, the fullwidth punctuation of
               U+FF01-FF65); at least 3 characters, numbers skipped, at most 8. Then the
               terms file.
  Recall       Per spec: the share of its cited set among the path's first 20 candidates.
               recall@20 is the mean over specs with a non-empty cited set; crosscut_recall@20
               the mean over specs that cite a cross-cutting AD; n/a when there are none.
               specs=<n> is the number of specs replayed.

Output (stdout): one line, aggregates only; no spec, term, ID, path or branch name.
  recall@20=<x> crosscut_recall@20=<y> specs=<n> path=<old|new>

Notes (stderr): the default base fell back to HEAD; k of n parent commits had no boot file
(old) or no wiki directory (new); files read past an export-ignore attribute; committed
symlinks left out; and every distinct line sumela-wiki.sh printed on stderr.

Read-only and private: each parent commit is read into a temp directory (git archive, with
git cat-file for files an export-ignore attribute hides) and deleted on exit. Committed
symlinks are left out of it: a link may point anywhere, the clone included. Every git call
runs with optional locks, auto-gc and background maintenance off. A shallow clone (its
boundary commit would seem to add every older spec) and a partial clone (git may fetch
missing blobs from the remote) are refused. sumela-wiki.sh runs with WIKI_PATH set to the
replayed wiki, SUMELA_SUMMARIES_DIR unset, and no git repository discoverable from the
replay tree. Messages on stderr may name files or refs of the clone.

Cost: a few git calls and one archive per spec; with 1 MB boot files, 30 specs take about
11 s on a laptop. No network, no model calls.

Exit codes: 0 ok · 1 error (git or the wiki tool failed, or the commit that added a spec was
not found) · 2 usage (including a --repo below the top level of its clone) · 3 precondition
refused (not a git repository, a shallow or partial clone, unknown base, no merged specs, no
boot file (old) or wiki directory (new) at any parent commit, or no wiki tool for --path new).
EOF
}

die() { local code="$1"; shift; printf '%s: %s\n' "$PROG" "$*" >&2; exit "$code"; }
note() { printf '%s: note: %s\n' "$PROG" "$*" >&2; }

# --- arguments ----------------------------------------------------------------------------------
REPO="" NSPEC=30 MODE=old BASE="" TERMS_FILE="" WIKI="${WIKI_PATH:-docs/second-brain/wiki}" TOOL=""
need_value() { [ "$2" -ge 2 ] || die 2 "$1 needs a value (see --help)"; }
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)      usage; exit 0 ;;
    --repo)         need_value "$1" $#; REPO="$2"; shift 2 ;;
    --repo=*)       REPO="${1#*=}"; shift ;;
    --n)            need_value "$1" $#; NSPEC="$2"; shift 2 ;;
    --n=*)          NSPEC="${1#*=}"; shift ;;
    --path)         need_value "$1" $#; MODE="$2"; shift 2 ;;
    --path=*)       MODE="${1#*=}"; shift ;;
    --base)         need_value "$1" $#; BASE="$2"; shift 2 ;;
    --base=*)       BASE="${1#*=}"; shift ;;
    --terms-file)   need_value "$1" $#; TERMS_FILE="$2"; shift 2 ;;
    --terms-file=*) TERMS_FILE="${1#*=}"; shift ;;
    --wiki-dir)     need_value "$1" $#; WIKI="$2"; shift 2 ;;
    --wiki-dir=*)   WIKI="${1#*=}"; shift ;;
    --wiki-tool)    need_value "$1" $#; TOOL="$2"; shift 2 ;;
    --wiki-tool=*)  TOOL="${1#*=}"; shift ;;
    *)              die 2 "unknown argument: $1 (see --help)" ;;
  esac
done

[ -n "$REPO" ] || die 2 "missing --repo <clone> (see --help)"
case "$NSPEC" in ''|*[!0-9]*) die 2 "--n must be a positive integer" ;; esac
[ "$NSPEC" -ge 1 ] 2>/dev/null || die 2 "--n must be a positive integer"
case "$MODE" in old|new) ;; *) die 2 "--path must be old or new" ;; esac
if [ -n "$TERMS_FILE" ]; then
  [ -f "$TERMS_FILE" ] && [ -r "$TERMS_FILE" ] || die 2 "--terms-file is not a readable file"
  TERMS_FILE="$(cd "$(dirname "$TERMS_FILE")" && pwd)/$(basename "$TERMS_FILE")"
fi
WIKI="${WIKI#./}"; while [ "${WIKI%/}" != "$WIKI" ]; do WIKI="${WIKI%/}"; done
case "$WIKI" in ''|/*|[A-Za-z]:*|*..*) die 2 "--wiki-dir must be a repo-relative path inside the repository" ;; esac
case "$WIKI" in */*) ART="${WIKI%/*}/artifacts" ;; *) ART="artifacts" ;; esac

# --- environment: read-only git, bytes not locale ------------------------------------------------
export LC_ALL=C
export GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0
# Every pathspec here is a literal path: as a glob, a spec named "x[1].md" would also match
# "x1.md", and the adding-commit lookup could return the other file's commit.
export GIT_LITERAL_PATHSPECS=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE 2>/dev/null || true
# The wiki tool honours it (R1-16); a replay reads the parent commit's summaries, never live ones.
unset SUMELA_SUMMARIES_DIR 2>/dev/null || true

[ -d "$REPO" ] || die 3 "--repo is not a directory"
g() {
  git -C "$REPO" -c core.quotePath=false -c log.follow=false -c log.showSignature=false \
      -c color.ui=never -c gc.auto=0 -c maintenance.auto=false -c core.fsmonitor=false "$@"
}
g rev-parse --git-dir >/dev/null 2>&1 || die 3 "--repo is not a git repository"
# Below the top level, pathspecs are relative to the subdirectory while git prints paths from
# the top: the adding-commit lookup would silently miss and replay the wrong tree.
if [ "$(g rev-parse --is-inside-work-tree 2>/dev/null)" = true ] && [ -n "$(g rev-parse --show-prefix 2>/dev/null)" ]; then
  die 2 "--repo must be the top level of its clone, not a subdirectory: $(g rev-parse --show-toplevel 2>/dev/null)"
fi
[ "$(g rev-parse --is-shallow-repository 2>/dev/null)" != true ] \
  || die 3 "shallow clone: its boundary commit would seem to add every older spec; run git fetch --unshallow"
if [ -n "$(g config --get extensions.partialclone 2>/dev/null)" ] \
   || g config --bool --get-regexp '^remote\..*\.promisor$' 2>/dev/null | awk '$2 == "true" { f = 1 } END { exit !f }'; then
  die 3 "partial clone: git may fetch missing blobs from the remote; run on a full clone"
fi

if [ -n "$BASE" ]; then
  BASE_SHA="$(g rev-parse -q --verify "$BASE^{commit}" 2>/dev/null)" || die 3 "base ref not found: $BASE"
elif BASE_SHA="$(g rev-parse -q --verify "origin/HEAD^{commit}" 2>/dev/null)"; then
  :
elif BASE_SHA="$(g rev-parse -q --verify "HEAD^{commit}" 2>/dev/null)"; then
  [ "$(g rev-parse --is-bare-repository 2>/dev/null)" = true ] \
    || note "origin/HEAD is not set, so the base is the checked-out HEAD; if that is not the base branch, pass --base <ref>"
else
  die 3 "no base: the clone has neither origin/HEAD nor a HEAD commit (pass --base)"
fi

if [ "$MODE" = new ]; then
  [ -n "$TOOL" ] || TOOL="$SRC_ROOT/.sumela/skills/using-second-brain/scripts/sumela-wiki.sh"
  [ -f "$TOOL" ] || die 3 "--path new needs sumela-wiki.sh (catalog and search ship in v0.20.1); not found: $TOOL"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sumela-replay.XXXXXX")" || die 1 "cannot create a temp directory"
# flush_tool_err: the wiki tool's stderr from its successful calls, once per distinct line. It
# runs at the end, and from the EXIT trap, so no tool output is lost on an error path either.
flush_tool_err() {
  [ -s "$TMP/tool.err" ] || return 0
  awk -v p="$PROG: sumela-wiki.sh: " '{ sub(/\r$/, "") } $0 != "" && !seen[$0]++ { print p $0 }' "$TMP/tool.err" >&2
  : > "$TMP/tool.err"
}
trap 'flush_tool_err; rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- awk programs (written once; LC_ALL=C makes every length, index and substr count bytes) ------
cat > "$TMP/lib.awk" <<'AWK'
# Shared helpers. Every text is normalised by norm() before it is matched or keyed, so a CRLF
# checkout, a capital letter or an accented Latin letter never changes a result.
function lib_init(    r, n, i) {
  NFOLD = 0
  n = split("a a a a a a ae c e e e e i i i i d n o o o o o - o u u u u y th ss a a a a a a ae c e e e e i i i i d n o o o o o - o u u u u y th y", r, " ")
  for (i = 1; i <= n; i++) if (r[i] != "-") fold_add(195, 127 + i, r[i])   # U+00C0-00FF
  n = split("a a a a a a c c c c c c c c d d d d e e e e e e e e e e g g g g g g g g h h h h i i i i i i i i i i ij ij j j k k k l l l l l l l", r, " ")
  for (i = 1; i <= n; i++) fold_add(196, 127 + i, r[i])                      # U+0100-013F
  n = split("l l l n n n n n n n n n o o o o o o oe oe r r r r r r s s s s s s s s t t t t t t u u u u u u u u u u u u w w y y y z z z z z z s", r, " ")
  for (i = 1; i <= n; i++) fold_add(197, 127 + i, r[i])                      # U+0140-017F
  n = split("s s t t", r, " ")
  for (i = 1; i <= n; i++) fold_add(200, 151 + i, r[i])                      # U+0218-021B
  LEAD1 = sprintf("%c", 195); LEAD2 = sprintf("%c", 196); LEAD3 = sprintf("%c", 197); LEAD4 = sprintf("%c", 200)
  BOM = sprintf("%c%c%c", 239, 187, 191)
  # Words: ASCII letters and digits, plus every byte of a non-ASCII character, so a word in another
  # script stays a term (matched as written). Non-ASCII punctuation is a separator, by UTF-8 bytes:
  #   C2 xx      U+0080-00BF  NBSP, guillemets, the middle dot, the copyright sign
  #   C3 97, B7  U+00D7, F7   the multiplication and division signs
  #   E2 80-AF   U+2000-2BFF  dashes, quotes, ellipsis, arrows, symbols (not U+2C00-2DFF: Latin
  #                           Extended-C, Glagolitic, Coptic and Tifinagh are letters)
  #   E2 B8-B9   U+2E00-2E7F  supplemental punctuation
  #   E3 80 xx   U+3000-303F  the ideographic space, 、。, brackets, quotes (not the iteration and
  #                           masu marks, the Hangzhou numerals or the tone marks, which are word parts)
  #   EF BC, BD  U+FF01-FF65  fullwidth ASCII punctuation and the halfwidth CJK punctuation
  CB = "[" sprintf("%c", 128) "-" sprintf("%c", 191) "]"
  WORD_SPLIT = "[^a-z0-9" sprintf("%c", 128) "-" sprintf("%c", 255) "]+"
  PUNCT_RE = sprintf("%c", 194) CB
  PUNCT_RE = PUNCT_RE "|" sprintf("%c%c", 195, 151) "|" sprintf("%c%c", 195, 183)
  PUNCT_RE = PUNCT_RE "|" sprintf("%c[%c-%c]", 226, 128, 175) CB "|" sprintf("%c[%c-%c]", 226, 184, 185) CB
  PUNCT_RE = PUNCT_RE "|" sprintf("%c%c[%c-%c%c-%c%c%c-%c%c-%c]", 227, 128, 128, 132, 136, 160, 176, 182, 183, 189, 191)
  PUNCT_RE = PUNCT_RE "|" sprintf("%c%c[%c-%c%c-%c%c-%c]", 239, 188, 129, 143, 154, 160, 187, 191)
  PUNCT_RE = PUNCT_RE "|" sprintf("%c%c[%c%c-%c]", 239, 189, 128, 155, 165)
  # A key token: a specs/ or plans/ path, an AD/TD ID, a wikilink target, or a same-directory
  # markdown link. Brackets stand in for escapes, which POSIX leaves undefined outside them.
  KEY_RE = "(specs|plans)/[a-z0-9._/-]*[a-z0-9]|(ad|td)-[0-9]+|[[][[][^]|#]+|[]][(](\\./)?[^)#/ ]+\\.md[#)]"
}
function fold_add(lead, second, to) { NFOLD++; FOLD_FROM[NFOLD] = sprintf("%c%c", lead, second); FOLD_TO[NFOLD] = to }
function norm(s,    i) {   # strip a trailing CR, fold Latin letters to ASCII, lower-case
  sub(/\r$/, "", s)
  if (index(s, LEAD1) || index(s, LEAD2) || index(s, LEAD3) || index(s, LEAD4))
    for (i = 1; i <= NFOLD; i++) if (index(s, FOLD_FROM[i])) gsub(FOLD_FROM[i], FOLD_TO[i], s)
  return tolower(s)
}
function name_of(path,    n, p) {   # "dir/2026-01-05-x.md" -> "2026-01-05-x"
  n = split(path, p, "/"); path = p[n]; sub(/\.md$/, "", path); return path
}
function self_key(    s) { s = norm(ENVIRON["RP_SLUG"]); return "spec:" name_of(s) }
# The specs and plans that exist at the parent commit: PRIOR[kind:name], and AK[name] = spec,
# plan or both, which resolves a wikilink that names a file without its directory.
function load_artifacts(path, root,    line, rel, kind, name) {
  if (path == "") return
  while ((getline line < path) > 0) {
    sub(/\r$/, "", line)
    if (substr(line, 1, length(root) + 1) != root "/") continue
    rel = substr(line, length(root) + 2)
    if (substr(rel, 1, 6) == "specs/") kind = "spec"; else if (substr(rel, 1, 6) == "plans/") kind = "plan"; else continue
    name = norm(rel)
    if (name !~ /\.md$/) continue
    name = name_of(name)
    if (name == "") continue
    PRIOR[kind ":" name] = 1
    if (!(name in AK)) AK[name] = kind; else if (AK[name] != kind) AK[name] = "both"
  }
  close(path)
}
function add_key(k) { NK++; KO[NK] = k }
# scan(s, samedir): the keys in a normalised line, left to right, into KO[1..NK]. samedir is the
# kind a bare "](name.md)" link resolves to ("spec" inside a spec; "" in a wiki page).
function scan(s, samedir,    pos, rest, st, len, tok, pre, post, t, num, c2) {
  NK = 0
  pos = 1
  while (pos <= length(s)) {
    rest = substr(s, pos)
    if (!match(rest, KEY_RE)) break
    st = pos + RSTART - 1; len = RLENGTH
    tok = substr(s, st, len); c2 = substr(tok, 1, 2)
    pre = (st > 1) ? substr(s, st - 1, 1) : ""
    post = substr(s, st + len, 1)
    if (c2 == "[[") {                      # [[name]], [[name|alias]], [[name#heading]]
      t = substr(tok, 3); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); sub(/\.md$/, "", t)
      if (index(t, "/") == 0 && (t in AK)) {
        if (AK[t] != "plan") add_key("spec:" t)
        if (AK[t] != "spec") add_key("plan:" t)
      }
      pos = st + 2                         # a path inside the brackets is matched next
    } else if (c2 == "](") {
      if (samedir != "") { t = substr(tok, 3); sub(/^\.\//, "", t); sub(/\.md[#)]$/, "", t); if (t != "") add_key(samedir ":" t) }
      pos = st + 2
    } else if (c2 == "ad" || c2 == "td") {
      if (pre !~ /[a-z0-9_]/ && post !~ /[a-z0-9_]/) {
        num = substr(tok, 4); sub(/^0+/, "", num); if (num == "") num = "0"
        add_key(c2 ":" num)
      }
      pos = st + len
    } else if (pre ~ /[a-z0-9_.-]/) {      # "subspecs/", "my-plans/": not the artifacts dirs
      pos = st + 1
    } else {
      t = name_of(tok)
      if (t != "") add_key((c2 == "sp" ? "spec" : "plan") ":" t)
      pos = st + len
    }
  }
  return NK
}
AWK

cat > "$TMP/terms.awk" <<'AWK'
# terms.awk <spec>: the query terms, one per line. The H1 words (or the file name's words when
# the spec has no H1), then the terms file. RP_SLUG names the spec; RP_TERMS_FILE is optional.
BEGIN {
  lib_init()
  MAXH1 = ENVIRON["RP_MAX"] + 0; MINLEN = ENVIRON["RP_MINLEN"] + 0
  slug = name_of(norm(ENVIRON["RP_SLUG"]))
  tf = ENVIRON["RP_TERMS_FILE"]; ntl = 0
  if (tf != "") {
    while ((getline l < tf) > 0) {
      sub(/\r$/, "", l)
      if (l ~ /^[ \t]*(#|$)/) continue
      if (l ~ /^[ \t]*-/) { sub(/^[ \t]*-/, "", l); nw = words(l, w); for (i = 1; i <= nw; i++) if (w[i] != "") DROP[w[i]] = 1; continue }
      if (index(l, "\t")) {
        key = substr(l, 1, index(l, "\t") - 1); sub(/^[ ]+/, "", key); sub(/[ ]+$/, "", key)
        if (name_of(norm(key)) != slug) continue
        l = substr(l, index(l, "\t") + 1)
      }
      TL[++ntl] = l
    }
    close(tf)
  }
}
{ line = $0; sub(/\r$/, "", line) }
NR == 1 && index(line, BOM) == 1 { line = substr(line, 4) }
NR == 1 && line == "---" { infm = 1; next }
infm { if (line == "---" || line == "...") infm = 0; next }
line ~ /^[ \t]*(```|~~~)/ { fence = !fence; next }
fence { next }
!found && line ~ /^#[ \t]/ { h1 = substr(line, 3); found = 1 }
END {
  if (!found) { h1 = slug; sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-/, "", h1) }
  add_words(h1, MAXH1)
  for (i = 1; i <= ntl; i++) add_words(TL[i], 0)
}
function words(text, w) { text = norm(text); gsub(PUNCT_RE, " ", text); return split(text, w, WORD_SPLIT) }
function add_words(text, max,    n, w, i, t, chars, added) {
  n = words(text, w); added = 0
  for (i = 1; i <= n; i++) {
    if (max && added >= max) break
    t = w[i]
    chars = t; gsub(CB, "", chars)         # characters, not bytes: drop UTF-8 continuation bytes
    if (length(chars) < MINLEN || t ~ /^[0-9]+$/ || (t in DROP) || (t in SEEN)) continue
    SEEN[t] = 1; print t; added++
  }
}
AWK

cat > "$TMP/cited.awk" <<'AWK'
# cited.awk <spec>: the spec's cited set, keeping only what existed at the parent commit.
# RP_ART_LIST: the parent's spec and plan paths; RP_IDS: the parent's lines naming an AD/TD ID.
BEGIN {
  lib_init()
  load_artifacts(ENVIRON["RP_ART_LIST"], ENVIRON["RP_ART_ROOT"])
  ids = ENVIRON["RP_IDS"]
  if (ids != "") {
    while ((getline l < ids) > 0) { n = scan(norm(l), ""); for (i = 1; i <= n; i++) if (KO[i] ~ /^(ad|td):/) PRIOR[KO[i]] = 1 }
    close(ids)
  }
  self = self_key()
}
{ n = scan(norm($0), "spec")
  for (i = 1; i <= n; i++) { k = KO[i]; if (k != self && (k in PRIOR) && !(k in done)) { done[k] = 1; print k } } }
AWK

cat > "$TMP/rank.awk" <<'AWK'
# rank.awk <boot files in order>: the old path. A line matches when it contains a term as a
# fixed string after normalisation (grep -i -F, with Latin letters folded on both sides); lines
# rank by how many distinct terms they contain, then by file order and line number. The first
# K distinct keys on the ranked lines are the candidates.
BEGIN {
  lib_init()
  load_artifacts(ENVIRON["RP_ART_LIST"], ENVIRON["RP_ART_ROOT"])
  K = ENVIRON["RP_K"] + 0; self = self_key(); nt = 0
  tf = ENVIRON["RP_TERMS"]
  while ((getline t < tf) > 0) if (t != "") T[++nt] = t
  close(tf)
  if (nt == 0) exit
}
{ line = norm($0); c = 0
  for (i = 1; i <= nt; i++) if (index(line, T[i])) c++
  if (c) { nb[c]++; B[c, nb[c]] = line; if (c > maxc) maxc = c } }
END {
  out = 0
  for (c = maxc; c >= 1 && out < K; c--)
    for (j = 1; j <= nb[c] && out < K; j++) {
      n = scan(B[c, j], "")
      for (x = 1; x <= n && out < K; x++) {
        k = KO[x]
        if (k == self || (k in done)) continue
        done[k] = 1; print k; out++
      }
    }
}
AWK

cat > "$TMP/newpath.awk" <<'AWK'
# newpath.awk: the new path's candidates from sumela-wiki.sh output, per R1-18's contract:
#   catalog: "<date> · <slug> · <H1>"        search: "<score> · <path> · <terms> · <first line>"
# The three lists interleave (search, catalog specs, catalog plans, then each one's second
# entry, ...). Lines of any other shape (cut markers, hints) are skipped and counted, so a run
# whose output never parses fails instead of scoring zero.
BEGIN {
  lib_init()
  load_artifacts(ENVIRON["RP_ART_LIST"], ENVIRON["RP_ART_ROOT"])
  K = ENVIRON["RP_K"] + 0; self = self_key()
  SEP = " " sprintf("%c%c", 194, 183) " "
  parsed = 0; other = 0
  ns = read_search(ENVIRON["RP_SEARCH"])
  nc = read_catalog(ENVIRON["RP_CAT_SPECS"], "spec", "C1")
  np = read_catalog(ENVIRON["RP_CAT_PLANS"], "plan", "C2")
  max = ns; if (nc > max) max = nc; if (np > max) max = np
  out = 0
  for (r = 1; r <= max && out < K; r++) {
    if (r <= ns) emit(L["S", r])
    if (r <= nc) emit(L["C1", r])
    if (r <= np) emit(L["C2", r])
  }
  statf = ENVIRON["RP_STATS"]
  printf "%d %d\n", parsed, other > statf
  close(statf)
  exit
}
function emit(keys,    n, a, i) {
  n = split(keys, a, " ")
  for (i = 1; i <= n && out < K; i++) if (a[i] != "" && a[i] != self && !(a[i] in done)) { done[a[i]] = 1; print a[i]; out++ }
}
function resolve(kind, name, date) {   # a catalog slug may or may not carry its date prefix
  if ((kind ":" name) in PRIOR) return kind ":" name
  if (date != "" && (kind ":" date "-" name) in PRIOR) return kind ":" date "-" name
  return kind ":" name
}
function read_catalog(path, kind, tag,    l, f, n, cnt, d) {
  cnt = 0
  if (path == "") return 0
  while ((getline l < path) > 0) {
    sub(/\r$/, "", l); if (l == "") continue
    n = split(l, f, SEP)
    if (n >= 3 && f[1] ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) {
      d = substr(f[1], 1, 10)
      parsed++; L[tag, ++cnt] = resolve(kind, name_of(norm(f[2])), d)
    } else other++
  }
  close(path)
  return cnt
}
function read_search(path,    l, f, n, cnt, keys, i, j, first) {
  cnt = 0
  if (path == "") return 0
  while ((getline l < path) > 0) {
    sub(/\r$/, "", l); if (l == "") continue
    n = split(l, f, SEP)
    if (n >= 4 && f[1] ~ /^[0-9]+([.][0-9]+)?$/) {
      parsed++; keys = ""
      j = scan(norm(f[2]), "")
      for (i = 1; i <= j; i++) keys = keys " " KO[i]
      if (j == 0) {                      # a wiki page: the IDs on its first matching line
        first = f[4]; for (i = 5; i <= n; i++) first = first SEP f[i]
        j = scan(norm(first), "")
        for (i = 1; i <= j; i++) if (KO[i] ~ /^(ad|td):/) keys = keys " " KO[i]
      }
      L["S", ++cnt] = keys
    } else other++
  }
  close(path)
  return cnt
}
AWK

cat > "$TMP/agg.awk" <<'AWK'
# agg.awk <rows>: "<spec#><TAB>c<TAB><key>" (cited) and "<spec#><TAB>t<TAB><key>" (candidate).
BEGIN { FS = "\t" }
$2 == "c" { nl[$1]++; L[$1, nl[$1]] = $3; if ($3 ~ /^ad:/) adn[$3]++; next }
$2 == "t" { T[$1, $3] = 1; next }
END {
  for (a in adn) if (adn[a] >= ccmin) CC[a] = 1
  for (i = 1; i <= n; i++) {
    if (!nl[i]) continue
    h = 0; cn = 0; ch = 0
    for (j = 1; j <= nl[i]; j++) {
      key = L[i, j]; hit = ((i, key) in T)
      h += hit
      if (key in CC) { cn++; ch += hit }
    }
    rs += h / nl[i]; rn++
    if (cn) { cs += ch / cn; cm++ }
  }
  printf "recall@%d=%s crosscut_recall@%d=%s specs=%d path=%s\n", k, (rn ? sprintf("%.3f", rs / rn) : "n/a"),
         k, (cm ? sprintf("%.3f", cs / cm) : "n/a"), n, path
}
AWK

# --- helpers -------------------------------------------------------------------------------------
HIDDEN=0   # files git archive omitted (export-ignore) and git cat-file supplied
# extract <commit> <dest> <path>...: the regular files under <path>... at <commit>, laid out as in
# the repo. A committed symlink is left out (its target may be anywhere, the clone included) and
# listed in $TMP/symlinks; no write ever goes through one.
extract() {
  local c="$1" dest="$2" p f rc out; shift 2
  local have=()
  mkdir -p "$dest" || return 1
  for p in "$@"; do
    out="$(g ls-tree --name-only "$c" -- "$p")" || return 1
    [ -n "$out" ] && have+=("$p")
  done
  [ ${#have[@]} -gt 0 ] || return 0
  g ls-tree -r -z "$c" -- "${have[@]}" > "$dest.lstree" || return 1
  tr '\0' '\n' < "$dest.lstree" \
    | awk -F '\t' '{ split($1, m, " ") } m[2] == "blob" && (m[1] == "100644" || m[1] == "100755") { print $2 }' \
    > "$dest.files" || return 1
  g archive --format=tar "$c" -- "${have[@]}" | tar -xf - -C "$dest"
  rc=("${PIPESTATUS[@]}")
  [ "${rc[0]}" -eq 0 ] && [ "${rc[1]}" -eq 0 ] || return 1
  ( cd "$dest" && find . -type l -print ) > "$dest.links" || return 1
  if [ -s "$dest.links" ]; then
    ( cd "$dest" && find . -type l -exec rm -f {} + ) || return 1
    sed 's|^\./||' "$dest.links" >> "$TMP/symlinks" || return 1
  fi
  while IFS= read -r f; do
    [ -L "$dest/$f" ] && continue          # never write through a link
    [ -f "$dest/$f" ] && continue
    mkdir -p "$dest/$(dirname "$f")" && g cat-file blob "$c:$f" < /dev/null > "$dest/$f" || return 1
    HIDDEN=$((HIDDEN + 1))
  done < "$dest.files"
  return 0
}

tag() { awk -v i="$1" -v t="$2" '{ printf "%s\t%s\t%s\n", i, t, $0 }'; }   # tag <spec#> <c|t>

# run_tool <out> <dir> <subcommand...>: one sumela-wiki.sh call against the replay tree. The tool
# sees the replayed wiki only: WIKI_PATH names it, and GIT_CEILING_DIRECTORIES keeps any git
# repository around the temp directory out of its reach. Pathspecs are the harness's business,
# so the tool gets git's default (glob) pathspecs. Its stderr is kept for flush_tool_err.
run_tool() {
  local out="$1" dir="$2" rc; shift 2
  ( unset GIT_LITERAL_PATHSPECS
    WIKI_PATH="$WIKI" GIT_CEILING_DIRECTORIES="$TMP" exec bash "$TOOL" -C "$dir" "$@" ) < /dev/null > "$out" 2> "$out.err"; rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s: sumela-wiki.sh %s failed on a replay tree (exit %s):\n' "$PROG" "$1" "$rc" >&2
    tail -5 "$out.err" >&2
    exit 1
  fi
  if [ -s "$out.err" ]; then cat "$out.err" >> "$TMP/tool.err" || exit 1; fi
  return 0
}

# --- the specs: newest N added on the base's first-parent history --------------------------------
g log -m --first-parent --diff-filter=A -M --name-only --no-color --format='@%H' "$BASE_SHA" -- "$ART/specs/" \
  > "$TMP/log" || die 1 "git log failed on the base"
awk -v n="$NSPEC" '
  /^@/ { c = substr($0, 2); next }
  $0 == "" || /^"/ || !/\.md$/ { next }
  { b = $0; sub(/.*\//, "", b) }
  b == "README.md" || b ~ /^[._]/ || ($0 in seen) { next }
  { seen[$0] = 1; print c "\t" $0; if (++k >= n) exit }' "$TMP/log" > "$TMP/specs"
NREPLAYED="$(awk 'END { print NR }' "$TMP/specs")"
[ "$NREPLAYED" -gt 0 ] || die 3 "no spec was ever added under $ART/specs/ on the base"

# --- replay each spec ----------------------------------------------------------------------------
BOOT=("$WIKI/_INDEX.md" "$WIKI/active-project-context.md" "$WIKI/_SEARCH_INDEX.md")
TOOL_RUNS=0 TOOL_PARSED=0 TOOL_OTHER=0
NPARENT=0    # replays with a parent commit (a spec added by a root commit has none)
NOINPUT=0    # ...whose parent had no boot file (old path) or no wiki directory (new path)
: > "$TMP/agg.tsv"
i=0
while IFS="$(printf '\t')" read -r M SPATH <&3; do
  i=$((i + 1)); d="$TMP/s$i"; mkdir -p "$d" || die 1 "cannot write the temp directory"
  export RP_SLUG="${SPATH##*/}" RP_ART_ROOT="$ART" RP_K="$K"
  C="$(g log -1 --diff-filter=A -M --format=%H "$M" -- "$SPATH")" || die 1 "git log failed for a spec"
  if [ -z "$C" ]; then
    # Only a merge can bring a file in with no adding commit below it (the merge commit itself
    # added it): its tree is then the merge's first parent. Anything else is an error.
    g rev-parse -q --verify "$M^2^{commit}" >/dev/null 2>&1 || die 1 "could not find the commit that added $SPATH"
    C="$M"
  fi
  P="$(g rev-parse -q --verify "$C^1^{commit}" 2>/dev/null)" || P=""
  g cat-file blob "$M:$SPATH" > "$d/spec" || die 1 "git cat-file failed for a spec"

  RP_MAX="$MAX_H1_TERMS" RP_MINLEN="$MIN_TERM_LEN" RP_TERMS_FILE="$TERMS_FILE" \
    awk -f "$TMP/lib.awk" -f "$TMP/terms.awk" "$d/spec" > "$d/terms" || die 1 "term extraction failed"

  if [ -z "$P" ]; then continue; fi          # added by a root commit: nothing was prior to it
  NPARENT=$((NPARENT + 1))

  g ls-tree -r -z --name-only "$P" -- "$ART/specs/" "$ART/plans/" > "$d/art.z" || die 1 "git ls-tree failed"
  tr '\0' '\n' < "$d/art.z" > "$d/art"
  g -c grep.lineNumber=false -c grep.column=false -c grep.fullName=false \
    grep -h -I -i -E -e '(ad|td)-[0-9]' "$P" -- "$WIKI/" "$ART/" > "$d/ids"
  [ $? -le 1 ] || die 1 "git grep failed on a parent commit"
  RP_ART_LIST="$d/art" RP_IDS="$d/ids" awk -f "$TMP/lib.awk" -f "$TMP/cited.awk" "$d/spec" \
    | tag "$i" c >> "$TMP/agg.tsv" || die 1 "citation extraction failed"

  if [ "$MODE" = old ]; then
    extract "$P" "$d/tree" "${BOOT[@]}" || die 1 "could not read the boot files of a parent commit"
    files=()
    for b in "${BOOT[@]}"; do [ -f "$d/tree/$b" ] && files+=("$d/tree/$b"); done
    if [ ${#files[@]} -eq 0 ]; then
      NOINPUT=$((NOINPUT + 1))
    else
      RP_ART_LIST="$d/art" RP_TERMS="$d/terms" awk -f "$TMP/lib.awk" -f "$TMP/rank.awk" "${files[@]}" \
        | tag "$i" t >> "$TMP/agg.tsv" || die 1 "old-path ranking failed"
    fi
  else
    wt="$(g ls-tree "$P" -- "$WIKI")" || die 1 "git ls-tree failed on a parent commit"
    case "$wt" in "040000 tree "*) ;; *) NOINPUT=$((NOINPUT + 1)) ;; esac
    if [ -s "$d/terms" ]; then
      extract "$P" "$d/tree" "$WIKI" "$ART" || die 1 "could not read the wiki of a parent commit"
      mkdir -p "$d/tree/.sumela"            # the tool anchors at the nearest .sumela/
      q="$(awk 'NF { printf "%s%s", s, $0; s = " " }' "$d/terms")"
      run_tool "$d/search" "$d/tree" search "$q"
      run_tool "$d/cat_specs" "$d/tree" catalog specs --match "$q"
      run_tool "$d/cat_plans" "$d/tree" catalog plans --match "$q"
      RP_ART_LIST="$d/art" RP_SEARCH="$d/search" RP_CAT_SPECS="$d/cat_specs" RP_CAT_PLANS="$d/cat_plans" \
        RP_STATS="$d/stats" awk -f "$TMP/lib.awk" -f "$TMP/newpath.awk" \
        | tag "$i" t >> "$TMP/agg.tsv" || die 1 "new-path parsing failed"
      read -r sp so < "$d/stats" || die 1 "new-path parsing left no statistics"
      TOOL_RUNS=$((TOOL_RUNS + 1)); TOOL_PARSED=$((TOOL_PARSED + sp)); TOOL_OTHER=$((TOOL_OTHER + so))
    fi
  fi
  rm -rf "$d/tree"
done 3< "$TMP/specs"

# --- inputs actually read: a typo in --wiki-dir or a stray WIKI_PATH must not pass as a low figure
LINKS=0; [ -s "$TMP/symlinks" ] && LINKS="$(LC_ALL=C sort -u "$TMP/symlinks" | awk 'END { print NR }')"
if [ "$NPARENT" -gt 0 ] && [ "$NOINPUT" -eq "$NPARENT" ]; then
  why="check --wiki-dir / WIKI_PATH"; [ "$LINKS" -eq 0 ] || why="$why; committed symlinks are left out"
  if [ "$MODE" = old ]; then die 3 "no boot file under $WIKI at any parent commit ($why)"
  else die 3 "no $WIKI directory at any parent commit ($why)"; fi
fi
if [ "$MODE" = new ] && [ "$TOOL_RUNS" -gt 0 ] && [ "$TOOL_PARSED" -eq 0 ]; then
  die 1 "sumela-wiki.sh printed no line the harness can parse in $TOOL_RUNS replays ($TOOL_OTHER other lines); expected R1-18's catalog/search output"
fi
if [ "$NOINPUT" -gt 0 ]; then
  if [ "$MODE" = old ]; then note "$NOINPUT of $NPARENT parent commits had no boot file under the wiki directory"
  else note "$NOINPUT of $NPARENT parent commits had no wiki directory"; fi
fi
[ "$HIDDEN" -eq 0 ] || note "$HIDDEN file(s) hidden by an export-ignore attribute were read with git cat-file"
[ "$LINKS" -eq 0 ] || note "$LINKS committed symlink(s) were left out of the replay trees (a link may point anywhere, the clone included)"
flush_tool_err

awk -v n="$NREPLAYED" -v k="$K" -v ccmin="$CROSSCUT_MIN" -v path="$MODE" -f "$TMP/agg.awk" "$TMP/agg.tsv" \
  || die 1 "aggregation failed"
