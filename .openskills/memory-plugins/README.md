# Memory Plugins

Optional, self-contained memory stack components. Each plugin provides semantic search or structural analysis capabilities that enhance agent recall across sessions.

## Why Plugins?

Memory plugins are **optional**. The agent degrades gracefully without them:
- No Qdrant? Session summaries remain as markdown files (Tier-3 fallback).
- No Graphify? Code queries fall through to grep (Tier-4 fallback).

Plugins are isolated packages with their own dependencies, scripts, and documentation. Activate only what your environment supports.

## Available Plugins

| Plugin | Tier | Purpose | Prerequisites |
|---|---|---|---|
| [qdrant-session-memory](qdrant-session-memory/) | 1 | Semantic search over past session summaries | Python 3.10+, Ollama, Qdrant |
| [graphify-code-graph](graphify-code-graph/) | 2 | Call-graph traversal, impact analysis | Python 3.10+, graphify CLI, Node.js |

## Activation

### Automatic (via setup script)

```bash
# From repo root
bash scripts/setup.sh        # Linux/macOS
powershell scripts/setup.ps1  # Windows
```

The setup script checks prerequisites and installs dependencies for each available plugin.

### Manual

1. Install Python dependencies:
   ```bash
   pip install -r .openskills/memory-plugins/qdrant-session-memory/requirements.txt
   pip install -r .openskills/memory-plugins/graphify-code-graph/requirements.txt
   ```

2. Ensure external services are running (Qdrant, Ollama, graphify CLI).

3. Register plugins in `SKILL_REGISTRY.md` (see below).

## How Skills Discover Plugins

Each plugin contains a `SKILL.md` that defines its routing triggers, commands, and prerequisites. These are registered in `.openskills/SKILL_REGISTRY.md` so the agent can load them on demand.

The agent follows this resolution chain:
1. Query matches a trigger pattern in SKILL_REGISTRY.md
2. Agent loads the plugin's `SKILL.md`
3. Agent executes the plugin's scripts via the documented commands
4. If the plugin is unavailable (missing deps), agent falls back to the next tier

## Structure

```
.openskills/memory-plugins/
├── README.md                          # This file
├── qdrant-session-memory/
│   ├── README.md                      # Plugin-specific setup and config
│   ├── SKILL.md                       # Skill registration (routing, commands)
│   ├── requirements.txt               # Python dependencies
│   └── scripts/
│       ├── setup-qdrant.py            # Collection bootstrap
│       ├── session-ingest.py          # Session summary ingestion
│       └── query-qdrant.py            # Semantic search
└── graphify-code-graph/
    ├── README.md                      # Plugin-specific setup and config
    ├── SKILL.md                       # Skill registration (routing, commands)
    ├── requirements.txt               # Python dependencies
    └── scripts/
        ├── auto-update-memory.py      # Graph rebuild + wiki sync
        ├── query-graph.py             # Call-graph queries
        └── sync-graphify-to-obsidian.py  # Graph → wiki sync
```
