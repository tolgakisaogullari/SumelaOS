---
name: review-report-reference
description: "CANONICAL format of the .sumela/reviews/ panel report — the contract shared by the skill that writes it and the three that read it. Loaded at Step 6c and by any gate checking a review. Private to its parent skill."
---

<why_canonical>
Four places touch this file: Step 6c writes it, Step 1 reads it back for `{PRIOR_ROUNDS}`,
`receiving-code-review` writes the outcome ledger into it, and the finish/ship gates validate
it. Restating the field list in any of them is how a writer and a reader come to disagree about
what a passing review looks like. **Defined here, once.**
</why_canonical>

<location>
Path: `.sumela/reviews/<UTC-ISO>-<branch-slug>.md`, in the **MAIN CHECKOUT** —
`dirname "$(git rev-parse --git-common-dir)"`. Not the current worktree: the directory is
gitignored, so `git worktree remove` deletes it along with the evidence the ship gate needs.

**Before writing, run `git check-ignore -q .sumela/reviews/`.** Not ignored → do NOT write: say
so and have the user add it (`update.sh`'s gitignore reconcile is consent-gated and may have
been declined). These reports quote the code they flag, secrets included; into a tracked
directory that is a committed leak.

Keep the newest 20 per branch; **Step 6c prunes** as it writes, or the retained set grows into the population check 1 must choose from.
</location>

<frontmatter>
```
---
reviewed_state: tree:<sha>       # `git write-tree` — CONTENT, not a diff stream.
                                 # Unstaged work: the tree of `git stash create`
                                 # (never mutate the real index)
branch: <git rev-parse --abbrev-ref HEAD>
reviewed_at: <ISO8601 UTC>
tier: Focused | Standard | Deep
panel: <lane names>
slices: <N>
round: <N>
verdict: Yes | No | With fixes
user_decision: none | proceed     # set by requesting-code-review Step 8
findings: critical=<n> important=<n> minor=<n> unproven=<n> rejected=<n>
confidence: high=<n> low=<n>      # low = the findings labelled (unproven)
outcomes: <id>=<fixed|skipped|no_change_needed> ...   # filled by receiving-code-review
---
```

`reviewed_state` hashes a TREE, deliberately, not a diff. A literal marker like `worktree`
matches itself forever, so a gate on it always passes; a *diff* hash fails the other way —
`git diff --staged` is empty after the commit, so a pre-commit report could never match at ship
time and every ship would demand a redundant panel. A tree hash survives that transition:
`git write-tree` from the index equals `HEAD^{tree}` of the commit it becomes.

**Which report:** always the NEWEST for this branch — never scan the retained set for one that
passes. A later round can LOWER a verdict, and both rounds may share a `reviewed_state`.

`confidence.low` counts the `(unproven)` findings. They are NOT optional — an unproven finding
keeps its severity and blocks (`receiving-code-review` → `<severity_model>`); the count just
shows how much of the verdict rests on unsettled evidence.
</frontmatter>

<body>
Sections in order: `Issues` (Critical → Important → Minor, each with its `<id>`), `Conflicts`,
`Gap sweep`, `Rejected on verification`, `Unproven`, `Strengths` (max 5), `Assessment`.

Finding ids are `r<round>.F<n>`, assigned in Step 6b **after** dedupe and aggregation — never by
a lane (slices collide), never severity-coded (dedupe raises severity and orphans the last
round's ledger).
</body>

<how_a_gate_checks_it>
1. The NEWEST report for this branch (`branch:` matches `git rev-parse --abbrev-ref HEAD`) —
   that one, not any that passes. **None → the review was not formally executed.** "Inline
   execution", "I applied secure coding standards myself" and "tests passed" are not substitutes.
2. Its `reviewed_state:` matches what is about to be committed or shipped — recompute the tree
   hash (`git write-tree` pre-commit, `git rev-parse HEAD^{tree}` after) and compare. A mismatch
   means the tree moved after the review: the report is STALE.
3. **STALE → ALWAYS re-run.** No exception. `proceed` does not apply: it was decided about a
   specific reviewed state. A proceed that survived the code moving underneath it would make
   `reviewed_state` decorative, and being non-forgeable by drift is why the field exists.
4. Not stale, but `verdict:` is not `Yes` → re-run, **unless** `user_decision: proceed` is
   recorded — the user's explicit Step 8 choice to ship with outstanding findings. Then do not
   re-block: name what remains and continue. **`proceed` waives the verdict, never the hash.**
5. `outcomes:` must account for every finding id in the body; an unaccounted id means
   `receiving-code-review` did not finish.
</how_a_gate_checks_it>
