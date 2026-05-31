# Second Brain Template — Karpathy LLM Wiki Pattern

A portable, IDE-agnostic second brain starter kit implementing Andrej Karpathy's LLM Wiki pattern. Works with Claude Code, Cursor, Cline, Kilo Code, Trae, and any AGENTS.md-compatible agent.

## Quick Start

1. **Copy this template** into your project:
   ```bash
   cp -r docs/second-brain/template/ <your-project>/docs/second-brain/
   ```

2. **Edit `wiki/active-project-context.md`:**
   - Replace `[Project Name]` with your project name
   - Fill in `date_created` / `date_updated` with today's date
   - Add your current sprint or initial project state

3. **Verify `wiki/_SCHEMA.md`** — this is the canonical format reference. Do not modify unless you need project-specific schema extensions.

4. **Start your first agent session.** The agent will:
   - Read `_INDEX.md` → `_SCHEMA.md` → `active-project-context.md`
   - Begin building wiki pages as you work (entity pages, decision records, etc.)
   - Log activity to `_LOG.md`

## Directory Structure

```
docs/second-brain/
├── raw_sources/          <- IMMUTABLE. User-provided source materials.
│   └── assets/           <- Images, diagrams, downloaded attachments.
├── artifacts/            <- IMMUTABLE. LLM-generated write-once documents.
│   ├── plans/            <- Sprint/implementation plans.
│   └── specs/            <- Design specs and brainstorming output.
└── wiki/                 <- LIVE. Continuously updated synthesis layer.
    ├── _INDEX.md          <- Human-optimized content catalog.
    ├── _LOG.md            <- Chronological append-only activity log.
    ├── _SCHEMA.md         <- Canonical format rules (do not modify lightly).
    ├── _SEARCH_INDEX.md   <- Agent-optimized search index (tag + key term table).
    ├── _IMPROVEMENT_QUEUE.md <- Self-improvement suggestion queue.
    └── active-project-context.md <- Current sprint snapshot (read every session).
```

## Companion Files (Not Included)

This template covers `docs/second-brain/` only. For the full agent experience, you also need:

- **`AGENTS.md`** (repo root) — Canonical agent bootstrap file
- **`.sumela/`** — Portable skill engine (SKILL_REGISTRY.md + skills/)
- **IDE pointer files** — `.cursor/rules/00-agent.md`, `.clinerules`, `.kilocode/rules.md`, `.trae/rules/00-agent.md`

See `ADOPTION_GUIDE.md` for complete setup instructions covering greenfield and brownfield projects.

## Scale Path

A production deployment can use a four-tier stack: Qdrant (semantic session memory) + Graphify (code AST + call graph) + wiki search index (`_SEARCH_INDEX.md`) + grep fallback. See `_SCHEMA.md` Section 13 and Section 16 for routing rules and growth thresholds. For very small projects, `_SEARCH_INDEX.md` + grep alone is sufficient — promote tiers as the wiki and codebase grow.

## Format Reference

All wiki pages follow the schema defined in `_SCHEMA.md`:
- YAML frontmatter with `type`, `tags`, `date_created`, `date_updated`
- Kebab-case file naming
- Obsidian wikilinks for internal references
- Standard markdown links for external references (artifacts, raw_sources)
