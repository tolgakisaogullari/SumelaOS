---
name: using-superpowers
description: "Use at the start of every conversation and before generating any response — including clarifying questions — to dispatch the right skills, capture signals, and check for information gaps."
---

<execution_workflow>
Run this dispatch loop BEFORE every response. Do NOT skip it for "simple" tasks.
<SUBAGENT-STOP>EXCEPTION: When dispatched as a focused task subagent, skip this skill.</SUBAGENT-STOP>

## STEP 1 — Authority hierarchy (resolve conflicts)

Order: user explicit instructions → `.openskills/superpowers-agent-mode-prompt.md` → loaded skill bodies → `.openskills/rules/*.md` → IDE default. User instructions ALWAYS override; the user is in control. If a skill body and the prompt file disagree on session bootstrap or signal capture, the prompt file wins. If a rule contradicts a loaded skill workflow, the skill wins for that workflow phase.

## STEP 2 — Signal capture from previous turn (silent)

Apply `.openskills/superpowers-agent-mode-prompt.md` `<signal_capture>` exactly. High/medium-confidence `correction`, `confirmation`, `decision`, `friction`, or `challenge` signals load `self-improvement-curator` and create pending queue entries. Mutations still flow only through `/evolve`.

## STEP 3 — Information gap check (silent, BUT enforced via canonical contract)

Before answering, ask: "Do I need context I don't already have?" Apply the canonical `<information_gap_routing>` block BEFORE drafting.

For deep workflows (ingest, code-commit, lint) or when multi-collection Qdrant routing is needed (`wiki_pages`, `code_chunks`), load `using-second-brain` and follow its INFORMATION GAP RESOLUTION section.

NEVER skip mandatory Tier-1/Tier-2 routing for matching historical, decision, call-graph, dependency, or impact questions.

### STEP 3b — Proactive Impact Analysis (silent, before code changes)

**WHEN:** Before modifying any function, class, method, or file — if the graphify-code-graph plugin is active (`.openskills/memory-plugins/graphify-code-graph/scripts/query-graph.py` exists).

**HOW:**
1. Identify the symbol(s) being changed (function name, class name, method name).
2. Run: `python .openskills/memory-plugins/graphify-code-graph/scripts/query-graph.py "<symbol>" --impact`
3. Parse the output: which files/classes/functions depend on this symbol?
4. If impact is non-trivial (3+ dependents): silently expand the change scope to include all affected files. Verify each affected file still compiles/works after the change.
5. If graphify is unavailable or graph.json is missing: skip silently — no fallback needed, this is an enhancement.

**WHY:** A change to `AuthService.RegisterAsync` might break `AuthController.Register`, `LoginFlow.Execute`, and `UserIntegrationTest`. Proactive impact detection prevents cascading failures without requiring the user to ask "what else is affected?"

**RULE:** This is SILENT — do not announce "I'm checking impact via graphify" unless the user explicitly asks. Just do it and incorporate the results into your analysis.

## STEP 4 — Skill discovery and loading

Walk through the active task and load every skill whose `description` matches:

- Process skills (load BEFORE implementation skills): `brainstorming`, `idea-explore`, `writing-plans`, `systematic-debugging`, `test-driven-development`.
- Implementation skills: `executing-plans`, `subagent-driven-development`, `using-git-worktrees`, `dispatching-parallel-agents`.
- Quality gates: `verification-before-completion`, `requesting-code-review`, `receiving-code-review`, `finishing-a-development-branch`.
- Cross-cutting: `secure-coding-standard`, `performance-optimization`, `shipping-and-launch`.

GLOBAL SECURITY MANDATE — If the task involves planning, writing, or reviewing code, load `secure-coding-standard` regardless of whether the user mentioned security.

<EXTREMELY-IMPORTANT>If a skill might apply with even 1% probability, load it. Memory of a previously-read skill is NOT a substitute for re-reading the current file.</EXTREMELY-IMPORTANT>

## STEP 5 — Skill execution protocol

- Announce loaded skills inline only if the user asked what you're doing; otherwise stay silent.
- If a loaded skill contains a checklist, create a TodoWrite item per step.
- Cross-check skill dependencies — e.g., before any commit step, ensure `requesting-code-review` is queued.
- INTERACTIVE PAUSES — When a skill explicitly asks the user (TDD opt-in, architecture choice, double-approval), STOP and wait. Never assume "yes".
- Skill types: rigid skills (e.g., `systematic-debugging`, `secure-coding-standard`) follow exactly — do NOT adapt away discipline; flexible skills (architecture patterns, conventions) adapt principles to context. The skill body declares which.
- Once loaded, the skill's `<execution_workflow>` is the operating directive for that phase.

## STEP 5b — Print Context Manifest (visibility checkpoint)

Print the Context Manifest exactly when `.openskills/superpowers-agent-mode-prompt.md` `<context_manifest_protocol>` requires it: after bootstrap, phase transitions, high-stakes actions, `/evolve`, or explicit user request. The GAPS section is the lint layer; never skip a mandatory manifest.

## STEP 6 — Forbidden rationalizations

- "This task is too simple to need a skill" — wrong, run the dispatch loop anyway.
- "Let me ask the user a clarifying question first" — wrong, skill check runs BEFORE clarifying questions.
- "I'll explore the codebase / check git first, skills later" — wrong, skills tell you HOW to explore; files lack conversation context.
- "I'll just do this one small thing first" — wrong, check BEFORE doing anything.
- "I remember this skill, no need to re-read" — wrong, skills evolve; load the file.
- "I'll commit and review later" — wrong, `requesting-code-review` runs before any commit.
- "Inline execution is equivalent to subagent dispatch" — wrong unless the skill defines an explicit IDE Fallback Protocol.
- "The manifest is noise, I'll skip it" — wrong, the manifest is the ONLY way the user sees gaps. Skipping it defeats the entire visibility design.
</execution_workflow>
