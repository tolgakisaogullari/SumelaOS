#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# sumela-token-report.sh — run scripts/sumela-token-report.py with the first Python >= 3.9.
#
# The token report (SumelaOS v0.20.0+) is an optional tool: Python 3.9 or later, the standard
# library only, always run isolated (-I). It runs on demand only, never from a git hook, the
# bootstrap or CI. It reads this install's local Claude Code transcripts, makes no network call,
# writes no file and prints aggregates to stdout. The options and the privacy contract:
#   bash scripts/sumela-token-report.sh --help
#   (the header of scripts/sumela-token-report.py documents every section and metric)
#
# Python is probed in order: python3, py -3, python; each must report 3.9 or later. PYTHONUTF8=1
# is exported for child processes, and -X utf8 is passed (python -I ignores PYTHON* variables).
#
# Exit codes: the report's own (0 printed; 2 degraded: no transcripts, another IDE or no session
# in the window, with a --static hint; 1 could not run); 1 with
# "optional tool: needs Python >=3.9" when no suitable Python is on PATH.
# -----------------------------------------------------------------------------
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
script="$here/sumela-token-report.py"
if [ ! -f "$script" ]; then
  echo "sumela-token-report: sumela-token-report.py is missing next to this wrapper" >&2
  exit 1
fi
export PYTHONUTF8=1

# probe <python command...>: true when it runs and is Python 3.9 or later. Its own output is not
# the report's: a Microsoft Store "python3" stub, for one, prints an install hint and exits 9009.
probe() { "$@" -I -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; }

if command -v python3 >/dev/null 2>&1 && probe python3; then
  exec python3 -I -X utf8 "$script" "$@"
elif command -v py >/dev/null 2>&1 && probe py -3; then
  exec py -3 -I -X utf8 "$script" "$@"
elif command -v python >/dev/null 2>&1 && probe python; then
  exec python -I -X utf8 "$script" "$@"
fi
echo "sumela-token-report: optional tool: needs Python >=3.9 (python3, py -3 or python on PATH)" >&2
exit 1
