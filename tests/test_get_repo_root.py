#!/usr/bin/env python3
"""Dependency-free unit test for qdrant-session-memory get_repo_root().

Regression guard for the silent ingestion bug: the legacy "three levels up"
returned the PLUGIN dir instead of the repo root in adopted projects, leaving
Qdrant wiki/code collections permanently empty. Run directly:

    python3 tests/test_get_repo_root.py

Exits non-zero on the first failed assertion. No pytest / third-party deps.
"""
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

# Path to the module under test, relative to this test file (tests/ -> repo root).
REPO = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO / ".sumela/memory-plugins/qdrant-session-memory/scripts/lib/memory_ingest.py"


def _load_module_at(file_path: Path):
    """Import memory_ingest.py as if it lived at `file_path` (fresh each time so
    __file__ reflects the simulated layout and the os.getenv read is re-evaluated)."""
    spec = importlib.util.spec_from_file_location("memory_ingest_under_test", file_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _plant_module(root: Path) -> Path:
    """Copy the real module into root/.sumela/memory-plugins/<plugin>/scripts/lib/."""
    dest = root / ".sumela/memory-plugins/qdrant-session-memory/scripts/lib"
    dest.mkdir(parents=True)
    target = dest / "memory_ingest.py"
    target.write_text(MODULE_PATH.read_text(encoding="utf-8"), encoding="utf-8")
    return target


def check(name, cond):
    if cond:
        print(f"  PASS  {name}")
    else:
        print(f"  FAIL  {name}")
        check.failed += 1
check.failed = 0


def main():
    os.environ.pop("SUMELA_REPO_ROOT", None)

    # 1. Vendored adoption layout with a top-level .sumela marker → repo root,
    #    NOT the plugin dir.
    with tempfile.TemporaryDirectory() as d:
        root = Path(d).resolve()
        target = _plant_module(root)
        mod = _load_module_at(target)
        got = mod.get_repo_root().resolve()
        check("vendored layout (.sumela marker) returns repo root", got == root)
        plugin_dir = root / ".sumela/memory-plugins/qdrant-session-memory"
        check("does NOT return the plugin dir", got != plugin_dir.resolve())

    # 2. Repo that uses .git as the marker (no extra .sumela above the plugin's).
    with tempfile.TemporaryDirectory() as d:
        root = Path(d).resolve()
        (root / ".git").mkdir()
        target = _plant_module(root)
        mod = _load_module_at(target)
        # .sumela exists at root too here; either marker resolves to the same root.
        check(".git marker resolves to repo root", mod.get_repo_root().resolve() == root)

    # 3. No marker anywhere → legacy three-levels-up fallback (plugin dir).
    with tempfile.TemporaryDirectory() as d:
        # Plant under a path with NO .git and NO .sumela above the lib dir by
        # building the nesting manually without the .sumela name as a marker dir.
        root = Path(d).resolve()
        dest = root / "vendor/qdrant/scripts/lib"
        dest.mkdir(parents=True)
        target = dest / "memory_ingest.py"
        target.write_text(MODULE_PATH.read_text(encoding="utf-8"), encoding="utf-8")
        mod = _load_module_at(target)
        expected = target.resolve().parent.parent.parent  # scripts/lib -> scripts -> qdrant
        check("no marker → legacy three-levels-up fallback", mod.get_repo_root().resolve() == expected)

    # 4. SUMELA_REPO_ROOT env override wins regardless of layout.
    with tempfile.TemporaryDirectory() as d:
        root = Path(d).resolve()
        override = root / "forced"
        override.mkdir()
        target = _plant_module(root)
        os.environ["SUMELA_REPO_ROOT"] = str(override)
        try:
            mod = _load_module_at(target)
            check("SUMELA_REPO_ROOT env override wins", mod.get_repo_root().resolve() == override.resolve())
        finally:
            os.environ.pop("SUMELA_REPO_ROOT", None)

    if check.failed:
        print(f"\n{check.failed} assertion(s) FAILED")
        sys.exit(1)
    print("\nAll get_repo_root assertions passed")


if __name__ == "__main__":
    main()
