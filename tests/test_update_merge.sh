#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/test_update_merge.sh — scripts/update.sh never overwrites a fork (R1-04).
#
# The updater classifies every CORE file three ways (LOCAL, BASE = upstream at the installed
# version, THEIRS = the new release's tag) and keeps local lines through `git merge-file`. This
# suite pins (each case builds its own fixture with tests/lib/upgrade-fixture.sh):
#   t01  an unmodified file takes upstream's copy and is vouched for in "files"
#   t02  a fork that upstream did not change stays byte-identical (kept: fork)
#   t02b a file you deleted is a readd row: it comes back only on your yes in a terminal
#   t03  a clean merge keeps the local line and the upstream line (merged, never "files")
#   t04  a conflict keeps LOCAL, writes .merge with markers, leaves VERSION (exit 3); --dry-run
#        writes nothing at all
#   t04b the re-run after a partial upgrade still merges, and a decision then completes it
#   t04c with no terminal and no --yes, nothing decides a fork (pre-commit included)
#   t04d an edited .merge survives the re-run as .merge.prev
#   t04e an unanswered .gitignore prompt adds nothing
#   t04f a .merge from an earlier run is never offered once its row is no longer a conflict
#   t04g a resolved .merge survives later runs, however many
#   t05  a CRLF copy of an unmodified file is "apply", not a fork
#   t06  a host file at a path upstream newly ships is never overwritten (collision)
#   t07  a base tree of another version, or a v2 record whose vouched files mostly differ,
#        disables merging: every differing row is review, and the files are named
#   t07b a v1 record listing files re-forked inside the upgrade commit never disables merging
#   t07c one forked file among four a v2 record vouches for is a fork, not a wrong base
#   t07d an unfinished run's record vouches for nothing, even for files edited since
#   t07e vouched files that already hold the new release are no evidence of a wrong base
#   t08  after an older updater overwrote forks and stamped VERSION (uncommitted), the forks
#        come back from HEAD and are merged
#   t08b ... also when that updater wrote a non-tag commit's bytes; your own uncommitted change
#        to a file it did not write is yours
#   t08c ... also when the project's .gitattributes export-ignores the CORE paths
#   t08d a release tree git archive cannot reproduce in full is refused
#   t08e ... and a file you deleted and committed is not re-added under --yes
#   t08f ... and what you staged before the run is named
#   t08g a change on top of that updater's write waits for you, with HEAD's copy as .head, in
#        this run and every later one until you decide
#   t08h your uncommitted edit to a file that updater did not write is merged, never dropped
#   t08i a gitignored live file absent from HEAD is never deleted
#   t08j HEAD's copy is back before any question, so [d]iff shows your fork as yours
#   t08k an untracked copy of an upstream file that nothing attributes is never removed
#   t08l a row waiting for your decision still waits after .sumela/.upgrade/ is cleaned away
#   t08m a working copy that is an upstream version older than the base is your revert
#   t09  the removed-files list: remove when LOCAL = BASE, keep-removed otherwise, rows outside
#        (installed, new] ignored
#   t09b a self-heal keeps a retired fork an older updater overwrote
#   t09c ... and your uncommitted edit to a retired file
#   t09d ... and a change on top of that updater's write to a retired file is a carry row
#   t10  a binary file is never merged
#   t11  a monorepo subdirectory install self-heals from HEAD:<prefix>
#   t12  interactive [s]kip all leaves VERSION and the record says partial (pty)
#   t13  interactive [k]eep is a decision: VERSION is stamped (pty)
#   t13b interactive: Enter, then end of input, decides nothing (pty)
#   t13c interactive: [t]heirs without the typed path replaces nothing (pty)
#   t13d interactive: [m]erged refuses a .merge that still has conflict markers (pty)
#   t13e `yes | update.sh` ends: three non-answers to a question (the first, or a row's) are no answer
#   t14  files that changed between a tag's version bump and the tag merge only when LOCAL is
#        one of the two copies, otherwise review
#   t15  the CORE list is the v0.19 one (both templates included)
#   t16  the record's upstream_commit is preferred over the tag as BASE
#   t16b a new scripts/update.sh defers the stamp to a re-run (exit 6), which still merges the
#        forks and carries the first pass
#   t16c the release's own updater finishes in one pass
#   t16d an updater older than v0.20.0 is never installed (kept: updater-floor)
#   t16e an older --source is refused: no downgrade
#   t16f a --force re-check of an uncommitted upgrade keeps its record and its forks
#   t16g a consumer-patched updater converges: the merged updater's own pass finishes
#   t16h a partial pass that installed a new updater names it, and only that updater finishes
#   t16i a cut during the record write leaves no temporary file
#   t27  a merged pre-commit stays executable, with no mode change in git diff
#   t28  an uncommitted file in --source is refused; --allow-dirty-source never installs it
#   t28b an untagged --source is refused; a shallow one resolves its origin's newest release
#   t29  a clean merge that breaks a merge pin becomes a conflict
#   t30  a retired fork whose successor is named becomes a carry row with its hunks
#   t30b removed-files rows outside the CORE paths are ignored
#   t31  the live _SCHEMA.md is merged against the template, keeping a local edit
#   t32  a release candidate tag is never the release a clone picks
# R1-05 extends this file with t17-t26 and t33-t37. The pty cases need python3 and a Unix pty:
# skipped otherwise. t28b's shallow part and t32 are skipped on Windows (file:// to an MSYS path).
#
# Run from anywhere:  bash tests/test_update_merge.sh [<case-prefix>...]
# Exit 0 = all assertions passed, 1 = a failure (printed above).
# -----------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UPDATER="$REPO_ROOT/scripts/update.sh"
PTY="$SCRIPT_DIR/lib/pty_run.py"
[ -f "$UPDATER" ] || { echo "FAIL: $UPDATER missing"; exit 1; }
# shellcheck source=lib/upgrade-fixture.sh
. "$SCRIPT_DIR/lib/upgrade-fixture.sh"
# shellcheck source=../scripts/lib/sumela-provenance.sh
. "$REPO_ROOT/scripts/lib/sumela-provenance.sh"

WORK="$(mktemp -d)"
trap 'cd / 2>/dev/null; rm -rf "$WORK"' EXIT
WORK="$(cd "$WORK" && pwd -P)"
# Every case runs the updater inside its own fixture. The suite itself stands in an empty scratch
# directory, so a run that forgot to cd finds no install ("No .sumela/ found") instead of updating
# the checkout this suite was started from.
mkdir "$WORK/cwd" && cd "$WORK/cwd" || { echo "FAIL: cannot enter $WORK/cwd"; exit 1; }
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_PREFIX
TAB="$(printf '\t')"

PASS=0 FAIL=0
ok()   { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP  $1"; }
tail_log() { [ -f "$1" ] && tail -n 40 "$1" | sed 's/^/      | /'; }
same() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '      expected: %s\n      got:      %s\n' "$2" "$3"; fi; }
expect_rc() {  # <label> <want> <got> <log>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (exit $3, wanted $2)"; tail_log "$4"; fi
}
strip_cr() { tr -d '\r' < "$1"; }
has_line()   { if [ -f "$2" ] && strip_cr "$2" | LC_ALL=C grep -qxF -- "$3"; then ok "$1"; else bad "$1 (no line '$3' in $2)"; fi; }
lacks_line() { if [ -f "$2" ] && ! strip_cr "$2" | LC_ALL=C grep -qxF -- "$3"; then ok "$1"; else bad "$1 (line '$3' in $2, or no file)"; fi; }
same_bytes() { if cmp -s "$2" "$3"; then ok "$1"; else bad "$1 ($2 and $3 differ)"; fi; }
same_text()  { if [ -f "$2" ] && [ -f "$3" ] && [ "$(strip_cr "$2")" = "$(strip_cr "$3")" ]; then ok "$1"; else bad "$1 ($2 and $3 differ)"; fi; }
exists()  { if [ -e "$2" ]; then ok "$1"; else bad "$1 ($2 missing)"; fi; }
absent()  { if [ ! -e "$2" ]; then ok "$1"; else bad "$1 ($2 exists)"; fi; }
log_has()   { if LC_ALL=C grep -qF -- "$3" "$2"; then ok "$1"; else bad "$1 (no '$3' in the output)"; tail_log "$2"; fi; }
log_lacks() { if ! LC_ALL=C grep -qF -- "$3" "$2"; then ok "$1"; else bad "$1 ('$3' in the output)"; LC_ALL=C grep -F -- "$3" "$2" | head -3 | sed 's/^/      | /'; fi; }
in_list()     { if printf '%s\n' "$2" | LC_ALL=C grep -qxF -- "$3"; then ok "$1"; else bad "$1 ('$3' not in: $(printf '%s' "$2" | tr '\n' ' '))"; fi; }
not_in_list() { if ! printf '%s\n' "$2" | LC_ALL=C grep -qxF -- "$3"; then ok "$1"; else bad "$1 ('$3' is listed)"; fi; }
rec() { sumela_record_get "$2" "$1/.sumela/.last-update.json" 2>/dev/null; }   # <install> <key>
rec_files() { sumela_record_files "$1/.sumela/.last-update.json"; }
ver_of() { tr -d '[:space:]' < "$1/.sumela/VERSION"; }
upg() { printf '%s/.sumela/.upgrade/%s' "$1" "$2"; }               # <install> <artifact>
is_windows() { case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac; return 1; }
pty_available() {
  command -v python3 >/dev/null 2>&1 && ! is_windows || return 1
  python3 -I "$PTY" --timeout 5 -- true >/dev/null 2>&1; [ $? -ne 126 ]
}
rc_in() {  # <label> <got> <log> <want>...: the exit is one of <want>
  local l="$1" got="$2" log="$3" w; shift 3
  for w in "$@"; do [ "$got" = "$w" ] && { ok "$l"; return; }; done
  bad "$l (exit $got, wanted one of: $*)"; tail_log "$log"
}
git_shim() {  # <dir>: a git that ignores GIT_ALLOW_PROTOCOL, so the updater may reach a file:// fixture
  local real; real="$(command -v git)"; mkdir -p "$1"
  printf '#!/bin/sh\nunset GIT_ALLOW_PROTOCOL\nexec "%s" "$@"\n' "$real" > "$1/git"; chmod 755 "$1/git"
}
A=.sumela/skills/alpha/SKILL.md B=.sumela/skills/beta/SKILL.md G=.sumela/skills/gamma/SKILL.md
P=.sumela/sumela-prompt.md H=.sumela/git-hooks/pre-commit

# base_upstream <dir>: fx_upstream, released as v0.19.0
base_upstream() { fx_upstream "$1" && fx_release "$1" 0.19.0; }

# --- t01 ---------------------------------------------------------------------------------
t01_unmodified_applies() {
  local d="$WORK/t01" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t01: exit 0" 0 "$rc" "$log"
  same_text "t01: the unmodified file is upstream's v0.20.0 copy" "$c/$A" "$up/$A"
  in_list "t01: it is vouched for in files" "$(rec_files "$c")" "$A"
  same "t01: VERSION is stamped" 0.20.0 "$(ver_of "$c")"
  same "t01: the record is v2 and complete" "2 0.20.0 false" "$(rec "$c" updater_schema) $(rec "$c" version) $(rec "$c" partial_upgrade)"
  same "t01: upstream_commit is the release's commit" "$(git -C "$up" rev-parse v0.20.0)" "$(rec "$c" upstream_commit)"
  same "t01: git status lists the file and VERSION only" "$(printf ' M .sumela/VERSION\n M %s' "$A")" "$(git -C "$c" status --porcelain)"
}

# --- t02 ---------------------------------------------------------------------------------
t02_fork_kept_when_upstream_unchanged() {
  local d="$WORK/t02" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$B" 3 "beta local three"; fx_commit "$c" "fork beta"
  cp "$c/$B" "$d/beta.before"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t02: exit 0" 0 "$rc" "$log"
  same_bytes "t02: the fork is byte-identical" "$d/beta.before" "$c/$B"
  in_list "t02: kept with why=fork" "$(rec "$c" kept)" "$B${TAB}fork"
  not_in_list "t02: never vouched for in files" "$(rec_files "$c")" "$B"
  same "t02: VERSION is stamped (a fork upstream did not touch needs no decision)" 0.20.0 "$(ver_of "$c")"
}

# --- t03 ---------------------------------------------------------------------------------
t03_clean_merge_keeps_local_lines() {
  local d="$WORK/t03" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_commit "$c" "fork alpha"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t03: exit 0" 0 "$rc" "$log"
  has_line "t03: the local line survives" "$c/$A" "alpha local three"
  has_line "t03: the upstream line arrives" "$c/$A" "alpha upstream twenty-five"
  in_list "t03: recorded in merged" "$(rec "$c" merged)" "$A"
  not_in_list "t03: never in files (its local hunks are reviewed as authored)" "$(rec_files "$c")" "$A"
  same "t03: VERSION is stamped" 0.20.0 "$(ver_of "$c")"
}

# --- t04 ---------------------------------------------------------------------------------
t04_conflict_keeps_local() {
  local d="$WORK/t04" rc; local up="$d/up" c="$d/c" log="$d/log" m
  base_upstream "$up"
  fx_set_line "$up/$A" 10 "alpha upstream ten"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 10 "alpha local ten"; fx_commit "$c" "fork alpha"
  cp "$c/$A" "$d/alpha.before"
  fx_update "$c" "$up" "$d/dry.log" --dry-run; rc=$?
  expect_rc "t04: --dry-run exits 0" 0 "$rc" "$d/dry.log"
  log_has "t04: --dry-run names the conflict" "$d/dry.log" "conflict     $A"
  same "t04: --dry-run writes nothing (git status is clean)" "" "$(git -C "$c" status --porcelain --ignored)"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t04: a conflict waits for a decision (exit 3)" 3 "$rc" "$log"
  same_bytes "t04: LOCAL is unchanged" "$d/alpha.before" "$c/$A"
  m="$(upg "$c" "$A.merge")"
  exists "t04: the merge is written to .sumela/.upgrade/<path>.merge" "$m"
  has_line "t04: .merge holds the local marker" "$m" "<<<<<<< local"
  has_line "t04: .merge holds the upstream marker" "$m" ">>>>>>> upstream v0.20.0"
  has_line "t04: .merge holds the local line" "$m" "alpha local ten"
  has_line "t04: .merge holds the upstream line" "$m" "alpha upstream ten"
  same "t04: VERSION is unchanged" 0.19.0 "$(ver_of "$c")"
  same "t04: the record says partial, at the installed version" "true 0.19.0" "$(rec "$c" partial_upgrade) $(rec "$c" version)"
  log_has "t04: the run names the waiting file" "$log" "Partial upgrade: 1 file(s)"
  # The install's own scripts/update.sh may still be a pre-0.20 updater: the hint names this one.
  log_has "t04: the re-run hint names the running updater and its source" "$log" "bash $UPDATER --source $up"
}

# --- t05 ---------------------------------------------------------------------------------
t05_crlf_local_is_unmodified() {
  local d="$WORK/t05" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_crlf "$c/$A"; fx_commit "$c" "a CRLF checkout"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t05: exit 0" 0 "$rc" "$log"
  same_text "t05: the CRLF copy took upstream's file (apply)" "$c/$A" "$up/$A"
  in_list "t05: vouched for in files" "$(rec_files "$c")" "$A"
  not_in_list "t05: not a merge" "$(rec "$c" merged)" "$A"
  log_lacks "t05: no conflict" "$log" "conflict"
}

# --- t06 ---------------------------------------------------------------------------------
t06_collision_host_file_kept() {
  local d="$WORK/t06" rc; local up="$d/up" c="$d/c" log="$d/log" D=.sumela/skills/delta/SKILL.md
  base_upstream "$up"
  mkdir -p "$up/.sumela/skills/delta"; fx_lines delta 30 > "$up/$D"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  mkdir -p "$c/.sumela/skills/delta"; echo "a host file of the project" > "$c/$D"; fx_commit "$c" "host file"
  cp "$c/$D" "$d/delta.before"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t06: a collision waits for a decision (exit 3)" 3 "$rc" "$log"
  same_bytes "t06: the host file is never overwritten" "$d/delta.before" "$c/$D"
  same_text "t06: upstream's copy is offered as .theirs" "$(upg "$c" "$D.theirs")" "$up/$D"
  log_has "t06: the row is a collision" "$log" "collision    $D"
  same "t06: VERSION is unchanged" 0.19.0 "$(ver_of "$c")"
}

# --- t07 ---------------------------------------------------------------------------------
t07_wrong_base_disables_merge() {
  local d="$WORK/t07" rc; local up="$d/up" c="$d/c" c2="$d/c2" log="$d/log" log2="$d/log2"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_set_line "$up/$G" 25 "gamma upstream twenty-five"
  fx_release "$up" 0.20.0
  # (a) the record's base commit is the v0.20.0 release: its tree says 0.20.0, the install 0.19.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_set_line "$c/$B" 3 "beta local three"; fx_commit "$c" forks
  fx_record_v2 "$c" 0.19.0 "$(git -C "$up" rev-parse v0.20.0)" "$P"
  cp "$c/$A" "$d/alpha.before"; cp "$c/$B" "$d/beta.before"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t07: a base of another version leaves every differing file waiting (exit 3)" 3 "$rc" "$log"
  log_has "t07: the run says why" "$log" "says v0.20.0, the install says v0.19.0: merging disabled"
  log_has "t07: the fork that would merge is review" "$log" "review       $A"
  log_has "t07: the fork that would be kept is review" "$log" "review       $B"
  log_has "t07: even the unmodified file is review (nothing proves it unmodified)" "$log" "review       $G"
  same_bytes "t07: fork one untouched" "$d/alpha.before" "$c/$A"
  same_bytes "t07: fork two untouched" "$d/beta.before" "$c/$B"
  same "t07: VERSION is unchanged" 0.19.0 "$(ver_of "$c")"
  # (b) a valid base, but three of the four files a v2 record vouches for differ from it
  fx_consumer "$c2" "$up" v0.19.0
  fx_set_line "$c2/$A" 3 "alpha local three"; fx_set_line "$c2/$B" 3 "beta local three"; fx_set_line "$c2/$G" 3 "gamma local three"
  fx_commit "$c2" forks
  fx_record_v2 "$c2" 0.19.0 "$(git -C "$up" rev-parse v0.19.0)" "$A" "$B" "$G" "$P"
  fx_update "$c2" "$up" "$log2" --yes; rc=$?
  expect_rc "t07: mostly-differing vouched files disable merging (exit 3)" 3 "$rc" "$log2"
  log_has "t07: the run counts them" "$log2" "3 of 4 vouched files differ from base v0.19.0 (wrong base?)"
  log_has "t07: the run names them" "$log2" " $A $B $G"
  log_has "t07: a fork is review then" "$log2" "review       $A"
}

# --- t07b --------------------------------------------------------------------------------
t07b_vouched_file_reforked_in_upgrade_commit() {
  local d="$WORK/t07b" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_set_line "$up/$G" 25 "gamma upstream twenty-five"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  # The flagship's shape: the upgrade commit re-forked files by hand, and the v1 record lists them.
  fx_set_line "$c/$A" 3 "alpha local three"; fx_set_line "$c/$B" 3 "beta local three"; fx_commit "$c" "upgrade, re-forked"
  fx_record_v1 "$c" 0.19.0 "$A" "$B" "$G" "$P"
  cp "$c/$B" "$d/beta.before"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t07b: exit 0" 0 "$rc" "$log"
  log_lacks "t07b: a v1 record never disables merging" "$log" "merging disabled"
  in_list "t07b: the re-forked file upstream changed is merged" "$(rec "$c" merged)" "$A"
  has_line "t07b: its local line survives" "$c/$A" "alpha local three"
  in_list "t07b: the re-forked file upstream left alone is kept" "$(rec "$c" kept)" "$B${TAB}fork"
  same_bytes "t07b: and untouched" "$d/beta.before" "$c/$B"
  in_list "t07b: the unforked upstream change is applied" "$(rec_files "$c")" "$G"
  same_text "t07b: with upstream's copy" "$c/$G" "$up/$G"
}

# --- t08 ---------------------------------------------------------------------------------
t08_self_heal_restores_fork() {
  local d="$WORK/t08" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_set_line "$up/$G" 25 "gamma upstream twenty-five"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_set_line "$c/$B" 3 "beta local three"; fx_commit "$c" forks
  git -C "$c" show "HEAD:$B" > "$d/beta.head"
  # A v0.19 pass on an empty answer: forks overwritten, VERSION stamped, a v1 record, no commit.
  fx_old_updater_pass "$c" "$up" v0.20.0 "$A" "$B" "$G"
  lacks_line "t08: (setup) the old pass overwrote the fork" "$c/$A" "alpha local three"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t08: exit 0" 0 "$rc" "$log"
  log_has "t08: the run says an older updater overwrote files" "$log" "an older updater"
  has_line "t08: the overwritten fork is back" "$c/$A" "alpha local three"
  has_line "t08: and merged with upstream's change" "$c/$A" "alpha upstream twenty-five"
  in_list "t08: recorded as merged" "$(rec "$c" merged)" "$A"
  same_text "t08: the fork upstream did not change is HEAD's copy again" "$c/$B" "$d/beta.head"
  same "t08: ... restored once (one line, one write)" 1 "$(LC_ALL=C grep -c "restored $B " "$log")"
  same_text "t08: the bytes that replaced it are kept as .working" "$(upg "$c" "$B.working")" "$up/$B"
  in_list "t08: kept as a fork" "$(rec "$c" kept)" "$B${TAB}fork"
  same_text "t08: the unforked file is upstream's" "$c/$G" "$up/$G"
  same "t08: VERSION is stamped" 0.20.0 "$(ver_of "$c")"
}

# --- t09 ---------------------------------------------------------------------------------
t09_removed_list() {
  local d="$WORK/t09" rc; local up="$d/up" c="$d/c" log="$d/log" E=.sumela/skills/epsilon/SKILL.md
  fx_upstream "$up"; mkdir -p "$up/.sumela/skills/epsilon"; fx_lines epsilon 30 > "$up/$E"; fx_release "$up" 0.19.0
  rm -rf "$up/.sumela/skills/beta" "$up/.sumela/skills/gamma" "$up/.sumela/skills/epsilon"
  mkdir -p "$up/scripts/lib"
  {
    echo "# retired CORE paths"
    printf '0.20.0\t%s\t-\n' "$G"
    printf '0.20.0\t%s\t-\r\n' "$B"          # a CRLF row reads the same
    printf '0.19.0\t%s\t-\n' "$E"            # retired by the installed version itself: not this upgrade's
  } > "$up/scripts/lib/sumela-removed-files.list"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$B" 3 "beta local three"; fx_commit "$c" "fork beta"
  cp "$c/$B" "$d/beta.before"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t09: exit 0 (both rows settle without a decision)" 0 "$rc" "$log"
  absent "t09: the unmodified retired file is removed" "$c/$G"
  absent "t09: and its emptied directory" "$c/.sumela/skills/gamma"
  in_list "t09: recorded in removed" "$(rec "$c" removed)" "$G"
  same_bytes "t09: the modified retired file is kept" "$d/beta.before" "$c/$B"
  in_list "t09: recorded as kept: removed-upstream" "$(rec "$c" kept)" "$B${TAB}removed-upstream"
  exists "t09: a row outside (installed, new] is ignored" "$c/$E"
  same "t09: VERSION is stamped" 0.20.0 "$(ver_of "$c")"
}

# --- t10 ---------------------------------------------------------------------------------
t10_binary_not_merged() {
  local d="$WORK/t10" rc; local up="$d/up" c="$d/c" log="$d/log" X=.sumela/skills/alpha/asset.bin
  fx_upstream "$up"; printf 'BIN\000one\n' > "$up/$X"; fx_release "$up" 0.19.0
  printf 'BIN\000two\n' > "$up/$X"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  printf 'BIN\000mine\n' > "$c/$X"; fx_commit "$c" "local binary"
  cp "$c/$X" "$d/bin.before"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t10: a binary fork waits for a decision (exit 3)" 3 "$rc" "$log"
  log_has "t10: it is review, as a binary file" "$log" "review       $X  (binary file)"
  same_bytes "t10: LOCAL is unchanged" "$d/bin.before" "$c/$X"
  same_bytes "t10: upstream's copy is offered as .theirs" "$up/$X" "$(upg "$c" "$X.theirs")"
  absent "t10: no .merge is made" "$(upg "$c" "$X.merge")"
}

# --- t11 ---------------------------------------------------------------------------------
t11_monorepo_subdir_install() {
  local d="$WORK/t11" rc; local up="$d/up" c="$d/c" log="$d/log" i
  i="$c/apps/web"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_set_line "$up/$G" 25 "gamma upstream twenty-five"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0 apps/web
  fx_set_line "$i/$A" 3 "alpha local three"; fx_set_line "$i/$B" 3 "beta local three"; fx_commit "$c" forks
  git -C "$c" show "HEAD:apps/web/$B" > "$d/beta.head"
  fx_old_updater_pass "$i" "$up" v0.20.0 "$A" "$B" "$G"
  fx_update "$i" "$up" "$log" --yes; rc=$?
  expect_rc "t11: exit 0" 0 "$rc" "$log"
  has_line "t11: the fork is restored from HEAD:apps/web/" "$i/$A" "alpha local three"
  has_line "t11: and merged" "$i/$A" "alpha upstream twenty-five"
  same_text "t11: the other fork is HEAD's copy again" "$i/$B" "$d/beta.head"
  same_text "t11: the unforked file is upstream's" "$i/$G" "$up/$G"
  same "t11: VERSION is stamped" 0.20.0 "$(ver_of "$i")"
  same "t11: nothing outside the install changed" "" "$(git -C "$c" status --porcelain | LC_ALL=C grep -v '^.. apps/web/' || true)"
}

# --- t12 / t13 (pty) ---------------------------------------------------------------------
conflict_fixture() {  # <dir>: an upstream and a consumer with one conflicting fork of alpha
  base_upstream "$1/up"
  fx_set_line "$1/up/$A" 10 "alpha upstream ten"; fx_release "$1/up" 0.20.0
  fx_consumer "$1/c" "$1/up" v0.19.0
  fx_set_line "$1/c/$A" 10 "alpha local ten"; fx_commit "$1/c" "fork alpha"
  cp "$1/c/$A" "$1/alpha.before"
}
t12_interactive_skip_all_does_not_stamp() {
  local d="$WORK/t12" rc
  pty_available || { skip "t12: needs python3 and a Unix pty"; return 0; }
  conflict_fixture "$d"
  fx_env python3 -I "$PTY" --cwd "$d/c" --log "$d/log" --expect 'need your decision' --send s \
    -- "${BASH:-bash}" "$UPDATER" --source "$d/up"; rc=$?
  expect_rc "t12: [s]kip all leaves a partial upgrade (exit 3)" 3 "$rc" "$d/log"
  same "t12: VERSION is not stamped" 0.19.0 "$(ver_of "$d/c")"
  same "t12: the record says partial" true "$(rec "$d/c" partial_upgrade)"
  same_bytes "t12: the fork is unchanged" "$d/alpha.before" "$d/c/$A"
  log_has "t12: the run lists what waits" "$d/log" "Partial upgrade: 1 file(s)"
}
t13_interactive_keep_is_deliberate() {
  local d="$WORK/t13" rc
  pty_available || { skip "t13: needs python3 and a Unix pty"; return 0; }
  conflict_fixture "$d"
  fx_env python3 -I "$PTY" --cwd "$d/c" --log "$d/log" --expect 'need your decision' --send r \
    --expect '\[k\]eep / \[m\]erged' --send k -- "${BASH:-bash}" "$UPDATER" --source "$d/up"; rc=$?
  expect_rc "t13: exit 0" 0 "$rc" "$d/log"
  same "t13: VERSION is stamped: keeping the fork was a decision" 0.20.0 "$(ver_of "$d/c")"
  in_list "t13: kept as conflict:local" "$(rec "$d/c" kept)" "$A${TAB}conflict:local"
  same "t13: the record is complete" false "$(rec "$d/c" partial_upgrade)"
  same_bytes "t13: the fork is unchanged" "$d/alpha.before" "$d/c/$A"
}

# --- t14 ---------------------------------------------------------------------------------
t14_ambiguous_tag_files() {
  local d="$WORK/t14" rc bump; local up="$d/up" c="$d/c" log="$d/log" n
  local E1=.sumela/skills/eps/e1.md E2=.sumela/skills/eps/e2.md E3=.sumela/skills/eps/e3.md
  fx_upstream "$up"; mkdir -p "$up/.sumela/skills/eps"
  for n in 1 2 3; do fx_lines "e$n" 30 > "$up/.sumela/skills/eps/e$n.md"; done
  fx_release "$up" 0.19.0 --no-tag; bump="$(git -C "$up" rev-parse HEAD)"   # the VERSION bump
  for n in 1 2 3; do fx_set_line "$up/.sumela/skills/eps/e$n.md" 10 "e$n tag ten"; done
  fx_commit "$up" "a fix after the bump"; git -C "$up" tag v0.19.0              # the tag, one commit later
  for n in 1 2 3; do fx_set_line "$up/.sumela/skills/eps/e$n.md" 25 "e$n upstream twenty-five"; done
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  git -C "$up" show "$bump:$E1" > "$c/$E1"                                     # installed at the bump
  git -C "$up" show "$bump:$E3" > "$c/$E3"; fx_set_line "$c/$E3" 3 "e3 local three"   # the bump's copy, forked
  fx_set_line "$c/$B" 3 "beta local three"                                     # an ordinary fork
  fx_commit "$c" "installed between the bump and the tag"
  cp "$c/$E3" "$d/e3.before"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t14: the ambiguous fork waits (exit 3)" 3 "$rc" "$log"
  same_text "t14: LOCAL = the bump's copy applies" "$c/$E1" "$up/$E1"
  same_text "t14: LOCAL = the tag's copy applies" "$c/$E2" "$up/$E2"
  log_has "t14: LOCAL = neither is review" "$log" "review       $E3  (the v0.19.0 tag sits after its version bump"
  same_bytes "t14: and untouched" "$d/e3.before" "$c/$E3"
  in_list "t14: a file that did not change between bump and tag is classified as usual" "$(rec "$c" kept)" "$B${TAB}fork"
}

# --- t15 ---------------------------------------------------------------------------------
core_list() {  # <update.sh> -> "CORE_FILES:<path>" and "CORE_DIRS:<path>" lines
  LC_ALL=C awk '{ sub(/\r$/, "") } /^CORE_(FILES|DIRS)=\(/ { a = substr($0, 1, index($0, "=") - 1); next }
    a != "" && /^\)/ { a = ""; next }
    a != "" { l = $0; sub(/^[ \t]+/, "", l); if (l ~ /^"/) { sub(/^"/, "", l); sub(/".*$/, "", l); print a ":" l } }' "$1"
}
t15_core_files_list_unchanged() {
  local want got
  want="$(printf 'CORE_FILES:%s\n' .sumela/sumela-prompt.md .sumela/rules/engineering_philosophy.md \
    .sumela/rules/identity_and_behavior.md .sumela/rules/architecture_patterns.md .sumela/rules/audit_and_output.md \
    .sumela/rules/security_protocol.md .sumela/rules/git_workflow_mandatory_review_protocol.md \
    .sumela/rules/self_improvement_protocol.md .sumela/rules/operational_excellence_maintenance.md.template \
    .sumela/RULE_REGISTRY.md.template
    printf 'CORE_DIRS:%s\n' .sumela/skills .sumela/git-hooks .sumela/memory-plugins .sumela/rules/templates \
    docs/second-brain/template scripts)"
  got="$(core_list "$UPDATER")"
  same "t15: CORE_FILES and CORE_DIRS are the v0.19 lists" "$want" "$got"
  if git -C "$REPO_ROOT" cat-file -e v0.19.0:scripts/update.sh 2>/dev/null; then
    git -C "$REPO_ROOT" show v0.19.0:scripts/update.sh > "$WORK/update-0.19.sh"
    same "t15: ... and match the v0.19.0 tag's updater" "$(core_list "$WORK/update-0.19.sh")" "$got"
  else
    skip "t15: the v0.19.0 tag is not in this clone"
  fi
}

# --- t16 ---------------------------------------------------------------------------------
t16_base_from_record_commit_preferred() {
  local d="$WORK/t16" rc side; local up="$d/up" c="$d/c" c2="$d/c2" log="$d/log" log2="$d/log2"
  base_upstream "$up"
  git -C "$up" checkout -q -b maint
  fx_set_line "$up/$A" 10 "alpha maint ten"; fx_commit "$up" "a maintenance build of 0.19.0"
  side="$(git -C "$up" rev-parse HEAD)"
  git -C "$up" checkout -q main
  fx_set_line "$up/$A" 10 "alpha upstream ten"; fx_release "$up" 0.20.0
  # Installed from the maintenance commit, which the v2 record names.
  fx_consumer "$c" "$up" "$side"
  fx_record_v2 "$c" 0.19.0 "$side" "$A"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t16: exit 0" 0 "$rc" "$log"
  log_has "t16: the base is the recorded commit" "$log" "Base:     the recorded commit ${side:0:12}"
  has_line "t16: LOCAL = that base, so upstream's copy applies" "$c/$A" "alpha upstream ten"
  in_list "t16: vouched for in files" "$(rec_files "$c")" "$A"
  # The same install without the record falls back to the tag, where the file is a conflict.
  fx_consumer "$c2" "$up" "$side"
  fx_update "$c2" "$up" "$log2" --yes; rc=$?
  expect_rc "t16: without the record the tag is the base: a conflict (exit 3)" 3 "$rc" "$log2"
  has_line "t16: and the file is kept" "$c2/$A" "alpha maint ten"
}

# --- t16b --------------------------------------------------------------------------------
# release_updater <upstream> <label>: the release ships a working updater (this one, marked with
# <label>, so each release's copy differs) and the library it sources.
release_updater() {
  # The framework pins its scripts to LF, so the updater it ships runs from a CRLF checkout too.
  printf '*.sh text eol=lf\n' > "$1/.gitattributes"
  mkdir -p "$1/scripts/lib"; cp "$REPO_ROOT/scripts/lib/sumela-provenance.sh" "$1/scripts/lib/"
  { cat "$UPDATER"; echo "# release build: $2"; } > "$1/scripts/update.sh"; chmod 755 "$1/scripts/update.sh"
}
t16b_updater_change_defers_stamp_until_rerun() {
  local d="$WORK/t16b" rc; local up="$d/up" c="$d/c" log="$d/log" log2="$d/log2" U=scripts/update.sh
  fx_upstream "$up"; fx_updater_stub "$up/$U" 0.19; fx_release "$up" 0.19.0
  release_updater "$up" 0.20.0
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_set_line "$up/$G" 25 "gamma upstream twenty-five"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_set_line "$c/$B" 3 "beta local three"; fx_commit "$c" forks
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t16b: the first pass exits 6 (re-run pending)" 6 "$rc" "$log"
  same_text "t16b: the new updater is installed" "$c/$U" "$up/$U"
  has_line "t16b: the outgoing one is kept as .bak" "$c/$U.bak" 'echo "updater stub 0.19"'
  same "t16b: VERSION waits for the re-run" 0.19.0 "$(ver_of "$c")"
  same "t16b: the record says a re-run is pending" "true 0.19.0" "$(rec "$c" pending_rerun) $(rec "$c" version)"
  log_has "t16b: the run names the new updater, by absolute path" "$log" "bash $c/scripts/update.sh --source $up"
  # An older updater's pass never clears the deferral; the new updater's does. It must keep
  # merging too: the pending record lists files that already hold v0.20.0's bytes.
  fx_update "$c" "$up" "$d/log1b" --yes; rc=$?
  expect_rc "t16b: an older updater's pass still defers (exit 6)" 6 "$rc" "$d/log1b"
  same "t16b: ... and leaves VERSION" 0.19.0 "$(ver_of "$c")"
  (cd "$c" && fx_env "${BASH:-bash}" "$c/$U" --source "$up" --yes) < /dev/null > "$log2" 2>&1; rc=$?
  expect_rc "t16b: the new updater's re-run exits 0" 0 "$rc" "$log2"
  log_lacks "t16b: the pending record never disables merging" "$log2" "merging disabled"
  same "t16b: the re-run stamps VERSION" 0.20.0 "$(ver_of "$c")"
  same "t16b: the record is complete" "false false" "$(rec "$c" pending_rerun) $(rec "$c" partial_upgrade)"
  has_line "t16b: the merged fork keeps its local line" "$c/$A" "alpha local three"
  has_line "t16b: ... and upstream's" "$c/$A" "alpha upstream twenty-five"
  in_list "t16b: it is still recorded as merged" "$(rec "$c" merged)" "$A"
  in_list "t16b: the other fork is kept" "$(rec "$c" kept)" "$B${TAB}fork"
  in_list "t16b: the first pass's updater is still vouched for" "$(rec_files "$c")" "$U"
  in_list "t16b: and its other file" "$(rec_files "$c")" "$G"
}

# --- t16g --------------------------------------------------------------------------------
t16g_patched_updater_converges() {
  local d="$WORK/t16g" rc1 rc2; local up="$d/up" c="$d/c" U=scripts/update.sh
  fx_upstream "$up"; mkdir -p "$up/scripts/lib"; cp "$REPO_ROOT/scripts/lib/sumela-provenance.sh" "$up/scripts/lib/"
  printf '*.sh text eol=lf\n' > "$up/.gitattributes"                            # as the framework ships its scripts
  LC_ALL=C awk 'NR == 4 { print "# an earlier release'"'"'s wording of this line"; next } { print }' "$UPDATER" > "$up/$U"
  chmod 755 "$up/$U"; fx_release "$up" 0.19.0
  cp "$UPDATER" "$up/$U"; fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  echo "# consumer patch: a note for our CI wrapper" >> "$c/$U"                   # far from line 4: a clean merge
  fx_set_line "$c/$B" 3 "beta local three"; fx_commit "$c" "patched updater, a fork"
  (cd "$c" && fx_env "${BASH:-bash}" "$c/$U" --source "$up" --yes) < /dev/null > "$d/log1" 2>&1; rc1=$?
  (cd "$c" && fx_env "${BASH:-bash}" "$c/$U" --source "$up" --yes) < /dev/null > "$d/log2" 2>&1; rc2=$?
  expect_rc "t16g: pass 1 installs the merged updater and defers (exit 6)" 6 "$rc1" "$d/log1"
  expect_rc "t16g: pass 2, by that updater, finishes (exit 0)" 0 "$rc2" "$d/log2"
  same "t16g: VERSION is stamped" 0.20.0 "$(ver_of "$c")"
  has_line "t16g: the consumer's patch survives" "$c/$U" "# consumer patch: a note for our CI wrapper"
  same "t16g: upstream's change arrived" "$(sed -n 4p "$UPDATER")" "$(sed -n 4p "$c/$U")"
}

# --- t16h --------------------------------------------------------------------------------
t16h_partial_pass_names_the_new_updater() {
  local d="$WORK/t16h" rc; local up="$d/up" c="$d/c" U=scripts/update.sh
  fx_upstream "$up"; release_updater "$up" 0.19.0; fx_release "$up" 0.19.0
  release_updater "$up" 0.20.0; fx_set_line "$up/$A" 10 "alpha upstream ten"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 10 "alpha local ten"; fx_commit "$c" fork
  fx_update "$c" "$up" "$d/log1" --yes; rc=$?                                   # this repository's updater: an older one
  expect_rc "t16h: pass 1 is partial (exit 3)" 3 "$rc" "$d/log1"
  log_has "t16h: the hint names the updater this pass installed" "$d/log1" "bash $c/scripts/update.sh --source $up   (the new updater this run installed)"
  same "t16h: the record defers to it" "true true" "$(rec "$c" partial_upgrade) $(rec "$c" pending_rerun)"
  if pty_available; then
    fx_env python3 -I "$PTY" --cwd "$c" --log "$d/log2" --expect 'need your decision' --send r \
      --expect '\[k\]eep / \[m\]erged' --send k -- "${BASH:-bash}" "$UPDATER" --source "$up"; rc=$?
    expect_rc "t16h: deciding with the older updater still defers (exit 6)" 6 "$rc" "$d/log2"
    same "t16h: ... and leaves VERSION" 0.19.0 "$(ver_of "$c")"
    fx_env python3 -I "$PTY" --cwd "$c" --log "$d/log3" --expect 'need your decision' --send r \
      --expect '\[k\]eep / \[m\]erged' --send k -- "${BASH:-bash}" "$c/$U" --source "$up"; rc=$?
    expect_rc "t16h: the new updater finishes (exit 0)" 0 "$rc" "$d/log3"
    same "t16h: VERSION is stamped" 0.20.0 "$(ver_of "$c")"
    same "t16h: the deferral is cleared" false "$(rec "$c" pending_rerun)"
  else
    skip "t16h: the deciding passes need python3 and a Unix pty"
  fi
}

# --- t16c --------------------------------------------------------------------------------
t16c_release_updater_finishes_in_one_pass() {
  local d="$WORK/t16c" rc; local up="$d/up" c="$d/c" log="$d/log" U=scripts/update.sh
  fx_upstream "$up"; fx_updater_stub "$up/$U" 0.19; fx_release "$up" 0.19.0
  # The release ships THIS updater and its library: running it from the release is running THEIRS.
  mkdir -p "$up/scripts/lib"; cp "$UPDATER" "$up/$U"; cp "$REPO_ROOT/scripts/lib/sumela-provenance.sh" "$up/scripts/lib/"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  (cd "$c" && fx_env "${BASH:-bash}" "$up/$U" --source "$up" --yes) < /dev/null > "$log" 2>&1; rc=$?
  expect_rc "t16c: the release's own updater stamps in one pass (exit 0)" 0 "$rc" "$log"
  same "t16c: VERSION is stamped" 0.20.0 "$(ver_of "$c")"
  same_text "t16c: the new updater is installed" "$c/$U" "$up/$U"
  log_lacks "t16c: no re-run is asked for" "$log" "RE-RUN NOW"
  log_lacks "t16c: no claim that an older updater ran" "$log" "This run used"
}

# --- t16d --------------------------------------------------------------------------------
t16d_updater_floor_never_installs_an_old_updater() {
  local d="$WORK/t16d" rc; local up="$d/up" c="$d/c" log="$d/log" U=scripts/update.sh
  fx_upstream "$up"; fx_updater_stub "$up/$U" 0.19; fx_release "$up" 0.19.0
  fx_updater_stub "$up/$U" "0.20 without the v0.20.0 marker"; fx_set_line "$up/$A" 25 "alpha upstream twenty-five"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  cp "$c/$U" "$d/updater.before"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t16d: exit 0 (the floor is settled, not a question)" 0 "$rc" "$log"
  same_bytes "t16d: the release's pre-0.20 updater is not installed" "$d/updater.before" "$c/$U"
  in_list "t16d: kept as updater-floor" "$(rec "$c" kept)" "$U${TAB}updater-floor"
  not_in_list "t16d: never vouched for" "$(rec_files "$c")" "$U"
  log_has "t16d: the run says why" "$log" "an updater that old is never installed"
}

# --- t16e --------------------------------------------------------------------------------
t16e_older_source_is_refused() {
  local d="$WORK/t16e" rc; local up="$d/up" c="$d/c" old="$d/stale" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.20.0
  fx_record_v2 "$c" 0.20.0 "$(git -C "$up" rev-parse v0.20.0)" "$A"
  cp "$c/.sumela/.last-update.json" "$d/record.before"
  git clone -q "$up" "$old" && git -C "$old" checkout -q v0.19.0      # a framework checkout nobody pulled
  fx_update "$c" "$old" "$log" --yes; rc=$?
  expect_rc "t16e: an older source is refused (exit 1)" 1 "$rc" "$log"
  log_has "t16e: the run says why" "$log" "refusing to downgrade"
  same "t16e: VERSION is unchanged" 0.20.0 "$(ver_of "$c")"
  has_line "t16e: the file keeps v0.20.0's line" "$c/$A" "alpha upstream twenty-five"
  same_bytes "t16e: the record is unchanged" "$d/record.before" "$c/.sumela/.last-update.json"
  same "t16e: nothing else changed" "" "$(git -C "$c" status --porcelain)"
}

# --- t16f --------------------------------------------------------------------------------
t16f_force_rerun_of_an_uncommitted_upgrade() {
  local d="$WORK/t16f" rc; local up="$d/up" c="$d/c" log="$d/log" log2="$d/log2"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_set_line "$up/$B" 25 "beta upstream twenty-five"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$B" 3 "beta local three"; fx_set_line "$c/$G" 3 "gamma local three"; fx_commit "$c" forks
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t16f: the upgrade completes (not committed)" 0 "$rc" "$log"
  cp "$c/$B" "$d/beta.merged"; cp "$c/$G" "$d/gamma.before"
  fx_update "$c" "$up" "$log2" --yes --force; rc=$?
  expect_rc "t16f: the forced re-check exits 0" 0 "$rc" "$log2"
  log_lacks "t16f: the v2 record vouches for the working tree: no self-heal" "$log2" "older updater"
  same_bytes "t16f: the merged fork is untouched" "$d/beta.merged" "$c/$B"
  same_bytes "t16f: the kept fork is untouched" "$d/gamma.before" "$c/$G"
  in_list "t16f: the upgrade's vendored file is still vouched for" "$(rec_files "$c")" "$A"
  same "t16f: VERSION stays" 0.20.0 "$(ver_of "$c")"
}

# --- t27 ---------------------------------------------------------------------------------
t27_merged_hook_keeps_mode() {
  local d="$WORK/t27" rc; local up="$d/up" c="$d/c" log="$d/log" H=.sumela/git-hooks/pre-commit
  base_upstream "$up"
  fx_set_line "$up/$H" 27 "# hook upstream change"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$H" 4 "# hook local secret scan"; chmod 755 "$c/$H"
  # Git for Windows takes no executable bit from a file (core.fileMode=false): the index gets it
  # here, as a checkout of a hook committed on Linux or macOS has it.
  git -C "$c" update-index --chmod=+x -- "$H"; fx_commit "$c" "fork the hook"
  same "t27: (setup) the hook is tracked as 100755" 100755 "$(git -C "$c" ls-files -s -- "$H" | cut -d' ' -f1)"
  # A file already identical to the release's, which lost its executable bit in the checkout.
  is_windows || chmod 644 "$c/scripts/tool.sh"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t27: exit 0" 0 "$rc" "$log"
  in_list "t27: the hook is merged" "$(rec "$c" merged)" "$H"
  has_line "t27: its local line survives" "$c/$H" "# hook local secret scan"
  if [ -x "$c/$H" ]; then ok "t27: the merged hook is executable"; else bad "t27: the merged hook is executable"; fi
  same "t27: git diff --summary shows no mode change" "" "$(git -C "$c" diff --summary -- "$H" | LC_ALL=C grep 'mode' || true)"
  if is_windows; then
    skip "t27: an unchanged file regains its executable bit (git does not track the bit on Windows)"
  else
    if [ -x "$c/scripts/tool.sh" ]; then ok "t27: an unchanged file regains the release's executable bit"
    else bad "t27: an unchanged file regains the release's executable bit"; fi
    same "t27: ... so git sees no change to it" "" "$(git -C "$c" status --porcelain -- scripts/tool.sh)"
    in_list "t27: ... and it is vouched for" "$(rec_files "$c")" scripts/tool.sh
  fi
}

# --- t28 ---------------------------------------------------------------------------------
t28_dirty_source_refused() {
  local d="$WORK/t28" rc; local up="$d/up" c="$d/c" log="$d/log" log2="$d/log2" X=.sumela/skills/alpha/__cache__.bin
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  echo "untracked bytecode" > "$up/$X"
  fx_consumer "$c" "$up" v0.19.0
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t28: a dirty source is refused (exit 1)" 1 "$rc" "$log"
  log_has "t28: the run says why" "$log" "uncommitted or untracked changes under the CORE paths"
  log_has "t28: and names the file" "$log" "$X"
  same "t28: nothing is written" "0.19.0 " "$(ver_of "$c") $(git -C "$c" status --porcelain --ignored)"
  fx_update "$c" "$up" "$log2" --yes --allow-dirty-source; rc=$?
  expect_rc "t28: --allow-dirty-source proceeds" 0 "$rc" "$log2"
  absent "t28: the untracked file is never installed" "$c/$X"
  same_text "t28: the tag's files are" "$c/$A" "$up/$A"
  not_in_list "t28: nor recorded" "$(rec_files "$c")" "$X"
}

# --- t29 ---------------------------------------------------------------------------------
t29_merge_pin_violation_becomes_conflict() {
  local d="$WORK/t29" rc; local up="$d/up" c="$d/c" log="$d/log" m
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"
  mkdir -p "$up/scripts/lib/sumela-merge-pins"
  printf '# path: %s\n# since: 0.20.0\nrequire\talpha line 5\nforbid\tskip the review\n' "$A" > "$up/scripts/lib/sumela-merge-pins/alpha.pins"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_del_line "$c/$A" 5; fx_commit "$c" "a fork that drops a pinned line"
  cp "$c/$A" "$d/alpha.before"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t29: the merge breaks a pin, so it waits (exit 3)" 3 "$rc" "$log"
  log_has "t29: the row names the pin" "$log" "conflict     $A  (pin: missing alpha line 5)"
  same_bytes "t29: LOCAL is unchanged" "$d/alpha.before" "$c/$A"
  m="$(upg "$c" "$A.merge")"
  lacks_line "t29: .merge holds the clean merge, which lacks the pinned line" "$m" "alpha line 5"
  has_line "t29: ... and upstream's change" "$m" "alpha upstream twenty-five"
  has_line "t29: .pin says why" "$(upg "$c" "$A.pin")" "pin: missing alpha line 5"
}

# --- t30 ---------------------------------------------------------------------------------
t30_removed_fork_with_successor_is_carry() {
  local d="$WORK/t30" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  rm -rf "$up/.sumela/skills/beta" "$up/.sumela/skills/gamma"; mkdir -p "$up/scripts/lib"
  printf '0.20.0\t%s\t%s\n0.20.0\t%s\t%s\n' "$G" "$A" "$B" "$A" > "$up/scripts/lib/sumela-removed-files.list"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$G" 3 "gamma local three"; fx_commit "$c" "fork gamma"
  cp "$c/$G" "$d/gamma.before"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t30: the carry row waits for a decision (exit 3)" 3 "$rc" "$log"
  log_has "t30: the forked retired file is a carry row naming its successor" "$log" "carry        $G  ($A)"
  same_bytes "t30: the fork is kept until you decide" "$d/gamma.before" "$c/$G"
  has_line "t30: .carry holds its local hunk" "$(upg "$c" "$G.carry")" "+gamma local three"
  absent "t30: the unmodified retired file is removed (nothing to carry)" "$c/$B"
}

# --- t31 ---------------------------------------------------------------------------------
t31_schema_three_way_keeps_local_edit() {
  local d="$WORK/t31" rc; local up="$d/up" c="$d/c" log="$d/log"
  local S=docs/second-brain/wiki/_SCHEMA.md T=docs/second-brain/template/wiki/_SCHEMA.md
  base_upstream "$up"
  fx_set_line "$up/$T" 25 "schema upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  mkdir -p "$c/docs/second-brain/wiki"; cp "$c/$T" "$c/$S"; fx_set_line "$c/$S" 3 "schema local three"
  fx_commit "$c" "the live schema, with a project note"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t31: exit 0" 0 "$rc" "$log"
  has_line "t31: the live schema keeps the local edit" "$c/$S" "schema local three"
  has_line "t31: and takes the template's change" "$c/$S" "schema upstream twenty-five"
  in_list "t31: recorded as merged" "$(rec "$c" merged)" "$S"
  in_list "t31: the template itself is applied" "$(rec_files "$c")" "$T"
}

# --- t32 ---------------------------------------------------------------------------------
t32_rc_tag_never_discovered() {
  local d="$WORK/t32" rc; local up="$d/up" c="$d/c" log="$d/log" shim="$d/bin" real
  if is_windows; then skip "t32: a file:// URL to an MSYS path (the tag filter is platform-independent)"; return 0; fi
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_set_line "$up/$A" 26 "alpha candidate twenty-six"; fx_release "$up" 0.21.0 --no-tag
  git -C "$up" tag v0.21.0-rc.1
  fx_consumer "$c" "$up" v0.19.0
  # The updater allows https, ssh and git transports only; this fixture serves file://.
  real="$(command -v git)"; mkdir -p "$shim"
  printf '#!/bin/sh\nunset GIT_ALLOW_PROTOCOL\nexec "%s" "$@"\n' "$real" > "$shim/git"; chmod 755 "$shim/git"
  (cd "$c" && PATH="$shim:$PATH" fx_env "${BASH:-bash}" "$UPDATER" --repo "file://$up" --yes) < /dev/null > "$log" 2>&1; rc=$?
  expect_rc "t32: exit 0" 0 "$rc" "$log"
  log_has "t32: the clone is the newest release, v0.20.0" "$log" "Cloning file://$up at v0.20.0"
  same "t32: VERSION is the release's, not the candidate's" 0.20.0 "$(ver_of "$c")"
  lacks_line "t32: no candidate content" "$c/$A" "alpha candidate twenty-six"
  has_line "t32: the release's content, applied over a base fetched into the shallow clone" "$c/$A" "alpha upstream twenty-five"
}

# --- t02b --------------------------------------------------------------------------------
t02b_deleted_file_is_readd_and_yes_never_readds() {
  local d="$WORK/t02b" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$B" 25 "beta upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  git -C "$c" rm -q "$B"; fx_commit "$c" "we do not use beta"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t02b: exit 0 (a declined re-add is settled)" 0 "$rc" "$log"
  log_has "t02b: the deleted file is a readd row, not an add" "$log" "readd        $B"
  absent "t02b: --yes never re-adds it" "$c/$B"
  in_list "t02b: recorded as kept: declined" "$(rec "$c" kept)" "$B${TAB}declined"
  same "t02b: VERSION is stamped" 0.20.0 "$(ver_of "$c")"
  # Without a terminal and without --yes nobody consents either.
  local c2="$d/c2" c3="$d/c3"
  fx_consumer "$c2" "$up" v0.19.0; git -C "$c2" rm -q "$B"; fx_commit "$c2" "we do not use beta"
  fx_update "$c2" "$up" "$d/log2"; rc=$?
  rc_in "t02b: no terminal: exit 0 (from R1-05 on, 2)" "$rc" "$d/log2" 0 2
  absent "t02b: no terminal: the deleted file stays deleted" "$c2/$B"
  if pty_available; then
    fx_consumer "$c3" "$up" v0.19.0; git -C "$c3" rm -q "$B"; fx_commit "$c3" "we do not use beta"
    fx_env python3 -I "$PTY" --cwd "$c3" --log "$d/log3" --expect 'Re-add it\? \[y/N\]: ' --send y \
      -- "${BASH:-bash}" "$UPDATER" --source "$up"; rc=$?
    expect_rc "t02b: your yes in a terminal re-adds it (exit 0)" 0 "$rc" "$d/log3"
    same_text "t02b: ... with upstream's copy" "$c3/$B" "$up/$B"
    in_list "t02b: ... vouched for" "$(rec_files "$c3")" "$B"
  else
    skip "t02b: the interactive yes needs python3 and a Unix pty"
  fi
}

# --- t04b --------------------------------------------------------------------------------
t04b_rerun_after_partial_keeps_merging() {
  local d="$WORK/t04b" rc; local up="$d/up" c="$d/c"
  base_upstream "$up"
  fx_set_line "$up/$A" 10 "alpha upstream ten"; fx_set_line "$up/$B" 25 "beta upstream twenty-five"
  fx_set_line "$up/$G" 25 "gamma upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 10 "alpha local ten"; fx_set_line "$c/$B" 3 "beta local three"; fx_commit "$c" forks
  cp "$c/$A" "$d/alpha.before"
  fx_update "$c" "$up" "$d/log1" --yes; rc=$?
  expect_rc "t04b: pass 1 is partial (exit 3)" 3 "$rc" "$d/log1"
  fx_update "$c" "$up" "$d/log2" --yes; rc=$?
  expect_rc "t04b: pass 2 is still partial (the conflict waits)" 3 "$rc" "$d/log2"
  log_lacks "t04b: the partial record never disables merging" "$d/log2" "merging disabled"
  log_has "t04b: the fork that merged still merges" "$d/log2" "merge        $B"
  log_has "t04b: the conflict still waits" "$d/log2" "conflict     $A"
  if pty_available; then
    fx_env python3 -I "$PTY" --cwd "$c" --log "$d/log3" --expect 'need your decision' --send r \
      --expect '\[k\]eep / \[m\]erged' --send k -- "${BASH:-bash}" "$UPDATER" --source "$up"; rc=$?
    expect_rc "t04b: keeping the conflict completes the upgrade (exit 0)" 0 "$rc" "$d/log3"
    same "t04b: VERSION is stamped" 0.20.0 "$(ver_of "$c")"
    in_list "t04b: the decision is recorded" "$(rec "$c" kept)" "$A${TAB}conflict:local"
    in_list "t04b: the merge is recorded" "$(rec "$c" merged)" "$B"
    in_list "t04b: the first pass's applied file is still vouched for" "$(rec_files "$c")" "$G"
    same_bytes "t04b: the kept fork is unchanged" "$d/alpha.before" "$c/$A"
  else
    skip "t04b: the deciding pass needs python3 and a Unix pty"
  fi
}

# --- t04c --------------------------------------------------------------------------------
t04c_no_terminal_never_overwrites() {
  local d="$WORK/t04c" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 10 "alpha upstream ten"; fx_set_line "$up/$H" 11 "# hook upstream ten"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 10 "alpha local ten"; fx_set_line "$c/$H" 11 "# hook local secret scan"; fx_commit "$c" forks
  cp -p "$c/$A" "$d/alpha.before"; cp -p "$c/$H" "$d/hook.before"
  fx_update "$c" "$up" "$log"; rc=$?                                 # no --yes, stdin is /dev/null
  rc_in "t04c: nothing is decided (exit 3; from R1-05 on, 2)" "$rc" "$log" 2 3
  same_bytes "t04c: the forked file is unchanged" "$d/alpha.before" "$c/$A"
  same_bytes "t04c: the forked pre-commit is unchanged" "$d/hook.before" "$c/$H"
  if [ -x "$c/$H" ]; then ok "t04c: the pre-commit is still executable"; else bad "t04c: the pre-commit is still executable"; fi
  same "t04c: VERSION is unchanged" 0.19.0 "$(ver_of "$c")"
}

# --- t04d --------------------------------------------------------------------------------
t04d_edited_merge_survives_a_rerun() {
  local d="$WORK/t04d" rc m; local up="$d/up" c="$d/c"
  conflict_fixture "$d"; up="$d/up"; c="$d/c"
  fx_update "$c" "$up" "$d/log1" --yes; rc=$?
  expect_rc "t04d: pass 1 is partial" 3 "$rc" "$d/log1"
  m="$(upg "$c" "$A.merge")"
  cp "$up/$A" "$m"; fx_set_line "$m" 10 "alpha both ten"                      # the developer resolves it
  fx_update "$c" "$up" "$d/log2" --yes; rc=$?
  expect_rc "t04d: pass 2 is partial" 3 "$rc" "$d/log2"
  has_line "t04d: the fresh .merge has its markers again" "$m" "<<<<<<< local"
  has_line "t04d: the edited one is kept as .merge.prev" "$m.prev" "alpha both ten"
  log_has "t04d: the run says so" "$d/log2" "is now $A.merge.prev"
}

# --- t04f --------------------------------------------------------------------------------
t04f_stale_merge_never_offered() {
  local d="$WORK/t04f" rc m; local up="$d/up" c="$d/c"
  conflict_fixture "$d"
  fx_update "$c" "$up" "$d/log1" --yes; rc=$?
  expect_rc "t04f: pass 1 is partial" 3 "$rc" "$d/log1"
  m="$(upg "$c" "$A.merge")"
  # The record now names the release commit as base: the same row becomes review, not conflict.
  base_to_release() {
    sed "s/\"upstream_commit\": \"[0-9a-f]*\"/\"upstream_commit\": \"$(git -C "$up" rev-parse v0.20.0)\"/" \
      "$c/.sumela/.last-update.json" > "$d/rec" && cp "$d/rec" "$c/.sumela/.last-update.json"
  }
  base_to_release
  fx_update "$c" "$up" "$d/log2" --yes; rc=$?
  expect_rc "t04f: pass 2 is partial" 3 "$rc" "$d/log2"
  log_has "t04f: the row is review now" "$d/log2" "review       $A"
  absent "t04f: an untouched earlier .merge is no longer offered" "$m"
  absent "t04f: ... and, still holding its markers, it is not kept" "$m.prev"
  # A .merge you resolved is kept, never offered as [m]erged for a row that is not a conflict.
  fx_update "$c" "$up" "$d/log3" --yes --force; rc=$?        # back to a conflict, which writes a .merge again
  cp "$up/$A" "$m"; fx_set_line "$m" 10 "alpha resolved by hand ten"
  base_to_release
  fx_update "$c" "$up" "$d/log4" --yes; rc=$?
  absent "t04f: an edited earlier .merge is no longer offered" "$m"
  has_line "t04f: ... it is kept as .merge.prev" "$m.prev" "alpha resolved by hand ten"
}

# --- t04g --------------------------------------------------------------------------------
t04g_resolved_merge_survives_later_runs() {
  local d="$WORK/t04g" rc m; local up="$d/up" c="$d/c"
  conflict_fixture "$d"
  m="$(upg "$c" "$A.merge")"
  fx_update "$c" "$up" "$d/log1" --yes
  cp "$up/$A" "$m"; fx_set_line "$m" 10 "alpha resolved by hand ten"            # you resolve the .merge
  fx_update "$c" "$up" "$d/log2" --yes
  has_line "t04g: run 2 keeps your resolution as .merge.prev" "$m.prev" "alpha resolved by hand ten"
  fx_set_line "$c/$A" 28 "alpha unrelated local edit twenty-eight"             # the fork changes, so does the merge
  fx_update "$c" "$up" "$d/log3" --yes; rc=$?
  expect_rc "t04g: run 3 is partial" 3 "$rc" "$d/log3"
  has_line "t04g: run 3 never moves the untouched .merge over your resolution" "$m.prev" "alpha resolved by hand ten"
  absent "t04g: ... and keeps no copy of that untouched .merge" "$m.prev.2"
  has_line "t04g: run 3's .merge is fresh" "$m" "alpha unrelated local edit twenty-eight"
  cp "$c/$A" "$m"; fx_set_line "$m" 10 "alpha resolved again ten"               # a second resolution
  fx_set_line "$c/$A" 29 "alpha another local edit twenty-nine"
  fx_update "$c" "$up" "$d/log4" --yes
  has_line "t04g: run 4 keeps the first resolution" "$m.prev" "alpha resolved by hand ten"
  has_line "t04g: ... and the second under the next free name" "$m.prev.2" "alpha resolved again ten"
}

# --- t04e --------------------------------------------------------------------------------
t04e_unanswered_gitignore_prompt_adds_nothing() {
  local d="$WORK/t04e" rc; local up="$d/up" c="$d/c"
  fx_upstream "$up"; mkdir -p "$up/scripts/lib"
  # The framework pins its scripts to LF (its .gitattributes): the library the updater sources is
  # read as LF even from a CRLF checkout, as the CI's autocrlf run reads it.
  printf '*.sh text eol=lf\n' > "$up/.gitattributes"
  printf '.sumela/.upgrade/\n.sumela/local.md\n' > "$up/scripts/lib/sumela-gitignore.list"
  cat > "$up/scripts/lib/sumela-gitignore.sh" <<'EOF'
_GI_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
sumela_gitignore_lines() { tr -d '\r' < "$_GI_DIR/sumela-gitignore.list" | grep -vE '^[[:space:]]*(#|$)'; }
EOF
  fx_release "$up" 0.19.0
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  cp "$c/.gitignore" "$d/gitignore.before"
  fx_update "$c" "$up" "$d/log1"; rc=$?                             # no --yes, stdin is /dev/null
  same_bytes "t04e: an unanswered prompt leaves .gitignore unchanged" "$d/gitignore.before" "$c/.gitignore"
  fx_update "$c" "$up" "$d/log2" --yes --force; rc=$?
  has_line "t04e: --yes adds the missing pattern" "$c/.gitignore" ".sumela/local.md"
}

# --- t07c --------------------------------------------------------------------------------
t07c_one_differing_vouched_file_is_a_fork() {
  local d="$WORK/t07c" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_set_line "$up/$G" 25 "gamma upstream twenty-five"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_commit "$c" "fork alpha"
  fx_record_v2 "$c" 0.19.0 "$(git -C "$up" rev-parse v0.19.0)" "$A" "$B" "$G" "$P"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t07c: exit 0" 0 "$rc" "$log"
  log_lacks "t07c: one forked file in four never disables merging" "$log" "merging disabled"
  in_list "t07c: the fork is merged" "$(rec "$c" merged)" "$A"
  in_list "t07c: the unforked file is applied" "$(rec_files "$c")" "$G"
}

# --- t08b --------------------------------------------------------------------------------
t08b_self_heal_after_a_pass_from_a_non_tag_commit() {
  local d="$WORK/t08b" rc rcc; local up="$d/up" c="$d/c" c2="$d/c2"
  base_upstream "$up"
  fx_set_line "$up/$A" 20 "alpha rc twenty"; fx_release "$up" 0.20.0 --no-tag; rcc="$(git -C "$up" rev-parse HEAD)"
  fx_set_line "$up/$A" 25 "alpha final twenty-five"; fx_commit "$up" "a fix after the candidate"; git -C "$up" tag v0.20.0
  # (a) The older updater cloned the default branch (the candidate), not the tag; its record lists the file.
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_commit "$c" fork
  fx_old_updater_pass "$c" "$up" "$rcc" "$A"
  cp "$c/$A" "$d/alpha.candidate"
  fx_update "$c" "$up" "$d/log" --yes; rc=$?
  expect_rc "t08b: exit 0" 0 "$rc" "$d/log"
  has_line "t08b: HEAD's fork is the local side (the candidate's bytes are an upstream version)" "$c/$A" "alpha local three"
  has_line "t08b: ... merged with the tag" "$c/$A" "alpha final twenty-five"
  in_list "t08b: recorded as merged" "$(rec "$c" merged)" "$A"
  same_bytes "t08b: the replaced copy (the candidate's) is kept as .working" "$d/alpha.candidate" "$(upg "$c" "$A.working")"
  # (b) Your uncommitted change to a file that older updater's record does not list is yours.
  fx_consumer "$c2" "$up" v0.19.0
  fx_set_line "$c2/$B" 3 "beta local three"; fx_commit "$c2" fork
  fx_old_updater_pass "$c2" "$up" v0.20.0 "$A"
  fx_set_line "$c2/$B" 7 "beta edited after that pass"; cp "$c2/$B" "$d/beta.working"
  fx_update "$c2" "$up" "$d/log2" --yes; rc=$?
  expect_rc "t08b: your change needs no decision (exit 0)" 0 "$rc" "$d/log2"
  same_bytes "t08b: the working copy, with your change and HEAD's fork, is untouched" "$d/beta.working" "$c2/$B"
  in_list "t08b: kept as a fork" "$(rec "$c2" kept)" "$B${TAB}fork"
}

# --- t08g --------------------------------------------------------------------------------
t08g_self_heal_afterpass_waits_across_runs() {
  local d="$WORK/t08g" rc; local up="$d/up" c="$d/c"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_commit "$c" fork
  fx_old_updater_pass "$c" "$up" v0.20.0 "$A"                                  # wrote upstream's alpha
  fx_set_line "$c/$A" 15 "alpha hand edit after that pass"; cp "$c/$A" "$d/alpha.working"
  fx_update "$c" "$up" "$d/log1" --yes; rc=$?
  expect_rc "t08g: a change on top of an older updater's write waits (exit 3)" 3 "$rc" "$d/log1"
  log_has "t08g: it is a review row" "$d/log1" "review       $A  (changed after an older updater wrote it"
  same_bytes "t08g: the working copy with your edit stays" "$d/alpha.working" "$c/$A"
  has_line "t08g: HEAD's copy (the fork) is offered as .head" "$(upg "$c" "$A.head")" "alpha local three"
  same "t08g: VERSION is HEAD's again" 0.19.0 "$(ver_of "$c")"
  fx_update "$c" "$up" "$d/log2" --yes; rc=$?                                   # no longer a self-heal
  expect_rc "t08g: the next run still waits (exit 3)" 3 "$rc" "$d/log2"
  log_has "t08g: ... on the same row" "$d/log2" "review       $A"
  same_bytes "t08g: ... and never touches the working copy" "$d/alpha.working" "$c/$A"
  same "t08g: ... nor stamps" 0.19.0 "$(ver_of "$c")"
  if pty_available; then
    fx_env python3 -I "$PTY" --cwd "$c" --log "$d/log3" --expect 'need your decision' --send r \
      --expect '\[k\]eep / \[m\]erged' --send d --expect '\[k\]eep / \[m\]erged' --send k \
      -- "${BASH:-bash}" "$UPDATER" --source "$up"; rc=$?
    expect_rc "t08g: your [k]eep settles it (exit 0)" 0 "$rc" "$d/log3"
    log_has "t08g: [d]iff shows HEAD's fork against yours" "$d/log3" "--- head/$A"
    log_has "t08g: ... with the fork's line" "$d/log3" "-alpha local three"
    absent "t08g: the decided row's .head is gone" "$(upg "$c" "$A.head")"
    same "t08g: VERSION is stamped" 0.20.0 "$(ver_of "$c")"
  else
    skip "t08g: the deciding run needs python3 and a Unix pty"
  fi
}

# --- t08l --------------------------------------------------------------------------------
t08l_waiting_row_survives_a_cleaned_upgrade_dir() {
  local d="$WORK/t08l" rc; local up="$d/up" c="$d/c"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_commit "$c" fork
  fx_old_updater_pass "$c" "$up" v0.20.0 "$A"
  fx_set_line "$c/$A" 15 "alpha hand edit after that pass"
  fx_update "$c" "$up" "$d/log1" --yes; rc=$?
  expect_rc "t08l: pass 1 waits (exit 3)" 3 "$rc" "$d/log1"
  in_list "t08l: the record lists the row as pending" "$(rec "$c" kept)" "$A${TAB}pending"
  fx_set_line "$c/$A" 3 "alpha local three"; cp "$c/$A" "$d/alpha.resolved"     # combined by hand
  rm -rf "$c/.sumela/.upgrade"                                                 # as git clean -fdX would
  fx_update "$c" "$up" "$d/log2" --yes; rc=$?
  expect_rc "t08l: the next run still waits (exit 3)" 3 "$rc" "$d/log2"
  log_has "t08l: ... on the same row" "$d/log2" "review       $A"
  same_bytes "t08l: ... never touching the working copy" "$d/alpha.resolved" "$c/$A"
  has_line "t08l: HEAD's copy is offered again as .head" "$(upg "$c" "$A.head")" "alpha local three"
  same "t08l: VERSION waits" 0.19.0 "$(ver_of "$c")"
  if pty_available; then
    fx_env python3 -I "$PTY" --cwd "$c" --log "$d/log3" --expect 'need your decision' --send r \
      --expect '\[k\]eep / \[m\]erged' --send k -- "${BASH:-bash}" "$UPDATER" --source "$up"; rc=$?
    expect_rc "t08l: your [k]eep settles it (exit 0)" 0 "$rc" "$d/log3"
    not_in_list "t08l: the record no longer lists it as pending" "$(rec "$c" kept)" "$A${TAB}pending"
    same_bytes "t08l: your combination is what is kept" "$d/alpha.resolved" "$c/$A"
  else
    skip "t08l: the deciding run needs python3 and a Unix pty"
  fi
}

# --- t08m --------------------------------------------------------------------------------
t08m_older_upstream_version_is_your_revert() {
  local d="$WORK/t08m" rc; local up="$d/up" c="$d/c"
  fx_upstream "$up"; fx_set_line "$up/$A" 5 "alpha v0.17 five"; fx_release "$up" 0.17.0
  git -C "$up" show "HEAD:$A" > "$d/alpha.v017"
  fx_set_line "$up/$A" 5 "alpha line 5"; fx_release "$up" 0.19.0
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_set_line "$up/$G" 25 "gamma upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_commit "$c" fork
  fx_old_updater_pass "$c" "$up" v0.20.0 "$G"                                  # it did not touch alpha
  cp "$d/alpha.v017" "$c/$A"                                                    # you revert alpha to v0.17's copy
  fx_update "$c" "$up" "$d/log" --yes; rc=$?
  expect_rc "t08m: exit 0" 0 "$rc" "$d/log"
  has_line "t08m: a version older than the base is your revert, kept" "$c/$A" "alpha v0.17 five"
  has_line "t08m: ... and merged with upstream's change" "$c/$A" "alpha upstream twenty-five"
  in_list "t08m: recorded as merged" "$(rec "$c" merged)" "$A"
}

# --- t08k --------------------------------------------------------------------------------
t08k_untracked_upstream_copy_is_never_removed() {
  local d="$WORK/t08k" rc; local up="$d/up" c="$d/c"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_set_line "$up/$B" 25 "beta upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  # beta was never committed: it sits in the working tree, untracked and not ignored.
  git -C "$c" rm -q --cached -- "$B"; git -C "$c" commit -q --amend -m "install, without beta"
  fx_set_line "$c/$A" 3 "alpha local three"; git -C "$c" commit -q -am fork     # tracked files only: beta stays untracked
  same "t08k: (setup) beta was never committed" "" "$(git -C "$c" log --format=%H -- "$B")"
  fx_old_updater_pass "$c" "$up" v0.20.0 "$A"                                  # its record does not list beta
  fx_update "$c" "$up" "$d/log" --yes; rc=$?
  expect_rc "t08k: exit 0" 0 "$rc" "$d/log"
  exists "t08k: an untracked copy nobody can attribute is never removed" "$c/$B"
  log_lacks "t08k: ... nor treated as a deletion" "$d/log" "readd        $B"
}

# --- t08j --------------------------------------------------------------------------------
t08j_self_heal_restores_before_the_questions() {
  local d="$WORK/t08j" rc; local up="$d/up" c="$d/c"
  pty_available || { skip "t08j: needs python3 and a Unix pty"; return 0; }
  conflict_fixture "$d"
  fx_old_updater_pass "$c" "$up" v0.20.0 "$A"                                 # overwrote the conflicting fork
  fx_env python3 -I "$PTY" --cwd "$c" --log "$d/log" --expect 'need your decision' --send r \
    --expect '\[k\]eep / \[m\]erged' --send d --expect '\[k\]eep / \[m\]erged' --send s \
    -- "${BASH:-bash}" "$UPDATER" --source "$up"; rc=$?
  expect_rc "t08j: skipped (exit 3)" 3 "$rc" "$d/log"
  log_has "t08j: [d]iff shows HEAD's fork as yours, already restored" "$d/log" "-alpha local ten"
  same_text "t08j: the working copy is HEAD's fork" "$d/alpha.before" "$c/$A"
}

# --- t08h --------------------------------------------------------------------------------
t08h_self_heal_keeps_your_uncommitted_change() {
  local d="$WORK/t08h" rc; local up="$d/up" c="$d/c"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_set_line "$up/$B" 25 "beta upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_commit "$c" fork
  fx_old_updater_pass "$c" "$up" v0.20.0 "$A"
  fx_set_line "$c/$B" 15 "beta uncommitted edit"                                # the record does not list beta
  fx_update "$c" "$up" "$d/log1" --yes; rc=$?
  expect_rc "t08h: exit 0" 0 "$rc" "$d/log1"
  has_line "t08h: your uncommitted edit stays" "$c/$B" "beta uncommitted edit"
  has_line "t08h: ... merged with upstream's change" "$c/$B" "beta upstream twenty-five"
  in_list "t08h: recorded as merged" "$(rec "$c" merged)" "$B"
  fx_update "$c" "$up" "$d/log2" --yes --force; rc=$?
  expect_rc "t08h: a re-check exits 0" 0 "$rc" "$d/log2"
  has_line "t08h: ... and keeps it" "$c/$B" "beta uncommitted edit"
}

# --- t08i --------------------------------------------------------------------------------
t08i_gitignored_live_file_is_never_deleted() {
  local d="$WORK/t08i" rc; local up="$d/up" c="$d/c"
  local S=docs/second-brain/wiki/_SCHEMA.md T=docs/second-brain/template/wiki/_SCHEMA.md
  base_upstream "$up"
  fx_set_line "$up/$T" 25 "schema upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  echo "docs/second-brain/wiki/" >> "$c/.gitignore"; fx_commit "$c" "the wiki is not tracked here"
  mkdir -p "$c/docs/second-brain/wiki"; cp "$c/$T" "$c/$S"
  # A v0.19 pass refreshed the template and, with consent, the live schema from it.
  fx_old_updater_pass "$c" "$up" v0.20.0 "$T"; cp "$c/$T" "$c/$S"; fx_record_v1 "$c" 0.20.0 "$T" "$S"
  fx_update "$c" "$up" "$d/log" --yes; rc=$?
  expect_rc "t08i: exit 0" 0 "$rc" "$d/log"
  exists "t08i: the gitignored live schema is never deleted" "$c/$S"
  has_line "t08i: ... and keeps its content" "$c/$S" "schema upstream twenty-five"
  log_lacks "t08i: its absence from HEAD decides nothing" "$d/log" "removed $S"
}

# --- t08c --------------------------------------------------------------------------------
t08c_self_heal_with_export_ignore() {
  local d="$WORK/t08c" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_set_line "$up/$G" 25 "gamma upstream twenty-five"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  printf '/.sumela export-ignore\n/scripts export-ignore\n/docs export-ignore\n' > "$c/.gitattributes"
  fx_set_line "$c/$A" 3 "alpha local three"; fx_set_line "$c/$B" 3 "beta local three"; fx_commit "$c" "forks, release-tarball attributes"
  git -C "$c" show "HEAD:$B" > "$d/beta.head"
  fx_old_updater_pass "$c" "$up" v0.20.0 "$A" "$B" "$G"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t08c: exit 0" 0 "$rc" "$log"
  has_line "t08c: the fork is back despite export-ignore" "$c/$A" "alpha local three"
  has_line "t08c: ... and merged" "$c/$A" "alpha upstream twenty-five"
  same_text "t08c: the other fork is HEAD's copy again" "$c/$B" "$d/beta.head"
  not_in_list "t08c: a fork is never vouched for" "$(rec_files "$c")" "$A"
  same "t08c: VERSION is stamped" 0.20.0 "$(ver_of "$c")"
}

# --- t08d --------------------------------------------------------------------------------
t08d_incomplete_upstream_tree_fails_closed() {
  local d="$WORK/t08d" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  printf '.sumela/skills/beta export-ignore\n' > "$up/.gitattributes"; fx_set_line "$up/$A" 25 "alpha upstream twenty-five"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t08d: a release tree git archive cannot reproduce is refused (exit 1)" 1 "$rc" "$log"
  log_has "t08d: the run names the missing file" "$log" "git archive left $B out of"
  same "t08d: VERSION is unchanged" 0.19.0 "$(ver_of "$c")"
  same "t08d: nothing was written" "" "$(git -C "$c" status --porcelain)"
}

# --- t08e --------------------------------------------------------------------------------
t08e_self_heal_respects_committed_deletion() {
  local d="$WORK/t08e" rc rcc; local up="$d/up" c="$d/c" c2="$d/c2" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$G" 20 "gamma rc twenty"; fx_release "$up" 0.20.0 --no-tag; rcc="$(git -C "$up" rev-parse HEAD)"
  fx_set_line "$up/$G" 25 "gamma final twenty-five"; fx_commit "$up" "a fix after the candidate"; git -C "$up" tag v0.20.0
  fx_consumer "$c" "$up" v0.19.0
  git -C "$c" rm -q "$G"; fx_commit "$c" "we do not use gamma"
  mkdir -p "$c/.sumela/skills/gamma"; fx_old_updater_pass "$c" "$up" v0.20.0 "$G"   # it re-added it
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t08e: exit 0" 0 "$rc" "$log"
  log_has "t08e: the re-added file is a readd row" "$log" "readd        $G"
  absent "t08e: --yes removes the older updater's re-add again" "$c/$G"
  in_list "t08e: recorded as kept: declined" "$(rec "$c" kept)" "$G${TAB}declined"
  not_in_list "t08e: never vouched for" "$(rec_files "$c")" "$G"
  # The same when that updater re-added a non-tag commit's copy.
  fx_consumer "$c2" "$up" v0.19.0
  git -C "$c2" rm -q "$G"; fx_commit "$c2" "we do not use gamma"
  mkdir -p "$c2/.sumela/skills/gamma"; fx_old_updater_pass "$c2" "$up" "$rcc" "$G"
  fx_update "$c2" "$up" "$d/log2" --yes; rc=$?
  expect_rc "t08e: exit 0 (a candidate's copy)" 0 "$rc" "$d/log2"
  absent "t08e: ... removed again, never merged and kept" "$c2/$G"
  not_in_list "t08e: ... and never recorded as merged" "$(rec "$c2" merged)" "$G"
}

# --- t08f --------------------------------------------------------------------------------
t08f_self_heal_warns_about_staged_overwrites() {
  local d="$WORK/t08f" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_commit "$c" fork
  fx_old_updater_pass "$c" "$up" v0.20.0 "$A"; git -C "$c" add -- "$A"     # the overwrite got staged
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t08f: exit 0" 0 "$rc" "$log"
  has_line "t08f: the working tree has the fork again" "$c/$A" "alpha local three"
  log_has "t08f: the run warns about the staged copy" "$log" "changes staged before this run"
  log_has "t08f: ... naming it" "$log" "  $A"
}

# --- t09b --------------------------------------------------------------------------------
t09b_self_heal_keeps_retired_fork() {
  local d="$WORK/t09b" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.19.1      # gamma unchanged in 0.19.1
  rm -rf "$up/.sumela/skills/gamma"; mkdir -p "$up/scripts/lib"
  printf '0.20.0\t%s\t-\n' "$G" > "$up/scripts/lib/sumela-removed-files.list"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$G" 3 "gamma local three"; fx_commit "$c" "fork gamma"
  fx_old_updater_pass "$c" "$up" v0.19.1 "$G" "$A"       # overwrote the fork with 0.19.1's gamma, stamped 0.19.1
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t09b: exit 0" 0 "$rc" "$log"
  has_line "t09b: the retired fork is HEAD's copy again, not removed" "$c/$G" "gamma local three"
  in_list "t09b: kept as removed-upstream" "$(rec "$c" kept)" "$G${TAB}removed-upstream"
  not_in_list "t09b: never recorded as removed" "$(rec "$c" removed)" "$G"
}

# --- t09c --------------------------------------------------------------------------------
t09c_self_heal_keeps_your_edit_to_a_retired_file() {
  local d="$WORK/t09c" rc; local up="$d/up" c="$d/c"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; rm -rf "$up/.sumela/skills/gamma"; mkdir -p "$up/scripts/lib"
  printf '0.20.0\t%s\t-\n' "$G" > "$up/scripts/lib/sumela-removed-files.list"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_commit "$c" fork
  fx_old_updater_pass "$c" "$up" v0.20.0 "$A"                                  # it never touched gamma
  fx_set_line "$c/$G" 7 "gamma uncommitted edit"; cp "$c/$G" "$d/gamma.before"
  fx_update "$c" "$up" "$d/log1" --yes; rc=$?
  expect_rc "t09c: exit 0" 0 "$rc" "$d/log1"
  same_bytes "t09c: your edit to the retired file is kept" "$d/gamma.before" "$c/$G"
  in_list "t09c: as kept: removed-upstream" "$(rec "$c" kept)" "$G${TAB}removed-upstream"
  fx_update "$c" "$up" "$d/log2" --yes --force; rc=$?
  expect_rc "t09c: a later run exits 0" 0 "$rc" "$d/log2"
  same_bytes "t09c: ... and never removes it" "$d/gamma.before" "$c/$G"
}

# --- t09d --------------------------------------------------------------------------------
t09d_self_heal_retired_afterpass_is_a_carry_row() {
  local d="$WORK/t09d" rc; local up="$d/up" c="$d/c"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.19.1      # gamma unchanged in 0.19.1
  rm -rf "$up/.sumela/skills/gamma"; mkdir -p "$up/scripts/lib"
  # No successor: without the self-heal's wait, a changed retired file would simply be kept.
  printf '0.20.0\t%s\t-\n' "$G" > "$up/scripts/lib/sumela-removed-files.list"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$G" 3 "gamma local three"; fx_commit "$c" "fork gamma"
  fx_old_updater_pass "$c" "$up" v0.19.1 "$G" "$A"                             # wrote 0.19.1's gamma over the fork
  fx_set_line "$c/$G" 7 "gamma edited after that pass"; cp "$c/$G" "$d/gamma.working"
  fx_update "$c" "$up" "$d/log1" --yes; rc=$?
  expect_rc "t09d: the retired file waits for a decision (exit 3)" 3 "$rc" "$d/log1"
  log_has "t09d: it is a carry row" "$d/log1" "carry        $G"
  same_bytes "t09d: the working copy stays" "$d/gamma.working" "$c/$G"
  has_line "t09d: .carry holds the working copy's change" "$(upg "$c" "$G.carry")" "+gamma edited after that pass"
  has_line "t09d: HEAD's copy (the fork) is .head" "$(upg "$c" "$G.head")" "gamma local three"
  fx_update "$c" "$up" "$d/log2" --yes; rc=$?
  expect_rc "t09d: the next run still waits (exit 3)" 3 "$rc" "$d/log2"
  log_has "t09d: ... on the same carry row" "$d/log2" "carry        $G"
  same_bytes "t09d: ... and never removes the file" "$d/gamma.working" "$c/$G"
}

# --- t07d / t07e ---------------------------------------------------------------------------
t07d_unfinished_record_never_vouches() {
  local d="$WORK/t07d" rc; local up="$d/up" c="$d/c"
  base_upstream "$up"
  fx_set_line "$up/$A" 10 "alpha upstream ten"; fx_set_line "$up/$G" 25 "gamma upstream twenty-five"
  fx_set_line "$up/$P" 25 "prompt upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 10 "alpha local ten"; fx_commit "$c" fork
  fx_update "$c" "$up" "$d/log1" --yes; rc=$?
  expect_rc "t07d: pass 1 is partial (it vouches for the two files it applied)" 3 "$rc" "$d/log1"
  fx_set_line "$c/$G" 3 "gamma edited between passes"; fx_set_line "$c/$P" 3 "prompt edited between passes"
  fx_update "$c" "$up" "$d/log2" --yes; rc=$?
  log_lacks "t07d: the unfinished record vouches for nothing: merging stays on" "$d/log2" "merging disabled"
  log_has "t07d: an edited vouched file is merged as a fork" "$d/log2" "merge        $G"
}
t07e_upgraded_bytes_are_no_evidence_of_a_wrong_base() {
  local d="$WORK/t07e" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_set_line "$up/$G" 25 "gamma upstream twenty-five"
  fx_set_line "$up/$P" 25 "prompt upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  fx_set_line "$c/$A" 3 "alpha local three"; fx_commit "$c" fork
  fx_record_v2 "$c" 0.19.0 "$(git -C "$up" rev-parse v0.19.0)" "$G" "$P" "$B"
  cp "$up/$G" "$c/$G"; cp "$up/$P" "$c/$P"                                      # an interrupted run applied two of them
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t07e: exit 0" 0 "$rc" "$log"
  log_lacks "t07e: files already holding the new release prove no wrong base" "$log" "merging disabled"
  in_list "t07e: the fork is merged" "$(rec "$c" merged)" "$A"
}

# --- t16i --------------------------------------------------------------------------------
t16i_cut_during_the_record_write_leaves_no_temp_file() {
  local d="$WORK/t16i" rc real; local up="$d/up" c="$d/c" shim="$d/shim"
  if is_windows; then skip "t16i: signals to a Git Bash process"; return 0; fi
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  # A mv that, for the record's temporary file only, stops the updater mid-write.
  real="$(command -v mv)"; mkdir -p "$shim"
  printf '#!/bin/sh\nfor a; do case "$a" in *.last-update.json.sumela-tmp.*) kill -TERM "$PPID"; sleep 2; exit 1 ;; esac; done\nexec "%s" "$@"\n' "$real" > "$shim/mv"
  chmod 755 "$shim/mv"
  mkdir -p "$d/tmp"
  (cd "$c" && PATH="$shim:$PATH" TMPDIR="$d/tmp" fx_env "${BASH:-bash}" "$UPDATER" --source "$up" --yes) < /dev/null > "$d/log" 2>&1; rc=$?
  if [ "$rc" -ne 0 ]; then ok "t16i: (setup) the run was cut (exit $rc)"; else bad "t16i: (setup) the run was cut"; fi
  same "t16i: no temporary record file is left" "" "$(cd "$c/.sumela" && ls -a | LC_ALL=C grep -F '.last-update.json.sumela-tmp.' || true)"
  same "t16i: no temporary directory is left (the updater's or the record library's)" "" "$(ls -A "$d/tmp")"
}

# --- t13b / t13c / t13d (pty) --------------------------------------------------------------
t13b_interactive_enter_only_never_overwrites() {
  local d="$WORK/t13b" rc
  pty_available || { skip "t13b: needs python3 and a Unix pty"; return 0; }
  base_upstream "$d/up"
  fx_set_line "$d/up/$A" 10 "alpha upstream ten"; fx_set_line "$d/up/$H" 11 "# hook upstream ten"; fx_release "$d/up" 0.20.0
  fx_consumer "$d/c" "$d/up" v0.19.0
  fx_set_line "$d/c/$A" 10 "alpha local ten"; fx_set_line "$d/c/$H" 11 "# hook local secret scan"; fx_commit "$d/c" forks
  cp -p "$d/c/$A" "$d/alpha.before"; cp -p "$d/c/$H" "$d/hook.before"
  fx_env python3 -I "$PTY" --cwd "$d/c" --log "$d/log" --expect 'need your decision' --send '' \
    --expect '\[k\]eep / \[m\]erged' --send '' --expect 'Answer k, m, t, d or s' --eof \
    -- "${BASH:-bash}" "$UPDATER" --source "$d/up"; rc=$?
  expect_rc "t13b: Enter and end of input decide nothing (exit 3)" 3 "$rc" "$d/log"
  same_bytes "t13b: the forked pre-commit is unchanged" "$d/hook.before" "$d/c/$H"
  same_bytes "t13b: the forked file is unchanged" "$d/alpha.before" "$d/c/$A"
  same "t13b: VERSION is unchanged" 0.19.0 "$(ver_of "$d/c")"
}
t13c_interactive_theirs_needs_the_typed_path() {
  local d="$WORK/t13c" rc
  pty_available || { skip "t13c: needs python3 and a Unix pty"; return 0; }
  conflict_fixture "$d"
  fx_env python3 -I "$PTY" --cwd "$d/c" --log "$d/log" --expect 'need your decision' --send r \
    --expect '\[k\]eep / \[m\]erged' --send t --expect 'Type the path' --send ".sumela/skills/alpha" \
    --expect 'Not confirmed[^\n]*\n[^\n]*\[s\]kip: ' --send s -- "${BASH:-bash}" "$UPDATER" --source "$d/up"; rc=$?
  expect_rc "t13c: a wrong path replaces nothing (exit 3)" 3 "$rc" "$d/log"
  same_bytes "t13c: the fork is unchanged" "$d/alpha.before" "$d/c/$A"
  same "t13c: nothing is recorded as taken over" "" "$(rec "$d/c" theirs_over_fork)"
}
t13d_interactive_merged_refuses_markers() {
  local d="$WORK/t13d" rc
  pty_available || { skip "t13d: needs python3 and a Unix pty"; return 0; }
  conflict_fixture "$d"
  fx_env python3 -I "$PTY" --cwd "$d/c" --log "$d/log" --expect 'need your decision' --send r \
    --expect '\[k\]eep / \[m\]erged' --send m --expect 'still has a conflict marker[^\n]*\n[^\n]*\[s\]kip: ' --send s \
    -- "${BASH:-bash}" "$UPDATER" --source "$d/up"; rc=$?
  expect_rc "t13d: the marker-laden merge is refused (exit 3)" 3 "$rc" "$d/log"
  same_bytes "t13d: the fork is unchanged" "$d/alpha.before" "$d/c/$A"
  same "t13d: nothing is recorded as merged" "" "$(rec "$d/c" merged)"
}

# --- t13e --------------------------------------------------------------------------------
# yes_into_updater <install> <source> <log> [r]: `yes` piped into the updater (after one "r" line
# with r). The stream is finite (20000 lines), so an updater that loops on it ends at its end, having
# asked 20000 times, instead of running on: the count of asks tells the two apart, with no watchdog.
yes_into_updater() {
  ( cd "$1" || exit 99
    if [ "${4:-}" = r ]; then
      { echo r; yes | head -n 20000; } | fx_env "${BASH:-bash}" "$UPDATER" --source "$2"; exit "${PIPESTATUS[1]}"
    fi
    yes | head -n 20000 | fx_env "${BASH:-bash}" "$UPDATER" --source "$2"; exit "${PIPESTATUS[2]}" ) > "$3" 2>&1
}
t13e_piped_yes_never_loops() {
  local d="$WORK/t13e" rc
  conflict_fixture "$d"
  yes_into_updater "$d/c" "$d/up" "$d/log"; rc=$?
  rc_in "t13e: yes | update.sh ends: three non-answers decide nothing (exit 3; from R1-05 on, 2)" "$rc" "$d/log" 2 3
  same "t13e: it asks no more than three times" 2 "$(LC_ALL=C grep -c 'Answer r or s' "$d/log")"
  same_bytes "t13e: the fork is unchanged" "$d/alpha.before" "$d/c/$A"
  same "t13e: VERSION is unchanged" 0.19.0 "$(ver_of "$d/c")"
  yes_into_updater "$d/c" "$d/up" "$d/log2" r; rc=$?
  rc_in "t13e: [r]eview, then yes: the row's question ends the same way (exit 3; from R1-05 on, 2)" "$rc" "$d/log2" 2 3
  same "t13e: ... after three asks" 2 "$(LC_ALL=C grep -c 'Answer k, m, t, d or s' "$d/log2")"
  same_bytes "t13e: ... and the fork is unchanged" "$d/alpha.before" "$d/c/$A"
  same "t13e: ... and VERSION too" 0.19.0 "$(ver_of "$d/c")"
}

# --- t28b --------------------------------------------------------------------------------
t28b_untagged_source_refused_shallow_clone_resolves_release() {
  local d="$WORK/t28b" rc; local up="$d/up" c="$d/c" c2="$d/c2" c3="$d/c3" src="$d/shallow" src2="$d/shallow2"
  base_upstream "$up"
  fx_set_line "$up/$A" 25 "alpha upstream twenty-five"; fx_release "$up" 0.20.0
  fx_set_line "$up/$A" 26 "alpha development twenty-six"; fx_release "$up" 0.21.0 --no-tag   # an unreleased tip
  fx_consumer "$c" "$up" v0.19.0
  fx_update "$c" "$up" "$d/log1" --yes; rc=$?
  expect_rc "t28b: an untagged HEAD is refused (exit 1)" 1 "$rc" "$d/log1"
  log_has "t28b: the run says why" "$d/log1" "which is not a release tag there"
  same "t28b: nothing is written" "0.19.0 " "$(ver_of "$c") $(git -C "$c" status --porcelain)"
  fx_update "$c" "$up" "$d/log2" --yes --allow-untagged-source; rc=$?
  expect_rc "t28b: --allow-untagged-source installs the HEAD commit" 0 "$rc" "$d/log2"
  same "t28b: ... at its version" 0.21.0 "$(ver_of "$c")"
  if is_windows; then skip "t28b: the shallow-clone part (a file:// URL to an MSYS path)"; return 0; fi
  # The depth-1 clone of the default branch a pre-0.20 updater makes: no tag at its tip.
  git clone -q --depth 1 "file://$up" "$src2"
  fx_consumer "$c3" "$up" v0.19.0
  (cd "$c3" && fx_env "${BASH:-bash}" "$UPDATER" --source "$src2" --dry-run) < /dev/null > "$d/log3" 2>&1; rc=$?
  expect_rc "t28b: --dry-run cannot resolve it without fetching (exit 1)" 1 "$rc" "$d/log3"
  same "t28b: ... and fetches nothing into the clone" "" "$(git -C "$src2" tag)"
  git_shim "$d/bin"
  git clone -q --depth 1 "file://$up" "$src"
  fx_consumer "$c2" "$up" v0.19.0
  (cd "$c2" && PATH="$d/bin:$PATH" fx_env "${BASH:-bash}" "$UPDATER" --source "$src" --yes) < /dev/null > "$d/log4" 2>&1; rc=$?
  expect_rc "t28b: the shallow clone installs its origin's newest release" 0 "$rc" "$d/log4"
  log_has "t28b: the run says which" "$d/log4" "installing the newest release, v0.20.0"
  same "t28b: VERSION is the release's, not the tip's" 0.20.0 "$(ver_of "$c2")"
  lacks_line "t28b: no unreleased content" "$c2/$A" "alpha development twenty-six"
  has_line "t28b: the release's content" "$c2/$A" "alpha upstream twenty-five"
}

# --- t30b --------------------------------------------------------------------------------
t30b_removed_list_ignores_non_core_paths() {
  local d="$WORK/t30b" rc; local up="$d/up" c="$d/c" log="$d/log"
  base_upstream "$up"
  rm -rf "$up/.sumela/skills/gamma"; mkdir -p "$up/scripts/lib"
  printf '0.20.0\t../outside.md\t-\n0.20.0\tAGENTS.md\t-\n0.20.0\t%s\t-\n' "$G" > "$up/scripts/lib/sumela-removed-files.list"
  fx_release "$up" 0.20.0
  fx_consumer "$c" "$up" v0.19.0
  echo "outside the install" > "$d/outside.md"
  fx_update "$c" "$up" "$log" --yes; rc=$?
  expect_rc "t30b: exit 0" 0 "$rc" "$log"
  exists "t30b: a path outside the install is never removed" "$d/outside.md"
  exists "t30b: an OVERLAY path is never removed" "$c/AGENTS.md"
  log_has "t30b: the run names the skipped rows" "$log" "row skipped (not a CORE path, or unreadable): 0.20.0 ../outside.md -"
  absent "t30b: a CORE row still applies" "$c/$G"
}

CASES="t01_unmodified_applies t02_fork_kept_when_upstream_unchanged t02b_deleted_file_is_readd_and_yes_never_readds
t03_clean_merge_keeps_local_lines t04_conflict_keeps_local t04b_rerun_after_partial_keeps_merging
t04c_no_terminal_never_overwrites t04d_edited_merge_survives_a_rerun t04e_unanswered_gitignore_prompt_adds_nothing
t04f_stale_merge_never_offered t04g_resolved_merge_survives_later_runs t05_crlf_local_is_unmodified t06_collision_host_file_kept t07_wrong_base_disables_merge
t07b_vouched_file_reforked_in_upgrade_commit t07c_one_differing_vouched_file_is_a_fork t07d_unfinished_record_never_vouches
t07e_upgraded_bytes_are_no_evidence_of_a_wrong_base t08_self_heal_restores_fork
t08b_self_heal_after_a_pass_from_a_non_tag_commit t08c_self_heal_with_export_ignore t08d_incomplete_upstream_tree_fails_closed
t08e_self_heal_respects_committed_deletion t08f_self_heal_warns_about_staged_overwrites t08g_self_heal_afterpass_waits_across_runs
t08h_self_heal_keeps_your_uncommitted_change t08i_gitignored_live_file_is_never_deleted
t08j_self_heal_restores_before_the_questions t08k_untracked_upstream_copy_is_never_removed
t08l_waiting_row_survives_a_cleaned_upgrade_dir t08m_older_upstream_version_is_your_revert t09_removed_list
t09b_self_heal_keeps_retired_fork t09c_self_heal_keeps_your_edit_to_a_retired_file
t09d_self_heal_retired_afterpass_is_a_carry_row t10_binary_not_merged t11_monorepo_subdir_install
t12_interactive_skip_all_does_not_stamp t13_interactive_keep_is_deliberate t13b_interactive_enter_only_never_overwrites
t13c_interactive_theirs_needs_the_typed_path t13d_interactive_merged_refuses_markers t13e_piped_yes_never_loops t14_ambiguous_tag_files
t15_core_files_list_unchanged t16_base_from_record_commit_preferred t16b_updater_change_defers_stamp_until_rerun
t16c_release_updater_finishes_in_one_pass t16d_updater_floor_never_installs_an_old_updater t16e_older_source_is_refused
t16f_force_rerun_of_an_uncommitted_upgrade t16g_patched_updater_converges t16h_partial_pass_names_the_new_updater
t16i_cut_during_the_record_write_leaves_no_temp_file t27_merged_hook_keeps_mode t28_dirty_source_refused
t28b_untagged_source_refused_shallow_clone_resolves_release t29_merge_pin_violation_becomes_conflict
t30_removed_fork_with_successor_is_carry t30b_removed_list_ignores_non_core_paths t31_schema_three_way_keeps_local_edit
t32_rc_tag_never_discovered"

echo "scripts/update.sh three-way merge (R1-04)"
for t in $CASES; do
  if [ $# -gt 0 ]; then
    want=false
    for pre in "$@"; do case "$t" in "$pre"*) want=true ;; esac; done
    [ "$want" = true ] || continue
  fi
  echo "== $t"
  "$t"
done
echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
