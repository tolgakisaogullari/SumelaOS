---
name: using-second-brain
description: "Use when starting a session, ingesting a raw source, finishing a branch, answering a question that may reference prior work, or facing an information gap during reasoning (entity definitions, past decisions, call graphs, prior session context)."
---

<brain_architecture>
The Second Brain is stored in `docs/second-brain/` (or your chosen Obsidian vault). It has three distinct layers (Karpathy pattern):

1. `raw_sources/`: IMMUTABLE. User-provided articles, logs, PDFs, meeting notes. You MUST READ from here but NEVER modify these files.
2. `artifacts/`: IMMUTABLE (write-once). LLM-generated plans (`artifacts/plans/`) and specs (`artifacts/specs/`). Created by `writing-plans` and `brainstorming` skills. Once written, NEVER modified.
3. `wiki/`: LIVE SYNTHESIS. A structured, interlinked directory of markdown files. You own this layer entirely. You create, update, and maintain cross-references here. This is where knowledge compounds.

Schema (Configuration): Format rules live in `wiki/_SCHEMA.md`. Behavioral rules live in `.openskills/SKILL_REGISTRY.md` and this skill file.

Reliability invariant: For this skill, Second Brain correctness and recoverability are more important than token reduction. Do not remove routing tiers, write gates, parity checks, or memory-sync steps solely to reduce context cost; simplify only when behavior remains at least as safe.
</brain_architecture>

<core_indexes>
The `wiki/` directory has FIVE special files (frontmatter-free, governed by `_SCHEMA.md`):
- `_INDEX.md`: Human-optimized content catalog. Read this FIRST every session for navigation.
- `_SEARCH_INDEX.md`: Agent-optimized search index. A table with per-page Type, Tags, Key Terms, and Summary columns. Use this for targeted search: match query terms against Key Terms/Tags → read only matched pages. Scales to hundreds of pages with zero runtime dependencies. Updated during every ingest/code-commit/lint.
- `_LOG.md`: Chronological append-only log. Format: `## [YYYY-MM-DD] type | topic` (parse-friendly). Type whitelist: `ingest | query | lint | code-commit | decision | migration`. NEVER rewrite past entries — they are immutable history.
- `_LOG.md` note: `_SCHEMA.md` is the canonical whitelist source; `evolve` is a valid log type for self-improvement applications.
- `_SCHEMA.md`: Canonical format source. Read this BEFORE writing any wiki page. Defines page types, frontmatter schemas, naming, templates, and cross-ref conventions.
- `_IMPROVEMENT_QUEUE.md`: Self-improvement queue. Managed by `self-improvement-curator` skill and reviewed via `/evolve`. Read at session start to surface pending count to the user. Do NOT modify as part of normal wiki operations — it has its own workflow.
</core_indexes>

<trigger_conditions>
Determine which workflow to execute based on these signals (highest specificity wins):

- **Session start** → bootstrap reads + parity + queue count are governed by `.openskills/superpowers-agent-mode-prompt.md` (`<session_bootstrap>`). This skill is invoked LAZILY when an information gap appears or one of the triggers below fires.
- **User says** "kaydet", "wiki'ye ekle", "ingest et", "şunu not al", "remember this" → INGEST workflow.
- **User drops multiple sources** or says "batch ingest", "hepsini işle" → BATCH INGEST workflow.
- **`finishing-a-development-branch` invoked** → CODE-COMMIT INGEST hook (update `active-project-context.md`, audit entity/api/decision/tech-debt pages, append `code-commit` entry to `_LOG.md`).
- **User says** "wiki'yi temizle", "lint et", "sağlık kontrolü", "clean the wiki" → LINT workflow.
- **Ad-hoc decision during conversation** — User makes or confirms an architectural/technology decision outside of a coding task (e.g., "Redis kullanacağız", "bu pattern'i seçelim") → DECISION CAPTURE workflow.
- **User says** "bunu kaydet", "save this source", "şu URL'yi ingest et", or a lint data-gap suggestion is approved → WEB SOURCE CAPTURE workflow.
- **Threshold trigger (ingest-based):** After writing a new `ingest` entry to `_LOG.md`, count total `ingest` entries. If count is a multiple of 5 (5, 10, 15, ...), ASK the user: *"Son 5 ingest'ten sonra tam bir lint öneriyorum — çalıştırayım mı?"* — NEVER auto-run lint.
- **Threshold trigger (time-based):** At session start, after reading `_LOG.md`, check the date of the last `lint` entry. If 7+ days have passed since the last lint, ASK the user: *"Son lint'ten bu yana 7+ gün geçmiş — bir sağlık kontrolü öneriyorum. Çalıştırayım mı?"* — NEVER auto-run lint.
- **Ingest with image references** → the standard INGEST workflow activates IMAGE READING WORKFLOW (operation 8) as a sub-step when `raw_sources/assets/` contains files referenced by the new source.
</trigger_conditions>

<operations>
When the user asks you to interact with the Second Brain, execute one of these strict workflows:

1. INGEST (Processing new sources — interactive by default):
   - **CONTEXT SCAN (MANDATORY FIRST STEP):** Read `_INDEX.md` to understand what wiki pages ALREADY exist. This prevents duplicate pages and ensures you UPDATE existing pages instead of creating redundant ones.
   - Read the new file(s) from `raw_sources/`.
   - **INTERACTIVE DISCUSSION (DEFAULT):** Present key takeaways to the user and discuss what to emphasize, what's surprising, and what contradicts existing knowledge. This is how the human stays in the loop as curator. ONLY skip this step if the user explicitly says "sessiz ingest" or "skip discussion".
   - MANDATORY SOURCE SUMMARY: Create a `source-summary` page in `wiki/summaries/<source-slug>.md` using the `_SCHEMA.md` source-summary template. This page captures the source's key takeaways, wiki impact, and any contradictions. Every raw_source MUST have exactly one corresponding summary page.
   - Create or update relevant concept/entity pages in the `wiki/` (follow `_SCHEMA.md` templates and frontmatter). A single source may touch 10-15 existing wiki pages — be thorough.
   - Synthesize contradictions: If new data contradicts old data, note it explicitly in the wiki pages using the strike-through pattern from `_SCHEMA.md` Section 9.
   - Update `_INDEX.md` with any new pages (including the new source-summary).
   - Update `_SEARCH_INDEX.md` with new/modified page rows (Type, Tags, Key Terms, Summary). See `_SCHEMA.md` Section 13.
   - Append an entry to `_LOG.md` (e.g., `## [2026-04-07] ingest | Read API Documentation v2`).
   - Run threshold check (see `<trigger_conditions>`).

1b. BATCH INGEST (Processing multiple sources at once):
   - **CONTEXT SCAN:** Same as INGEST step 1 — read `_INDEX.md` first.
   - List all new files in `raw_sources/` that lack a corresponding `summaries/<source-slug>.md`.
   - Present the list to the user: *"Şu N kaynak henüz işlenmemiş: [list]. Hepsini sırayla mı işleyeyim, yoksa öncelik sıranız var mı?"*
   - Process each source sequentially using the INGEST workflow above. Between sources, provide a brief progress update.
   - After ALL sources are processed, run a single lint pass to catch cross-source contradictions and missing cross-references.

2. QUERY & COMPILE (Answering questions):
   - Read `_INDEX.md` to locate relevant wiki pages, then read those specific pages.
   - **SESSION CONTEXT CHECK:** If the query references past conversations (e.g., "geçen hafta ne konuştuk?", "daha önce şunu tartışmıştık"), check `_SEARCH_INDEX.md` for `session-summary` type entries. Read matched session summaries to retrieve conversational context.
   - Synthesize the answer using strict citations from the wiki.
   - QUERY WRITE-BACK (USER APPROVAL REQUIRED): If your synthesized answer combines **3+ wiki pages** OR exceeds **~200 words of analysis**, you MUST ASK the user: *"Bu analizi `wiki/insights/YYYY-MM-DD-<konu>.md` altına insight olarak kaydedeyim mi?"* — If approved: create the insight page using `_SCHEMA.md` insight template, update `_INDEX.md`, update `_SEARCH_INDEX.md` with the new insight row, append `query` entry to `_LOG.md`. **NEVER auto-save without explicit user approval.**

3. LINT (Health Check & Maintenance):
   - Triggered when the user asks to "lint" or "clean" the wiki (or via threshold trigger — see `<trigger_conditions>`).
   - Scan the `wiki/` directory. Perform ALL of the following:
     - **Broken wikilink detection:** every `[[...]]` reference must resolve to an existing file.
     - **Orphan page detection:** any wiki page (excluding special files) with zero inbound links.
     - **Stale claim detection:** new raw_sources that contradict older wiki claims — surface using `_SCHEMA.md` Section 9 contradiction pattern.
     - **Missing concept pages:** terms that appear frequently across the wiki but have no dedicated page.
     - **Missing cross-references:** pages that logically relate but aren't linked.
     - **Missing source summaries:** every file in `raw_sources/` (excluding `assets/`) MUST have a corresponding `summaries/<source-slug>.md` page. Flag any unmatched sources.
     - **`_SEARCH_INDEX.md` parity:** every `_INDEX.md` entry MUST have a corresponding row in `_SEARCH_INDEX.md` and vice versa. Flag any mismatches and fix them.
     - **Data gap suggestions:** areas where a web search could fill knowledge holes — ASK the user before running any web search, NEVER auto-search.
   - Report all findings to the user; do not auto-fix without explicit approval.

4. ARCHIVE (Retiring stale wiki pages):
   - Triggered when a wiki page is outdated, superseded, or no longer relevant to the active project state.
   - Move the page to `wiki/archive/<original-name>.md`.
   - Update the page's frontmatter: set `status: archive` and `type: archive`.
   - Update `_INDEX.md`: remove from its original category, add a single-line entry under "Archive".
   - Update `_SEARCH_INDEX.md`: update the archived page's row with `archive/` prefix in the Page column.
   - Update all inbound `[[wikilinks]]` across the wiki to point to `archive/<original-name>` (or remove if the reference is no longer meaningful).
   - Append a `migration` entry to `_LOG.md` explaining what was archived and why.
   - NEVER delete wiki pages — always archive.

5. DECISION CAPTURE (Persisting ad-hoc architectural decisions):
   - Triggered when the user makes or confirms a significant **project-level** architectural/technology decision during a conversation that is NOT part of a code-commit flow.
   - **BOUNDARY with `self-improvement-curator`:** This workflow captures decisions about **the project** (which technology, which pattern, which endpoint design — things another developer without Claude would still follow). Decisions about **how the agent itself should work** (rule changes, skill updates, workflow preferences) are handled by `self-improvement-curator`'s `decision` signal → `_IMPROVEMENT_QUEUE.md`, NOT this workflow. Decision tree: *"If a new developer joined the team without Claude, would this decision still apply to them?"* → Yes = this workflow (wiki) / No = `self-improvement-curator` (queue). If both apply, split into two captures.
   - ASK the user: *"Bu kararı wiki'ye kaydetmemi ister misiniz?"* — NEVER auto-capture without approval.
   - If approved:
     - Read `wiki/architecture-decisions.md` to find the latest AD-XX number.
     - Append a new AD entry using the `_SCHEMA.md` decision template (Karar → Bağlam → Alternatifler → Sonuç).
     - Update `_INDEX.md` if the decision count changed significantly or a new category emerged.
     - Update `_SEARCH_INDEX.md`: update the `architecture-decisions` row's Key Terms with the new AD-XX ID.
     - Append a `decision` entry to `_LOG.md`.
   - This workflow prevents valuable design rationale from being lost in chat history — a core Karpathy principle: *"Nothing should disappear into chat history."*

6. UN-INGESTED SOURCE PARITY CHECK (Session-start auto-scan):
   - Triggered silently at every session start, AFTER reading `_INDEX.md`.
   - Scan `docs/second-brain/raw_sources/` for all files (excluding `assets/` subdirectory).
   - For each file, check if a corresponding `wiki/summaries/<source-slug>.md` exists.
   - If **all sources have summaries**: stay silent, proceed normally.
   - If **un-ingested sources are found**: report to the user: *"Şu N kaynak henüz wiki'ye ingest edilmemiş: [list]. İşlememi ister misiniz?"* — NEVER auto-ingest without approval.
   - Karpathy principle: *"Every source should be integrated into the wiki. Raw sources without summaries are dead weight."*

7. WEB SOURCE CAPTURE (Saving external knowledge to raw_sources):
   - Triggered when: (a) a lint "data gap" suggestion is approved by the user, OR (b) the user explicitly says "bunu kaydet", "save this source", "şu URL'yi ingest et", OR (c) the agent discovers critical external documentation during brainstorming/debugging that would benefit the wiki.
   - ALWAYS ASK the user before saving: *"Bu bilgiyi raw_sources'a kaydedip wiki'ye ingest etmemi ister misiniz?"* — NEVER auto-save.
   - If approved:
     1. Fetch the content (via WebFetch or copy from chat context).
     2. Save as `docs/second-brain/raw_sources/YYYY-MM-DD-<descriptive-slug>.md` with a YAML header noting the original URL/source.
     3. Immediately trigger the INGEST workflow (operation #1) for the new file.
   - This closes the loop between lint's "data gap suggestions" and actual knowledge acquisition — a gap in the original Karpathy pattern where lint detects missing knowledge but provides no structured path to fill it.

8. IMAGE READING WORKFLOW (Karpathy Image Pattern — sub-step of INGEST):
   - Triggered during INGEST when `docs/second-brain/raw_sources/assets/` contains image files referenced by the incoming source (`![[...]]` or `![](../raw_sources/assets/...)` syntax).
   - Reason: LLMs cannot read markdown with inline images in one pass. The canonical pattern isolates text reading from image viewing.
   - Protocol (per `_SCHEMA.md` Section 17):
     1. Read the source markdown text first (establish full textual context).
     2. Identify all image references in the text.
     3. View each referenced image separately via your native image-read capability.
     4. Fuse text + image content in the `summaries/<source-slug>.md` page under a dedicated "Görseller / Images" heading.
   - Storage: images live under `raw_sources/assets/` per `_SCHEMA.md` Section 12.
   - Never attempt to describe an image without viewing it; cite "(not viewed)" if viewing is blocked.
</operations>

<wiki_formatting_and_search>
CANONICAL SCHEMA SOURCE:
All format rules — page types, YAML frontmatter schemas, naming conventions, page templates, cross-reference rules, _LOG.md entry format — are defined in `docs/second-brain/wiki/_SCHEMA.md`. You MUST read this file BEFORE creating or editing any wiki page (if not already loaded in this session) — loaded automatically, no user action required. Do NOT load it at session start. Do not duplicate schema details in skills, code, or memory; always defer to `_SCHEMA.md` as the single source of truth.

## INFORMATION GAP RESOLUTION — Four-Tier Search (single canonical workflow)

> **CANONICAL EAGER LAYER:** the trigger patterns, Hard Rule, concrete Tier-1 commands, score threshold (0.5), and Self-Check rule live in `.openskills/superpowers-agent-mode-prompt.md` `<information_gap_routing>` so that the routing fires BEFORE this lazy skill loads. This section provides the FULL OPERATIONAL DETAIL — multi-collection Qdrant routing (1a/1b/1c), Tier-2 Graphify commands, and the structural decision tree — when this skill is invoked for ingest / code-commit / lint workflows or when an information gap is deep enough to warrant the full tier walk.
>
> If a contradiction appears between this section and the eager `<information_gap_routing>` block, the eager block wins (per `<authority_hierarchy>`).

Do not redefine trigger detection in this section. If trigger behavior changes, update the canonical eager layer first, then keep this section as operational detail.

This workflow MUST run whenever an information gap appears, regardless of source:
- The user asks a question that needs prior context (decisions, sessions, code structure).
- You internally recognize a gap while coding, refactoring, debugging, or planning ("what methods does this entity have?", "where is this exception thrown?", "why did we choose this pattern?", "what did we agree on last session?").

There is NO separate "user query" vs "agent reasoning" branch. Same tiers, same order, same hard rule.

### Tier order — STRICTLY in this sequence

| Tier | System | Command | When |
|---|---|---|---|
| 1a | Qdrant `chat_history` | `python .openskills/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<query>" --limit 3` | Past sessions, prior decisions, "geçen hafta", "daha önce" |
| 1b | Qdrant `wiki_pages` | `python .openskills/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<query>" --collection wiki_pages` | Curated knowledge — ADRs, entity defs, sprint plans (semantic) |
| 1c | Qdrant `code_chunks` | `python .openskills/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<query>" --collection code_chunks` | Source code semantic search (when Graphify lookup is too narrow) |
| 2 | Graphify graph (read directly via `query-graph.py`) | `python .openskills/memory-plugins/graphify-code-graph/scripts/query-graph.py "<symbol>"` (primary, surfaces call edges); `graphify query` / `explain` / `path` (secondary, cluster/community) | Function/class lookup, call graph, callers/callees, impact analysis |
| 3 | Obsidian `_SEARCH_INDEX.md` | Match keyword against Tags + Key Terms columns, then read matched pages | ADRs, sprint plans, entity definitions, documented patterns |
| 4 | Grep / Read fallback | `grep` / `Select-String` / `Read` on known path | Exact string match when Tiers 1–3 return nothing |

### Hard Rule — Historical / Decision Questions

Any question referencing past sessions, sprint choices, architecture rationale, or documented decisions is AUTOMATICALLY a Tier-1 + Tier-3 candidate. NEVER skip these tiers by going directly to a known file path. Direct `Read` on a known path for a "why" or "what did we decide" question is a workflow violation.

### Self-Check Before Any `Read`

Before issuing a `Read` tool call to answer a historical/decision/structural question, silently confirm: *"Did I check Tier 1 (Qdrant) and Tier 3 (`_SEARCH_INDEX.md`) first?"* If not, run them before the `Read`.

### Decision tree (auto-apply, no user input needed)

```
Information gap detected.
├── Past session / prior decision / "why" question?
│   └── YES → Tier 1 (Qdrant). Then Tier 3 if more context needed.
├── Code structure / call graph / impact analysis?
│   └── YES → Tier 2 (Graphify).
├── ADR / sprint plan / entity definition?
│   └── YES → Tier 3 (`_SEARCH_INDEX.md` keyword match → read matched pages).
└── Else → Tier 4 (grep / Read on known path).
```

### Citation rule

When you synthesize an answer from any tier, cite the source path or query result so the user can audit (e.g., `wiki/architecture-decisions.md#AD-07`, `Qdrant chat_history score=0.71 from 2026-04-28-sprint12-following-feed`).

SEARCH INDEX MAINTENANCE (MANDATORY):
After every INGEST, CODE-COMMIT, or LINT operation that creates or updates wiki pages, you MUST update `_SEARCH_INDEX.md` by adding/modifying the corresponding row(s). Format rules are in `_SCHEMA.md` Section 13.

SCALING NOTE:
At ~1000+ wiki pages, promote Qdrant + Graphify to primary and use `_SEARCH_INDEX.md` as secondary. See `_SCHEMA.md` Section 13 and Section 16.

ASSET LINKING:
Images and diagrams live in `docs/second-brain/raw_sources/assets/`. Use Obsidian embed format: `![[image_name.png]]` or standard markdown `![Alt](../raw_sources/assets/image.png)`.

ARTIFACT LINKING (CRITICAL FORMAT RULE):
Artifacts (`artifacts/plans/`, `artifacts/specs/`) live OUTSIDE the `wiki/` directory. Per `_SCHEMA.md` Section 5, all references to artifacts MUST use **standard markdown links** (relative paths), NOT Obsidian wikilinks. Example: `[2026-04-08-feature-plan](../artifacts/plans/2026-04-08-feature-plan.md)`.
</wiki_formatting_and_search>

<development_context_hook>
When finishing a coding task (via `finishing-a-development-branch`), treat it as an INGEST operation:
- Update `wiki/active-project-context.md` with the new codebase state.
- Append a `code-commit` entry to `_LOG.md` detailing the architectural changes or bug fixes.
- **AUTOMATIC MEMORY SYNC:** Run `python .openskills/memory-plugins/graphify-code-graph/scripts/auto-update-memory.py` after every code-commit or branch finish. This rebuilds the Graphify code graph, syncs insights to the wiki, and verifies Qdrant health with zero user intervention. NEVER ask the user for permission; only report errors if they occur.
- **USER REPORT (MANDATORY):** After the script executes, read its stdout output (specifically the `MEMORY UPDATE REPORT` block) and present a brief Turkish summary to the user so they know the memory stack was maintained. Example:
  > "Bellek bakımı tamamlandı. Graphify kod graph'ı güncellendi, wiki senkronizasyonu tamam, Qdrant ulaşılabilir durumda."
</development_context_hook>
