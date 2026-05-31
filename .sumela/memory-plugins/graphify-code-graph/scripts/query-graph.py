#!/usr/bin/env python3
"""
query-graph.py — Tier-2 helper: agent-friendly view onto graphify-out/graph.json (v1.0-agnostic)

Why this script exists:
    `graphify query` does a BFS budget walk that returns NODE neighborhoods but
    does not surface CALL edges in human-readable form.
    `graphify explain` returns a single node's connections but matches the first
    candidate (often the interface, not the implementation) and stops there.

    Our graph (NetworkX format under `graphify-out/graph.json`) carries
    call edges that the agent needs to answer "who calls X" / "X calls
    who" / "impact of changing X" questions. This script reads those edges
    directly and prints a structured report.

Usage:
    python query-graph.py "RegisterAsync"
    python query-graph.py "AuthService" --depth 2
    python query-graph.py "Comment" --impact
    python query-graph.py "RegisterAsync" --relation calls --json
    python query-graph.py "RegisterAsync" --confidence EXTRACTED
    python query-graph.py "MyFunc" --graph-dir custom-graph-output

Modes:
    default      callers + callees + same-name node summary
    --depth N    transitive BFS up to N hops (default 1)
    --impact     incoming closure up to depth 3 (which files break if you change X)
    --relation R restrict to a relation type (calls | method | contains | inherits | uses | imports_from)
    --confidence C   restrict to confidence (EXTRACTED | INFERRED | AMBIGUOUS)
    --json       machine-readable JSON output
    --graph-dir DIR  override default graphify-out directory

Exit codes:
    0  success (one or more matched nodes)
    1  no matching node
    2  graph file missing or malformed

Environment:
    GRAPHIFY_OUT_DIR — graph output directory (default: graphify-out)
"""
import argparse
import json
import os
import sys
from collections import deque
from pathlib import Path
from typing import Iterable

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

DEFAULT_GRAPH_DIR = os.getenv("GRAPHIFY_OUT_DIR", "graphify-out")


def _print_report(lines: list):
    print("\n" + "=" * 60)
    print("GRAPH QUERY REPORT")
    print("=" * 60)
    for line in lines:
        print(line)
    print("=" * 60 + "\n")


def _report_failure(stage: str, reason: str, exit_code: int = 1):
    _print_report([
        "Status: FAILED",
        f"Stage: {stage}",
        f"Reason: {reason}",
        "Action for agent: surface the failure to the user.",
    ])
    sys.exit(exit_code)


class Graph:
    """Wrapper around the NetworkX-format graph.json with lookup helpers."""

    def __init__(self, path: str):
        if not os.path.exists(path):
            _report_failure("Input", f"graph file not found: {path}", exit_code=2)
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except json.JSONDecodeError as e:
            _report_failure("Parse", f"graph.json is not valid JSON: {e}", exit_code=2)

        if "nodes" not in data or "links" not in data:
            _report_failure(
                "Parse",
                "graph.json missing 'nodes' or 'links'; expected NetworkX node-link format.",
                exit_code=2,
            )

        self.path = path
        self.nodes: list[dict] = data["nodes"]
        self.links: list[dict] = data["links"]
        self._by_id: dict[str, dict] = {n["id"]: n for n in self.nodes}
        self._out_by_src: dict[str, list[dict]] = {}
        self._in_by_tgt: dict[str, list[dict]] = {}
        for L in self.links:
            self._out_by_src.setdefault(L["source"], []).append(L)
            self._in_by_tgt.setdefault(L["target"], []).append(L)

    def get(self, node_id: str) -> dict | None:
        return self._by_id.get(node_id)

    def out_edges(self, node_id: str) -> list[dict]:
        return self._out_by_src.get(node_id, [])

    def in_edges(self, node_id: str) -> list[dict]:
        return self._in_by_tgt.get(node_id, [])

    def find_by_symbol(self, symbol: str) -> list[dict]:
        """Match nodes whose label or id contains the symbol (case-insensitive).

        Strips leading dot/parens for method-style queries. Matching is generous
        so users can pass bare class/method names.
        """
        s = symbol.strip().lower()
        for prefix in (".",):
            if s.startswith(prefix):
                s = s[len(prefix):]
        s = s.rstrip("()")
        s = s.strip()
        matches: list[dict] = []
        for n in self.nodes:
            label = (n.get("label") or "").lower()
            nid = (n.get("id") or "").lower()
            if s in label or s in nid:
                matches.append(n)

        def _rank(n: dict) -> tuple[int, int]:
            label = (n.get("label") or "").lower().strip(".()")
            if label == s:
                return (0, 0)
            if label.startswith(s) or label.endswith(s):
                return (1, len(label))
            if s in label:
                return (2, len(label))
            return (3, len(n.get("id", "")))
        matches.sort(key=_rank)
        return matches


def _fmt_node_ref(n: dict) -> str:
    label = n.get("label", "?")
    src = (n.get("source_file") or "").replace("\\", "/")
    loc = n.get("source_location") or ""
    if src:
        return f"{label}  [{src}{':' + loc if loc else ''}]"
    return label


def _fmt_edge(graph: Graph, edge: dict, direction: str) -> str:
    other_id = edge["target"] if direction == "out" else edge["source"]
    other = graph.get(other_id) or {"label": other_id, "id": other_id}
    arrow = "-->" if direction == "out" else "<--"
    rel = edge.get("relation", "?")
    conf = edge.get("confidence", "?")
    tag = f"[{rel}, {conf}]"
    return f"  {arrow} {_fmt_node_ref(other):<70} {tag}"


def _bfs(graph: Graph, root_ids: Iterable[str], direction: str, depth: int,
         relation: str | None, confidence: str | None) -> list[tuple[int, dict]]:
    """Return list of (depth, edge) reached, deduped by edge identity."""
    visited_nodes: set[str] = set(root_ids)
    queue: deque[tuple[int, str]] = deque((0, nid) for nid in root_ids)
    seen_edges: set[tuple[str, str, str]] = set()
    out: list[tuple[int, dict]] = []
    while queue:
        d, nid = queue.popleft()
        if d >= depth:
            continue
        edges = graph.out_edges(nid) if direction == "out" else graph.in_edges(nid)
        for e in edges:
            if relation and e.get("relation") != relation:
                continue
            if confidence and e.get("confidence") != confidence:
                continue
            key = (e["source"], e["target"], e.get("relation", ""))
            if key in seen_edges:
                continue
            seen_edges.add(key)
            out.append((d + 1, e))
            other = e["target"] if direction == "out" else e["source"]
            if other not in visited_nodes:
                visited_nodes.add(other)
                queue.append((d + 1, other))
    return out


def _print_human(graph: Graph, matches: list[dict], args: argparse.Namespace):
    head_lines = [
        "Status: SUCCESS",
        f"Symbol: {args.symbol}",
        f"Matched nodes: {len(matches)}",
    ]
    for m in matches[:5]:
        head_lines.append(f"  {m.get('id','?')[:55]:<55} {_fmt_node_ref(m)}")
    if len(matches) > 5:
        head_lines.append(f"  ... (+{len(matches) - 5} more)")
    head_lines.append("Action for agent: cite source_file:source_location for each edge in your answer.")
    _print_report(head_lines)

    root_ids = {m["id"] for m in matches}
    relation = args.relation
    confidence = args.confidence

    if args.impact:
        impact = _bfs(graph, root_ids, "in", 3, relation, confidence)
        print(f"IMPACT (incoming transitive, depth <= 3, relation={relation or 'any'}): {len(impact)} edges")
        for d, e in impact:
            print(f"  d={d} {_fmt_edge(graph, e, 'in').lstrip()}")
        return

    out_edges = _bfs(graph, root_ids, "out", args.depth, relation, confidence)
    in_edges = _bfs(graph, root_ids, "in", args.depth, relation, confidence)

    rel_label = relation or "any relation"
    conf_label = f", confidence={confidence}" if confidence else ""

    print(f"OUTGOING ({rel_label}{conf_label}, depth <= {args.depth}): {len(out_edges)} edges")
    if not out_edges:
        print("  (none)")
    for d, e in out_edges[:60]:
        prefix = f"  d={d}" if args.depth > 1 else ""
        print(f"{prefix} {_fmt_edge(graph, e, 'out').lstrip()}")
    if len(out_edges) > 60:
        print(f"  ... (+{len(out_edges) - 60} more — use --json for full list)")
    print()

    print(f"INCOMING ({rel_label}{conf_label}, depth <= {args.depth}): {len(in_edges)} edges")
    if not in_edges:
        print("  (none)")
    for d, e in in_edges[:60]:
        prefix = f"  d={d}" if args.depth > 1 else ""
        print(f"{prefix} {_fmt_edge(graph, e, 'in').lstrip()}")
    if len(in_edges) > 60:
        print(f"  ... (+{len(in_edges) - 60} more — use --json for full list)")


def _print_json(graph: Graph, matches: list[dict], args: argparse.Namespace):
    root_ids = {m["id"] for m in matches}
    if args.impact:
        impact = _bfs(graph, root_ids, "in", 3, args.relation, args.confidence)
        payload = {
            "status": "SUCCESS",
            "symbol": args.symbol,
            "mode": "impact",
            "matched_nodes": [
                {"id": m["id"], "label": m.get("label"),
                 "source_file": m.get("source_file"), "source_location": m.get("source_location"),
                 "community": m.get("community")}
                for m in matches
            ],
            "incoming_transitive": [
                {"depth": d, "source": e["source"], "target": e["target"],
                 "relation": e.get("relation"), "confidence": e.get("confidence")}
                for d, e in impact
            ],
        }
    else:
        out_edges = _bfs(graph, root_ids, "out", args.depth, args.relation, args.confidence)
        in_edges = _bfs(graph, root_ids, "in", args.depth, args.relation, args.confidence)
        payload = {
            "status": "SUCCESS",
            "symbol": args.symbol,
            "depth": args.depth,
            "relation_filter": args.relation,
            "confidence_filter": args.confidence,
            "matched_nodes": [
                {"id": m["id"], "label": m.get("label"),
                 "source_file": m.get("source_file"), "source_location": m.get("source_location"),
                 "community": m.get("community")}
                for m in matches
            ],
            "outgoing": [
                {"depth": d, "source": e["source"], "target": e["target"],
                 "relation": e.get("relation"), "confidence": e.get("confidence")}
                for d, e in out_edges
            ],
            "incoming": [
                {"depth": d, "source": e["source"], "target": e["target"],
                 "relation": e.get("relation"), "confidence": e.get("confidence")}
                for d, e in in_edges
            ],
        }
    print(json.dumps(payload, indent=2, ensure_ascii=False))


def main():
    default_graph = os.path.join(DEFAULT_GRAPH_DIR, "graph.json")

    parser = argparse.ArgumentParser(
        description="Tier-2 graph query — read graph.json directly for callers/callees/impact.",
    )
    parser.add_argument("symbol", help="Symbol to look up (class/method/file name; case-insensitive substring match).")
    parser.add_argument("--depth", type=int, default=1, help="BFS depth for outgoing+incoming edges (default 1).")
    parser.add_argument("--impact", action="store_true", help="Impact mode: incoming closure depth 3 (what breaks if you change this).")
    parser.add_argument("--relation", choices=["calls", "method", "contains", "inherits", "uses", "imports_from", "rationale_for"],
                        default=None, help="Restrict to a single relation type.")
    parser.add_argument("--confidence", choices=["EXTRACTED", "INFERRED", "AMBIGUOUS"],
                        default=None, help="Restrict to a single confidence level.")
    parser.add_argument("--json", action="store_true", help="Output structured JSON instead of human-readable report.")
    parser.add_argument("--graph-dir", default=DEFAULT_GRAPH_DIR,
                        help=f"Directory containing graph.json (default: {DEFAULT_GRAPH_DIR}).")
    parser.add_argument("--graph", default=None,
                        help="Full path to graph.json (overrides --graph-dir).")
    args = parser.parse_args()

    graph_path = args.graph or os.path.join(args.graph_dir, "graph.json")
    graph = Graph(graph_path)
    matches = graph.find_by_symbol(args.symbol)
    if not matches:
        if args.json:
            print(json.dumps({"status": "NO_MATCH", "symbol": args.symbol}, indent=2))
            sys.exit(1)
        _report_failure("Match", f"no node matches symbol '{args.symbol}' (case-insensitive substring on label or id).", exit_code=1)

    if args.json:
        _print_json(graph, matches, args)
    else:
        _print_human(graph, matches, args)
    sys.exit(0)


if __name__ == "__main__":
    main()
