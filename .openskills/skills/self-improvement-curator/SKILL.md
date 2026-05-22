---
name: self-improvement-curator
description: "Use after every user turn to capture correction, confirmation, decision, friction, or challenge signals; or when the user invokes /evolve, says 'evolve', 'review pending improvements', 'pending önerileri incele', or asks to review captured learnings."
---

<purpose>
This skill implements the agent's self-improvement loop. It captures signals during normal conversation and persists them to a queue that survives across sessions, so the agent can **learn from mistakes, confirmations, and decisions** without losing that knowledge to context compaction or session boundaries.

The core invariant: **NEVER auto-modify rules, skills, schema, or wiki pages based on signals.** All changes flow through a human approval gate via the `/evolve` slash command.

Format contract and entry schema live in `docs/second-brain/wiki/_SCHEMA.md` Section 15. This skill file defines only the behavioral workflow.
</purpose>

<activation>
LAZY — loaded by `using-superpowers` when signal capture or `/evolve` review needs the full workflow. Session-start pending-count surfacing remains governed by `.openskills/superpowers-agent-mode-prompt.md`.
</activation>

<trigger_phrases>
This skill's `evolve_review_workflow` MUST be triggered when the user invokes any of these (IDE-agnostic — works in Claude Code, Cursor, Copilot, or any agent that loads this skill):

**Slash command (Claude Code only):** `/evolve`

**Natural language triggers (all IDEs):**
- Turkish: "evolve", "öğrenilenleri gözden geçir", "improvement'ları göster", "pending önerileri incele", "self-improvement review", "kuyruğu aç"
- English: "run evolve", "review improvements", "review pending improvements", "show the improvement queue", "let's review what you learned"

When any trigger fires, execute `<evolve_review_workflow>` below. The workflow definition here is the SINGLE SOURCE OF TRUTH — the Claude Code slash command at `.claude/commands/evolve.md` is only a thin ergonomic shortcut that delegates to this skill.
</trigger_phrases>

<session_start_protocol>
Pending-count surfacing at session start is performed by `superpowers-agent-mode-prompt.md` (`<session_bootstrap>` STEP 2.5). Do NOT duplicate that read here.

The full `_IMPROVEMENT_QUEUE.md` is loaded ONLY when `/evolve` is triggered (see `<evolve_review_workflow>`). Re-validation pulse and applied-entry loading happen inside the evolve workflow, not at session start.
</session_start_protocol>

<signal_capture_workflow>
During every user turn, scan for these five signal types. Capture is silent — you do NOT announce that you're capturing unless asked.

**Signal types** (full definitions in `_SCHEMA.md` Section 15.4):

1. **`correction`** — User says "hayır", "öyle değil", "bir daha böyle yapma", "şunu kullanma", or equivalents in any language. Capture: what they corrected, what the correct approach is.

2. **`confirmation`** — User validates a non-obvious choice you made ("evet, tam da böyle", "doğru seçim", "güzel yakalamışsın"). Only capture if the choice was **contested or non-default** — don't capture routine "ok" responses.

3. **`decision`** — A decision is made during brainstorming/ULTRATHINK about **how the agent should work** (which rule to add, which workflow to change, which skill to invoke differently). Capture: the decision, alternatives, reason.

   **CRITICAL BOUNDARY — do NOT double-capture with `using-second-brain` DECISION CAPTURE (operation #5):**
   - **Project architectural decisions** (which technology, which pattern, which endpoint design — answers to "would another developer on this project also follow this?") → handled by `using-second-brain` DECISION CAPTURE workflow → written to `wiki/architecture-decisions.md` as AD-XX. DO NOT capture these as `decision` signals.
   - **Agent behavioral decisions** (which rule file should change, which skill should be updated, how the agent should approach a class of tasks differently — answers to "this is about how the agent works, not about the project") → capture as `decision` signal in the queue.
   - Decision tree: *"If a new developer joined the team without Claude, would this decision still apply to them?"* → **Yes** = project decision (wiki) / **No** = agent decision (queue).
   - Edge case: if a decision has BOTH dimensions (e.g., "we'll use Redis AND the agent should always propose Redis for read-heavy patterns"), split into two entries: the project fact goes to the wiki via DECISION CAPTURE, the agent behavior goes to the queue as a `decision` signal.

4. **`friction`** — The same mistake or question repeats within or across sessions. Capture: the pattern, the friction it caused.

5. **`challenge`** — You observe concrete evidence (code, logs, behavior) that contradicts an existing `applied` entry. Capture: which IMP-ID is challenged, what the contradicting evidence is.

**Confidence assignment (CRITICAL — anti-silence rule):**

| Situation | Confidence |
|---|---|
| Explicit user confirmation OR rejection OR 2+ repeated corrections | `high` — MUST capture |
| Concrete evidence (code/log/file ref) but user didn't explicitly weigh in | `medium` — MUST capture |
| Pure intuition, no concrete anchor | `low` — SKIP capture |

**When in doubt: pick `medium`, never `low`.** The `/evolve` review gate protects the user; silent skipping is the worse failure mode.

**Capture procedure:**
1. Read `_IMPROVEMENT_QUEUE.md` to find the next free `IMP-NNN` ID (check the "ID counter" header line).
2. Append a new YAML entry under `## Pending` following the schema in `_SCHEMA.md` Section 15.3.
3. Update the "ID counter" header to `IMP-<NNN+1>`.
4. Do NOT update `_LOG.md` for pending entries — only applied/superseded/rejected get log entries.
5. Do NOT notify the user mid-turn. The session-start notification covers visibility.

**Scope decision (which file would this eventually touch?):**

| Evidence points to… | `scope` | Default target path |
|---|---|---|
| A behavioral/workflow rule (how to act, what to avoid) | `rule` | `.openskills/rules/<existing_category>.md` or `<new_topic>.md` |
| A reusable skill workflow | `skill` | `.openskills/skills/<skill-name>/SKILL.md` |
| A fact/entity/architecture on the project | `wiki` | `docs/second-brain/wiki/<page>.md` |
| Current sprint/status | `active-context` | `docs/second-brain/wiki/active-project-context.md` |
| Wiki format itself | `schema` | `docs/second-brain/wiki/_SCHEMA.md` |

**IMPORTANT — direct rule integration:** For `scope: rule`, the DEFAULT target is `.openskills/rules/`. Do not use `.openskills/learned-rules/` anymore. Append the new rule to the most relevant existing category file (e.g., `backend_standards.md`, `frontend_standards.md`), or create a new one if it's a completely new domain. Since `.openskills/rules/` is the canonical IDE-agnostic rule layer, this eliminates the need for manual migration to IDE-specific folders.

If unsure, pick the closest scope and let `/evolve` review reclassify it.
</signal_capture_workflow>

<evolve_review_workflow>
Triggered by the user invoking `/evolve` (or explicitly asking "pending improvements'ları göster", "öğrenilenleri review edelim").

0. PRINT CONTEXT MANIFEST FIRST. `/evolve` mutates rules/skills/schema/wiki, so the user must see exactly which skills and rules are currently loaded BEFORE any pending entry is reviewed. Follow the format defined in `superpowers-agent-mode-prompt.md` `<context_manifest_protocol>`. If GAPS are non-zero, ask the user whether to load the missing items first or proceed knowingly.
1. Read `_IMPROVEMENT_QUEUE.md`.
2. List all `pending` entries to the user with full context: id, signal_type, scope, target, proposed_change, evidence, confidence, provider_context.
3. For EACH pending entry, present a diff preview of what the change would look like (read the target file first, show before/after).
4. Ask the user for each entry: **[onayla / reddet / düzenle / ertele]**.
5. Based on user choice:
   - **Onayla (approve):**
     - If `scope: rule` or `scope: schema` → DOUBLE APPROVAL. First confirm: *"Bu kural/schema değişikliği için çift onay gerekiyor. Değişikliği yazmaya hazırım, onaylıyor musun?"* Only proceed on a second explicit yes.
     - **BOOTSTRAP (auto-create if missing):** Before writing, check if the target file exists. If NOT:
       1. Ensure the parent directory exists (`mkdir -p <parent>` equivalent — in bash: `mkdir -p "$(dirname <target>)"`).
       2. Create an empty file or a minimal stub (for `scope: rule`, a one-line topic header `# <topic>`; for other scopes, empty).
       3. Proceed with the normal write step as if the file existed.
       4. Mention in the summary report: *"<target> yeni oluşturuldu."*
     - **DUPLICATE CHECK (MANDATORY before any append):** Before appending content to an existing rule/skill/wiki file, scan the target file for an existing block with the same IMP-ID reference, the same heading, or substantially overlapping content (e.g., the same code example or the same imperative sentence). If a duplicate is found:
       1. Report it to the user: *"Bu içerik zaten {file}:{line} satırında mevcut. (a) yeni bloğu ekleme, mevcudu güncelle, (b) iki bloğu birleştir, (c) yine de ekle (gerekçe iste)."*
       2. Default to (a) UPDATE EXISTING — edit the existing block in place, preserving the original IMP-ID reference and adding any new context.
       3. Choose (b) MERGE only when the user explicitly asks; preserve both IMP-IDs in the merged block.
       4. Choose (c) APPEND ANYWAY only when the user provides a justification (e.g., the duplication is intentional for emphasis); record the justification in the `_LOG.md` entry.
       This gate prevents the historical pattern where the same Anti-Enumeration block or Windows-CMD block was appended multiple times across `/evolve` runs.
     - Apply the change to the target file (Edit tool for existing content, Write tool if the file is empty).
     - **REGISTRY UPDATE (MANDATORY when target is a registered rule or skill):**
       - **If `scope: rule` AND `target` matches `.openskills/rules/<file>.md`:**
         - If the file is NEW (BOOTSTRAP triggered earlier): you MUST add a `<rule>` entry to `.openskills/RULE_REGISTRY.md`.
           1. Ask the user for:
              - Activation pattern: `universal` | `phase-conditional` | `stack-conditional` | `security-mandate` | `pointer`.
              - `applies_phases`: subset of `ideation, specification, planning, implementation, verification, code_review, branch_finish, shipping, debugging` (or `all` for universal).
              - `stack`: only if `stack-conditional` — one of `backend, frontend, mobile, ai, infra`.
           2. Generate a description in "Use when..." form from the entry's `proposed_change` (max ~250 chars, third person).
           3. Show the proposed `<rule>` block as a DIFF PREVIEW. Get explicit user yes BEFORE writing.
           4. Insert the new `<rule>` entry into `<available_rules>` at a sensible position (group with similar activation patterns).
           5. Update `<phase_to_rule_matrix>` — add the new rule name under EACH applicable phase row, in the correct column (Universal / Phase-conditional / Stack-conditional).
         - If the file is EXISTING: re-read the rule's current `<description>` in `RULE_REGISTRY.md`. If the new content introduces a meaningful pattern, technology, or term that the description does NOT mention (e.g., new `AsSplitQuery` guidance added to `backend_standards.md` but the description's enumeration omits it), propose a refreshed description with a DIFF PREVIEW. User approves; then update.
       - **If `scope: skill` AND `target` matches `.openskills/skills/<name>/SKILL.md`:**
         - If the file is NEW: add a `<skill>` entry to `.openskills/SKILL_REGISTRY.md` using the same DIFF-PREVIEW + user-approval pattern. Activation = `eager` | `lazy`. Then ENFORCE PARITY: the registry `<description>` MUST be byte-identical to the skill's frontmatter `description:` field.
         - If the file is EXISTING and the change touches the frontmatter description: update `SKILL_REGISTRY.md` description in lockstep so parity is preserved.
       - **If `scope: schema`, `scope: wiki`, or `scope: active-context`:** registry update is not applicable, skip this sub-step.
       - **Same-transaction rollback:** if the user rejects the registry diff preview, REVERT the target file write made in the previous step (use `git restore <target>` for tracked files, delete the file for newly-created ones). The improvement entry stays `pending`. This prevents partial state where the rule/skill file exists but the registry does not know about it.
       - **`_LOG.md` extension:** append the registry path to the same `evolve` entry, e.g., `## [YYYY-MM-DD] evolve | IMP-NNN applied: <summary>; registry: RULE_REGISTRY.md updated`.
     - Update entry: `status: applied`, add `applied: <today>`, `last_validated: <today>`, `challenges: []`. Move entry from `## Pending` to `## Applied`.
     - Append an `evolve` entry to `_LOG.md`: `## [YYYY-MM-DD] evolve | IMP-NNN applied: <summary>` (extended with registry note per REGISTRY UPDATE step above when applicable).
     - If this was a `signal_type: challenge` entry and it was approved → also update the challenged entry: move it from `## Applied` to `## Superseded`, set `status: superseded`, `superseded_by: <this-id>`, `superseded_at: <today>`.
   - **Reddet (reject):**
     - Move entry to `## Rejected`, set `status: rejected`, `rejected_at: <today>`, ask user for `rejection_reason` and record it.
     - Do NOT write to `_LOG.md` for rejects (avoids log noise).
   - **Düzenle (edit):**
     - Ask user what to change in `proposed_change`/`target`/`scope`, update entry in place, keep it `pending`.
   - **Ertele (defer):**
     - Leave entry in `## Pending`, add `deferred_at: <today>` field.
6. After processing all pending entries, report summary to user: N approved, N rejected, N deferred.
7. If any `schema`, `rule`, or `skill` entries were applied, remind the user: *"Rule/skill değişiklikleri uygulandı, registry de güncellendi (varsa). Yeni session'da agent yeni durumu otomatik keşfedecek. İstersen şimdi `/context` ile manifest'i yeniden bastırabilirim."*
</evolve_review_workflow>

<challenge_detection_rules>
Raise a `challenge` signal when:
- You read a file and its content directly contradicts an applied entry's `proposed_change`.
- Test output, runtime behavior, or profiler data contradicts a performance-related applied entry.
- A newer source (ingested into the wiki) supersedes the basis for an applied entry.
- Another Claude model in a previous session made a decision you now see concrete evidence against.

Do NOT raise a challenge based on:
- Style preference or taste.
- A single datapoint when the applied entry was based on multiple.
- Memory alone — always tie challenges to concrete evidence visible in the current session.

When raising a challenge, the entry's `evidence` field MUST cite the concrete source (file path, test output, commit hash, user quote).
</challenge_detection_rules>

<safety_invariants>
These rules are ABSOLUTE. Violating them breaks user trust in the self-improvement loop:

1. **NEVER write to `.openskills/rules/`, `.openskills/skills/`, `wiki/_SCHEMA.md`, or canonical wiki pages as a result of signal capture.** Only `/evolve` with explicit approval may trigger writes.
2. **NEVER auto-apply a `challenge` signal.** Supersede-flow always requires `/evolve` review.
3. **NEVER delete queue entries.** Use `superseded` or `rejected` status. The queue is append-heavy history.
4. **NEVER skip `provider_context`.** Record which model detected the signal (from environment info). This enables future cross-model reconciliation.
5. **NEVER rewrite past `_LOG.md` entries.** If a mistake was logged, add a new `migration` entry clarifying — don't edit the old one.
6. **NEVER capture sensitive data** (passwords, tokens, user PII) in `evidence` fields. Sanitize before writing.
7. **NEVER let confidence thresholds silence the loop.** If `low` is tempting, escalate to `medium` and let the user decide.
</safety_invariants>

<turkish_user_communication>
Per project identity rules, all user-facing text is in Turkish. When surfacing pending count at session start or presenting review options in `/evolve`, use Turkish. Internal entry fields (`proposed_change`, `evidence`) may be in English or Turkish — mirror whatever language the user used.
</turkish_user_communication>

<re_validation_pulse>
When this skill is loaded for signal capture or `/evolve`, randomly select ONE applied entry whose `last_validated` is older than 90 days. During the session, passively watch for concrete evidence (code, log, file ref) that contradicts that entry's `proposed_change`. If you observe such evidence, automatically open a `challenge` signal — do NOT modify the original entry directly.

If you observe NO contradicting evidence by session end, update the entry's `last_validated` to today (this is a low-friction housekeeping write to the queue file, not a rule/skill mutation).

This pulse keeps applied learnings honest without burdening the user with periodic reviews.
</re_validation_pulse>

<superpowers_integration>
Hook signal capture into specific skill workflows:

| Skill | Hook |
|---|---|
| `brainstorming` / `idea-explore` (ULTRATHINK depth) | Architectural decisions confirmed by the user → `decision` signal at `high` confidence. |
| `systematic-debugging` | A bug pattern repeated 2+ times across sessions → `friction` signal. |
| `requesting-code-review` / `receiving-code-review` | A reviewer (subagent or user) rejects an approach → `correction` signal. |
| `finishing-a-development-branch` | Before final commit, remind the user once: *"Branch kapanışı önce /evolve açmak ister misin?"* Optional, never blocking. |
</superpowers_integration>
