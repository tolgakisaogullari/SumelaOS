# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Core framework version is tracked in `.sumela/VERSION` (consumed by `scripts/update.sh`).

## [Unreleased]

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
- **End-to-end smoke test** — `tests/smoke.sh` runs `setup.sh` against a throwaway
  copy and asserts the contract (AGENTS.md + every selected IDE pointer generated, a
  plugin registered exactly once, no unrendered placeholders, structure + reconcile
  pass) and that a second run is idempotent. Wired into the opt-in CI workflow; this
  is the first FUNCTIONAL test of the self-modifying setup pipeline (was parse-only).

### Fixed

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
