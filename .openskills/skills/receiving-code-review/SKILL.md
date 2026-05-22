---
name: receiving-code-review
description: "Use when receiving code review feedback from a subagent reviewer or human partner - before implementing any suggested changes."
---

<severity_sections>
Map every review finding to the severity model used by `requesting-code-review`:

| Section | Required Action |
|---------|-----------------|
| Critical | Blocks commit/merge; must fix before proceeding |
| Important | Required before proceeding unless technically disproven |
| Minor | Optional; author may ignore at their discretion |
| Recommendations / FYI | Informational; no action needed unless the author chooses |

**Approval standard:** Accept feedback as complete when the change definitively improves overall code health and no Critical or Important findings remain. Do not block on style preferences or optional suggestions.
</severity_sections>

<feedback_sources>
Treat feedback source as part of the context:
- **Human partner / user:** Highest priority. If feedback conflicts with the current plan, clarify intent before changing direction.
- **Local subagent review:** Strong signal, but still verify against code, tests, architecture, and security constraints.
- **External / GitHub reviewer:** Evaluate as a suggestion unless repository policy or the user makes it mandatory. If it conflicts with an earlier user decision or documented architecture, stop and ask the user.
</feedback_sources>

<workflow>
Execute feedback processing using these strict steps:

1. READ & CLARIFY: Read all feedback. If ANY item in a multi-item request is unclear, STOP and ask for clarification immediately. DO NOT partially implement.

2. VERIFY & SECURITY CHECK (CRITICAL): Cross-check feedback against the actual codebase. Verify whether it breaks existing functionality, backward compatibility, or prior architectural decisions. You MUST also verify requested changes against `secure-coding-standard`. If a requested change introduces a vulnerability, bypasses security layers, leaks sensitive data, or weakens logging hygiene, DO NOT implement it.

3. YAGNI CHECK: If feedback requests expanding or fixing an unused/dead feature, endpoint, option, or abstraction, propose removing the dead surface instead of implementing the fix.

4. RESPOND & IMPLEMENT (CONTEXT-AWARE EXECUTION):
   - If feedback is incorrect, breaking, insecure, or contradicts a user-approved decision: Push back using this hierarchy: technical facts and data override opinions; style guides govern style; architecture decisions govern design. State: "Disagreeing because [technical fact/reference]. Evidence: [code/test/doc]." DO NOT modify the code.
   - Never accept "I'll fix it later" for Critical or Important findings. Resolve before proceeding, or file an explicit TD entry when the user approves deferral.
   - Cannot verify? State the limitation explicitly: "Cannot verify [X] without [Y]. Should I investigate, ask, or proceed?" DO NOT proceed under uncertainty.
   - Multi-item order: clarify all unclear items first, then implement in this order: (1) blocking issues - breaks/security, (2) simple fixes - typos/imports, (3) complex fixes - refactoring/logic. Test each fix individually before moving to the next.

   SCENARIO A (Local Subagent Review / Uncommitted Changes):
   - Implement accepted items one by one. If TDD mode was enabled for this task, update/add the corresponding tests and run them.
   - Stage fixes only when the active workflow or user explicitly expects staged output. Never commit.
   - Reply factually with what changed and which files are staged or unstaged.

   SCENARIO B (Remote GitHub PR Review):
   - Implement accepted items one by one and test each.
   - Commit/push only when the active GitHub PR workflow or the user explicitly authorizes it.
   - Reply directly to inline review comments via the repository's approved API/tooling when available. Avoid top-level PR comments for inline findings.

5. FINAL VERIFICATION: Ensure required fixes are complete, verification has run or blockers are stated, and the worktree/staged state matches the active workflow before returning to `requesting-code-review`, `subagent-driven-development`, or `finishing-a-development-branch`.
</workflow>

<communication_constraints>
- BANNED BEHAVIORS: Do not use performative agreement, emotional responses, gratitude, or apologies (for example, "You're absolutely right", "Great point", "Thanks for catching that").
- DELETE-IT RULE: If you catch yourself about to write gratitude or emotional agreement, delete it and state the technical result instead.
- ACTIONS > WORDS: Do not say "I will fix this" when you can fix it. State the result.
- CORRECTING YOURSELF: If your pushback was proven wrong, state factually: "Verified. My initial understanding was wrong because [reason]. Fixing." Do not over-explain.
</communication_constraints>
