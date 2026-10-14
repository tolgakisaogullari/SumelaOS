#!/usr/bin/env bash
# C6 cross-cutting AD — check. AD-02 routes every outbound HTTP call through HttpClient; session 1 wrote
# the spec and plan for a feature that adds such a call, session 2 (handoff pasted) implemented it.
# Pass: a new spec or plan cites AD-02, src/shop/shipping.py uses the client, and no new or changed
# Python file in src/ (other than http_client.py itself) calls a raw HTTP library.
# Usage: check.sh <meta-dir>. Exit 0 pass, 1 fail, 2 the check could not run.
set -uo pipefail
# shellcheck source=../../lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
m="$1"
cmp_need_session "$m" 2

docs=(); code=(); shipping=()
while IFS= read -r f; do if [ -n "$f" ]; then docs+=("$f"); fi; done <<EOF
$(cmp_changed "$m" docs/second-brain/artifacts | cmp_list_files '*.md')
EOF
while IFS= read -r f; do
  case "$f" in
    '') ;;
    */src/shop/http_client.py) ;;
    */src/shop/shipping.py) code+=("$f"); shipping+=("$f") ;;
    *) code+=("$f") ;;
  esac
done <<EOF
$(cmp_changed "$m" src | cmp_list_files '*.py')
EOF
RAW_HTTP_ERE='(^|[^A-Za-z0-9_])(import (requests|httpx|aiohttp|urllib3)|from (requests|httpx|aiohttp|urllib3)[ .]|urllib\.request|from urllib import request|http\.client|urlopen[[:space:]]*\()'
cites_ad()      { cmp_grep_any '(^|[^A-Za-z0-9])AD-0?2([^0-9]|$)' ${docs[@]+"${docs[@]}"}; }
uses_client()   { cmp_grep_any 'HttpClient|http_client|get_json' ${shipping[@]+"${shipping[@]}"}; }
no_raw_http()   { ! cmp_grep_any "$RAW_HTTP_ERE" ${code[@]+"${code[@]}"}; }

cmp_expect "a new spec or plan cites AD-02" cites_ad
cmp_expect "src/shop/shipping.py uses HttpClient" uses_client
cmp_expect "no new or changed code in src/ calls a raw HTTP library" no_raw_http
cmp_verdict
