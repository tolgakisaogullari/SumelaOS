---
name: onboard-sumela
description: "Use when a developer joins a project that ALREADY has SumelaOS committed — '/onboardSumela', 'onboard SumelaOS', 'join this project', 'set up my clone', 'projeye katıl', 'kurulumumu yap'. Wires git hooks, sets the per-developer interaction language + domains, and offers the optional memory runtime — WITHOUT re-running install or touching team-wide config. NOT for first-time install (that is /initSumela)."
---

<purpose>
A teammate who pulls an already-initialized SumelaOS repo gets all the TEAM-WIDE,
tracked config for free (AGENTS.md, the registries, rules, the domain taxonomy, the
prompt, the hooks files). What they do NOT get automatically — because git cannot
carry it — are the PER-DEVELOPER, untracked pieces:

  * git hooks wiring (`core.hooksPath` is local git config, never shared)
  * their interaction language (`.sumela/local.md`, gitignored)
  * which business domain(s) they work in (`.sumela/local.md` `domains:`)
  * the optional memory-plugin runtime (Qdrant / Ollama / graphify on their machine)

This skill fills exactly those gaps with a guide-and-confirm flow, so a new teammate
has zero manual homework. It NEVER re-asks or regenerates team-wide config (project
name, code-naming/documentation language, governance, the domain taxonomy) — those
are committed and owned by the team. This is the teammate counterpart to /initSumela
(first-time install): if the project has NO `.sumela/` yet, use /initSumela instead.
</purpose>

<activation>
LAZY — loaded on demand when the user invokes /onboardSumela or an equivalent ("onboard
me", "set up my clone", "projeye katıl"). It is ALSO the single source of truth that the
`<onboarding_gate>` in `sumela-prompt.md` defers to: when the gate detects an un-onboarded
clone it follows THIS skill rather than duplicating the steps.
</activation>

<execution_workflow>
Execute in order. This skill only writes the per-developer file `.sumela/local.md`, local
git config, and (with consent) plugin runtime — it MUST NOT modify any tracked team-wide
file unless STEP 6 explicitly applies the solo-mode new-domain path.

## STEP 1 — Detect state (read-only)
Run a quick health read; if the clone is already onboarded, say so and STOP (idempotent).
  ☐ `bash scripts/status.sh` (or `pwsh scripts/status.ps1`) — note the "Git hooks" line.
  ☐ Check `.sumela/local.md` exists.
  ☐ If the project registers memory plugins (grep `SKILL_REGISTRY.md` for
    `qdrant-session-memory` / `graphify-code-graph`), note whether their runtime is up
    (status.sh reports Qdrant reachability; absence just means "offer to set up").

If hooks are wired to THIS install AND `.sumela/local.md` exists → report
"Already onboarded — nothing to do" and STOP. Otherwise continue with only the missing
steps.

## STEP 2 — Ask ONLY the per-developer questions
Resolve the interaction language FIRST (everything below is shown in it). Ask:

```
## 👤 Your per-developer setup

1. Interaction language — what language should the agent talk to YOU in?
   (Project default is AGENTS.md Section 2; this overrides it for your clone only.)
   Your choice: ___

2. Business domain(s) — which domain(s) do you work in? (only if the project uses them)
   Available in this project: <list the names from RULE_REGISTRY.md <domain_scopes>>
   Pick one or more (comma-separated), name a NEW one, or leave blank.
   Your choice: ___
```

To populate the domain list, READ `.sumela/RULE_REGISTRY.md` `<domain_scopes>` and present
the domain names (ignore the `(none)` placeholder row). NEVER ask about code-naming
language, documentation language, governance, or the domain taxonomy — those are
team-wide and already committed.

## STEP 3 — Write `.sumela/local.md` (per-developer, untracked)
Copy `.sumela/local.md.example` → `.sumela/local.md` if absent, then set:
  * `interaction_language:` to the answer (or the AGENTS.md default if blank).
  * `domains:` to the chosen domain(s), comma-separated (omit/blank if none).
`.sumela/local.md` is gitignored — confirm it is NOT staged.

## STEP 4 — Wire git hooks (idempotent, non-destructive)
Run the framework's dedicated hooks-only wirer:

```bash
bash scripts/setup.sh --hooks-only      # PowerShell: pwsh scripts/setup.ps1 -HooksOnly
```

This sets `core.hooksPath` and handles EVERY case correctly — unset, already-this-install,
an existing SumelaOS dispatcher, another SumelaOS install (→ promotes to a monorepo
dispatcher), and a non-SumelaOS path like Husky (→ warns and does NOT override). It does
NOT generate or touch any tracked config. Relay its output to the user (especially the
Husky/non-SumelaOS warning, which needs a manual hook merge). Do NOT run the full
`setup.sh` / `/initSumela`: those regenerate the tracked overlay (AGENTS.md,
RULE_REGISTRY.md, rules) and would clobber the committed team config.

## STEP 5 — Offer the optional memory runtime (guide-and-confirm)
Only if the project registers memory plugins and the developer wants them: run
`bash scripts/setup-memory.sh --plugins <registered-list>` (PowerShell: `setup-memory.ps1
-Plugins ...`). It auto-installs safe deps and CONFIRMS each invasive step (Docker/Ollama/
graphify) — relay its summary verbatim; never paraphrase its one-time commands. If declined,
skip — the agent still degrades gracefully (markdown / grep fallback). This step never
edits tracked files.

## STEP 6 — New-domain edge case
If the developer named a domain that is NOT in the taxonomy (`<domain_scopes>`):
  * Their `domains:` value is still written to `.sumela/local.md` in STEP 3 so they are not
    blocked; until the taxonomy includes it, `sumela-prompt.md` STEP 4 warns-and-skips that
    value (no rule loads for it yet).
  * Adding the domain is a TRACKED, team-wide change (a `<domain_scopes>` row + a
    `<rule activation="domain-conditional">` entry + a `.sumela/rules/domains/<slug>.md`
    file). Branch on `AGENTS.md` governance:
    - **solo** — apply it directly: append the scope row + the domain-conditional rule entry
      to `.sumela/RULE_REGISTRY.md`, and render `.sumela/rules/templates/domain_standards.md.empty`
      → `.sumela/rules/domains/<slug>.md` (substitute `{{domain_name}}`/`{{date_created}}`).
      Then PROVE parity: `python3 scripts/reconcile-registry.py --check` AND
      `bash scripts/validate-structure.sh` must pass.
    - **team** — do NOT edit the agent-control surface inline. Route it through `/evolve`
      as a `scope: rule` change with `activation: domain-conditional` (its REGISTRY UPDATE
      step adds the `<domain_scopes>` row + the domain-conditional `<rule>` entry + renders
      `.sumela/rules/domains/<slug>.md`, then opens a CODEOWNERS-reviewed PR for
      `RULE_REGISTRY.md` + `.sumela/rules/`). Tell the developer their domain activates once
      that PR merges; until then `local.md` keeps their `domains:` so they're unblocked
      (the prompt warns-and-skips the not-yet-in-taxonomy value).

## STEP 7 — Confirm
Run `bash scripts/status.sh` again and report the green state (hooks wired, language +
domains set, memory runtime status). Re-running `/onboardSumela` later is safe.
</execution_workflow>

<output_contract>
On completion, report concisely (in the developer's interaction language): what was wired
(hooks), what was set (`interaction_language`, `domains`), whether the memory runtime was
set up or skipped, and — if a new domain was requested — whether it was applied (solo) or
queued via /evolve (team). Do NOT print the full Context Manifest here unless asked.
</output_contract>

