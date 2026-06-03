# Second Brain Schema

> **This file is the canonical format source.** The wiki's structure, page templates, frontmatter schema, and naming conventions are defined here. The `using-second-brain` skill points to this file and does not duplicate the details. When setting up second-brain in a new project, copy `_SCHEMA.md` as-is — it is entirely project-independent.

---

## 1. Three-Layer Architecture

Karpathy's LLM Wiki pattern is based on three distinct layers:

```
docs/second-brain/
├── raw_sources/      ← IMMUTABLE. Raw sources provided by the user.
│   └── assets/       ← Images, diagrams, downloaded attachments.
├── artifacts/        ← IMMUTABLE. LLM-generated but write-once documents.
│   ├── plans/        ← writing-plans skill outputs.
│   └── specs/        ← brainstorming skill outputs.
└── wiki/             ← LIVE. Synthesis layer continuously updated by the LLM.
    ├── archive/      ← Pages retired from the wiki but not deleted.
    ├── insights/     ← Analyses saved via query write-back.
    ├── summaries/    ← LLM-generated summary page for each raw_source file.
    ├── _INDEX.md          ← Special: human-optimized content catalog.
    ├── _LOG.md            ← Special: chronological activity log.
    ├── _SCHEMA.md         ← Special: this file.
    ├── _SEARCH_INDEX.md   ← Special: agent-optimized search index.
    └── *.md               ← Synthesis pages (entity, concept, decision, core).
```

**Layer rules:**
- `raw_sources/`: The LLM **reads** from this folder, **never writes**. Raw and immutable.
- `artifacts/`: The LLM **writes** to this folder (as skill output), then **does not touch it**. Write-once.
- `wiki/`: The LLM **continuously updates** this folder. Synthesis, contradiction resolution, and cross-referencing live here.

---

## 2. Page Types

Every wiki page falls under a type. The type is specified in the frontmatter via the `type:` field.

| Type | Description | Example |
|---|---|---|
| `core` | The project's foundational reference pages | `architecture-and-stack`, `developer-onboarding`, `active-project-context` |
| `entity` | An entity or domain object in the system | `domain-entities`, `user-model`, `payment-flow` |
| `concept` | A concept, pattern, or subsystem | `api-registry`, `tech-debt-and-known-issues`, `caching-strategy` |
| `decision` | Architecture decision records (ADR-style) | `architecture-decisions` |
| `insight` | Analyses saved from query write-back | `insights/2026-04-08-cache-vs-redis-comparison` |
| `archive` | Content no longer in active use but retained | `archive/sprint-history` |
| `source-summary` | A summary of a raw_source file | `summaries/karpathy-llm-wiki` |

**Special files (DO NOT take frontmatter):** `_INDEX.md`, `_LOG.md`, `_SCHEMA.md`, `_SEARCH_INDEX.md`

---

## 3. YAML Frontmatter Schema

Every wiki page (EXCEPT special files) MUST begin with this frontmatter:

```yaml
---
type: entity              # required — page type (from the table above)
tags: [domain, auth]      # required — minimum 1 tag; for search and Dataview
date_created: 2026-04-08  # required — ISO 8601 (YYYY-MM-DD)
date_updated: 2026-04-08  # required — last update date
sources_referenced: 0     # optional — number of sources this page was derived from
status: active            # optional — active | archive | deprecated
---
```

**Type-specific additional fields:**

```yaml
# for the decision type:
---
type: decision
decision_id: AD-12        # required — Architecture Decision ID
decision_status: accepted # accepted | superseded | deprecated
superseded_by: AD-15      # optional — if superseded
---

# for the insight type:
---
type: insight
query_origin: "Redis vs in-memory cache comparison"  # required — source question
related_pages: [caching-strategy, performance]
---

# for the source-summary type:
---
type: source-summary
source_path: ../../raw_sources/karpathy-llm-wiki.md  # required
source_type: article | book | meeting | code-snapshot | external
ingested_date: 2026-04-08
---
```

---

## 4. Naming Conventions

| Location | Format | Example |
|---|---|---|
| Wiki pages | `kebab-case.md` | `domain-entities.md`, `tech-debt-and-known-issues.md` |
| Artifacts (plans/specs) | `YYYY-MM-DD-feature-name.md` | `2026-04-08-second-brain-restructure.md` |
| Insights | `insights/YYYY-MM-DD-topic.md` | `insights/2026-04-08-cache-comparison.md` |
| Archive pages | `archive/<original-name>.md` | `archive/sprint-history.md` |
| Source summaries | `summaries/<source-slug>.md` | `summaries/karpathy-llm-wiki.md` |
| Web-captured sources | `raw_sources/YYYY-MM-DD-<slug>.md` | `raw_sources/2026-04-11-react-native-hls.md` |

**Rules:**
- Lowercase only, separated by hyphens (`kebab-case`)
- ASCII only — transliterate non-ASCII letters (e.g. Turkish ı→i, ş→s, ç→c, ğ→g, ö→o, ü→u; German ä→a, ß→ss; French é→e)
- NO spaces
- In dated files, the date ALWAYS comes first

---

## 5. Cross-Reference Convention

**Two formats** are used for references within the wiki:

### Obsidian wikilink (preferred)
```markdown
[[domain-entities]]                    # no extension, kebab-case file name
[[domain-entities|Domain Model]]       # custom label
[[architecture-decisions#AD-05]]       # to a specific heading
```

Obsidian wikilinks are resolved by file name within the vault — no need to know the path. As a result, they work even when files are moved to different folders.

### Standard markdown link (relative path)
```markdown
[domain-entities](./domain-entities.md)
[plan file](../artifacts/plans/2026-04-08-second-brain-restructure.md)
```

**Usage rule:**
- References within the wiki → Obsidian wikilink (`[[...]]`)
- References outside the wiki (artifacts, raw_sources, .sumela) → Standard markdown link (relative path)
- Never use an absolute path

---

## 6. `_LOG.md` Entry Format

`_LOG.md` MUST be parse-friendly. The format Karpathy recommends:

```markdown
## [YYYY-MM-DD] type | topic

- Bullet point description
- Second bullet
- Affected wiki pages: [[page-1]], [[page-2]]
- Commit (if any): `abc1234`
```

**Type whitelist (single word, lowercase):**
| Type | When |
|---|---|
| `ingest` | A new raw_source was processed, wiki pages were updated |
| `query` | A user question was answered and an insight was saved to the wiki |
| `lint` | A wiki health check was performed |
| `code-commit` | A development branch was finished, the wiki was updated to reflect it |
| `decision` | A new architecture decision was recorded (decision page updated) |
| `evolve` | Self-improvement queue review (`/evolve`) — an IMP entry became proposed/applied/superseded |
| `migration` | A structural wiki change (folder move, format update) |

**Parse verification:**
```bash
grep "^## \[" docs/second-brain/wiki/_LOG.md | tail -10
```
This command should list the last 10 entries. No entry should be written in a non-parseable format.

---

## 7. `_INDEX.md` Structure

`_INDEX.md` is a content-oriented catalog. Each active wiki page is listed as one line:

```markdown
[[page-name]] - One-line summary. (Sources: N)
```

**Categories (suggested):**
- **Core Pages** — pages with `type: core`
- **Entity & Concept Pages** — `type: entity` or `type: concept`
- **Decision Records** — `type: decision`
- **Source Summaries** — `type: source-summary` (the summary page for each raw_source)
- **Insights** — `type: insight` (query write-back records)
- **Archive** — `type: archive` (for reference)
- **Artifacts (External)** — pointers to the plans/ and specs/ folders (single line, standard markdown link)

**Rule:** `_INDEX.md` is read at the start of every session, so it must be **compact**. Archive lists should be reduced to a single line.

---

## 8. Page Templates

### Core Page Template

```markdown
---
type: core
tags: [<primary-concern>, <project-name>]
date_created: YYYY-MM-DD
date_updated: YYYY-MM-DD
status: active
---

# [Page Title] — [Project Name]

> **The purpose of this file and how often it is read.** (E.g., "Read at the start of every session.")

---

## [Section 1]
Content...

## [Section 2]
Content...

---

## References
- [[related-page-1]]
- [[related-page-2]]
```

### Entity Page Template

```markdown
---
type: entity
tags: [domain, <feature-area>]
date_created: YYYY-MM-DD
date_updated: YYYY-MM-DD
sources_referenced: 0
status: active
---

# [Entity Name]

## Definition
What is this entity, what does it do?

## Fields / Properties
| Field | Type | Description |
|---|---|---|

## Relationships
- one-to-many with `[[other-entity]]`
- many-to-many with `[[third-entity]]`

## Usage Locations
- `[[api-registry#endpoint-X]]`
- `[[caching-strategy]]`

## Sources
- `../artifacts/specs/YYYY-MM-DD-feature-design.md`
```

### Decision Page Template (Architecture Decision Record)

```markdown
---
type: decision
decision_id: AD-XX
decision_status: accepted
tags: [architecture, <area>]
date_created: YYYY-MM-DD
date_updated: YYYY-MM-DD
---

## AD-XX: [Decision Title]

**Decision:** In one sentence, what was decided.

**Context:** Why was this decision needed? What problems existed?

**Alternatives:** Which options were evaluated?
- Option A: ... (Pros / Cons)
- Option B: ... (Pros / Cons)

**Outcome:** What did the decision lead to? Which pages are affected?
- change on `[[entity-X]]`
- new endpoint in `[[api-registry]]`

**Sources:** `../artifacts/specs/YYYY-MM-DD-design.md`
```

### Insight Page Template (Query Write-Back)

```markdown
---
type: insight
query_origin: "The original question the user asked"
tags: [insight, <area>]
date_created: YYYY-MM-DD
date_updated: YYYY-MM-DD
related_pages: [page-1, page-2]
---

# [Insight Title]

## Question
[The user's original question]

## Answer / Synthesis
[An analysis that combines 3+ wiki pages]

## Linked Pages
- `[[page-1]]` — relevant in this respect
- `[[page-2]]` — relevant in this respect

## Open Questions / Follow-up
- ?
```

### Source Summary Page Template

```markdown
---
type: source-summary
source_path: ../../raw_sources/<filename>
source_type: article
ingested_date: YYYY-MM-DD
tags: [source, <topic>]
date_created: YYYY-MM-DD
date_updated: YYYY-MM-DD
---

# [Source Title]

## Summary
What is this source about? 3-5 sentences.

## Key Takeaways
- Takeaway 1
- Takeaway 2

## Reflection in the Wiki
Which wiki pages did this source update?
- `[[page-1]]` — this part was added
- `[[page-2]]` — this contradiction was noted

## Contradictions
Does this source contradict the existing wiki? How was it resolved?
```

---

## 9. Contradiction Management

The core value of the Karpathy pattern: when new sources refute old claims, this is **explicitly noted in the wiki, not overwritten**.

**Example:**
```markdown
## Cache Strategy

~~Old claim (2026-03-15): All endpoints should be cached with Redis.~~
**Refuted (2026-04-02):** [2026-04-02-cache-analysis-design](../artifacts/specs/2026-04-02-cache-analysis-design.md) → 
only read-heavy endpoints should be placed in Redis; for write-heavy endpoints the cache invalidation cost outweighs the benefit.
```

Contradictions are also recorded in `_LOG.md` as a `decision` entry.

---

## 10. Special Files Contract

These four files **take no frontmatter** and are subject to special rules:

| File | Rule |
|---|---|
| `_INDEX.md` | Read at the start of every session. Maximum ~100 lines. Pointers only, no content. |
| `_LOG.md` | Append-only. Only new entries are added, older ones are NEVER modified (historical accuracy). |
| `_SCHEMA.md` | This file. Updated only when the schema changes. |
| `_SEARCH_INDEX.md` | Agent-optimized search index. Updated on every ingest/code-commit/lint. Detail: Section 13. |

**Historical accuracy rule:** `_LOG.md` is considered immutable history. Once an entry is written, rewriting it for path or name changes is forbidden — instead, a new `migration` entry is added.

**Team concurrency model (multi-developer merge strategy):**
- `_LOG.md` → because it is append-only, it is marked with `merge=union` in the repo root's `.gitattributes`: concurrent log additions from different developers merge instead of conflicting. (Rotation/`migration` exception: see the `.gitattributes` notes.)
- `_improvement-queue/` → because each signal is a separate `IMP-*.md` file, concurrent capture produces no conflicts at all (no merge driver needed).
- `active-project-context.md` → structured prose; `union` is NOT applied (it would corrupt the sections). It is shared sprint state, not a personal scratchpad — per-developer active work is kept on separate lines with `@name`/branch in the "Active Work" section, transient detail is written to the session summary. Real conflicts are resolved manually.

---

## 11. `_LOG.md` Rotation Mechanism

Because `_LOG.md` is append-only, it grows as the project grows. The agent using lightweight grep at the start of a session mitigates this issue, but the full file may be read during lint.

**Rotation rule (optional, kicks in at ~50+ entries):**
1. Entries in `_LOG.md` older than 6 months are moved to an `archive/_LOG-YYYY.md` file.
2. The move is logged as a `migration` entry.
3. Archived log files remain immutable.
4. Rotation is only suggested during lint; it does not run automatically.

---

## 12. Obsidian Ecosystem Guide (Karpathy Tips)

The wiki is designed to be used as an Obsidian vault. The following settings and plugins are recommended:

**Basic Settings:**
- **Files and links → Attachment folder path:** `raw_sources/assets/` (so images are downloaded to a central location)
- **Files and links → New link format:** `Relative path to file` (wikilink compatibility)

**Recommended Plugins:**
- **Graph View** (core) — Visualizes the shape of the wiki; helps detect hub pages and orphans.
- **Dataview** — Produces dynamic tables and lists from YAML frontmatter (e.g., `TABLE date_updated, type FROM "wiki" SORT date_updated DESC`).
- **Obsidian Web Clipper** — Converts web articles to markdown and saves them under `raw_sources/`.

**Optional:**
- **Marp** — A markdown-based presentation format. Slides can be generated directly from wiki content.

---

## 13. Scaling — `_SEARCH_INDEX.md` (Agent-Optimized Search)

As the wiki grows, `_INDEX.md` alone becomes insufficient. The mechanism that solves this problem **with zero dependencies** (no script, no runtime, no binary): `_SEARCH_INDEX.md`.

### Two-Stage Search Strategy

| Stage | What | How |
|---|---|---|
| 1. Index scan | The agent reads the `_SEARCH_INDEX.md` table | Matches query terms against the `Key Terms` and `Tags` columns |
| 2. Targeted read | Reads only the matching pages | Accesses full page content, synthesizes the answer |

This strategy works even when the wiki reaches hundreds of pages: 200 pages × ~120 characters/line = ~24KB — fits comfortably into any LLM context.

### `_SEARCH_INDEX.md` Structure

```markdown
| Page | Type | Tags | Key Terms | Summary |
|---|---|---|---|---|
| [[page-name]] | core | tag1, tag2 | term1, term2, term3 | One-line description |
```

**Column rules:**
- **Page:** Obsidian wikilink (clickable)
- **Type:** One of the page types from `_SCHEMA.md` Section 2
- **Tags:** A copy of the frontmatter `tags` field (comma-separated)
- **Key Terms:** 5-15 search terms extracted from the page's content — technical concepts, technology names, IDs (e.g., `AD-01..AD-12`, `TD-01..TD-14`), domain terms. **Different from Tags:** tags categorize, key terms enable search matching.
- **Summary:** One line, maximum ~100 characters

### Maintenance Rules

- `_SEARCH_INDEX.md` is updated on every **ingest**, **code-commit**, and **lint** operation.
- New wiki page → a new row is added.
- If a page is moved to the archive → the row is updated with the `archive/` prefix.
- Since a page is never deleted (NEVER delete — always archive) → a row is never removed.
- Consistency with `_INDEX.md` is checked during lint: every `_INDEX.md` entry must also exist in `_SEARCH_INDEX.md` and vice versa.

### Optional: Higher-Tier Search Layers (~500+ pages)

For very large wikis or code-heavy projects, `_SEARCH_INDEX.md` alone becomes insufficient. The recommended roadmap:

- **Tier 1 — Qdrant** (semantic session memory): Ollama embedding (`qwen3-embedding:0.6b`) + local Qdrant. Solves "what did we talk about last week?" type questions.
- **Tier 2 — Graphify** (code structure): AST + call graph. For function/class lookup and impact analysis.
- Both tiers are wired into routing at the skill level (`using-second-brain` skill, REASONING AID workflow).

---

## 14. Complete List of Special Files

Current special files (DO NOT take frontmatter):

| File | Purpose | Maintenance Frequency |
|---|---|---|
| `_INDEX.md` | Human-optimized content catalog (Obsidian navigation) | Every ingest/code-commit |
| `_LOG.md` | Chronological append-only activity log | Every operation |
| `_SCHEMA.md` | Canonical format rules | On schema change |
| `_SEARCH_INDEX.md` | Agent-optimized search index (tag + key term table) | Every ingest/code-commit/lint |
| `_improvement-queue/` | Self-improvement suggestion queue — a directory, each signal its own `IMP-*.md` file (signal capture + approval + challenge) | A new file each time a signal is captured |

---

## 15. Self-Improvement Queue (`_improvement-queue/`)

This is the persistent suggestion queue used so the agent can learn across sessions. It is managed by the `self-improvement-curator` skill and reviewed via the `/evolve` slash command. The queue is a **directory** (each signal its own `IMP-*.md` file) — so that concurrent capture across a team does not produce merge conflicts. See `_improvement-queue/README.md`.

### 15.1 Purpose

The Karpathy wiki pattern provides contradiction tolerance for **knowledge**; `_improvement-queue/` applies the same pattern for **the agent learning its own behavior/rules**. The goal:
- Write correction/confirmation/decision signals captured in a session to the queue without losing them
- Strictly prevent writing to a rule/skill/wiki without an approval gate
- Allow old learned rules to be **challenged + superseded**
- Preserve the history of learnings from different LLM providers (the `provider_context` field)

### 15.2 File Structure (Directory — Each Signal Its Own File)

The queue is **not a monolithic file**, it is a directory: `_improvement-queue/`. Each signal
**is its own file**. On a team, multiple developers' agents capture signals at the same time —
because each signal is a separate file, concurrent captures **do not produce merge
conflicts**. There is **NO** shared `IMP-NNN` counter (a shared counter would collide on
concurrent capture). The status (pending/applied/...) lives in each file's frontmatter;
a status change is an edit to a single small file, not a contended rewrite of a monolith.

**File name = ID:** `IMP-YYYYMMDD-<short>.md`
- `IMP-` prefix (greppable) + `YYYYMMDD` capture date (chronological) + `<short>`
  (4-character base36, generated locally, no coordination). Before writing, the agent
  verifies that the file name does not already exist; on a rare collision it regenerates.
  A "human-friendly GUID": counterless and collision-free, yet sayable in review ("apply
  IMP-20260601-a3f8").
- The `id:` frontmatter field **must equal** the file name's root name. The file name is the
  single source of truth; there is no counter anywhere to be incremented.
- Only `IMP-*.md` files are entries. `README.md` is not an entry; all status
  queries glob `IMP-*.md` (README does not count).

The frontmatter holds the scannable metadata; the body holds human-readable prose (`## Proposed
Change`, `## Evidence`):

```markdown
---
id: IMP-20260414-a3f8
detected: 2026-04-14
signal_type: correction
scope: rule
target: .sumela/rules/backend_standards.md
provider_context: claude-opus-4-8
confidence: high
status: pending
---

## Proposed Change

EF Core queries with 3+ joins must explicitly declare `AsSplitQuery()`.

## Evidence

Session 2026-04-14: N+1 + Cartesian explosion was caught; the user approved AsSplitQuery.
```

When the status changes, the file is edited **in place** (not moved): `applied`/`superseded`/
`rejected` entries are **not deleted** (historical accuracy), only their frontmatter is updated.

### 15.3 Entry Schema (Required Fields)

`proposed_change` and `evidence` live in the body (under the `## Proposed Change` / `## Evidence`
headings); the following fields are in the frontmatter:

| Field | Type | Description |
|---|---|---|
| `id` | `IMP-YYYYMMDD-<short>` | The file name's root name. No counter, never reuse. |
| `detected` | `YYYY-MM-DD` | The date the signal was captured |
| `signal_type` | enum | `correction` \| `confirmation` \| `decision` \| `friction` \| `challenge` \| `resolution` \| `preference` |
| `scope` | enum | `rule` \| `skill` \| `wiki` \| `schema` \| `active-context` |
| `target` | path | The relative path of the file to be touched. For `scope: rule`, default `.sumela/rules/<topic>.md` (portable, IDE-agnostic). |
| `provider_context` | string | The model that captured the signal (`claude-opus-4-8`, `claude-sonnet-4-6`, etc.) |
| `confidence` | enum | `high` \| `medium` \| `low` (see 15.5) |
| `status` | enum | `pending` \| `proposed` \| `applied` \| `superseded` \| `rejected` |

**Additional frontmatter fields by status (added in place when the status changes):**
- `proposed` (team-mode, gated scope — PR open) → `pr: <pr-url>` (the actual PR URL; not just the branch name), `proposed_at: YYYY-MM-DD`
- `applied` → `applied: YYYY-MM-DD`, `last_validated: YYYY-MM-DD`, `challenges: [IMP-ID, ...]`
- `superseded` → `superseded_by: IMP-ID`, `superseded_at: YYYY-MM-DD`
- `rejected` → `rejected_at: YYYY-MM-DD`, `rejection_reason: text`
- `pending` (deferred at `/evolve`) → `deferred_at: YYYY-MM-DD` (status stays `pending`)
- `signal_type: challenge` → `supersedes: IMP-ID` (which applied entry it questions)

### 15.4 Signal Types (What Gets Captured?)

| Type | When |
|---|---|
| `correction` | When the user says "no, that's not it" / "don't do it like that again" / "don't use that" |
| `confirmation` | When the user approves a debatable choice ("yes, exactly like that", "the right choice") |
| `decision` | When an architecture decision is made during brainstorming/ULTRATHINK |
| `friction` | When the same error/question recurs 2+ times (pattern detection) |
| `challenge` | When new evidence is found that contradicts an existing `applied` entry |
| `resolution` | When the agent diagnoses and resolves a bug/problem **itself** — the GENERALIZED lesson is captured, not the instance (e.g., not "service X wasn't registered" but "new services must be registered in DI") |
| `preference` | When the user gives a forward-looking, persistent working rule without it being a reaction to an error ("from now on always do X", "keep comments minimal") — different from a reactive `correction`: a proactive stance |

### 15.5 Confidence Thresholds (To Avoid Staying Silent)

It is unacceptable for `self-improvement-curator` to set the threshold too high and never write anything. The rule:

- **`high`**: The user explicitly confirmed OR rejected OR made the same correction 2+ times → **ALWAYS** written to the queue.
- **`medium`**: Debatable but the evidence is concrete (there is a code/log/file reference) → **ALWAYS** written to the queue, presented to the user in review with an "I'm not sure" note.
- **`low`**: Only intuition, no concrete evidence → **NOT written** (to avoid noise).

**Rule:** When in doubt, pick `medium`, don't fall back to `low`. The review gate protects the user — missing a signal for the sake of reducing the agent's workload is unacceptable.

### 15.6 Challenge & Supersede Flow (Updating Old Learnings)

Different providers/times may decide differently. If the agent, in a new session, finds concrete evidence that contradicts an existing `applied` entry:

1. **It creates a new entry**, with `signal_type: challenge` and a `supersedes: <IMP-ID>` field referencing the original.
2. The entry is written to the queue as `pending` — it is **never applied automatically**.
3. If the user approves the challenge in the `/evolve` review:
   - The original entry file's frontmatter is updated in place: `status: superseded`, `superseded_by: <new-IMP-ID>`, `superseded_at` is added
   - The new entry becomes `status: applied` and is applied to the relevant file
   - An `evolve` entry in `_LOG.md`: *"IMP-20260714-c3d4 applied; supersedes IMP-20260601-a1b2 — reason: ..."*
4. The original entry file is **not deleted** — only its frontmatter is set to `superseded`, the file stays in place (historical accuracy).

### 15.7 Proactive Re-validation

At the start of a session, within the `using-second-brain` eager-load:
- The number of pending entries is reported (if the count > 0, the user is told *"N suggestions await approval, you can review them with /evolve"*)
- A summary of the last 5 applied entries is shown (that's the context budget) — scan the directory with `grep -l "^status: applied" IMP-*.md` and take the most recent 5 by date
- **Re-validation pulse**: One random applied entry whose `last_validated` has not been updated in the last 90 days is selected → the agent passively attends, throughout the session, to whether this entry is still valid. If it sees a contradiction, it automatically opens a `challenge` signal.

### 15.8 Approval Model (Double-Approval Rule)

| Scope | Approval Model |
|---|---|
| `wiki` (synthesis pages) | Single approval + diff preview |
| `active-context` | Single approval |
| `skill` (new) | Single approval + `writing-skills` skill is mandatory |
| `skill` (existing edit) | Single approval + diff + list of affected workflows |
| `rule` (`.sumela/rules/*.md`) | **Double approval:** "should this rule be written?" → then "apply?" |
| `schema` (`_SCHEMA.md`) | **Double approval** + manual review mandatory |

**Governance mode (team) — PR gate for gated scopes:** If `governance` in `AGENTS.md` Section 8 is `team`, changes with `rule` / `skill` / `schema` scope (i.e., those affecting every developer's agent) are not applied directly; `/evolve` applies them on a `sumela/evolve-<IMP-ID>` branch + commit + opens a **pull request** and the entry becomes `status: proposed`. Once a code owner merges the PR, it becomes `applied` (see 15.10 reconcile). In `solo` mode OR for `wiki`/`active-context` scopes, today's direct-apply behavior applies. Detail: `self-improvement-curator/SKILL.md` `<evolve_review_workflow>`.

### 15.9 Hygiene & Archiving

- If `_improvement-queue/` has 500+ entries, `superseded` and `rejected` files are moved to the `_improvement-queue/archive/YYYY/` subdirectory (files are not deleted)
- `applied` entries are **never** archived (active learning, must remain challengeable)
- Archiving is recorded with a `migration` log entry
- The session-start eager-load reads only `pending` + the last 5 `applied` (context budget); the status directory is scanned with `grep -l "^status: <status>" IMP-*.md`

### 15.10 `_LOG.md` Integration

The following events are written to `_LOG.md` as an `evolve` entry:
- When an IMP entry becomes `proposed` (team-mode, PR opened)
- When an IMP entry becomes `applied` (solo direct apply OR team-mode PR merge — reconcile)
- When an IMP entry becomes `superseded` (challenge approval; `supersedes: <IMP-ID>` is added to the applied log line)

`rejected` events are **not written** to `_LOG.md` (to avoid log noise) — neither a solo rejection nor a PR closed in team-mode.

Format:
```markdown
## [2026-04-14] evolve | IMP-20260414-a3f8 applied: AsSplitQuery rule added
- Scope: rule → .sumela/rules/backend_standards.md
- Provider: claude-opus-4-8
- PR: <url> (team mode; none in solo)
- Challenges: none
```

**Reconcile (team mode):** At the start of `/evolve`, the PR of every entry in the `proposed` status is checked (`gh pr view` / `glab mr view`; if missing, the user is asked): if merged → `applied` (+ `applied`/`last_validated`), if closed without merging → `rejected`, if still open → stays `proposed`.

## 16. Scale Playbook (Wiki Growth Roadmap)

As the wiki grows, the search stack changes. Proceed according to the table below:

| Wiki Size | Search Stack | Action Required |
|---|---|---|
| 0-100 pages | `_SEARCH_INDEX.md` + grep | None; current stack sufficient |
| 100-300 pages | Same | Audit `_SEARCH_INDEX.md` parity more frequently |
| 300-1000 pages | `_SEARCH_INDEX.md` + grep + **Graphify** + **Qdrant (chat_history)** | Install `graphify` CLI, deploy local Qdrant + Ollama embeddings; wire `auto-update-memory.py` |
| 1000+ pages | Qdrant + Graphify primary; `_SEARCH_INDEX.md` secondary | Multi-collection Qdrant (chat_history + wiki_pages + code_chunks); enriched payloads |

Threshold check: invoked during lint workflow (count `*.md` in wiki/ non-recursively).

## 17. Image Reading Workflow (Karpathy Image Pattern)

LLMs (including Claude) generally cannot read inline images in a single pass. The pattern Karpathy recommends is applied in this wiki as follows:

1. The agent first reads the source markdown text (full textual context is established).
2. The agent identifies the image references (`![[...]]` or `![](../raw_sources/assets/...)`).
3. The agent additionally views the images using its native image-read capability.
4. The agent combines the text + image content in the source-summary page.

**Storage rule:** all image assets are kept under `raw_sources/assets/` (see Section 12 "Obsidian Ecosystem Guide"). The Obsidian "Attachment folder path" setting must be mapped to this directory.
