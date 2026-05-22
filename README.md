# OpenSkills — Project-Agnostic AI Agent Framework

A portable skill engine, rule framework, and second-brain wiki system for AI coding agents. Works with Claude Code, Cursor, Cline, Kilo Code, Trae, and any IDE that reads `AGENTS.md`. Copy into any project, run setup, and your agent has 27 universal skills, structured rules, and a living knowledge base from the first session.

## Quick Start

```bash
git clone https://github.com/your-org/openkills-template.git my-project
cd my-project
bash scripts/setup.sh        # Linux/macOS
# OR
powershell scripts/setup.ps1 # Windows
```

The setup script asks for your project name, tech stacks, and IDE — then generates `AGENTS.md`, rule files, IDE pointers, and wiki scaffolding. Total time: ~2 minutes.

### Existing Projects (Auto-Detection)

If you have an existing project, use `/initOpenSkills` in your AI coding assistant:

```
/initOpenSkills
```

The agent will:
1. Scan your project for manifest files (package.json, *.csproj, go.mod, etc.)
2. Detect the tech stack, architecture pattern, and code conventions
3. Present the analysis for your confirmation
4. Generate all configuration files automatically

No manual template filling required.

## Features

- **27 universal agent skills** — brainstorming, planning, TDD, debugging, code review, shipping, and more
- **Rule framework** — 7 universal rules + stack-specific rule templates (backend, frontend, mobile)
- **Second-brain wiki** — Karpathy LLM Wiki pattern with structured knowledge capture
- **Memory plugins** — optional Qdrant session memory (Tier-1) and Graphify code graph (Tier-2)
- **IDE-agnostic** — one `AGENTS.md` serves all IDEs via thin pointer files
- **Self-improvement loop** — `/evolve` command captures corrections and friction signals
- **Setup automation** — `setup.sh` / `setup.ps1` with interactive and non-interactive modes
- **Auto-detection** — `/initOpenSkills` scans your existing project and generates configuration automatically

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Your Project                    │
│                                                  │
│  AGENTS.md  ◄── IDE pointer files                │
│      │           (CLAUDE.md, .cursor/rules/,     │
│      │            .clinerules, .kilocode/,        │
│      │            .trae/rules/)                   │
│      ▼                                           │
│  ┌──────────────────────────────────┐            │
│  │         .openskills/             │            │
│  │  SKILL_REGISTRY.md               │            │
│  │  RULE_REGISTRY.md                │            │
│  │  skills/        (20 skills)      │            │
│  │  rules/         (7+ rules)       │            │
│  │  memory-plugins/ (optional)      │            │
│  └──────────────────────────────────┘            │
│      │                                           │
│      ▼                                           │
│  ┌──────────────────────────────────┐            │
│  │    docs/second-brain/            │            │
│  │  wiki/        (live synthesis)   │            │
│  │  raw_sources/ (immutable input)  │            │
│  │  artifacts/   (immutable output) │            │
│  └──────────────────────────────────┘            │
└─────────────────────────────────────────────────┘

Core (always)          Plugins (optional)
─────────────          ──────────────────
Git + any IDE          Python 3.10+
                       Qdrant + Ollama
                       Graphify CLI
```

## Supported IDEs

| IDE | Pointer File | Auto-discovered? |
|---|---|---|
| Claude Code | `CLAUDE.md` (root) | Yes |
| Cursor | `.cursor/rules/00-agent.md` | Yes |
| Cline | `.clinerules` (root) | Yes |
| Kilo Code | `.kilocode/rules.md` | Yes |
| Trae | `.trae/rules/00-agent.md` | Yes |
| OpenCode | `.opencode/` | Yes |

All pointer files are ≤15 lines and redirect to `AGENTS.md`. Updates go to one file only; pointers never drift.

## What's Included

```
.
├── AGENTS.md.template              # Agent bootstrap template
├── CLAUDE.md.template              # IDE pointer templates
├── .clinerules.template
├── .cursor/rules/00-agent.md.template
├── .kilocode/rules.md.template
├── .trae/rules/00-agent.md.template
├── scripts/
│   ├── setup.sh                    # Interactive setup (Bash)
│   ├── setup.ps1                   # Interactive setup (PowerShell)
│   └── validate-structure.sh       # Structure validation
├── .openskills/
│   ├── SKILL_REGISTRY.md           # Skill catalog
│   ├── RULE_REGISTRY.md.template   # Rule catalog template
│   ├── skills/                     # 20 universal skills
│   ├── rules/                      # Universal + stack-specific rules
│   └── memory-plugins/             # Optional memory stack
│       ├── qdrant-session-memory/
│       └── graphify-code-graph/
└── docs/second-brain/
    └── template/                   # Wiki scaffolding template
```

## Documentation

- **[ADOPTION_GUIDE.md](docs/second-brain/template/ADOPTION_GUIDE.md)** — Greenfield, brownfield, and team onboarding modes
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — How to add skills, rules, and plugins
- **[docs/second-brain/template/README.md](docs/second-brain/template/README.md)** — Second-brain wiki template overview

## License

[MIT](LICENSE) — use freely in any project, commercial or personal.
