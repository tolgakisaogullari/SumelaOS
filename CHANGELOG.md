# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Core framework version is tracked in `.sumela/VERSION` (consumed by `scripts/update.sh`).

## [Unreleased]

### Added

- **Extra documentation ingest paths** — adopting projects can index authoritative docs that
  live OUTSIDE `docs/second-brain/wiki/` (architecture docs, ADR dirs, API references) into the
  same Qdrant `wiki_pages` Tier-1 index, on the same pull-time/background/gated terms as the
  wiki — without copying them into the wiki (no drift). Mechanism in the framework, policy in
  the consumer: the framework ships an EMPTY default and NO project-specific paths. Configure
  per project via `.sumela/ingest.conf` (tracked, one repo-relative dir per line; copy the
  shipped `.sumela/ingest.conf.example`) or the `EXTRA_INGEST_DIRS` env var (comma/colon-
  separated; wins when set). A single resolver (`lib/memory_ingest.get_extra_ingest_dirs`,
  exposed to bash/PowerShell via `resolve-ingest-dirs.py`) does all resolution + validation so
  the three callers never drift: paths must be repo-relative and resolve to a real dir strictly
  inside the repo (absolute / `~` / `..` / globs / drive-letters / leading-dash / symlink-escape
  all rejected; missing skipped with a warning, never fails a pull). Docs only — `.md` files,
  symlink-safe walk (no following dir symlinks; per-file repo-containment re-check), deduped by
  resolved path; the code corpus is untouched. A per-run file cap (`EXTRA_INGEST_MAX_FILES`,
  default 5000) plus `.git`/`node_modules`/`vendor` skips bound the background re-embed.
  `sumela_wiki_sync` expands its change scope + orphan-prune to the extra dirs; `setup-memory`
  seeds them on first bring-up; `status.{sh,ps1}` report them. Documented in `ADOPTION_GUIDE.md`
  (incl. the trust note: a tracked path is a team-wide decision — CODEOWNERS-protect in team
  mode). Covered by `tests/test_extra_ingest_dirs.py`.

- **Rich, queryable session memory** — session summaries now carry structured metadata so
  memory answers "which developer did what, in which domain, when". A canonical
  `session-summary` page type + template lands in `_SCHEMA.md` (frontmatter: `developer`,
  `developer_email`, `domains`, `spec_artifact`, `plan_artifact`, `session_date`,
  `session_topics`; required detailed sections). `session-ingest.py` ingests these into the
  `chat_history` payload (incl. `date_int` for range filters); `query-qdrant.py` gains
  `--developer` / `--domain` / `--since` / `--until` filters plus a filter-only listing mode
  (`"*"` query → all matches via scroll, not top-K). The post-merge hook passes the commit's
  git author/date as `--fallback-developer`/`--fallback-date` so even un-stamped summaries are
  attributed. `sumela-prompt.md` routes who/when/domain questions to these filters (git log as
  the authoritative commit-level fallback).
- **Session summary written at task completion, not only on handoff** — the
  `<session_summary_protocol>` is now canonical in `using-second-brain` (single source);
  `context-handoff` references it, and `finishing-a-development-branch` Step 7 also writes +
  ingests a session summary. Previously a clean task finish with no context-pressure handoff
  left no conversational `chat_history` record (only curated-wiki ADR/commit-log updates).

- **Business-domain rule scope** — a third rule axis, orthogonal to stack scope.
  In team mode, setup / `/initSumela` asks the project's domain taxonomy (e.g. Card,
  Payments); each domain gets a tracked `RULE_REGISTRY.md` `<domain_scopes>` entry +
  a `.sumela/rules/domains/<slug>.md` rule file (generated from a new
  `domain_standards.md.empty` template). Which domain(s) a developer works in is
  per-developer and untracked (`.sumela/local.md` `domains:`); `sumela-prompt.md`
  STEP 4 loads the union of matching domain rules (a developer can be `backend` +
  `Card` at once), warning-and-skipping any domain not in the taxonomy. The Context
  Manifest gains a `[Domain: …]` header. `reconcile-registry.py` and
  `validate-structure.sh` now enforce domain rule↔registry parity (and `--stats`
  reports `domain_rules`).
- **`/onboardSumela` teammate onboarding** — a new skill (the single source of truth)
  for a developer who pulls an already-installed repo. It wires git hooks, sets the
  per-developer interaction language + domains in `.sumela/local.md`, and offers the
  optional memory runtime — without re-running install or touching team-wide config
  (use `/initSumela` only for first-time install). A non-nagging `STEP 0` onboarding
  gate in `sumela-prompt.md` detects a fresh clone (hooks unwired AND no `local.md`)
  and offers it once, deferring to the skill rather than duplicating its steps.
- **Parallel code-review panel** — `requesting-code-review` now dispatches three
  lane reviewers concurrently instead of one generalist: Correctness & Security
  (incl. auth/credential token lifecycle + security-boundary tests), Design &
  Contracts (conventions, architecture, API/contract stability, backward-compat),
  and Integration & Operations (cross-module impact via graphify, performance,
  data/persistence, observability/rollback, test coverage). The orchestrator then
  synthesizes the lanes — dedupes overlapping findings, surfaces `CONFLICT`s, and
  applies an AND-gate (any lane's Critical blocks commit/merge). New lane templates:
  `reviewer-correctness-security.md`, `reviewer-design-contracts.md`,
  `reviewer-integration-ops.md`; the legacy single-reviewer `code-reviewer.md` is
  retained as an IDE/degraded fallback. SDD's final review (Step 5) inherits the
  panel automatically; its per-task Stage-1/Stage-2 reviews are unchanged.
- **`reconcile-registry.py --stats`** — prints the canonical skill counts
  (`skill_workflows`, `loadable_skills`, `plugin_skills`) as the single source of
  truth for any number quoted in docs.
- **README skill-count drift guard** — `validate-structure.sh` compares the README
  `<!-- sumela:skill-count -->` marker against `--stats` and fails on mismatch, so
  the documented count can never silently diverge when a skill is added/removed
  (silent no-op in user projects, where README isn't present).
- **"How SumelaOS Extends Superpowers" README section** — an evidence-based,
  honest side-by-side vs [obra/superpowers](https://github.com/obra/superpowers)
  (21 vs 14 skill workflows, the review panel, rules/memory/governance layers — and
  where Superpowers is still broader on harness count).

### Changed

- **Context Manifest triggers narrowed** — the manifest now prints only on explicit
  user request (`/context`) and immediately before high-stakes actions (commit,
  code-review dispatch, finishing a branch, shipping, `/evolve`). It no longer
  prints at session start or on every phase transition, removing the "first output
  must be the manifest" mandate. Cuts recurring output tokens and per-turn latency
  while keeping the GAP-visibility checkpoint where it matters; spec trimmed in
  `sumela-prompt.md`. Dependent references (using-superpowers, RULE_REGISTRY
  template, AGENTS.md template, init-sumela, README) updated to match.

### Fixed

- **Qdrant ingestion no longer silently no-ops in adopted projects.** The Qdrant plugin's
  `get_repo_root()` (`memory-plugins/qdrant-session-memory/scripts/lib/memory_ingest.py`)
  hard-coded "three levels up" from the module, which resolved to the *plugin* directory
  (`.sumela/memory-plugins/qdrant-session-memory`) rather than the repository root. In every
  project that vendored SumelaOS, `WIKI_DIR`/`SRC_DIR` then pointed under the plugin dir
  (so wiki/code ingest found nothing) and `relative_to(REPO_ROOT)` raised on real doc paths —
  the `wiki_pages`/`code_chunks` collections stayed permanently empty while `setup-memory`
  still reported them "ready" and `query-qdrant` returned 0 results forever, so Tier-1
  semantic memory was non-functional with no error on the happy path. `get_repo_root()` now
  walks up to the first ancestor containing `.git` or a top-level `.sumela/` (matching what
  the PowerShell scripts already do), honors a `SUMELA_REPO_ROOT` override, and keeps the old
  three-levels-up only as a last-resort fallback — correct in both the framework's own repo
  and vendored adoptions. Covered by `tests/test_get_repo_root.py` (run in `tests/smoke.sh`).

- **Graphify build no longer reports false success or silently skips `graph.html`.**
  `setup-memory.{sh,ps1}`, `auto-update-memory.py`, and a downstream sync error message used
  `graphify update .` — the incremental path — for the initial build, and the setup scripts
  suppressed all output (`*> $null` / `>/dev/null 2>&1`) and declared "Code graph built" on
  exit 0 alone. On any repo over graphify's ~5000-node viz limit, the interactive `graph.html`
  was skipped with a warning the user never saw, yet setup still reported success. Now:
  - **All paths** use the canonical `graphify .` for the first build (`graphify . --update` only
    for incremental re-runs — `--update` is a flag, not the legacy `update` subcommand).
  - **`setup-memory.{sh,ps1}` (interactive setup):** output is no longer suppressed, so graphify's
    own viz/limit warnings reach the user; the "Code graph built" success is gated on `graph.html`
    actually existing, not exit 0; when graphify skips the viz on a large graph, setup reads the
    real node count, raises `GRAPHIFY_VIZ_NODE_LIMIT` above it, and regenerates the viz via
    `graphify cluster-only .` — falling back to a flagged to-do with the exact command if it still
    can't, never a fake "built".
  - **`auto-update-memory.py` (the git-hook / background path):** same canonical command + viz
    auto-raise/regenerate; graphify's own viz/`graph.html` warnings are best-effort echoed from
    captured output (and a `cluster-only` failure is reported with its exit code), while the
    structured report ALWAYS carries an explicit `note:` line distinguishing "graph updated" (the
    query-critical `graph.json` is fresh) from "interactive `graph.html` skipped" + the exact
    remediation. A skipped viz is reported, not silently treated as full success, and not treated as
    a hard failure (which would falsely fail the background hook on every large-repo commit).
  - The graphify plugin README now documents the AST-only nature (semantic extraction needs a
    generative backend SumelaOS does not wire up), that Tier-2 queries work off `graph.json` even
    when the viz is skipped, and why `graphify-out/` is gitignored.

## [0.4.0] - 2026-06-02

### Added — less manual work, monorepo support

- **Auto-reconcile `SKILL_REGISTRY.md`** — `scripts/reconcile-registry.py` registers
  on-disk skills missing from the registry (verbatim description, `activation="lazy"`)
  and reports orphans; run by `update.sh` with consent.
- **Health report** — `scripts/status.sh` / `status.ps1`: one read-only command for
  version, governance, structure, registry/mirror/shared-rule drift, improvement-queue
  count, git-hook wiring, secret scanner, and memory plugins. Every issue lists its fix.
- **Secret governance** — if `gitleaks` is installed, the pre-commit hook scans staged
  changes and blocks on a finding (silent if absent; `SUMELA_DISABLE_SECRET_SCAN=1` to
  disable; tool/version errors never block). Setup seeds a `.gitignore` secret baseline.
- **Monorepo support** — hooks self-anchor to their install dir (subdir installs now
  validate their own subtree instead of silently no-op'ing). Multiple installs in one
  repo auto-promote to a root dispatcher (`.sumela-hooks/` + `_dispatch.sh`) that runs
  every install's hooks. Org-shared rules live once in `.sumela-shared/rules/`;
  `scripts/sync-shared-rules.py` distributes + registers them (universal) into each
  install (run by setup / update; drift surfaced by `status.sh`).
- **OpenCode IDE support** — `.opencode/AGENTS.md.template` pointer; wired into
  `setup.sh` / `setup.ps1` (template list, IDE map, multiselect, `--ides`) and the
  README Supported-IDEs table, completing the IDE matrix the README already advertised.
- **One-step memory runtime** — `scripts/setup-memory.sh` / `.ps1`: opting into a
  memory plugin no longer leaves the developer to install Qdrant/Ollama/graphify by
  hand. It auto-installs the cheap/safe deps (pip) and CONFIRMS-and-runs the invasive
  steps (start Qdrant via Docker, pull the Ollama embedding model, install the graphify
  CLI), reuses anything already present, then creates the Qdrant collections + builds
  the initial graph. Idempotent; non-interactive mode prints every exact command
  instead of running it; `/initSumela` and `setup.sh`/`.ps1` invoke it after copying
  the plugins (skip with `SUMELA_SKIP_MEMORY_SETUP=1`, e.g. in CI / the smoke test).
  It is also the **add-a-plugin-later** path: since bootstrap copies all plugin
  files, `setup-memory.sh --plugins <name>` registers a not-yet-enabled plugin in
  `SKILL_REGISTRY.md` and brings its runtime up — no re-init needed. All script
  output is English (framework artifacts stay language-neutral); the `/initSumela`
  consent prompt is rendered in the developer's configured interaction language.
- **End-to-end smoke test** — `tests/smoke.sh` runs `setup.sh` against a throwaway
  copy and asserts the contract (AGENTS.md + every selected IDE pointer generated, a
  plugin registered exactly once, no unrendered placeholders, structure + reconcile
  pass) and that a second run is idempotent. Wired into the opt-in CI workflow; this
  is the first FUNCTIONAL test of the self-modifying setup pipeline (was parse-only).
- **Signal taxonomy expanded** (`self-improvement-curator`) — two new capture types:
  `resolution` (agent-originated: a bug/problem the agent fixes itself → capture the
  GENERALIZED class-level lesson, never the one-off instance) and `preference` (a
  proactive standing user instruction, distinct from a reactive `correction`). Wired
  in lockstep across the prompt, registries, schema, and queue README.
- **Pull-time code-graph refresh** — `post-merge`/`post-checkout` now also run
  `sumela_graph_sync`: when a pull/checkout brings CODE changes, it refreshes the
  local graphify graph in the background via `auto-update-memory.py --graph-only`
  (a new graph-only mode that writes ONLY the gitignored graph dir — no wiki sync,
  no `_LOG.md` append, so a pull never dirties the tree). Self-gating, non-blocking,
  opt-out with `SUMELA_DISABLE_GRAPH_SYNC=1`.
- **Pull-time Qdrant content refresh** — the pull hooks also keep the Qdrant semantic
  collections (whose embeddings would otherwise lag the git-current tracked files) in
  sync: `sumela_wiki_sync` re-ingests `wiki_pages` when a CURATED page changed
  (session-summaries + underscore-special files like `_LOG.md` excluded, so a
  union-merged log alone never triggers it; default on, opt-out
  `SUMELA_DISABLE_WIKI_SYNC=1`). `sumela_code_sync` keeps `code_chunks` honest: it
  PRUNES orphans for removed code files cheaply on every pull, but the heavy whole-tree
  re-embed is no longer all-or-nothing — when code_chunks is STALE
  (> `SUMELA_CODE_REINGEST_DAYS`, default 14) it PROMPTS for approval on an interactive
  pull (default No, 30s timeout) or prints a non-blocking notice otherwise;
  `SUMELA_PULL_CODE_REINGEST=1` forces it, `SUMELA_DISABLE_CODE_SYNC=1` turns it off.
- **Qdrant orphan pruning** — new `delete-from-qdrant.py` (delete points by a payload
  key). `wiki_sync`/`code_sync` call it for pages/files DELETED upstream, so a removed
  wiki page or source file stops surfacing in semantic search. `chat_history` is
  deliberately exempt — a removed session summary does not retract a past decision.
  All syncs remain background, best-effort, Qdrant-reachability-gated, and write only
  the Qdrant cache — never the tracked tree.
- **Richer memory-sync log** — the pull-time summary ingest now reports WHO (git
  author) and WHICH tasks (filename + `session_topics`) each arriving summary
  belongs to, inline (up to 10) and in `.sumela/.graph-sync.log`/`.memory-sync.log`.

### Fixed

- **Existing-project install completeness** — the README agent prompt now delegates
  the copy to the maintained `bootstrap.sh`/`.ps1` (no more hand-list drift; bootstrap
  now also copies `docs/second-brain/template/` and the new `.opencode/`), and
  `/initSumela` gained Step 3.6b (`.gitattributes` union-merge + `.gitignore` secret
  baseline) so both install paths reach full parity with `setup.sh`.
- **English-only framework artifacts (global-ready)** — removed hardcoded Turkish from
  the agent-control surface: the prompt's routing/trigger examples, skill trigger
  phrases + user-facing example prompts (`self-improvement-curator`, `using-second-brain`,
  `context-handoff`, `idea-explore`, `finishing-a-development-branch`), the plugin
  trigger lines, the `_SCHEMA.md` template (fully translated, section numbers + enums
  preserved), and the two ingest scripts' examples. Triggers are now English + "the
  equivalent in any language"; instructions that said "respond in Turkish" now say
  "in the configured interaction language". Setup-script output is English; the agent
  still renders all user-facing text in the developer's chosen language.

- **`status.sh` / `status.ps1` hook detection** now recognizes all three wiring forms
  the monorepo work introduced (root, subdir `<rel>/.sumela/git-hooks`, and the
  `.sumela-hooks` dispatcher — verifying this install is registered) instead of only
  the root form; the fix it suggests is rerunning setup (correct for every topology).
- **`setup.ps1` plugin registration is now idempotent** — guards on an existing
  `<name>` before appending, matching `setup.sh`; re-running with a plugin selected no
  longer duplicates its `<skill>` block in `SKILL_REGISTRY.md`.
- **Bootstrap scripts hardened** — `bootstrap.sh` uses `set -euo pipefail`, surfaces
  clone failures, fails loudly on the essential payload, and cleans up via `trap`;
  `bootstrap.ps1` reaches parity (copies all IDE templates + `.gitkeep` dirs, real
  error/next-step output) instead of being a minimal stub.
- **`.sumela/VERSION` bumped to 0.4.0** so `update.sh`'s version gate and `status.sh`
  reflect the post-0.3.0 core (it had stayed at 0.3.0 while features landed).

## [0.3.0] - 2026-06-01

### Added — team enablement

- **Shared session memory** — `session-ingest.py` is idempotent (deterministic point
  IDs, delete-by-session); `post-merge`/`post-checkout` git hooks re-ingest teammates'
  committed session summaries into each developer's local Qdrant on pull.
- **Team-safe wiki** — `_LOG.md` uses git `union` merge; the self-improvement queue is
  a directory (`_improvement-queue/`, one `IMP-YYYYMMDD-<short>.md` per signal, no
  shared counter); `active-project-context.md` per-developer "Active Work" convention.
- **`/evolve` governance** — `governance: solo|team` (AGENTS.md §8). In team mode,
  rule/skill/schema changes route through a PR (`proposed` status + reconcile) and a
  `.github/CODEOWNERS` block guards the agent-control surface.
- **Enforcement** — `validate-structure.sh` runs via a `.sumela/git-hooks/pre-commit`
  hook (scoped, bypassable) and an opt-in GitHub Actions workflow (`setup.sh --ci`).
- **Per-developer config** — gitignored `.sumela/local.md` overrides only
  `interaction_language`; code naming/documentation stay team-wide.
- **Upgrade path** — `.sumela/VERSION` + `scripts/update.sh` / `update.ps1` refresh the
  framework CORE (prompt, skills, scripts, hooks, universal rules, schema, templates)
  without touching the project OVERLAY (AGENTS.md, stack rules, wiki, registries,
  governance/CI choices), with per-file diff + consent.
- **IDE mirror sync** — `scripts/sync-mirrors.sh` regenerates verbatim IDE mirrors
  from `sumela-prompt.md`; drift is checked by pre-commit + CI.

### Changed

- `core.hooksPath` is wired for every git repo (memory hooks self-gate); the CI
  workflow is opt-in (not auto-imposed).
- Reconciled the language protocol: project code follows the configured
  naming/documentation languages; only framework artifacts + commit messages stay English.

## [0.2.0] - 2026-05-22

### Added
- `init-sumela` skill: `/initSumela` command for automatic brownfield adoption
  - Auto-detects tech stack from manifest files (csproj, package.json, go.mod, Cargo.toml, etc.)
  - Identifies architecture pattern from directory structure (Clean Arch, MVC, microservices, monorepo, etc.)
  - Detects code conventions from existing source files (naming, error handling, validation, testing)
  - Generates AGENTS.md, RULE_REGISTRY.md, rules, wiki pages, and IDE pointers in one pass
  - Interactive confirmation before writing any files
- **Proactive Qdrant session context (STEP 3c)**: Agent silently queries Qdrant before starting non-trivial tasks
  - Checks past sessions for relevant decisions, lessons, and context
  - 5 scenarios: task start, entity encounter, architecture decision, debugging, file history
  - Mirrors Graphify's proactive impact analysis pattern

### Fixed
- Subagent-driven-development: added independent review option (4th choice after task completion)
- Graphify plugin: corrected installation to `uv tool install graphifyy` (PyPI, not npm)
- Graphify plugin: added "No API Key Required for Queries" clarification
- **Proactive impact analysis (STEP 3b)**: Agent now queries graphify before code changes to detect affected dependents

## [0.1.0] - 2026-05-22

### Added
- 27 universal agent skills (brainstorming, planning, TDD, debugging, code review, shipping, etc.)
- 7 universal rules + stack-specific rule templates (empty + best-practice variants)
- Second-brain wiki template with Karpathy LLM Wiki pattern (raw_sources → artifacts → wiki)
- Memory plugins: Qdrant session memory (Tier-1), Graphify code graph (Tier-2)
- Setup scripts: setup.sh (Bash), setup.ps1 (PowerShell) with interactive and non-interactive modes
- Validation script: validate-structure.sh
- IDE pointer templates: Claude Code, Cursor, Cline, Kilo Code, Trae
- ADOPTION_GUIDE with greenfield, brownfield, and team onboarding modes
- Self-improvement loop: `/evolve` command for capturing corrections and friction signals
- Context Manifest protocol for session-start transparency
- Phase-to-rule matrix for automatic rule loading based on active phase and stack scope
