#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/test_replay_harness.sh — self-test of tests/eval/wiki-retrieval-replay.sh (R1-13, A14).
#
# Builds synthetic consumer histories (generic content, fixture-only names; no model, no network)
# in which every cited item's retrievability is known by construction, then checks the harness
# against hand-computed figures:
#
#   t_synthetic_known_citations_recall_1   every prior citation sits on a line the old path ranks
#                                          in its top 20; also through a merge commit, whose parent
#                                          is the feature-branch commit before the spec
#   t_reads_parent_commit_not_later        a citation that becomes retrievable only in the adding
#                                          commit, after a review edit, at the merge or later stays
#                                          unfound (old path); the new path's tree never holds the
#                                          spec under replay (the stub refuses one that does)
#   t_crosscutting_subset_measured         an AD cited by 3 specs is scored on its own; one cited by
#                                          2 is not; the subset is computed over the replayed window
#   t_never_writes_to_clone                git status, the reflog, refs and every file (incl. .git)
#                                          are unchanged after old- and new-path runs, also when
#                                          committed symlinks point into the clone; the detector
#                                          itself is shown to catch a write
#   plus: ranking by distinct terms and a cut at exactly 20 on both paths (and the new path's
#   interleave), the term rules (characters, separators, the 8-word cap), ID forms, the prior
#   filter, the window rules, terms-file add/drop, CRLF, export-ignore, bare and origin/HEAD
#   clones, the base window, the new path through stub sumela-wiki.sh tools (its stderr, its
#   environment), missing or truncated inputs, usage and precondition exits, cleanup of TMPDIR,
#   and aggregates-only output.
#
# Every expected figure is derived in the comment above its assertion.
# Dependency-free (bash 3.2 + git). Run from anywhere:  bash tests/test_replay_harness.sh
# Exit 0 = all assertions passed, 1 = a failure (printed above).
# -----------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
H="$REPO_ROOT/tests/eval/wiki-retrieval-replay.sh"

[ -f "$H" ] || { echo "FAIL: harness missing: $H"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/no-hooks"
# The developer's environment must not steer the harness or the stub tools.
unset WIKI_PATH SUMELA_SUMMARIES_DIR 2>/dev/null || true

PASS=0 FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

# The fixture's git: no user hooks, signing or autocrlf from the developer's global config.
GITC=(-c core.hooksPath="$WORK/no-hooks" -c commit.gpgsign=false -c tag.gpgsign=false
      -c core.autocrlf=false -c user.name=Fixture -c user.email=fixture@example.com
      -c init.defaultBranch=main)
gx() { git "${GITC[@]}" "$@"; }

# --- fixture builder ------------------------------------------------------------------------------
R="" EOL=lf
fx() { gx -C "$R" "$@"; }
commit() { fx add -A && fx commit -q -m "$1"; }
put() {  # put <path-under-repo>: stdin -> file, in the fixture's line endings
  mkdir -p "$(dirname "$R/$1")"
  if [ "$EOL" = crlf ]; then awk '{ printf "%s\r\n", $0 }' > "$R/$1"; else cat > "$R/$1"; fi
}
add() {  # add <path-under-repo> <line>...: append lines
  local f="$1"; shift
  printf '%s\n' "$@" | if [ "$EOL" = crlf ]; then awk '{ printf "%s\r\n", $0 }'; else cat; fi >> "$R/$f"
}
WI=docs/second-brain/wiki
AR=docs/second-brain/artifacts

# build <dir> <variant>: full | crosscut | rank | crlf | exportignore
#
# main: root (S0 ledger-export spec+plan, AD-01..04, TD-01..02)
#       A  wiki context for S1        C1 spec S1 invoice-retry (+ its index link)
#       └─ feat/payment-webhooks: B1 wiki context for S2 · C2 spec S2 · C2b plan for S2
#       app v2 · merge --no-ff (M2)
#       D  wiki context for S3        C3 spec S3 refund-notifications (+ new AD-05, same commit)
# feat/unmerged: a newer spec that never reaches main (must not be replayed)
#
# Cited sets after the prior filter (what existed at each spec's parent commit):
#   S1 {spec ledger-export-design, plan ledger-export, AD-1, AD-3, TD-2}      (5)
#   S2 {spec invoice-retry-design, AD-2, AD-3, AD-4}   (its own plan is later)  (4)
#   S3 {plan payment-webhooks, AD-3, AD-4}             (AD-5 is its own, new)   (3)
# AD-3 is cited by 3 specs (cross-cutting); AD-4 by 2 (not).
build() {
  local v="$2"
  R="$1"; EOL=lf; [ "$v" = crlf ] && EOL=crlf
  gx init -q -b main "$R" >/dev/null

  put "$WI/_INDEX.md" <<'EOF'
# Wiki Index — fixture

## Core Pages
[[active-project-context]] - Current sprint, next steps.

## Plans & Specs (Immutable Artifacts)

### Active
- [2026-01-05-ledger-export-design](../artifacts/specs/2026-01-05-ledger-export-design.md)
- [2026-01-06-ledger-export](../artifacts/plans/2026-01-06-ledger-export.md)
EOF
  put "$WI/active-project-context.md" <<'EOF'
---
type: core
---

# Active Project Context — fixture

## Active Sprint

- Ledger export shipped.

## Next Steps

1. Pick the next feature.
EOF
  put "$WI/_SEARCH_INDEX.md" <<'EOF'
# Wiki Search Index

| Page | Type | Tags | Key Terms | Summary |
|---|---|---|---|---|
| [[active-project-context]] | core | active-context | current-state | Active sprint snapshot |
EOF
  put "$WI/architecture-decisions.md" <<'EOF'
# Architecture Decisions — fixture

## Decisions

## AD-01: Ledger rows are append-only
**Status:** accepted

## AD-02: Webhook payloads are signed
**Status:** accepted

## AD-03: Every outbound HTTP call goes through the shared gateway client
**Status:** accepted

## AD-04: Notifications are queued, never sent inline
**Status:** accepted
EOF
  put "$WI/tech-debt-and-known-issues.md" <<'EOF'
# Tech Debt — fixture

## TD-01: Report export is slow
## TD-02: Retry backoff is fixed, not exponential
EOF
  put "$AR/specs/2026-01-05-ledger-export-design.md" <<'EOF'
# Ledger export design

Uses AD-01.
EOF
  put "$AR/plans/2026-01-06-ledger-export.md" <<'EOF'
# Ledger export implementation plan
EOF
  printf 'app v1\n' > "$R/src-app.txt"
  [ "$v" = exportignore ] && printf 'docs/** export-ignore\n' > "$R/.gitattributes"
  commit "root"

  # A: S1's context. The rank variant (derived at "ranking ... and the cut at 20" below) puts
  # S1's TD-2 and AD-1 on one two-term line after sixteen noise lines, and adds a one-term line
  # early in file order and an index line that links S1 itself, before S1 exists.
  if [ "$v" = rank ]; then
    add "$WI/_INDEX.md" "- Invoice backoff: AD-199" \
      "- Invoice retry (draft): [2026-02-01-invoice-retry-design](../artifacts/specs/2026-02-01-invoice-retry-design.md)"
    add "$WI/active-project-context.md" \
      "- Invoice retry: next step; see [2026-01-06-ledger-export](../artifacts/plans/2026-01-06-ledger-export.md)."
  else
    add "$WI/active-project-context.md" \
      "- Invoice retry: next step; see [2026-01-06-ledger-export](../artifacts/plans/2026-01-06-ledger-export.md), AD-01 and TD-02."
  fi
  add "$WI/_INDEX.md" \
    "- Invoice retry builds on [2026-01-05-ledger-export-design](../artifacts/specs/2026-01-05-ledger-export-design.md)."
  add "$WI/_SEARCH_INDEX.md" \
    "| [[architecture-decisions]] | decision | architecture | AD-03, retry, gateway-client | Invoice retry goes through the gateway client |"
  if [ "$v" = rank ]; then
    local nn
    for nn in 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
      add "$WI/_SEARCH_INDEX.md" "| [[note-$nn]] | insight | notes | AD-1$nn | Invoice retry note $nn |"
    done
    add "$WI/_SEARCH_INDEX.md" "| [[retry-backoff]] | debt | backoff | TD-02, AD-01 | Invoice retry backoff is fixed |"
  fi
  commit "wiki: invoice retry context"

  # C1: S1 on main. A same-directory link, a backticked path, a self path, a wikilink with an ID,
  # and frontmatter whose YAML comment would pass for the H1 if the frontmatter went unseen (as it
  # would behind a byte-order mark, or in the CRLF variant were the CR not stripped).
  put "$AR/specs/2026-02-01-invoice-retry-design.md" <<'EOF'
---
status: approved
# reviewer note: not a title
---

# Invoice retry design

Prior context: [2026-01-05-ledger-export-design](2026-01-05-ledger-export-design.md) and
`docs/second-brain/artifacts/plans/2026-01-06-ledger-export.md`.

This spec: docs/second-brain/artifacts/specs/2026-02-01-invoice-retry-design.md

Decisions honoured: [[architecture-decisions#AD-01]], AD-03 (the gateway client). Known debt: TD-02.
EOF
  # ...saved by an editor that writes a UTF-8 byte-order mark: the frontmatter must still be seen.
  { printf '\357\273\277'; cat "$R/$AR/specs/2026-02-01-invoice-retry-design.md"; } > "$R/bom.tmp" \
    && mv "$R/bom.tmp" "$R/$AR/specs/2026-02-01-invoice-retry-design.md"
  add "$WI/_INDEX.md" "- [2026-02-01-invoice-retry-design](../artifacts/specs/2026-02-01-invoice-retry-design.md)"
  commit "spec: invoice retry"

  # S2 on a feature branch, merged with a merge commit. Its context exists only on the branch.
  fx checkout -q -b feat/payment-webhooks
  add "$WI/active-project-context.md" \
    "- Payment webhooks: verify signatures per AD-02; reuse the event shape of [2026-02-01-invoice-retry-design](../artifacts/specs/2026-02-01-invoice-retry-design.md)." \
    "- Payment webhooks hand off to the queue (AD-04)."
  if [ "$v" = crosscut ]; then
    add "$WI/active-project-context.md" "- Outbound HTTP: one gateway client for every call (AD-03)."
  else
    add "$WI/active-project-context.md" "- Payment webhooks call out through the gateway client (AD-03)."
  fi
  commit "wiki: payment webhooks context"
  put "$AR/specs/2026-03-01-payment-webhooks-design.md" <<'EOF'
# Payment webhooks design

Builds on [[2026-02-01-invoice-retry-design]]. Its plan: ../plans/2026-03-02-payment-webhooks.md

Decisions: AD-02 (signatures), AD-03 (gateway client), AD-04 (queue).
EOF
  commit "spec: payment webhooks"
  put "$AR/plans/2026-03-02-payment-webhooks.md" <<'EOF'
# Payment webhooks implementation plan
EOF
  add "$WI/_INDEX.md" "- [2026-03-02-payment-webhooks](../artifacts/plans/2026-03-02-payment-webhooks.md)"
  commit "plan: payment webhooks"
  fx checkout -q main
  printf 'app v2\n' > "$R/src-app.txt"
  commit "app v2"
  fx merge -q --no-ff -m "Merge feat/payment-webhooks" feat/payment-webhooks

  # D, C3: S3 on main; it introduces AD-05 in the same commit, so AD-05 is not prior. Its plan
  # citation sits only on a line whose words match S3's title after Latin folding on both sides
  # (upper-case Ş Ö Ğ Ü Ç İ in the wiki, lower-case ş ö ğ ü ç ı in the H1): unfolded, the title
  # words fall apart into pieces shorter than 3 characters and the line is never matched.
  add "$WI/active-project-context.md" "- Refund notifications: AD-04 applies."
  add "$WI/_INDEX.md" "- ŞÖĞÜÇ İŞİK: [2026-03-02-payment-webhooks](../artifacts/plans/2026-03-02-payment-webhooks.md)"
  [ "$v" = crosscut ] || add "$WI/active-project-context.md" "- Refund notifications also go through the gateway client (AD-03)."
  commit "wiki: refund context"
  put "$AR/specs/2026-04-01-refund-notifications-design.md" <<'EOF'
# Refund notifications design: şöğüç ışık

Follows docs/second-brain/artifacts/plans/2026-03-02-payment-webhooks.md.
Decisions: AD-03, AD-04, and the new AD-05 (refund window).
EOF
  add "$WI/architecture-decisions.md" "" "## AD-05: Refunds close after 30 days" "**Status:** accepted"
  commit "spec: refund notifications"

  # A newer spec on a branch that is never merged.
  fx checkout -q -b feat/unmerged
  put "$AR/specs/2026-05-01-unmerged-thing-design.md" <<'EOF'
# Unmerged thing design

AD-01.
EOF
  commit "spec: unmerged"
  fx checkout -q main
}

# run <name> <args...>: run the harness; stdout -> $WORK/<name>.out, stderr -> .err, exit -> RC
RC=0
run() { local n="$1"; shift; bash "$H" "$@" > "$WORK/$n.out" 2> "$WORK/$n.err"; RC=$?; }
# expect_line <name> <label> <expected stdout line>
expect_line() {
  local got; got="$(cat "$WORK/$1.out")"
  if [ "$RC" -eq 0 ] && [ "$got" = "$3" ]; then ok "$2"
  else bad "$2 (exit $RC; expected '$3', got '$got'; stderr: $(tr '\n' ' ' < "$WORK/$1.err"))"; fi
}
expect_exit() {  # expect_exit <code> <label> [<stderr substring>]
  if [ "$RC" -eq "$1" ] && { [ -z "${3:-}" ] || grep -qF -- "$3" "$WORK/last.err"; }; then ok "$2"
  else bad "$2 (expected exit $1${3:+ and '$3'}, got $RC: $(tr '\n' ' ' < "$WORK/last.err"))"; fi
}
# expect_err <name> <label> <line>...: stderr holds exactly these lines, in this order
expect_err() {
  local n="$1" label="$2"; shift 2
  if [ "$(cat "$WORK/$n.err")" = "$(printf '%s\n' "$@")" ]; then ok "$label"
  else bad "$label (stderr: $(tr '\n' '|' < "$WORK/$n.err"))"; fi
}

for v in full crosscut rank crlf exportignore; do build "$WORK/$v" "$v"; done

# --- stub sumela-wiki.sh tools ------------------------------------------------------------------
# STUB speaks R1-18's documented output: catalog lines "<date> · <slug> · <H1>" (spec slugs
# without their date prefix, plan slugs with it) and search lines "<score> · <path> · <terms> ·
# <first line>". It lists every spec, plan and AD/TD heading of the tree it is pointed at, so a
# correct extraction of each parent commit gives recall 1. It refuses (exit 3-9):
#   a tree without .sumela/; an unset WIKI_PATH; a SUMELA_SUMMARIES_DIR from the caller's shell;
#   a git repository discoverable from the tree; an empty query; the harness's literal-pathspec
#   setting; and a tree that holds the spec under replay (its file name carries the query's first
#   three words in every fixture here), which only a tree read at or after the commit that added
#   the spec can.
mkdir -p "$WORK/stub"
STUB="$WORK/stub/sumela-wiki.sh"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
dir=""; [ "${1:-}" = "-C" ] && { dir="$2"; shift 2; }
[ -n "$dir" ] && [ -d "$dir/.sumela" ] || { echo "stub: no .sumela/ anchor under -C" >&2; exit 3; }
[ -n "${WIKI_PATH:-}" ] || { echo "stub: WIKI_PATH is not set" >&2; exit 4; }
[ -z "${SUMELA_SUMMARIES_DIR+x}" ] || { echo "stub: SUMELA_SUMMARIES_DIR reached the tool" >&2; exit 5; }
if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then echo "stub: a git repository is reachable from the replay tree" >&2; exit 6; fi
[ -z "${GIT_LITERAL_PATHSPECS+x}" ] || { echo "stub: GIT_LITERAL_PATHSPECS reached the tool" >&2; exit 8; }
printf '%s\n' "$*" >> "$STUB_LOG"
wiki="$dir/$WIKI_PATH"
case "$WIKI_PATH" in */*) art="$dir/${WIKI_PATH%/*}/artifacts" ;; *) art="$dir/artifacts" ;; esac
case "${1:-}" in
  catalog) [ "${3:-}" = "--match" ] || { echo "stub: catalog without --match" >&2; exit 2; }; q="${4:-}" ;;
  search)  q="${2:-}" ;;
  *)       exit 2 ;;
esac
[ -n "$q" ] || { echo "stub: $1 without terms" >&2; exit 7; }
read -r w1 w2 w3 _ <<< "$q"
if ls "$art/specs" 2>/dev/null | grep -q -F -- "-$w1${w2:+-$w2}${w3:+-$w3}"; then
  echo "stub: the replay tree holds the spec under replay" >&2; exit 9
fi
case "$1" in
  catalog)
    for f in "$art/$2"/*.md; do
      [ -f "$f" ] || continue
      b="$(basename "$f" .md)"; d="${b%%-[a-z]*}"
      if [ "$2" = specs ]; then s="${b#????-??-??-}"; else s="$b"; fi
      printf '%s · %s · %s\n' "$d" "$s" "$(head -1 "$f" | tr -d '\r' | sed 's/^# //')"
    done
    echo "[cut: +0 older — --before 2026-01-01]" ;;
  search)
    grep -h -E '^## (AD|TD)-' "$wiki"/architecture-decisions.md "$wiki"/tech-debt-and-known-issues.md 2>/dev/null \
      | tr -d '\r' | sed 's|^|2.5 · docs/second-brain/wiki/architecture-decisions.md · x · |'
    echo "no further hits: try --deep, the catalogs or Tier-1b" ;;
esac
EOF
export STUB_LOG="$WORK/stub.log"; : > "$STUB_LOG"
printf '#!/usr/bin/env bash\necho "boom" >&2; exit 1\n' > "$WORK/stub/fails.sh"

echo "== t_synthetic_known_citations_recall_1 (old path) =="
# Every cited item of S1, S2 and S3 is on a line matching the spec's title words at its parent.
# S2's context lines exist only on its feature branch: a harness that read the base before the
# merge (instead of the parent of the commit that added the spec) would score S2 at 0.
run full --repo "$WORK/full" --n 3 --path old
expect_line full "known citations: recall 1, cross-cutting AD recalled, 3 specs" \
  "recall@20=1.000 crosscut_recall@20=1.000 specs=3 path=old"
# The fixture has no remote, so the default base falls back to HEAD; in a non-bare clone HEAD may
# be a feature branch, so the run says so, once, and says nothing else.
expect_err full "without origin/HEAD the default base is HEAD, with one note on stderr" \
  "wiki-retrieval-replay: note: origin/HEAD is not set, so the base is the checked-out HEAD; if that is not the base branch, pass --base <ref>"
run fullb --repo "$WORK/full" --n 3 --path old --base main
expect_line fullb "the same figures with --base main" "recall@20=1.000 crosscut_recall@20=1.000 specs=3 path=old"
if [ ! -s "$WORK/fullb.err" ]; then ok "a clean run prints nothing on stderr"; else bad "stderr not empty: $(cat "$WORK/fullb.err")"; fi
# --n 10: S0 joins (added by the root commit, so nothing is prior to it and it is not scored);
# the unmerged branch's newer spec is never replayed (specs would be 5).
run n10 --repo "$WORK/full" --n 10
expect_line n10 "a root-commit spec counts in specs= but not in the mean; unmerged specs are skipped" \
  "recall@20=1.000 crosscut_recall@20=1.000 specs=4 path=old"
run crlf --repo "$WORK/crlf" --n 3
expect_line crlf "CRLF specs and boot files give the same figures" \
  "recall@20=1.000 crosscut_recall@20=1.000 specs=3 path=old"
run ei --repo "$WORK/exportignore" --n 3
expect_line ei "export-ignore'd boot files are still read (git cat-file fills the archive's gaps)" \
  "recall@20=1.000 crosscut_recall@20=1.000 specs=3 path=old"
if grep -q 'export-ignore attribute were read with git cat-file' "$WORK/ei.err"; then ok "…and the run says so on stderr"
else bad "no export-ignore note on stderr: $(cat "$WORK/ei.err")"; fi

echo "== t_reads_parent_commit_not_later =="
# One spec, on a feature branch: its adding commit also adds an index line naming AD-2; a review
# edit follows; the branch is merged with a merge commit; a later main-line line names AD-2 too.
# At the parent of the adding commit only AD-1 is retrievable: recall 1/2 = 0.500. Reading the
# boot files at the adding commit, after the review edit (a lookup that is not limited to adds),
# at the merge or at the base would find AD-2 as well (1.000).
R="$WORK/timepoint"; EOL=lf; gx init -q -b main "$R" >/dev/null
put "$WI/_INDEX.md" <<'EOF'
# Index
EOF
put "$WI/active-project-context.md" <<'EOF'
- Alpha sync: AD-01
EOF
put "$WI/architecture-decisions.md" <<'EOF'
## AD-01: One
## AD-02: Two
EOF
commit "root"
fx checkout -q -b feat/alpha-sync
put "$AR/specs/2026-07-01-alpha-sync-design.md" <<'EOF'
# Alpha sync design

Cites AD-01 and AD-02.
EOF
add "$WI/_INDEX.md" "- [alpha sync design](../artifacts/specs/2026-07-01-alpha-sync-design.md): alpha sync builds on AD-02"
commit "spec: alpha sync, with its index line"
add "$AR/specs/2026-07-01-alpha-sync-design.md" "" "Reviewed."
commit "spec: review edit"
fx checkout -q main
fx merge -q --no-ff -m "Merge feat/alpha-sync" feat/alpha-sync
add "$WI/active-project-context.md" "- Alpha sync follow-up: AD-02"
commit "wiki: later context"
run tp --repo "$WORK/timepoint" --n 1 --base main
expect_line tp "old path: the boot files are read at the parent of the adding commit, never later" \
  "recall@20=0.500 crosscut_recall@20=n/a specs=1 path=old"
# The new path through STUB: its registers list both IDs at the parent (1.000); a tree read at or
# after the adding commit holds the spec itself, which the stub refuses (the run would fail).
run tpn --repo "$WORK/timepoint" --n 1 --base main --path new --wiki-tool "$STUB"
expect_line tpn "new path: the tree the tool reads is the parent commit's (it never holds the spec)" \
  "recall@20=1.000 crosscut_recall@20=n/a specs=1 path=new"

echo "== t_crosscutting_subset_measured =="
# crosscut variant: AD-3 sits only on lines without S2's or S3's title words.
#   S1 5/5 = 1 · S2 {AD-2, AD-4, spec S1} of 4 = 0.75 · S3 {plan, AD-4} of 3 = 0.667
#   recall = (1 + 0.75 + 0.6667) / 3 = 0.806 · cross-cutting AD-3: S1 1, S2 0, S3 0 -> 0.333
# Were AD-4 (cited by only 2) counted as cross-cutting, S2 and S3 would each score 0.5 -> 0.667.
run cc --repo "$WORK/crosscut" --n 3
expect_line cc "cross-cutting ADs are measured on their own (0.333), apart from overall recall (0.806)" \
  "recall@20=0.806 crosscut_recall@20=0.333 specs=3 path=old"
# --n 2 replays S3 and S2 only: AD-3 is then cited by 2 of the window's specs -> no cross-cutting AD.
#   recall = (0.75 + 0.6667) / 2 = 0.708
run cc2 --repo "$WORK/crosscut" --n 2
expect_line cc2 "the cross-cutting threshold (>=3 specs) is counted within the replayed window" \
  "recall@20=0.708 crosscut_recall@20=n/a specs=2 path=old"

echo "== ranking by distinct terms, and the cut at exactly 20 =="
# rank variant, S1 (terms invoice, retry, design) at its parent. In rank order:
#   3 terms: the index line linking S1 itself (skipped: a spec is never its own candidate), then
#            "builds on ... ledger-export-design" -> slot 1 spec ledger-export-design
#   2 terms: the plan line -> 2 · AD-3 -> 3 · sixteen noise lines -> 4..19 · one line holding
#            TD-2 -> 20 and AD-1 -> 21
#   1 term:  "Invoice backoff: AD-199", first in file order -> 22
# S1 4/5 = 0.8 · S2 1 · S3 1 -> 0.933. A cut at 19 loses TD-2; one at 21 (or none, or one that
# lets a line finish past 20) finds AD-1; file-order ranking puts AD-199 at slot 2 and a self
# link that took a slot would put S1 there, each pushing TD-2 to 21; ranking by occurrences
# instead of distinct terms lifts the AD-3 and TD-2/AD-1 lines (3 occurrences) above the plan
# line and the noise. Each gives S1 0.6 (0.867) or 1 (1.000).
run rank --repo "$WORK/rank" --n 3
expect_line rank "lines rank by distinct terms matched and only the first 20 candidates count" \
  "recall@20=0.933 crosscut_recall@20=1.000 specs=3 path=old"

echo "== title words: at most 8, 3+ characters, no numbers, punctuation separates; the file name without an H1 =="
# A separate history; every route below is a line "- <word>: AD-nn" that only that word matches.
# - T1's H1 opens with "ox" (too short) and "2026" (a number), which must not take a slot, then
#   nine words: "hotel", the eighth, finds AD-07; "india", the ninth, would find AD-01.
#   T1 cites AD-01, AD-02 (ox), AD-03 and AD-15 (2026) and AD-07: 1/5. The number's line names
#   two IDs, so a number that took a slot (pushing "hotel" out) cannot leave the figure unchanged.
# - T2 has no H1: its file name's words (date dropped) find "lima" (AD-04). Its same-directory
#   link to T1 is a citation that no line carries: 1/2.
# - T3's H1 "kǵx—nova⸺oslo©papa" holds a word in a Latin letter outside the fold table (kept as
#   written: AD-05) joined to others by an em dash (U+2014), a two-em dash (U+2E3A) and a copyright
#   sign, all separators: "nova" finds AD-06 and "papa" AD-13: 3/3.
# - T4's H1 "elk ǵǵ ⱥⱦⱡ ⴰⴱⴳ ⴰⴱ yankee、zulu（xray）": "elk" (3 characters, AD-08) counts; "ǵǵ" and
#   "ⴰⴱ" (2 characters, 4 and 6 bytes: AD-09, AD-14) do not; Latin Extended-C and Tifinagh
#   letters (U+2C00-2DFF) are letters (AD-10, AD-11); 、 (U+3001) and （ ） (U+FF08-FF09) separate
#   words, so "zulu" finds AD-12: 4/6.
# - A later rename of T1 is not a new spec, even with diff.renames=false in the clone's config.
#   (1/5 + 1/2 + 1 + 4/6) / 4 = 0.592 over specs=4; with "india" in a terms file T1 is 2/5 -> 0.642
R="$WORK/terms"; EOL=lf; gx init -q -b main "$R" >/dev/null
fx config diff.renames false
put "$WI/architecture-decisions.md" <<'EOF'
# Architecture Decisions

## AD-01: One
## AD-02: Two
## AD-03: Three
## AD-04: Four
## AD-05: Five
## AD-06: Six
## AD-07: Seven
## AD-08: Eight
## AD-09: Nine
## AD-10: Ten
## AD-11: Eleven
## AD-12: Twelve
## AD-13: Thirteen
## AD-14: Fourteen
## AD-15: Fifteen
EOF
put "$WI/active-project-context.md" <<'EOF'
# Active Project Context

- india: AD-01
- ox: AD-02
- 2026: AD-03, AD-15
- lima: AD-04
- kǵx: AD-05
- nova: AD-06
- hotel: AD-07
- elk: AD-08
- ǵǵ: AD-09
- ⱥⱦⱡ: AD-10
- ⴰⴱⴳ: AD-11
- zulu: AD-12
- papa: AD-13
- ⴰⴱ: AD-14
EOF
commit "root"
put "$AR/specs/2026-06-01-terms-design.md" <<'EOF'
# ox 2026 alpha bravo charlie delta echo foxtrot golf hotel india

Cites AD-01, AD-02, AD-03, AD-07 and AD-15.
EOF
commit "spec: terms"
put "$AR/specs/2026-06-02-kilo-lima.md" <<'EOF'
---
title: none
---

Cites AD-04. See [the terms spec](2026-06-01-terms-design.md).
EOF
commit "spec: no H1"
put "$AR/specs/2026-06-03-glyphs.md" <<'EOF'
# kǵx—nova⸺oslo©papa

Cites AD-05, AD-06 and AD-13.
EOF
commit "spec: glyphs"
put "$AR/specs/2026-06-04-scripts.md" <<'EOF'
# elk ǵǵ ⱥⱦⱡ ⴰⴱⴳ ⴰⴱ yankee、zulu（xray）

Cites AD-08, AD-09, AD-10, AD-11, AD-12 and AD-14.
EOF
commit "spec: scripts"
fx mv "$AR/specs/2026-06-01-terms-design.md" "$AR/specs/2026-06-01-terms-design-v2.md"
commit "rename a spec"
run terms --repo "$WORK/terms" --n 10
expect_line terms "term rules (8 words, 3+ characters, no numbers, punctuation and CJK/fullwidth separators, other scripts kept), file-name fallback, same-dir links, renames" \
  "recall@20=0.592 crosscut_recall@20=n/a specs=4 path=old"
printf 'india\n' > "$WORK/tf-india"
run terms2 --repo "$WORK/terms" --n 10 --terms-file "$WORK/tf-india"
expect_line terms2 "terms-file words are added beyond the 8 title words" \
  "recall@20=0.642 crosscut_recall@20=n/a specs=4 path=old"

echo "== terms file: add per spec, add for all, drop =="
printf '# fixture terms\n2026-03-01-payment-webhooks-design\toutbound\n' > "$WORK/tf-one"
# S2 now matches the "Outbound HTTP" line and finds AD-3: (1 + 1 + 0.6667)/3; cross-cut (1 + 1 + 0)/3
run tf1 --repo "$WORK/crosscut" --n 3 --terms-file "$WORK/tf-one"
expect_line tf1 "a '<spec><TAB><words>' line adds terms to that spec only" \
  "recall@20=0.889 crosscut_recall@20=0.667 specs=3 path=old"
printf 'outbound\n' > "$WORK/tf-all"
run tf2 --repo "$WORK/crosscut" --n 3 --terms-file "$WORK/tf-all"
expect_line tf2 "a bare line adds terms to every spec" \
  "recall@20=1.000 crosscut_recall@20=1.000 specs=3 path=old"
printf -- '-payment webhooks design\r\n' > "$WORK/tf-drop"
# S2 loses every title word and retrieves nothing: (1 + 0 + 0.6667)/3; cross-cut (1 + 0 + 0)/3.
run tf3 --repo "$WORK/crosscut" --n 3 --terms-file "$WORK/tf-drop"
expect_line tf3 "a '-<words>' line drops title words (CRLF terms file)" \
  "recall@20=0.556 crosscut_recall@20=0.333 specs=3 path=old"

echo "== ID forms, paths, wikilinks and the cited set =="
# A separate history. At the root: AD-03 and AD-05 in the register (written zero-padded), TD-07,
# the specs base-design and shared-name, the plan shared-name, and a draft that shares K1's name.
# K1 ("Kilo design", behind a fenced block whose "# Not the title" line must not become the H1)
# cites AD-5, AD-3, TD-07, base-design, shared-name as spec and as plan, and itself:
#   cited {AD-5, AD-3, TD-7, spec base-design, spec shared-name, plan shared-name} (6; itself never,
#   though the draft makes its name prior)
#   found: "AD-05" is AD-5 · "[[shared-name]]" names both the spec and the plan · TD-07  -> 4/6
#   unfound: AD-3 appears on a Kilo line only as "upload-3" and "AD-03x", not IDs; base-design only
#   as "notes/subspecs/...", not the specs directory
# K2 "Lima design" cites TD-07, on the Lima line: 1/1 · K3 "Mike design" cites TD-07: 0/1.
# recall = (0.667 + 1 + 0) / 3 = 0.556. TD-07 is cited by all three, but only ADs are
# cross-cutting: n/a (counting TDs would give 0.667).
R="$WORK/ids"; EOL=lf; gx init -q -b main "$R" >/dev/null
put "$WI/architecture-decisions.md" <<'EOF'
# Architecture Decisions

## AD-03: Three
## AD-05: Five
EOF
put "$WI/tech-debt-and-known-issues.md" <<'EOF'
# Tech Debt

## TD-07: Seven
EOF
put "$WI/active-project-context.md" <<'EOF'
# Active Project Context

- Kilo: AD-05
- Kilo: upload-3 and AD-03x
- Kilo: notes/subspecs/2026-09-01-base-design.md
- Kilo: [[shared-name]]
- Kilo: TD-07
- Lima: TD-07
EOF
printf '# Base design\n' | put "$AR/specs/2026-09-01-base-design.md"
printf '# Shared name\n' | put "$AR/specs/shared-name.md"
printf '# Shared name plan\n' | put "$AR/plans/shared-name.md"
printf '# Kilo draft\n' | put "$AR/specs/drafts/2026-09-05-kilo-design.md"
commit "root"
put "$AR/specs/2026-09-05-kilo-design.md" <<'EOF'
```text
# Not the title: zulu
```

# Kilo design

Cites AD-5, AD-3, TD-07, docs/second-brain/artifacts/specs/2026-09-01-base-design.md,
docs/second-brain/artifacts/specs/shared-name.md and docs/second-brain/artifacts/plans/shared-name.md.
Itself: docs/second-brain/artifacts/specs/2026-09-05-kilo-design.md
EOF
commit "spec: kilo"
printf '# Lima design\n\nCites TD-07.\n' | put "$AR/specs/2026-09-06-lima-design.md"
commit "spec: lima"
printf '# Mike design\n\nCites TD-07.\n' | put "$AR/specs/2026-09-07-mike-design.md"
commit "spec: mike"
run ids --repo "$WORK/ids" --n 3 --base main
expect_line ids "AD-05 is AD-5; IDs need word boundaries; subspecs/ is not specs/; [[name]] of a spec and a plan is both; a spec never cites itself; fences hide a heading; TDs are never cross-cutting" \
  "recall@20=0.556 crosscut_recall@20=n/a specs=3 path=old"

echo "== the window: first-parent adds of *.md specs, once per path =="
# A separate history: the code-only root, spec A (no terms, written before the wiki existed), the
# wiki, a README, a dot file, an underscore file and a non-markdown file under specs/, spec B; a
# branch adds xray, drops it again and adds yankee; main removes B and restores it; then a merge.
# Window, newest first: yankee (at the merge), B (its restore; its first add is the same path),
# A -> specs=3. xray never reached the base; the other four files are not specs.
#   yankee: no line carries its words, 0/1 · B: "- Bravo: AD-01", 1/1 · A: nothing prior, unscored
#   recall = (0 + 1) / 2 = 0.500. A's parent commit had no boot file: one note says so.
R="$WORK/window"; EOL=lf; gx init -q -b main "$R" >/dev/null
printf 'code\n' > "$R/app.txt"; commit "root: code only"
printf '# ox 42\n' | put "$AR/specs/2026-01-10-alpha.md"; commit "spec: written before the wiki"
printf '# Active Project Context\n\n- Bravo: AD-01\n' | put "$WI/active-project-context.md"
printf '# Architecture Decisions\n\n## AD-01: One\n' | put "$WI/architecture-decisions.md"
commit "wiki"
for f in README.md .hidden.md _draft.md notes.txt; do printf 'x\n' | put "$AR/specs/$f"; done
commit "specs: not specs"
printf '# Bravo design\n\nCites AD-01.\n' | put "$AR/specs/2026-01-20-bravo-design.md"; commit "spec: bravo"
fx checkout -q -b feat/yankee
printf '# Xray design\n\nCites AD-01.\n' | put "$AR/specs/2026-01-25-xray-design.md"; commit "spec: xray"
fx rm -q "$AR/specs/2026-01-25-xray-design.md"; commit "drop xray"
printf '# Yankee design\n\nCites AD-01.\n' | put "$AR/specs/2026-01-26-yankee-design.md"; commit "spec: yankee"
fx checkout -q main
fx rm -q "$AR/specs/2026-01-20-bravo-design.md"; commit "remove bravo"
printf '# Bravo design\n\nCites AD-01.\n' | put "$AR/specs/2026-01-20-bravo-design.md"; commit "restore bravo"
fx merge -q --no-ff -m "Merge feat/yankee" feat/yankee
run window1 --repo "$WORK/window" --n 10 --base main
expect_line window1 "the window: first-parent only, *.md only, no README or dot/underscore files, one replay per path" \
  "recall@20=0.500 crosscut_recall@20=n/a specs=3 path=old"
expect_err window1 "a parent commit without boot files is counted in a note, not silently scored" \
  "wiki-retrieval-replay: note: 1 of 3 parent commits had no boot file under the wiki directory"
# A spec that only a merge commit adds (no commit below it adds the file) is replayed at the
# merge's first parent: main had "- Alpha: AD-01" there; "- Alpha follow-up: AD-02" comes with the
# merge itself and the branch had neither line. 1/2 = 0.500 (at the merge 1.000, on the branch 0).
R="$WORK/evil"; EOL=lf; gx init -q -b main "$R" >/dev/null
printf '# Context\n' | put "$WI/active-project-context.md"
printf '## AD-01: One\n## AD-02: Two\n' | put "$WI/architecture-decisions.md"
commit "root"
fx checkout -q -b feat/evil; printf 'app\n' > "$R/app.txt"; commit "app"
fx checkout -q main; add "$WI/active-project-context.md" "- Alpha: AD-01"; commit "wiki: alpha"
fx merge -q --no-ff --no-commit feat/evil
printf '# Alpha design\n\nCites AD-01 and AD-02.\n' | put "$AR/specs/2026-08-02-alpha-design.md"
add "$WI/active-project-context.md" "- Alpha follow-up: AD-02"
commit "Merge feat/evil, adding a spec"
run evil --repo "$WORK/evil" --n 1 --base main
expect_line evil "a spec added by a merge commit alone is replayed at the merge's first parent" \
  "recall@20=0.500 crosscut_recall@20=n/a specs=1 path=old"
# Pathspecs are literal: "alpha[1].md" is looked up as itself, not as a glob that also matches
# "alpha1.md". Both reach main in one merge; the branch added alpha[1], then "- Alpha: AD-02",
# then alpha1, so a glob lookup from the merge would return alpha1's adding commit.
#   alpha[1] at its parent (the root): AD-01 only, 1/2 · alpha1 cites nothing, unscored -> 0.500
R="$WORK/literal"; EOL=lf; gx init -q -b main "$R" >/dev/null
printf -- '- Alpha: AD-01\n' | put "$WI/active-project-context.md"
printf '## AD-01: One\n## AD-02: Two\n' | put "$WI/architecture-decisions.md"
commit "root"
fx checkout -q -b feat/alpha
printf '# Alpha design\n\nCites AD-01 and AD-02.\n' | put "$AR/specs/2026-08-01-alpha[1].md"; commit "spec: alpha[1]"
add "$WI/active-project-context.md" "- Alpha: AD-02"; commit "wiki: more alpha"
printf '# Zulu\n' | put "$AR/specs/2026-08-01-alpha1.md"; commit "spec: alpha1"
fx checkout -q main
fx merge -q --no-ff -m "Merge feat/alpha" feat/alpha
run literal --repo "$WORK/literal" --n 2 --base main
expect_line literal "a spec name with glob characters is looked up literally" \
  "recall@20=0.500 crosscut_recall@20=n/a specs=2 path=old"

echo "== clones and the base window =="
gx clone -q --bare "$WORK/full" "$WORK/bare.git" 2>/dev/null
run bare --repo "$WORK/bare.git" --n 3
expect_line bare "a bare clone works (default base HEAD)" "recall@20=1.000 crosscut_recall@20=1.000 specs=3 path=old"
if [ ! -s "$WORK/bare.err" ]; then ok "…and needs no note: a bare clone's HEAD is the remote's default branch"
else bad "bare clone stderr: $(cat "$WORK/bare.err")"; fi
gx clone -q "$WORK/full" "$WORK/clone" 2>/dev/null
gx -C "$WORK/clone" checkout -q -b local-work origin/main~4   # HEAD alone would replay 2 specs
run origin --repo "$WORK/clone" --n 3
expect_line origin "the default base is origin/HEAD, not the checked-out branch" \
  "recall@20=1.000 crosscut_recall@20=1.000 specs=3 path=old"
# Pinned at the S2 merge: the window is S2, S1 and S0 (root, unscored); AD-3 is cited by 2 -> n/a.
M2="$(git -C "$WORK/full" rev-parse 'main~2')"
run window --repo "$WORK/full" --n 3 --base "$M2"
expect_line window "--base <sha> pins the window" "recall@20=1.000 crosscut_recall@20=n/a specs=3 path=old"

echo "== the new path, through stub sumela-wiki.sh tools =="
: > "$STUB_LOG"
run new --repo "$WORK/full" --n 3 --path new --wiki-tool "$STUB"
expect_line new "new path: each parent's specs, plans and registers reach the tool; recall 1" \
  "recall@20=1.000 crosscut_recall@20=1.000 specs=3 path=new"
# 3 specs x (search + catalog specs + catalog plans)
if [ "$(grep -c '' "$STUB_LOG")" -eq 9 ] && grep -q '^catalog specs --match invoice retry design$' "$STUB_LOG"; then
  ok "new path: three tool calls per spec, the title words passed as one query"
else bad "new path tool calls: $(tr '\n' '|' < "$STUB_LOG")"; fi
printf '#!/usr/bin/env bash\necho "something else entirely"\n' > "$WORK/stub/garbage.sh"
run last --repo "$WORK/full" --n 3 --path new --wiki-tool "$WORK/stub/garbage.sh"
expect_exit 1 "new path: output that never parses fails (exit 1) instead of scoring 0" "no line the harness can parse"
run last --repo "$WORK/full" --n 3 --path new --wiki-tool "$WORK/stub/fails.sh"
expect_exit 1 "new path: a failing tool fails the run (exit 1) and its stderr is shown" "boom"
run last --repo "$WORK/full" --path new --wiki-tool "$WORK/stub/missing.sh"
expect_exit 3 "new path without the tool: exit 3" "needs sumela-wiki.sh"
# The window history through STUB: yankee and B find AD-01 in the register (1.000). Spec A has no
# terms, so the tool is never called with an empty query (the stub would refuse one), and its
# parent commit had no wiki directory, which one note says.
run neww --repo "$WORK/window" --n 10 --base main --path new --wiki-tool "$STUB"
expect_line neww "new path: a spec without terms makes no tool call" \
  "recall@20=1.000 crosscut_recall@20=n/a specs=3 path=new"
expect_err neww "new path: a parent commit without the wiki directory is counted in a note" \
  "wiki-retrieval-replay: note: 1 of 3 parent commits had no wiki directory"
# The caller's WIKI_PATH and SUMELA_SUMMARIES_DIR never reach the tool: --wiki-dir is passed as
# WIKI_PATH, and the stub refuses a SUMELA_SUMMARIES_DIR (live summaries are not the parent's).
WIKI_PATH=docs/elsewhere/wiki SUMELA_SUMMARIES_DIR="$WORK/live-summaries" \
  run envs --repo "$WORK/full" --n 3 --base main --path new --wiki-tool "$STUB" --wiki-dir "$WI"
expect_line envs "new path: the tool gets WIKI_PATH=<--wiki-dir> and no SUMELA_SUMMARIES_DIR from the caller" \
  "recall@20=1.000 crosscut_recall@20=1.000 specs=3 path=new"
# The tool's stderr is never dropped: each distinct line once, after its calls succeed.
cat > "$WORK/stub/warn.sh" <<EOF
#!/usr/bin/env bash
echo "warning: no budgets file; using built-in caps" >&2
echo "notice: legacy index, per-artifact lines skipped" >&2
exec bash "$STUB" "\$@"
EOF
run warn --repo "$WORK/full" --n 3 --base main --path new --wiki-tool "$WORK/stub/warn.sh"
expect_line warn "new path: a tool that warns still scores" "recall@20=1.000 crosscut_recall@20=1.000 specs=3 path=new"
expect_err warn "new path: the tool's warnings reach stderr, each distinct line once" \
  "wiki-retrieval-replay: sumela-wiki.sh: warning: no budgets file; using built-in caps" \
  "wiki-retrieval-replay: sumela-wiki.sh: notice: legacy index, per-artifact lines skipped"
# The cut at exactly 20 and the interleave (search, catalog specs, catalog plans, then each one's
# second entry, ...), through a stub that prints fixed lists per spec and ignores the tree:
#   S1 search only: AD-3 1, spec ledger-export-design 2, plan ledger-export 3, noise 4..19,
#      TD-2 20, AD-1 21 -> 4/5 = 0.8 (a cut at 19 loses TD-2, one at 21 finds AD-1)
#   S2 rank 1: "AD-3 AD-4" (one hit, two IDs) 1-2, catalog spec invoice-retry-design 3, a noise
#      plan 4; ranks 2-6 noise 5..19; rank 7: search AD-2 20, then noise -> 4/4 = 1 (any order not
#      led by search, or search drained before the catalogs, loses AD-2 or the catalog spec)
#   S3 ranks 1-2: search AD-3, AD-4; rank 7: search noise 19, catalog-spec noise 20, catalog plan
#      payment-webhooks 21 -> 2/3 (any order that does not put catalog plans last finds it)
#   recall = (0.8 + 1 + 0.6667) / 3 = 0.822 · AD-3, cited by all three, found by all: 1.000
cat > "$WORK/stub/rank.sh" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "-C" ] && shift 2
case "${1:-}" in catalog) list="$2"; q="${4:-}" ;; search) list=search; q="${2:-}" ;; *) exit 2 ;; esac
[ -n "$q" ] || exit 7
W=docs/second-brain/wiki/notes.md; A=docs/second-brain/artifacts
ids()   { local x; for x in "$@"; do printf '1.0 · %s · x · %s\n' "$W" "$x"; done; }
noise() { local n="$1"; while [ "$n" -le "$2" ]; do ids "AD-$n"; n=$((n + 1)); done; }
cat_n() { local n="$2"; while [ "$n" -le "$3" ]; do printf '2026-01-%02d · noise-%s-%s · Noise\n' "$n" "$1" "$n"; n=$((n + 1)); done; }
case "${q%% *}/$list" in
  invoice/search) ids AD-03
                  printf '1.0 · %s · x · -\n' "$A/specs/2026-01-05-ledger-export-design.md" "$A/plans/2026-01-06-ledger-export.md"
                  noise 201 216; ids TD-02 AD-01; noise 217 220 ;;
  payment/search) ids "AD-03 AD-04"; noise 301 305; ids AD-02; noise 306 318 ;;
  payment/specs)  printf '2026-02-01 · invoice-retry-design · Invoice retry design\n'; cat_n spec 2 7 ;;
  payment/plans)  cat_n plan 1 7 ;;
  refund/search)  ids AD-03 AD-04; noise 401 418 ;;
  refund/specs)   cat_n spec 1 7 ;;
  refund/plans)   cat_n plan 1 6; printf '2026-03-02 · 2026-03-02-payment-webhooks · Plan\n' ;;
esac
echo "[cut: +0 older — --before 2026-01-01]"
EOF
run nrank --repo "$WORK/full" --n 3 --base main --path new --wiki-tool "$WORK/stub/rank.sh"
expect_line nrank "new path: the lists interleave search-first and only the first 20 candidates count" \
  "recall@20=0.822 crosscut_recall@20=1.000 specs=3 path=new"

echo "== t_never_writes_to_clone =="
# fresh_marker <path>: a file every later write is -newer than. Linux stamps files with a coarse
# clock (one tick is several ms), so a write right after a plain touch can carry the same mtime
# and pass unnoticed; wait until a probe on the same filesystem is newer than the marker.
fresh_marker() {
  local n=0
  touch "$1"
  while touch "$1.probe" && [ -z "$(find "$1.probe" -newer "$1")" ] && [ "$n" -lt 5000 ]; do n=$((n + 1)); done
  rm -f "$1.probe"
}
# snapshot <repo>: every path, every file's checksum (inside .git too), git status (optional locks
# off, so the check itself writes nothing), the HEAD reflog and the refs.
snapshot() {
  ( cd "$1" && find . -print | LC_ALL=C sort && find . -type f -exec cksum {} + | LC_ALL=C sort -k3 )
  GIT_OPTIONAL_LOCKS=0 git -C "$1" status --porcelain=v1 -uall
  git -C "$1" reflog --format='%H %gs'
  git -C "$1" for-each-ref
}
# A clone with local state the harness must not touch: an uncommitted edit, a staged file and an
# untracked file. Both paths run from inside it, so a stray relative write would land there too.
T="$WORK/touched"
gx clone -q "$WORK/full" "$T" 2>/dev/null
printf 'local edit\n' >> "$T/src-app.txt"
printf 'staged\n' > "$T/staged.txt" && gx -C "$T" add staged.txt
printf 'untracked\n' > "$T/untracked.txt"
snapshot "$T" > "$WORK/snap.before"
fresh_marker "$WORK/marker"
( cd "$T" && bash "$H" --repo . --n 3 --path old > "$WORK/nw-old.out" 2>&1 ); rc_old=$?
( cd "$T/docs" && bash "$H" --repo .. --n 3 --path new --wiki-tool "$STUB" > "$WORK/nw-new.out" 2>&1 ); rc_new=$?
snapshot "$T" > "$WORK/snap.after"
newer="$(find "$T" -newer "$WORK/marker" -print | head -5)"
if [ "$rc_old" -eq 0 ] && [ "$rc_new" -eq 0 ]; then ok "both paths ran from inside the clone"
else bad "runs failed: old=$rc_old new=$rc_new: $(cat "$WORK/nw-old.out" "$WORK/nw-new.out")"; fi
if cmp -s "$WORK/snap.before" "$WORK/snap.after"; then ok "git status, reflog, refs and every file are unchanged"
else bad "the clone changed: $(diff "$WORK/snap.before" "$WORK/snap.after" | head -10 | tr '\n' ' ')"; fi
if [ -z "$newer" ]; then ok "no file in the clone was touched (mtime)"; else bad "touched: $newer"; fi
# The detector itself: a write to .git and a touch must both be caught.
D2="$WORK/detector"; cp -R "$T" "$D2"
snapshot "$D2" > "$WORK/snap.d1"; fresh_marker "$WORK/marker2"
printf 'x\n' >> "$D2/.git/description"
snapshot "$D2" > "$WORK/snap.d2"
if ! cmp -s "$WORK/snap.d1" "$WORK/snap.d2" && [ -n "$(find "$D2" -newer "$WORK/marker2" -print)" ]; then
  ok "self-test: the snapshot and the mtime check both catch a write inside .git"
else bad "self-test: a write inside .git went unnoticed"; fi
# Committed symlinks: _INDEX.md points (absolute) at a file in the clone that does not exist, so a
# write through it would create that file; _SEARCH_INDEX.md points at a live, untracked file in
# the clone that names AD-2. Both are left out of the replay trees: AD-1 is found through the
# regular active-project-context.md, AD-2 is not (0.500); the new path's registers give 1.000.
LK="$WORK/links"; R="$LK"; EOL=lf; gx init -q -b main "$R" >/dev/null
printf '## AD-01: One\n## AD-02: Two\n' | put "$WI/architecture-decisions.md"
printf -- '- Alpha sync: AD-01\n' | put "$WI/active-project-context.md"
ln -s "$LK/$WI/WRITTEN-BY-HARNESS.md" "$LK/$WI/_INDEX.md"
ln -s "$LK/live-notes.md" "$LK/$WI/_SEARCH_INDEX.md"
if [ -L "$LK/$WI/_INDEX.md" ] && [ -L "$LK/$WI/_SEARCH_INDEX.md" ]; then
  commit "root"
  printf '# Alpha sync design\n\nCites AD-01 and AD-02.\n' | put "$AR/specs/2026-07-01-alpha-sync-design.md"
  commit "spec: alpha sync"
  printf -- '- Alpha sync: AD-02\n' > "$LK/live-notes.md"
  snapshot "$LK" > "$WORK/snap.l1"; fresh_marker "$WORK/marker3"
  run lold --repo "$LK" --n 1 --base main
  run lnew --repo "$LK" --n 1 --base main --path new --wiki-tool "$STUB"; rc_lnew=$RC
  snapshot "$LK" > "$WORK/snap.l2"
  # Exactly one note on stderr: a symlink is neither followed nor filled in as an export-ignore gap.
  if [ "$(cat "$WORK/lold.out")" = "recall@20=0.500 crosscut_recall@20=n/a specs=1 path=old" ] \
     && [ "$rc_lnew" -eq 0 ] && [ "$(cat "$WORK/lnew.out")" = "recall@20=1.000 crosscut_recall@20=n/a specs=1 path=new" ] \
     && [ "$(cat "$WORK/lold.err")" = "wiki-retrieval-replay: note: 2 committed symlink(s) were left out of the replay trees (a link may point anywhere, the clone included)" ]; then
    ok "committed symlinks are left out of the replay trees, with a note (no live file is read)"
  else bad "symlink runs: old '$(cat "$WORK/lold.out")' new '$(cat "$WORK/lnew.out")' (exit $rc_lnew): $(cat "$WORK/lold.err" "$WORK/lnew.err" | tr '\n' ' ')"; fi
  if cmp -s "$WORK/snap.l1" "$WORK/snap.l2" && [ ! -e "$LK/$WI/WRITTEN-BY-HARNESS.md" ] \
     && [ -z "$(find "$LK" -newer "$WORK/marker3" -print | head -1)" ]; then
    ok "no write goes through a committed symlink into the clone"
  else bad "the symlinked clone changed: $(diff "$WORK/snap.l1" "$WORK/snap.l2" | head -10 | tr '\n' ' ')"; fi
else
  ok "symlink fixture skipped: this filesystem cannot create symlinks"
  ok "symlink write check skipped: this filesystem cannot create symlinks"
fi

echo "== missing inputs, preconditions, usage, help, cleanup, privacy =="
run last;                                           expect_exit 2 "no arguments: exit 2" "missing --repo"
run last --repo "$WORK/full" --bogus;               expect_exit 2 "unknown argument: exit 2" "unknown argument"
run last --repo;                                    expect_exit 2 "--repo without a value: exit 2" "needs a value"
run last --repo "$WORK/full" --path sideways;       expect_exit 2 "--path other than old|new: exit 2"
run last --repo "$WORK/full" --n 0;                 expect_exit 2 "--n 0: exit 2"
run last --repo "$WORK/full" --n x3;                expect_exit 2 "--n not a number: exit 2"
run last --repo "$WORK/full" --terms-file "$WORK/none"; expect_exit 2 "unreadable --terms-file: exit 2"
run last --repo "$WORK/full" --wiki-dir /abs/wiki;  expect_exit 2 "absolute --wiki-dir: exit 2"
run last --repo "$WORK/full/docs";                  expect_exit 2 "--repo below the top level of its clone: exit 2" "top level"
run last --repo "$WORK/missing-dir";                expect_exit 3 "--repo not a directory: exit 3"
mkdir -p "$WORK/plain"
run last --repo "$WORK/plain";                      expect_exit 3 "--repo not a git repository: exit 3"
run last --repo "$WORK/full" --base no-such-ref;    expect_exit 3 "unknown --base: exit 3" "base ref not found"
R="$WORK/nospecs"; EOL=lf; gx init -q -b main "$R" >/dev/null
printf 'x\n' > "$R/readme.txt"; commit "only code"
run last --repo "$WORK/nospecs";                    expect_exit 3 "no merged specs: exit 3" "no spec was ever added"
run last --repo "$WORK/nospecs" --wiki-dir wiki;    expect_exit 3 "--wiki-dir moves the specs directory too" "under artifacts/specs/"
# A wiki directory that no parent commit has (a typo, or a WIKI_PATH exported for another project)
# would score 0.000 and pass for a weak baseline: it is refused instead.
run last --repo "$WORK/full" --base main --wiki-dir docs/second-brain/wikii
expect_exit 3 "old path: no boot file at any parent commit: exit 3, not 0.000" \
  "no boot file under docs/second-brain/wikii at any parent commit (check --wiki-dir / WIKI_PATH)"
WIKI_PATH=docs/second-brain/kb run last --repo "$WORK/full" --base main
expect_exit 3 "a stray WIKI_PATH is the default wiki dir, so it is refused the same way" "no boot file under docs/second-brain/kb"
run last --repo "$WORK/full" --base main --path new --wiki-tool "$STUB" --wiki-dir docs/second-brain/wikii
expect_exit 3 "new path: no wiki directory at any parent commit: exit 3" \
  "no docs/second-brain/wikii directory at any parent commit"
# A shallow clone's boundary commit seems to add every older spec; a partial clone would fetch.
gx clone -q --depth 2 "file://$WORK/full" "$WORK/shallow" 2>/dev/null
run last --repo "$WORK/shallow";                    expect_exit 3 "a shallow clone: exit 3" "shallow clone"
gx clone -q "$WORK/full" "$WORK/partial" 2>/dev/null
git -C "$WORK/partial" config core.repositoryformatversion 1
git -C "$WORK/partial" config extensions.partialclone origin
run last --repo "$WORK/partial";                    expect_exit 3 "a partial clone: exit 3" "partial clone"
run help --help
if [ "$RC" -eq 0 ] && grep -q 'Exit codes' "$WORK/help.out" && grep -q 'aggregates only' "$WORK/help.out" \
   && grep -q 'Read-only' "$WORK/help.out" && grep -q 'Cost' "$WORK/help.out" \
   && grep -q 'shallow' "$WORK/help.out" && grep -q 'symlinks' "$WORK/help.out"; then
  ok "--help documents exit codes, output, read-only access, privacy and cost"
else bad "--help is incomplete (exit $RC)"; fi
# The temp directory is removed on success and on an error exit. Here TMPDIR sits inside a git
# repository, which the tool must not reach (STUB refuses a tree from which git finds one).
TR="$WORK/tmprepo"; gx init -q "$TR" >/dev/null; mkdir -p "$TR/tmp"
TMPDIR="$TR/tmp" run tmpok --repo "$WORK/full" --n 3 --base main --path new --wiki-tool "$STUB"; rc_tmpok=$RC
TMPDIR="$TR/tmp" run tmpdie --repo "$WORK/full" --n 3 --base main --path new --wiki-tool "$WORK/stub/fails.sh"; rc_tmpdie=$RC
if [ "$rc_tmpok" -eq 0 ] && [ "$rc_tmpdie" -eq 1 ] && [ -z "$(ls -A "$TR/tmp")" ]; then
  ok "the temp directory is removed after a run and after an error; no repository around it reaches the tool"
else bad "TMPDIR after runs (exits $rc_tmpok/$rc_tmpdie): [$(ls -A "$TR/tmp" | tr '\n' ' ')] $(cat "$WORK/tmpok.err")"; fi
# Aggregates only: fixture names, terms and IDs never reach stdout or stderr, whatever the path.
printf 'qzxcanary\n2026-02-01-invoice-retry-design\tqzxcanarytwo\n' > "$WORK/tf-canary"
run priv --repo "$WORK/full" --n 10 --base main --terms-file "$WORK/tf-canary"; rc_priv=$RC
run privnew --repo "$WORK/full" --n 10 --base main --path new --wiki-tool "$STUB" --terms-file "$WORK/tf-canary"; rc_privnew=$RC
leaks="$(cat "$WORK/priv.out" "$WORK/priv.err" "$WORK/privnew.out" "$WORK/privnew.err" \
  | grep -i -E 'canary|invoice|payment|refund|ledger|webhook|AD-0|TD-0|2026-|feat/|src-app|fixture' || true)"
lines="$(cat "$WORK/priv.out" "$WORK/privnew.out" | grep -c -v -E '^recall@20=([0-9]\.[0-9]{3}|n/a) crosscut_recall@20=([0-9]\.[0-9]{3}|n/a) specs=[0-9]+ path=(old|new)$')"
if [ "$rc_priv" -eq 0 ] && [ "$rc_privnew" -eq 0 ] && [ -z "$leaks" ] && [ "$lines" -eq 0 ] \
   && [ "$(cat "$WORK/priv.out" "$WORK/privnew.out" | grep -c '')" -eq 2 ] \
   && [ ! -s "$WORK/priv.err" ] && [ ! -s "$WORK/privnew.err" ]; then
  ok "output is one aggregate line per run; no name, term or ID leaks"
else bad "leak or extra output (exits $rc_priv/$rc_privnew): [$leaks] extra-lines=$lines"; fi

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
