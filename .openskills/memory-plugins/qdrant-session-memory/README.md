# Qdrant Session Memory Plugin

Tier-1 memory: semantic search over session summaries stored in Qdrant vector database.

## Prerequisites

- **Python 3.10+**
- **Ollama** running with `qwen3-embedding:0.6b` model
- **Qdrant** running on `localhost:6333` (default)

## Setup

```bash
# Install Python dependencies
pip install -r .openskills/memory-plugins/qdrant-session-memory/requirements.txt

# Bootstrap Qdrant collections
python .openskills/memory-plugins/qdrant-session-memory/scripts/setup-qdrant.py
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
python .openskills/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "what did we decide" --host my-qdrant --port 6333

# Use environment variables
export QDRANT_HOST=192.168.1.100
export OLLAMA_URL=http://gpu-server:11434
python .openskills/memory-plugins/qdrant-session-memory/scripts/session-ingest.py session-summary.md
```

## Scripts

| Script | Purpose |
|---|---|
| `setup-qdrant.py` | Create Qdrant collections (idempotent) |
| `session-ingest.py` | Ingest a session summary markdown into Qdrant |
| `query-qdrant.py` | Semantic search over session history |

## Graceful Degradation

If Qdrant is unavailable:
- `session-ingest.py` prints a warning and exits 0 (markdown summary is preserved)
- `query-qdrant.py` prints a failure report and exits 1 (agent falls back to Tier-3)
