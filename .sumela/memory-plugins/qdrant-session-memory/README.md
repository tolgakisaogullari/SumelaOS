# Qdrant Session Memory Plugin

Tier-1 memory: semantic search over session summaries stored in Qdrant vector database.

## Prerequisites

- **Python 3.10+**
- **Ollama** running with `qwen3-embedding:0.6b` model
- **Qdrant** running on `localhost:6333` (default)

## Setup

```bash
# Install Python dependencies
pip install -r .sumela/memory-plugins/qdrant-session-memory/requirements.txt

# Bootstrap Qdrant collections
python .sumela/memory-plugins/qdrant-session-memory/scripts/setup-qdrant.py
```

## Configuration

All scripts accept CLI arguments and environment variables. CLI args take precedence.

| Setting | CLI Arg | Env Var | Default |
|---|---|---|---|
| Qdrant host | `--host` | `QDRANT_HOST` | `localhost` |
| Qdrant port | `--port` | `QDRANT_PORT` | `6333` |
| Ollama URL | `--ollama-url` | `OLLAMA_URL` | `http://localhost:11434` |
| Collection name | `--collection` | `QDRANT_COLLECTION` | `chat_history` |

### Examples

```bash
# Use custom Qdrant instance
python .sumela/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "what did we decide" --host my-qdrant --port 6333

# Use environment variables
export QDRANT_HOST=192.168.1.100
export OLLAMA_URL=http://gpu-server:11434
python .sumela/memory-plugins/qdrant-session-memory/scripts/session-ingest.py session-summary.md
```

## Session metadata — queryable by developer / domain / date

`session-ingest.py` reads the session-summary frontmatter (see `_SCHEMA.md` Session Summary
Page Template) into the `chat_history` payload, so sessions are filterable, not just
semantically searchable. Fields: `developer`, `developer_email`, `domains` (list),
`spec_artifact`, `plan_artifact`, `date`/`date_int` (YYYYMMDD), `session_topics`.

`query-qdrant.py` adds matching filters:

```bash
# Filtered semantic search (combine a query with filters)
python .../query-qdrant.py "card limit bug" --developer "Ada Lovelace" --domain Card

# Filter-ONLY listing — everything a developer did in a date range (pass "*" as the query)
python .../query-qdrant.py "*" --developer "Ada Lovelace" --since 2026-06-01 --until 2026-06-07

# All Card-domain sessions since a date
python .../query-qdrant.py "*" --domain Card --since 2026-06-01
```

`--developer`/`--domain` are exact (case-sensitive) matches on the stored value; `--since`/`--until`
range on `date_int`. Summaries stamp `domains` in the canonical `<domain_scopes>` casing (e.g.
`Card`), so query with that casing (`--domain Card`). Notes: (1) summaries written before this
feature lack these fields and won't match a filter. New + edited summaries carry them going
forward; a pre-existing summary backfills ONLY if it's re-committed (the post-merge hook
re-ingests just the Added/Modified summaries in a pulled range, not the whole tree). To fully
backfill history once, manually re-ingest: `for f in docs/second-brain/wiki/session-summaries/*.md; do python .../session-ingest.py "$f"; done`. (2) when frontmatter omits
`developer`/`session_date`, the hook passes the commit's git author/date via
`--fallback-developer`/`--fallback-date`; (3) for exact commit-level attribution, `git log` is
the authoritative source — this captures the session narrative.

## Scripts

| Script | Purpose |
|---|---|
| `setup-qdrant.py` | Create Qdrant collections (idempotent) |
| `session-ingest.py` | Ingest a session summary markdown into Qdrant (developer/domain/date/spec/plan metadata) |
| `query-qdrant.py` | Semantic search + developer/domain/date filters (and filter-only listing) over session history |
| `ingest-code-to-qdrant.py` | Ingest source code files into `code_chunks` collection |
| `ingest-wiki-to-qdrant.py` | Ingest wiki pages into `wiki_pages` collection |
| `lib/memory_ingest.py` | Shared helpers (chunking, embedding, deterministic IDs) |

## Graceful Degradation

If Qdrant is unavailable:
- `session-ingest.py` prints a warning and exits 0 (markdown summary is preserved)
- `query-qdrant.py` prints a failure report and exits 1 (agent falls back to Tier-3)
- `ingest-code-to-qdrant.py` and `ingest-wiki-to-qdrant.py` print failure reports and exit 1
