#!/usr/bin/env bash
# C2 superseded decision — check. Session 1 decided CSV, session 2 replaced it with JSON Lines, and
# session 3, with no handoff pasted, implemented the export "in the format decided for this task".
# Pass: the new code in src/ defines export_orders and writes JSON, and none of it uses the csv module.
# Usage: check.sh <meta-dir>. Exit 0 pass, 1 fail, 2 the check could not run.
set -uo pipefail
# shellcheck source=../../lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
m="$1"
cmp_need_session "$m" 3

files=()
while IFS= read -r f; do if [ -n "$f" ]; then files+=("$f"); fi; done <<EOF
$(cmp_changed "$m" src | cmp_list_files '*.py')
EOF
JSON_ERE='(^|[^A-Za-z0-9_])(import json|from json import|json\.dumps?\()'
CSV_ERE='(^|[^A-Za-z0-9_])(import csv|from csv import|csv\.(writer|DictWriter|reader|DictReader)\()'
defines_export() { cmp_grep_any 'def export_orders[[:space:]]*\(' ${files[@]+"${files[@]}"}; }
uses_json()      { cmp_grep_any "$JSON_ERE" ${files[@]+"${files[@]}"}; }
no_csv()         { ! cmp_grep_any "$CSV_ERE" ${files[@]+"${files[@]}"}; }

cmp_expect "export_orders is implemented in src/" defines_export
cmp_expect "the export writes JSON (the decision of session 2)" uses_json
cmp_expect "no new code in src/ writes the superseded CSV format" no_csv
cmp_verdict
