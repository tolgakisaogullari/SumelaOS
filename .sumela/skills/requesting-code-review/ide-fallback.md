---
name: ide-fallback-reference
description: "Degraded review protocol for requesting-code-review when the IDE exposes no subagent/Task dispatch primitive. Load ONLY when parallel lanes cannot run. Private to its parent skill."
---

<when_to_load>
Load this ONLY if the current IDE has no subagent / Task dispatch primitive, so the Step 3
lanes cannot run as isolated parallel contexts. If dispatch works, you never need this file.
</when_to_load>

<protocol>
1. NEVER claim "inline execution" is equivalent to the parallel panel. The panel's value is
   physical context isolation — a single context that reviews its own work carries the
   author's framing into the review, which is precisely what the lanes exist to break.
2. Tell the user plainly that context isolation is unavailable in this IDE.
3. Offer two options:
   - **C1 — simulate the lanes sequentially.** Run the Step 3 lanes one at a time in this
     context, each opened with a fresh *"review this as if you did not write it"* framing and
     each producing its own distinct written report before the next begins. Never merge two
     lanes into one pass.
   - **C2 — defer.** Postpone the formal panel to a subagent-capable IDE or session.
4. If C1: run Correctness & Security FIRST (it is the mandatory floor), then the remaining
   lanes in Step 3 order. Then apply the FULL Step 6 treatment unchanged — 6a inline
   verification of every Critical/Important, 6b merge and AND-gate, 6c artifact write. Step 7
   hand-off and the Step 8 re-review loop also still apply. The degraded path degrades
   ISOLATION, not rigor.
5. **Last resort only** — a trivially small diff where even sequential lanes are overkill:
   the legacy single-reviewer template `requesting-code-review/code-reviewer.md` remains
   available. Prefer the lane simulation. If you use it, state explicitly in your report that
   you took the degraded path and why, so the artifact does not read as a full panel review.
</protocol>
