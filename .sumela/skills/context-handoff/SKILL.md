---
name: context-handoff
description: "Use when context compaction warnings appear, after 8+ major tool sequences, after 3+ large file reads plus 2+ review cycles, when a sprint task closes mid-session with more work pending, or when the user asks for a handoff prompt or to start a new session (in any language)."
---

<purpose>
Long development sessions accumulate context — plan files, tool outputs, review diffs, logs. When context approaches capacity, raw compression loses critical task state. This skill protects against that loss by creating a durable session-summary/query-write-back artifact in the Second Brain, then generating a compact handoff prompt that points to it.

1. Detecting context pressure early — not at the wall.
2. Choosing the right protocol: clean finish vs. checkpoint park.
3. Updating the Second Brain surfaces that actually changed so the next session starts with accurate state.
4. Routing this session's DECISIONS to a durable home so they accumulate across sessions instead of dying with the chat.
5. Running /evolve pre-check so learning signals aren't lost across session boundaries.
6. Generating a handoff prompt the next agent can execute without rereading the entire session history.

**Core invariant:** The next agent must be able to continue exactly where this session stopped — no reconstruction, no guesswork.
</purpose>

<activation>
EAGER — loaded at session start. Context monitoring must be active from the first user turn because pressure builds gradually and the ideal stopping point appears before the crisis point, not at it.
</activation>

<commands>
## Named commands used by this skill

**`{IMP_PENDING_COUNT}`** — the pending `/evolve` suggestion count. Run the form for your shell.
Glob `IMP-*.md` only, NEVER the whole directory: `_improvement-queue/README.md` contains a
`status: pending` example that would inflate the count. Do NOT read the files themselves.

- bash: `grep -l "^status: pending" docs/second-brain/wiki/_improvement-queue/IMP-*.md 2>/dev/null | wc -l`
- PowerShell: `@(Get-ChildItem docs/second-brain/wiki/_improvement-queue/IMP-*.md -EA SilentlyContinue | Select-String "^status: pending").Count`
</commands>

<trigger_conditions>
Activate the handoff-assessment workflow when ANY of these conditions are true:

1. **System signal:** Context compaction warnings appear, or significant prior message compression is observed.
2. **Task-count heuristic:** You have executed 8+ major tool call sequences (each task counts as one sequence) in the current session.
3. **Volume heuristic:** The session has involved 3+ full reads of large files (>200 lines) AND 2+ code-review cycles.
4. **Sprint milestone heuristic:** A sprint task is marked complete and the remaining task count suggests 2+ tasks still need to be done this session.
5. **Explicit user trigger:** User says "context handoff", "prepare handoff", "new session", "let's continue in a new session", "is the context full?" — or the equivalent in any language.

**Rule:** Activate the assessment — do NOT interrupt the user mid-task. Always complete the current smallest meaningful unit first, THEN assess.
</trigger_conditions>

<assessment_workflow>
After completing the current task unit, when trigger conditions are met:

1. **Assess current state:**
   - Is there an active sprint plan? (Check `docs/second-brain/artifacts/plans/` if not in context.)
     - **If the sprint plan or recent session context is missing from working memory, run the four-tier decision tree before proceeding:** `python .sumela/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<topic>" --limit 3` for session summaries (Tier 1), then `_SEARCH_INDEX.md` for wiki pages (Tier 3). Do NOT rely solely on manual file reads for historical context.
   - Is the current task FULLY DONE or IN PROGRESS?
   - Did the active sprint/project state change? If yes, is `wiki/active-project-context.md` up to date? If no, the session summary + `_SEARCH_INDEX.md` update may be the correct persistent artifact.
   - (The `/evolve` pending count is NOT taken here — `<decision_triage>` may file new `IMP-*.md`
     signals, so the only count that can be reported is the one taken AFTER triage, in Protocol A
     Step 3 / Protocol B Step 5.)

2. **Choose protocol:**
   - Current task is FULLY COMPLETE → **Protocol A**
   - Current task is IN PROGRESS → **Protocol B**

3. **Execute the chosen protocol.** Both protocols run `<decision_triage>` as an internal step,
   before the session summary is written and before the `/evolve` count is taken.

4. **Present handoff prompt to user and ask for confirmation.**
</assessment_workflow>

<decision_triage>
## Decision Triage — run BEFORE writing the session summary

A decision that lives only in this session's chat dies with this session. Before the summary is
written, route EVERY decision made this session to a durable home. **This is what makes the
carried-forward set cumulative:** each session files its decisions where the NEXT session already
looks, instead of leaving them in a per-session file nobody reopens.

For each decision apply the boundary test from `using-second-brain` operation 5 (DECISION CAPTURE):
*"If a new developer joined the team without an agent, would this decision still apply to them?"*

| Answer | Durable home | How it gets there |
|---|---|---|
| **YES** — project-level (technology choice, pattern, contract/API shape, layer boundary) | `wiki/architecture-decisions.md` as `AD-XX` | Route to `using-second-brain` operation 5. It owns AD numbering and the full write set (`_INDEX`, `_SEARCH_INDEX`, `_LOG`). |
| **NO** — about how the AGENT works (a rule, skill, workflow change, or a standing user preference) | `_improvement-queue/IMP-*.md` | The `decision` / `preference` signal path in `sumela-prompt.md` `<signal_capture>`; reviewed via `/evolve`. |
| **Neither** — tactical, scoped to this task | The session summary's `## Decisions Made` | No further routing needed. |

**Do NOT write an AD entry from this skill.** Two guarantees depend on that:
- DECISION CAPTURE asks *"Would you like me to save this decision to the wiki?"* and NEVER
  auto-captures. A silent write from here would bypass a consent gate the wiki relies on.
- AD numbers are allocated by reading the page's current maximum — that is a read-modify-write with
  no lock. Handoff is the most worktree-exposed moment in the system, so two parallel handoffs can
  allocate the same `AD-XX`.

If the user declines, or context is too tight to run the capture, record the decision as an
**AD candidate** line in the handoff prompt. `finishing-a-development-branch` also writes ADs and
runs at a calmer moment; the next session can promote it there.

Triage is a classification, not a write — it is cheap. Only the buckets that earn a write get one,
and only with the consent their own workflow requires.
</decision_triage>

<minimum_viable_handoff>
## Minimum Viable Handoff — what to drop when context runs out

This skill fires when context is nearly exhausted, so its own steps can fail to complete. If you
cannot finish everything, **drop from the top of this list and work down.** The order is
irreplaceability: the last item exists nowhere else on disk, everything above it can be rebuilt,
re-derived or re-run later. Note that the first three to go are the newest and most expensive parts
of this skill — that is deliberate, they buy the least.

**Drop FIRST:**
1. The Standing Decisions pointer — but only after confirming `architecture-decisions.md` is linked
   from `_INDEX.md`/`_SEARCH_INDEX.md`, because that link is then the next session's only route to
   it. Bootstrap does NOT read that page (STEP 2 reads `_INDEX.md`, `active-project-context.md`, the
   `_LOG` tail and the IMP count); only some phase skills do, and only later. If the page is
   orphaned, keep the pointer and fix the link instead.
2. `/evolve` review — degrade to the pending count (already the documented behaviour).
3. Decision triage's AD routing — degrade to an "AD candidate" line (see `<decision_triage>`).
4. `session-ingest.py` — droppable, but NOT free. No hook re-ingests a locally authored summary:
   `post-merge` only covers what an incoming range brought in, and `post-commit` exits unless HEAD
   is a merge commit. So skipping this leaves the markdown in git but ABSENT from your local
   `chat_history` — the next session's Tier-1 query will not find it until someone re-runs the
   script (or a teammate pulls the committed file).
5. `_SEARCH_INDEX.md` / `_INDEX.md` rows — a later lint pass recovers these.
6. The session summary markdown with a real `## Decisions Made` block — everything downstream reads
   it. Degrade to a terse-but-honest summary long before dropping it entirely.

**NEVER DROP — this is the whole point of the handoff:**
7. The Protocol B `[CHECKPOINT]` block in the plan file, the 🔴 Continue Point, the branch name, and
   `git status --short`. Without these the next session cannot resume at all.

Agent Notes do NOT appear on this ladder: they are written into the session summary's
`## Notes for the Next Session`, so item 6 covers them. Never let them exist only in the
copy-pasted prompt — an unpasted prompt loses them, and they exist nowhere else.

If you drop item 4 or anything below it, say so explicitly under `### Handoff Completeness` in the
prompt rather than letting the next agent discover the gap.
</minimum_viable_handoff>

<protocol_a>
## Protocol A — Task Complete, Context Low

Use when: The current task is fully finished and verified.

### Steps

**Step 1 — Second Brain Update (MANDATORY):**
- If the active sprint/project state changed, update `wiki/active-project-context.md`:
  - Mark the completed task as done in the sprint section.
  - Update sprint progress counters.
- If this was a maintenance/audit/session-summary-only handoff with no active sprint state change, do not force `active-project-context.md`; preserve the state in the session summary and `_SEARCH_INDEX.md`.
- If a real loggable operation occurred, append the matching entry to `_LOG.md` (`code-commit`, `decision`, `evolve`, `migration`, etc.). Do not create a `_LOG.md` entry solely because a handoff prompt was generated.
- **Critical:** The next session's eager-load reads `active-project-context.md` first, then index/search surfaces. Stale active state is dangerous; unnecessary active-context churn is also dangerous.

**Step 2 — Decision Triage (MANDATORY):**
- Execute `<decision_triage>` for every decision made this session. It runs BEFORE the `/evolve`
  count and BEFORE the summary: triage may file new `IMP-*.md` signals, so counting first would
  report a clean queue moments before it stops being clean.

**Step 3 — Evolve Check:**
- Run `{IMP_PENDING_COUNT}` — do NOT read the full file.
- If count > 0, ask the user:
  > *"There are {N} pending /evolve suggestions before handoff. Would you like to review them now, or add them as a note to the handoff prompt?"*
- If user says **now**: execute `/evolve` workflow (self-improvement-curator skill).
- If user says **sonra**: note the pending count in the handoff prompt.
- **Timing constraint:** If /evolve review would consume too much remaining context, skip it and note it in handoff prompt. Never sacrifice handoff quality for evolve completeness.

**Step 4 — Session Summary (MANDATORY):**
- Create a session summary file following `using-second-brain` `<session_summary_protocol>` (canonical; see `<session_summary_protocol>` below for the context-handoff-specific trigger note).
- This persists the session's conversational context as a searchable wiki page.
- The handoff prompt will reference this summary file.
   - Immediately after creating the summary, execute the applicable `<session_memory_ingestion>` steps: always index the session summary, and run code-graph/wiki memory maintenance only when the session changed code or other memory-sync inputs. **Relay the structured report output to the user in the project's configured language**.

**Step 5 — Generate and present handoff prompt** using `<handoff_template>` below.
</protocol_a>

<protocol_b>
## Protocol B — Task In Progress, Context Low

Use when: You are mid-task and context is running low.

### Steps

**Step 1 — Find a clean stopping point (CRITICAL):**
- Complete the **smallest meaningful compilable unit** you are currently in:
  - Finish the method body
  - Finish the file you are editing
  - Finish the test class (even if not all tests are written)
  - Finish the migration file
- **NEVER stop** in the middle of a method, a partial file edit, a half-written test, or an open transaction.
- If you are mid-refactor: bring the codebase to a state where it compiles, even if incomplete. Leave TODOs in comments.
- Stage completed changes only when the active workflow or user explicitly expects staged output. Otherwise leave them unstaged and document the exact `git status --short` state in the handoff.

**Step 2 — Mark CHECKPOINT in the plan file:**
- Open the active plan file under `docs/second-brain/artifacts/plans/`.
- Under the current in-progress task, append a checkpoint block:
  ```markdown
  > **[CHECKPOINT YYYY-MM-DD]:** <What was completed in this session — be specific (file names, method names).>  
  > **Next step:** <Exactly where to continue — file path, method name, test name, or migration step.>
  ```
- This checkpoint is the contract between sessions. Precision matters: "Next step: Add `IPaymentProcessor` registration to `Program.cs` line ~85, after `AddScoped<IOrderService>`" is good. "Continue implementation" is not.

**Step 3 — Second Brain Update (MANDATORY):**
- If the checkpoint changes active sprint/project state, update `wiki/active-project-context.md`:
  - Mark the task as `🔄 IN PROGRESS (checkpoint reached)`.
  - Add the checkpoint summary to the active sprint section.
- If this is a maintenance/audit checkpoint rather than active sprint execution, preserve the checkpoint in the plan/session summary and `_SEARCH_INDEX.md`; do not invent sprint state.
- Append an entry to `_LOG.md` only if a real loggable operation occurred. Staging alone is not a `code-commit`.

**Step 4 — Decision Triage (MANDATORY):**
- Same as Protocol A Step 2.

**Step 5 — Evolve Check:**
- Same as Protocol A Step 3.

**Step 6 — Session Summary (MANDATORY):**
- Same as Protocol A Step 4. Create session summary following `using-second-brain` `<session_summary_protocol>` (canonical).
   - Immediately after creating the summary, execute the applicable `<session_memory_ingestion>` steps: always index the session summary, and run code-graph/wiki memory maintenance only when the session changed code or other memory-sync inputs. **Relay the structured report output to the user in the project's configured language**.

**Step 7 — Generate and present handoff prompt** using `<handoff_template>` below.
- The "🔴 Continue Point" section MUST include the full checkpoint detail so the next agent continues from exactly where you stopped.
</protocol_b>

<session_summary_protocol>
## Session Summary Generation Protocol

The session-summary write+ingest procedure is CANONICAL in `using-second-brain` `<session_summary_protocol>` (single source of truth — shared with `finishing-a-development-branch` so the two triggers never drift). READ and FOLLOW it; do NOT re-specify the fields/steps here.

What is specific to context-handoff:
- **When:** ALWAYS during context-handoff (Protocol A Step 4, Protocol B Step 6); also when the user explicitly asks to save a session mid-session.
- The canonical protocol stamps the queryable frontmatter (`developer` from `git config user.name`, `domains` from `.sumela/local.md`, `spec_artifact`/`plan_artifact`, `session_date`, `session_topics`), writes `wiki/session-summaries/YYYY-MM-DD-<topic>.md` per the `_SCHEMA.md` Session Summary Page Template, updates `_SEARCH_INDEX.md`/`_INDEX.md`, and ingests into Qdrant `chat_history`.
- Capture substantive detail (decisions + rationale, concrete work + commits/files, artifact links) — a pointer-only stub defeats the memory. A handoff summary is mid-task context; be detailed enough that the NEXT session resumes exactly where you stopped.
</session_summary_protocol>

<session_memory_ingestion>
## Session Memory Ingestion (v2.2) — ROUTED AUTOMATION + USER REPORT

During context-handoff, the agent runs the appropriate steps below without offloading manual decisions to the user, and **presents the output as a summary in the project's configured language**:

1. **Create Session Summary** — per `using-second-brain` `<session_summary_protocol>` (canonical: substantive content + the queryable `developer`/`domains`/`spec_artifact`/`plan_artifact` frontmatter). Do NOT write a thin "main topic + decisions" stub.
   - Format: `wiki/session-summaries/YYYY-MM-DD-topic.md`

2. **Auto-Index to Qdrant**
   ```bash
   python .sumela/memory-plugins/qdrant-session-memory/scripts/session-ingest.py docs/second-brain/wiki/session-summaries/YYYY-MM-DD-topic.md
   ```
   This script:
   - Chunks the markdown (512 tokens, 50 overlap)
   - Generates embeddings via Ollama `qwen3-embedding:0.6b`
   - Auto-upserts to Qdrant `chat_history`
   - If Qdrant is down, only the markdown summary remains. It is NOT auto-retried locally (see
     the `<minimum_viable_handoff>` note on hook scope) — re-run this script when Qdrant is back
     if the next session needs to find this summary by semantic search
   - **Output:** Prints a `SESSION INGEST REPORT` block

   **Agent instruction:** After the script runs, read the `SESSION INGEST REPORT` block from stdout and present a brief summary to the user in the project's configured language:
   > "Session memory processed. Split into {chunk count} chunks and {'saved to Qdrant' | 'could not save (markdown backup remains)'}. "

3. **Graphify + Qdrant Maintenance (Conditional — Code/Memory Sync End)**
   ```bash
   python scripts/auto-update-memory.py
   ```
   **When it runs:**
   - Code changes landed, a branch finish/code-commit occurred, or Graphify call graph can be stale.
   - Wiki sync inputs changed in a way that `sync-graphify-to-obsidian.py` must reflect.
   - The user explicitly requests memory maintenance or Second Brain health repair.

   **When it does NOT run:**
   - Pure handoff prompt generation.
   - Session-summary-only maintenance/audit work where `_SEARCH_INDEX.md` already records the durable context.
   - Cases where running it would create misleading `_LOG.md` churn without a real code/wiki sync operation.

   This script:
   - Rebuilds the code graph (`graphify update .` — AST-only, no LLM key)
   - Syncs to wiki via `sync-graphify-to-obsidian.py`
   - Runs Qdrant health check
   - Writes real maintenance/sync results to `_LOG.md` when applicable
   - **Output:** Prints a `MEMORY UPDATE REPORT` block

   **Agent instruction:** After the script runs, read the `MEMORY UPDATE REPORT` block from stdout and present a brief summary to the user in the project's configured language:
   > "Memory maintenance complete. Graphify code graph {'updated' | 'failed'}, wiki sync {'ok' | 'error'}, Qdrant {'reachable' | 'unreachable'}."
   If the script was skipped because conditions weren't met, write briefly and clearly in the handoff: "Graphify/wiki memory maintenance skipped; this handoff only updated session summary + search index."

**Qdrant Query Tool — Session-to-Session Bridge:**
After session summaries are indexed to Qdrant, the next session can semantically search this history via `python .sumela/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py "<query>" --limit 3`. This forms Tier-1 of the REASONING AID workflow.

**Rule:** Never ask the user "should I update Graphify/Qdrant?". Session summary ingestion runs on every handoff. `auto-update-memory.py` only runs when the above conditions are met; it should not run unnecessarily to avoid creating misleading `_LOG.md` or wiki maintenance traces. If it fails, notify the user; if it succeeds or is intentionally skipped, the agent should present a brief summary report in the project's configured language.
</session_memory_ingestion>

<handoff_template>
## Handoff Prompt Template

Present the filled template inside a fenced code block so the user can copy-paste it directly into a new session.

````
@.sumela/sumela-prompt.md

## Session Handoff — {DATE}

> **Read this first.** After `<session_bootstrap>` completes and BEFORE your first edit, read
> `{session-summary-path}` — it carries this session's full decision rationale and work detail;
> what follows is only a digest of it. If you have already read that file this session, skip.

### Project & Branch
- Branch: `{branch-name}`
- Worktree: `{worktree-path}` (or "main repo, no worktree")
- Plan / Artifact: [{plan-file-name}](docs/second-brain/artifacts/plans/{plan-file.md}) or `{none - maintenance/session summary only}`

### Sprint Summary
- Sprint: {sprint-id or feature-name}
- Total tasks: {N}
- Completed: {M} tasks ✅
- Remaining: {N-M} tasks

### Completed Tasks (This Session)
{For each task completed in this session:}
- ✅ T{N}: {task-name} — {commit-hash or "staged"}

### 🔴 Continue Point
**T{N}: {task-name}**

{Full task description copied from the plan file — do NOT summarize, copy verbatim so the next agent has full intent context.}

{Protocol B only — add the checkpoint block:}
> **[CHECKPOINT {DATE}]:** {What was done.}  
> **Next step:** {Exactly where to continue.}

### Decisions — This Session
{Every decision MADE this session, with its rationale and the durable home triage assigned it.
 Copy from the session summary's `## Decisions Made`. Write "None." if there were none.}
- {What was decided} — {why}. → `AD-12` | `IMP-20260918-retry-policy` | AD candidate (not yet filed) | session-scoped

### Decisions — Standing (carried forward)
> Earlier sessions decided these and they still hold. Do not re-litigate them; if one now looks
> wrong, supersede it explicitly rather than quietly doing something else.
- **Architecture:** `docs/second-brain/wiki/architecture-decisions.md` — read the `## AD-XX` entries
  whose **Status** is `accepted` before proposing any architecture. ({N} entries | page not created yet)
- **Agent workflow:** {N} pending in `_improvement-queue/` — review with `/evolve`.
{Do NOT paste AD bodies here. That page is the authority and the ONLY surface that can express
 `superseded_by`; a pasted copy goes stale and will present a reversed decision as current.}

### Agent Notes for the Next Session
{HARD-WON EXPERIENCE from this session — the working knowledge that exists nowhere on disk and
 would cost the next agent real time to rediscover. Not decisions, not blockers, not plan content.
 For example: approaches tried and rejected (and WHY they failed), environment or tooling quirks,
 files that look relevant but are not, commands that do not work in this repo, a measurement that
 came back negative so nobody repeats it, how this user prefers to work through a problem.
 Write "None." if there is genuinely nothing.}
- {The note} — {why it matters to the next session}

{**Carried forward:** also copy any note from the PREVIOUS handoff that is still true and still
 useful. Drop the ones the work has since resolved or disproved — this list is pruned every
 handoff, not appended to forever. That pruning is what keeps experience accumulating without the
 prompt growing without bound.}

### Pending Decisions / Blockers
{Decisions NOT yet made — open questions the next agent must resolve or raise with the user — and
 anything blocking progress. A decision that WAS made belongs in "Decisions — This Session", even
 if it is revisitable. Write "None." if clear.}

### Second Brain Status
- `active-project-context.md`: {Updated ✅ | Unchanged - active state unchanged}
- Session summary: `{session-summary}`
- `/evolve` pending: {N suggestions — will be reminded at session start} or {Clean ✅}

### Handoff Completeness
{"Full" — or name the `<minimum_viable_handoff>` items that were dropped and why, so the next
 agent knows what is missing instead of discovering it.}

### Uncommitted / Staged Changes
{Run `git status` summary here, or write "None — all changes committed."}
````

### Template filling rules:
- `{DATE}` → today's date in YYYY-MM-DD format.
- `{branch-name}` → current git branch (run `git branch --show-current` if not known).
- `{session-summary-path}` → the SAME path as `{session-summary}`. It appears twice on purpose: once
  as an instruction the next agent acts on, once as status. A path listed only under status is
  decorative — bootstrap reads `_INDEX.md` and `active-project-context.md`, never the summary.
- Plan / Artifact → use the active plan when one exists; otherwise reference the maintenance artifact or session-summary path.
- Task description → copy verbatim from plan file when one exists; otherwise write `N/A - maintenance/session-summary handoff`.
- Checkpoint → exact file/method/line reference, not vague direction.
- **Decisions — This Session** → one line per decision, each ending in the home `<decision_triage>`
  assigned it. A decision with no home means triage was not run.
- **Decisions — Standing** → a POINTER plus counts, never a copy. Count only the `## AD-<number>`
  headings under that page's `## Decisions` section — the Entry-shape example above it is a literal
  `## AD-NN:` placeholder, so an unscoped count reports 1 entry on an empty page. If the page does
  not exist yet, write "page not created yet" rather than omitting the line, so the next agent knows
  the surface is empty and not merely unlinked.
- **Pending vs This Session** → the discriminator is whether the decision was MADE, not whether it
  is final. Made-but-revisitable goes in "This Session" with a note; not-yet-made goes in "Pending".
- **Agent Notes** → write the SAME list into the session summary's `## Notes for the Next Session`
  before filling it in here. The prompt is a copy the user may never paste; the summary is the
  durable one, and it is what a later session finds by search. Do NOT file these as `/evolve`
  signals to get them across the session boundary — a pending signal is inert until `/evolve` runs,
  and bootstrap shows the next session only its COUNT, never its content. Experience transfers
  here, immediately. Promoting the durable ones into signals happens in one batch at task end
  (`finishing-a-development-branch`), which is a separate concern from this handoff.
- `/evolve pending` → actual count from `{IMP_PENDING_COUNT}`.
- `{session-summary}` → path to the session summary created in Protocol A Step 4 / Protocol B Step 6.
- Staged changes → actual `git status --short` output or a concise summary.
</handoff_template>

<safety_invariants>
1. **Compilable state required.** Never end a session with a broken build. If Protocol B, ensure the partial implementation compiles before stopping.
2. **Second Brain update is non-negotiable.** A handoff must update the correct durable surface: `active-project-context.md` for active state changes, session summary + `_SEARCH_INDEX.md` for conversational/query write-back context.
3. **Never auto-terminate.** Always ask the user. They may want to push through, or they may need the handoff for a different reason.
4. **Document staged changes.** Uncommitted staged changes must be explicitly noted in the handoff prompt — the next agent needs to know what state git is in.
5. **Evolve before handoff (best-effort).** Try to handle /evolve first; if context is too tight, at minimum note the pending count in the handoff prompt.
6. **Checkpoint precision.** A vague checkpoint ("continue the service implementation") is worse than none. If you cannot be precise, describe the exact file state and what the next logical step is.
7. **No decision dies in the chat.** Every decision made this session gets a durable home via `<decision_triage>` before the summary is written. A decision that appears in the handoff prompt with no home assigned means triage did not run.
8. **Standing decisions are pointed at, never copied.** The handoff links `architecture-decisions.md`; it does not paste entries. Only that page can record `superseded_by`, so a copy will eventually present a reversed decision as current — which is worse than omitting it.
</safety_invariants>

<user_communication>
All user-facing text should be in the project's configured interaction language.

**When presenting the handoff:**

*Protocol A:*
> "Context is getting full. Last task completed ✅. Second Brain updated. Handoff prompt for the next session:"

*Protocol B:*
> "Context is getting full. Task {N} left at a safe point — checkpoint added to plan file. Second Brain updated. Handoff prompt for the next session:"

Then present the filled template in a code block, followed by:
> "You can send this prompt as the first message in a new session."
</user_communication>
