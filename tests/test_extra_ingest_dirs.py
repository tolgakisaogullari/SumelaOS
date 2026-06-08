#!/usr/bin/env python3
"""Dependency-free unit test for get_extra_ingest_dirs() — the single source of
truth for the "extra documentation ingest paths" feature (consumed by the Python
ingest, the bash git-hook, and the PowerShell/bash setup+status scripts via
resolve-ingest-dirs.py). Run directly:

    python3 tests/test_extra_ingest_dirs.py

Exits non-zero on the first failed assertion. No pytest / third-party deps.
Covers config precedence (env > conf > empty), path validation (reject absolute /
~ / .. / glob / drive-letter / empty-segment / symlink-escape), skip-missing, and
order-stable dedupe.
"""
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO / ".sumela/memory-plugins/qdrant-session-memory/scripts/lib/memory_ingest.py"

_spec = importlib.util.spec_from_file_location("memory_ingest_eid", MODULE_PATH)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
get_extra_ingest_dirs = _mod.get_extra_ingest_dirs


def check(name, cond):
    if cond:
        print(f"  PASS  {name}")
    else:
        print(f"  FAIL  {name}")
        check.failed += 1
check.failed = 0


def rel(root, dirs):
    return sorted(d.relative_to(Path(root).resolve()).as_posix() for d in dirs)


def main():
    os.environ.pop("EXTRA_INGEST_DIRS", None)

    with tempfile.TemporaryDirectory() as d:
        root = Path(d).resolve()
        (root / ".sumela").mkdir()
        (root / "docs" / "arch").mkdir(parents=True)
        (root / "docs" / "adr").mkdir(parents=True)
        (root / "outside_target").mkdir()
        conf = root / ".sumela" / "ingest.conf"

        # 1. Empty default: no conf, no env → []
        check("empty default → no dirs", get_extra_ingest_dirs(root) == [])

        # 2. Conf file: valid dirs, comments + blanks ignored
        conf.write_text("docs/arch\n# a comment\n\n  docs/adr  \n", encoding="utf-8")
        check("conf returns both valid dirs (trimmed, comments skipped)",
              rel(root, get_extra_ingest_dirs(root)) == ["docs/adr", "docs/arch"])

        # 3. Env overrides conf; colon + comma both split
        os.environ["EXTRA_INGEST_DIRS"] = "docs/arch:docs/adr"
        check("env overrides conf (colon-split)",
              rel(root, get_extra_ingest_dirs(root)) == ["docs/adr", "docs/arch"])
        os.environ["EXTRA_INGEST_DIRS"] = "docs/arch,docs/adr"
        check("env comma-split",
              rel(root, get_extra_ingest_dirs(root)) == ["docs/adr", "docs/arch"])

        # 4. Rejections: absolute, ~, .., glob, drive-letter, empty-segment, leading-dash
        os.environ["EXTRA_INGEST_DIRS"] = (
            "/etc:~/x:docs/../../outside_target:docs/*:C:/x:docs//arch:-rf:docs/arch"
        )
        got = rel(root, get_extra_ingest_dirs(root))
        check("all hostile entries rejected, only docs/arch survives", got == ["docs/arch"])

        # 5. Missing dir skipped (with warning), existing kept
        os.environ["EXTRA_INGEST_DIRS"] = "docs/arch,docs/nope"
        check("missing dir skipped, existing kept",
              rel(root, get_extra_ingest_dirs(root)) == ["docs/arch"])

        # 6. Dedupe + order-stable
        os.environ["EXTRA_INGEST_DIRS"] = "docs/adr,docs/arch,docs/adr"
        out = get_extra_ingest_dirs(root)
        check("dedupe + order-stable (first-seen)",
              [p.relative_to(root).as_posix() for p in out] == ["docs/adr", "docs/arch"])

        # 7. Symlink dir whose target escapes the repo → rejected
        link = root / "escape_link"
        try:
            link.symlink_to(root.parent / "outside_target")  # points outside repo
            made_link = True
        except (OSError, NotImplementedError):
            made_link = False
        if made_link:
            os.environ["EXTRA_INGEST_DIRS"] = "escape_link"
            check("symlinked dir escaping repo root → rejected", get_extra_ingest_dirs(root) == [])
        else:
            print("  SKIP  symlink-escape (symlinks unsupported here)")

        # 8. A path resolving to repo root itself → rejected
        os.environ["EXTRA_INGEST_DIRS"] = "docs/.."
        check("path resolving to repo root → rejected", get_extra_ingest_dirs(root) == [])

    os.environ.pop("EXTRA_INGEST_DIRS", None)

    if check.failed:
        print(f"\n{check.failed} assertion(s) FAILED")
        sys.exit(1)
    print("\nAll get_extra_ingest_dirs assertions passed")


if __name__ == "__main__":
    main()
