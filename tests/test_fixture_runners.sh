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
# -Culture tr-TR reaches the processes a suite starts. For a failing suite with a long log it
# checks what both runners show, the same way: a FAIL line far from the end with the lines
# after it, git's line-ending warnings counted instead of shown (real ones from git, too), the
# 400-line cap on the excerpt, and the full log saved under SUMELA_FIXTURE_LOG_DIR.
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
unset SUMELA_FIXTURE_LOG_DIR        # set only by the runs that check the saved full logs

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
# section <log> <suite>: what a runner printed below the FAIL line of one suite
section() {
  LC_ALL=C awk -v s="  FAIL  $2 (" 'index($0, s) == 1 { on = 1; next }
    /^  (PASS|FAIL)  [^ ]/ || /^[0-9]+ suites/ { on = 0 } on' "$1"
}

# The planted long and flood suites print the same lines in both runners' fixtures:
#   long:  lines 1-200 "  PASS  early check N.", 201 "  FAIL  the far-away check", 202-203 its
#          details, 204-503 git line-ending warnings, 504-603 "  PASS  late check N.", and
#          604 "300 passed, 1 failed"; it exits 1
#   flood: 1000 lines "  FAIL  flood NNNN.", then 60 lines "  PASS  flood tail N."; it exits 1
# excerpt_checks <log> <long suite> <flood suite>: what both runners show for them.
excerpt_checks() {
  local log="$1" n
  has   "a long failing suite gets a FAIL line" "$log" "  FAIL  $2 (exit 1,"
  has   "...its failure lines before the tail are counted" "$log" "    [failure lines before the last 60 lines: 1, each shown with up to 6 lines after it]"
  has   "...a FAIL line 400 lines before the end is shown, with its place in the log" "$log" "    [line 201]"
  has   "...the FAIL line itself" "$log" "      FAIL  the far-away check"
  has   "...the lines after it" "$log" "        got:      2"
  has   "...6 of them, git's warnings skipped" "$log" "      PASS  late check 4."
  lacks "...and no more" "$log" "PASS  late check 5."
  lacks "a passing line far from any failure is not shown" "$log" "PASS  early check 100."
  has   "git's line-ending warnings are counted on one line" "$log" "    [300 lines of git line-ending warnings (\"LF will be replaced by CRLF\") left out]"
  lacks "...and never shown" "$log" "LF will be replaced by CRLF the next time"
  has   "the tail follows, with its place in the log" "$log" "    [the last 60 lines, from line 545]"
  has   "...up to the suite's last line" "$log" "    300 passed, 1 failed"
  has   "a flood of failure lines gets a FAIL line" "$log" "  FAIL  $3 (exit 1,"
  has   "...its excerpt stops at 400 lines and says what it left out" "$log" "    [the excerpt stops at 400 lines; not shown: 600 more lines, failure lines among them: 600]"
  n="$(LC_ALL=C grep -c 'FAIL  flood ' "$log")"
  if [ "$n" = 400 ]; then ok "...it shows 400 of its failure lines"; else bad "...it shows 400 of its failure lines (got $n)"; fi
  has   "...the first 400" "$log" "      FAIL  flood 0001."
  has   "...through the 400th" "$log" "      FAIL  flood 0400."
  lacks "...and not the 401st" "$log" "FAIL  flood 0401."
  has   "...then its tail" "$log" "      PASS  flood tail 60."
}

# saved_log_checks <log> <full-log dir> <long suite> <passing suite> <header label>
saved_log_checks() {
  local log="$1" dir="$2" saved="$2/$3.log" n
  has   "the header names the directory of the full logs" "$log" "$5$dir (each failing suite's)"
  has   "a failing suite names its full log" "$log" "    [full log: $saved]"
  if [ ! -f "$saved" ]; then
    bad "...which is saved ($saved is missing)"
  else
    n="$(LC_ALL=C grep -c 'LF will be replaced by CRLF the next time' "$saved")"
    if [ "$(wc -l <"$saved" | tr -d ' ')" = 604 ] && [ "$n" = 300 ] &&
       LC_ALL=C grep -qx '  FAIL  the far-away check' "$saved" &&
       [ "$(LC_ALL=C sed -n '$p' "$saved")" = "300 passed, 1 failed" ]; then
      ok "...and holds every line the suite printed, the warnings too"
    else
      bad "...and holds every line the suite printed, the warnings too ($(wc -l <"$saved" | tr -d ' ') lines, $n warnings)"
    fi
  fi
  if [ -e "$dir/$4.log" ]; then bad "a passing suite's log is not saved"; else ok "a passing suite's log is not saved"; fi
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
lacks "without SUMELA_FIXTURE_LOG_DIR no full log is saved" "$log" "[full log:"

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

# What a failing suite's log shows; the CI job's conditions (CRLF checkouts, the full logs saved).
L="$WORK/gb-long/tests"
mkdir -p "$L"
cp "$GB_RUNNER" "$L/"
cat >"$L/test_wiki_long.sh" <<'EOF'
i=0; while [ $i -lt 200 ]; do i=$((i + 1)); echo "  PASS  early check $i."; done
echo "  FAIL  the far-away check"
echo "    expected: 1"
echo "    got:      2"
i=0; while [ $i -lt 300 ]; do i=$((i + 1)); echo "warning: in the working copy of 'f$i', LF will be replaced by CRLF the next time Git touches it"; done
i=0; while [ $i -lt 100 ]; do i=$((i + 1)); echo "  PASS  late check $i."; done
echo "300 passed, 1 failed"
exit 1
EOF
cat >"$L/test_wiki_flood.sh" <<'EOF'
i=0; while [ $i -lt 1000 ]; do i=$((i + 1)); printf '  FAIL  flood %04d.\n' "$i"; done
i=0; while [ $i -lt 60 ]; do i=$((i + 1)); echo "  PASS  flood tail $i."; done
exit 1
EOF
cat >"$L/test_wiki_warnings.sh" <<'EOF'
# Fails, and prints nothing but the warnings git itself gives when it adds LF files under
# core.autocrlf=true (one line each since git 2.37, two lines before).
d="$(mktemp -d)" && cd "$d" && git -c init.defaultBranch=main init -q . || exit 9
i=0; while [ $i -lt 30 ]; do i=$((i + 1)); printf 'text\n' >"f$i.txt"; done
LC_ALL=C git -c core.autocrlf=true add .
cd / && rm -rf "$d"
exit 1
EOF
printf 'echo "  FAIL  printed by a suite that exits 0"\nexit 0\n' >"$L/test_registry_parity.sh"

log="$WORK/gb-long.log"
run "$log" gitenv crlf env SUMELA_FIXTURE_LOG_DIR="$WORK/gb logs" "$BASH" "$L/run-gitbash-fixtures.sh" --require-crlf
rc_is "long failing suites: exit 1" 1
has   "...and the summary counts them" "$log" "4 suites, 3 failed"
has   "a suite that exits 0 passes, whatever it prints" "$log" "  PASS  test_registry_parity.sh ("
excerpt_checks "$log" test_wiki_long.sh test_wiki_flood.sh
section "$log" test_wiki_warnings.sh >"$WORK/gb-warnings.txt"
has   "a suite that prints only git's real warnings still fails" "$log" "  FAIL  test_wiki_warnings.sh (exit 1,"
has   "...its warnings are counted" "$WORK/gb-warnings.txt" " of git line-ending warnings (\"LF will be replaced by CRLF\") left out]"
has   "...and nothing else is shown" "$WORK/gb-warnings.txt" "    (no other output)"
saved_log_checks "$log" "$WORK/gb logs" test_wiki_long.sh test_registry_parity.sh "  full logs:     "

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
  lacks "without SUMELA_FIXTURE_LOG_DIR no full log is saved" "$log" "[full log:"

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

  # What a failing suite's log shows: the same planted lines as in the Git Bash fixture.
  L="$WORK/ps-long/tests"
  mkdir -p "$L"
  cp "$PS_RUNNER" "$L/"
  cat >"$L/test_long.ps1" <<'EOF'
for ($i = 1; $i -le 200; $i++) { Write-Output "  PASS  early check $i." }
Write-Output '  FAIL  the far-away check'
Write-Output '    expected: 1'
Write-Output '    got:      2'
for ($i = 1; $i -le 300; $i++) { Write-Output "warning: in the working copy of 'f$i', LF will be replaced by CRLF the next time Git touches it" }
for ($i = 1; $i -le 100; $i++) { Write-Output "  PASS  late check $i." }
Write-Output '300 passed, 1 failed'
exit 1
EOF
  cat >"$L/test_flood.ps1" <<'EOF'
for ($i = 1; $i -le 1000; $i++) { Write-Output ('  FAIL  flood ' + $i.ToString('0000') + '.') }
for ($i = 1; $i -le 60; $i++) { Write-Output "  PASS  flood tail $i." }
exit 1
EOF
  cat >"$L/test_warnings.ps1" <<'EOF'
# Fails, and prints nothing but git's warnings, on standard error as git does.
for ($i = 1; $i -le 30; $i++) { [Console]::Error.WriteLine("warning: in the working copy of 'f$i.txt', LF will be replaced by CRLF the next time Git touches it") }
exit 1
EOF
  printf "Write-Output '  FAIL  printed by a suite that exits 0'\nexit 0\n" >"$L/test_passes.ps1"

  log="$WORK/ps-long.log"
  run "$log" env -u CI LC_ALL=en_US.UTF-8 SUMELA_FIXTURE_LOG_DIR="$WORK/ps logs" "$PWSH" -NoProfile -File "$L/run-ps-fixtures.ps1"
  rc_is "long failing suites: exit 1" 1
  has   "...and the summary counts them" "$log" "4 suites, 3 failed"
  has   "a suite that exits 0 passes, whatever it prints" "$log" "  PASS  test_passes.ps1 ("
  excerpt_checks "$log" test_long.ps1 test_flood.ps1
  section "$log" test_warnings.ps1 >"$WORK/ps-warnings.txt"
  has   "a suite that prints only git's warnings still fails" "$log" "  FAIL  test_warnings.ps1 (exit 1,"
  has   "...its warnings are counted" "$WORK/ps-warnings.txt" "    [30 lines of git line-ending warnings (\"LF will be replaced by CRLF\") left out]"
  has   "...and the rest of its output is shown" "$WORK/ps-warnings.txt" "    [stderr]"
  saved_log_checks "$log" "$WORK/ps logs" test_long.ps1 test_passes.ps1 "  full logs:  "

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
