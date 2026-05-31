---
name: persuasion-principles
description: MANDATORY reference for applying linguistic persuasion patterns when designing or editing skills. Maximizes agent compliance and eliminates rationalization.
---

<execution_workflow>
Apply these linguistic patterns strictly when writing or modifying skills. DO NOT include academic justifications or ethical philosophy in the skill documents themselves.

**Research foundation:** Meincke et al. (2025), N=28,000 conversations — persuasion techniques more than doubled compliance rates (33% → 72%). Authority, commitment, and scarcity were most effective.

---

## The Seven Principles

### 1. Authority (Discipline & Safety Skills)
- Use absolute imperatives: "YOU MUST", "NEVER", "ALWAYS"
- Non-negotiable framing: "No exceptions."
- Eliminates decision fatigue and rationalization

```markdown
✅ Write code before test? Delete it. Start over. No exceptions.
❌ Consider writing tests first when feasible.
```

### 2. Commitment (Multi-step Workflows)
- Force explicit declarations: "You MUST announce: 'I am using [Skill]'"
- Sequential urgency: "IMMEDIATELY after X, do Y before proceeding."
- Mandate tracking: `TodoWrite` for step-by-step accountability

### 3. Scarcity (Immediate Action Requirements)
- Time-bound framing: "Before proceeding", "IMMEDIATELY after X"
- Prevents "I'll do it later" rationalizations

### 4. Social Proof (Establishing Norms)
- Universal patterns: "Every time", "Always"
- Failure norms: "Skipping X = failure. Every time."

### 5. Unity (Collaborative Patterns)
- Shared identity language: "our codebase", "we're colleagues"
- Use for collaborative workflows, NOT discipline enforcement

### 6. Reciprocity
- Use SPARINGLY — can feel manipulative
- Almost always less effective than the above four

### 7. Liking
- **NEVER use for compliance enforcement**
- Creates sycophancy, degrades technical honesty

---

## Principle Combinations by Skill Type

| Skill Type | Use | Avoid |
|---|---|---|
| Discipline-enforcing (TDD, verification) | Authority + Commitment + Social Proof | Liking, Reciprocity |
| Technique / guidance | Moderate Authority + Unity | Heavy authority |
| Collaborative workflow | Unity + Commitment | Authority, Liking |
| Reference / docs | Clarity only — no persuasion | All persuasion |

---

## Implementation Checklist (Apply When Writing Skill Directives)
- Does the rule use bright-line triggers? ("When X, do Y" vs "Generally do Y")
- Are loopholes explicitly closed with specific counters?
- Is the language devoid of emotional manipulation?
- Is "Liking" pattern absent?
- Is authority language used ONLY for discipline-enforcing rules?
</execution_workflow>
