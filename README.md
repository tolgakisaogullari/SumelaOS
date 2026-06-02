# SumelaOS — Project-Agnostic AI Agent Framework

<p align="center">
  <img src="sumela.jpeg" alt="Sumela Monastery, Trabzon, Turkey" width="500" height="625">
</p>

A portable skill engine, rule framework, and second-brain wiki system for AI coding agents. Works with Claude Code, Cursor, Cline, Kilo Code, Trae, and any IDE that reads `AGENTS.md`. Copy into any project, run setup, and your agent has 26 universal skills, structured rules, and a living knowledge base from the first session.

Built to scale from **a single developer to a whole team** — with git-native shared memory, governed self-improvement, enforced structure, per-developer overrides, and a versioned upgrade path. See [Working as a Team](#working-as-a-team).

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
5. Run /initSumela — auto-detect the project's stack, architecture, and conventions
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

Then run `/initSumela` in your AI assistant.

## Features

- **26 universal agent skills** — brainstorming, planning, TDD, debugging, code review, shipping, and more
- **Rule framework** — 7 universal rules + stack-specific rule templates (backend, frontend, mobile)
- **Second-brain wiki** — Karpathy LLM Wiki pattern with structured knowledge capture
- **Memory plugins** — optional Qdrant session memory (Tier-1) and Graphify code graph (Tier-2)
- **IDE-agnostic** — one `AGENTS.md` serves all IDEs via thin pointer files
- **Self-improvement loop** — `/evolve` command captures corrections and friction signals
- **Setup automation** — `setup.sh` / `setup.ps1` with interactive and non-interactive modes
- **Auto-detection** — `/initSumela` scans your existing project and generates configuration automatically
- **Team-ready** — git-native shared session memory, conflict-free wiki, and per-developer language overrides (see [Working as a Team](#working-as-a-team))
- **Governed learning** — in team mode, `/evolve` routes rule/skill/schema changes through a reviewed pull request (CODEOWNERS)
- **Enforced structure** — `validate-structure.sh` runs via a pre-commit hook and an opt-in CI workflow, so the contract can't silently drift
- **Versioned upgrades** — `update.sh` refreshes the framework core without touching your project's overlay; `sync-mirrors.sh` keeps verbatim IDE mirrors in lockstep

## Working as a Team

SumelaOS started as a single-developer tool; these layers make the same setup safe for a whole team. All are opt-in and degrade gracefully when unused.

| Capability | How it works |
|---|---|
| **Shared session memory** | Session summaries are committed to git (the shared source of truth). `post-merge`/`post-checkout` git hooks re-ingest changed summaries into each developer's **local** Qdrant on `git pull`, so a teammate's recorded decisions become searchable on your machine. |
| **Conflict-free wiki** | The append-only `_LOG.md` uses git's `union` merge; the self-improvement queue is a directory (one `IMP-YYYYMMDD-<short>.md` per signal, no shared counter) so concurrent captures never collide; `active-project-context.md` has a per-developer "Active Work" convention. |
| **Governed self-improvement** | `governance: solo \| team` in `AGENTS.md`. In **team** mode, `/evolve` routes changes to the agent-control surface (rules, skills, prompt, schema) through a **pull request** reviewed by `CODEOWNERS` — one developer's learning can't become everyone's standard without review. Lower-stakes wiki/context changes still apply directly. |
| **Enforcement** | A `pre-commit` hook runs the structure validation (and an IDE-mirror drift check) before commits touching the agent surface; an **opt-in** GitHub Actions workflow (`setup.sh --ci`) runs the same on push/PR. Bypass a commit with `git commit --no-verify`. |
| **Per-developer config** | Each developer can override **only** their interaction language via a gitignored `.sumela/local.md` (copy `.sumela/local.md.example`). Code naming/documentation languages stay team-wide for codebase consistency. |
| **Versioned upgrades** | `.sumela/VERSION` + `scripts/update.sh` (and `.ps1`) refresh the framework **core** (prompt, skills, scripts, hooks, universal rules, templates) from upstream — with a per-file diff and your consent — while never touching your **overlay** (AGENTS.md, stack rules, wiki, registries, governance/CI choices). |
| **IDE mirror sync** | Some IDEs need the prompt body verbatim. List those files in `.sumela/mirrors.conf`; `scripts/sync-mirrors.sh` keeps a marker block in each one byte-equal to `sumela-prompt.md`, and pre-commit + CI fail on drift. |
| **Monorepo-ready** | Install at the repo root **or** a subdir — hooks self-anchor to their install. Multiple installs in one repo auto-promote to a root dispatcher (`.sumela-hooks/`) that runs every install's hooks. Rules shared across packages live once in `.sumela-shared/rules/` and `sync-shared-rules.py` distributes + registers them (universal) into each install. See the [ADOPTION_GUIDE §13](docs/second-brain/template/ADOPTION_GUIDE.md). |

Setup tooling wires these per clone (`setup.sh` / `setup.ps1` / `/initSumela`). For step-by-step team adoption, see the [ADOPTION_GUIDE](docs/second-brain/template/ADOPTION_GUIDE.md).

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
│  │  skills/        (26 skills)      │            │
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
│   ├── setup.sh / setup.ps1        # Interactive setup
│   ├── bootstrap.sh / bootstrap.ps1 # One-command install
│   ├── validate-structure.sh       # Structure validation (CI + pre-commit run this)
│   ├── status.sh / status.ps1      # Read-only health report (version, drift, queue, hooks)
│   ├── update.sh / update.ps1      # Refresh framework core (keeps your overlay)
│   ├── reconcile-registry.py       # Auto-register on-disk skills into SKILL_REGISTRY.md
│   ├── sync-shared-rules.py        # Distribute .sumela-shared/rules/ into each install (monorepo)
│   ├── sync-mirrors.sh / .ps1      # Keep verbatim IDE mirrors in sync
│   └── auto-update-memory.py       # Memory-stack maintenance orchestrator
├── .github/workflows/
│   └── sumela-validate.yml         # Opt-in CI structure check
├── .sumela/
│   ├── VERSION                     # Core framework version (for update.sh)
│   ├── SKILL_REGISTRY.md           # Skill catalog
│   ├── RULE_REGISTRY.md.template   # Rule catalog template
│   ├── skills/                     # 26 skills (across 21 dirs)
│   ├── rules/                      # Universal + stack-specific rules
│   ├── git-hooks/                  # pre-commit validation + memory-sync hooks
│   ├── local.md.example            # Per-developer override template (gitignored when copied)
│   ├── mirrors.conf.example        # IDE mirror targets
│   └── memory-plugins/             # Optional memory stack
│       ├── qdrant-session-memory/
│       └── graphify-code-graph/
└── docs/second-brain/
    └── template/                   # Wiki scaffolding template (incl. _improvement-queue/)
```

## Documentation

- **[ADOPTION_GUIDE.md](docs/second-brain/template/ADOPTION_GUIDE.md)** — Greenfield, brownfield, and team onboarding modes
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — How to add skills, rules, and plugins
- **[docs/second-brain/template/README.md](docs/second-brain/template/README.md)** — Second-brain wiki template overview

## What Problems Does This Solve?

AI coding agents (Claude Code, Cursor, Cline, etc.) are powerful but unstructured by default. Each session starts from scratch — no memory of past decisions, no coding standards, no architectural guardrails. SumelaOS solves this:

| Problem | Without SumelaOS | With SumelaOS |
|---|---|---|
| **No workflow structure** | Agent improvises each task | 26 skills define structured workflows (brainstorm → plan → implement → review → ship) |
| **No coding standards** | Agent uses its own defaults | Project-specific rules enforce your conventions |
| **No session memory** | Every session starts from zero | Qdrant plugin remembers past decisions; on a team, summaries sync to every developer via git hooks |
| **No code structure awareness** | Agent greps blindly | Graphify plugin understands call graphs and dependencies |
| **No knowledge capture** | Knowledge lives in chat history | Second-brain wiki captures decisions, entities, and architecture |
| **No self-improvement** | Same mistakes repeat | `/evolve` command captures friction signals and applies learnings |
| **IDE lock-in** | Different configs per IDE | One `AGENTS.md` serves all IDEs via thin pointer files |
| **Team merge conflicts** | Everyone edits the same memory/queue files | Union-merge logs + one-file-per-signal queue + per-developer overrides |
| **Ungoverned agent standards** | One dev's correction silently becomes everyone's rule | Team mode routes rule/skill/schema changes through a reviewed PR (CODEOWNERS) |
| **Drift & decay** | Structure rots; framework updates clobber customizations | Pre-commit + CI enforce the contract; `update.sh` upgrades the core, never the overlay |

## Credits & Foundations

SumelaOS builds on the work of two exceptional open-source projects:

### [obra/superpowers](https://github.com/obra/superpowers) — The Skill Engine

The core skill architecture — the universal skills covering brainstorming, planning, TDD, debugging, code review, shipping, and more — is based on [Superpowers](https://github.com/obra/superpowers) by [obra](https://github.com/obra). Superpowers introduced the concept of structured agent workflows: instead of letting the agent improvise, skills define step-by-step procedures that enforce quality gates, security checks, and user approval points.

**What we added on top:**
- **Rule framework** with phase-to-rule matrix (universal + stack-specific rules)
- **Second-brain wiki** with Karpathy LLM Wiki pattern for knowledge capture
- **Self-improvement loop** (`/evolve`) for capturing and applying learnings
- **Context Manifest** protocol for session-start transparency
- **Proactive impact analysis** — agent checks code dependencies before making changes
- **Project-agnostic template** — works with any stack, not just one project
- **Team-enablement layer** — git-native shared memory, conflict-free wiki, PR-governed `/evolve`, pre-commit + CI enforcement, per-developer overrides, and a versioned core upgrade path

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
