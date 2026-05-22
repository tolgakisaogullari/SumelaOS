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
- **Word limits:** `<200 words` for frequently-loaded skills, `<500 words` for others.
- **Keywords:** Embed error messages, symptoms, tool names for discoverability.
- **Cross-references:** Use skill name only — `REQUIRED SUB-SKILL: skill-name`. Never use `@` syntax (force-loads files, burns context).
- **Code examples:** ONE excellent, complete, runnable example. Never multi-language.
- **Flowcharts:** ONLY for non-obvious decision points. Never for linear steps.
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
- If skill frontmatter `description:` changed → update `.openskills/SKILL_REGISTRY.md`.
- Verify registry `<description>` is byte-identical to skill frontmatter.
- Perform this check for ALL touched skills before proceeding.
</execution_workflow>
