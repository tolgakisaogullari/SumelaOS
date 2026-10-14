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
# tests/test_migrate_runner.sh, tests/test_migration_notes.sh. Each runs under this bash, with
# the repository root as working directory and stdin from /dev/null, and passes when it exits 0.
#
# Before any suite, a self-check sends two throwaway suites down the same path. One runs
# "exit 3" and must fail with 3. The other must pass, and it reports how a repository it
# creates checks text out. With --require-crlf, that must be CRLF, the condition the CI job
# exists for. A failed self-check stops the run with exit 2 instead of passing.
#
# The CI condition on another machine, without touching your own git config (git 2.32+; like
# the CI runner, this global config holds no user identity, so a suite sets its own):
#   cfg="$(mktemp)"; git config --file "$cfg" core.autocrlf true
#   GIT_CONFIG_GLOBAL="$cfg" bash tests/run-gitbash-fixtures.sh --require-crlf
#
# Usage: bash tests/run-gitbash-fixtures.sh [--require-crlf]
# Exit 0 = every suite passed, or none exists yet ("0 suites"); 1 = a suite failed (the tail of
# its output is printed); 2 = usage error, or the self-check failed.
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sumela-gitbash-fixtures.XXXXXX")" || {
  echo "run-gitbash-fixtures: cannot create a temporary directory" >&2
  exit 2
}
trap 'rm -rf "$WORK"' EXIT

# run_suite <script> <log>: runs the script the way every suite runs; returns its exit status.
run_suite() {
  (cd "$REPO_ROOT" && "$BASH" "$1") </dev/null >"$2" 2>&1
}

# print_tail <log>: the last TAIL_LINES lines of a log, indented.
print_tail() {
  local lines
  if [ ! -s "$1" ]; then echo "    (no output)"; return; fi
  lines="$(wc -l <"$1" | tr -d ' ')"
  [ "$lines" -le "$TAIL_LINES" ] || echo "    [$((lines - TAIL_LINES)) earlier lines omitted]"
  tail -n "$TAIL_LINES" "$1" | sed 's/^/    /'
}

autocrlf="$(git -C "$REPO_ROOT" config --get core.autocrlf || echo unset)"
echo "Bash fixtures (tests/test_wiki_*.sh, test_update_merge.sh, test_migrate_runner.sh, test_migration_notes.sh)"
echo "  bash:          $BASH_VERSION ($(uname -s))"
echo "  core.autocrlf: $autocrlf"

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
  echo "  passing suite output:"; print_tail "$check/pass.log"
  echo "  failing suite output:"; print_tail "$check/fail.log"
  exit 2
fi
echo "  checkouts:     ${eol:-unknown} line endings in a repository a suite creates"
echo "  self-check:    ok (a failing suite gives exit 3, a passing one exit 0)"

# --- The suites ------------------------------------------------------------------------------
total=0 failed=0
for pattern in 'test_wiki_*.sh' test_update_merge.sh test_migrate_runner.sh test_migration_notes.sh; do
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
      print_tail "$log"
    fi
  done
done

if [ "$total" -eq 0 ]; then echo "0 suites"; else echo "$total suites, $failed failed"; fi
[ "$failed" -eq 0 ] || exit 1
exit 0
