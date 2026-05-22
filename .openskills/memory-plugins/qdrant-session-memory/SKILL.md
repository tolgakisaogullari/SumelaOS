---
name: qdrant-session-memory
description: "Use when answering questions about past decisions, prior sessions, or 'why' questions — semantic search over Qdrant session history. Activates Tier-1 routing."
---

# Tier-1: Qdrant Session Memory

## Routing
- **Trigger:** Query contains "neden", "niye", "why", "ne karar verdik", "what did we decide", "geçen sefer", "previously", "last time", or references past sprint/decision/ADR.
- **Command:** `python .openskills/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<query>" --limit 3`
- **Threshold:** Top score ≥ 0.5 → read matching session summary file
- **Fallback:** If Qdrant unavailable or score < 0.5 → skip, let Tier-3 (_SEARCH_INDEX.md) handle it

## Session Ingestion
- After context-handoff, run:
  ```
  python .openskills/memory-plugins/qdrant-session-memory/scripts/session-ingest.py <path-to-session-summary.md>
  ```
- Requires: Ollama (qwen3-embedding:0.6b), Qdrant on localhost:6333
- If Qdrant unavailable: session summary remains as markdown only (no data loss)

## Prerequisites
- Python 3.10+
- `pip install -r .openskills/memory-plugins/qdrant-session-memory/requirements.txt`
- Ollama running with `qwen3-embedding:0.6b` model
- Qdrant running on localhost:6333
