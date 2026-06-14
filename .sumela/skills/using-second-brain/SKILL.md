---
name: using-second-brain
description: "Use when starting a session, ingesting a raw source, finishing a branch, answering a question that may reference prior work, or facing an information gap during reasoning (entity definitions, past decisions, call graphs, prior session context)."
---

<brain_architecture>
The Second Brain is stored in `docs/second-brain/` (or your chosen Obsidian vault). It has three distinct layers (Karpathy pattern):

1. `raw_sources/`: IMMUTABLE. User-provided articles, logs, PDFs, meeting notes. You MUST READ from here but NEVER modify these files.
2. `artifacts/`: IMMUTABLE (write-once). LLM-generated plans (`artifacts/plans/`) and specs (`artifacts/specs/`). Created by `writing-plans` and `brainstorming` skills. Once written, NEVER modified.
3. `wiki/`: LIVE SYNTHESIS. A structured, interlinked directory of markdown files. You own this layer entirely. You create, update, and maintain cross-references here. This is where knowledge compounds.

Schema (Configuration): Format rules live in `wiki/_SCHEMA.md`. Behavioral rules live in `.sumela/SKILL_REGISTRY.md` and this skill file.

Reliability invariant: For this skill, Second Brain correctness and recoverability are more important than token reduction. Do not remove routing tiers, write gates, parity checks, or memory-sync steps solely to reduce context cost; simplify only when behavior remains at least as safe.
</brain_architecture>

<core_indexes>
The `wiki/` directory has FIVE special files (frontmatter-free, governed by `_SCHEMA.md`):
- `_INDEX.md`: Human-optimized content catalog. Read this FIRST every session for navigation.
- `_SEARCH_INDEX.md`: Agent-optimized search index. A table with per-page Type, Tags, Key Terms, and Summary columns. Use this for targeted search: match query terms against Key Terms/Tags → read only matched pages. Scales to hundreds of pages with zero runtime dependencies. Updated during every ingest/code-commit/lint.
- `_LOG.md`: Chronological append-only log. Format: `## [YYYY-MM-DD] type | topic` (parse-friendly). Type whitelist: `ingest | query | lint | code-commit | decision | migration`. NEVER rewrite past entries — they are immutable history.
- `_LOG.md` note: `_SCHEMA.md` is the canonical whitelist source; `evolve` is a valid log type for self-improvement applications.
- `_SCHEMA.md`: Canonical format source. Read this BEFORE writing any wiki page. Defines page types, frontmatter schemas, naming, templates, and cross-ref conventions.
- `_improvement-queue/`: Self-improvement queue — a directory, one `IMP-*.md` per signal. Managed by `self-improvement-curator` skill and reviewed via `/evolve`. At session start, surface the pending count by globbing `IMP-*.md` (never scan the whole dir — the `README.md` example would inflate the count). Do NOT modify as part of normal wiki operations — it has its own workflow.
</core_indexes>

<trigger_conditions>
Determine which workflow to execute based on these signals (highest specificity wins):

- **Session start** → bootstrap reads + parity + queue count are governed by `.sumela/sumela-prompt.md` (`<session_bootstrap>`). This skill is invoked LAZILY when an information gap appears or one of the triggers below fires.
- **User says** "save", "add to wiki", "ingest", "note this", "remember this" (or the equivalent in any language) → INGEST workflow.
- **User drops multiple sources** or says "batch ingest", "process all" (or the equivalent in any language) → BATCH INGEST workflow.

- **User says** "clean the wiki", "lint", "health check" (or the equivalent in any language) → LINT workflow.
- **Ad-hoc decision during conversation** — User makes or confirms an architectural/technology decision outside of a coding task (e.g., "let's use Redis", "select this pattern") → DECISION CAPTURE workflow.
- **User says** "save this", "save this source", "ingest that URL" (or the equivalent in any language), or a lint data-gap suggestion is approved → WEB SOURCE CAPTURE workflow.
- **Threshold trigger (ingest-based):** After writing a new `ingest` entry to `_LOG.md`, count total `ingest` entries. If count is a multiple of 5 (5, 10, 15, ...), ASK the user: *"After the last 5 ingests, I recommend a full lint — should I run it?"* — NEVER auto-run lint.
- **Threshold trigger (time-based):** At session start, after reading `_LOG.md`, check the date of the last `lint` entry. If 7+ days have passed since the last lint, ASK the user: *"It's been 7+ days since the last lint — I recommend a health check. Should I run it?"* — NEVER auto-run lint.
- **Ingest with image references** → the standard INGEST workflow activates IMAGE READING WORKFLOW (operation 8) as a sub-step when `raw_sources/assets/` contains files referenced by the new source.
</trigger_conditions>

<operations>
When the user asks you to interact with the Second Brain, execute one of these strict workflows:

1. INGEST (Processing new sources — interactive by default):
   - **CONTEXT SCAN (MANDATORY FIRST STEP):** Read `_INDEX.md` to understand what wiki pages ALREADY exist. This prevents duplicate pages and ensures you UPDATE existing pages instead of creating redundant ones.
   - Read the new file(s) from `raw_sources/`.
   - **INTERACTIVE DISCUSSION (DEFAULT):** Present key takeaways to the user and discuss what to emphasize, what's surprising, and what contradicts existing knowledge. This is how the human stays in the loop as curator. ONLY skip this step if the user explicitly says "silent ingest" or "skip discussion".
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
   - Present the list to the user: *"These {N} sources have not been processed yet: [list]. Should I process them all in order, or do you have a priority?"*
   - Process each source sequentially using the INGEST workflow above. Between sources, provide a brief progress update.
   - After ALL sources are processed, run a single lint pass to catch cross-source contradictions and missing cross-references.

2. QUERY & COMPILE (Answering questions):
   - Read `_INDEX.md` to locate relevant wiki pages, then read those specific pages.
   - **SESSION CONTEXT CHECK:** If the query references past conversations (e.g., "what did we discuss last week?", "we discussed this before" — or the equivalent in any language), check `_SEARCH_INDEX.md` for `session-summary` type entries. Read matched session summaries to retrieve conversational context.
   - Synthesize the answer using strict citations from the wiki.
   - QUERY WRITE-BACK (USER APPROVAL REQUIRED): If your synthesized answer combines **3+ wiki pages** OR exceeds **~200 words of analysis**, you MUST ASK the user: *"Should I save this analysis as an insight page at `wiki/insights/YYYY-MM-DD-<topic>.md`?"* — If approved: create the insight page using `_SCHEMA.md` insight template, update `_INDEX.md`, update `_SEARCH_INDEX.md` with the new insight row, append `query` entry to `_LOG.md`. **NEVER auto-save without explicit user approval.**

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
   - **BOUNDARY with `self-improvement-curator`:** This workflow captures decisions about **the project** (which technology, which pattern, which endpoint design — things another developer without Claude would still follow). Decisions about **how the agent itself should work** (rule changes, skill updates, workflow preferences) are handled by `self-improvement-curator`'s `decision` signal → `_improvement-queue/`, NOT this workflow. Decision tree: *"If a new developer joined the team without Claude, would this decision still apply to them?"* → Yes = this workflow (wiki) / No = `self-improvement-curator` (queue). If both apply, split into two captures.
   - ASK the user: *"Would you like me to save this decision to the wiki?"* — NEVER auto-capture without approval.
   - If approved:
     - Read `wiki/architecture-decisions.md` to find the latest AD-XX number.
     - Append a new AD entry using the `_SCHEMA.md` decision template (Decision → Context → Alternatives → Outcome).
     - Update `_INDEX.md` if the decision count changed significantly or a new category emerged.
     - Update `_SEARCH_INDEX.md`: update the `architecture-decisions` row's Key Terms with the new AD-XX ID.
     - Append a `decision` entry to `_LOG.md`.
   - This workflow prevents valuable design rationale from being lost in chat history — a core Karpathy principle: *"Nothing should disappear into chat history."*

6. UN-INGESTED SOURCE PARITY CHECK (Session-start auto-scan):
   - Triggered silently at every session start, AFTER reading `_INDEX.md`.
   - Scan `docs/second-brain/raw_sources/` for all files (excluding `assets/` subdirectory).
   - For each file, check if a corresponding `wiki/summaries/<source-slug>.md` exists.
   - If **all sources have summaries**: stay silent, proceed normally.
   - If **un-ingested sources are found**: report to the user: *"These {N} sources have not been ingested into the wiki yet: [list]. Would you like me to process them?"* — NEVER auto-ingest without approval.
   - Karpathy principle: *"Every source should be integrated into the wiki. Raw sources without summaries are dead weight."*

7. WEB SOURCE CAPTURE (Saving external knowledge to raw_sources):
   - Triggered when: (a) a lint "data gap" suggestion is approved by the user, OR (b) the user explicitly says "save this", "save this source", "ingest that URL" (or the equivalent in any language), OR (c) the agent discovers critical external documentation during brainstorming/debugging that would benefit the wiki.
   - ALWAYS ASK the user before saving: *"Want me to save this to raw_sources and ingest it into the wiki?"* — NEVER auto-save.
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
      4. Fuse text + image content in the `summaries/<source-slug>.md` page under a dedicated "Images" heading.
   - Storage: images live under `raw_sources/assets/` per `_SCHEMA.md` Section 12.
   - Never attempt to describe an image without viewing it; cite "(not viewed)" if viewing is blocked.

9. SESSION SUMMARY (canonical — see `<session_summary_protocol>` below):
   - The per-session conversational work record (who did what, decisions + rationale, artifacts) written to `wiki/session-summaries/` and ingested into Qdrant `chat_history`. Both `finishing-a-development-branch` (task completion) and `context-handoff` (context pressure) invoke THIS protocol — it is the single source of truth so the two triggers never drift.
</operations>

<session_summary_protocol>
## Session Summary Protocol (canonical — referenced by context-handoff + finishing-a-development-branch)

Persists the session's conversational context as a structured, queryable wiki page + Qdrant `chat_history` record. This is how a future session or teammate answers "what did <developer> do last week, in which domain, and why".

### When invoked
- **Task/branch completion** — `finishing-a-development-branch` Step 7 (so EVERY finished task leaves a record, even with no handoff).
- **Context-pressure handoff** — `context-handoff` Protocol A/B Step 3.
- **Explicit** — user asks to "save the session".
If a summary for the same task already exists for today, UPDATE/supersede it (do not create a near-duplicate); idempotent re-ingest makes re-running safe.

### Capture (stamp the frontmatter — this is what makes memory queryable)
Resolve and write into the `session-summary` frontmatter (format = `_SCHEMA.md` Session Summary Page Template):
- `developer` ← `git config user.name` (the person who DID the work); `unknown` if unset. `developer_email` ← `git config user.email` (optional).
- `domains` ← the session's domain context, written in the CANONICAL casing from `RULE_REGISTRY.md` `<domain_scopes>` (e.g. `Card`, not `card`) so `--domain` queries match reliably (the Qdrant filter is exact-match): default to `.sumela/local.md` `domains` resolved to that canonical casing; refine if the work explicitly belonged to a different domain.
- `spec_artifact` / `plan_artifact` ← paths of the spec/plan this task produced or used, if any (find them via `active-project-context.md` links or the plan you executed). Omit if none.
- `session_date` ← today (ISO); `session_topics` ← 2-5 topics.

### Content (substantive — NOT lip-service)
Fill every applicable section of the template with real detail: Topics; **Decisions Made with their rationale**; **Work Completed** (concrete changes + commit hash(es) + files); Artifacts (spec/plan links); Open Questions/Blockers; Related Wiki Pages. A pointer-only stub defeats the memory — capture enough that the work is reconstructable. Keep the `## Decisions Made` heading verbatim (parsed by `session-ingest.py`).

### Steps
1. Read `_SCHEMA.md` Session Summary Page Template (if not already in context).
2. Create `docs/second-brain/wiki/session-summaries/YYYY-MM-DD-<topic>.md` (kebab-case dominant topic) from the template; `mkdir -p` the directory if absent.
3. Update `_SEARCH_INDEX.md` with a row for the new summary (Type `session-summary`); update `_INDEX.md` Session Summaries section on the first summary or a milestone.
4. Ingest into Qdrant `chat_history`:
   ```bash
   python .sumela/memory-plugins/qdrant-session-memory/scripts/session-ingest.py docs/second-brain/wiki/session-summaries/YYYY-MM-DD-<topic>.md
   ```
   Reads the frontmatter (developer/domains/session_date/spec/plan) into the payload. If Qdrant is down, the markdown remains and the next pull's hook re-ingests — no retry needed. Relay the `SESSION INGEST REPORT` to the user in the configured language.
5. COMMIT it. The summary lands in your LOCAL Qdrant immediately, but cross-developer recall ("what did X do") needs the markdown COMMITTED so teammates pull it and their post-merge hook ingests it into their own Qdrant. In `finishing-a-development-branch` the code was committed earlier (Step 2), so explicitly commit the new `session-summaries/` file + the `_SEARCH_INDEX`/`_INDEX` updates (a small `docs(memory): session summary` commit is fine). If you already PUSHED in that flow (PR path), push again so the summary reaches the remote/PR. Uncommitted summaries are author-local only.
</session_summary_protocol>

<wiki_formatting_and_search>
CANONICAL SCHEMA SOURCE:
All format rules — page types, YAML frontmatter schemas, naming conventions, page templates, cross-reference rules, _LOG.md entry format — are defined in `docs/second-brain/wiki/_SCHEMA.md`. You MUST read this file BEFORE creating or editing any wiki page (if not already loaded in this session) — loaded automatically, no user action required. Do NOT load it at session start. Do not duplicate schema details in skills, code, or memory; always defer to `_SCHEMA.md` as the single source of truth.

## INFORMATION GAP RESOLUTION — Four-Tier Search (single canonical workflow)

> **CANONICAL EAGER LAYER:** the trigger patterns, Hard Rule, concrete Tier-1 commands, score threshold (0.5), and Self-Check rule live in `.sumela/sumela-prompt.md` `<information_gap_routing>` so that the routing fires BEFORE this lazy skill loads. This section provides the FULL OPERATIONAL DETAIL — multi-collection Qdrant routing (1a/1b/1c), Tier-2 Graphify commands, and the structural decision tree — when this skill is invoked for ingest / code-commit / lint workflows or when an information gap is deep enough to warrant the full tier walk.
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
| 1a | Qdrant `chat_history` | `python .sumela/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<query>" --limit 3` | Past sessions, prior decisions, "last week", "previously" |
| 1b | Qdrant `wiki_pages` | `python .sumela/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<query>" --collection wiki_pages` | Curated knowledge — ADRs, entity defs, sprint plans (semantic) |
| 1c | Qdrant `code_chunks` | `python .sumela/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<query>" --collection code_chunks` | Source code semantic search (when Graphify lookup is too narrow) |
| 2 | Graphify graph (read directly via `query-graph.py`) | `python .sumela/memory-plugins/graphify-code-graph/scripts/query-graph.py "<symbol>"` (primary, surfaces call edges); `graphify query` / `explain` / `path` (secondary, cluster/community) | Function/class lookup, call graph, callers/callees, impact analysis |
| 3 | Obsidian `_SEARCH_INDEX.md` | Match keyword against Tags + Key Terms columns, then read matched pages | ADRs, sprint plans, entity definitions, documented patterns |
| 4 | Grep / Read fallback | `grep` / `Select-String` / `Read` on known path | Exact string match when Tiers 1–3 return nothing |

### Hard Rule — route by family before any direct `Read`

Family definitions are canonical in the eager `<information_gap_routing>` block; this is operational detail only. Match the question to a family and run its tier(s) BEFORE going to a known file path:
- FAMILY A (past sessions, sprint choices, architecture rationale, documented decisions) → Tier-1 (`chat_history`), then Tier-3 if more context is needed. **Best-effort:** query when `chat_history` has content; skip when it is known-empty and note that once per session. (FAMILY A is NOT mandatory — only B and C are.)
- FAMILY B (call-graph / callers / impact on a named **symbol** — the symbol NAME is known) → Tier-2 (Graphify graph first); escalate to Tier-1c (`code_chunks`) if the graph is too narrow.
- FAMILY C (project reference / how-to / convention / "where is it documented") → Tier-3 (`_SEARCH_INDEX.md`), escalate to Tier-1b (`wiki_pages`).
- GATE 3 (a workflow gate from `<workflow_retrieval_gates>`, NOT a question-family — find code by BEHAVIOR, no symbol name known) → Tier-1c (`code_chunks` semantic) FIRST, before any blind grep. Discriminator vs FAMILY B: symbol name known → FAMILY B (graph first); no name, want to find code by behavior → GATE 3 (`code_chunks` first). Exact-token grep stays first-class for a literal string you already know.
Direct `Read`/`grep` on a known path for a question that matches FAMILY B or FAMILY C — bypassing its tier — is a workflow violation. FAMILY B and FAMILY C tiers are MANDATORY; FAMILY A is best-effort.

### Self-Check Before Any `Read`

Before issuing a `Read` tool call, silently confirm: *"Which family is this (A/B/C, GATE 3, or none)? Did I run that family's tier(s) — Tier-1 / Tier-2(+1c) / Tier-3(+1b) — first?"* For FAMILY B and FAMILY C the tier is MANDATORY — run it before the `Read`. FAMILY A is best-effort (query `chat_history` only when it has content; skip when known-empty, note once per session). (A pure-conversation or in-progress-edit turn matches no family — no tier required.)

### Decision tree (auto-apply, no user input needed)

```
Information gap detected.
├── Past session / prior decision / "why" question? (FAMILY A — best-effort)
│   └── YES → Tier 1 (Qdrant `chat_history`) WHEN it has content; skip when known-empty (note once per session). Then Tier 3 if more context needed.
├── Code structure / call graph / impact on a NAMED symbol? (FAMILY B — mandatory)
│   └── YES → Tier 2 (Graphify graph FIRST). Escalate to Tier 1c (`code_chunks` semantic) if the graph is too narrow.
├── Want to FIND code by BEHAVIOR, no symbol name known? (GATE 3)
│   └── YES → Tier 1c (`code_chunks` semantic) FIRST, before any blind grep. (Symbol name known → FAMILY B instead. Literal token known → exact-token grep, first-class.)
├── Project reference / how-to / convention / "where is it documented" / ADR / sprint plan / entity definition? (FAMILY C — mandatory)
│   └── YES → Tier 3 (`_SEARCH_INDEX.md` keyword match → read matched pages) → escalate to Tier 1b (`wiki_pages` semantic) if the index misses.
└── Else → Tier 4 (grep / Read on known path).
```

**Workflow retrieval gates (canonical in the eager block):** three SOFT/best-effort lifecycle gates live in `.sumela/sumela-prompt.md` `<workflow_retrieval_gates>` — GATE 1 task-intake (brainstorming entry → Tier-3 `_SEARCH_INDEX` + Tier-1b `wiki_pages`), GATE 2 impact-before-contract-change (`query-graph.py <symbol> --impact --depth 1 --limit 10`), GATE 3 find-code-by-behavior (`query-qdrant.py --collection code_chunks` before blind grep). They are best-effort, not mandatory. The eager block is canonical; this file is operational detail only — do not redefine trigger detection here.

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
- **AUTOMATIC MEMORY SYNC:** Run `python scripts/auto-update-memory.py` after every code-commit or branch finish. This rebuilds the Graphify code graph, syncs insights to the wiki, and verifies Qdrant health with zero user intervention. NEVER ask the user for permission; only report errors if they occur.
- **USER REPORT (MANDATORY):** After the script executes, read its stdout output (specifically the `MEMORY UPDATE REPORT` block) and present a brief summary to the user in the project's configured language so they know the memory stack was maintained. Example:
  > "Memory maintenance complete. Graphify code graph updated, wiki sync ok, Qdrant reachable."
</development_context_hook>
