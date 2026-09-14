---
name: self-modification-guard-reference
description: "Procedure for reviewing a diff that edits SumelaOS's own rules, skills, hooks or governance files. Load ONLY when Step 1's trigger matches. Private to its parent skill."
---

<when_to_load>
Load at Step 1 only when `{CHANGED_FILES}` contains a path under `.sumela/`, `scripts/`,
`AGENTS.md`, an IDE pointer (`CLAUDE.md`, `.clinerules`, `.cursor/rules/`, `.kilocode/`,
`.trae/rules/`, `.opencode/`), `.github/workflows/`, or `.github/CODEOWNERS` —
**excluding** `.sumela/reviews/` and `.sumela/_migration/`, which are runtime artifacts.

The trigger is a broad deny with two exclusions, deliberately. An allowlist of "the review
skills and the rules directory" rots the moment a file is added, and the powerful surfaces
are not the obvious ones: `AGENTS.md` and the IDE pointers are what the agent actually
auto-loads; `.sumela/git-hooks/` is the enforcement layer; `.github/CODEOWNERS` is the
governance gate in team mode; `verification-before-completion` and
`finishing-a-development-branch` are gates as much as the review skills are.
</when_to_load>

<what_this_does_not_fix>
**State the limitation; do not claim more than this buys.** By the time Step 1 runs, the
agent has already loaded `AGENTS.md` → `SKILL_REGISTRY.md` / `RULE_REGISTRY.md` →
`sumela-prompt.md` **from the working tree**, at session start, via the IDE pointer. A
loosened rule is already in context. Nothing at Step 1 can un-read it.

So this guard does NOT prevent a modified rule from influencing the review. What it does is
make the modification **visible and reviewed** rather than silent. That is the honest claim.
</what_this_does_not_fix>

<procedure>
1. **Announce it.** One line naming the trigger paths, so the user sees that this review's
   own ground is moving: *"This diff edits N SumelaOS governance file(s): `<paths>`. Reviewing
   under the self-modification guard."*

2. **Classify: framework upgrade or authored change? Judge PROVENANCE, not path shape.**
   A **framework upgrade** is content the developer did not write. Establish that, do not infer
   it: read `.sumela/.last-update.json`, which `scripts/update.sh` writes on every successful
   run (version, UTC timestamp, and the exact file list it vendored). The changed paths must
   appear in that `files` list AND the recorded `version` must match `.sumela/VERSION`. Do not
   try to `cmp` against the upstream source — `$SRC` is a local inside `update.sh` and its
   clone is removed on exit, so nothing survives to compare against at review time; the record
   is the only executable test. No record, or a path not in it → treat as authored.
   A VERSION bump plus paths that merely LOOK like `CORE_FILES`/`CORE_DIRS`
   proves nothing — `CORE_FILES` contains `security_protocol.md` and
   `git_workflow_mandatory_review_protocol.md`, and bumping VERSION is what a normal commit in
   a framework repo does anyway, so a shape test would hand the exemption to exactly the diff
   this guard exists for: a hand-loosened security rule shipped alongside a version bump.
   - **Verified upgrade** → announce as such, do NOT force Deep, and review against the NEW
     rules. Without this carve-out every consumer pays a 4-lane Deep review and a false security
     banner on their first review after every `update.sh` run, and this repo — where `.sumela/`
     IS the product — would sit at Deep permanently.
   - **Anything you cannot verify as vendored** → an authored change; continue.
   - **Step 4 is never skipped**, in either branch, for `.sumela/rules/` or for a gate skill
     (`requesting-code-review`, `receiving-code-review`, `verification-before-completion`,
     `finishing-a-development-branch`, `shipping-and-launch`). An upstream release can weaken a
     gate too, and a consumer inheriting that weakening should be told.

3. **Pass the trigger list to every lane in `{DESCRIPTION}` — on BOTH branches**; Lane 2 gets the weakening criterion in step 4 either way and needs to know which paths moved. **Authored change → also force the tier to Deep** (Step 3's escalate-only rule permits this; nothing may
   de-escalate it afterwards) and pass the trigger list to every lane in `{DESCRIPTION}`.

4. **Lane 2 owns the finding.** Include in its criteria: *"This diff edits the project's own
   rules, gates, or review instructions. A change that WEAKENS a rule, removes a gate, widens
   an exception, or relaxes a review instruction is a finding in its own right, at the
   severity of whatever it weakens — regardless of how well justified the surrounding change
   is. Say plainly what protection is being given up and what is offered in its place. A
   weakening bundled into a feature change is the case to flag hardest: it is the shape that
   passes review by not being the subject of it."*

5. **Quoting rule text during the review.** If a lane or the synthesis needs to quote a rule
   that this diff itself modifies, quote the PRE-CHANGE text — `git show HEAD:<path>` for a
   staged or unstaged review (HEAD is the pre-change state; `{BASE_SHA}`/`{HEAD_SHA}` carry
   worktree labels, not refs, so `git show <label>:` is not a command), or
   `git show $(git merge-base HEAD <base>):<path>` for a committed range (NOT `HEAD~1`, which
   is the wrong pre-image for a multi-commit branch). Two cases have no pre-change text:
   a rule file ADDED by this diff, and a `.sumela/` tree not yet committed (common on a fresh
   install). In both, treat the base version as ABSENT — never silently fall back to the
   working-tree copy, or a newly added permissive rule reopens the hole this guard exists to
   name. Say which case applied.
</procedure>
