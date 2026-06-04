---
name: init-sumela
description: "Use when the user says '/initSumela', 'init SumelaOS', 'kur SumelaOS', or 'setup SumelaOS' in an existing project — auto-detects tech stack, architecture, and conventions, then generates AGENTS.md, rules, wiki, and IDE pointers."
---

<purpose>
Automate brownfield adoption of the SumelaOS framework for existing projects. Instead of manually filling templates, the agent reads the project structure, detects the tech stack, identifies architecture patterns and code conventions, and generates all configuration files in one pass.

This is the "zero-config" onboarding experience: one command → fully functional agent framework.
</purpose>

<activation>
LAZY — loaded on demand when the user invokes /initSumela or equivalent.
</activation>

<execution_workflow>
Execute these steps strictly in order. STOP and ask for user confirmation before writing any files.

## PHASE 1 — Project Reconnaissance (silent)

Read the project structure to build a mental model. Do NOT write anything yet.

### Step 1.1: Stack Detection

Scan for manifest/dependency files to identify the tech stack:

| File Found | Stack Detected | Backend | Frontend | Mobile |
|---|---|---|---|---|
| `*.csproj`, `*.sln`, `*.slnx` | .NET | ✅ | | |
| `package.json` with `react-native` or `expo` | React Native / Expo | | | ✅ |
| `package.json` with `react` + `vite`/`next`/`cra` | React | | ✅ | |
| `package.json` with `vue`/`nuxt` | Vue | | ✅ | |
| `package.json` with `angular` | Angular | | ✅ | |
| `go.mod` | Go | ✅ | | |
| `Cargo.toml` | Rust | ✅ | | |
| `pom.xml`, `build.gradle` | Java/Kotlin | ✅ | | |
| `requirements.txt`, `pyproject.toml`, `Pipfile` | Python | ✅ | | |
| `Gemfile` | Ruby | ✅ | | |
| `pubspec.yaml` | Flutter | | | ✅ |
| `docker-compose.yml` | Infrastructure | infra | | |
| `nginx/`, `terraform/`, `k8s/` | Infrastructure | infra | | |

For each `package.json` found, read it to extract: framework, key dependencies, scripts (build/test/lint/dev commands).

For each `*.csproj` found, read it to extract: target framework, key packages, project references.

### Step 1.2: Architecture Detection

Analyze directory structure to identify the architecture pattern:

| Pattern | Indicators |
|---|---|
| **Clean Architecture** | `src/Domain/`, `src/Application/`, `src/Infrastructure/`, `src/Api/` or `src/Presentation/` |
| **MVC** | `Controllers/`, `Models/`, `Views/` or `app/`, `resources/views/` |
| **Microservices** | `services/`, `gateway/`, multiple `Dockerfile`s, `docker-compose.yml` with multiple services |
| **Monorepo** | `packages/`, `apps/`, `libs/`, workspace config (lerna, nx, turborepo, pnpm-workspace) |
| **Modular Monolith** | `modules/`, `features/`, each with own controller/service/repository |
| **Hexagonal/Ports-Adapters** | `ports/`, `adapters/`, `domain/` |
| **Feature-based** | `features/auth/`, `features/users/`, each with own files |
| **Flat** | Single `src/` or `app/` with files organized by type |

### Step 1.3: Convention Detection

Sample 3-5 representative source files to detect:

- **Naming conventions**: PascalCase, camelCase, snake_case for classes, methods, variables
- **File organization**: by-type (controllers/, services/) vs by-feature (auth/, users/)
- **Import style**: relative vs absolute, barrel files (index.ts)
- **Error handling**: try-catch patterns, error middleware, Result pattern
- **Validation**: where and how (middleware, decorators, manual)
- **Testing**: framework (jest, xunit, pytest), file naming (*.test.ts, *_test.go, *Tests.cs), location (co-located or separate)

### Step 1.4: Infrastructure Detection

Scan for:
- **Database**: connection strings in config files, ORM packages (EF Core, Prisma, TypeORM, SQLAlchemy)
- **Cache**: Redis, Memcached references
- **Message broker**: RabbitMQ, Kafka, SQS references
- **Cloud**: AWS/GCP/Azure SDK references, cloud config files
- **CI/CD**: `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`
- **Containerization**: `Dockerfile`, `docker-compose.yml`

### Step 1.5: Code Style Detection

Scan for:
- **Linter config**: `.eslintrc*`, `.prettierrc*`, `.editorconfig`, `pylint`, `golangci-lint`
- **Formatter config**: `prettier`, `black`, `gofmt`, `rustfmt`
- **Type checking**: `tsconfig.json`, `strict` mode, nullable reference types

### Step 1.6: Pre-existing Agent-Artifact Detection (read-only)

The project may ALREADY have agent configuration from prior tooling. Detect it now (do NOT modify anything yet) so PHASE 2c can plan a non-destructive merge. Scan for and record each hit:

- **Existing `AGENTS.md`** at the repo root (the most common collision).
- **Existing skill files**: `.claude/skills/**/*.md`, `.cursor/rules/**`, `.kilocode/rules*`, `.trae/rules/**`, a pre-existing `.sumela/skills/**`, or any directory the user names. Read each skill's intent (name + what it does).
- **Existing rule / coding-standard files**: `CONVENTIONS.md`, `STANDARDS.md`, `.editorconfig`-adjacent docs, a pre-existing `.sumela/rules/**`, or rules embedded in their `AGENTS.md`.
- **Existing `docs/second-brain/`** — ONLY this subpath. Do NOT treat the user's general `docs/` as ours; it is almost always their own project documentation and is classified UNRELATED (never touched).

Classify each hit as: **COLLIDES** (same path/name as something we install), **CUSTOM** (project-specific, no collision — valuable, import candidate), or **UNRELATED** (not an agent artifact → leave untouched). If NOTHING is found, skip PHASE 2c entirely (clean greenfield adoption). If anything is found, PHASE 2c runs.

## PHASE 2 — Analysis Report (user-facing)

Present the detected configuration to the user for confirmation. Render this report in the project's configured interaction language (the example below is the English reference; if the language isn't resolved yet, use English). Format:

```
## 🔍 Project Analysis

### Detected Stack
| Layer | Technology | Detail |
|---|---|---|
| Backend | .NET 10 / C# 14 | ASP.NET Core, EF Core, RabbitMQ |
| Frontend | React 19 / Vite | Tailwind CSS, Shadcn UI |
| Mobile | React Native / Expo | Expo SDK 54, NativeWind v4 |

### Architecture Pattern
Clean Architecture + DDD (light) + CQRS-leaning

### Detected Conventions
- Naming: PascalCase (classes), camelCase (methods)
- Error handling: Global exception middleware
- Validation: FluentValidation at boundaries
- Testing: xUnit, separate test project

### Infrastructure
- Database: PostgreSQL (EF Core)
- Cache: Redis
- Message Broker: RabbitMQ
- CI/CD: GitHub Actions

### Code Style
- TypeScript strict mode enabled
- ESLint + Prettier configured
- Nullable reference types enabled (.NET)

---

Is this correct? Anything that needs fixing?
1. Confirm and continue
2. Make corrections (which part?)
3. Cancel
```

**WAIT for user confirmation.** If user says "2", ask which part to correct and re-analyze. If user says "3", abort.

## PHASE 2a — Language & Governance Configuration (MANDATORY)

After the user confirms the analysis, MUST ask about language preferences. NEVER skip this step — these settings control how the agent communicates, names code, and writes documentation.

```
## 🌐 Language Configuration

The agent needs to know your language preferences for three different contexts:

### 1. Interaction Language
What language should the agent use when talking to you?
(Explanations, questions, status reports, error messages, handoff prompts)

Examples: English, Turkish, German, Spanish, Japanese, Chinese, French, Portuguese

Your choice: ___

### 2. Code Naming Language
What language should code names be in?
(Service names, method names, function names, class names, variable names, file names)

Most teams use English for code names regardless of their interaction language.
Examples: English, Turkish, German

Your choice: ___

### 3. Code Documentation Language
What language should code comments and documentation be in?
(Docstrings, inline comments, XML doc comments, property descriptions, README sections within code)

Examples: English, Turkish, German, Spanish, Japanese

Your choice: ___
```

**Store the answers as:**
- `INTERACTION_LANGUAGE` → e.g., "English", "Turkish", "German" — the team-wide **default**; each developer can override their own interaction language via `.sumela/local.md` (gitignored; copy `.sumela/local.md.example`). Mention this to the user.
- `NAMING_LANGUAGE` → e.g., "English", "Turkish" — team-wide, not locally overridable.
- `DOCUMENTATION_LANGUAGE` → e.g., "English", "Turkish", "German" — team-wide, not locally overridable.

**Common configurations:**

| Scenario | Interaction | Naming | Documentation |
|---|---|---|---|
| International team | English | English | English |
| Turkish team, English code | Turkish | English | English |
| Turkish team, Turkish code | Turkish | Turkish | Turkish |
| German team, English code | German | English | German |
| Japanese team, English code | Japanese | English | Japanese |

**Default suggestion:** If the user seems unsure, suggest "English" for all three — it's the most portable choice.

### Governance mode (MANDATORY)

Also ask how `/evolve` should apply changes to the **agent-control surface** (rules, skills, prompt, schema — the files that change every developer's agent):

```
## 🏛️ Governance Mode

- solo — /evolve applies approved changes directly. Best when one developer owns
         the agent configuration.
- team — /evolve routes changes to rules/skills/prompt/schema through a pull
         request so a code owner reviews them before they become everyone's
         standard. Lower-stakes wiki/active-context changes still apply directly.

Your choice (solo/team): ___
```

**Store as `GOVERNANCE_MODE`** → `solo` (default) or `team`. If the user is unsure or working alone, choose `solo`. Note: this is independent of whether the repo has CODEOWNERS — a solo developer may still use CODEOWNERS on GitHub/Azure, so we ask explicitly rather than auto-detecting.

### Business domains (ONLY when `GOVERNANCE_MODE` is `team`)

If — and only if — the user chose `team`, also ask whether the team organizes work by business **domain**:

```
## 🗂️ Business Domains (optional)

Does your team split work into business domains (e.g. Card, Payments, Onboarding)?
Each domain gets its own rule file that the agent loads — in ADDITION to phase and
stack rules — for developers who work in that domain. Domain is an INDEPENDENT axis
from tech stack (a developer can be backend + Card at once).

List your domains comma-separated, or leave blank to skip (you can add them later
via /onboardSumela or /evolve).

Your domains: ___
```

**Store as `DOMAINS`** (a possibly-empty list). The domain SET is the team-wide, TRACKED taxonomy (it goes into `RULE_REGISTRY.md` `<domain_scopes>` + one rule file each). Which domain(s) a given developer works in is PER-DEVELOPER and UNTRACKED — that is asked during onboarding (`/onboardSumela`), NOT here, and is stored in `.sumela/local.md` `domains:`. In `solo` mode, do NOT ask — leave `DOMAINS` empty.

## PHASE 2b — Memory Plugin Selection (MANDATORY)

After the user confirms the analysis, MUST ask about optional memory plugins. NEVER skip this step.

```
## 🧩 Optional Memory Plugins

SumelaOS comes with two optional memory plugins. They help the agent learn from
past sessions and code structure. Select which ones to install:

| Plugin | What It Does | Requirements |
|---|---|---|
| **Qdrant Session Memory** (Tier-1) | Finds past sessions via semantic search. Answers "what did we decide before?" questions. Indexes code and wiki files. | Python 3.10+, Qdrant, Ollama (qwen3-embedding:0.6b) |
| **Graphify Code Graph** (Tier-2) | Analyzes code call graphs. Answers "where is X used?" and "what breaks if I change X?" questions. | Python 3.10+, graphify CLI (uv tool install graphifyy) |

The framework works without these plugins — Tier-3 (wiki search) and Tier-4 (grep fallback) are always active.

1. Install both (Qdrant + Graphify)
2. Install Qdrant only
3. Install Graphify only
4. Install none (core framework only)
```

**WAIT for user choice.** Store the selection as `PLUGIN_CHOICE`.

**Conditional logic based on PLUGIN_CHOICE** (which directories to COPY):

- If "1" (both): Copy both `.sumela/memory-plugins/qdrant-session-memory/` and `.sumela/memory-plugins/graphify-code-graph/`. Wire git hooks (see Step 3.7). Set `MEM_PLUGINS=qdrant-session-memory,graphify-code-graph`.
- If "2" (qdrant only): Copy only `.sumela/memory-plugins/qdrant-session-memory/`. Wire git hooks. Set `MEM_PLUGINS=qdrant-session-memory`.
- If "3" (graphify only): Copy only `.sumela/memory-plugins/graphify-code-graph/`. Set `MEM_PLUGINS=graphify-code-graph`.
- If "4" (none): Do NOT copy `.sumela/memory-plugins/` at all. Remove memory-plugins references from SKILL_REGISTRY.md in the generated copy. Set `MEM_PLUGINS=` (skip the bootstrap below).

**Bring the runtime up automatically (least manual work — do NOT leave the developer to install Qdrant/Ollama/graphify by hand):**

If `MEM_PLUGINS` is non-empty, ask the user ONE consent question (phrase it in the
configured `interaction_language` — the wording below is the English reference):
> *"Set up the runtime for the memory layer you chose? I'll install the safe/cheap deps (pip) directly and confirm each invasive step with you (start Qdrant via Docker, pull the Ollama model, install the graphify CLI). [Y/n]"*

- If **yes**: run `bash scripts/setup-memory.sh --plugins "$MEM_PLUGINS"` (PowerShell: `pwsh scripts/setup-memory.ps1 -Plugins "$MEM_PLUGINS"`). The script auto-installs the safe deps and CONFIRMS each invasive action (start Qdrant via Docker, pull the Ollama model, install the graphify CLI), reusing anything already present, then creates the Qdrant collections + builds the initial graph. **Relay its summary to the user** in the configured language; any line it could not auto-do is printed with the EXACT one-time command — surface those, never paraphrase them away.
  - If you are running non-interactively (cannot relay the script's own prompts), instead run it with `--yes` after the user agreed above, so the invasive steps are auto-confirmed; or `--non-interactive` if the user wants to start the services themselves (it then prints every exact command instead of running it).
- If **no**: skip the bootstrap; tell the user they can run `bash scripts/setup-memory.sh` anytime — it is idempotent and will confirm each step.

**IMPORTANT:** If the user declined a plugin (choice 2/3/4), do NOT copy its scripts, do NOT register it in SKILL_REGISTRY.md, do NOT run any of its scripts, and do NOT include it in `MEM_PLUGINS`. Never reference an unavailable plugin in generated files.

## PHASE 2c — Brownfield Merge (ONLY if Step 1.6 found pre-existing artifacts)

Skip this entire phase on a clean greenfield project. When existing agent artifacts were detected, run a **non-destructive, propose-and-approve** merge. Governing principles (do NOT violate):

- **Never destroy.** Every original we will replace or fold is first COPIED into a quarantine dir (PHASE 3 Step 3.0) — nothing is overwritten before it is preserved.
- **Scope tightly.** Only ever touch `AGENTS.md`, `.sumela/**`, and `docs/second-brain/**`. NEVER rename, move, or delete the user's general `docs/`, `.claude/`, source, or any UNRELATED file.
- **Integrate, don't dump.** Fold useful content into the matching structured section with a provenance note; do not paste whole legacy files into ours.
- **Propose, then apply.** Present the plan below and get per-item approval BEFORE any write.

### Step 2c.1 — Decompose monolithic / mixed config files

Real-world agent config is often ONE sprawling file (`AGENTS.md`, `CLAUDE.md`, `.clinerules`, `.cursor/rules/*`, `.kilocode/rules*`, …) that JUMBLES everything together — project metadata, reusable procedures (skills), and standing constraints (rules) all inline. Do NOT migrate such a file as a single blob. PARSE it and classify each content block, then route each to its correct home so our structure stays clean and our contract stays intact:

- **Skill-like block** — a reusable procedure/workflow ("when starting a feature do A→B→C", a debugging routine, a release checklist) → destined for `.sumela/skills/<name>/SKILL.md` (+ registry entry).
- **Rule-like block** — a standing constraint/convention → if it is **stack-specific** ("use camelCase in TS", "no console.log in prod") it goes to the matching `.sumela/rules/<stack>_standards.md`; if it is **project-wide / cross-cutting** (e.g., "every PR links an issue", a documentation policy, a dependency-update cadence) it goes to `.sumela/rules/operational_excellence_maintenance.md` (the non-stack operational rule), NOT a stack file. (Commit/branch/PR-review policy usually belongs in the built-in `git_workflow_mandatory_review_protocol` rule — check there first before creating a duplicate.) NEVER into a universal rule (`engineering_philosophy`, `identity_and_behavior`, …). Each gets a RULE_REGISTRY entry (see Step 2c.3 for the metadata contract).
- **Project config / metadata** — stack, build/test/lint commands, architecture, languages, security notes → folded into the generated `AGENTS.md` structured sections.
- **Reference content** — examples/snippets, a domain glossary, a TODO / known-issues list → offer to migrate into the **wiki** (`docs/second-brain/`), not quarantine-and-forget (this content is usually worth keeping searchable).
- **IDE/tool boilerplate** — "read this file first", tool-specific pointer cruft → discard (meaning: NOT folded into our structure; the whole original still survives in quarantine, so nothing is truly deleted). Our pointer system replaces it.
- **Ambiguous / cannot classify confidently** → preserve in quarantine and list under "needs manual review". NEVER guess a destination.

The ORIGINAL file is preserved whole in quarantine regardless of how its blocks were split. Surface the decomposition in the plan below so the user sees exactly where each block lands.

### Step 2c.2 — Present the Migration Plan (user-facing) and WAIT for approval

One row per detected artifact AND per decomposed block:

```
## 🔀 Migration Plan (existing agent config detected)

| Item | Found at | Class | Proposed action |
|---|---|---|---|
| AGENTS.md §"Release flow" | ./AGENTS.md | CUSTOM (skill-like) | Extract to .sumela/skills/release-flow/SKILL.md + register |
| AGENTS.md §"Coding rules"  | ./AGENTS.md | CUSTOM (rule-like)  | Fold into .sumela/rules/backend_standards.md + RULE_REGISTRY row |
| AGENTS.md §"Stack/commands"| ./AGENTS.md | CONFIG             | Fold into generated AGENTS.md sections |
| AGENTS.md §"Read this file" | ./AGENTS.md | BOILERPLATE        | Discard (replaced by our pointer) |
| custom skill `foo`         | .claude/skills/foo | CUSTOM       | Import to .sumela/skills/foo/SKILL.md (normalized) + register |
| skill `brainstorming`      | .cursor/.../  | COLLIDES (built-in) | Keep OURS; quarantine theirs; merge only unique steps if you ask |
| CONVENTIONS.md             | ./CONVENTIONS.md | CUSTOM (rule) | Fold into .sumela/rules/<stack>_standards.md + RULE_REGISTRY row |
| docs/second-brain/         | ./docs/second-brain | COLLIDES  | Rename to docs/second-brain-legacy/, install ours, migrate pages |
| docs/ (general)            | ./docs        | UNRELATED          | Left untouched |
| <can't classify>           | ./AGENTS.md   | AMBIGUOUS          | Quarantine + flag for manual review |

For each row: (1) apply as proposed, (2) skip (leave as-is), (3) modify the action.
```

**WAIT for approval.** Resolve each row before proceeding. Conflicts (e.g., a legacy directive that contradicts the runtime contract / `sumela-prompt` authority hierarchy) are surfaced for an explicit user decision — never silently merged or silently dropped.

### Step 2c.3 — Collision, format & STRUCTURAL-INTEGRITY rules (do NOT break our structure)

Every import MUST conform to our contracts. An import that would break our structure is normalized first or preserved-only — NEVER force-fit:

- **Skill imports** must become a VALID `.sumela/skills/<name>/SKILL.md`: proper frontmatter (`name` = unique kebab-case, `description`) + body in our shape; then registered with a correct `<skill>` entry — run `reconcile-registry.py` (it adds on-disk skills verbatim) or hand-write a matching `<path>`. An import MUST NOT collide with a built-in name (keep ours), alter the registry's pseudo-XML structure, or claim authority over `sumela-prompt.md`.
- **Rule imports** must become a VALID `.sumela/rules/<name>.md` AND get a RULE_REGISTRY entry WITH phase / stack / activation metadata — `reconcile-registry.py` checks domain-conditional rule↔file parity but NOT stack rules or matrix rows, so add the matrix row by hand. The `stack=` value MUST be one of the generated `<stack_scopes>` (Step 3.2): if a rule targets a stack not in scope, either register it under an existing scope or EXTEND `<stack_scopes>` first — otherwise the matrix row is invalid. A **domain**-specific rule uses `activation="domain-conditional"` + `domain="<Domain>"` (the `domain=` value MUST be one of the generated `<domain_scopes>`) and lives at `.sumela/rules/domains/<slug>.md`. Project-wide (non-stack, non-domain) rules need no scope and live in `operational_excellence_maintenance.md` — but note that rule's matrix row has a LIMITED `applies_phases` (planning/branch_finish/shipping by default): if the imported rule must apply in other phases (e.g., code_review, debugging), WIDEN that row's `applies_phases` accordingly, or it won't load when relevant. Project-specific conventions only; the universal rules are off-limits.
- **Skill name clash with a built-in** (one of the 22): NEVER overwrite ours. Quarantine theirs; offer to merge only genuinely-unique steps, or keep theirs as `<name>-legacy`.
- **Cannot normalize without guessing** (unknown execution model, contradictory directives): preserve-only + flag; do not jam it into our format.
- **PROVE integrity after import**: once imports are applied, `python3 scripts/reconcile-registry.py --check` AND `bash scripts/validate-structure.sh --post-setup` MUST pass. These prove the SKILL side, the domain-conditional rule↔file parity, and the repo-hygiene side are intact. NOTE they do NOT deep-validate stack rows or the matrix (reconcile checks only domain rule files), so for each imported stack rule ALSO eyeball that its matrix row is well-formed (valid `stack=`/`activation=`, a real phase). If anything fails, fix or revert the offending import before continuing.

## PHASE 3 — File Generation (after confirmation)

Generate all configuration files (Steps 3.1–3.9 below), presenting a checklist as you go. If PHASE 2c ran, do Step 3.0 FIRST.

### Step 3.0: Quarantine originals (ONLY if PHASE 2c ran)

Before generating/overwriting anything, COPY every original the approved plan will replace or fold into a dated quarantine dir, preserving relative structure:

```
.sumela/_migration/<YYYY-MM-DD>/   (use `date +%Y-%m-%d`)
  ├── AGENTS.legacy.md
  ├── rules/...            (originals)
  ├── skills/...           (originals)
  └── MIGRATION_REPORT.md  (written in PHASE 4)
```

Compute the date ONCE (`date +%Y-%m-%d`) and reuse it for both the quarantine dir and the PHASE 4 report so a run crossing midnight cannot split them. If the dated dir already exists (a same-day re-run), append a `-NN` counter rather than copying onto a prior quarantine — the safety net must never clobber itself.

BEFORE copying anything in, ENSURE `.gitignore` ignores `.sumela/_migration/` — append that exact line if it is missing. Do NOT assume the Step 3.6b block covers it: that block is guarded on `.sumela/local.md`, so a project that adopted SumelaOS before this line existed already has the block and would SKIP it, leaving the quarantine (and its possible legacy secrets) git-trackable. This independent check is what actually guarantees the next bullet.

Copy (not move) so the originals stay in place until their in-place replacement is actually written. **The quarantine dir is in `.gitignore` (ensured just above), so it stays LOCAL and the PHASE 4 commit never stages it** — it may hold secrets from a legacy config; the user reviews it and deletes it when satisfied. (This resolves the otherwise-contradictory "don't auto-commit" note vs. the PHASE 4 `git add` step.)

For an existing `docs/second-brain/`, preserve ONLY the user's content: move their `wiki/`, `raw_sources/`, `artifacts/`, and any loose `*.md` into `docs/second-brain-legacy/`, but LEAVE `docs/second-brain/template/` in place — Step 3.6 copies FROM that template, so sweeping it into legacy would starve the copy. Then materialize our `wiki/` etc. from the template and migrate useful legacy pages across.

Then proceed with the generation steps below, folding/importing per the approved plan and adding a provenance note to each integrated piece (e.g., a trailing `<!-- migrated from <legacy path> on <date> -->`).

### Step 3.1: Generate AGENTS.md

Read `AGENTS.md.template` and fill all `{{placeholders}}`:
- `{{project_name}}` → from repo root directory name or user input
- `{{project_purpose}}` → from README.md one-liner or user input
- `{{tech_stack_summary}}` → from Phase 1 analysis
- `{{interaction_language}}` → `INTERACTION_LANGUAGE` from PHASE 2a (default: English)
- `{{naming_language}}` → `NAMING_LANGUAGE` from PHASE 2a (default: English)
- `{{documentation_language}}` → `DOCUMENTATION_LANGUAGE` from PHASE 2a (default: English)
- `{{governance_mode}}` → `GOVERNANCE_MODE` from PHASE 2a (`solo` or `team`)
- `{{backend_commands}}` → from package.json scripts / csproj commands
- `{{frontend_commands}}` → from frontend package.json scripts
- `{{mobile_commands}}` → from mobile package.json scripts
- `{{infrastructure_commands}}` → from docker-compose.yml or detected infra
- `{{dependency_flow}}` → from architecture pattern detection
- `{{package_boundaries}}` → from directory structure
- `{{naming_conventions}}` → from convention detection
- `{{technical_constraints}}` → from code style detection
- `{{project_specific_security}}` → from security-relevant packages detected

### Step 3.2: Generate RULE_REGISTRY.md

Read `RULE_REGISTRY.md.template` and fill:
- `{{stack_scopes}}` → generate from detected stacks + path patterns
- `{{stack_rules}}` → generate XML rule entries for each detected stack
- `{{domain_scopes}}` → from `DOMAINS` (PHASE 2a). One row per domain: `` | `<Domain>` | Work scoped to the <Domain> domain … | ``. If `DOMAINS` is empty, emit the single fallback row `` | `(none)` | No domains configured — add via /onboardSumela or /evolve | ``.
- `{{domain_rules}}` → for each domain, a `<rule activation="domain-conditional" applies_phases="all" domain="<Domain>">` entry whose `<path>` is `.sumela/rules/domains/<slug>.md` (slug = lowercase, non-alphanumeric → `-`). Empty when `DOMAINS` is empty.
- `{{phase_matrix_rows}}` → fill the phase-to-rule matrix; every row has FIVE columns (Phase | Universal | Phase-conditional | Stack-conditional | Domain-conditional), with the trailing two cells `(load matching stack rules) | (load matching domain rules)`.

### Step 3.3: Generate Rules

Based on detected stack:
- For each stack (backend/frontend/mobile): copy the appropriate template variant
  - Ask user: "Empty template (fill yourself) or best-practice (industry standards)?"
  - Copy selected variant to `.sumela/rules/<stack>_standards.md`
- Copy `operational_excellence_maintenance.md.template` → `.sumela/rules/operational_excellence_maintenance.md`
- For each domain in `DOMAINS` (team mode): `mkdir -p .sumela/rules/domains` and render `.sumela/rules/templates/domain_standards.md.empty` → `.sumela/rules/domains/<slug>.md`, substituting `{{domain_name}}` (the domain, original case) and `{{date_created}}`. NEVER overwrite an existing domain rule file (idempotent). There is no `.best-practice` variant for domains — they are project-specific.
- Fill project-specific sections based on detected conventions

### Step 3.4: Generate Wiki Pages

From templates:
- `active-project-context.md` → fill with current project state from git log, README, detected structure
- `_INDEX.md` → standard sections with project name
- `_LOG.md`, `_SEARCH_INDEX.md` → standard templates
- `_improvement-queue/` → create the directory and copy its `README.md` anchor (the queue is a directory, one `IMP-*.md` per signal — no monolithic file)

### Step 3.5: Generate IDE Pointers

Ask user which IDEs they use. Generate pointer files for selected IDEs.

### Step 3.6: Copy Second Brain Template

Copy `docs/second-brain/template/` structure to `docs/second-brain/`.

### Step 3.6b: Repo hygiene — gitignore baselines + union-merge (parity with `setup.sh`)

`setup.sh` makes these idempotent, marker-guarded edits; the brownfield path MUST make them too, otherwise team-safe merge, per-developer privacy, and secret governance silently never activate on this install route. Use a marker comment (or a stable entry line) so a re-run never duplicates the block.

1. **`.gitattributes` union-merge** for the append-only log (kills merge conflicts when teammates append to the shared `_LOG.md` concurrently). If the line is not already present, append:

   ```
   # SumelaOS — append-only ledger: concurrent log appends combine instead of conflicting
   docs/second-brain/wiki/_LOG.md merge=union
   ```

2. **`.gitignore` per-developer / runtime artifacts** — never commit a developer's local override or plugin runtime output. If `.sumela/local.md` is not already an ignored line, append (guard on the `.sumela/local.md` line, not the comment):

   ```
   # SumelaOS — per-developer / runtime artifacts (never commit)
   .sumela/local.md
   .sumela/.memory-sync.log
   .sumela/.graph-sync.log
   .sumela/.code-chunks-synced
   .superpowers/
   **/scripts/.superpowers/
   graphify-out/
   qdrant-storage/
   .sumela/_migration/
   AGENTS.md.bak*
   ```

   UPGRADE NOTE: this whole block is guarded on the `.sumela/local.md` line, so a project that adopted SumelaOS earlier already has the block and will SKIP it — meaning newer entries (`.sumela/_migration/`, `AGENTS.md.bak*`) would never land. For those two secret-bearing entries, ALSO append each individually if the exact line is missing (independent of the block), so the upgrade path is covered. (This mirrors the independent guards in `setup.sh` / `setup.ps1` §6c.)

3. **`.gitignore` secret baseline** — never commit credentials. If the marker is absent, append:

   ```
   # SumelaOS — common secret files (never commit; see .sumela/rules/security_protocol.md)
   .env
   .env.*
   !.env.example
   !.env.*.example
   *.pem
   *.key
   *.p12
   *.pfx
   *.secret
   secrets.json
   ```

   Do NOT overwrite an existing `.gitignore`/`.gitattributes` — append only if your marker line is missing. (When `gitleaks` is installed, the pre-commit hook adds a staged-diff secret scan on top of this baseline.)

### Step 3.7: Wire Git Hooks (whenever the project is a git repo)

`core.hooksPath = .sumela/git-hooks` enables two things: the `pre-commit`
validation hook (runs `validate-structure.sh` before a commit touches the
agent-control surface — useful for everyone) and the `post-merge`/`post-checkout`
memory-sync hooks (which self-gate: inert unless the Qdrant plugin + session
summaries + a reachable Qdrant all exist). Wire it regardless of plugin choice:

1. Confirm the project is a git repo: `git rev-parse --is-inside-work-tree`.
2. Check for an existing hooks path: `git config --local --get core.hooksPath`.
   - If it is set to something OTHER than `.sumela/git-hooks`, do NOT override —
     warn the user that hook installation must be merged manually.
   - Otherwise run: `git config core.hooksPath .sumela/git-hooks`
3. Ensure the hooks are executable: `chmod +x .sumela/git-hooks/pre-commit .sumela/git-hooks/post-merge .sumela/git-hooks/post-checkout`
4. Tell the user each teammate who later pulls the repo should run **`/onboardSumela`**
   once per clone — it wires this hook for them and sets their per-developer language +
   domains (hooks are not shared by git automatically). The by-hand equivalent is the
   `git config core.hooksPath` command above. Also mention a single commit can bypass the
   pre-commit check with `git commit --no-verify`.

### Step 3.8: CODEOWNERS for the agent-control surface (only if `GOVERNANCE_MODE` is `team`)

In `team` mode, `/evolve` routes agent-control changes through a PR; CODEOWNERS
ensures those PRs require a code owner's review. Skip entirely in `solo` mode.

1. Create or append to `.github/CODEOWNERS` (do NOT overwrite an existing one —
   append the agent-control block if your marker line is not already present):

   ```
   # SumelaOS agent-control surface — changes here alter every developer's agent.
   # Replace @OWNER with your team/maintainer handle (e.g. @org/maintainers).
   /.sumela/rules/                     @OWNER
   /.sumela/skills/                    @OWNER
   /.sumela/sumela-prompt.md           @OWNER
   /.sumela/RULE_REGISTRY.md           @OWNER
   /.sumela/SKILL_REGISTRY.md          @OWNER
   /.sumela/git-hooks/                 @OWNER
   /docs/second-brain/wiki/_SCHEMA.md  @OWNER
   ```
2. Ask the user for their owner handle and replace `@OWNER`; if unknown, leave the
   placeholder and tell them to set it before enabling branch protection.

### Step 3.9: CI validation workflow (opt-in — ASK, default no)

The CI workflow is optional (not every team uses GitHub Actions). ASK the user:
*"Add a GitHub Actions workflow that runs the structure validation on push/PR? (y/N)"*

- If **yes**: create `.github/workflows/sumela-validate.yml` using the content shipped
  by `setup.sh` section 7e (runs `validate-structure.sh --check-placeholders` + shell
  syntax). Do not overwrite an existing workflow file.
- If **no** (default): create nothing — the pre-commit hook (Step 3.7) still enforces
  locally. For GitLab/Azure, point them to the snippet in `ADOPTION_GUIDE.md`
  (Section 9, "CI & Pre-Commit Enforcement").

## PHASE 4 — Validation & Summary

### Step 4.1: Run Validation

```bash
bash scripts/validate-structure.sh --post-setup
```

`--post-setup` adds the hygiene guard: it PROVES this run actually wired the git
hooks (`core.hooksPath`), seeded the `.gitignore` per-developer/runtime + secret
baselines, and added the `.gitattributes` union-merge rule — so a half-finished
init cannot report success. If any of those FAIL, go back and complete the
matching Step 3.6b / 3.7 action, then re-run.

All checks must pass.

### Step 4.1b: Write the Migration Report (ONLY if PHASE 2c ran)

Write `.sumela/_migration/<YYYY-MM-DD>/MIGRATION_REPORT.md` recording, for full auditability:
- **Imported / folded** — each piece, its legacy source, and its new home (e.g., "custom skill `foo` → `.sumela/skills/foo/`"; "deploy commands from legacy AGENTS.md → AGENTS.md §Commands").
- **Preserved only (needs manual review)** — anything quarantined but NOT auto-integrated (e.g., an ambiguous skill, a conflicting directive the user deferred).
- **Left untouched** — UNRELATED artifacts (general `docs/`, source) confirmed not modified.
- **Collisions resolved** — every name clash and how it was settled.
- A closing note: *"Originals are preserved here. Review for secrets before committing this folder; delete it once you've confirmed the migration."*

### Step 4.2: Present Summary

```
## ✅ SumelaOS Setup Complete

### Generated Files
| File | Status |
|---|---|
| AGENTS.md | ✅ Created (filled with project info) |
| .sumela/RULE_REGISTRY.md | ✅ Created |
| .sumela/rules/backend_standards.md | ✅ best-practice variant |
| .sumela/rules/frontend_standards.md | ✅ best-practice variant |
| .sumela/rules/operational_excellence_maintenance.md | ✅ Created |
| docs/second-brain/wiki/active-project-context.md | ✅ Created |
| CLAUDE.md | ✅ Created |
| ... | |

### Next Steps
1. Review the generated files and customize if needed
2. Ask for the Context Manifest anytime with `/context` to see which skills/rules are loaded (it also prints automatically before high-stakes actions like commit, code review, shipping, and `/evolve`)
3. Start the self-improvement loop with `/evolve`
4. (Optional) Activate memory plugins — should have been asked during `/initSumela`

### Git
All files staged. Would you like to commit?
```

### Step 4.3: Offer Commit

If user confirms: `git add -A && git commit -m "feat(meta): initialize SumelaOS agent framework"`

## PHASE 5 — Register Skill in Registry

After successful init, append this entry to `.sumela/SKILL_REGISTRY.md`:

```xml
<skill activation="lazy">
<name>init-sumela</name>
<description>Use when the user says '/initSumela', 'init SumelaOS', 'kur SumelaOS', or 'setup SumelaOS' in an existing project — auto-detects tech stack, architecture, and conventions, then generates AGENTS.md, rules, wiki, and IDE pointers.</description>
<path>.sumela/skills/init-sumela/SKILL.md</path>
</skill>
```

</execution_workflow>

<error_handling>
- **No manifest files found** (no package.json, *.csproj, etc.): Ask user to describe the stack manually.
- **Ambiguous architecture** (could be multiple patterns): Present options and ask user to choose.
- **Multiple stacks detected** (monorepo with backend + frontend + mobile): Generate rules for all detected stacks.
- **Existing AGENTS.md / skills / rules / `docs/second-brain/`**: do NOT improvise overwrite-or-merge — run the **PHASE 2c Brownfield Merge** protocol (detect → classify → quarantine → propose plan → per-item approve → fold/import with provenance → migration report). Originals go to `.sumela/_migration/<date>/`; nothing is destroyed.
- **Validation fails**: Show specific failures and offer to fix.
</error_handling>

<constraints>
- NEVER overwrite existing files without explicit user confirmation
- NEVER guess — if detection is ambiguous, ask the user
- ALWAYS present analysis before writing — the user must confirm the detected stack
- ALWAYS run validation after generation
- Generated files must be valid markdown with proper frontmatter
- No project-specific content in universal rules (engineering_philosophy, identity_and_behavior, etc.)
- BROWNFIELD (existing agent artifacts): NEVER overwrite a built-in skill or a universal rule with imported content; NEVER touch the user's general `docs/` (only `docs/second-brain/`); ALWAYS quarantine an original before replacing/folding it; ALWAYS get per-item approval before integrating (PHASE 2c).
</constraints>
