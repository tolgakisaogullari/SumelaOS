---
name: graphify-code-graph
description: "Use when answering questions about function callers/callees, code dependencies, impact analysis, or 'who calls X' — structural search over Graphify code graph. Activates Tier-2 routing."
---

# Tier-2: Graphify Code Graph

## Important: No API Key Required for Queries

All query operations (`query-graph.py`, `graphify query`, `graphify path`, `graphify explain`) read from the local `graphify-out/graph.json` file. They are **purely local** — no network calls, no API keys, no cost. API keys are only needed for initial graph BUILD from docs/PDFs/images (not for querying an existing graph).

## Routing
- **Trigger:** Query contains "X nerede kullanılıyor", "X used where", "who calls X", "what does X call", "if I change X what breaks", or references function/class/method + asks about callers/callees/dependencies.
- **Primary tool:** `python .openskills/memory-plugins/graphify-code-graph/scripts/query-graph.py "<symbol>"`
  - `--depth 2` for transitive (2-hop)
  - `--impact` for incoming closure (what breaks if you change X)
  - `--relation calls` to restrict to call edges
  - `--json` for machine-readable output
- **Secondary tools:**
  - `graphify query "<symbol>" --budget 2000` — BFS neighborhood walk
  - `graphify explain "<symbol>"` — plain-language node summary
  - `graphify path "<src>" "<tgt>"` — shortest path between nodes
- **Fallback:** If graphify not installed or graph.json missing → skip, fall through to Tier-4 (grep)

## Graph Maintenance
- After code commits, run:
  ```
  python .openskills/memory-plugins/graphify-code-graph/scripts/auto-update-memory.py
  ```
- This updates the graph, syncs to wiki, and runs Qdrant health check (if plugin active)
- Conditional: only run when code changed, not for pure handoff/summary sessions

## Prerequisites
- Python 3.10+
- **uv** (recommended) or **pipx**: `uv tool install graphifyy`
- `pip install -r .openskills/memory-plugins/graphify-code-graph/requirements.txt`
- Run `/graphify .` in IDE or `graphify .` in terminal to seed `graphify-out/graph.json`
- Optional: `graphify hook install` for auto-rebuild on commit

## Community Plugin Notice
> This plugin depends on [graphify](https://github.com/safishamsi/graphify) — a third-party open-source tool (51k+ stars, MIT license). Verify compatibility with your codebase and language before activation. The plugin degrades gracefully if graphify is unavailable.
