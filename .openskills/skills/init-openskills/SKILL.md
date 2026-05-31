---
name: init-openskills
description: "Use when the user says '/initOpenSkills', 'init openskills', 'kur openskills', or 'setup openskills' in an existing project — auto-detects tech stack, architecture, and conventions, then generates AGENTS.md, rules, wiki, and IDE pointers."
---

<purpose>
Automate brownfield adoption of the OpenSkills framework for existing projects. Instead of manually filling templates, the agent reads the project structure, detects the tech stack, identifies architecture patterns and code conventions, and generates all configuration files in one pass.

This is the "zero-config" onboarding experience: one command → fully functional agent framework.
</purpose>

<activation>
LAZY — loaded on demand when the user invokes /initOpenSkills or equivalent.
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

### Altyapı
- Database: PostgreSQL (EF Core)
- Cache: Redis
- Message Broker: RabbitMQ
- CI/CD: GitHub Actions

### Code Style
- TypeScript strict mode enabled
- ESLint + Prettier configured
- Nullable reference types enabled (.NET)

---

Bu doğru mu? Düzeltilmesi gereken bir şey var mı?
1. Onayla ve devam et
2. Düzeltme yap (hangi kısım?)
3. İptal et
```

**WAIT for user confirmation.** If user says "2", ask which part to correct and re-analyze. If user says "3", abort.

## PHASE 2b — Memory Plugin Selection (MANDATORY)

After the user confirms the analysis, MUST ask about optional memory plugins. NEVER skip this step.

```
## 🧩 Opsiyonel Memory Plugin'leri

OpenSkills framework'ü iki opsiyonel memory plugin'i ile gelir. Bunlar agent'ın
geçmiş session'lardan ve kod yapısından öğrenmesini sağlar. Kurmak istediklerini seç:

| Plugin | Ne Yapıyor | Gereksinimler |
|---|---|---|
| **Qdrant Session Memory** (Tier-1) | Geçmiş session'ları semantic search ile bulur. "Daha önce ne karar verdik?" sorularını yanıtlar. Kod ve wiki dosyalarını indexler. | Python 3.10+, Qdrant, Ollama (qwen3-embedding:0.6b) |
| **Graphify Code Graph** (Tier-2) | Kod çağrı grafiğini analiz eder. "X nerede kullanılıyor?" ve "X'i değiştirsem ne etkilenir?" sorularını yanıtlar. | Python 3.10+, graphify CLI (uv tool install graphifyy) |

Bu plugin'ler olmadan da framework çalışır — Tier-3 (wiki search) ve Tier-4 (grep fallback) her zaman aktif.

1. Her ikisini de kur (Qdrant + Graphify)
2. Sadece Qdrant'ı kur
3. Sadece Graphify'ı kur
4. Hiçbirini kurma (sadece core framework)
```

**WAIT for user choice.** Store the selection as `PLUGIN_CHOICE`.

**Conditional logic based on PLUGIN_CHOICE:**

- If "1" (both): Copy both `.openskills/memory-plugins/qdrant-session-memory/` and `.openskills/memory-plugins/graphify-code-graph/` directories. Run `setup-qdrant.py` if Qdrant is available. Run `graphify .` if graphify is installed.
- If "2" (qdrant only): Copy only `.openskills/memory-plugins/qdrant-session-memory/`. Run `setup-qdrant.py` if Qdrant is available. Do NOT copy graphify plugin.
- If "3" (graphify only): Copy only `.openskills/memory-plugins/graphify-code-graph/`. Run `graphify .` if graphify is installed. Do NOT copy qdrant plugin.
- If "4" (none): Do NOT copy `.openskills/memory-plugins/` directory at all. Remove memory-plugins references from SKILL_REGISTRY.md in the generated copy.

**IMPORTANT:** If user declines a plugin, do NOT copy its scripts, do NOT register it in SKILL_REGISTRY.md, and do NOT run any of its scripts. The agent should not reference unavailable plugins in generated files.

## PHASE 3 — File Generation (after confirmation)

Generate all configuration files. Present a checklist:

### Step 3.1: Generate AGENTS.md

Read `AGENTS.md.template` and fill all `{{placeholders}}`:
- `{{project_name}}` → from repo root directory name or user input
- `{{project_purpose}}` → from README.md one-liner or user input
- `{{tech_stack_summary}}` → from Phase 1 analysis
- `{{interaction_language}}` → ask user (default: English)
- `{{code_language}}` → English (standard)
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
  - Copy selected variant to `.openskills/rules/<stack>_standards.md`
- Copy `operational_excellence_maintenance.md.template` → `.openskills/rules/operational_excellence_maintenance.md`
- Fill project-specific sections based on detected conventions

### Step 3.4: Generate Wiki Pages

From templates:
- `active-project-context.md` → fill with current project state from git log, README, detected structure
- `_INDEX.md` → standard sections with project name
- `_LOG.md`, `_SEARCH_INDEX.md`, `_IMPROVEMENT_QUEUE.md` → standard templates

### Step 3.5: Generate IDE Pointers

Ask user which IDEs they use. Generate pointer files for selected IDEs.

### Step 3.6: Copy Second Brain Template

Copy `docs/second-brain/template/` structure to `docs/second-brain/`.

## PHASE 4 — Validation & Summary

### Step 4.1: Run Validation

```bash
bash scripts/validate-structure.sh
```

All checks must pass.

### Step 4.2: Present Summary

```
## ✅ OpenSkills Kurulumu Tamamlandı

### Oluşturulan Dosyalar
| Dosya | Durum |
|---|---|
| AGENTS.md | ✅ Oluşturuldu (proje bilgileriyle dolduruldu) |
| .openskills/RULE_REGISTRY.md | ✅ Oluşturuldu |
| .openskills/rules/backend_standards.md | ✅ best-practice variant |
| .openskills/rules/frontend_standards.md | ✅ best-practice variant |
| .openskills/rules/operational_excellence_maintenance.md | ✅ Oluşturuldu |
| docs/second-brain/wiki/active-project-context.md | ✅ Oluşturuldu |
| CLAUDE.md | ✅ Oluşturuldu |
| ... | |

### Sonraki Adımlar
1. Oluşturulan dosyaları incele ve gerekirse özelleştir
2. İlk session'da agent автоматik olarak Context Manifest basacak
3. `/evolve` ile self-improvement döngüsünü başlat
4. (Opsiyonel) Memory plugin'leri aktive et — `/initOpenSkills` sırasında sormuş olmalı

### Git
Tüm dosyalar staged. Commit etmek ister misin?
```

### Step 4.3: Offer Commit

If user confirms: `git add -A && git commit -m "feat(meta): initialize openskills agent framework"`

## PHASE 5 — Register Skill in Registry

After successful init, append this entry to `.openskills/SKILL_REGISTRY.md`:

```xml
<skill activation="lazy">
<name>init-openskills</name>
<description>Use when the user says '/initOpenSkills', 'init openskills', 'kur openskills', or 'setup openskills' in an existing project — auto-detects tech stack, architecture, and conventions, then generates AGENTS.md, rules, wiki, and IDE pointers.</description>
<path>.openskills/skills/init-openskills/SKILL.md</path>
</skill>
```

</execution_workflow>

<error_handling>
- **No manifest files found** (no package.json, *.csproj, etc.): Ask user to describe the stack manually.
- **Ambiguous architecture** (could be multiple patterns): Present options and ask user to choose.
- **Multiple stacks detected** (monorepo with backend + frontend + mobile): Generate rules for all detected stacks.
- **Existing AGENTS.md**: Warn user and ask whether to overwrite or merge.
- **Existing .openskills/**: Warn user and ask whether to overwrite, merge, or abort.
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
