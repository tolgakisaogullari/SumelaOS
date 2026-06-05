# SumelaOS — Project-Agnostic AI Agent Framework

<p align="center">
  <img src="sumela.jpeg" alt="Sumela Monastery, Trabzon, Turkey" width="500" height="625">
</p>

A portable skill engine, rule framework, and second-brain wiki system for AI coding agents. Works with Claude Code, Cursor, Cline, Kilo Code, Trae, OpenCode, and any IDE that reads `AGENTS.md`. Copy into any project, run setup, and your agent has 22 skill workflows, structured rules, and a living knowledge base from the first session.

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

**Prerequisites.** The core framework needs only **git** and any AI coding agent — nothing else. The optional memory layer adds: **Python 3.10+** (both plugins), **Docker + Ollama** (Qdrant session memory), and the **graphify** CLI (code graph). Setup installs the safe deps and *confirms* each invasive step, but it cannot install Docker/Ollama for you — have those present first if you want the Qdrant plugin. Decline the plugins and there are no extra prerequisites.

> Setup is automatic in the sense that it leaves **no manual file-editing homework** — it does ask a few setup questions (3 languages, governance mode, which plugins/IDEs), each with a sensible default.

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
Set up the SumelaOS agent framework in this project. Do everything automatically; leave no manual steps.

STEP 1 — Copy the framework into this project.
Prefer the bundled bootstrap — it clones the repo, copies .sumela/, scripts/, EVERY IDE pointer template, and the second-brain template, then cleans up the clone:
  • macOS/Linux:  curl -sSL https://raw.githubusercontent.com/tolgakisaogullari/SumelaOS/master/scripts/bootstrap.sh | bash
  • Windows:      git clone --depth 1 https://github.com/tolgakisaogullari/SumelaOS.git "$env:TEMP\SumelaOS"; pwsh "$env:TEMP\SumelaOS\scripts\bootstrap.ps1"; Remove-Item "$env:TEMP\SumelaOS" -Recurse -Force
If you cannot run a script, do it manually: clone the repo to a temp dir, then copy into this project's root — .sumela/, scripts/, AGENTS.md.template, ALL IDE pointer templates (CLAUDE.md.template, .clinerules.template, .cursor/, .kilocode/, .trae/, .opencode/), and docs/second-brain/template/ (as docs/second-brain/template/). Then delete the temp clone. Do NOT copy framework-meta files (.git/, .github/, tests/, README.md, CHANGELOG.md, CONTRIBUTING.md, LICENSE).

STEP 2 — Run /initSumela. In a fresh project your IDE may NOT yet register this as a slash command (it lives in .sumela/skills/, and AGENTS.md does not exist yet — /initSumela generates it), so if "/initSumela" does not resolve, just READ and FOLLOW .sumela/skills/init-sumela/SKILL.md directly. In a single pass it:
  • auto-detects the stack, architecture, and code conventions;
  • if you ALREADY have agent config (an AGENTS.md, custom skills/rules, or a docs/second-brain/), runs a NON-DESTRUCTIVE merge: it quarantines your originals to .sumela/_migration/<date>/, proposes a plan, and folds the useful parts into the SumelaOS structure after you approve — it never overwrites your work, and never touches your general docs/;
  • asks the three languages (interaction / code naming / documentation) and the governance mode (solo | team);
  • asks which optional memory plugins to install (Qdrant, Graphify) — if you opt in, it then runs scripts/setup-memory.sh to bring the runtime up: auto-installs the safe deps and CONFIRMS each invasive step (start Qdrant via Docker, pull the Ollama model, install the graphify CLI), so you do no manual setup; if you decline, it installs and runs nothing for them;
  • generates AGENTS.md, the rules, RULE_REGISTRY.md, the wiki, and the IDE pointers;
  • wires the git hooks (core.hooksPath), seeds the .gitignore per-developer/runtime + secret baselines and the .gitattributes union-merge;
  • (team mode) sets up CODEOWNERS, and optionally adds the CI validation workflow.

Just run /initSumela and answer its prompts — do not re-ask what it already asks.
```

The agent will:
1. Copy the framework into your project (bootstrap, or a complete manual copy)
2. Auto-detect your tech stack, architecture, and code conventions
3. Ask your languages, governance mode, optional memory plugins (Qdrant, Graphify), and — in team mode — your business-domain taxonomy
4. Generate AGENTS.md, rules, registries, wiki, and IDE pointers — then wire git hooks, seed the per-developer/runtime + secret .gitignore baselines and the .gitattributes union-merge, and (team mode) CODEOWNERS + optional CI

### Joining a Project — Teammate Onboarding Prompt

Different from the install prompt above. Use this when the project **already has SumelaOS committed** and you just `git clone`d / `git pull`ed it. The shared, tracked config (AGENTS.md, rules, the domain taxonomy, registries, hooks files) is already there — you only need to wire the **per-developer** pieces. Paste this to your agent:

```
Onboard me onto this project's SumelaOS setup. Run /onboardSumela — if it doesn't resolve
as a slash command, read and follow .sumela/skills/onboard-sumela/SKILL.md. It will:
  • wire my git hooks (core.hooksPath) so pre-commit validation + memory-sync run;
  • ask only MY per-developer settings — interaction language and which business domain(s)
    I work in — and write them to .sumela/local.md (gitignored);
  • offer to set up the optional memory runtime (Qdrant/Ollama/graphify) if the team uses it.
Do NOT run /initSumela and do NOT regenerate any team-wide/tracked config.
```

> **Do not run `/initSumela` as a teammate** — that is the first-time installer; it re-detects and regenerates the team-wide config. As a teammate you want `/onboardSumela`, which only touches your local, untracked setup.

### Alternative: One-Command Bootstrap

```bash
# Linux/macOS
curl -sSL https://raw.githubusercontent.com/tolgakisaogullari/SumelaOS/master/scripts/bootstrap.sh | bash

# Windows/PowerShell
git clone --depth 1 https://github.com/tolgakisaogullari/SumelaOS.git $env:TEMP\SumelaOS
pwsh $env:TEMP\SumelaOS\scripts\bootstrap.ps1   # copies .sumela/, scripts/, all IDE templates, second-brain
Remove-Item $env:TEMP\SumelaOS -Recurse -Force
```

Then run `/initSumela` in your AI assistant (if it doesn't resolve as a slash command in a fresh project, tell the agent to read and follow `.sumela/skills/init-sumela/SKILL.md`).

### Adding the memory layer later

Declined Qdrant/Graphify at first setup and want it now? The plugin files already
ship with the framework (bootstrap copies them all), so it's one command — it
registers the plugin and brings its runtime up (auto-safe deps + confirm-and-run
for Docker/Ollama/graphify):

```bash
bash scripts/setup-memory.sh --plugins qdrant-session-memory,graphify-code-graph
# Windows: pwsh scripts/setup-memory.ps1 -Plugins qdrant-session-memory,graphify-code-graph
```

Or just ask your agent to "add the Qdrant and Graphify memory plugins." Re-running
it anytime is safe (idempotent).

## Features

<!-- sumela:skill-count workflows=22 loadable=27 (verified by validate-structure.sh against reconcile-registry.py --stats) -->
- **22 skill workflows** (27 loadable skill files incl. sub-skills) — open-ended ideation (`idea-explore`), brainstorming, planning, TDD, debugging, code review, shipping, and more
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
| **Per-developer config** | Each developer overrides **only** their interaction language and active business **domain(s)** via a gitignored `.sumela/local.md` (copy `.sumela/local.md.example`) — set fastest by running `/onboardSumela` on a fresh clone. Code naming/documentation languages and the domain **taxonomy** stay team-wide for consistency. |
| **Versioned upgrades** | `.sumela/VERSION` + `scripts/update.sh` (and `.ps1`) refresh the framework **core** (prompt, skills, scripts, hooks, universal rules, templates) from upstream — with a per-file diff and your consent — while never touching your **overlay** (AGENTS.md, stack rules, wiki, registries, governance/CI choices). |
| **IDE mirror sync** | Some IDEs need the prompt body verbatim. List those files in `.sumela/mirrors.conf`; `scripts/sync-mirrors.sh` keeps a marker block in each one byte-equal to `sumela-prompt.md`, and pre-commit + CI fail on drift. |
| **Monorepo-ready** | Install at the repo root **or** a subdir — hooks self-anchor to their install. Multiple installs in one repo auto-promote to a root dispatcher (`.sumela-hooks/`) that runs every install's hooks. Rules shared across packages live once in `.sumela-shared/rules/` and `sync-shared-rules.py` distributes + registers them (universal) into each install. See the [ADOPTION_GUIDE §13](docs/second-brain/template/ADOPTION_GUIDE.md). |

Setup tooling wires these per clone — the first developer installs with `setup.sh` / `setup.ps1` / `/initSumela`; each teammate who later pulls the repo runs `/onboardSumela` (see [Joining a Project](#joining-a-project--teammate-onboarding-prompt) above). For step-by-step team adoption, see the [ADOPTION_GUIDE](docs/second-brain/template/ADOPTION_GUIDE.md).

## The Sumela Prompt — Your Agent's Constitution

The most important file in this framework is `.sumela/sumela-prompt.md`. It is the **runtime contract** — the single source of truth that governs how your agent behaves across every session and every IDE.

This file defines:
- **Session bootstrap** — what the agent reads when a session starts
- **Skill and rule loading** — which workflows and constraints are active
- **Information gap routing** — how the agent searches for context (Qdrant, Graphify, wiki, grep)
- **Signal capture** — how the agent learns from corrections and friction
- **Context manifest** — what skills/rules are loaded; shown on request (`/context`) and before high-stakes actions

Every other file in `.sumela/` defers to this prompt when instructions conflict. **You don't need to edit it** — it works out of the box. But if you want to customize how your agent behaves at the deepest level, this is where you do it.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Your Project                    │
│                                                  │
│  AGENTS.md  ◄── IDE pointer files                │
│      │           (CLAUDE.md, .cursor/rules/,     │
│      │            .clinerules, .kilocode/,        │
│      │            .trae/rules/, .opencode/)       │
│      ▼                                           │
│  ┌──────────────────────────────────┐            │
│  │         .sumela/             │            │
│  │  SKILL_REGISTRY.md               │            │
│  │  RULE_REGISTRY.md                │            │
│  │  skills/        (22 workflows)   │            │
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
| OpenCode | `.opencode/AGENTS.md` | Yes |

All pointer files are ≤15 lines (the shipped ones are ~9) and redirect to `AGENTS.md`. Updates go to one file only; pointers never drift.

**The six above are a starter set, not a limit.** The real contract is `AGENTS.md` + `.sumela/`; each pointer is just a ~9-line "read `AGENTS.md` first" redirect. To support a tool that isn't listed, drop one pointer into whatever instruction file that tool auto-reads (or, if it reads `AGENTS.md` natively, nothing at all). So SumelaOS runs in **any agent/IDE that loads a project instruction file** — the same engine, unchanged, behind every pointer.

## What's Included

```
.
├── AGENTS.md.template              # Agent bootstrap template
├── CLAUDE.md.template              # IDE pointer templates
├── .clinerules.template
├── .cursor/rules/00-agent.md.template
├── .kilocode/rules.md.template
├── .trae/rules/00-agent.md.template
├── .opencode/AGENTS.md.template
├── scripts/
│   ├── setup.sh / setup.ps1        # Interactive setup
│   ├── bootstrap.sh / bootstrap.ps1 # One-command install
│   ├── validate-structure.sh       # Structure validation (CI + pre-commit run this)
│   ├── status.sh / status.ps1      # Read-only health report (version, drift, queue, hooks)
│   ├── update.sh / update.ps1      # Refresh framework core (keeps your overlay)
│   ├── setup-memory.sh / .ps1      # Bring up Qdrant/Ollama/graphify (auto-safe + confirm-invasive)
│   ├── reconcile-registry.py       # Auto-register on-disk skills into SKILL_REGISTRY.md
│   ├── sync-shared-rules.py        # Distribute .sumela-shared/rules/ into each install (monorepo)
│   ├── sync-mirrors.sh / .ps1      # Keep verbatim IDE mirrors in sync
│   └── auto-update-memory.py       # Memory-stack maintenance orchestrator
├── tests/
│   └── smoke.sh                    # End-to-end setup test (run + idempotency); CI runs it
├── .github/workflows/
│   └── sumela-validate.yml         # Opt-in CI: structure + smoke test
├── .sumela/
│   ├── VERSION                     # Core framework version (for update.sh)
│   ├── SKILL_REGISTRY.md           # Skill catalog
│   ├── RULE_REGISTRY.md.template   # Rule catalog template
│   ├── skills/                     # 22 workflows · 27 loadable skill files
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
| **No workflow structure** | Agent improvises each task | 22 skill workflows define structured procedures (ideate → brainstorm → plan → implement → review → ship) |
| **No coding standards** | Agent uses its own defaults | Project-specific rules enforce your conventions |
| **No session memory** | Every session starts from zero | Qdrant plugin remembers past decisions; on a team, summaries sync to every developer via git hooks |
| **No code structure awareness** | Agent greps blindly | Graphify plugin understands call graphs and dependencies |
| **No knowledge capture** | Knowledge lives in chat history | Second-brain wiki captures decisions, entities, and architecture |
| **No self-improvement** | Same mistakes repeat | `/evolve` command captures friction signals and applies learnings |
| **IDE lock-in** | Different configs per IDE | One `AGENTS.md` serves all IDEs via thin pointer files |
| **Team merge conflicts** | Everyone edits the same memory/queue files | Union-merge logs + one-file-per-signal queue + per-developer overrides |
| **Ungoverned agent standards** | One dev's correction silently becomes everyone's rule | Team mode routes rule/skill/schema changes through a reviewed PR (CODEOWNERS) |
| **Drift & decay** | Structure rots; framework updates clobber customizations | Pre-commit + CI enforce the contract; `update.sh` upgrades the core, never the overlay |

## How SumelaOS Extends Superpowers

SumelaOS's skill engine is a fork of [obra/superpowers](https://github.com/obra/superpowers) — the project that pioneered structured agent workflows. We kept all 14 of its skill workflows verbatim and built **8 more** on top, then layered on systems Superpowers does not ship (rules, knowledge base, memory, governance). The table below is an honest side-by-side — including where Superpowers is still broader.

| Capability | [Superpowers](https://github.com/obra/superpowers) | SumelaOS |
|---|---|---|
| **Skill workflows** | 14 | **22** — the same 14 + 8 added: `secure-coding-standard`, `performance-optimization`, `shipping-and-launch`, `using-second-brain`, `self-improvement-curator`, `context-handoff`, `init-sumela`, `onboard-sumela` |
| **Code review** | Single reviewer subagent | **3-lane parallel panel** — Correctness & Security (incl. auth/credential token lifecycle) · Design & Contracts · Integration & Operations — synthesized with an AND-gate (any lane's Critical blocks) |
| **Rule framework** | TDD / YAGNI / DRY as methodology | Phase-to-rule matrix: universal + stack-specific rules loaded per active phase & stack |
| **Knowledge base** | — | Second-brain wiki (Karpathy LLM-Wiki pattern): raw sources → artifacts → live wiki |
| **Session memory** | — | Optional Qdrant semantic memory; on a team, summaries sync to every dev via git hooks |
| **Code-graph awareness** | — | Optional Graphify call-graph + impact analysis, queried before changes |
| **Self-improvement** | — | `/evolve` loop: captures correction/friction signals → governed application |
| **Team governance** | — | `solo \| team` modes; `/evolve` routes rule/skill/schema changes through a CODEOWNERS-reviewed PR; per-developer language overrides |
| **Context visibility** | — | Context Manifest (loaded skills/rules + GAPS) on request and before high-stakes actions |
| **Harness / IDE support** | Ready-made installers for 8 named harnesses (Codex CLI/App, Factory Droid, Gemini CLI, Copilot CLI, …) | **IDE-agnostic by design** — one `AGENTS.md` + a ~15-line pointer per tool. 6 shipped as examples (Claude Code, Cursor, Cline, Kilo Code, Trae, OpenCode); **any** other tool that reads a project instruction file works by dropping in a pointer (or reading `AGENTS.md` natively) — the list is a starter set, not a ceiling |

In short: **Superpowers is the skill engine; SumelaOS is that engine plus the memory, rules, knowledge, and governance layers a team needs** — delivered through a single `AGENTS.md` that any tool consumes via a thin pointer, so harness coverage is a starter list, not a ceiling. Superpowers ships turnkey installers for more *named* harnesses today; SumelaOS's pointer model is designed to reach any of them (and any future tool) by adding one redirect file.

## Credits & Foundations

SumelaOS builds on the work of two exceptional open-source projects:

### [obra/superpowers](https://github.com/obra/superpowers) — The Skill Engine

The core skill architecture — the universal skills covering brainstorming, planning, TDD, debugging, code review, shipping, and more — is based on [Superpowers](https://github.com/obra/superpowers) by [obra](https://github.com/obra). Superpowers introduced the concept of structured agent workflows: instead of letting the agent improvise, skills define step-by-step procedures that enforce quality gates, security checks, and user approval points.

**What we added on top:**
- **Rule framework** with phase-to-rule matrix (universal + stack-specific rules)
- **Second-brain wiki** with Karpathy LLM Wiki pattern for knowledge capture
- **Self-improvement loop** (`/evolve`) for capturing and applying learnings
- **Context Manifest** protocol for on-demand and pre-high-stakes transparency
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
