#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# tests/eval/compliance/stub-agent.sh — a scripted stand-in for an agent CLI. No model is called.
#
# The harness's self-test (tests/test_compliance_harness.sh) and free dry runs use it as the agent
# command:
#   run.sh --framework HEAD --runs 1 --state-dir <tmp> \
#          --agent-cmd 'bash {HARNESS}/stub-agent.sh {SCENARIO_DIR} {SESSION} {DIR} {PROMPT}'
# For the session it is called for it runs a canned outcome from <scenario-dir>/canned.sh,
# canned_<outcome>_s<n>, else canned_s<n>, in <dir>, and prints a Claude Code stream-json transcript of
# what it did, so the real transcript path is exercised. The scenario and the session come as
# arguments: the harness exports nothing of its own to an agent. The outcome: this scenario's entry in
# CMP_STUB_OUTCOMES ("C1=golden C2=counter ..."), else CMP_STUB_OUTCOME, else golden. Outcomes named
# golden* must pass their scenario's check, counter* must fail it (each scenario lists its outcomes in
# CANNED_OUTCOMES).
# -----------------------------------------------------------------------------
set -uo pipefail

[ $# -ge 3 ] || { echo "usage: stub-agent.sh <scenario-dir> <session> <dir> [<prompt>]" >&2; exit 2; }
STUB_SCENARIO_DIR="$1"; STUB_SESSION="$2"; dir="$3"
STUB_PROMPT="${4:-}"
cd "$dir" || exit 1

STUB_N=0
STUB_FINAL=""

stub_json() {  # stdin -> one JSON string literal; UTF-8 bytes pass through unchanged
  LC_ALL=C awk 'BEGIN { for (i = 1; i < 32; i++) code[sprintf("%c", i)] = i }
    { s = (NR > 1) ? s "\n" $0 : $0 }
    END { out = ""; n = length(s)
          for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            if (c == "\\") out = out "\\\\"
            else if (c == "\"") out = out "\\\""
            else if (c == "\n") out = out "\\n"
            else if (c == "\t") out = out "\\t"
            else if (c == "\r") out = out "\\r"
            else if (c in code) out = out sprintf("\\u%04x", code[c])
            else out = out c
          }
          printf "\"%s\"", out }'
}
stub_emit() { printf '%s\n' "$1"; }

stub_say() {  # stub_say <text>: an assistant text block
  stub_emit "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":$(printf '%s' "$1" | stub_json)}]},\"parent_tool_use_id\":null}"
}

# stub_tool <name> <input-json> <result-text> [<parent-tool-use-id>]: a tool call and its result. The
# result alternates between the two shapes Claude Code emits (a string, a list of text blocks).
stub_tool() {
  local id parent="null" content
  STUB_N=$((STUB_N + 1)); id="toolu_stub_$STUB_N"
  [ -z "${4:-}" ] || parent="\"$4\""
  stub_emit "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"$id\",\"name\":\"$1\",\"input\":$2}]},\"parent_tool_use_id\":$parent}"
  if [ $((STUB_N % 2)) -eq 0 ]; then content="$(printf '%s' "$3" | stub_json)"
  else content="[{\"type\":\"text\",\"text\":$(printf '%s' "$3" | stub_json)}]"; fi
  stub_emit "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"$id\",\"content\":$content}]},\"parent_tool_use_id\":$parent}"
}

stub_shell() {  # stub_shell <command> [<parent-id>]: run it here and report its output
  local out; out="$(bash -c "$1" 2>&1)"
  stub_tool Bash "{\"command\":$(printf '%s' "$1" | stub_json)}" "$out" "${2:-}"
}
stub_read() {  # stub_read <relpath> [<parent-id>]
  stub_tool Read "{\"file_path\":$(printf '%s' "$PWD/$1" | stub_json)}" "$(cat "$1" 2>&1)" "${2:-}"
}
stub_write() {  # stub_write <relpath> < content
  local content; content="$(cat)"
  mkdir -p "$(dirname "$1")" && printf '%s\n' "$content" > "$1"
  stub_tool Write "{\"file_path\":$(printf '%s' "$PWD/$1" | stub_json),\"content\":$(printf '%s' "$content" | stub_json)}" \
    "File created successfully at: $PWD/$1"
}
stub_edit() {  # stub_edit <relpath> <old> <new>: replace the first occurrence, literally
  STUB_OLD="$2" STUB_NEW="$3" LC_ALL=C awk 'BEGIN { RS = "\001"; o = ENVIRON["STUB_OLD"]; n = ENVIRON["STUB_NEW"] }
    { i = index($0, o); if (i) $0 = substr($0, 1, i - 1) n substr($0, i + length(o)); printf "%s", $0 }' "$1" > "$1.stub-tmp" &&
    mv -f "$1.stub-tmp" "$1"
  stub_tool Edit "{\"file_path\":$(printf '%s' "$PWD/$1" | stub_json),\"old_string\":$(printf '%s' "$2" | stub_json),\"new_string\":$(printf '%s' "$3" | stub_json)}" \
    "The file $PWD/$1 has been updated."
}
stub_ask() {  # stub_ask <question>: the question tool, unanswered in a headless session
  stub_tool AskUserQuestion "{\"questions\":[{\"question\":$(printf '%s' "$1" | stub_json),\"header\":\"Decision\",\"multiSelect\":false,\"options\":[{\"label\":\"Yes\",\"description\":\"\"},{\"label\":\"No\",\"description\":\"\"}]}]}" \
    "Error: no answer in a non-interactive session"
}
# stub_dispatch <prompt> [<command the subagent runs>] [<text the subagent says>]: a subagent call (Task
# tool); the subagent's own events carry its parent_tool_use_id, as Claude Code reports them.
stub_dispatch() {
  local parent
  STUB_N=$((STUB_N + 1)); parent="toolu_stub_$STUB_N"
  stub_emit "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"$parent\",\"name\":\"Task\",\"input\":{\"description\":\"Implement one plan task\",\"subagent_type\":\"general-purpose\",\"prompt\":$(printf '%s' "$1" | stub_json)}}]},\"parent_tool_use_id\":null}"
  [ -z "${2:-}" ] || stub_shell "$2" "$parent"
  [ -z "${3:-}" ] || stub_emit "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":$(printf '%s' "$3" | stub_json)}]},\"parent_tool_use_id\":\"$parent\"}"
  stub_emit "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"$parent\",\"content\":[{\"type\":\"text\",\"text\":\"DONE\"}]}]},\"parent_tool_use_id\":null}"
}
stub_final() { STUB_FINAL="$1"; }   # the session's last reply

stub_handoff() {  # stub_handoff <continue point> [<task ground rules>]: a last reply carrying a handoff prompt
  printf 'Context saved; the session summary is written. Handoff prompt for the next session:\n\n````\n@.sumela/sumela-prompt.md\n\n## Session Handoff — 2026-10-14\n\n### 🔴 Continue Point\n%s\n\n### Task Ground Rules — in force for this task\n%s\n````\n\nYou can send this prompt as the first message in a new session.' \
    "$1" "${2:-None.}"
}

scenario="$(basename "$STUB_SCENARIO_DIR")"
outcome=""
for pair in ${CMP_STUB_OUTCOMES:-}; do
  case "$pair" in "$scenario="*) outcome="${pair#*=}" ;; esac
done
[ -n "$outcome" ] || outcome="${CMP_STUB_OUTCOME:-golden}"

stub_emit "{\"type\":\"system\",\"subtype\":\"init\",\"cwd\":$(printf '%s' "$PWD" | stub_json),\"model\":\"stub\",\"tools\":[\"Bash\",\"Read\",\"Edit\",\"Write\",\"Task\",\"AskUserQuestion\"]}"
if [ -f "$STUB_SCENARIO_DIR/canned.sh" ]; then
  # shellcheck source=/dev/null
  . "$STUB_SCENARIO_DIR/canned.sh"
  fn="canned_${outcome}_s${STUB_SESSION}"
  declare -F "$fn" > /dev/null || fn="canned_s${STUB_SESSION}"
  if declare -F "$fn" > /dev/null; then "$fn"; fi
fi
[ -n "$STUB_FINAL" ] || STUB_FINAL="(stub: nothing to do in this session)"
stub_say "$STUB_FINAL"
stub_emit "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":$STUB_N,\"result\":$(printf '%s' "$STUB_FINAL" | stub_json)}"
