---
name: gap-sweep-reference
description: "The four diff-derived queries the orchestrator runs after merging lane reports, to catch defects a lane-partitioned panel structurally cannot own. Loaded at Step 6b. Private to its parent skill."
---

<why_not_introspection>
The obvious version — "ask yourself what the lanes missed" — is worthless here. You have just
verified and merged these findings; you hold the lanes' framing and you have been converging.
Open-ended self-questioning by that context yields nothing, or an invention the plausibility
rule waves through and the rejection rule then makes hard to remove.

So none of the queries below ask you to think. Each one starts from something the DIFF
states, runs a search, and reports a hit count — the same mechanism as the lanes' coverage
line and Step 2's printed `--numstat`. Print every query with its result. **No hits is a
result, not a finding.**
</why_not_introspection>

<queries>
1. **Added field / option / key that nothing reads.** List every field, config key, option,
   enum member, or event name this diff ADDS. Grep each one across the repo. Zero hits
   outside its own definition means a live code path is gated on something nothing populates
   or nothing consumes — the feature silently does nothing. Report at the READ site, not the
   definition; this class is routinely Critical and no single lane owns it, because the
   definition and the would-be reader sit in different lanes' territory.

2. **Removed guard whose invariant nobody re-established.** The diff's `-` lines are a finite,
   enumerable list. For every removed check, validation, lock, early return, `try`/`catch`, or
   default value, grep for what replaced it. "Removed and not replaced" is the answer you are
   looking for; "removed because the caller now guarantees it" needs the caller cited.

3. **Added early exit and what now does not run.** Grep the diff for an added
   `return` / `raise` / `throw` / `break` / `continue` that sits mid-function. Read the code
   AFTER it in that function. Anything that used to run on that path and no longer does is the
   finding — cleanup, an unlock, a metric, a commit, an audit log.

4. **Cross-slice contract.** Only when the review ran in more than one slice: a contract
   changed in slice A whose consumer lives in slice B was reviewed by two panels that never
   saw each other. List the public signatures, schemas, and event shapes changed in each
   slice, and grep for consumers in the others.
</queries>

<output>
Add a `### Gap sweep` section to the merged report: one line per query with the search run
and its hit count, then any findings it produced (which go through Step 6a verification like
every other finding — the sweep gets no exemption from the evidence line).
</output>

