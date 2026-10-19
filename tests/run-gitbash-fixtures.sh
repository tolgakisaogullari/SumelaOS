#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/run-gitbash-fixtures.sh - runs the bash suites that touch tracked text, one process each.
#
# The CI "windows" job runs it under Git Bash after `git config --global core.autocrlf true`,
# Git for Windows' installer default: every repository a suite creates then checks text out
# with CRLF, and a reader that forgets to strip "\r" fails here [RU-C3]. The job runs it once
# more after `Set-Culture tr-TR`, so the PowerShell twins a suite starts run under tr-TR
# [RU-M2]. tests/smoke.sh runs the same suites on Linux and macOS; tests/test_fixture_runners.sh
# tests this file.
#
# Suites, each that exists: tests/test_wiki_*.sh, tests/test_update_merge.sh,
# tests/test_migrate_runner.sh, tests/test_migration_notes.sh, tests/test_registry_parity.sh.
# Each runs under this bash, with the repository root as working directory and stdin from
# /dev/null, and passes when it exits 0.
#
# Before any suite, a self-check sends two throwaway suites down the same path. One runs
# "exit 3" and must fail with 3. The other must pass, and it reports how a repository it
# creates checks text out. With --require-crlf, that must be CRLF, the condition the CI job
# exists for. A failed self-check stops the run with exit 2 instead of passing.
#
# What a failing suite printed is shown in two parts, so a failure far from the end of a long
# log is never lost. First every failure line before the last 60 lines, each with the 6 lines
# after it, as one excerpt of at most 400 lines (a cut says how many lines it left out). Then
# the last 60 lines. A failure line starts with FAIL or FAILED, or holds Exception, Traceback,
# fatal:, error:, [stderr] or a bash "line N:" error; a line that starts with PASS or SKIP never
# is one. "[line N]" gives a block's place in the full log. git's line-ending warnings ("LF will
# be replaced by CRLF"), which crowd a log under core.autocrlf=true, are left out of what is
# shown and counted on one line. The suite itself sees its output unchanged.
#
# SUMELA_FIXTURE_LOG_DIR=<dir> saves the full log of each failing suite as <dir>/<suite>.log
# (the CI job uploads that directory). Under Git Bash a Windows path is accepted.
#
# The CI condition on another machine, without touching your own git config (git 2.32+; like
# the CI runner, this global config holds no user identity, so a suite sets its own):
#   cfg="$(mktemp)"; git config --file "$cfg" core.autocrlf true
#   GIT_CONFIG_GLOBAL="$cfg" bash tests/run-gitbash-fixtures.sh --require-crlf
#
# Usage: bash tests/run-gitbash-fixtures.sh [--require-crlf]
# Exit 0 = every suite passed, or none exists yet ("0 suites"); 1 = a suite failed (its failure
# lines and the tail of its output are printed); 2 = usage error, or the self-check failed.
# -----------------------------------------------------------------------------
if [ -z "${BASH_VERSION:-}" ]; then
  echo "run-gitbash-fixtures: run it with bash: bash tests/run-gitbash-fixtures.sh" >&2
  exit 2
fi
set -uo pipefail

usage() { echo "usage: bash tests/run-gitbash-fixtures.sh [--require-crlf]"; }
require_crlf=0
for arg in "$@"; do
  case "$arg" in
    --require-crlf) require_crlf=1 ;;
    -h|--help) usage; echo "Runs the bash suites that touch tracked text; see the header of this file."; exit 0 ;;
    *) echo "run-gitbash-fixtures: unknown argument '$arg'" >&2; usage >&2; exit 2 ;;
  esac
done

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
TAIL_LINES=60
CONTEXT_LINES=6      # lines shown after each failure line
EXCERPT_CAP=400      # lines of failure excerpt shown per suite, before its tail

LOG_DIR="${SUMELA_FIXTURE_LOG_DIR:-}"
if [ -n "$LOG_DIR" ] && command -v cygpath >/dev/null 2>&1; then
  # Git Bash: D:\a\_temp\logs becomes /d/a/_temp/logs; if that fails, the path is used as given.
  LOG_DIR="$(cygpath -u "$LOG_DIR")" && [ -n "$LOG_DIR" ] || LOG_DIR="$SUMELA_FIXTURE_LOG_DIR"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sumela-gitbash-fixtures.XXXXXX")" || {
  echo "run-gitbash-fixtures: cannot create a temporary directory" >&2
  exit 2
}
trap 'rm -rf "$WORK"' EXIT

# run_suite <script> <log>: runs the script the way every suite runs; returns its exit status.
run_suite() {
  (cd "$REPO_ROOT" && "$BASH" "$1") </dev/null >"$2" 2>&1
}

# The excerpt of a log, as the header describes; tests/run-ps-fixtures.ps1 prints the same.
# POSIX awk (BWK awk, mawk, gawk), run under LC_ALL=C so any bytes pass through unchanged.
EXCERPT_AWK='
function noun(k)        { return k == 1 ? "line" : "lines" }
function fail_line(s)   { return s ~ /^[ \t]*FAIL(ED)?$/ || s ~ /^[ \t]*FAIL(ED)?[^A-Za-z0-9_]/ }
function verdict_ok(s)  { return s ~ /^[ \t]*(PASS|SKIP)$/ || s ~ /^[ \t]*(PASS|SKIP)[^A-Za-z0-9_]/ }
function eol_warning(s) {
  return s ~ /warning: .*(LF will be replaced by CRLF|CRLF will be replaced by LF)/ ||
         s ~ /^[ \t]*The file will have its original line endings in your working directory[ \t]*$/
}
function failure_line(s) {
  if (fail_line(s)) return 1
  if (verdict_ok(s)) return 0
  return s ~ /Exception|Traceback|\[stderr\]|[Ff][Aa][Tt][Aa][Ll]:|[Ee][Rr][Rr][Oo][Rr]:|: line [0-9]+: /
}
BEGIN { tailn += 0; ctx += 0; cap += 0 }
{ sub(/\r$/, "") }
$0 != "" { lastraw = NR }
!fail_line($0) && eol_warning($0) { warnings++; next }
{ n++; text[n] = $0; at[n] = NR }
END {
  if (lastraw == 0) { print "    (no output)"; exit }
  while (n > 0 && at[n] > lastraw) n--         # trailing empty lines, as the PowerShell runner drops them
  if (warnings > 0) printf "    [%d %s of git line-ending warnings (\"LF will be replaced by CRLF\") left out]\n", warnings, noun(warnings)
  if (n == 0) { print "    (no other output)"; exit }
  t = n - tailn; if (t < 0) t = 0              # lines 1..t come before the tail
  found = 0
  for (i = 1; i <= t; i++) {
    if (!failure_line(text[i])) continue
    found++; failure[i] = 1
    for (j = i; j <= i + ctx && j <= t; j++) keep[j] = 1
  }
  if (found > 0) {
    printf "    [failure lines before the last %d lines: %d, each shown with up to %d lines after it]\n", tailn, found, ctx
    shown = 0; prev = -1; cut = 0; cutfail = 0
    for (i = 1; i <= t; i++) {
      if (!(i in keep)) continue
      if (shown >= cap) { cut++; if (i in failure) cutfail++; continue }
      if (i != prev + 1) printf "    [line %d]\n", at[i]
      print "    " text[i]; shown++; prev = i
    }
    if (cut > 0) printf "    [the excerpt stops at %d lines; not shown: %d more %s, failure lines among them: %d]\n", cap, cut, noun(cut), cutfail
    printf "    [the last %d lines, from line %d]\n", n - t, at[t + 1]
  } else if (t > 0) {
    printf "    [%d earlier %s omitted]\n", t, noun(t)
  }
  for (i = t + 1; i <= n; i++) print "    " text[i]
}'

# print_log <log>: what a failing suite printed, indented: its failure excerpt, then its tail.
print_log() {
  if [ ! -s "$1" ]; then echo "    (no output)"; return; fi
  LC_ALL=C awk -v tailn="$TAIL_LINES" -v ctx="$CONTEXT_LINES" -v cap="$EXCERPT_CAP" "$EXCERPT_AWK" "$1"
}

# save_log <log> <suite name>: with SUMELA_FIXTURE_LOG_DIR set, keeps the full log there.
save_log() {
  [ -n "$LOG_DIR" ] || return 0
  if mkdir -p "$LOG_DIR" && cp "$1" "$LOG_DIR/$2.log"; then
    echo "    [full log: $LOG_DIR/$2.log]"
  else
    echo "    [could not save the full log in $LOG_DIR: see the error above]"
  fi
}

autocrlf="$(git -C "$REPO_ROOT" config --get core.autocrlf || echo unset)"
echo "Bash fixtures (tests/test_wiki_*.sh, test_update_merge.sh, test_migrate_runner.sh, test_migration_notes.sh, test_registry_parity.sh)"
echo "  bash:          $BASH_VERSION ($(uname -s))"
echo "  core.autocrlf: $autocrlf"
[ -z "$LOG_DIR" ] || echo "  full logs:     $LOG_DIR (each failing suite's)"

# --- Self-check: the path every suite takes must tell a failure from a pass ----------------
check="$WORK/self-check"
mkdir "$check"
cat >"$check/pass.sh" <<'EOF'
echo "probe ok"
# How a repository this suite creates checks text out: core.autocrlf and the rest of git's config.
eol=unknown
if mkdir "${0%/*}/eol-probe" && cd "${0%/*}/eol-probe" && git init -q . && printf 'a\nb\n' >f &&
   git add f && git checkout-index --prefix=co/ -- f; then
  if [ -n "$(LC_ALL=C tr -cd '\r' <co/f)" ]; then eol=crlf; else eol=lf; fi   # tr: a Windows grep may drop CRs
fi
echo "eol $eol"
EOF
printf 'echo "failing on purpose"\nexit 3\n' >"$check/fail.sh"
run_suite "$check/pass.sh" "$check/pass.log"; pass_rc=$?
run_suite "$check/fail.sh" "$check/fail.log"; fail_rc=$?
eol="$(LC_ALL=C sed -n 's/^eol \([a-z]*\)$/\1/p' "$check/pass.log")"
problem=""
if [ "$fail_rc" -ne 3 ]; then
  problem="a suite that runs \"exit 3\" gave exit $fail_rc"
elif [ "$pass_rc" -ne 0 ]; then
  problem="a suite that passes gave exit $pass_rc"
elif ! LC_ALL=C grep -q '^probe ok$' "$check/pass.log"; then
  problem="the output of the passing suite was not captured"
elif [ "$require_crlf" -eq 1 ] && [ "$eol" != crlf ]; then
  problem="--require-crlf: a repository a suite creates checks text out with ${eol:-unknown} line endings, not CRLF (core.autocrlf: $autocrlf)"
fi
if [ -n "$problem" ]; then
  echo "  self-check FAILED: $problem"
  echo "  passing suite output:"; print_log "$check/pass.log"
  echo "  failing suite output:"; print_log "$check/fail.log"
  exit 2
fi
echo "  checkouts:     ${eol:-unknown} line endings in a repository a suite creates"
echo "  self-check:    ok (a failing suite gives exit 3, a passing one exit 0)"

# --- The suites ------------------------------------------------------------------------------
total=0 failed=0
for pattern in 'test_wiki_*.sh' test_update_merge.sh test_migrate_runner.sh test_migration_notes.sh test_registry_parity.sh; do
  for suite in "$TESTS_DIR"/$pattern; do          # $pattern unquoted: it is a glob
    [ -f "$suite" ] || continue                   # a pattern that matched nothing stays literal
    name="${suite##*/}"
    log="$WORK/$name.log"
    total=$((total + 1))
    started=$SECONDS
    if run_suite "$suite" "$log"; then
      echo "  PASS  $name ($((SECONDS - started)) s)"
    else
      rc=$?
      failed=$((failed + 1))
      echo "  FAIL  $name (exit $rc, $((SECONDS - started)) s)"
      save_log "$log" "$name"
      print_log "$log"
    fi
  done
done

if [ "$total" -eq 0 ]; then echo "0 suites"; else echo "$total suites, $failed failed"; fi
[ "$failed" -eq 0 ] || exit 1
exit 0
