---
name: writing-skills
description: "Use when creating new skills, editing existing skills, or verifying skills work before deployment."
---

<execution_workflow>
Execute these steps strictly in order when creating or editing any skill document.

## THE IRON LAW
```
NO SKILL WITHOUT A FAILING TEST FIRST
```
Applies to new skills AND edits. No exceptions — not for "simple additions", not for "documentation updates".

---

## Skill Types
| Type | Description | Example |
|---|---|---|
| **Technique** | Concrete steps to follow | `condition-based-waiting`, `root-cause-tracing` |
| **Pattern** | Mental model for thinking about problems | `defense-in-depth` |
| **Reference** | API docs, syntax guides, tool docs | heavily-referenced configs |
| **Orchestration** | Dispatches subagents / gates a multi-step workflow | `requesting-code-review`, `subagent-driven-development` |

---

## 1. RED PHASE — Write Failing Test (Baseline)
- DO NOT write the skill first.
- Run a pressure scenario with a subagent WITHOUT the skill.
- Document exact failures, rationalizations, and choices the agent made verbatim.

---

## 2. GREEN PHASE — Write Minimal Skill

### SKILL.md Structure
- **Frontmatter:** exactly two fields (`name`, `description`), max 1024 chars total.
  - `name`: letters/numbers/hyphens only, verb-first active voice (e.g., `creating-skills`).
  - `description`: "Use when..." — ONLY triggering conditions and symptoms. NEVER summarize the workflow.
  - **Why this matters (CSO rule):** If the description summarizes the workflow, agents follow the description instead of reading the full skill. The skill body gets skipped.
- **Length:** keep the SKILL.md body **under 500 LINES**, per Anthropic's own skill-authoring guidance. Not words — an earlier version of this rule said "<200 words for frequently-loaded skills, <500 for others". That is a different unit and a much tighter one: at this repo's median of ~13 words per line, 500 lines is roughly 6,600 words, so the old cap was about **13x** stricter, and its 200-word tier about **33x**. Under the word count 19 of 22 skills looked over budget; under the real measure, one does.
  - **The separate, stricter budget for frequently-loaded skills is GONE.** The official rule is flat: a skill loaded every session gets the same 500 lines as one loaded twice a year. That is a real relaxation, recorded here rather than absorbed into "a different unit".
  - Checked by `tests/test_skill_structure.py` **in the SumelaOS repo**. That file is not synced into consumer projects by `scripts/update.sh`, so in an upgraded install this is a rule you apply by hand, not a gate — do not treat it as machine-checked there.
  - Chasing the wrong number is what produced two rule violations in a single session: common-path content shuffled into siblings so a counter would drop, then a re-baseline justified with "only the measurement changed" when the file had grown. A metric that measures the wrong thing pushes toward gaming it.
- **Progressive disclosure:** over 500 lines, move CONDITIONAL sections — ones only a branch the common path does not take needs — into sibling files. Moving common-path content out relocates tokens instead of removing them and costs an extra read.
- **References must be ONE level deep from SKILL.md.** Claude may preview a file with `head -100` instead of reading it whole when it arrives there through another referenced file, so a rule buried two levels down can silently not apply. Name every sibling directly in SKILL.md.
- **A reference file over 100 lines needs a `## Contents` list**, so a partial read still shows the file's full scope.
- **Caching does not change this.** Cached content still occupies the context window and still counts as input tokens (total = cache_read + cache_creation + input); caching makes a re-read cheaper, not smaller.
- **Keywords:** Embed error messages, symptoms, tool names for discoverability.
- **Cross-references:** Use skill name only — `REQUIRED SUB-SKILL: skill-name`. Never use `@` syntax (force-loads files, burns context).
- **Code examples:** ONE excellent, complete, runnable example. Never multi-language.
- **Flowcharts:** ONLY for non-obvious decision points. Never for linear steps. Conventions (shapes, labels, edge semantics) live in `writing-skills/graphviz-conventions.dot`, itself written in the DSL it documents.
- **Persuasion:** Apply linguistic patterns from `persuasion-principles.md` when writing directives and discipline-enforcing rules.

### Description Field — Critical Rules
```yaml
# BAD: summarizes workflow — agent follows this instead of reading skill
description: Use when creating skills — run baseline, write SKILL.md, test with subagent

# GOOD: triggering conditions only
description: Use when creating new skills, editing existing skills, or verifying skills work before deployment
```

---

## 3. REFACTOR PHASE — Close Loopholes
- Run the exact same pressure scenario WITH the new skill.
- If agent finds new rationalizations, add explicit counters to the skill.
- Re-test until bulletproof. Do NOT deploy untested skills.

---

## Skill Creation Checklist
**Use TodoWrite to create a todo for each item.**

**RED:**
- [ ] Pressure scenario run WITHOUT skill — baseline documented verbatim

**GREEN:**
- [ ] `name` uses letters/numbers/hyphens only
- [ ] `description` starts with "Use when..." — no workflow summary
- [ ] Description under 500 chars, third person
- [ ] Word count within target (<200 or <500)
- [ ] Keywords for discoverability throughout
- [ ] `persuasion-principles.md` patterns applied to directives
- [ ] One excellent code example (not multi-language)
- [ ] Cross-references use skill name only (no `@` links)
- [ ] Pressure scenario run WITH skill — agent complies

**REFACTOR:**
- [ ] New rationalizations found and explicitly forbidden
- [ ] Rationalization table built from test iterations
- [ ] Re-tested until bulletproof

---

## Anti-Patterns
| Anti-Pattern | Why Bad |
|---|---|
| Narrative: "In session 2025-10-03, we found..." | Too specific, not reusable |
| Multi-language examples (js + py + go) | Mediocre quality, maintenance burden |
| Description summarizes workflow | Agent follows description, skips skill body |
| `@path/to/SKILL.md` cross-references | Force-loads files, burns context |
| Generic flowchart labels (step1, helper2) | Labels must have semantic meaning |

## Portability & Custom Architecture Guard
When auditing or editing skills that are part of the custom portable
Superpowers-derived architecture:
- Preserve the Second Brain integration (wiki, ingest, Qdrant, Graphify).
- Protect project-agnostic core / project overlay split.
- Keep token-cost optimizations (absorbed/condensed workflows).
- Do not treat local changes as temporary deviations from upstream
  `obra/superpowers`; they are first-class system features.
Any skill change must improve this structure without degrading behavior.

## Registry Parity Check (Post-Edit)
After editing any skill, run a retrospective parity check:
- If skill frontmatter `description:` changed → update `.sumela/SKILL_REGISTRY.md`.
- Verify registry `<description>` is byte-identical to skill frontmatter.
- Perform this check for ALL touched skills before proceeding.
</execution_workflow>
