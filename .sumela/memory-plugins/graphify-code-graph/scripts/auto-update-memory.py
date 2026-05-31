#!/usr/bin/env python3
"""
auto-update-memory.py — Automatic memory stack maintenance (v2.4-agnostic)

Usage:
    python auto-update-memory.py
    python auto-update-memory.py --project-root /path/to/repo --graph-dir graphify-out --wiki-path docs/second-brain/wiki

What it does:
    1. Runs `graphify update .` to rebuild the code graph.
    2. Syncs Graphify insights to Obsidian wiki (with noise filter).
    3. Verifies Qdrant is reachable and appends a status line to _LOG.md.
    4. Prints a structured status report for the agent to relay to the user.

This script is safe to run after every code-commit or at session end.

Environment:
    GRAPHIFY_OUT_DIR — graph output directory (default: graphify-out)
    WIKI_PATH        — wiki directory path (default: docs/second-brain/wiki)
    PROJECT_ROOT     — project root directory (default: auto-detected from script location)
    QDRANT_HOST      — Qdrant host (default: localhost)
    QDRANT_PORT      — Qdrant port (default: 6333)
"""
import subprocess
import sys
import os
import argparse
import datetime
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def print_report(summary_lines: list):
    print("\n" + "=" * 60)
    print("MEMORY UPDATE REPORT")
    print("=" * 60)
    for line in summary_lines:
        print(line)
    print("=" * 60 + "\n")


def report_success(graphify_ok: bool, sync_ok: bool, qdrant_ok: bool, log_warning: str | None = None):
    lines = [
        "Status: COMPLETE",
        f"1. Graphify code graph: {'OK' if graphify_ok else 'FAIL'}",
        f"2. Wiki sync (graphify -> Obsidian): {'OK' if sync_ok else 'FAIL'}",
        f"3. Qdrant health check: {'OK' if qdrant_ok else 'FAIL'}",
    ]
    if log_warning:
        lines.append(f"4. _LOG.md size: {log_warning}")
    lines.append("Action for agent: Relay this summary to the user.")
    print_report(lines)


def report_failure(stage: str, reason: str):
    print_report([
        "Status: FAILED",
        f"Stage: {stage}",
        f"Reason: {reason}",
        "Action for agent: Inform the user of the failure.",
    ])


def get_script_dir() -> Path:
    """Return the directory containing this script."""
    return Path(__file__).resolve().parent


def run_graphify(project_root: Path) -> bool:
    print("[1/4] Running graphify update...")
    result = subprocess.run(
        ["graphify", "update", "."],
        capture_output=True, text=True, cwd=str(project_root)
    )
    if result.returncode != 0:
        print("ERROR: graphify failed:", result.stderr)
        return False
    print("OK    graphify updated.")
    return True


def check_qdrant(host: str, port: int) -> bool:
    print("[3/4] Checking Qdrant health...")
    try:
        from qdrant_client import QdrantClient
        client = QdrantClient(host=host, port=int(port), check_compatibility=False)
        collections = client.get_collections().collections
        print(f"OK    Qdrant reachable. Collections: {len(collections)}")
        return True
    except ImportError:
        print("WARN  qdrant-client not installed, skipping Qdrant health check.")
        return False
    except Exception as e:
        print(f"WARN  Qdrant unreachable: {e}")
        return False


LOG_ROTATE_THRESHOLD = 800  # lines


def check_log_size(wiki_path: Path) -> str | None:
    """Return a warning string if _LOG.md exceeds threshold; else None."""
    log_path = wiki_path / "_LOG.md"
    if not log_path.exists():
        return None
    with open(log_path, "r", encoding="utf-8") as f:
        n = sum(1 for _ in f)
    if n >= LOG_ROTATE_THRESHOLD:
        return (
            f"{n} lines (threshold {LOG_ROTATE_THRESHOLD}). "
            f"Consider archiving entries older than 6 months to wiki/archive/_LOG-YYYY.md "
            f"and adding a `migration` log entry. Manual review required — auto-rotation disabled."
        )
    return None


def log_status(wiki_path: Path, graphify_ok: bool, sync_ok: bool, qdrant_ok: bool):
    print("[4/4] Logging status...")
    log_path = wiki_path / "_LOG.md"
    date_str = datetime.datetime.now().strftime("%Y-%m-%d")
    line = (
        f"\n## [{date_str}] lint | Auto memory update: "
        f"graphify={'OK' if graphify_ok else 'FAIL'}, "
        f"wiki_sync={'OK' if sync_ok else 'FAIL'}, "
        f"qdrant={'OK' if qdrant_ok else 'FAIL'}\n"
    )
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(line)
    print("OK    Logged.")


def sync_graphify_wiki(script_dir: Path, project_root: Path, graph_dir: str, wiki_path: str) -> bool:
    print("[2/4] Syncing Graphify insights to Obsidian wiki...")
    sync_script = script_dir / "sync-graphify-to-obsidian.py"
    if not sync_script.exists():
        print("WARN  sync-graphify-to-obsidian.py not found, skipping wiki sync.")
        return False
    result = subprocess.run(
        [sys.executable, str(sync_script), "--graph-dir", graph_dir, "--wiki-path", wiki_path],
        capture_output=True, text=True, cwd=str(project_root)
    )
    if result.returncode != 0:
        print("WARN  Graphify wiki sync failed:", result.stderr)
        return False
    print("OK    Graphify wiki synced.")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Automatic memory stack maintenance."
    )
    parser.add_argument("--project-root", default=os.getenv("PROJECT_ROOT"),
                        help="Project root directory (default: auto-detected)")
    parser.add_argument("--graph-dir", default=os.getenv("GRAPHIFY_OUT_DIR", "graphify-out"),
                        help="Graph output directory (default: graphify-out or GRAPHIFY_OUT_DIR env)")
    parser.add_argument("--wiki-path", default=os.getenv("WIKI_PATH", "docs/second-brain/wiki"),
                        help="Wiki directory path (default: docs/second-brain/wiki or WIKI_PATH env)")
    parser.add_argument("--qdrant-host", default=os.getenv("QDRANT_HOST", "localhost"),
                        help="Qdrant host (default: localhost or QDRANT_HOST env)")
    parser.add_argument("--qdrant-port", type=int, default=int(os.getenv("QDRANT_PORT", "6333")),
                        help="Qdrant port (default: 6333 or QDRANT_PORT env)")
    args = parser.parse_args()

    script_dir = get_script_dir()

    if args.project_root:
        project_root = Path(args.project_root)
    else:
        # Default: two levels up from scripts/ directory (repo root convention)
        project_root = script_dir.parent.parent

    if not project_root.exists():
        report_failure("Config", f"Project root not found: {project_root}")
        sys.exit(1)

    wiki_path = project_root / args.wiki_path

    g_ok = run_graphify(project_root)
    s_ok = sync_graphify_wiki(script_dir, project_root, args.graph_dir, args.wiki_path)
    q_ok = check_qdrant(args.qdrant_host, args.qdrant_port)

    log_status(wiki_path, g_ok, s_ok, q_ok)
    log_warning = check_log_size(wiki_path)
    report_success(g_ok, s_ok, q_ok, log_warning)

    if not g_ok or not s_ok or not q_ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
