---
name: self-improvement-curator
description: "Use after every user turn to capture correction, confirmation, decision, friction, challenge, resolution, or preference signals (resolution = bugs the agent fixes itself; preference = standing user instructions); or when the user invokes /evolve, says 'evolve', 'review pending improvements', or asks to review captured learnings."
---

<purpose>
This skill implements the agent's self-improvement loop. It captures signals during normal conversation and persists them to a queue that survives across sessions, so the agent can **learn from mistakes, confirmations, and decisions** without losing that knowledge to context compaction or session boundaries.

The core invariant: **NEVER auto-modify rules, skills, schema, or wiki pages based on signals.** All changes flow through a human approval gate via the `/evolve` slash command.

Format contract and entry schema live in `docs/second-brain/wiki/_SCHEMA.md` Section 15. This skill file defines only the behavioral workflow.
</purpose>

<activation>
LAZY — loaded by `using-superpowers` when signal capture or `/evolve` review needs the full workflow. Session-start pending-count surfacing remains governed by `.sumela/sumela-prompt.md`.
</activation>

<trigger_phrases>
This skill's `evolve_review_workflow` MUST be triggered when the user invokes any of these (IDE-agnostic — works in Claude Code, Cursor, Copilot, or any agent that loads this skill):

**Slash command (Claude Code only):** `/evolve`

**Natural language triggers (all IDEs, in any language — these are English references):**
- "run evolve", "review improvements", "review pending improvements", "show the improvement queue", "let's review what you learned", or the equivalent in the user's language.

When any trigger fires, execute `<evolve_review_workflow>` below. The workflow definition here is the SINGLE SOURCE OF TRUTH — the Claude Code slash command at `.claude/commands/evolve.md` is only a thin ergonomic shortcut that delegates to this skill.
</trigger_phrases>

<session_start_protocol>
Pending-count surfacing at session start is performed by `sumela-prompt.md` (`<session_bootstrap>` STEP 2). Do NOT duplicate that read here.

The full set of `_improvement-queue/IMP-*.md` entries is scanned ONLY when `/evolve` is triggered (see `<evolve_review_workflow>`). Re-validation pulse and applied-entry loading happen inside the evolve workflow, not at session start.
</session_start_protocol>

<signal_capture_workflow>
During every user turn — and after you independently resolve a bug or problem — scan for these seven signal types. Capture is silent — you do NOT announce that you're capturing unless asked.

**Signal types** (full definitions in `_SCHEMA.md` Section 15.4):

1. **`correction`** — User says "no", "not like that", "don't do it this way again", "don't use that", or the equivalent in any language. Capture: what they corrected, what the correct approach is.

2. **`confirmation`** — User validates a non-obvious choice you made ("yes, exactly", "good call", "nice catch"). Only capture if the choice was **contested or non-default** — don't capture routine "ok" responses.

3. **`decision`** — A decision is made during brainstorming/ULTRATHINK about **how the agent should work** (which rule to add, which workflow to change, which skill to invoke differently). Capture: the decision, alternatives, reason.

   **CRITICAL BOUNDARY — do NOT double-capture with `using-second-brain` DECISION CAPTURE (operation #5):**
   - **Project architectural decisions** (which technology, which pattern, which endpoint design — answers to "would another developer on this project also follow this?") → handled by `using-second-brain` DECISION CAPTURE workflow → written to `wiki/architecture-decisions.md` as AD-XX. DO NOT capture these as `decision` signals.
   - **Agent behavioral decisions** (which rule file should change, which skill should be updated, how the agent should approach a class of tasks differently — answers to "this is about how the agent works, not about the project") → capture as `decision` signal in the queue.
   - Decision tree: *"If a new developer joined the team without Claude, would this decision still apply to them?"* → **Yes** = project decision (wiki) / **No** = agent decision (queue).
   - Edge case: if a decision has BOTH dimensions (e.g., "we'll use Redis AND the agent should always propose Redis for read-heavy patterns"), split into two entries: the project fact goes to the wiki via DECISION CAPTURE, the agent behavior goes to the queue as a `decision` signal.

4. **`friction`** — The same mistake or question repeats within or across sessions. Capture: the pattern, the friction it caused.

5. **`challenge`** — You observe concrete evidence (code, logs, behavior) that contradicts an existing `applied` entry. Capture: which IMP-ID is challenged, what the contradicting evidence is.

6. **`resolution`** — You autonomously diagnosed and fixed a bug, or worked a non-trivial problem through to a working solution, **without the user pointing it out**. The agent flags its OWN learning here; capture stays silent. This is the only signal type that originates from the agent's own problem-solving rather than a user turn.

   **Generalize the lesson — capture the CLASS of problem, never the one-off instance.** The `proposed_change` must read as a guard that prevents a DIFFERENT future occurrence of the same class, not a note about this specific symptom:
   - ✗ instance (useless): *"OrderService wasn't registered in the DI container, so I added it."*
   - ✓ class (reusable): *"When a new service is created it must be registered in the DI container — otherwise you get a runtime resolve error."*

   Generalization test: *"Would this sentence prevent a DIFFERENT future case of the same class (another service, another module)?"* If no, it is too specific — generalize it or skip it. Strip instance-specific identifiers (the concrete service/file/value) from `proposed_change`; keep them only in `evidence` as the triggering example.

   - **Confidence:** `medium` by default (concrete evidence — the error + the fix diff — but the user didn't weigh in, so it MUST be captured); escalate to `high` if the same class already cost time in a prior session (it is then also `friction`) or the root cause was non-obvious.
   - **Scope:** usually `rule` (a standard the agent should follow going forward — append to the most relevant OVERLAY `.sumela/rules/<category>.md`, never an upstream-managed CORE rule file; see "direct rule integration"). Use `wiki` only when the lesson is a project-specific architectural fact, not a general practice.

7. **`preference`** — The user volunteers a durable, forward-looking standing instruction about how you should work, **without reacting to a specific mistake**: *"always use strict mode from now on"*, *"keep comments minimal"*, *"write PR descriptions in this format"*, *"'deploy' means staging"*. Capture the standing rule and the scope it applies to.

   **Distinct from `correction`:** `correction` is REACTIVE — the user rejects a specific output, so an error occurred. `preference` is PROACTIVE — a standing rule offered with no triggering mistake. Test: *if the user is fixing something you just did → `correction`; if they are setting a rule for FUTURE work independent of any specific output → `preference`.* (Negative-reactive phrasings like "don't do it this way again" / "don't use that" stay `correction`.)

   - **Confidence:** an explicit standing instruction → `high` (MUST capture); a preference merely inferred from one ambiguous remark → `medium`.
   - **Scope:** usually `rule` (a behavioral standard — append to the relevant OVERLAY `.sumela/rules/<category>.md`, never an upstream-managed CORE rule file; see "direct rule integration"); use `active-context` if it is sprint-scoped rather than durable. If unsure, pick the closest scope and let `/evolve` reclassify.

**Confidence assignment (CRITICAL — anti-silence rule):**

| Situation | Confidence |
|---|---|
| Explicit user confirmation OR rejection OR 2+ repeated corrections | `high` — MUST capture |
| Concrete evidence (code/log/file ref) but user didn't explicitly weigh in | `medium` — MUST capture |
| Pure intuition, no concrete anchor | `low` — SKIP capture |

**When in doubt: pick `medium`, never `low`.** The `/evolve` review gate protects the user; silent skipping is the worse failure mode.

**Capture procedure (one file per signal — NO shared counter):**
1. Generate the ID `IMP-YYYYMMDD-<short>` where `YYYYMMDD` is today's date and `<short>` is 4 random lowercase base36 chars (e.g., `IMP-20260601-a3f8`). There is NO "next ID" counter — the ID is self-generated locally so concurrent captures by different developers never collide.
2. Confirm `docs/second-brain/wiki/_improvement-queue/<id>.md` does not already exist; on the rare clash, regenerate `<short>` and retry.
3. Create that file with YAML frontmatter (scannable metadata, including `status: pending`) plus body sections `## Proposed Change` and `## Evidence`, following the schema in `_SCHEMA.md` Section 15.2–15.3. The `id:` frontmatter MUST equal the filename stem.
4. Do NOT update `_LOG.md` for pending entries — only `proposed`/`applied`/`superseded` get log entries (rejects are never logged).
5. Do NOT notify the user mid-turn. The session-start notification covers visibility.

**Scope decision (which file would this eventually touch?):**

| Evidence points to… | `scope` | Default target path |
|---|---|---|
| A behavioral/workflow rule (how to act, what to avoid) | `rule` | `.sumela/rules/<existing_category>.md` or `<new_topic>.md` |
| A reusable skill workflow | `skill` | `.sumela/skills/<skill-name>/SKILL.md` |
| A fact/entity/architecture on the project | `wiki` | `docs/second-brain/wiki/<page>.md` |
| Current sprint/status | `active-context` | `docs/second-brain/wiki/active-project-context.md` |
| Wiki format itself | `schema` | `docs/second-brain/wiki/_SCHEMA.md` |

**IMPORTANT — direct rule integration:** For `scope: rule`, the DEFAULT target is `.sumela/rules/`. Do not use `.sumela/learned-rules/` anymore.

**CORE vs OVERLAY — NEVER append a project rule to an upstream-managed CORE file.** These 7 universal rule files are SHIPPED and MANAGED by SumelaOS upstream, and `scripts/update.sh` refreshes them (with consent) on every upgrade:
`engineering_philosophy`, `identity_and_behavior`, `architecture_patterns`, `audit_and_output`, `security_protocol`, `git_workflow_mandatory_review_protocol`, `self_improvement_protocol`.
A rule appended to one of these is either silently lost when the user applies the upstream diff, or it permanently forks the file — costing every future upstream improvement to it. (This is a recurring trap: a general-sounding principle "fits" `engineering_philosophy.md`, so it gets appended there and is clobbered on the next update.)

Route a new project rule to an **OVERLAY** file instead — these are project-owned and `update.sh` NEVER touches them:
- the most relevant stack / ops / domain file: `backend_standards.md`, `frontend_standards.md`, `mobile_standards.md`, `operational_excellence_maintenance.md`, `domains/<slug>.md`; or
- a NEW `.sumela/rules/<topic>.md` — **any rule file NOT in the 7-core set above is OVERLAY by construction** (update only refreshes the named core files + `rules/templates/`).
Then register the file in `RULE_REGISTRY.md` (see REGISTRY UPDATE) — a new overlay rule usually wants `activation="universal"` if it is a general standard.

To EXTEND or OVERRIDE a core rule's behavior for this project (not add an unrelated rule), do NOT edit the core file — add an OVERLAY rule on the same topic (e.g. `engineering_philosophy_project.md`). Rules are additive constraints loaded together, so an overlay rule layers on top of (and can tighten/override) the core one while the core file stays cleanly upstream-managed.

If the principle is genuinely UNIVERSAL and belongs to the framework itself (not just this project), do NOT append it locally at all — propose it UPSTREAM (a PR to the SumelaOS repo's core `engineering_philosophy.md` etc.) so every project gets it and you carry no local fork.

Since `.sumela/rules/` is the canonical IDE-agnostic rule layer, this eliminates the need for manual migration to IDE-specific folders.

If unsure, pick the closest scope and let `/evolve` review reclassify it.
</signal_capture_workflow>

<evolve_review_workflow>
Triggered by the user invoking `/evolve` (or explicitly asking to show pending improvements / review what was learned, in any language).

0. PRINT CONTEXT MANIFEST FIRST. `/evolve` mutates rules/skills/schema/wiki, so the user must see exactly which skills and rules are currently loaded BEFORE any pending entry is reviewed. Follow the format defined in `sumela-prompt.md` `<context_manifest_protocol>`. If GAPS are non-zero, ask the user whether to load the missing items first or proceed knowingly.
0.5. GOVERNANCE + RECONCILE.
   - Read the governance mode from `AGENTS.md` Section 8 (`governance: solo | team`). **Gated scopes** = `rule`, `skill`, `schema` (the agent-control surface that changes every developer's agent). `wiki` / `active-context` are NEVER gated. In `solo` mode there are no PRs to reconcile — skip the rest of this step.
   - **Reconcile in-flight proposals (team mode).** A proposed change's `status: proposed` flip lives inside its own still-open PR, so it only reaches the base branch when that PR merges. First `git fetch` so PR/merge state is current. Find every in-flight proposal — the `sumela/evolve-<IMP-ID>` branches and their PRs (`gh pr list --head 'sumela/evolve-*' --state all`, or `glab`; if neither CLI is available, ask the user the state of each `sumela/evolve-*` branch). For each:
     - PR **merged** → the merge carried that entry's `status: proposed` onto base. `git pull` the base so the merge is local, THEN flip the entry frontmatter `status: applied`, add `applied: <today>`, `last_validated: <today>`, `challenges: []`; append `_LOG.md` `evolve | <IMP-ID> applied: <summary> (PR merged)` — but only if no `evolve | <IMP-ID> applied` line already exists (idempotent: a re-run must not double-log); if it was a `signal_type: challenge`, NOW run the challenge-supersede update on the challenged entry (and log `supersedes: <IMP-ID>`). Delete the merged local branch.
     - PR **closed without merge** → the change never reached base; the entry on base is still `pending`. Mark it `status: rejected`, `rejected_at: <today>`, `rejection_reason: "evolve PR closed without merge"`. Delete the local branch.
     - PR **still open** → report it to the user ("IMP-… still awaiting code-owner review: <pr>"); leave it (step 1's skip-guard keeps it from being re-proposed).
   - Also scan base for any entry already `status: proposed` whose merge you reconciled in a prior session but didn't finalize: `grep -l "^status: proposed" docs/second-brain/wiki/_improvement-queue/IMP-*.md` → if its PR is merged, flip to `applied` as above.
1. Scan the queue directory: `grep -l "^status: pending" docs/second-brain/wiki/_improvement-queue/IMP-*.md` (PowerShell: `Select-String -Path docs/second-brain/wiki/_improvement-queue/IMP-*.md -Pattern "^status: pending"`). Use the `IMP-*.md` glob — never `grep -r` over the directory, which would also match the example in `README.md`.
   - **In-flight skip-guard (team mode):** a `proposed` entry's status flip lives inside its still-open PR, so on the base branch it may still read `pending`. Before listing a pending entry, skip it if an evolve PR is already in flight for it: `git branch --list "sumela/evolve-<IMP-ID>"` is non-empty OR `gh pr list --head "sumela/evolve-<IMP-ID>" --state open` returns a PR. Report such entries as "in review" (handled by reconcile), do NOT re-propose them.
2. List all `pending` entries to the user with full context (frontmatter: id, signal_type, scope, target, confidence, provider_context; body: `## Proposed Change`, `## Evidence`).
3. For EACH pending entry, present a diff preview of what the change would look like (read the target file first, show before/after).
4. Ask the user for each entry: **[approve / reject / edit / defer]** (render the options in the user's language).
5. Based on user choice:
   - **Approve:**
     - If `scope: rule` or `scope: schema` → DOUBLE APPROVAL. First confirm: *"This rule/schema change needs a second approval. I'm ready to write it — do you confirm?"* Only proceed on a second explicit yes.
     - **ROUTING (governance, from step 0.5):** first VALIDATE `scope` — it MUST be one of `rule`, `skill`, `schema`, `wiki`, `active-context`. If it is missing or unrecognized, STOP and ask the user to fix the entry's scope; do NOT default to direct apply (a typo'd gated scope must never bypass the team gate). Then: if mode is `team` AND `scope` ∈ {`rule`, `skill`, `schema`} → use the **PR-GATED PATH** terminal. Otherwise (`solo` mode, or `scope` ∈ {`wiki`, `active-context`}) → use the **DIRECT PATH** terminal. The change MECHANICS below (BOOTSTRAP, DUPLICATE CHECK, apply, REGISTRY UPDATE) are IDENTICAL in both paths — only WHERE they run (working tree vs a dedicated branch) and the entry's terminal status differ.
     - **BOOTSTRAP (auto-create if missing):** Before writing, check if the target file exists. If NOT:
       1. Ensure the parent directory exists (`mkdir -p <parent>` equivalent — in bash: `mkdir -p "$(dirname <target>)"`).
       2. Create an empty file or a minimal stub (for `scope: rule`, a one-line topic header `# <topic>`; for other scopes, empty).
       3. Proceed with the normal write step as if the file existed.
       4. Mention in the summary report: *"<target> was created."*
     - **DUPLICATE CHECK (MANDATORY before any append):** Before appending content to an existing rule/skill/wiki file, scan the target file for an existing block with the same IMP-ID reference, the same heading, or substantially overlapping content (e.g., the same code example or the same imperative sentence). If a duplicate is found:
       1. Report it to the user: *"This content already exists at {file}:{line}. (a) don't add a new block, update the existing one; (b) merge the two blocks; (c) append anyway (ask for a justification)."*
       2. Default to (a) UPDATE EXISTING — edit the existing block in place, preserving the original IMP-ID reference and adding any new context.
       3. Choose (b) MERGE only when the user explicitly asks; preserve both IMP-IDs in the merged block.
       4. Choose (c) APPEND ANYWAY only when the user provides a justification (e.g., the duplication is intentional for emphasis); record the justification in the `_LOG.md` entry.
       This gate prevents the historical pattern where the same Anti-Enumeration block or Windows-CMD block was appended multiple times across `/evolve` runs.
     - Apply the change to the target file (Edit tool for existing content, Write tool if the file is empty).
     - **REGISTRY UPDATE (MANDATORY when target is a registered rule or skill):**
       - **If `scope: rule` AND `target` matches `.sumela/rules/<file>.md` OR `.sumela/rules/domains/<slug>.md`:**
         - If the file is NEW (BOOTSTRAP triggered earlier): you MUST add a `<rule>` entry to `.sumela/RULE_REGISTRY.md`.
           1. Ask the user for:
              - Activation pattern: `universal` | `phase-conditional` | `stack-conditional` | `domain-conditional` | `security-mandate` | `pointer`.
              - `applies_phases`: subset of `ideation, specification, planning, implementation, verification, code_review, branch_finish, shipping, debugging` (or `all` for universal / domain-conditional).
              - `stack`: only if `stack-conditional` — one of `backend, frontend, mobile, ai, infra`.
              - `domain`: only if `domain-conditional` — the business domain (original case, e.g. `Card`). The rule file MUST live at `.sumela/rules/domains/<slug>.md` (slug = lowercase, non-alphanumeric → `-`); render it from `.sumela/rules/templates/domain_standards.md.empty` (substituting `{{domain_name}}`/`{{date_created}}`) if BOOTSTRAP made only a stub. If the domain is NOT already a row in `<domain_scopes>`, you MUST ALSO add a `<domain_scopes>` row for it (that block is the source of truth for valid `domain=` values).
           2. Generate a description in "Use when..." form from the entry's `proposed_change` (max ~250 chars, third person).
           3. Show the proposed `<rule>` block (plus any new `<domain_scopes>` row) as a DIFF PREVIEW. Get explicit user yes BEFORE writing.
           4. Insert the new `<rule>` entry into `<available_rules>` at a sensible position (group with similar activation patterns).
           5. Update `<phase_to_rule_matrix>` — add the new rule name under EACH applicable phase row, in the correct column (Universal / Phase-conditional / Stack-conditional / Domain-conditional).
         - If the file is EXISTING: re-read the rule's current `<description>` in `RULE_REGISTRY.md`. If the new content introduces a meaningful pattern, technology, or term that the description does NOT mention (e.g., new `AsSplitQuery` guidance added to `backend_standards.md` but the description's enumeration omits it), propose a refreshed description with a DIFF PREVIEW. User approves; then update.
       - **If `scope: skill` AND `target` matches `.sumela/skills/<name>/SKILL.md`:**
         - If the file is NEW: add a `<skill>` entry to `.sumela/SKILL_REGISTRY.md` using the same DIFF-PREVIEW + user-approval pattern. Activation = `eager` | `lazy`. Then ENFORCE PARITY: the registry `<description>` MUST be byte-identical to the skill's frontmatter `description:` field.
         - If the file is EXISTING and the change touches the frontmatter description: update `SKILL_REGISTRY.md` description in lockstep so parity is preserved.
       - **If `scope: schema`, `scope: wiki`, or `scope: active-context`:** registry update is not applicable, skip this sub-step.
       - **Same-transaction rollback:** if the user rejects the registry diff preview, REVERT the target file write made in the previous step (use `git restore <target>` for tracked files, delete the file for newly-created ones). The improvement entry stays `pending`. This prevents partial state where the rule/skill file exists but the registry does not know about it.
       - **`_LOG.md` extension:** append the registry path to the same `evolve` entry, e.g., `## [YYYY-MM-DD] evolve | <IMP-ID> applied: <summary>; registry: RULE_REGISTRY.md updated`.
     - **DIRECT PATH terminal** (solo mode, or `scope` ∈ {`wiki`, `active-context`}): the mechanics above ran in the working tree. Now:
       - Edit the entry FILE's frontmatter IN PLACE: `status: applied`, add `applied: <today>`, `last_validated: <today>`, `challenges: []`. The file does NOT move — its `status` field is the source of truth.
       - Append an `evolve` entry to `_LOG.md`: `## [YYYY-MM-DD] evolve | <IMP-ID> applied: <summary>` (extended with registry note per REGISTRY UPDATE step above when applicable).
       - If this was a `signal_type: challenge` entry and it was approved → also edit the challenged entry FILE's frontmatter in place: `status: superseded`, `superseded_by: <this-id>`, `superseded_at: <today>`.
     - **PR-GATED PATH terminal** (team mode AND `scope` ∈ {`rule`, `skill`, `schema`}): EVERYTHING goes into ONE pull request — never write the gated change OR the entry's status flip directly to the protected base branch.
       1. Resolve the base: `BASE=$(git symbolic-ref --short HEAD)` is NOT it — determine the integration base explicitly (`main` or `master`, whichever exists). Create the work branch off that base: `git checkout -b sumela/evolve-<IMP-ID> <base>`.
       2. On this branch, run the Shared mechanics (BOOTSTRAP, DUPLICATE CHECK, apply, REGISTRY UPDATE) for the gated file(s) + registry.
       3. ALSO on this branch, edit the entry FILE's frontmatter: `status: proposed`, `proposed_at: <today>` (leave `pr:` for step 5). Committing the entry flip INSIDE the PR — not on base — is what keeps base unwritten; the pending-scan skip-guard (step 1) prevents re-listing in the meantime.
       4. Commit everything together with a Conventional Commit citing the entry: `git commit -m "feat(agent): apply <IMP-ID> — <summary>"`.
       5. Open a PR targeting the base: `gh pr create --fill --base <base>` (or `glab mr create`). Capture the returned URL and set the entry's `pr: <url>` (amend the commit). **If neither CLI is available:** push the branch, print a ready-to-paste PR title + body (citing the entry's evidence), and ask the user to open the PR. Do this BEFORE flipping anything user-visible — if the user cannot provide a PR URL now, REVERT the entry flip (leave it `status: pending`) and tell them the branch `sumela/evolve-<IMP-ID>` is pushed and ready; re-run `/evolve` once the PR exists. Never leave an entry `proposed` with a `pr:` that is only a branch name and no real PR.
       6. Return to where you started: `git checkout -` (safe — nothing was written to base; the entry flip lives in the PR branch only).
       - Append an `evolve` entry to `_LOG.md` on the branch: `## [YYYY-MM-DD] evolve | <IMP-ID> proposed: <summary> (PR: <url>)`.
       - Do NOT mark `applied` and do NOT run the challenge-supersede update yet — both happen at RECONCILE (step 0.5) when the PR merges (the merge brings `status: proposed` onto base; reconcile then flips it to `applied`).
       - Tell the user: the change awaits a code owner's review in the PR; it becomes `applied` automatically on the next `/evolve` after the PR merges.
   - **Reject:**
     - Edit the entry FILE's frontmatter in place: `status: rejected`, `rejected_at: <today>`; ask user for `rejection_reason` and record it. The file is NOT deleted.
     - Do NOT write to `_LOG.md` for rejects (avoids log noise).
   - **Edit:**
     - Ask user what to change in the `## Proposed Change` body / `target` / `scope`, update the entry file in place, keep `status: pending`.
   - **Defer:**
     - Leave `status: pending`, add a `deferred_at: <today>` frontmatter field.
6. After processing all pending entries, report summary to user: N applied (direct), N proposed (PR opened, team mode), N rejected, N deferred — plus any reconcile outcomes from step 0.5 (N merged→applied).
7. Closing reminder, governance-aware:
   - If any gated entry was **applied directly** (solo mode): *"Rule/skill changes applied, and the registry was updated (if relevant). A new session will discover the new state automatically. I can reprint the manifest with `/context` if you want."*
   - If any gated entry was **proposed** (team mode): *"Rule/skill/schema changes were opened as a PR and await code-owner review; once merged, the next `/evolve` flips them to `applied` automatically. PR links: <…>."* Do NOT claim these are live yet — they take effect only after the PR merges.
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

1. **NEVER write to `.sumela/rules/`, `.sumela/skills/`, `wiki/_SCHEMA.md`, or canonical wiki pages as a result of signal capture.** Only `/evolve` with explicit approval may trigger writes.
2. **NEVER auto-apply a `challenge` signal.** Supersede-flow always requires `/evolve` review.
3. **NEVER delete queue entry files.** Use `superseded` or `rejected` status (edited into the file's frontmatter). Each `IMP-*.md` file is permanent history.
4. **NEVER skip `provider_context`.** Record which model detected the signal (from environment info). This enables future cross-model reconciliation.
5. **NEVER rewrite past `_LOG.md` entries.** If a mistake was logged, add a new `migration` entry clarifying — don't edit the old one.
6. **NEVER capture sensitive data** (passwords, tokens, user PII) in `evidence` fields. Sanitize before writing.
7. **NEVER let confidence thresholds silence the loop.** If `low` is tempting, escalate to `medium` and let the user decide.
</safety_invariants>

<user_communication_language>
All user-facing text uses the project's configured **interaction language** (per `AGENTS.md` Section 2, overridable per-developer via `.sumela/local.md` — resolved at `sumela-prompt.md` session bootstrap; defaults to English). When surfacing the pending count at session start or presenting review options in `/evolve`, use that language. Internal entry fields (`proposed_change`, `evidence`) may be in any language — mirror whatever language the user used.
</user_communication_language>

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
| `systematic-debugging` (root cause fixed) | A bug diagnosed and fixed to a working state → `resolution` signal capturing the GENERALIZED root-cause guard (the class, not the instance). |
| `requesting-code-review` / `receiving-code-review` | A reviewer (subagent or user) rejects an approach → `correction` signal. |
| `finishing-a-development-branch` | Before final commit, remind the user once: *"Want to run /evolve before closing the branch?"* Optional, never blocking. |
</superpowers_integration>
