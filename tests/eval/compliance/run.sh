#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/eval/compliance/run.sh — the agent-compliance evaluation [RQ-13]. Maintainer-run, source-only,
# never part of CI. Runs scripted multi-session scenarios (C1-C6) against the SumelaOS instruction text
# of one framework version, on synthetic fixture repositories, with a real headless agent, and judges
# every outcome mechanically. `--help` documents usage, cost, privacy and exit codes; README.md the rest.
# bash 3.2 compatible.
# -----------------------------------------------------------------------------
set -uo pipefail
umask 077

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  tests/eval/compliance/run.sh --framework <git-ref> --agent-cmd '<command>' [--runs N]
                               [--scenario <id>]... [--compare <baseline-ref>] [--state-dir <dir>] [--keep]
  tests/eval/compliance/run.sh --framework <git-ref> --compare <baseline-ref> --no-run [--state-dir <dir>]
  tests/eval/compliance/run.sh --list | --help

Runs the agent-compliance scenarios against the SumelaOS instruction text of <git-ref> (a tag such as
v0.20.1-rc.1, a branch or a commit of this repository). For every run of every scenario it builds a
synthetic consumer repository from `git archive <git-ref>` plus `scripts/setup.sh --non-interactive`,
runs the scenario's sessions one after another through the agent command, and checks the outcome
mechanically: file state, git state and transcript order. No model judges anything.

Options:
  --framework <ref>    the framework version under test
  --agent-cmd '<cmd>'  runs ONE headless agent session: bash runs it in the session's checkout, stdin
                       closed. Placeholders, each a word of its own and never inside quotes: {PROMPT}
                       the session's prompt (required), {DIR} the checkout, {SESSION} its number,
                       {SCENARIO_DIR} the scenario's directory, {HARNESS} this directory. Inside a
                       quoted argument use $CMP_DIR and the like: shell variables of the command, never
                       exported. The command prints its transcript on stdout: Claude Code stream-json,
                       or event lines (README.md). For Claude Code:
                         'bash {HARNESS}/agents/claude-code.sh --model <pinned model id> {DIR} {PROMPT}'
                       A permission-bypass mode is refused, and so is a command that spans lines
                       without a backslash at the end of each line.
  --runs N             runs per scenario, 1 to 3 (default 3; the gate needs 3)
  --scenario <id>      run only this scenario; repeatable (default: every scenario, see --list)
  --compare <ref>      then apply the release gate against the saved results of <ref>
  --no-run             with --compare: gate the saved results of --framework, run nothing
  --state-dir <dir>    where results are saved (default: this checkout's developer state directory,
                       from scripts/lib/sumela-state.sh)
  --keep               keep the work directories (fixtures and transcripts) and print where they are
  --list               list the scenarios
  -h, --help           this text

Output: a TSV table, `scenario runs pass framework`, one row per scenario; aggregates only. It is
also merged into <state>/compliance/<framework>.tsv (mode 0600): a re-run scenario replaces its row,
and a scenario with a run that could not complete is not saved. Progress goes to stderr.

Gate (--compare; plan §6.2, Q19): for every scenario gated at the framework's version (meta.txt
gate_from), both sides have 3 runs, the new text passes at least 2 of 3, and it passes no fewer than
the baseline. Run the baseline and the candidate with the same agent command and pinned model.

Cost: a scenario is at most 3 headless agent sessions, so one framework costs at most
6 scenarios x 3 sessions x 3 runs = 54 sessions, each loading the full SumelaOS context (about 135 KB
of instructions before any work) and running a small task to completion. The old-text baseline runs
once (v0.20.0); each later release candidate runs once. Cap every session in the agent command
(agents/claude-code.sh passes Claude Code's --max-budget-usd, 3 USD unless you set it) and use
--scenario with --runs 1 while writing or debugging a scenario. A dry run with the stub agent
(README.md) costs nothing.

Privacy: the fixtures are synthetic (generic code, no consumer content) and nothing runs on a real
checkout. The agent command sends the fixture's files and the prompts to its model provider. The agent
runs as you, so it reaches whatever your account can reach unless something fences it: Claude Code runs
its read-only shell commands (cat, ls, grep, read-only git) without asking, a Bash rule is a command
prefix that no path limits, and code the agent runs (tests, git hooks, the wiki tool) is not fenced at
all. agents/claude-code.sh fences what Claude Code can fence: edits only inside the session's checkout,
its file tools refused outside the checkout (Claude Code 2.1.257 or later), reads under your home
directory denied to the file tools and to the shell commands Claude Code recognizes, no MCP servers, no
session persistence, no auto memory; --sandbox adds Claude Code's OS-level sandbox to shell commands.
For a hard boundary, run the evaluation as a throwaway user, or in a container or VM (README.md).
Transcripts and fixtures stay in private temporary directories (0700) that are deleted at exit unless
--keep; only aggregates are printed or saved, plus the last lines of a run's log when the run could
not complete. The harness never reads your own agent transcripts. The fixture runs the ref's own
scripts/setup.sh and hooks on this machine: evaluate only refs you trust.

Exit codes: 0 every run completed (and, with --compare, the gate passed); 1 the gate failed;
2 usage (also a placeholder inside quotes, or an agent command that spans lines without a backslash);
3 precondition refused (unknown ref, missing python3, missing state library without --state-dir, a
permission-bypass agent command, a missing baseline, a CLAUDE.md, AGENTS.md or .sumela above TMPDIR);
4 a run could not complete (a fixture, an agent session or a check failed; its cause is printed, the
run is left out of the counts and its scenario is not saved: re-run it).
EOF
}

usage_err() { cmp_err "$1"; echo "Run with --help for usage." >&2; exit 2; }

FRAMEWORK="" RUNS=3 AGENT_CMD="" COMPARE="" STATE_DIR="" KEEP=false NO_RUN=false LIST=false SELECTED=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --framework) [ $# -ge 2 ] || usage_err "--framework needs a value"; FRAMEWORK="$2"; shift ;;
    --agent-cmd) [ $# -ge 2 ] || usage_err "--agent-cmd needs a value"; AGENT_CMD="$2"; shift ;;
    --runs)      [ $# -ge 2 ] || usage_err "--runs needs a value"; RUNS="$2"; shift ;;
    --scenario)  [ $# -ge 2 ] || usage_err "--scenario needs a value"; SELECTED="$SELECTED $2"; shift ;;
    --compare)   [ $# -ge 2 ] || usage_err "--compare needs a value"; COMPARE="$2"; shift ;;
    --state-dir) [ $# -ge 2 ] || usage_err "--state-dir needs a value"; STATE_DIR="$2"; shift ;;
    --keep)   KEEP=true ;;
    --no-run) NO_RUN=true ;;
    --list)   LIST=true ;;
    *) usage_err "unknown option: $1" ;;
  esac
  shift
done

ALL_IDS="$(cmp_scenario_ids | tr '\n' ' ')"
if [ "$LIST" = true ]; then
  for id in $ALL_IDS; do
    d="$HERE/scenarios/$id"
    printf '%s\t%s sessions\tgated from %s\t%s: %s\n' "$id" "$(cmp_meta "$d" sessions)" \
      "$(cmp_meta "$d" gate_from)" "$(cmp_meta "$d" title)" "$(cmp_meta "$d" pass)"
  done
  exit 0
fi

# --- Validation ---------------------------------------------------------------------------------
[ -n "$FRAMEWORK" ] || usage_err "--framework is required"
case "$FRAMEWORK$COMPARE" in -*|*' '*) usage_err "a git ref cannot start with '-' or contain a space" ;; esac
case "$COMPARE" in -*) usage_err "a git ref cannot start with '-'" ;; esac
case "$RUNS" in 1|2|3) ;; *) usage_err "--runs must be 1, 2 or 3 (the documented cost bound)" ;; esac
if [ "$NO_RUN" = true ]; then
  [ -n "$COMPARE" ] || usage_err "--no-run needs --compare <baseline-ref>"
  [ -z "$AGENT_CMD" ] || usage_err "--no-run runs nothing: drop --agent-cmd"
else
  [ -n "$AGENT_CMD" ] || usage_err "--agent-cmd is required (see --help and README.md)"
  case "$AGENT_CMD" in *'{PROMPT}'*) ;; *) usage_err "--agent-cmd must pass {PROMPT} to the agent" ;; esac
  why="$(cmp_agent_cmd_ok "$AGENT_CMD")" || usage_err "--agent-cmd: $why"
  case "$AGENT_CMD" in
    *dangerously*|*bypassPermissions*|*danger-full-access*|*yolo*)
      cmp_err "refused: the agent command uses a permission-bypass mode; give it an explicit tool allow-list scoped to the fixture (README.md)"
      exit 3 ;;
  esac
  command -v python3 > /dev/null 2>&1 || { cmp_err "python3 is required to read agent transcripts"; exit 3; }
fi
[ -n "$SELECTED" ] || SELECTED="$ALL_IDS"
for id in $SELECTED; do
  case " $ALL_IDS " in *" $id "*) ;; *) usage_err "unknown scenario: $id (see --list)" ;; esac
done
git -C "$REPO_ROOT" rev-parse --git-dir > /dev/null 2>&1 && [ -d "$REPO_ROOT/.sumela" ] ||
  { cmp_err "run.sh must run from a SumelaOS framework source checkout ($REPO_ROOT)"; exit 3; }

# Results live in this checkout's developer state directory (R1-03), never in the repository.
if [ -z "$STATE_DIR" ]; then
  [ -f "$REPO_ROOT/scripts/lib/sumela-state.sh" ] ||
    { cmp_err "scripts/lib/sumela-state.sh is missing; pass --state-dir <dir>"; exit 3; }
  # shellcheck source=/dev/null
  . "$REPO_ROOT/scripts/lib/sumela-state.sh"
  STATE_DIR="$(sumela_state_dir --create --root "$REPO_ROOT")" && [ -n "$STATE_DIR" ] ||
    { cmp_err "could not resolve the developer state directory; pass --state-dir <dir>"; exit 3; }
fi
RESULTS_DIR="$STATE_DIR/compliance"

if [ "$NO_RUN" = true ]; then
  cmp_gate "$RESULTS_DIR" "$COMPARE" "$FRAMEWORK"; rc=$?
  [ "$rc" -eq 3 ] && exit 3
  exit "$rc"
fi

if [ -n "$COMPARE" ] && [ ! -f "$RESULTS_DIR/$(cmp_safe_name "$COMPARE").tsv" ]; then
  cmp_err "no saved results for the baseline $COMPARE in $RESULTS_DIR: run it first (R1-15)"; exit 3
fi
for id in $SELECTED; do
  ref="$(cmp_meta "$HERE/scenarios/$id" requires_ref)"
  [ -z "$ref" ] || git -C "$REPO_ROOT" rev-parse --verify --quiet "$ref^{commit}" > /dev/null ||
    { cmp_err "scenario $id needs $ref in this repository (git fetch --tags)"; exit 3; }
done

# --- Work directories: notes and transcripts apart from the fixtures the agent works in ------------
# The fixtures' directory has a neutral name and its physical path (on macOS /var is /private/var):
# the agent sees the path, and Claude Code applies an allow rule only when the resolved path matches too.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sumela-compliance.XXXXXX")" || { cmp_err "mktemp failed"; exit 4; }
FIX="$(mktemp -d "${TMPDIR:-/tmp}/work.XXXXXX")" || { rm -rf "$WORK"; cmp_err "mktemp failed"; exit 4; }
FIX_P="$(cd "$FIX" && pwd -P)" && [ -n "$FIX_P" ] || { rm -rf "$WORK" "$FIX"; cmp_err "cannot resolve $FIX"; exit 4; }
FIX="$FIX_P"
cleanup() {
  if [ "$KEEP" = true ]; then cmp_err "kept: $WORK (notes and transcripts) and $FIX (fixtures)"
  else rm -rf "$WORK" "$FIX"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Claude Code also loads CLAUDE.md from every parent directory of a session: keep the fixtures clear of any.
d="$FIX"
while [ "$d" != / ] && [ -n "$d" ]; do
  d="$(dirname "$d")"
  for x in CLAUDE.md AGENTS.md .sumela; do
    [ ! -e "$d/$x" ] || { cmp_err "refused: $d/$x would reach the fixture sessions; set TMPDIR outside any project"; exit 3; }
  done
done

cmp_prepare_framework "$REPO_ROOT" "$FRAMEWORK" "$WORK"; rc=$?
[ "$rc" -eq 0 ] || exit "$([ "$rc" -eq 3 ] && echo 3 || echo 4)"
cmp_hermetic_env
# Exported for the scenarios' setup.sh; cmp_agent_env removes every CMP_* variable before an agent starts.
CMP_VERBOSE=1 CMP_BASE_CACHE="$WORK/base"; export CMP_VERBOSE CMP_BASE_CACHE
FINGERPRINT="$(cmp_agent_fingerprint "$AGENT_CMD")"
HARNESS="$(cmp_harness_fingerprint)"

cmp_err "framework $FRAMEWORK (${CMP_FRAMEWORK_SHA:0:12}, version $CMP_FRAMEWORK_VERSION); runs $RUNS; scenarios:$SELECTED"
ROWS="$WORK/rows.tsv" SAVE="$WORK/save.tsv"; : > "$ROWS"; : > "$SAVE"
ERRORS=0 k=0
for id in $SELECTED; do
  sdir="$HERE/scenarios/$id"; done_runs=0; passes=0; errors=0; r=1
  while [ "$r" -le "$RUNS" ]; do
    cmp_err "[$id run $r/$RUNS] $(cmp_meta "$sdir" title)"
    k=$((k + 1))
    m="$(cmp_new_run "$WORK/runs" "$FIX" "$id-r$r" "w$k")" || { errors=$((errors + 1)); r=$((r + 1)); continue; }
    outcome="$(cmp_run_one "$sdir" "$m" "$AGENT_CMD")"
    case "$outcome" in
      pass) done_runs=$((done_runs + 1)); passes=$((passes + 1)) ;;
      fail) done_runs=$((done_runs + 1)) ;;
      *) errors=$((errors + 1)); outcome="error (left out of the counts; its cause is printed above)" ;;
    esac
    cmp_err "[$id run $r/$RUNS] $outcome"
    # A finished run's fixture goes now, so a later run's agent never finds an earlier run's outcome.
    [ "$KEEP" = true ] || rm -rf "$(cmp_root "$m")"
    r=$((r + 1))
  done
  printf '%s\t%s\t%s\t%s\n' "$id" "$done_runs" "$passes" "$FRAMEWORK" >> "$ROWS"
  # A scenario with a run that could not complete is printed but not saved: a partial count never
  # replaces a saved row. Re-run the scenario.
  if [ "$errors" -eq 0 ]; then tail -n 1 "$ROWS" >> "$SAVE"
  else ERRORS=$((ERRORS + errors)); cmp_err "$id: not saved ($errors run(s) could not complete)"; fi
done

printf 'scenario\truns\tpass\tframework\n'
cat "$ROWS"
if [ -s "$SAVE" ]; then
  saved="$(cmp_save_results "$RESULTS_DIR" "$FRAMEWORK" "$CMP_FRAMEWORK_SHA" "$CMP_FRAMEWORK_VERSION" "$FINGERPRINT" "$SAVE" "$HARNESS")" ||
    { cmp_err "could not save the results in $RESULTS_DIR"; exit 4; }
  cmp_err "saved: $saved"
fi

gate=0
if [ -n "$COMPARE" ]; then
  echo
  cmp_gate "$RESULTS_DIR" "$COMPARE" "$FRAMEWORK"; gate=$?
fi
if [ "$ERRORS" -gt 0 ]; then
  cmp_err "$ERRORS run(s) could not complete and were left out of the counts; the cause of each is printed above (--keep keeps the full logs); re-run those scenarios"
  exit 4
fi
[ "$gate" -eq 0 ] || exit 1
exit 0
