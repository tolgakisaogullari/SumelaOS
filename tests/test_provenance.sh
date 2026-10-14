#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/test_provenance.sh — the provenance record, .sumela/.last-update.json (R1-03).
#
# The self-modification guard trusts ONE array of this record, "files": what the developer did not
# write. scripts/lib/sumela-provenance.{sh,ps1} read and write it for the updater, registry sync
# and the migration ledgers. This suite pins:
#   - the reader returns "files", only as an array of strings, and nothing from the other arrays;
#   - add_files deduplicates, binds each path to its HEAD and content in "carry", and never
#     changes a record's schema (a v1 record never starts vouching);
#   - a write keeps what the run's tools added earlier [RU-M4] while HEAD and the content are
#     unchanged, and nothing an EARLIER run vendored or a tool wrote and the developer then
#     committed or edited (a file written once must not vouch for hand edits forever);
#   - upstream_commit stays paired with its version; a finished record lends nothing;
#   - a git failure is named, never silent; bad input is refused and leaves the record unchanged;
#   - arrays are in byte order under any locale;
#   - the PowerShell twin writes the same bytes, without a BOM.
#
# Every case builds its own throwaway repository under $WORK. Commit dates are fixed, so two
# fixtures built the same way have the same HEAD (the parity steps compare "carry_head" bytes).
# pwsh is used when present (SKIP otherwise).
#
# Run from anywhere:  bash tests/test_provenance.sh
# Exit 0 = all assertions passed, 1 = a failure (printed above).
# -----------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/sumela-provenance.sh"
PSLIB="$REPO_ROOT/scripts/lib/sumela-provenance.ps1"
[ -f "$LIB" ] || { echo "FAIL: $LIB missing"; exit 1; }
# shellcheck source=../scripts/lib/sumela-provenance.sh
. "$LIB"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
WORK="$(cd "$WORK" && pwd -P)"
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_PREFIX
export GIT_AUTHOR_DATE='2026-10-14T00:00:00 +0000' GIT_COMMITTER_DATE='2026-10-14T00:00:00 +0000'

PASS=0 FAIL=0 PSN=0
ok()   { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP  $1"; }
same() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '      expected: %s\n      got:      %s\n' "$2" "$3"; fi; }
unchanged() { if cmp -s "$2" "$3"; then ok "$1"; else bad "$1 (the record changed)"; fi; }
TAB="$(printf '\t')"
PWSH="$(command -v pwsh 2>/dev/null || true)"

# mkinstall <dir> [<install-subdir>]: a repository with one commit and an install at the subdir.
# The record is gitignored, as in a consumer.
mkinstall() {
  local d="$1" i="${2:-.}"
  mkdir -p "$d/$i/.sumela/rules" "$d/$i/.sumela/migrations-applied" "$d/$i/scripts"
  git -C "$d" init -q -b main; git -C "$d" config user.email t@example.com; git -C "$d" config user.name Test
  echo .last-update.json > "$d/.gitignore"
  echo 0.19.0 > "$d/$i/.sumela/VERSION"; echo a > "$d/$i/.sumela/rules/a.md"; echo b > "$d/$i/scripts/b.sh"
  echo reg > "$d/$i/.sumela/SKILL_REGISTRY.md"
  git -C "$d" add -A && git -C "$d" commit -qm init
}
commit_all() { git -C "$1" add -A . && git -C "$1" commit -qm "${2:-commit}"; }
rec_of() { printf '%s/.sumela/.last-update.json' "$1"; }
blob() { git -C "$1" hash-object --no-filters -- "$2"; }      # <dir> <path>: the content a carry entry binds
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1"; printf '      wanted: %s\n      in:     %s\n' "$3" "$2" ;; esac; }
masked() { sed 's/"updated_at": "[^"]*"/"updated_at": "T"/' "$1"; }
# ps_run <dir> <statements>: pwsh from <dir> with the PowerShell twin loaded. Exit 0, or the
# exception's SumelaExitCode when a writer threw, or 9 for any other error.
ps_run() {
  PSN=$((PSN + 1))
  local f="$WORK/ps_$PSN.ps1"
  {
    echo '$ErrorActionPreference = "Stop"; Set-StrictMode -Version Latest'
    echo '. $env:t_pslib'
    echo 'try {'
    printf '%s\n' "$2"
    echo '} catch {'
    echo '  [Console]::Error.WriteLine($_.Exception.Message)'
    echo '  $c = $_.Exception.Data["SumelaExitCode"]; if ($null -eq $c) { exit 9 }; exit [int]$c'
    echo '}'
    echo 'exit 0'
  } > "$f"
  (cd "$1" && t_pslib="$PSLIB" "$PWSH" -NoProfile -NonInteractive -File "$f")
}

echo "== t_record_files_ignores_other_arrays"
d="$WORK/t1"; mkinstall "$d"
cat > "$(rec_of "$d")" <<'JSON'
{
  "updater_schema": 2,
  "version": "0.20.0",
  "base_version": "0.19.0",
  "upstream_commit": "0123abcd",
  "updated_at": "2026-10-14T00:00:00Z",
  "pending_rerun": false,
  "partial_upgrade": false,
  "files": [
    ".sumela/rules/a.md",
    "scripts/b.sh"
  ],
  "merged": [".sumela/skills/m/SKILL.md", ".sumela/skills/m2/SKILL.md"],
  "kept": [{"path": ".sumela/skills/k/SKILL.md", "why": "fork"}],
  "theirs_over_fork": [".sumela/skills/t/SKILL.md"],
  "removed": [".sumela/skills/r/SKILL.md"],
  "carry_head": "0123abcd",
  "carry": ["- .sumela/x.md"]
}
JSON
want="$(printf '.sumela/rules/a.md\nscripts/b.sh')"
same "files prints the files array and nothing else" "$want" "$(cd "$d" && sumela_record_files)"
same "…given the record path explicitly" "$want" "$(sumela_record_files "$(rec_of "$d")")"
# The plan's reference reader (R1-04 quotes it) must keep reading what the library writes.
ref_reader() {
  LC_ALL=C awk '/^  "files": \[/ { f = 1; next } f && /^  \]/ { exit }
                f { sub(/^ *"/, ""); sub(/",? *\r?$/, ""); if (length) print }' "$1"
}
(cd "$d" && sumela_record_write 0.20.0 complete --files "$(printf 'z.md\ny.md')" --merged ".sumela/m.md" \
   --kept ".sumela/k.md${TAB}fork" --theirs-over-fork ".sumela/t.md" --removed ".sumela/r.md")
same "a written record: files holds only the files rows, sorted" "$(printf 'y.md\nz.md')" "$(cd "$d" && sumela_record_files)"
same "…and the plan's reference reader reads the same list" "$(printf 'y.md\nz.md')" "$(ref_reader "$(rec_of "$d")")"
printf '{\n  "files": [],\n  "merged": ["m.md"]\n}\n' > "$WORK/oneline.json"
same "a one-line empty files array reads as empty, never as the next lines" "" "$(sumela_record_files "$WORK/oneline.json")"
same "no record: files prints nothing and exits 0" "0:" "$(out="$(sumela_record_files "$WORK/none.json")"; echo "$?:$out")"

echo "== t_record_add_dedupes"
d="$WORK/t2"; mkinstall "$d"; r="$(rec_of "$d")"
echo one > "$d/a.md"
(cd "$d" && sumela_record_add_files a.md a.md); rc=$?
same "add to a missing record: exit 0" 0 "$rc"
same "the path is recorded once" "a.md" "$(sumela_record_files "$r")"
same "a new record vouches for nothing: no version" "1" "$(sumela_record_get version "$r" >/dev/null; echo $?)"
same "…and no updater_schema" "1" "$(sumela_record_get updater_schema "$r" >/dev/null; echo $?)"
same "carry_head is the HEAD the path was recorded at" "$(git -C "$d" rev-parse HEAD)" "$(sumela_record_get carry_head "$r")"
(cd "$d" && sumela_record_add_files b.md a.md)
same "a second add merges, sorted, each path once" "$(printf 'a.md\nb.md')" "$(sumela_record_files "$r")"
same "carry binds each path to its content: its blob, or - when it is no file" \
  "$(printf '%s a.md\n- b.md' "$(blob "$d" a.md)")" "$(sumela_record_get carry "$r")"
cp "$r" "$WORK/t2.before"
(cd "$d" && sumela_record_add_files a.md b.md); rc=$?
same "re-adding recorded paths: exit 0" 0 "$rc"
unchanged "…and the record is not rewritten" "$WORK/t2.before" "$r"
echo two > "$d/a.md"
(cd "$d" && sumela_record_add_files a.md)
same "adding a path again records its new content" "$(printf '%s a.md\n- b.md' "$(blob "$d" a.md)")" "$(sumela_record_get carry "$r")"
(cd "$d" && sumela_record_add_files A.md)
same "paths are case-sensitive: A.md and a.md are two paths" "$(printf 'A.md\na.md\nb.md')" "$(sumela_record_files "$r")"
commit_all "$d"
(cd "$d" && sumela_record_add_files c.md)
same "an add at a new HEAD drops the entries of the old one" "- c.md" "$(sumela_record_get carry "$r")"
same "…and records the new HEAD" "$(git -C "$d" rev-parse HEAD)" "$(sumela_record_get carry_head "$r")"
same "…while files keeps every path" "$(printf 'A.md\na.md\nb.md\nc.md')" "$(sumela_record_files "$r")"

echo "== t_record_write_preserves_earlier_files"
# (a) The documented flow: a fresh upgrade worktree has no record. The pre-update ledgers and the
#     registry sync add theirs; the updater's write must keep them [RU-M4].
d="$WORK/t3a"; mkinstall "$d"; r="$(rec_of "$d")"
echo "status: done" > "$d/.sumela/migrations-applied/upgrade-01@0.20.0"
echo "reg2" > "$d/.sumela/SKILL_REGISTRY.md"
(cd "$d" && sumela_record_add_files .sumela/migrations-applied/upgrade-01@0.20.0 && sumela_record_add_files .sumela/SKILL_REGISTRY.md)
echo a2 > "$d/.sumela/rules/a.md"
(cd "$d" && sumela_record_write 0.20.0 complete --base-version 0.19.0 --files .sumela/rules/a.md); rc=$?
same "the write succeeds" 0 "$rc"
same "the run's earlier ledger and registry paths are kept beside the vendored file" \
  "$(printf '.sumela/SKILL_REGISTRY.md\n.sumela/migrations-applied/upgrade-01@0.20.0\n.sumela/rules/a.md')" "$(sumela_record_files "$r")"
same "a finished run's record has no carry list" "1 1" "$(sumela_record_get carry "$r" >/dev/null; echo $?) $(sumela_record_get carry_head "$r" >/dev/null; echo $?)"
same "the write stamps updater_schema 2" 2 "$(sumela_record_get updater_schema "$r")"
# Post-update steps add to the finished record; the guard must see them at review time.
echo "status: done" > "$d/.sumela/migrations-applied/upgrade-04@0.20.0"
(cd "$d" && sumela_record_add_files .sumela/migrations-applied/upgrade-04@0.20.0)
if sumela_record_files "$r" | grep -qxF .sumela/migrations-applied/upgrade-04@0.20.0; then ok "a post-update add lands in files"; else bad "a post-update add lands in files"; fi
# (b) The next run, in place. The earlier run's record and its tools' paths are committed; only
#     this run's uncommitted additions may be carried.
commit_all "$d" "upgrade to v0.20.0"
echo "status: done" > "$d/.sumela/migrations-applied/upgrade-01@0.20.1"
(cd "$d" && sumela_record_add_files .sumela/migrations-applied/upgrade-01@0.20.1)
echo b2 > "$d/scripts/b.sh"
(cd "$d" && sumela_record_write 0.20.1 complete --base-version 0.20.0 --files scripts/b.sh)
same "an earlier run's vendored and tool paths are not carried; this run's are" \
  "$(printf '.sumela/migrations-applied/upgrade-01@0.20.1\nscripts/b.sh')" "$(sumela_record_files "$r")"
# (c) A partial write, then the run completes in another process (--resolve): every row stays.
#     The partial pass applied a.md, so a.md is uncommitted when the run completes.
d="$WORK/t3c"; mkinstall "$d"; r="$(rec_of "$d")"
echo a2 > "$d/.sumela/rules/a.md"
(cd "$d" && sumela_record_write 0.19.0 partial --base-version 0.19.0 --upstream-commit 0a1b2c --files .sumela/rules/a.md \
   --merged scripts/b.sh --kept ".sumela/k.md${TAB}fork")
same "a partial write sets partial_upgrade" true "$(sumela_record_get partial_upgrade "$r")"
(cd "$d" && sumela_record_write 0.20.0 complete --theirs-over-fork .sumela/t.md)
same "completing keeps the partial pass's files" ".sumela/rules/a.md" "$(sumela_record_files "$r")"
same "…its merged rows" "scripts/b.sh" "$(sumela_record_get merged "$r")"
same "…its kept rows" ".sumela/k.md${TAB}fork" "$(sumela_record_get kept "$r")"
same "…adds the new theirs_over_fork row" ".sumela/t.md" "$(sumela_record_get theirs_over_fork "$r")"
same "…carries base_version" "0.19.0" "$(sumela_record_get base_version "$r")"
same "…but not 0.19.0's upstream_commit into a 0.20.0 record (it names the wrong release)" "" "$(sumela_record_get upstream_commit "$r")"
same "…and clears partial_upgrade" false "$(sumela_record_get partial_upgrade "$r")"
# (c2) upstream_commit stays paired with its version: a partial write that stays at the version
#      keeps it; a complete write records the one it is given.
d="$WORK/t3c2"; mkinstall "$d"; r="$(rec_of "$d")"
(cd "$d" && sumela_record_write 0.19.0 partial --base-version 0.19.0 --upstream-commit 0a1b2c --kept ".sumela/x.md${TAB}conflict:local")
(cd "$d" && sumela_record_write 0.19.0 partial)
same "a partial write at the same version keeps upstream_commit" "0a1b2c" "$(sumela_record_get upstream_commit "$r")"
same "…and the partial pass's rows" ".sumela/x.md${TAB}conflict:local" "$(sumela_record_get kept "$r")"
(cd "$d" && sumela_record_write 0.20.0 complete --upstream-commit 9f8e7d)
same "the completing write records the commit it is given" "9f8e7d" "$(sumela_record_get upstream_commit "$r")"
# (d) The two-pass flow: a pending_rerun record's files (the updater the first pass installed)
#     are carried by the re-run.
d="$WORK/t3d"; mkinstall "$d"; r="$(rec_of "$d")"
echo "new updater" > "$d/scripts/update.sh"
(cd "$d" && sumela_record_write 0.19.0 complete --pending-rerun --files scripts/update.sh)
same "--pending-rerun sets pending_rerun" true "$(sumela_record_get pending_rerun "$r")"
(cd "$d" && sumela_record_write 0.20.0 complete --files .sumela/rules/a.md)
same "the re-run carries the first pass's files" "$(printf '.sumela/rules/a.md\nscripts/update.sh')" "$(sumela_record_files "$r")"
same "…and clears pending_rerun" false "$(sumela_record_get pending_rerun "$r")"
# (e) A carried path classified anew leaves files: merged and theirs-over-fork never vouch.
d="$WORK/t3e"; mkinstall "$d"; r="$(rec_of "$d")"
(cd "$d" && sumela_record_write 0.19.0 partial --files "$(printf '.sumela/rules/a.md\nscripts/b.sh')")
(cd "$d" && sumela_record_write 0.20.0 complete --merged .sumela/rules/a.md --kept "scripts/b.sh${TAB}declined")
same "a reclassified path is no longer in files" "" "$(sumela_record_files "$r")"
same "…it is in its new class" ".sumela/rules/a.md|scripts/b.sh${TAB}declined" "$(sumela_record_get merged "$r")|$(sumela_record_get kept "$r")"
# (f) A dirty file of an EARLIER run's record is still not carried: only carry entries are.
d="$WORK/t3f"; mkinstall "$d"; r="$(rec_of "$d")"
echo a2 > "$d/.sumela/rules/a.md"; echo b2 > "$d/scripts/b.sh"
(cd "$d" && sumela_record_write 0.20.0 complete --files "$(printf '.sumela/rules/a.md\nscripts/b.sh')")
commit_all "$d"
echo "hand edit" >> "$d/.sumela/rules/a.md"
(cd "$d" && sumela_record_write 0.20.1 partial --files .sumela/VERSION)
same "an uncommitted hand-edit of an earlier run's file never starts vouching" ".sumela/VERSION" "$(sumela_record_files "$r")"
# (g) A monorepo install, paths with spaces: the dirty check cuts the install prefix.
d="$WORK/t3g"; mkinstall "$d" "svc/a b"; r="$(rec_of "$d/svc/a b")"
mkdir -p "$d/svc/a b/.sumela/migrations-applied/x y"
echo "done" > "$d/svc/a b/.sumela/migrations-applied/x y/ö ş"
(cd "$d/svc/a b" && sumela_record_add_files ".sumela/migrations-applied/x y/ö ş" .sumela/migrations-applied/missing)
(cd "$d/svc/a b/scripts" && sumela_record_write 0.20.0 complete --files scripts/b.sh)
same "in a monorepo install, an untracked ledger with spaces is carried; a missing one is not" \
  "$(printf '.sumela/migrations-applied/x y/ö ş\nscripts/b.sh')" "$(sumela_record_files "$r")"
# (i) An abandoned partial run: its files were restored (--undo-plan), but the gitignored record
#     still says partial_upgrade. The next run's write must not vouch for the restored file.
d="$WORK/t3i"; mkinstall "$d"; r="$(rec_of "$d")"
echo a2 > "$d/.sumela/rules/a.md"; echo b2 > "$d/scripts/b.sh"
(cd "$d" && sumela_record_write 0.19.0 partial --files "$(printf '.sumela/rules/a.md\nscripts/b.sh')" --merged .sumela/m.md)
git -C "$d" checkout -q -- .sumela/rules/a.md                  # restored; b.sh is still applied
(cd "$d" && sumela_record_write 0.20.0 complete --files .sumela/VERSION)
same "an abandoned run's restored file is not carried; its still-applied one is" \
  "$(printf '.sumela/VERSION\nscripts/b.sh')" "$(sumela_record_files "$r")"
# (h) A carry entry naming a directory never expands into the files below it.
d="$WORK/t3h"; mkinstall "$d"; r="$(rec_of "$d")"
mkdir -p "$d/.sumela/newdir"; echo n > "$d/.sumela/newdir/inner.md"
(cd "$d" && sumela_record_add_files .sumela/newdir && sumela_record_write 0.20.0 complete --files scripts/b.sh)
same "a directory entry is not expanded into its files" "scripts/b.sh" "$(sumela_record_files "$r")"
# (j) A tool path recorded after a finished run's write, committed, then hand-edited: the next
#     run's write must not carry it (HEAD moved since it was recorded).
d="$WORK/t3j"; mkinstall "$d"; r="$(rec_of "$d")"
echo a2 > "$d/.sumela/rules/a.md"; echo 0.20.0 > "$d/.sumela/VERSION"
(cd "$d" && sumela_record_write 0.20.0 complete --base-version 0.19.0 --files "$(printf '.sumela/rules/a.md\n.sumela/VERSION')")
echo "reg + synced skill" > "$d/.sumela/SKILL_REGISTRY.md"
(cd "$d" && sumela_record_add_files .sumela/SKILL_REGISTRY.md)
commit_all "$d" "upgrade to v0.20.0"
echo "reg + HAND-LOOSENED ENTRY" > "$d/.sumela/SKILL_REGISTRY.md"
echo b2 > "$d/scripts/b.sh"
(cd "$d" && sumela_record_write 0.20.1 complete --base-version 0.20.0 --files scripts/b.sh)
same "a committed tool path, hand-edited later, is not carried by the next run" "scripts/b.sh" "$(sumela_record_files "$r")"
# (k) The same at one HEAD: a tool path edited after it was recorded is not carried, and the
#     write names it.
d="$WORK/t3k"; mkinstall "$d"; r="$(rec_of "$d")"
echo "reg2" > "$d/.sumela/SKILL_REGISTRY.md"
(cd "$d" && sumela_record_add_files .sumela/SKILL_REGISTRY.md)
echo "reg2 + HAND-LOOSENED ENTRY" > "$d/.sumela/SKILL_REGISTRY.md"
err="$( (cd "$d" && sumela_record_write 0.20.0 complete --files scripts/b.sh) 2>&1 >/dev/null)"
same "a tool path edited after it was recorded is not carried" "scripts/b.sh" "$(sumela_record_files "$r")"
has "…and the write names it" "$err" ".sumela/SKILL_REGISTRY.md changed after it was recorded"
# (l) A partial run's file edited before the run completes is not carried; its untouched file is.
d="$WORK/t3l"; mkinstall "$d"; r="$(rec_of "$d")"
echo a2 > "$d/.sumela/rules/a.md"; echo b2 > "$d/scripts/b.sh"
(cd "$d" && sumela_record_write 0.19.0 partial --files "$(printf '.sumela/rules/a.md\nscripts/b.sh')")
same "a partial record lists its files in carry, with their content" \
  "$(printf '%s .sumela/rules/a.md\n%s scripts/b.sh' "$(blob "$d" .sumela/rules/a.md)" "$(blob "$d" scripts/b.sh)")" "$(sumela_record_get carry "$r")"
same "…at HEAD" "$(git -C "$d" rev-parse HEAD)" "$(sumela_record_get carry_head "$r")"
echo "a2 + hand edit" > "$d/.sumela/rules/a.md"
(cd "$d" && sumela_record_write 0.20.0 complete --files .sumela/VERSION 2>/dev/null)
same "a partial run's file edited before completion is not carried; the untouched one is" \
  "$(printf '.sumela/VERSION\nscripts/b.sh')" "$(sumela_record_files "$r")"
# (m) A recorded path that is gone by the write is not carried: an untracked file deleted, a
#     tracked one deleted, a tracked one git rm'd, a tracked one deleted before it was recorded
#     ("-", and an uncommitted deletion when the write runs). The run's other path still is.
d="$WORK/t3m"; mkinstall "$d"; r="$(rec_of "$d")"
echo done > "$d/.sumela/migrations-applied/s1"; echo done > "$d/.sumela/migrations-applied/s2"
echo b2 > "$d/scripts/b.sh"; echo reg2 > "$d/.sumela/SKILL_REGISTRY.md"; rm "$d/.sumela/rules/a.md"
(cd "$d" && sumela_record_add_files .sumela/migrations-applied/s1 .sumela/migrations-applied/s2 scripts/b.sh .sumela/SKILL_REGISTRY.md .sumela/rules/a.md)
rm "$d/.sumela/migrations-applied/s1" "$d/scripts/b.sh"
git -C "$d" rm -q -f .sumela/SKILL_REGISTRY.md
(cd "$d" && sumela_record_write 0.20.0 complete --files .sumela/VERSION)
same "deleted and git rm'd paths are not carried; the present one is" \
  "$(printf '.sumela/VERSION\n.sumela/migrations-applied/s2')" "$(sumela_record_files "$r")"
# (n) A finished run's record lends nothing: not its merged, kept, theirs-over-fork or removed
#     rows, not its base_version or upstream_commit.
d="$WORK/t3n"; mkinstall "$d"; r="$(rec_of "$d")"
(cd "$d" && sumela_record_write 0.20.0 complete --base-version 0.19.0 --upstream-commit 0a1b2c --files .sumela/rules/a.md \
   --merged .sumela/m.md --kept ".sumela/k.md${TAB}fork" --theirs-over-fork .sumela/t.md --removed .sumela/r.md)
(cd "$d" && sumela_record_write 0.20.0 complete --files scripts/b.sh)
for k in merged kept theirs_over_fork removed base_version upstream_commit; do
  same "a finished record's $k is not carried" "" "$(sumela_record_get "$k" "$r")"
done
same "…nor its files" "scripts/b.sh" "$(sumela_record_files "$r")"
# (p) An entry recorded at another HEAD is not carried even with its content unchanged: a commit
#     in between ends the run the entry belonged to.
d="$WORK/t3p"; mkinstall "$d"; r="$(rec_of "$d")"
echo "status: done" > "$d/.sumela/migrations-applied/x"
(cd "$d" && sumela_record_add_files .sumela/migrations-applied/x)
echo c > "$d/other.txt"; git -C "$d" add other.txt; git -C "$d" commit -qm other
(cd "$d" && sumela_record_write 0.20.0 complete --files scripts/b.sh)
same "an unchanged entry recorded before a commit is not carried" "scripts/b.sh" "$(sumela_record_files "$r")"
# (q) A name holding a line break never poses as another status entry: a directory named
#     "x<LF>?? .sumela" holding a SKILL_REGISTRY.md must not make the clean registry look
#     uncommitted.
d="$WORK/t3q"; mkinstall "$d"; r="$(rec_of "$d")"
(cd "$d" && sumela_record_add_files .sumela/SKILL_REGISTRY.md)        # clean: HEAD's content
weird="$d/.sumela/x
?? .sumela"
if mkdir -p "$weird" 2>/dev/null && echo z > "$weird/SKILL_REGISTRY.md" 2>/dev/null; then
  (cd "$d" && sumela_record_write 0.20.0 complete --files scripts/b.sh)
  same "a name with a line break does not make a clean recorded path look uncommitted" "scripts/b.sh" "$(sumela_record_files "$r")"
else
  skip "this file system refuses a line break in a name"
fi

echo "== t_record_write_refuses_bad_input"
d="$WORK/t4"; mkinstall "$d"; r="$(rec_of "$d")"
(cd "$d" && sumela_record_write 0.20.0 complete --files a.md)
cp "$r" "$WORK/t4.before"
try_write() {  # <label> <args...>
  local label="$1"; shift
  (cd "$d" && sumela_record_write "$@" 2>/dev/null); local rc=$?
  same "$label: exit 2" 2 "$rc"
  unchanged "$label: the record is unchanged" "$WORK/t4.before" "$r"
}
try_write "one path in two classes" 0.20.1 complete --files x.md --merged x.md
try_write "one kept path with two reasons" 0.20.1 complete --kept "$(printf 'k.md\tfork\nk.md\tdeclined')"
try_write "a path holding a quote" 0.20.1 complete --files 'q"x.md'
try_write "a path holding a backslash" 0.20.1 complete --files 'b\x.md'
try_write "a path holding a TAB" 0.20.1 complete --files "$(printf 't\tx.md')"
try_write "a path holding a control character" 0.20.1 complete --merged "$(printf 'c\001x.md')"
try_write "a kept row without a reason" 0.20.1 complete --kept k.md
try_write "a kept reason outside [a-z][a-z0-9:-]*" 0.20.1 complete --kept "k.md${TAB}Fork!"
try_write "a version that is not a version" '-rf' complete
try_write "an empty version" '' complete
try_write "an upstream commit that is not lowercase hex" 0.20.1 complete --upstream-commit 'HEAD~1'
# A line break would split a checked value into two rows, the second shaped like a valid one.
try_write "a version with a line break before a row-shaped line" "$(printf '0.20.1\npath\tx')" complete
try_write "a version ending in a line break" $'0.20.1\n' complete
try_write "a version ending in a CR" $'0.20.1\r' complete
try_write "a base version with a line break" 0.20.1 complete --base-version "$(printf '0.20.0\nversion\t1')"
try_write "an upstream commit with a line break" 0.20.1 complete --upstream-commit "$(printf 'abc\nwhy\tfork')"
try_write "a state that is neither complete nor partial" 0.20.1 "done"
try_write "an unknown option" 0.20.1 complete --bogus x
(cd "$d" && sumela_record_write 0.20.1 complete --files "$(printf 'crlf.md\r\nb.md\r')"); rc=$?
same "a list with CRLF line ends is read (one trailing CR per line dropped)" "0:b.md crlf.md" "$rc:$(sumela_record_files "$r" | tr '\n' ' ' | sed 's/ $//')"

echo "== t_record_add_refuses_bad_paths"
cp "$r" "$WORK/t4.before"
for p in 'q"x' 'b\x' "$(printf 't\tx')" "$(printf 'n\nx')" "$(printf 'c\001x')" ''; do
  (cd "$d" && sumela_record_add_files "$p" 2>/dev/null); rc=$?
  same "add refuses $(printf '%s' "$p" | od -An -c | tr -s ' ' | sed 's/^ //'): exit 2" 2 "$rc"
done
(cd "$d" && sumela_record_add_files ok.md 'bad"x' 2>/dev/null); rc=$?
same "one refused path refuses the whole call" 2 "$rc"
unchanged "…and the record is unchanged" "$WORK/t4.before" "$r"

echo "== t_record_get_values"
d="$WORK/t5"; mkinstall "$d"; r="$(rec_of "$d")"
(cd "$d" && sumela_record_write 0.20.0 partial --base-version 0.19.0 --upstream-commit abc --files a.md \
   --merged "$(printf 'm2.md\nm1.md')" --kept "$(printf 'k.md\tfork\nj.md\tupdater-floor')")
same "a string, unquoted" 0.20.0 "$(cd "$d" && sumela_record_get version)"
same "a number" 2 "$(sumela_record_get updater_schema "$r")"
same "a boolean" true "$(sumela_record_get partial_upgrade "$r")"
same "a one-line array, one element per line, sorted" "$(printf 'm1.md\nm2.md')" "$(sumela_record_get merged "$r")"
same "kept rows as <path><TAB><why>" "$(printf 'j.md\tupdater-floor\nk.md\tfork')" "$(sumela_record_get kept "$r")"
same "an empty array prints nothing, exit 0" "0:" "$(out="$(sumela_record_get removed "$r")"; echo "$?:$out")"
same "an absent key: exit 1" 1 "$(sumela_record_get nope "$r" >/dev/null; echo $?)"
same "an absent record: exit 1" 1 "$(sumela_record_get version "$WORK/none.json" >/dev/null; echo $?)"
same "an invalid key: exit 2" 2 "$(sumela_record_get 'Bad-Key' "$r" >/dev/null 2>&1; echo $?)"
UTF8_LOCALE="$(locale -a 2>/dev/null | LC_ALL=C grep -E '^(en_US|de_DE|tr_TR)\.(UTF-8|utf8)$' | head -1)"
if [ -n "$UTF8_LOCALE" ]; then
  # A child shell started under the locale: a temporary LC_ALL= on a function call does not
  # make bash re-read its locale.
  same "a non-ASCII key is invalid under $UTF8_LOCALE too (byte-based check): exit 2" 2 \
    "$(LC_ALL="$UTF8_LOCALE" bash -c '. "$1"; sumela_record_get "vérsion" "$2"' _ "$LIB" "$r" >/dev/null 2>&1; echo $?)"
else
  skip "non-ASCII key under a UTF-8 locale: none installed"
fi
same "outside any install: exit 1, nothing printed" "1:" "$(out="$(cd / && sumela_record_get version 2>/dev/null)"; echo "$?:$out")"

echo "== t_v1_record_compat"
# The record v0.19's update.sh writes, and the one its update.ps1 writes under Windows
# PowerShell 5.1: a BOM, a blank line in an empty files array, no final newline.
d="$WORK/t6"; mkinstall "$d"; r="$(rec_of "$d")"
v1_bash='{
  "version": "0.19.0",
  "updated_at": "2026-09-19T10:00:00Z",
  "pending_rerun": false,
  "files": [
    ".sumela/rules/a.md",
    "scripts/b.sh"
  ]
}'
printf '%s\n' "$v1_bash" > "$r"
same "a v1 record's files are read" "$(printf '.sumela/rules/a.md\nscripts/b.sh')" "$(sumela_record_files "$r")"
same "a v1 record has no updater_schema (it never vouches)" 1 "$(sumela_record_get updater_schema "$r" >/dev/null; echo $?)"
printf '%s\n' "$v1_bash" | sed 's/$/\r/' > "$WORK/v1crlf.json"
same "a CRLF copy reads the same" "$(sumela_record_files "$r")" "$(sumela_record_files "$WORK/v1crlf.json")"
same "…and its scalars carry no CR" "0.19.0" "$(sumela_record_get version "$WORK/v1crlf.json")"
printf '\357\273\277{\n  "version": "0.19.0",\n  "updated_at": "2026-09-19T10:00:00Z",\n  "pending_rerun": false,\n  "files": [\n\n  ]\n}' > "$WORK/v1bom.json"
same "a BOM, a blank line and no final newline: still readable" "0:0.19.0" "$(v="$(sumela_record_get version "$WORK/v1bom.json")"; echo "$?:$v")"
echo "status: done" > "$d/.sumela/migrations-applied/upgrade-01@0.20.0"
(cd "$d" && sumela_record_add_files .sumela/migrations-applied/upgrade-01@0.20.0)
same "add keeps a v1 record v1: no updater_schema appears" 1 "$(sumela_record_get updater_schema "$r" >/dev/null; echo $?)"
same "…its version and other values stay" "0.19.0 2026-09-19T10:00:00Z false" "$(sumela_record_get version "$r") $(sumela_record_get updated_at "$r") $(sumela_record_get pending_rerun "$r")"
same "…and files gains the path" "$(printf '.sumela/migrations-applied/upgrade-01@0.20.0\n.sumela/rules/a.md\nscripts/b.sh')" "$(sumela_record_files "$r")"
echo "fork" >> "$d/.sumela/rules/a.md"                         # dirty, but listed by the v1 record only
(cd "$d" && sumela_record_write 0.20.0 complete --files .sumela/VERSION)
same "a write over a finished v1 record carries only this run's added paths" \
  "$(printf '.sumela/VERSION\n.sumela/migrations-applied/upgrade-01@0.20.0')" "$(sumela_record_files "$r")"
cp "$WORK/v1bom.json" "$WORK/t6b.json"
sumela_record_add_files --record "$WORK/t6b.json" x.md 2> "$WORK/t6b.err"     # no git above $WORK: a warning, still written
same "add drops the BOM it found" "7b" "$(head -c 1 "$WORK/t6b.json" | od -An -tx1 | tr -d ' ')"
printf '%s\n' "$v1_bash" | sed 's/"pending_rerun": false/"pending_rerun": true/' > "$r"
echo "new b" > "$d/scripts/b.sh"                      # the first pass installed it: uncommitted
(cd "$d" && sumela_record_write 0.20.0 complete --files .sumela/VERSION)
same "a v1 pending_rerun record binds no content, so none of its files is carried" \
  ".sumela/VERSION" "$(sumela_record_files "$r")"

echo "== t_unreadable_record"
d="$WORK/t7"; mkinstall "$d"; r="$(rec_of "$d")"
printf '{\n  "files": [\n    "a.md",\n  "oops"\n}\n' > "$r"; cp "$r" "$WORK/t7.before"
(cd "$d" && sumela_record_add_files b.md 2>/dev/null); rc=$?
same "add to an unreadable record: exit 3" 3 "$rc"
unchanged "…and it is left unchanged" "$WORK/t7.before" "$r"
same "get on an unreadable record: exit 3" 3 "$(sumela_record_get version "$r" >/dev/null 2>&1; echo $?)"
same "files on an unreadable record vouches for nothing" "0:" "$(out="$(sumela_record_files "$r" 2>/dev/null)"; echo "$?:$out")"
err="$( (cd "$d" && sumela_record_write 0.20.0 complete --files c.md) 2>&1 >/dev/null)"; rc=$?
same "the updater's write replaces an unreadable record" "0:c.md" "$rc:$(sumela_record_files "$r")"
case "$err" in *unreadable*) ok "…and says so" ;; *) bad "…and says so (stderr: $err)" ;; esac
printf '{\n  "version": "0.20.0"\n}\n' > "$r"
(cd "$d" && sumela_record_add_files b.md 2>/dev/null); rc=$?
same "a record without a files array is not extended: exit 3" 3 "$rc"

echo "== t_files_only_as_an_array_of_strings"
# Any other shape of "files" vouches for nothing, and add_files leaves such a record alone.
for shape in '"a.md"' '[{"path": "a.md", "why": "fork"}]' '1' 'true' '["a.md", 1]'; do
  printf '{\n  "version": "0.20.0",\n  "files": %s\n}\n' "$shape" > "$WORK/shape.json"
  same "files as $shape vouches for nothing" "" "$(sumela_record_files "$WORK/shape.json" 2>/dev/null)"
  same "…and sumela_record_get files agrees (exit 0, nothing)" "0:" "$(out="$(sumela_record_get files "$WORK/shape.json" 2>/dev/null)"; echo "$?:$out")"
  cp "$WORK/shape.json" "$WORK/shape.before"
  (sumela_record_add_files --record "$WORK/shape.json" b.md 2>/dev/null); rc=$?
  same "add to a record whose files is $shape: exit 3" 3 "$rc"
  unchanged "…and it is left unchanged" "$WORK/shape.before" "$WORK/shape.json"
done
err="$(sumela_record_files "$WORK/shape.json" 2>&1 >/dev/null)"
has "the reader says why it vouches for nothing" "$err" "is not an array of strings"
printf '{\n  "files": ["a.md", "b.md"]\n}\n' > "$WORK/oneline2.json"
same "a one-line array of strings is read" "$(printf 'a.md\nb.md')" "$(sumela_record_files "$WORK/oneline2.json")"
# An invalid carry entry (a hand edit) is dropped with a message, never carried.
d="$WORK/t7b"; mkinstall "$d"; r="$(rec_of "$d")"
echo reg2 > "$d/.sumela/SKILL_REGISTRY.md"
printf '{\n  "files": [],\n  "carry_head": "%s",\n  "carry": ["XYZ .sumela/SKILL_REGISTRY.md"]\n}\n' "$(git -C "$d" rev-parse HEAD)" > "$r"
err="$( (cd "$d" && sumela_record_write 0.20.0 complete --files .sumela/VERSION) 2>&1 >/dev/null)"
same "an invalid carry entry is not carried" ".sumela/VERSION" "$(sumela_record_files "$r")"
has "…and the write says it dropped it" "$err" "dropped an invalid carry entry"

echo "== t_errexit_callers"
# Registry sync and the migration runner may run under set -euo pipefail. Absent keys (no record
# yet, a v1 record without merged/kept) and a failing git must never end the caller's shell.
d="$WORK/t9"; mkinstall "$d"; mkdir -p "$WORK/t9-nogit/.sumela"
cat > "$WORK/errexit.sh" <<'SH'
set -euo pipefail
. "$1"
cd "$2"
echo "status: done" > .sumela/migrations-applied/upgrade-01@0.20.0
sumela_record_add_files .sumela/migrations-applied/upgrade-01@0.20.0
sumela_record_write 0.20.0 complete --files .sumela/rules/a.md
sumela_record_files > /dev/null
printf '{\n  "version": "0.19.0",\n  "pending_rerun": true,\n  "files": [\n    "scripts/b.sh"\n  ]\n}\n' > .sumela/.last-update.json
sumela_record_write 0.20.0 complete --files .sumela/VERSION
echo "b2" > scripts/b.sh
sumela_record_write 0.20.1 partial --files scripts/b.sh --kept "$(printf 'k.md\tfork')"
sumela_record_write 0.20.1 complete
if sumela_record_get nope; then echo unexpected; fi
sumela_record_add_files --record "$3/.sumela/.last-update.json" x.md
sumela_record_write 0.20.0 complete --record "$3/.sumela/.last-update.json" --files y.md
echo "ok:$(sumela_record_files | tr '\n' ' ')|$(sumela_record_files "$3/.sumela/.last-update.json")"
SH
out="$(bash "$WORK/errexit.sh" "$LIB" "$d" "$WORK/t9-nogit" 2> "$WORK/errexit.err")"
same "every flow completes for a caller under set -euo pipefail" "ok:scripts/b.sh |y.md" "$out"
has "…and the add outside git says the next write will not carry it" "$(cat "$WORK/errexit.err")" "the next write will not carry them"

echo "== t_git_failure_is_reported"
# A git failure must never be silent: what is not carried is named on stderr with git's reason,
# and nothing is carried. First a git that fails one command (a shell function shadows git).
d="$WORK/t11b"; mkinstall "$d"; r="$(rec_of "$d")"
echo "status: done" > "$d/.sumela/migrations-applied/u1"
(cd "$d" && sumela_record_add_files .sumela/migrations-applied/u1)
cp "$r" "$WORK/t11b.rec"
for cmd in status hash-object; do
  cp "$WORK/t11b.rec" "$r"
  (   # a plain subshell: bash 3.2 cannot parse a case pattern inside $( )
    git() { case " $* " in *" $cmd "*) echo "fatal: simulated $cmd failure" >&2; return 128 ;; esac; command git "$@"; }
    cd "$d" && sumela_record_write 0.20.0 complete --files .sumela/VERSION
  ) > /dev/null 2> "$WORK/t11b.err"; rc=$?
  err="$(cat "$WORK/t11b.err")"
  same "a failing git $cmd does not fail the write: exit 0" 0 "$rc"
  same "…nothing is carried" ".sumela/VERSION" "$(sumela_record_files "$r")"
  has "…and stderr names git's reason and the count" "$err" "(fatal: simulated $cmd failure); 1 earlier path(s) not carried"
done
# Then a git that refuses the whole repository ("dubious ownership").
d="$WORK/t11"; mkinstall "$d"; r="$(rec_of "$d")"
echo "status: done" > "$d/.sumela/migrations-applied/upgrade-01@0.20.0"
(cd "$d" && sumela_record_add_files .sumela/migrations-applied/upgrade-01@0.20.0)
refuse() { GIT_TEST_ASSUME_DIFFERENT_OWNER=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 "$@"; }
if (cd "$d" && refuse git rev-parse --git-dir >/dev/null 2>&1); then
  skip "this git does not refuse a repository owned by another user (git 2.35.2 or later does)"
else
  err="$( (cd "$d" && refuse sumela_record_write 0.20.0 complete --files .sumela/VERSION) 2>&1 >/dev/null)"; rc=$?
  same "a git failure does not fail the write: exit 0" 0 "$rc"
  same "…nothing is carried" ".sumela/VERSION" "$(sumela_record_files "$r")"
  has "…and stderr says so" "$err" "cannot read the git state of"
  has "…counting what was not carried" "$err" "1 earlier path(s) not carried"
  case "$err" in *"git gave no reason"*) bad "…with git's reason (stderr: $err)" ;; *) ok "…with git's reason" ;; esac
  err="$( (cd "$d" && refuse sumela_record_add_files .sumela/x.md) 2>&1 >/dev/null)"; rc=$?
  same "add under a git failure still records the path: exit 0" "0:yes" "$rc:$(sumela_record_files "$r" | grep -qxF .sumela/x.md && echo yes)"
  has "…and says the next write will not carry it" "$err" "the next write will not carry them"
  err="$( (cd "$d" && refuse sumela_record_write 0.20.1 partial --files .sumela/VERSION) 2>&1 >/dev/null)"; rc=$?
  same "a partial write under a git failure: exit 0, no carry list" "0:1" "$rc:$(sumela_record_get carry "$r" >/dev/null; echo $?)"
  has "…and it says the completing write will not carry its files" "$err" "will not carry its files"
fi

echo "== t_byte_order_under_a_utf8_locale"
# Every array is in byte order whatever the caller's locale: the library sorts under LC_ALL=C.
# (A UTF-8 collation puts a.md before A.md and ö.md before Z.md.)
if [ -n "$UTF8_LOCALE" ]; then
  d="$WORK/t12"; mkinstall "$d"; r="$(rec_of "$d")"
  for f in b.md ö.md a.md; do echo x > "$d/$f"; done
  out="$(cd "$d" && LC_ALL="$UTF8_LOCALE" bash -c '. "$1"
    sumela_record_add_files b.md ö.md a.md &&
    sumela_record_write 0.20.0 partial --files "$(printf "Z.md\nA.md")" --merged "$(printf "m.md\nM.md")" \
      --kept "$(printf "k.md\tfork\nK.md\tfork")" --removed "$(printf "r.md\nR.md")" && echo written' _ "$LIB" 2>&1)"
  same "the writes succeed under $UTF8_LOCALE" "written" "$out"
  same "files in byte order" "$(printf 'A.md\nZ.md\na.md\nb.md\nö.md')" "$(sumela_record_files "$r")"
  same "merged in byte order" "$(printf 'M.md\nm.md')" "$(sumela_record_get merged "$r")"
  same "kept in byte order" "$(printf 'K.md\tfork\nk.md\tfork')" "$(sumela_record_get kept "$r")"
  same "removed in byte order" "$(printf 'R.md\nr.md')" "$(sumela_record_get removed "$r")"
  same "carry in byte order of its paths" "A.md Z.md a.md b.md ö.md" "$(sumela_record_get carry "$r" | cut -d' ' -f2- | tr '\n' ' ' | sed 's/ $//')"
else
  skip "byte order under a UTF-8 locale: none installed"
fi

echo "== t_record_written_by_ps_has_no_bom"
if [ -z "$PWSH" ]; then
  skip "pwsh unavailable"
else
  d="$WORK/t8"; mkinstall "$d"; r="$(rec_of "$d")"
  ps_run "$d" 'Write-SumelaRecord -Version 0.20.0 -State complete -Files @("a.md")'; rc=$?
  same "Write-SumelaRecord succeeds" 0 "$rc"
  same "Write-SumelaRecord writes no BOM" "7b" "$(head -c 1 "$r" | od -An -tx1 | tr -d ' ')"
  if LC_ALL=C grep -q "$(printf '\r')" "$r"; then bad "…and no CR"; else ok "…and no CR"; fi
  printf '\357\273\277{\n  "version": "0.19.0",\n  "pending_rerun": false,\n  "files": [\n\n  ]\n}' > "$r"
  ps_run "$d" 'Add-SumelaRecordFiles -Path "b.md"'; rc=$?
  same "Add-SumelaRecordFiles on v0.19's BOM record succeeds" 0 "$rc"
  same "…and drops the BOM" "7b" "$(head -c 1 "$r" | od -An -tx1 | tr -d ' ')"
  same "…keeping the record v1" 1 "$(sumela_record_get updater_schema "$r" >/dev/null; echo $?)"
fi

echo "== t_bash_ps_records_identical"
if [ -z "$PWSH" ]; then
  skip "pwsh unavailable"
else
  mkinstall "$WORK/tpl"
  echo "status: done" > "$WORK/tpl/.sumela/migrations-applied/upgrade-01@0.20.0"
  echo a2 > "$WORK/tpl/.sumela/rules/a.md"; echo b2 > "$WORK/tpl/scripts/b.sh"   # what the partial pass applied
  cp -R "$WORK/tpl" "$WORK/b"; cp -R "$WORK/tpl" "$WORK/p"
  B="$WORK/b"; P="$WORK/p"
  step=0
  # parity <label> <bash statements> <PowerShell statements>: run both, compare exit codes and bytes
  parity() {
    step=$((step + 1))
    (cd "$B" && eval "$2") >/dev/null 2>&1; local rb=$?
    ps_run "$P" "$3" >/dev/null 2>&1; local rp=$?
    if [ "$rb" != "$rp" ]; then bad "step $step ($1): exit codes differ (bash $rb, PowerShell $rp)"; return; fi
    if [ ! -f "$(rec_of "$B")" ] && [ ! -f "$(rec_of "$P")" ]; then ok "step $step ($1): exit $rb, no record"; return; fi
    if [ "$(masked "$(rec_of "$B")")" = "$(masked "$(rec_of "$P")")" ] && \
       [ "$(head -c 3 "$(rec_of "$B")" | od -An -tx1)" = "$(head -c 3 "$(rec_of "$P")" | od -An -tx1)" ]; then
      ok "step $step ($1): exit $rb, same bytes"
    else
      bad "step $step ($1): the records differ"; diff <(masked "$(rec_of "$B")") <(masked "$(rec_of "$P")") | head -10 | sed 's/^/      /'
    fi
  }
  parity "add to a missing record" \
    'sumela_record_add_files .sumela/migrations-applied/upgrade-01@0.20.0' \
    'Add-SumelaRecordFiles -Path ".sumela/migrations-applied/upgrade-01@0.20.0"'
  parity "add non-ASCII, spaces and a case pair" \
    'sumela_record_add_files ".sumela/skills/ö ş/SKILL.md" .sumela/skills/a.md .sumela/skills/A.md .sumela/skills/İı.md' \
    'Add-SumelaRecordFiles -Path @(".sumela/skills/ö ş/SKILL.md", ".sumela/skills/a.md", ".sumela/skills/A.md", ".sumela/skills/İı.md")'
  # A soft hyphen (U+00AD) is ignorable to a linguistic comparison: both paths must stay.
  parity "add two paths that differ only by a soft hyphen" \
    'sumela_record_add_files .sumela/skills/sh.md "$(printf ".sumela/skills/s\302\255h.md")"' \
    'Add-SumelaRecordFiles -Path @(".sumela/skills/sh.md", (".sumela/skills/s" + [char]0xAD + "h.md"))'
  parity "partial write with every array" \
    'sumela_record_write 0.19.0 partial --base-version 0.19.0 --upstream-commit 0a1b --files "$(printf ".sumela/rules/a.md\nscripts/b.sh")" --merged .sumela/skills/m.md --kept "$(printf ".sumela/skills/k.md\tfork\n.sumela/skills/z.md\tconflict:local")"' \
    'Write-SumelaRecord -Version 0.19.0 -State partial -BaseVersion 0.19.0 -UpstreamCommit 0a1b -Files @(".sumela/rules/a.md", "scripts/b.sh") -Merged ".sumela/skills/m.md" -Kept @(".sumela/skills/k.md`tfork", ".sumela/skills/z.md`tconflict:local")'
  parity "complete: a carried path classified anew" \
    'sumela_record_write 0.20.0 complete --theirs-over-fork .sumela/skills/t.md --kept "$(printf ".sumela/rules/a.md\tdeclined")"' \
    'Write-SumelaRecord -Version 0.20.0 -State complete -TheirsOverFork ".sumela/skills/t.md" -Kept ".sumela/rules/a.md`tdeclined"'
  parity "a post-update add to the finished record" \
    'sumela_record_add_files .sumela/SKILL_REGISTRY.md' \
    'Add-SumelaRecordFiles -Path ".sumela/SKILL_REGISTRY.md"'
  commit_all "$B"; commit_all "$P"
  same "the fixed commit dates give both fixtures one HEAD" "$(git -C "$B" rev-parse HEAD)" "$(git -C "$P" rev-parse HEAD)"
  for x in "$B" "$P"; do
    echo "status: done" > "$x/.sumela/migrations-applied/upgrade-01@0.20.1"
    echo "reg + HAND-LOOSENED ENTRY" > "$x/.sumela/SKILL_REGISTRY.md"   # recorded at the old HEAD: never carried
  done
  parity "the next run's pre-update ledger" \
    'sumela_record_add_files .sumela/migrations-applied/upgrade-01@0.20.1' \
    'Add-SumelaRecordFiles -Path ".sumela/migrations-applied/upgrade-01@0.20.1"'
  parity "the next run's write carries only this run's tool paths" \
    'sumela_record_write 0.20.1 complete --pending-rerun --files scripts/update.sh' \
    'Write-SumelaRecord -Version 0.20.1 -State complete -PendingRerun -Files "scripts/update.sh"'
  same "…not the registry hand-edited after the earlier run was committed" \
    "$(printf '.sumela/migrations-applied/upgrade-01@0.20.1\nscripts/update.sh')" "$(sumela_record_files "$(rec_of "$B")")"
  parity "the re-run carries the pending pass" \
    'sumela_record_write 0.20.2 complete --files "$(printf "x.md\ny.md")"' \
    'Write-SumelaRecord -Version 0.20.2 -State complete -Files "x.md`ny.md"'
  for x in "$B" "$P"; do echo "applied" > "$x/scripts/p.sh"; done
  parity "a partial write lists its files in carry" \
    'sumela_record_write 0.20.2 partial --files scripts/p.sh' \
    'Write-SumelaRecord -Version 0.20.2 -State partial -Files "scripts/p.sh"'
  for x in "$B" "$P"; do echo "applied + hand edit" > "$x/scripts/p.sh"; done
  parity "completing after a hand edit does not carry the edited file" \
    'sumela_record_write 0.20.3 complete --upstream-commit abc' \
    'Write-SumelaRecord -Version 0.20.3 -State complete -UpstreamCommit "abc"'
  same "…so files is empty" "" "$(sumela_record_files "$(rec_of "$B")")"
  parity "refused: one path in two classes" \
    'sumela_record_write 0.20.2 complete --files c.md --merged c.md' \
    'Write-SumelaRecord -Version 0.20.2 -State complete -Files "c.md" -Merged "c.md"'
  parity "refused: a quote in a path" \
    'sumela_record_add_files "q\"x"' \
    'Add-SumelaRecordFiles -Path "q`"x"'
  parity "refused: an upstream commit that is not hex" \
    'sumela_record_write 0.20.2 complete --upstream-commit XYZ' \
    'Write-SumelaRecord -Version 0.20.2 -State complete -UpstreamCommit "XYZ"'
  for x in "$B" "$P"; do printf '\357\273\277{\n  "version": "0.19.0",\n  "pending_rerun": false,\n  "files": [\n\n  ]\n}' > "$(rec_of "$x")"; done
  parity "add to v0.19's BOM record keeps it v1" \
    'sumela_record_add_files b.md' \
    'Add-SumelaRecordFiles -Path "b.md"'
  for x in "$B" "$P"; do printf '{\n  "files": [\n    "a.md",\n  "oops"\n}\n' > "$(rec_of "$x")"; done
  parity "refused: add to an unreadable record" \
    'sumela_record_add_files b.md' \
    'Add-SumelaRecordFiles -Path "b.md"'
  parity "the write replaces an unreadable record" \
    'sumela_record_write 0.20.2 complete --files c.md' \
    'Write-SumelaRecord -Version 0.20.2 -State complete -Files "c.md"'
  out_b="$(cd "$B" && sumela_record_get kept; sumela_record_get version; sumela_record_files)"
  out_p="$(ps_run "$P" '(Get-SumelaRecordValue -Key kept), (Get-SumelaRecordValue -Key version), (Get-SumelaRecordFiles) | ForEach-Object { $_ }' 2>/dev/null)"
  same "the readers agree" "$out_b" "$out_p"
fi

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
