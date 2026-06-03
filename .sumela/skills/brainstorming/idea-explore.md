---
name: idea-explore
description: "Use when an idea is raw or unclear — before any architectural decisions or code are written."
---

<HARD-GATE>
DO NOT jump to solutions, technical options, or architecture until Phase 2 is complete and the user has confirmed a direction. Problem clarity precedes solution design.
</HARD-GATE>

<philosophy>
- Simplicity is the ultimate sophistication. Push toward the simplest version that still solves the real problem.
- Start with the user experience, work backwards to the technology.
- Say no to 1,000 things. Focus beats breadth.
- Challenge every assumption. "How it's usually done" is not a reason.
- The "Not Doing" list is arguably the most valuable output. Focus is about saying no to good ideas.
</philosophy>

<workflow>
Guide the user through three phases. This is a conversation, not a template — adapt based on their responses.

## Phase 1: Understand & Expand (Divergent)

**Goal:** Take the raw idea and open it up before narrowing down.

1. RESTATE AS "HOW MIGHT WE":
   Reformulate the user's request as a crisp problem statement:
   "How Might We [solve X] for [who] so that [outcome]?"
   This forces clarity on what's actually being solved, not just what's being built.

2. ASK 3-5 SHARPENING QUESTIONS (one at a time):
   - Who is this for, specifically? (not "users" — a concrete person or role)
   - What does success look like in 3 months?
   - What are the real constraints? (time, tech, team size, dependencies)
   - What has been tried before, and why did it fall short?
   - Why does this need to be solved now?

   Do NOT proceed to idea generation until you know who this is for and what success looks like.

3. GENERATE 5-8 VARIATIONS using these lenses (pick the most relevant, don't force all):
   - **Inversion:** "What if we did the exact opposite?"
   - **Constraint removal:** "What if time/budget/tech weren't factors?"
   - **Simplification:** "What's the version that's 10x simpler?"
   - **Audience shift:** "What if this were designed for a completely different user?"
   - **Combination:** "What if we merged this with an adjacent idea already in the system?"
   - **10x scale:** "What would this look like if 100x more people used it?"
   - **Expert lens:** "What would a domain expert find obvious that we're missing?"

   **If working inside a codebase:** Use `Glob`, `Grep`, and `Read` to scan for relevant context — existing architecture, patterns, prior art. Ground variations in what actually exists.

   Push beyond what the user initially asked for. Don't just produce better versions of their request.

## Phase 2: Evaluate & Converge

After the user reacts (which variations resonate, pushback, additions), shift to convergent mode:

1. CLUSTER into 2-3 distinct directions. Each must feel meaningfully different, not just variations on a theme.

2. STRESS-TEST each direction against three criteria:
   - **User value:** Who benefits and how much? Is this a painkiller or a vitamin?
   - **Feasibility:** What is the technical and resource cost? What's the hardest part?
   - **Differentiation:** What makes this genuinely different from what already exists?

3. SURFACE HIDDEN ASSUMPTIONS — for each direction, explicitly name:
   - What you're betting is true (but haven't validated yet)
   - What could kill this idea if the assumption is wrong
   - What you're consciously choosing to ignore (and why that's acceptable for now)

   **Be honest, not supportive.** If a direction is weak, say so with specificity. Push back on complexity, question real value. A good thinking partner is not a yes-machine.

## Phase 3: Sharpen & Output

Produce a markdown one-pager artifact and ask the user if they'd like to save it:

```markdown
# [Idea Name]

## Problem Statement
[One-sentence "How Might We" framing]

## Recommended Direction
[The chosen direction and why — 2-3 paragraphs max]

## Key Assumptions to Validate
- [ ] [Assumption 1] — how to test: [method]
- [ ] [Assumption 2] — how to test: [method]
- [ ] [Assumption 3] — how to test: [method]

## MVP Scope
[The minimum version that tests the core assumption. Be explicit about what's in.]

## Not Doing (and Why)
- [Feature/approach 1] — [reason: out of scope, wrong user, later phase, etc.]
- [Feature/approach 2] — [reason]
- [Feature/approach 3] — [reason]

## Open Questions
- [Question that must be answered before building begins]
```

If the user confirms, save to `docs/ideas/[idea-name].md` (or a path of their choosing).

## Handoff

Once the direction is confirmed and the one-pager is approved, present this choice:

"The idea is clear. What's the next step?
1. **Move to architecture design:** invoke the `brainstorming` skill to lay out the technical options and the spec.
2. **Stop here:** stay at this stage for now and continue later."

If Option 1: invoke `brainstorming` immediately. Pass the confirmed "How Might We" statement and Recommended Direction as context.
</workflow>

<anti_patterns>
- Generating 20+ shallow variations instead of 5-8 considered ones
- Skipping "who is this for" and jumping to solutions
- Yes-machining weak ideas instead of pushing back with specificity
- Producing a plan without surfacing hidden assumptions
- Omitting the "Not Doing" list — this is non-negotiable
- Jumping straight to Phase 3 without completing Phases 1 and 2
- Ignoring existing codebase constraints when ideating inside a project
</anti_patterns>

<verification>
Before handing off to `brainstorming`, confirm:
- [ ] A clear "How Might We" problem statement exists
- [ ] Target user and success criteria are explicitly defined
- [ ] Multiple directions were explored, not just the first idea
- [ ] Hidden assumptions are listed with validation strategies
- [ ] A "Not Doing" list makes trade-offs explicit
- [ ] The user confirmed the final direction
</verification>
