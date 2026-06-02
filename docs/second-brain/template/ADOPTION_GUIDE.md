# Second Brain Adoption Guide

> **Primary audience:** AI coding agents (Claude Code, Cursor, Cline, Kilo Code, Trae, or any AGENTS.md-compatible agent). Secondary audience: human users reviewing the output.
>
> This guide provides step-by-step instructions for adopting the Karpathy LLM Wiki second brain template in both new (greenfield) and existing (brownfield) projects.

---

## 1. Overview

This template implements Andrej Karpathy's LLM Wiki pattern — a three-layer knowledge system:

- **`raw_sources/`** — Immutable. User-provided source materials (articles, meeting notes, screenshots).
- **`artifacts/`** — Immutable. LLM-generated write-once documents (plans, specs).
- **`wiki/`** — Live. Continuously updated synthesis layer maintained by the agent.

The template includes 4 wiki special files (`_INDEX.md`, `_LOG.md`, `_SCHEMA.md`, `_SEARCH_INDEX.md`), the `_improvement-queue/` directory (one `IMP-*.md` per signal — team-safe, no merge conflicts), one starter page (`active-project-context.md`), and empty directory scaffolding for sources and artifacts.

Companion components (not included in this template but required for full functionality):
- `AGENTS.md` — Canonical agent bootstrap file at repo root
- `.sumela/` — Portable skill engine with `SKILL_REGISTRY.md`
- IDE pointer files — Thin redirects so each IDE discovers `AGENTS.md`

---

## 2. Prerequisites

### Core (required for all setups)

| Requirement | Purpose |
|---|---|
| Git | Version control — the agent uses git for branch management, history, and handoff |
| Any AGENTS.md-compatible IDE | Agent runtime — Claude Code, Cursor, Cline, Kilo Code, Trae, or any IDE that reads `AGENTS.md` |

No build tools, databases, Python, or runtime dependencies are required for the core second brain + skill engine.

### Memory Plugins (optional — activate only what your environment supports)

| Requirement | Plugin | Purpose |
|---|---|---|
| Python 3.10+ | Both plugins | Script runtime for Qdrant and Graphify integrations |
| Qdrant + Ollama (`qwen3-embedding:0.6b`) | `qdrant-session-memory` | Tier-1 semantic search over past session summaries |
| `graphify` CLI + Node.js | `graphify-code-graph` | Tier-2 structural code graph (callers, callees, impact analysis) |

If no plugins are active, the agent degrades gracefully to Tier-3 (`_SEARCH_INDEX.md` keyword search) + Tier-4 (grep fallback). See [Plugin Activation](#11-plugin-activation) for setup instructions.

---

## 3. Mode A: Greenfield Project Adoption

Use this mode when starting a **new project** with no existing codebase or wiki.

### A.1. Copy the template

```bash
cp -r <source>/docs/second-brain/template/ <your-project>/docs/second-brain/
```

Or manually create the directory structure matching `README.md`.

### A.2. Create `AGENTS.md` at repo root

Write a canonical agent bootstrap file. Include:

1. **Project identity** — project name, one-line purpose.
2. **Language protocol** — which language for user interaction vs. code/comments (configurable per project).
3. **Eager-load directives** — instruct agent to read on session start:
   - `.sumela/SKILL_REGISTRY.md`
   - `docs/second-brain/wiki/_INDEX.md`
   - `docs/second-brain/wiki/_SCHEMA.md`
   - `docs/second-brain/wiki/active-project-context.md`
   - `docs/second-brain/wiki/_improvement-queue/` (check pending count)
4. **Skill resolution protocol** — reference `.sumela/SKILL_REGISTRY.md`.
5. **Security mandate** — reference `secure-coding-standard` skill.
6. **Signal capture** — enable `self-improvement-curator` skill.

### A.3. Create IDE pointer files

Create thin pointer files for each IDE you use. Each file should be ≤15 lines and contain only:

```markdown
# [IDE Name] Agent Configuration

> **This is a pointer file.** Canonical agent instructions live in `AGENTS.md` at
> the project root. Read that file first.

**Directives:**
1. Read `AGENTS.md` — it is the single source of truth.
2. Follow `.sumela/SKILL_REGISTRY.md` for skill resolution.
3. Do not duplicate instructions across IDE-specific files.
```

Files to create:
- `CLAUDE.md` (root) — for Claude Code
- `.cursor/rules/00-agent.md` — for Cursor
- `.clinerules` — for Cline
- `.kilocode/rules.md` — for Kilo Code
- `.trae/rules/00-agent.md` — for Trae

### A.4. Initialize `active-project-context.md`

Replace all placeholder values:
- `[Project Name]` → your project name
- `YYYY-MM-DD` → today's date
- Add initial project state under "Aktif Çalışma"

### A.5. Copy `.sumela/` skill engine

Copy the entire `.sumela/` directory from the source project. This includes:
- `SKILL_REGISTRY.md` — skill catalog
- `skills/` — all skill definitions
- `rules/` — portable rule files (customize per project)
- `learned-rules/` — empty initially; populated by `self-improvement-curator`

### A.6. Run validation

```bash
bash scripts/setup.sh    # Mac/Linux
# OR
powershell -File scripts/setup.ps1   # Windows
```

### A.7. First commit

```bash
git add docs/second-brain/ .sumela/ AGENTS.md CLAUDE.md .cursor/ .clinerules .kilocode/ .trae/
git commit -m "feat(meta): initialize second brain + skill engine"
```

---

## 4. Mode B: Brownfield Project Adoption

Use this mode when adding the second brain to an **existing project** with code already in development. The agent must extract knowledge from the codebase rather than starting blank.

### B.1. Repository Reconnaissance

The agent MUST perform these reads before writing any wiki page:

1. **Read `README.md`** (or equivalent) — extract project purpose, tech stack, setup instructions.
2. **Read top-level directory structure** — `ls` or `tree` at depth 2 to understand module organization.
3. **Read `package.json` / `*.csproj` / `Cargo.toml` / `go.mod`** — extract dependencies, framework versions.
4. **Read recent git log** — `git log --oneline -30` to understand recent activity, active features, team conventions.
5. **Read any existing documentation** — `docs/`, `wiki/`, `CONTRIBUTING.md`, `ARCHITECTURE.md`.

<!-- INFERRED FROM CODE, NEEDS CONFIRMATION -->
Mark all extracted information with this comment until the user confirms.

### B.2. Entity & Architecture Discovery

From the code analysis, build an initial understanding of:

- **Architecture pattern** — monolith, microservices, clean architecture, MVC, etc.
- **Domain entities** — primary data models, their relationships.
- **API surface** — endpoints, authentication, versioning.
- **Infrastructure** — database, cache, message queue, cloud services.
- **Tech debt signals** — TODO/FIXME comments, deprecated patterns, known issues.

**CRITICAL RULES:**
- **NEVER guess.** If information is ambiguous, ask the user.
- Mark all inferred content with `<!-- INFERRED FROM CODE, NEEDS CONFIRMATION -->`.
- Limit initial wiki to **5-10 pages** maximum. Expand incrementally.
- Defer architectural decisions to `/evolve` review — do not commit to interpretations.

### B.3. Initial Wiki Page Synthesis

Create pages in this order (skip any that don't apply):

1. `active-project-context.md` — current state, recent activity, next steps
2. `architecture-and-stack.md` — tech stack, architecture pattern, layer boundaries
3. `domain-entities.md` — primary entities and relationships
4. `developer-onboarding.md` — setup instructions, required tools, environment variables
5. `api-registry.md` — endpoint catalog (if API project)
6. `tech-debt-and-known-issues.md` — seeded from TODO/FIXME markers + recent bugfix commits
7. `architecture-decisions.md` — skeleton with inferred decisions (awaits user confirmation)

**User confirmation loop:**
```
Agent: "I've analyzed the codebase and drafted 6 initial wiki pages.
        Here's a summary of what I inferred:
        - [list key findings]
        Shall I show you each page for review, or should I proceed
        and you'll review via git diff?"
User:  [confirms or requests changes]
```

### B.4. Tech Debt & Known Issues Seeding

Scan the codebase for:
- `TODO`, `FIXME`, `HACK`, `XXX` comments → extract and categorize
- Recent bugfix commits (git log `--grep="fix"`) → identify recurring problem areas
- Deprecated dependencies → flag for upgrade

Create `tech-debt-and-known-issues.md` with prioritized items (High / Medium / Low).

### B.5. Finalize and Validate

1. Update `_INDEX.md` with all created pages.
2. Update `_SEARCH_INDEX.md` with key terms for each page.
3. Append a `migration` entry to `_LOG.md`: `## [YYYY-MM-DD] migration | Initial second brain adoption from existing codebase`.
4. Run `scripts/setup.sh` or `setup.ps1` to validate structure.
5. Commit all wiki files.

---

## 5. Mode C: Team Onboarding

Use this mode when a **new team member** joins a project that already has SumelaOS set up. No template copying or project configuration is needed — but a few **one-time local steps** wire the per-developer pieces (git hooks, optional memory, your language), because git does not share those automatically.

### C.1. One-Time Local Setup (run once per clone)

Fastest path — re-run setup; it wires everything idempotently and won't overwrite the project's committed config:

```bash
bash scripts/setup.sh        # or: powershell scripts/setup.ps1
```

Or do the equivalent by hand:

1. **Wire the git hooks** (required — hooks are NOT shared by git). Enables the pre-commit validation, the IDE-mirror drift check, and team memory sync:
   `git config core.hooksPath .sumela/git-hooks`
2. **Shared memory** (only if your team uses the Qdrant plugin): so teammates' committed session summaries sync into *your* local Qdrant on `git pull`, install Python 3.10+, a local Qdrant, and Ollama with `qwen3-embedding:0.6b`, then `pip install -r .sumela/memory-plugins/qdrant-session-memory/requirements.txt`. See [Plugin Activation](#11-plugin-activation). Without it, the lower memory tiers still work.
3. **Your interaction language** (optional): copy `.sumela/local.md.example` to `.sumela/local.md` and set `interaction_language`. It's gitignored, so your choice doesn't change the team config; code naming/documentation stay team-wide.
4. **Know the governance mode:** check `AGENTS.md` §8 (`governance: solo | team`). In **team** mode, your `/evolve` changes to the agent-control surface (rules, skills, prompt, schema) open a **pull request** for a code owner to review instead of applying directly.

### C.2. Read the Core Files

The agent (or human) reads these files in order on the first session:

1. **`AGENTS.md`** (repo root) — project identity, language protocol, developer commands, architecture conventions.
2. **`.sumela/SKILL_REGISTRY.md`** — discover all available skills (eager and lazy).
3. **`docs/second-brain/wiki/active-project-context.md`** — current sprint state, active work, recent decisions.
4. **`docs/second-brain/wiki/_improvement-queue/`** — check pending count. If > 0, review with `/evolve`.

### C.3. What to Expect on First Session

The agent will automatically:

1. **Run the full bootstrap sequence** (per `sumela-prompt.md`):
   - Read `SKILL_REGISTRY.md` + `RULE_REGISTRY.md`
   - Read `_INDEX.md` + `active-project-context.md`
   - Check `_improvement-queue/` pending count
   - Eager-load 2 skills: `using-superpowers` (dispatcher) + `context-handoff` (context-pressure guardian)
   - Load applicable rules based on phase + stack scope
2. **Print a Context Manifest** — this is the first user-facing output. It shows: active skills, loaded rules, detected stack scope, and any rule gaps. Review it to confirm the agent understood the project correctly.
3. **Report readiness** — if any expected file is missing, the agent will flag the gap.

### C.4. How to Contribute

| Action | Method |
|---|---|
| Add a new skill | Follow the `writing-skills` skill — create `SKILL.md` under `.sumela/skills/<name>/`, register in `SKILL_REGISTRY.md` |
| Add a new rule | Use `/evolve` — the agent creates the rule file, registers it in `RULE_REGISTRY.md`, and updates the phase-to-rule matrix |
| Report friction or a correction | Use `/evolve` — the agent captures the signal as a new file in `_improvement-queue/` for review |
| Ingest a new source document | Place in `docs/second-brain/raw_sources/`, then trigger ingest via the `using-second-brain` skill |

In **team** governance mode, `/evolve`'s rule/skill/schema changes don't land directly — they open a pull request for a code owner (`CODEOWNERS`) to review before they become everyone's standard. The pre-commit hook and CI also run the structure + mirror-drift checks on your commits; bypass an individual commit with `git commit --no-verify`.

### C.5. Staying Current

Pull framework improvements without losing your project's customizations:

```bash
bash scripts/update.sh --dry-run    # preview
bash scripts/update.sh              # apply (diff + consent per changed core file)
```

It refreshes the framework **core** and never touches your **overlay** (AGENTS.md, stack rules, wiki, registries, governance/CI choices, `.sumela/local.md`). See [Upgrading SumelaOS](#upgrading-sumelaos-core-vs-overlay).

---

## 6. IDE Pointer Configuration

Each IDE has a different discovery mechanism. Create only the files relevant to your IDE(s):

| IDE | File | Auto-discovered? |
|---|---|---|
| Claude Code | `CLAUDE.md` (root) | Yes — reads on session start |
| Cursor | `.cursor/rules/00-agent.md` | Yes — loads rule files from `.cursor/rules/` |
| Cline | `.clinerules` (root) | Yes — reads on session start |
| Kilo Code | `.kilocode/rules.md` | Yes — reads on session start |
| Trae | `.trae/rules/00-agent.md` | Yes — loads rule files from `.trae/rules/` |

All pointer files use the identical template from Section 3.3 above. Updates go to `AGENTS.md` only; pointers never drift.

**`.gitignore` considerations:**
- `.kilocode/*` should be ignored EXCEPT `!.kilocode/rules.md`
- `.cursor/` generally tracked (rules are shared)
- `.trae/` generally tracked (rules are shared)

---

## 7. Project Identity Customization

After copying the template, customize these project-specific values:

### In `AGENTS.md`:
- **Project name** — replace with your project's name
- **Project purpose** — one-line description
- **Language protocol** — set the team-wide interaction language (e.g., Turkish, English, Japanese) plus code naming and documentation languages (typically English). The interaction language is a **default**: each developer can override their own by copying `.sumela/local.md.example` to `.sumela/local.md` (gitignored) and setting `interaction_language`. Code naming/documentation stay team-wide and are not locally overridable.
- **Tech stack summary** — frameworks, languages, databases

### In `active-project-context.md`:
- Replace `[Project Name]` in the title
- Fill in current sprint/project state
- Add relevant reference links

### In `.sumela/rules/`:
- Review each rule file — remove project-specific rules that don't apply
- Keep generic rules (architecture patterns, security, git workflow)
- Add new rules specific to your project's conventions

---

## 8. First Session Expectations

When an agent loads the project for the first time after adoption, it runs the full bootstrap sequence (defined in `sumela-prompt.md`):

1. **Read discovery surfaces** — `SKILL_REGISTRY.md` + `RULE_REGISTRY.md`.
2. **Second-brain init** — `_INDEX.md` → `active-project-context.md` → last 5 `_LOG.md` entries → pending count in `_improvement-queue/`.
3. **Eager-load 2 skills** — `using-superpowers` (top-level dispatcher) + `context-handoff` (context-pressure guardian). All other skills load lazily on demand.
4. **Load applicable rules** — universal rules always, phase-conditional rules based on active phase, stack-conditional rules based on detected scope.
5. **Print Context Manifest** — the first user-facing output. Shows: active skills, loaded rules, detected stack scope, and any rule gaps. Review it to confirm the agent understood the project correctly.
6. **Check `_improvement-queue/`** — if pending count > 0, the agent notifies you (in the project's interaction language) and offers to review via `/evolve`.

If any expected file is missing, the agent flags the gap and offers to create it.

---

## 9. Ongoing Maintenance

### Periodic Tasks

| Task | Frequency | Trigger |
|---|---|---|
| Update `active-project-context.md` | Every sprint/milestone completion | `finishing-a-development-branch` skill |
| Update `_SEARCH_INDEX.md` | Every ingest, code-commit, lint | Automatic during wiki operations |
| Append to `_LOG.md` | Every significant operation | Automatic |
| Review `_improvement-queue/` | When pending count > 0 | `/evolve` command |
| Lint wiki (check parity, orphans) | Monthly or when prompted | Manual or lint trigger in `using-second-brain` |
| Archive old `_LOG.md` entries | When entry count > 50 | During lint (see `_SCHEMA.md` Section 11) |

### CI & Pre-Commit Enforcement

The structure contract is enforced automatically, not just by convention:

- **CI (opt-in):** `setup.sh --ci` / `setup.ps1 -Ci` (or answering `y` at the setup prompt) adds `.github/workflows/sumela-validate.yml`, which runs `bash scripts/validate-structure.sh --check-placeholders` (+ shell syntax) on every push/PR. It is **not** created by default — enable it only if you want GitHub Actions enforcement (the pre-commit hook below works regardless).
- **Pre-commit:** when `core.hooksPath` is wired (setup does this), `.sumela/git-hooks/pre-commit` runs the same validation locally before a commit that touches the agent-control surface — plus an **IDE-mirror drift check** (`sync-mirrors.sh --check`, a no-op unless you maintain mirrors). Bypass an individual commit with `git commit --no-verify`.

**Not on GitHub Actions?** The check is just one script — wire it into your CI:

```yaml
# GitLab CI (.gitlab-ci.yml)
sumela-validate:
  image: ubuntu:latest
  before_script: [ "apt-get update -qq && apt-get install -y -qq git python3" ]
  script:
    - bash scripts/validate-structure.sh --check-placeholders
    - bash scripts/sync-mirrors.sh --check
```

```yaml
# Azure Pipelines
- script: bash scripts/validate-structure.sh --check-placeholders
  displayName: SumelaOS Validate
- script: bash scripts/sync-mirrors.sh --check
  displayName: SumelaOS Mirror Drift Check
```

### Upgrading SumelaOS (core vs overlay)

The framework evolves. To pull CORE improvements without clobbering your project's
OVERLAY, run the updater (it never touches your AGENTS.md, stack rules, wiki,
registries, governance/CI choices, or `.sumela/local.md`):

```bash
bash scripts/update.sh --dry-run    # preview what would change
bash scripts/update.sh              # apply (diff + consent for any locally-changed core file)
bash scripts/update.ps1             # Windows
```

- **CORE** (refreshed): `sumela-prompt.md`, `skills/`, `git-hooks/`, the seven
  universal rules, `scripts/*`, `docs/second-brain/template/`, and installed
  memory-plugins. Version-gated on `.sumela/VERSION`.
- **OVERLAY** (never touched): `AGENTS.md`, `RULE_REGISTRY.md`, `SKILL_REGISTRY.md`,
  your stack rules (`backend_standards.md`, …, `operational_excellence_maintenance.md`),
  `docs/second-brain/wiki/*`, `.sumela/local.md`, `.gitignore`/`.gitattributes`,
  IDE pointers, CODEOWNERS, CI workflow.
- After an update that added/removed skills or rules, reconcile the registries by hand
  (or re-run `/initSumela`'s registry step). If `_SCHEMA.md` changed, diff/copy
  `docs/second-brain/template/wiki/_SCHEMA.md` → `docs/second-brain/wiki/_SCHEMA.md`.

**IDE mirrors:** if some IDE entrypoints carry the prompt body verbatim, list them in
`.sumela/mirrors.conf` (copy `.sumela/mirrors.conf.example`) and run
`scripts/sync-mirrors.sh` to regenerate them from `sumela-prompt.md` (`--init` scaffolds
a missing one). Pre-commit and CI run `sync-mirrors.sh --check` to fail on drift.

### Wiki Hygiene Rules

- **Never delete pages** — archive them (`wiki/archive/`).
- **Never overwrite contradictions** — note them explicitly (see `_SCHEMA.md` Section 9).
- **Keep `_INDEX.md` compact** — ≤100 lines. Move completed sprint details to archive.
- **Update frontmatter `date_updated`** on every page edit.

---

## 10. Scale Path — Four-Tier Memory Stack

As your wiki and codebase grow, the search strategy evolves. Each tier activates independently — you can run with just Tier 3 + 4 forever, or promote tiers as you hit each threshold.

| Wiki Size | Recommended Stack | Action |
|---|---|---|
| 0–300 pages | Tier 3 (`_SEARCH_INDEX.md`) + Tier 4 (grep) | None needed |
| 300+ pages OR session memory needed | + Tier 1 (Qdrant) — semantic session search | Set up Ollama + Qdrant + run `scripts/session-ingest.py` after each session |
| Code-heavy projects (any size) | + Tier 2 (Graphify) — structural code search | Install `graphify` CLI; run `scripts/auto-update-memory.py` after each commit |
| 1000+ pages | All four tiers; Qdrant + Graphify primary, `_SEARCH_INDEX.md` secondary | Multi-collection Qdrant (chat_history + wiki_pages + code_chunks) |

To activate Tier 1 (Qdrant semantic session memory):
1. Install Qdrant locally (`docker run -p 6333:6333 qdrant/qdrant`) and Ollama with `qwen3-embedding:0.6b`.
2. `pip install qdrant-client requests` in your project's Python env.
3. Run `scripts/setup-qdrant.py` once to create collections.
4. Each session-end, agent runs `scripts/session-ingest.py <summary.md>` (auto-invoked by `context-handoff` skill).

To activate Tier 2 (Graphify structural search):
1. Install `graphify` CLI: `uv tool install graphifyy` (PyPI package `graphifyy` — see [graphify repo](https://github.com/safishamsi/graphify)).
2. Run `/graphify .` in your IDE or `graphify .` in terminal to seed `graphify-out/graph.json`.
3. Optional: `graphify hook install` for auto-rebuild on commit.
4. After each commit, agent invokes `scripts/auto-update-memory.py` (auto via `finishing-a-development-branch`).

**Routing rules** for which tier handles which query type live in the `using-second-brain` skill, not in this guide — keep skill as single source of truth.

---

## 11. Plugin Activation

Memory plugins are optional add-ons that enhance agent recall. Each plugin is a self-contained package under `.sumela/memory-plugins/<name>/` with its own `SKILL.md`, scripts, and dependencies.

### Enabling a Plugin After Initial Setup

1. **Install dependencies:**
   ```bash
   pip install -r .sumela/memory-plugins/<plugin-name>/requirements.txt
   ```

2. **Register in `SKILL_REGISTRY.md`** — add a `<skill>` entry before the closing `</available_skills>` tag:
   ```xml
   <skill activation="lazy">
   <name><plugin-name></name>
   <description>Memory plugin — see `.sumela/memory-plugins/<plugin-name>/SKILL.md` for routing and prerequisites.</description>
   <path>.sumela/memory-plugins/<plugin-name>/SKILL.md</path>
   </skill>
   ```

3. **Ensure external services are running** (Qdrant, Ollama, graphify CLI — see plugin's `README.md`).

4. **Run the plugin's setup script** (if available):
   ```bash
   python .sumela/memory-plugins/<plugin-name>/scripts/setup-qdrant.py
   ```

The `setup.sh` / `setup.ps1` script automates steps 1-2 for all selected plugins during initial setup.

### Disabling a Plugin

1. Remove the plugin's `<skill>` entry from `.sumela/SKILL_REGISTRY.md`.
2. Optionally remove the plugin directory from `.sumela/memory-plugins/`.
3. The agent degrades gracefully — queries fall through to the next tier.

### Plugin Health Check

| Plugin | Verify Command | Expected Output |
|---|---|---|
| `qdrant-session-memory` | `python .sumela/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "test" --limit 1` | JSON results (may be empty if no sessions ingested yet) |
| `graphify-code-graph` | `python .sumela/memory-plugins/graphify-code-graph/scripts/query-graph.py "main" --depth 1` | Callers/callees list or "No matches" |

If either command fails with a connection error, check that the external service (Qdrant on `localhost:6333`, graphify CLI on PATH) is running.

---

## 12. Troubleshooting

### Agent doesn't read `AGENTS.md`

- **Cause:** IDE pointer file missing or misconfigured.
- **Fix:** Verify the pointer file exists for your IDE (Section 6). Ensure it contains the directive to read `AGENTS.md`.

### Two improvement-queue entries with the same ID

- **Cause:** Extremely rare random-suffix clash in `IMP-YYYYMMDD-<short>` (there is no
  shared counter to desync — concurrent captures create separate files). Typically
  surfaces as a git **add/add conflict** on the same `IMP-*.md` path during merge.
- **Fix:** Rename one entry file to a fresh `IMP-YYYYMMDD-<short>` and update its `id:`
  frontmatter to match, then re-add. IDs are the filename; never reuse one.

### Wiki pages have no frontmatter

- **Cause:** Page created without following `_SCHEMA.md` template.
- **Fix:** Add YAML frontmatter per `_SCHEMA.md` Section 3. Run lint to catch all non-conforming pages.

### `_SEARCH_INDEX.md` out of sync with `_INDEX.md`

- **Cause:** Pages added to one but not the other.
- **Fix:** Run a lint operation — the `using-second-brain` skill checks parity between the two files.

### `setup.sh` / `setup.ps1` reports missing files

- **Cause:** Incomplete template copy or directory structure.
- **Fix:** Re-copy missing files from template. Check that `.gitkeep` files are present in empty directories.

### Agent creates duplicate wiki pages

- **Cause:** `_INDEX.md` not read before page creation.
- **Fix:** Ensure `_INDEX.md` is in the agent's eager-load list. The agent should always check existing pages before creating new ones.

### Brownfield adoption: agent guesses incorrectly

- **Cause:** Insufficient codebase analysis or skipped user confirmation.
- **Fix:** All inferred content must be marked with `<!-- INFERRED FROM CODE, NEEDS CONFIRMATION -->`. The agent must ask the user to confirm before finalizing. Use `/evolve` to review and correct.
