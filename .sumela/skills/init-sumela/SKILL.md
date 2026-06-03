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

## PHASE 2 — Analysis Report (user-facing)

Present the detected configuration to the user for confirmation. Format:

```
## 🔍 Proje Analizi

### Tespit Edilen Stack
| Katman | Teknoloji | Detay |
|---|---|---|
| Backend | .NET 10 / C# 14 | ASP.NET Core, EF Core, RabbitMQ |
| Frontend | React 19 / Vite | Tailwind CSS, Shadcn UI |
| Mobile | React Native / Expo | Expo SDK 54, NativeWind v4 |

### Mimari Pattern
Clean Architecture + DDD (light) + CQRS-leaning

### Tespit Edilen Konvansiyonlar
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

**Conditional logic based on PLUGIN_CHOICE:**

- If "1" (both): Copy both `.sumela/memory-plugins/qdrant-session-memory/` and `.sumela/memory-plugins/graphify-code-graph/` directories. Run `setup-qdrant.py` if Qdrant is available. Run `graphify .` if graphify is installed. Wire git hooks (see Step 3.7).
- If "2" (qdrant only): Copy only `.sumela/memory-plugins/qdrant-session-memory/`. Run `setup-qdrant.py` if Qdrant is available. Do NOT copy graphify plugin. Wire git hooks (see Step 3.7).
- If "3" (graphify only): Copy only `.sumela/memory-plugins/graphify-code-graph/`. Run `graphify .` if graphify is installed. Do NOT copy qdrant plugin.
- If "4" (none): Do NOT copy `.sumela/memory-plugins/` directory at all. Remove memory-plugins references from SKILL_REGISTRY.md in the generated copy.

**IMPORTANT:** If user declines a plugin, do NOT copy its scripts, do NOT register it in SKILL_REGISTRY.md, and do NOT run any of its scripts. The agent should not reference unavailable plugins in generated files.

## PHASE 3 — File Generation (after confirmation)

Generate all configuration files. Present a checklist:

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
- `{{phase_matrix_rows}}` → fill phase-to-rule matrix with stack columns

### Step 3.3: Generate Rules

Based on detected stack:
- For each stack (backend/frontend/mobile): copy the appropriate template variant
  - Ask user: "Empty template (fill yourself) or best-practice (industry standards)?"
  - Copy selected variant to `.sumela/rules/<stack>_standards.md`
- Copy `operational_excellence_maintenance.md.template` → `.sumela/rules/operational_excellence_maintenance.md`
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

### Step 3.6b: Repo hygiene — secret baseline + union-merge (parity with `setup.sh`)

`setup.sh` makes these two idempotent, marker-guarded edits; the brownfield path MUST make them too, otherwise team-safe merge and secret governance silently never activate on this install route. Use a marker comment so a re-run never duplicates the block.

1. **`.gitattributes` union-merge** for the append-only log (kills merge conflicts when teammates append to the shared `_LOG.md` concurrently). If the line is not already present, append:

   ```
   # SumelaOS — union-merge the append-only second-brain log (conflict-free concurrent appends)
   docs/second-brain/wiki/_LOG.md merge=union
   ```

2. **`.gitignore` secret baseline** — never commit credentials. If the marker is absent, append:

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
4. Tell the user each teammate must run the `git config core.hooksPath` command
   once per clone (hooks are not shared by git automatically), that `setup.sh`
   / `setup.ps1` do this step for them, and that a single commit can bypass the
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
bash scripts/validate-structure.sh
```

All checks must pass.

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
2. On the first session, the agent will automatically print the Context Manifest
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
- **Existing AGENTS.md**: Warn user and ask whether to overwrite or merge.
- **Existing .sumela/**: Warn user and ask whether to overwrite, merge, or abort.
- **Validation fails**: Show specific failures and offer to fix.
</error_handling>

<constraints>
- NEVER overwrite existing files without explicit user confirmation
- NEVER guess — if detection is ambiguous, ask the user
- ALWAYS present analysis before writing — the user must confirm the detected stack
- ALWAYS run validation after generation
- Generated files must be valid markdown with proper frontmatter
- No project-specific content in universal rules (engineering_philosophy, identity_and_behavior, etc.)
</constraints>
