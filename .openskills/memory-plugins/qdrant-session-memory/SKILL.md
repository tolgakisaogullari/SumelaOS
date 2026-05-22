---
name: qdrant-session-memory
description: "Use when answering questions about past decisions, prior sessions, or 'why' questions — semantic search over Qdrant session history. Activates Tier-1 routing."
---

# Tier-1: Qdrant Session Memory

## Important: No API Key Required for Queries

All query operations read from the local Qdrant database via `query-qdrant.py`. They are **purely local** — no external API calls, no cost. API keys are only needed for embedding generation via Ollama (which runs locally).

## Proactive Usage (Silent)

The agent should query Qdrant **without waiting for the user to ask** in these scenarios:

### Before Starting a Task
When the user assigns a new task, check if similar work was done before:
```
python .openskills/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<task description>" --limit 3
```
- If top score ≥ 0.5: read the matching session summary for context, lessons learned, and decisions made
- If score < 0.5: skip — no relevant past context

### When Encountering an Entity or Concept
When the task involves an entity, service, or concept that might have been discussed before:
```
python .openskills/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<entity name> <context>" --limit 3
```
Example: Task mentions "CommentService" → query "CommentService design decisions"

### When Making Architectural Decisions
Before proposing an architecture or design choice, check if similar decisions were made:
```
python .openskills/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<decision topic>" --limit 3
```
Example: "caching strategy" → check if caching was discussed before

### When Debugging
Before diving into a bug, check if similar issues were encountered:
```
python .openskills/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<bug description or error message>" --limit 3
```

### When a File is Mentioned
When the task involves a specific file that might have history:
```
python .openskills/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<filename> changes" --limit 3
```

**RULE:** This is SILENT — do not announce "I'm checking past sessions via Qdrant" unless the user explicitly asks. Just query, read relevant context, and incorporate into your analysis.

## Reactive Usage (User-Triggered)

These triggers require an explicit user query:

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
