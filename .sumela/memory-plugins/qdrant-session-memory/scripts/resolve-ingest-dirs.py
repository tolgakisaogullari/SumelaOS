#!/usr/bin/env python3
"""resolve-ingest-dirs.py — print the validated EXTRA documentation ingest dirs.

Single source of truth for the bash git-hook and the PowerShell/bash setup+status
scripts: they shell out to this instead of re-implementing config resolution and
path validation (which would inevitably drift). Prints one repo-relative path per
line (POSIX separators), nothing if none are configured. Always exits 0 — resolution
is best-effort and must never block a pull.

Config + validation rules live in lib.memory_ingest.get_extra_ingest_dirs.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.memory_ingest import get_repo_root, get_extra_ingest_dirs

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def main() -> int:
    try:
        root = get_repo_root()
        for d in get_extra_ingest_dirs(root):
            print(d.relative_to(root).as_posix())
    except Exception as e:  # never fail the caller (hook/setup/status)
        print(f"[warn] resolve-ingest-dirs failed: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
