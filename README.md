# SumelaOS — Project-Agnostic AI Agent Framework

A portable skill engine, rule framework, and second-brain wiki system for AI coding agents. Works with Claude Code, Cursor, Cline, Kilo Code, Trae, and any IDE that reads `AGENTS.md`. Copy into any project, run setup, and your agent has 27 universal skills, structured rules, and a living knowledge base from the first session.

## Why SumelaOS?

In 386 AD, two Athenian monks climbed a nearly vertical cliff in the Pontic Mountains of Trabzon, Turkey. At 1,200 meters elevation, they built a monastery that would endure for over 1,600 years.

Sumela Monastery was not built on safe ground. It clings to a steep rock face, defying gravity. Despite facing destruction over the centuries, it was persistently rebuilt and restored, standing as a testament to resilience. 

The name "Sumela" comes from the Greek "Sou Melá" — "of the black mountain," referring to the dark rock beneath it. 

This project carries that spirit:
- **Built on difficult terrain.** AI agents work in complex, messy codebases — not ideal conditions.
- **Resilient through destruction.** Sessions end, context is lost, knowledge disappears. SumelaOS preserves it.
- **Rebuilt, never abandoned.** Every session learns from the last. The `/evolve` command captures friction and applies corrections — the monastery is always being restored.
- **Structured on the cliff.** Skills, rules, and knowledge layers are the architectural scaffolding that holds everything together.

Like the monks who built Sumela on impossible ground, we build agent workflows on the unpredictable foundation of AI — and make them last.

## Quick Start

### New Projects (Template)

```bash
git clone https://github.com/tolgakisaogullari/SumelaOS.git my-project
cd my-project
bash scripts/setup.sh        # Linux/macOS
# OR
powershell scripts/setup.ps1 # Windows
```

### Existing Projects — Agent Prompt

Copy-paste this prompt into your AI coding assistant (Claude Code, Cursor, OpenCode, Cline, etc.) in any existing project:

```
Set up the SumelaOS agent framework in this project. Steps:

1. Clone https://github.com/tolgakisaogullari/SumelaOS to a temporary directory
2. Copy .sumela/, scripts/, and template files (AGENTS.md.template, CLAUDE.md.template, .clinerules.template, .cursor/, .kilocode/, .trae/) to this project's root
3. Copy docs/second-brain/template/ as docs/second-brain/, create .gitkeep for empty directories
4. Delete the temporary clone
5. Run /initSumelaOS — auto-detect the project's stack, architecture, and conventions
6. Ask language preferences: (a) What language should the agent use to communicate? (b) What language for code names? (c) What language for code comments/docs?
7. Ask about memory plugins (Qdrant, Graphify) — if the user declines, do not install or run their scripts

Do everything automatically, leave no manual steps.
```

The agent will:
1. Clone the SumelaOS repo and copy files to your project
2. Auto-detect your tech stack, architecture, and code conventions
3. Ask about optional memory plugins (Qdrant session memory, Graphify code graph)
4. Generate AGENTS.md, rules, wiki, and IDE pointers based on your project

### Alternative: One-Command Bootstrap

```bash
# Linux/macOS
curl -sSL https://raw.githubusercontent.com/tolgakisaogullari/SumelaOS/master/scripts/bootstrap.sh | bash

# Windows/PowerShell
git clone --depth 1 https://github.com/tolgakisaogullari/SumelaOS.git $env:TEMP\SumelaOS
Copy-Item -Path "$env:TEMP\SumelaOS\.sumela" -Destination "." -Recurse -Force
Copy-Item -Path "$env:TEMP\SumelaOS\scripts" -Destination "." -Recurse -Force
```

Then run `/initSumelaOS` in your AI assistant.

## Features

- **27 universal agent skills** — brainstorming, planning, TDD, debugging, code review, shipping, and more
- **Rule framework** — 7 universal rules + stack-specific rule templates (backend, frontend, mobile)
- **Second-brain wiki** — Karpathy LLM Wiki pattern with structured knowledge capture
- **Memory plugins** — optional Qdrant session memory (Tier-1) and Graphify code graph (Tier-2)
- **IDE-agnostic** — one `AGENTS.md` serves all IDEs via thin pointer files
- **Self-improvement loop** — `/evolve` command captures corrections and friction signals
- **Setup automation** — `setup.sh` / `setup.ps1` with interactive and non-interactive modes
- **Auto-detection** — `/initSumelaOS` scans your existing project and generates configuration automatically

## The Sumela Prompt — Your Agent's Constitution

The most important file in this framework is `.sumela/sumela-prompt.md`. It is the **runtime contract** — the single source of truth that governs how your agent behaves across every session and every IDE.

This file defines:
- **Session bootstrap** — what the agent reads when a session starts
- **Skill and rule loading** — which workflows and constraints are active
- **Information gap routing** — how the agent searches for context (Qdrant, Graphify, wiki, grep)
- **Signal capture** — how the agent learns from corrections and friction
- **Context manifest** — what the agent shows you at session start

Every other file in `.sumela/` defers to this prompt when instructions conflict. **You don't need to edit it** — it works out of the box. But if you want to customize how your agent behaves at the deepest level, this is where you do it.

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
│  │         .sumela/             │            │
│  │  SKILL_REGISTRY.md               │            │
│  │  RULE_REGISTRY.md                │            │
│  │  skills/        (27 skills)      │            │
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
├── .sumela/
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

## What Problems Does This Solve?

AI coding agents (Claude Code, Cursor, Cline, etc.) are powerful but unstructured by default. Each session starts from scratch — no memory of past decisions, no coding standards, no architectural guardrails. SumelaOS solves this:

| Problem | Without SumelaOS | With SumelaOS |
|---|---|---|
| **No workflow structure** | Agent improvises each task | 27 skills define structured workflows (brainstorm → plan → implement → review → ship) |
| **No coding standards** | Agent uses its own defaults | Project-specific rules enforce your conventions |
| **No session memory** | Every session starts from zero | Qdrant plugin remembers past decisions and context |
| **No code structure awareness** | Agent greps blindly | Graphify plugin understands call graphs and dependencies |
| **No knowledge capture** | Knowledge lives in chat history | Second-brain wiki captures decisions, entities, and architecture |
| **No self-improvement** | Same mistakes repeat | `/evolve` command captures friction signals and applies learnings |
| **IDE lock-in** | Different configs per IDE | One `AGENTS.md` serves all IDEs via thin pointer files |

## Credits & Foundations

SumelaOS builds on the work of two exceptional open-source projects:

### [obra/superpowers](https://github.com/obra/superpowers) — The Skill Engine

The core skill architecture — 25 universal skills covering brainstorming, planning, TDD, debugging, code review, shipping, and more — is based on [Superpowers](https://github.com/obra/superpowers) by [obra](https://github.com/obra). Superpowers introduced the concept of structured agent workflows: instead of letting the agent improvise, skills define step-by-step procedures that enforce quality gates, security checks, and user approval points.

**What we added on top:**
- **Rule framework** with phase-to-rule matrix (universal + stack-specific rules)
- **Second-brain wiki** with Karpathy LLM Wiki pattern for knowledge capture
- **Self-improvement loop** (`/evolve`) for capturing and applying learnings
- **Context Manifest** protocol for session-start transparency
- **Proactive impact analysis** — agent checks code dependencies before making changes
- **Project-agnostic template** — works with any stack, not just one project

### [safishamsi/graphify](https://github.com/safishamsi/graphify) — The Code Graph

[Graphify](https://github.com/safishamsi/graphify) by [Safi Shamsi](https://github.com/safishamsi) turns any codebase into a queryable knowledge graph. It uses tree-sitter AST extraction to map function calls, class relationships, and module dependencies — all locally, no API keys required for queries.

**What we added on top:**
- **Proactive usage** — agent queries graphify before making changes to detect affected dependents
- **Plugin architecture** — graphify is an optional memory plugin, not a hard dependency
- **Integration with session memory** — graph insights combined with Qdrant session history

### [Karpathy LLM Wiki Pattern](https://karpathy.medium.com/) — The Knowledge Layer

The second-brain wiki system implements Andrej Karpathy's LLM Wiki pattern: a three-layer knowledge system (raw sources → artifacts → live wiki) that gives agents structured access to project knowledge instead of re-reading files every session.

### How These Fit Together

```
Superpowers (skills)     Graphify (code graph)     Qdrant (session memory)
     │                        │                          │
     ▼                        ▼                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    SumelaOS Framework                       │
│                                                               │
│  Skills define WHAT to do (workflows)                        │
│  Rules define HOW to do it (conventions)                     │
│  Graphify knows the CODE structure (call graphs)             │
│  Qdrant knows the HISTORY (past decisions)                   │
│  Wiki captures KNOWLEDGE (architecture, entities)            │
│  /evolve captures LEARNINGS (corrections, friction)          │
└─────────────────────────────────────────────────────────────┘
```

## License

[MIT](LICENSE) — use freely in any project, commercial or personal.
