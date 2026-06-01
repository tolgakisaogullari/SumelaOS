#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# sync-mirrors.sh — keep verbatim IDE mirrors of .sumela/sumela-prompt.md in sync.
#
# Some IDE entrypoints must carry the prompt body VERBATIM (weak models skip
# "read the canonical file" pointers). List those files in .sumela/mirrors.conf
# (one repo-relative path per line). Each must contain a marker block:
#     <!-- SUMELA-MIRROR:BEGIN -->  ...  <!-- SUMELA-MIRROR:END -->
# Only the content BETWEEN the markers is rewritten; your IDE-specific wrapper
# outside the markers is preserved.
#
# Usage:
#   bash scripts/sync-mirrors.sh            # regenerate the marked block in each mirror
#   bash scripts/sync-mirrors.sh --check    # exit 1 if any mirror has drifted (CI/pre-commit)
#   bash scripts/sync-mirrors.sh --init     # scaffold any listed-but-missing mirror file
# Best-effort: no mirrors.conf / no entries / no python3 → exit 0 (nothing to do).
# -----------------------------------------------------------------------------
set -uo pipefail

MODE=sync
case "${1:-}" in
  --check) MODE=check ;;
  --init)  MODE=init ;;
  "")      ;;
  *) echo "usage: sync-mirrors.sh [--check|--init]" >&2; exit 2 ;;
esac

ROOT="$(pwd)"
while [ "$ROOT" != "/" ] && [ ! -d "$ROOT/.sumela" ]; do ROOT="$(dirname "$ROOT")"; done
[ -d "$ROOT/.sumela" ] || { echo "sync-mirrors: no .sumela/ found from $(pwd) upward."; exit 0; }

PROMPT="$ROOT/.sumela/sumela-prompt.md"
CONF="$ROOT/.sumela/mirrors.conf"
[ -f "$PROMPT" ] || { echo "sync-mirrors: $PROMPT missing — nothing to mirror."; exit 0; }
if [ ! -f "$CONF" ]; then
  [ "$MODE" = check ] && exit 0
  echo "sync-mirrors: no .sumela/mirrors.conf (copy .sumela/mirrors.conf.example) — nothing to do."
  exit 0
fi

mirrors=()
while IFS= read -r line || [ -n "$line" ]; do
  line="$(printf '%s' "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$line" ] && mirrors+=("$line")
done < "$CONF"

if [ ${#mirrors[@]} -eq 0 ]; then
  [ "$MODE" = check ] && exit 0
  echo "sync-mirrors: .sumela/mirrors.conf has no entries — nothing to do."
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "sync-mirrors: python3 not found — skipping ($MODE). Install python3 to enable mirror sync."
  exit 0
fi

python3 - "$MODE" "$ROOT" "$PROMPT" ${mirrors[@]+"${mirrors[@]}"} <<'PY'
import sys, os
mode, root, prompt_path = sys.argv[1], sys.argv[2], sys.argv[3]
mirrors = sys.argv[4:]
BEGIN, END = "SUMELA-MIRROR:BEGIN", "SUMELA-MIRROR:END"
BEGIN_LINE = "<!-- SUMELA-MIRROR:BEGIN — auto-generated from .sumela/sumela-prompt.md; do not edit between the markers. Run scripts/sync-mirrors.sh to regenerate. -->"
END_LINE = "<!-- SUMELA-MIRROR:END -->"

with open(prompt_path, encoding="utf-8") as f:
    prompt = f.read().rstrip("\n")
prompt_lines = prompt.split("\n")

def markers(lines):
    bi = ei = -1
    for i, l in enumerate(lines):
        if BEGIN in l and bi == -1:
            bi = i
        elif END in l and bi != -1 and ei == -1:
            ei = i
    return bi, ei

rc = 0
for rel in mirrors:
    norm = rel.replace("\\", "/")
    if os.path.isabs(rel) or norm.startswith("/") or ".." in norm.split("/"):
        print(f"  REFUSED {rel} (absolute or '..' path not allowed)"); rc = 1; continue
    path = os.path.join(root, rel)
    if mode == "init":
        if os.path.exists(path):
            print(f"  exists  {rel} (left as-is)"); continue
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, exist_ok=True)
        hdr = ("<!-- This file mirrors .sumela/sumela-prompt.md for an IDE that needs the prompt body\n"
               "     verbatim. Put any IDE-specific frontmatter/wrapper OUTSIDE the markers. -->\n\n")
        with open(path, "w", encoding="utf-8") as f:
            f.write(hdr + BEGIN_LINE + "\n" + prompt + "\n" + END_LINE + "\n")
        print(f"  created {rel}")
        continue

    if not os.path.exists(path):
        print(f"  MISSING {rel} (run: scripts/sync-mirrors.sh --init)"); rc = 1; continue

    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    bi, ei = markers(lines)
    if bi == -1 or ei == -1 or ei <= bi:
        print(f"  NO-MARKERS {rel} (add SUMELA-MIRROR:BEGIN/END, or run --init)"); rc = 1; continue

    inner = "\n".join(lines[bi + 1:ei]).rstrip("\n")
    if inner == prompt:
        print(f"  ok      {rel}")
    elif mode == "check":
        print(f"  DRIFT   {rel} (mirror block differs from sumela-prompt.md — run scripts/sync-mirrors.sh)"); rc = 1
    else:  # sync
        new = lines[:bi] + [BEGIN_LINE] + prompt_lines + [END_LINE] + lines[ei + 1:]
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(new).rstrip("\n") + "\n")
        print(f"  synced  {rel}")

sys.exit(rc)
PY
