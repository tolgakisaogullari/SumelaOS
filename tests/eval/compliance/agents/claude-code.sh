#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/eval/compliance/agents/claude-code.sh — one headless Claude Code session for the agent-compliance
# harness [RQ-13]. Source-only, maintainer-run; bash 3.2 compatible.
#
#   run.sh ... --agent-cmd 'bash {HARNESS}/agents/claude-code.sh --model <pinned model id> {DIR} {PROMPT}'
#
# Usage: claude-code.sh --model <id> [--max-budget-usd <usd>] [--effort <level>] [--sandbox]
#                       [--allow-unfenced-reads] [--] <dir> <prompt>
#
# It runs `claude -p` in <dir> with an argument list built here, one array element per argument (a
# command string spread over lines would end at the first line break). What each part is for:
#   --model                         the pinned model: the baseline and the candidate must run the same one
#   --output-format stream-json --verbose, --forward-subagent-text
#                                   the transcript the harness reads, subagents' messages marked as theirs
#   --permission-mode dontAsk       nothing prompts; a call that no rule below allows is denied
#   --allowedTools                  edits under <dir>; git; the framework's own scripts (bash .sumela/...,
#                                   bash scripts/...); python3 -m unittest; skills
#   --disallowedTools Read(~/**)    no reads under your home directory by the file tools or by the shell
#                                   commands Claude Code recognizes (cat, head, tail, sed, ...)
#   --settings                      permissions.blockReadsOutsideWorkingDirectories: the file tools refuse
#                                   paths outside <dir> (Claude Code 2.1.257 or later); with --sandbox
#                                   also Claude Code's OS-level sandbox for shell commands, strict, which
#                                   may write only to <dir>, the sandbox's temporary directory, the
#                                   fixture's origin and XDG_STATE_HOME
#   --setting-sources project,local your user settings, hooks and plugins stay out
#   --strict-mcp-config             no MCP servers
#   --no-session-persistence        no session transcript under ~/.claude/projects; auto memory is off too
#   --max-budget-usd                the per-session cost cap (default 3)
# Its environment: the harness's CMP_* variables removed; auto memory and background auto-updates off
# (a CLI that updates itself mid-evaluation changes what is compared); credentials scrubbed from the
# commands Claude Code starts.
#
# What stays open (README.md, "What the agent can reach"): a Bash rule is a command prefix, not a path,
# so `git -C <elsewhere>` and a git alias pass `Bash(git *)`, and code the agent writes and then runs
# (tests, hooks, the wiki tool) reaches whatever your account can, unless --sandbox, a container, a
# virtual machine or a throwaway user fences it.
#
# Exit codes: 2 usage; 3 refused (claude not on PATH, <dir> not a directory, <dir> inside your home
# directory, Claude Code older than 2.1.257 without --allow-unfenced-reads); anything else is Claude
# Code's own exit code.
# -----------------------------------------------------------------------------
set -uo pipefail

FENCE_MIN=2.1.257

usage() { LC_ALL=C sed -n '3,/^# ------/p' "${BASH_SOURCE[0]}" | LC_ALL=C sed -e '$d' -e 's/^# \{0,1\}//'; }
die() { printf 'claude-code.sh: %s\n' "$2" >&2; exit "$1"; }
version_ge() {  # version_ge <a> <b>: 0 when a >= b (numeric major.minor.patch)
  LC_ALL=C awk -v a="$1" -v b="$2" 'BEGIN { na = split(a, x, "."); nb = split(b, y, ".")
    for (i = 1; i <= 3; i++) { p = (i <= na) ? x[i] + 0 : 0; q = (i <= nb) ? y[i] + 0 : 0; if (p != q) exit (p > q ? 0 : 1) }
    exit 0 }'
}
json_str() { printf '"%s"' "$(printf '%s' "$1" | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }

MODEL="" BUDGET=3 EFFORT="" SANDBOX=false UNFENCED=false
while [ $# -gt 0 ]; do
  case "$1" in
    --model)          [ $# -ge 2 ] || die 2 "--model needs a value"; MODEL="$2"; shift ;;
    --max-budget-usd) [ $# -ge 2 ] || die 2 "--max-budget-usd needs a value"; BUDGET="$2"; shift ;;
    --effort)         [ $# -ge 2 ] || die 2 "--effort needs a value"; EFFORT="$2"; shift ;;
    --sandbox)        SANDBOX=true ;;
    --allow-unfenced-reads) UNFENCED=true ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; break ;;
    -*)               die 2 "unknown option: $1 (see --help)" ;;
    *)                break ;;
  esac
  shift
done
[ $# -eq 2 ] || die 2 "usage: claude-code.sh --model <id> [options] [--] <dir> <prompt> (see --help)"
[ -n "$MODEL" ] || die 2 "--model is required: pin the model, so the baseline and the candidate run the same one"
case "$BUDGET" in ''|*[!0-9.]*|*.*.*) die 2 "--max-budget-usd must be a number of US dollars" ;; esac
DIR="$1" PROMPT="$2"
[ -n "$PROMPT" ] || die 2 "the prompt is empty"

command -v claude > /dev/null 2>&1 || die 3 "claude (Claude Code) is not on PATH"
DIR_P="$(cd "$DIR" 2> /dev/null && pwd -P)" && [ -n "$DIR_P" ] || die 3 "not a directory: $DIR"
HOME_P="$(cd "${HOME:-/}" 2> /dev/null && pwd -P)" || HOME_P="${HOME:-/}"
[ "$HOME_P" != / ] || die 3 "HOME is /: the read fence on your home directory would cover everything"
case "$DIR_P/" in "$HOME_P"/*)
  die 3 "$DIR_P is inside your home directory, whose reads this wrapper denies: set TMPDIR outside $HOME_P" ;;
esac

# Claude Code's file tools stay inside <dir> only from 2.1.257 on; older versions are refused unless asked.
VERSION="$(claude --version | LC_ALL=C sed -n 's/^[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1)"
FENCE=false
if [ -n "$VERSION" ] && version_ge "$VERSION" "$FENCE_MIN"; then FENCE=true
elif [ "$UNFENCED" != true ]; then
  die 3 "Claude Code ${VERSION:-of an unknown version} cannot keep its file tools inside the session's checkout (permissions.blockReadsOutsideWorkingDirectories needs $FENCE_MIN or later): update Claude Code, or pass --allow-unfenced-reads to run with only your home directory fenced"
fi

# The main checkout: a session in a linked worktree may call the framework's tools by the main checkout's path.
MAIN_P="$(git -C "$DIR_P" rev-parse --path-format=absolute --git-common-dir 2> /dev/null)" &&
  MAIN_P="$(cd "$(dirname "$MAIN_P")" 2> /dev/null && pwd -P)" && [ -n "$MAIN_P" ] || MAIN_P="$DIR_P"

allow=("Edit(/$DIR_P/**)" "Bash(git *)" "Bash(bash .sumela/*)" "Bash(bash scripts/*)"
       "Bash(python3 -m unittest *)" "Skill")
for root in "$DIR_P" "$MAIN_P"; do
  allow+=("Bash(bash $root/.sumela/*)" "Bash(bash \"$root/.sumela/*)")
  [ "$MAIN_P" != "$DIR_P" ] || break
done

settings=""
if [ "$FENCE" = true ]; then settings='"permissions":{"blockReadsOutsideWorkingDirectories":true}'; fi
if [ "$SANDBOX" = true ]; then
  writes=""
  origin="$(git -C "$DIR_P" remote get-url origin 2> /dev/null)" || origin=""
  for w in "${XDG_STATE_HOME:-}" "$origin"; do
    [ -n "$w" ] && [ -d "$w" ] || continue
    w="$(cd "$w" && pwd -P)" || continue
    writes="${writes:+$writes,}$(json_str "$w")"
  done
  settings="${settings:+$settings,}\"sandbox\":{\"enabled\":true,\"failIfUnavailable\":true,\"allowUnsandboxedCommands\":false,\"filesystem\":{\"allowWrite\":[$writes]}}"
fi

extra=()
[ -z "$EFFORT" ] || extra+=(--effort "$EFFORT")
[ -z "$settings" ] || extra+=(--settings "{$settings}")

for v in $(env | LC_ALL=C sed -n 's/^\(CMP_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 DISABLE_AUTOUPDATER=1 CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1

cd "$DIR_P" || die 3 "cannot enter $DIR_P"
exec claude -p --model "$MODEL" --output-format stream-json --verbose --forward-subagent-text \
  --permission-mode dontAsk --setting-sources project,local --strict-mcp-config --no-session-persistence \
  --max-budget-usd "$BUDGET" ${extra[@]+"${extra[@]}"} \
  --disallowedTools "Read(~/**)" --allowedTools "${allow[@]}" -- "$PROMPT"
