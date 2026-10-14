#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/test_fixture_runners.sh - the two CI fixture runners count, report and refuse correctly.
#
# tests/run-ps-fixtures.ps1 and tests/run-gitbash-fixtures.sh decide whether the CI "windows"
# job is green, and every Windows acceptance in Release 1 rests on them. A runner that stopped
# counting failures, or stopped finding suites, would turn that job green while suites fail.
# This suite copies each runner into a throwaway repository with planted passing and failing
# suites. It checks the exit code, the PASS and FAIL lines and the "N suites, M failed"
# summary, and also the usage errors (exit 2), "0 suites", --require-crlf, and that
# -Culture tr-TR reaches the processes a suite starts.
#
# Needs bash and git. The PowerShell half needs pwsh (SKIP without it) and runs outside Windows,
# where LC_ALL selects the culture. On Windows the CI job relies on the runner's own self-check.
# Run from anywhere:  bash tests/test_fixture_runners.sh
# Exit 0 = all assertions passed, 1 = a failure (printed above).
# -----------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GB_RUNNER="$SCRIPT_DIR/run-gitbash-fixtures.sh"
PS_RUNNER="$SCRIPT_DIR/run-ps-fixtures.ps1"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0 FAIL=0
ok()   { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP  $1"; }

# Every run reads this file as stdin. A suite that inherited it, instead of the empty stdin
# the runner must give it, would read a line.
printf 'planted input\n' >"$WORK/stdin.txt"

# run <log> <command...>: runs the command, writes its output with CRs stripped to <log>, sets RC.
RC=0
run() {
  local log="$1"
  shift
  "$@" <"$WORK/stdin.txt" >"$log.raw" 2>&1
  RC=$?
  tr -d '\r' <"$log.raw" >"$log"
}
# rc_is <label> <expected exit code>: about the last run
rc_is() { if [ "$RC" = "$2" ]; then ok "$1"; else bad "$1 (expected exit $2, got $RC)"; fi; }
# has <label> <log> <text>: the log contains the text (a fixed string)
has() {
  if LC_ALL=C grep -qF -- "$3" "$2"; then ok "$1"; return; fi
  bad "$1 (missing: $3)"
  LC_ALL=C sed -n '1,40p' "$2" | sed 's/^/      | /'
}
# lacks <label> <log> <text>
lacks() { if LC_ALL=C grep -qF -- "$3" "$2"; then bad "$1 (unexpected: $3)"; else ok "$1"; fi; }
# last_is <label> <log> <line>
last_is() {
  local last
  last="$(LC_ALL=C sed -n '$p' "$2")"
  if [ "$last" = "$3" ]; then ok "$1"; else bad "$1 (expected the last line [$3], got [$last])"; fi
}

# =============================================================================================
echo "Git Bash runner (tests/run-gitbash-fixtures.sh)"
GB="$WORK/gb repo"                         # a space in the path, as in many Windows profiles
t="$GB/tests"
mkdir -p "$t"
cp "$GB_RUNNER" "$t/"
printf 'echo "wiki a passes"\n' >"$t/test_wiki_a.sh"
printf 'echo "wiki b fails on purpose" >&2\nexit 3\n' >"$t/test_wiki_b.sh"
cat >"$t/test_update_merge.sh" <<'EOF'
# Passes only when stdin is empty: the runner gives every suite /dev/null.
if IFS= read -r line; then echo "stdin had: $line"; exit 4; fi
EOF
cat >"$t/test_migration_notes.sh" <<'EOF'
# Passes only when the working directory is the repository root.
root="$(cd "$(dirname "$0")/.." && pwd -P)"
[ "$(pwd -P)" = "$root" ] || { echo "cwd is $(pwd -P), not $root"; exit 5; }
EOF
cat >"$t/test_migrate_runner.sh" <<'EOF'
# Passes only when a repository it creates checks text out with CRLF line endings.
d="$(dirname "$0")/../crlf-probe-$$"
mkdir "$d" && cd "$d" && git init -q . && printf 'a\n' >f && git add f &&
  git checkout-index --prefix=co/ -- f || exit 6
[ -n "$(LC_ALL=C tr -cd '\r' <co/f)" ] || { echo "checked out with LF"; exit 7; }
EOF
printf 'exit 1\n' >"$t/test_other.sh"           # not in the runner's list
printf 'exit 1\n' >"$t/test_wiki_c.sh.bak"     # does not end in .sh
mkdir "$t/test_wiki_dir.sh"                    # a directory

# Only the given global config and no system config, on any git version: GIT_CONFIG_GLOBAL
# needs git 2.32, and HOME covers older ones.
mkdir -p "$WORK/home-crlf" "$WORK/home-lf"
git config --file "$WORK/home-crlf/.gitconfig" core.autocrlf true
git config --file "$WORK/home-lf/.gitconfig" core.autocrlf false
# gitenv <crlf|lf> <command...>
gitenv() {
  local home="$WORK/home-$1"
  shift
  env -u XDG_CONFIG_HOME HOME="$home" GIT_CONFIG_GLOBAL="$home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 "$@"
}

log="$WORK/gb-crlf.log"
run "$log" gitenv crlf "$BASH" "$t/run-gitbash-fixtures.sh" --require-crlf
rc_is "one failing suite: exit 1" 1
has   "the summary counts the suites in its list and the failure" "$log" "5 suites, 1 failed"
has   "a passing suite gets a PASS line" "$log" "  PASS  test_wiki_a.sh ("
has   "a failing suite gets a FAIL line with its exit code" "$log" "  FAIL  test_wiki_b.sh (exit 3,"
has   "...and the tail of its output, stderr included" "$log" "    wiki b fails on purpose"
has   "a suite reads an empty stdin" "$log" "  PASS  test_update_merge.sh ("
has   "a suite runs from the repository root" "$log" "  PASS  test_migration_notes.sh ("
has   "a suite's repository checks text out with CRLF" "$log" "  PASS  test_migrate_runner.sh ("
has   "the self-check passes" "$log" "  self-check:    ok"
has   "the header reports CRLF checkouts" "$log" "  checkouts:     crlf line endings"
lacks "a suite outside its list does not run" "$log" "test_other.sh"
lacks "a file that does not end in .sh does not run" "$log" "test_wiki_c.sh.bak"
lacks "a directory does not run" "$log" "test_wiki_dir.sh"

log="$WORK/gb-lf-required.log"
run "$log" gitenv lf "$BASH" "$t/run-gitbash-fixtures.sh" --require-crlf
rc_is "--require-crlf without CRLF checkouts: exit 2" 2
has   "...naming the reason" "$log" "self-check FAILED: --require-crlf"
lacks "...before any suite runs" "$log" "PASS  test_wiki_a.sh"

log="$WORK/gb-lf.log"
run "$log" gitenv lf "$BASH" "$t/run-gitbash-fixtures.sh"
rc_is "LF checkouts without --require-crlf: the suites run (exit 1)" 1
has   "...and the CRLF suite fails" "$log" "  FAIL  test_migrate_runner.sh (exit 7,"
has   "...counted in the summary" "$log" "5 suites, 2 failed"

mkdir -p "$WORK/gb-green/tests"
cp "$GB_RUNNER" "$WORK/gb-green/tests/"
printf 'exit 0\n' >"$WORK/gb-green/tests/test_wiki_ok.sh"
log="$WORK/gb-green.log"
run "$log" gitenv crlf "$BASH" "$WORK/gb-green/tests/run-gitbash-fixtures.sh"
rc_is "every suite passes: exit 0" 0
last_is "...and the summary says so" "$log" "1 suites, 0 failed"

mkdir -p "$WORK/gb-empty/tests"
cp "$GB_RUNNER" "$WORK/gb-empty/tests/"
log="$WORK/gb-empty.log"
run "$log" gitenv crlf "$BASH" "$WORK/gb-empty/tests/run-gitbash-fixtures.sh"
rc_is "no suite yet: exit 0" 0
last_is "...and the last line is \"0 suites\"" "$log" "0 suites"

run "$WORK/gb-u1.log" "$BASH" "$t/run-gitbash-fixtures.sh" --bogus
rc_is "an unknown argument: exit 2" 2
run "$WORK/gb-u2.log" "$BASH" "$t/run-gitbash-fixtures.sh" ""
rc_is "an empty argument: exit 2" 2
run "$WORK/gb-u3.log" "$BASH" "$t/run-gitbash-fixtures.sh" --require-crlf extra
rc_is "an extra argument after a valid one: exit 2" 2
run "$WORK/gb-u4.log" "$BASH" "$t/run-gitbash-fixtures.sh" -h
rc_is "-h: exit 0" 0
has   "...with the usage line" "$WORK/gb-u4.log" "usage: bash tests/run-gitbash-fixtures.sh [--require-crlf]"

# =============================================================================================
echo ""
echo "PowerShell runner (tests/run-ps-fixtures.ps1)"
PWSH="$(command -v pwsh 2>/dev/null || true)"
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) on_windows=1 ;; *) on_windows=0 ;; esac
if [ -z "$PWSH" ]; then
  skip "the PowerShell runner (pwsh unavailable)"
elif [ "$on_windows" -eq 1 ]; then
  skip "the PowerShell runner on Windows (the OS sets the culture; the CI job relies on the runner's self-check)"
else
  p="$WORK/ps repo's/tests"                # a space and a single quote in the path
  mkdir -p "$p"
  cp "$PS_RUNNER" "$p/"
  printf "Write-Output 'a passes'\nexit 0\n" >"$p/test_a_pass.ps1"
  printf "Write-Output 'b fails on purpose'\nexit 3\n" >"$p/test_b_fail.ps1"
  printf "Write-Output 'c throws'\nthrow 'boom'\n" >"$p/test_c_throw.ps1"
  cat >"$p/test_d_culture.ps1" <<'EOF'
# Fails under a Turkic culture, where "I".ToLower() is a dotless i.
if ('I'.ToLower() -cne 'i') { Write-Output 'lowercasing depends on the culture'; exit 5 }
EOF
  cat >"$p/test_e_child.ps1" <<'EOF'
# Fails when a process this suite starts runs under another culture than the suite itself.
$exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$child = @(& $exe -NoProfile -NonInteractive -Command '[System.Globalization.CultureInfo]::CurrentCulture.Name') -join ' '
$own = [System.Globalization.CultureInfo]::CurrentCulture.Name
if ($child -cne $own) { Write-Output ('the child runs under [' + $child + '], the suite under [' + $own + ']'); exit 6 }
EOF
  printf 'exit 1\n' >"$p/helper.ps1"          # not test_*
  printf 'exit 1\n' >"$p/Test_Upper.ps1"      # the prefix is case-sensitive
  printf 'x\n' >"$p/test_x.ps1xml"            # does not end in .ps1
  mkdir "$p/test_dir.ps1"                     # a directory

  # LC_ALL=en_US.UTF-8: the plain runs get en-US whatever this machine's locale (on macOS an
  # unset or C locale falls back to the system language). CI is unset unless a case sets it.
  log="$WORK/ps-plain.log"
  run "$log" env -u CI LC_ALL=en_US.UTF-8 "$PWSH" -NoProfile -File "$p/run-ps-fixtures.ps1"
  rc_is "failing suites: exit 1" 1
  has   "the summary counts every test_*.ps1 and the failures" "$log" "5 suites, 2 failed"
  has   "a passing suite gets a PASS line" "$log" "  PASS  test_a_pass.ps1 ("
  has   "a failing suite gets a FAIL line with its exit code" "$log" "  FAIL  test_b_fail.ps1 (exit 3,"
  has   "...and the tail of its output" "$log" "    b fails on purpose"
  has   "an uncaught error fails with exit 1" "$log" "  FAIL  test_c_throw.ps1 (exit 1,"
  has   "a culture-sensitive suite passes under en-US" "$log" "  PASS  test_d_culture.ps1 ("
  has   "a process a suite starts shares its culture" "$log" "  PASS  test_e_child.ps1 ("
  has   "the self-check passes" "$log" "  self-check: ok"
  has   "the header reports the host default culture" "$log" "  culture:    en-US, the host default"
  lacks "a file without the test_ prefix does not run" "$log" "helper.ps1"
  lacks "a Test_ prefix does not run" "$log" "Test_Upper.ps1"
  lacks "a .ps1xml file does not run" "$log" "test_x.ps1xml"
  lacks "a directory does not run" "$log" "test_dir.ps1"

  # CI=true: the runner stops with exit 2 if a process a suite starts misses the culture.
  log="$WORK/ps-tr.log"
  run "$log" env CI=true LC_ALL=en_US.UTF-8 "$PWSH" -NoProfile -File "$p/run-ps-fixtures.ps1" -Culture tr-TR
  rc_is "-Culture tr-TR in CI: exit 1 for the failing suites, not 2" 1
  has   "the culture-sensitive suite fails too" "$log" "  FAIL  test_d_culture.ps1 (exit 5,"
  has   "...counted in the summary" "$log" "5 suites, 3 failed"
  has   "a process a suite starts runs under tr-TR as well" "$log" "  PASS  test_e_child.ps1 ("
  has   "the header reports both" "$log" "  culture:    tr-TR in each suite process and in the processes it starts"
  has   "...and the LC_ALL each suite gets" "$log" "  LC_ALL:     tr_TR.UTF-8, set for each suite"
  has   "\"exit 3\" keeps its code under -Culture" "$log" "  FAIL  test_b_fail.ps1 (exit 3,"
  has   "an uncaught error still gives exit 1" "$log" "  FAIL  test_c_throw.ps1 (exit 1,"
  lacks "no warning" "$log" "WARNING"

  mkdir -p "$WORK/ps-empty/tests"
  cp "$PS_RUNNER" "$WORK/ps-empty/tests/"
  log="$WORK/ps-empty.log"
  run "$log" env -u CI LC_ALL=en_US.UTF-8 "$PWSH" -NoProfile -File "$WORK/ps-empty/tests/run-ps-fixtures.ps1"
  rc_is "no suite yet: exit 0" 0
  last_is "...and the last line is \"0 suites\"" "$log" "0 suites"

  run "$WORK/ps-u1.log" "$PWSH" -NoProfile -File "$p/run-ps-fixtures.ps1" -Bogus
  rc_is "an unknown argument: exit 2" 2
  run "$WORK/ps-u2.log" "$PWSH" -NoProfile -File "$p/run-ps-fixtures.ps1" -Culture
  rc_is "-Culture without a value: exit 2" 2
  has   "...naming what is missing" "$WORK/ps-u2.log" "-Culture needs a culture name"
  run "$WORK/ps-u3.log" "$PWSH" -NoProfile -File "$p/run-ps-fixtures.ps1" -Culture ""
  rc_is "an empty -Culture: exit 2" 2
  run "$WORK/ps-u4.log" "$PWSH" -NoProfile -File "$p/run-ps-fixtures.ps1" -Culture xx-NOPE-zz
  rc_is "an unknown culture: exit 2" 2
  run "$WORK/ps-u5.log" "$PWSH" -NoProfile -File "$p/run-ps-fixtures.ps1" -h
  rc_is "-h: exit 0" 0
  has   "...with the usage line" "$WORK/ps-u5.log" "usage: run-ps-fixtures.ps1 [-Culture <name>]"
fi

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
