#!/usr/bin/env python3
"""
sync-graphify-to-obsidian.py — Graphify to Wiki Sync (Smart) (v2.1-agnostic)

Usage:
    python sync-graphify-to-obsidian.py
    python sync-graphify-to-obsidian.py --graph-dir graphify-out --wiki-path docs/second-brain/wiki

What it does:
    1. Parses graphify-out/GRAPH_REPORT.md
    2. Extracts: God Nodes, Surprising Connections, Top Communities
    3. Generates ONE synthesis page: wiki/graphify-insights.md
    4. Updates _SEARCH_INDEX.md and _INDEX.md with a single row
    5. Cleans up old community-* pages if they exist
    6. Prints a structured status report for the agent to relay to the user.

This script is idempotent and designed to stay lightweight.

Environment:
    GRAPHIFY_OUT_DIR — graph output directory (default: graphify-out)
    WIKI_PATH        — wiki directory path (default: docs/second-brain/wiki)
"""
import os
import sys
import re
import argparse
from datetime import datetime
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def print_report(summary_lines: list):
    print("\n" + "=" * 60)
    print("GRAPHIFY WIKI SYNC REPORT")
    print("=" * 60)
    for line in summary_lines:
        print(line)
    print("=" * 60 + "\n")


def report_success(stats: dict, god_nodes: int, surprising: int, communities: int):
    print_report([
        "Status: SUCCESS",
        f"Corpus: {stats.get('nodes', '?')} nodes, {stats.get('edges', '?')} edges, {stats.get('communities', '?')} communities",
        f"God nodes extracted: {god_nodes}",
        f"Surprising connections found: {surprising}",
        f"Top communities documented: {communities}",
        "Files updated: wiki/graphify-insights.md, _SEARCH_INDEX.md, _INDEX.md",
        "Action for agent: Relay this summary to the user.",
    ])


def report_failure(stage: str, reason: str):
    print_report([
        "Status: FAILED",
        f"Stage: {stage}",
        f"Reason: {reason}",
        "Action for agent: Inform the user of the failure.",
    ])


def _is_noise_connection(first_line: str, files_line: str) -> bool:
    """Filter out low-signal surprising connections.

    Rules:
      1. Skip if both source files contain test markers (test-to-test).
      2. Skip if source is a method stub (label starts with '.') AND
         target is a test function (label starts with 'test_' OR file path
         contains 'tests/' or 'Tests.cs').
    """
    test_markers = ("tests/", "Tests.cs")
    test_matches = sum(1 for m in test_markers if m in files_line)
    if test_matches >= 2:
        return True

    labels = re.findall(r"`([^`]+)`", first_line)
    if len(labels) >= 2:
        source_label = labels[0]
        target_label = labels[1]
        if source_label.startswith(".") and (
            target_label.startswith("test_")
            or "tests/" in files_line
            or "Tests.cs" in files_line
        ):
            return True

    return False


def parse_graph_report(path: Path) -> dict:
    """Extract key sections from GRAPH_REPORT.md."""
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    data = {
        "god_nodes": [],
        "surprising_connections": [],
        "top_communities": [],
        "stats": {},
    }

    m = re.search(r"(\d+) nodes . (\d+) edges . (\d+) communities", text)
    if m:
        data["stats"] = {"nodes": m.group(1), "edges": m.group(2), "communities": m.group(3)}

    god_section = re.search(
        r"## God Nodes \(most connected.*?\n(.*?)(?:\n## |$)", text, re.DOTALL
    )
    if god_section:
        for line in god_section.group(1).strip().splitlines():
            m = re.search(r"`([^`]+)` - (\d+) edges", line)
            if m:
                data["god_nodes"].append((m.group(1), int(m.group(2))))

    surprise_section = re.search(
        r"## Surprising Connections \(you probably didn't know these\)\n(.*?)(?:\n## |$)", text, re.DOTALL
    )
    if surprise_section:
        raw = surprise_section.group(1).strip()
        blocks = re.split(r"\n(?=- `)", raw)
        for block in blocks:
            lines = block.strip().splitlines()
            if not lines:
                continue
            first = lines[0]
            files = lines[1] if len(lines) > 1 else ""
            if not _is_noise_connection(first, files):
                data["surprising_connections"].append((first, files))

    comm_blocks = re.findall(
        r"### Community (\d+) - \"([^\"]+)\"\nCohesion: ([\d.]+)\nNodes \((\d+)\): ([^\n]+)",
        text,
    )
    communities = []
    for cid, name, cohesion, count, nodes in comm_blocks:
        communities.append((int(cid), name, float(cohesion), int(count), nodes))
    communities.sort(key=lambda x: x[3], reverse=True)
    data["top_communities"] = communities[:15]

    return data


def generate_insights_page(data: dict, graph_dir: str) -> str:
    today = datetime.now().strftime("%Y-%m-%d")
    stats = data["stats"]

    god_section = "\n".join(
        [f"| `{name}` | {degree} |" for name, degree in data["god_nodes"]]
    ) or "| _No god nodes extracted_ | |"

    surprise_section = "\n".join(
        [f"- {line.lstrip('- ').strip()}\n  {files}" for line, files in data["surprising_connections"]]
    ) or "- _No surprising connections detected._"

    comm_section = "\n".join(
        [
            f"| Community {cid} — {name} | {count} nodes | {cohesion} | `{nodes[:60]}...` |"
            for cid, name, cohesion, count, nodes in data["top_communities"]
        ]
    ) or "| _No communities extracted_ | | | |"

    return f"""---
type: concept
tags: [graphify, structural-analysis, auto-generated, code-graph]
date_created: {today}
date_updated: {today}
sources_referenced: 1
status: active
---

# Graphify Structural Insights

> Auto-generated from `{graph_dir}/GRAPH_REPORT.md`. Do not edit manually — overwritten on every sync.
> Run the auto-update-memory script to refresh.

## Corpus Stats
- **Nodes:** {stats.get('nodes', '?')}
- **Edges:** {stats.get('edges', '?')}
- **Communities:** {stats.get('communities', '?')}

## God Nodes (Most Connected)
| Node | Edges |
|---|---|
{god_section}

## Surprising Connections
{surprise_section}

## Top Communities (by node count)
| Community | Nodes | Cohesion | Sample Nodes |
|---|---|---|---|
{comm_section}

## Source
- `{graph_dir}/GRAPH_REPORT.md`
- `{graph_dir}/graph.json`
"""


def update_search_index(search_index: Path):
    row = "| [[graphify-insights]] | concept | graphify, structural-analysis, auto-generated | god-nodes, surprising-connections, communities, call-graph | Auto-generated Graphify structural analysis |"
    with open(search_index, "r", encoding="utf-8") as f:
        content = f.read()

    content = re.sub(r"\| \[\[graphify-insights\]\].*\n", "", content)
    content = content.rstrip() + "\n" + row + "\n"

    with open(search_index, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  Updated: {search_index}")


def update_index(index_path: Path):
    with open(index_path, "r", encoding="utf-8") as f:
        content = f.read()

    section = "## Graphify Structural Insights\n[[graphify-insights]] — Auto-generated code graph analysis (god nodes, communities, surprising connections).\n"

    if "## Graphify Structural Insights" in content:
        content = re.sub(
            r"## Graphify Structural Insights\n.*?(?=\n## |$)",
            section.rstrip(),
            content,
            flags=re.DOTALL,
        )
    else:
        content = content.rstrip() + "\n\n" + section

    with open(index_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  Updated: {index_path}")


def cleanup_old_communities(wiki_dir: Path):
    old_dir = wiki_dir / "graphify-communities"
    if old_dir.exists():
        for f in old_dir.glob("community-*.md"):
            f.unlink()
            print(f"  Cleaned old: {f}")
        old_dir.rmdir()
        print(f"  Removed empty: {old_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Sync Graphify insights to Obsidian wiki pages."
    )
    parser.add_argument("--graph-dir", default=os.getenv("GRAPHIFY_OUT_DIR", "graphify-out"),
                        help="Graph output directory (default: graphify-out or GRAPHIFY_OUT_DIR env)")
    parser.add_argument("--wiki-path", default=os.getenv("WIKI_PATH", "docs/second-brain/wiki"),
                        help="Wiki directory path (default: docs/second-brain/wiki or WIKI_PATH env)")
    args = parser.parse_args()

    graph_report = Path(args.graph_dir) / "GRAPH_REPORT.md"
    wiki_dir = Path(args.wiki_path)
    insights_page = wiki_dir / "graphify-insights.md"
    search_index = wiki_dir / "_SEARCH_INDEX.md"
    index = wiki_dir / "_INDEX.md"

    if not graph_report.exists():
        report_failure("Input", f"{graph_report} not found. Run 'graphify .' first.")
        sys.exit(1)

    print("[1/5] Parsing GRAPH_REPORT.md...")
    data = parse_graph_report(graph_report)
    print(f"  God nodes: {len(data['god_nodes'])}, Surprising: {len(data['surprising_connections'])}, Communities: {len(data['top_communities'])}")

    print("[2/5] Generating insights page...")
    page = generate_insights_page(data, args.graph_dir)
    with open(insights_page, "w", encoding="utf-8") as f:
        f.write(page)
    print(f"  Written: {insights_page}")

    print("[3/5] Cleaning old community pages...")
    cleanup_old_communities(wiki_dir)

    print("[4/5] Updating _SEARCH_INDEX.md...")
    update_search_index(search_index)

    print("[5/5] Updating _INDEX.md...")
    update_index(index)

    report_success(
        data["stats"],
        len(data["god_nodes"]),
        len(data["surprising_connections"]),
        len(data["top_communities"]),
    )


if __name__ == "__main__":
    main()
