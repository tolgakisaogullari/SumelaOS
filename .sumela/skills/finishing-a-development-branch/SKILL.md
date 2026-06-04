---
name: finishing-a-development-branch
description: "Use when implementation is complete and all code review is approved - to commit staged changes, integrate the branch, and update the Second Brain."
---

<execution_workflow>
Execute these steps strictly in sequence. DO NOT announce the skill.

1. PRE-FLIGHT TEST & SECURITY CHECK (ADAPTIVE):
   - Run the project's test suite (e.g., `npm test`, `pytest`, `cargo test`) to ensure NO existing tests are broken (Regression Check).
   - If TDD Mode was Enabled: Verify all newly written tests pass.
   - If TDD Mode was Skipped: Verify that the project successfully builds/compiles, AND ensure any required security tests (from `secure-coding-standard`) pass successfully.
   - If ANY required test or build FAILS: Show failures to the user and STOP. Do not proceed to Step 2.
   - If tests/build PASS: Proceed to Step 2.

2. MANDATORY COMMIT (THE CHECKPOINT):
   - Run `git status` to check for uncommitted/staged changes.
   - CRITICAL REVIEW GATE: You MUST ensure that the `requesting-code-review` skill was executed and explicitly approved before proceeding. "Inline execution", "I applied secure coding standards myself", or "Tests passed" are NOT valid excuses. If the `requesting-code-review` skill was NOT formally executed, you MUST STOP this workflow immediately and run `requesting-code-review`. Do not commit until the review is fully resolved.
   - CRITICAL REMINDER: If this skill was invoked AFTER review feedback was already received and applied inline, still verify that `requesting-code-review` was formally dispatched earlier in the session. Inline review execution (subagent dispatched directly without going through the `requesting-code-review` workflow) does NOT satisfy the review gate. If formal review was skipped, STOP and run `requesting-code-review` before proceeding.
   - Commit the approved STAGED changes using a descriptive, conventional commit message (e.g., `git commit -m "feat: implement [feature] based on plan"`). If critical security mitigations were applied, mention them briefly in the commit body.
   - NEVER merge or push without committing the approved work first.

3. DETERMINE BASE:
   - Identify base branch silently (`git merge-base HEAD main` or `git merge-base HEAD master`).

4. PRESENT OPTIONS:
   - PRE-FLIGHT: Before presenting options, check if the current feature branch is already merged into base (e.g., via fast-forward performed outside this skill). Run `git merge-base --is-ancestor <current-feature-branch> <base-branch>` silently. If it returns true (0), the branch is already merged. In this case, SKIP Options 1-4 selection and proceed directly to Step 7 (Memory Persistence). Do NOT ask the user to choose; the merge is already a fact.
   Present EXACTLY these 4 options to the user. Do not add any explanations or conversational filler:
   "Implementation, tests, and security reviews complete. Changes are committed. What would you like to do?
   1. Merge back to <base-branch> locally AND update Second Brain
   2. Push, create a Pull Request AND update Second Brain
   3. Keep the branch as-is (I'll handle it later)
   4. Discard this work"
   Wait for user selection.

5. EXECUTE CHOICE:
   - Dirty worktree guard (before Options 1, 2, or 4): run `git status --short`. If unrelated dirty files are present, STOP and ask the user whether to stash them. If stashing is approved, use a descriptive stash name and later report: stash name/message, captured files, why it was needed, and whether it was reapplied or dropped.
   - Option 1 (Merge): `git checkout <base>`, `git pull`, `git merge <current-feature-branch>`, run tests again on merged result. If pass, `git branch -d <current-feature-branch>`. Proceed to Step 6.
   - Option 2 (PR): Push branch (`git push -u origin <branch>`). Create PR using the GitHub connector/IDE tool when available, or `gh pr create` otherwise. The PR body MUST include Summary, Security Notes, and Test Plan sections. Bash-compatible fallback:
     ```bash
     gh pr create --title "<conventional-prefix>: <feature summary>" --body "$(cat <<'EOF'
     ## Summary
     - <2-3 bullets describing what changed and why>

     ## Security Notes
     - <list any secure-coding-standard mitigations applied; write "None applicable." if not relevant>

     ## Test Plan
     - [ ] <verification steps the reviewer should run>
     EOF
     )"
     ```
     PowerShell-compatible fallback: create the same body in a temporary markdown file, then run `gh pr create --title "<conventional-prefix>: <feature summary>" --body-file <temp-file>`.
     Do NOT cleanup worktree.
   - Option 3 (Keep): Do nothing. Report "Worktree preserved." Do NOT cleanup worktree.
   - Option 4 (Discard): Show the user this exact warning before deleting anything:
     ```
     This will permanently delete:
     - Branch: <branch-name>
     - Commits: <list of commit hashes + first lines>
     - Worktree at: <worktree-path>
     Type 'discard' to confirm.
     ```
     Require them to type EXACTLY "discard" to confirm. Any other input aborts. If confirmed: checkout base, `git branch -D <current-feature-branch>`. Proceed to Step 6.

6. WORKTREE CLEANUP:
   - ONLY for Options 1 and 4: Identify the target worktree with `git worktree list`. Verify the resolved absolute path belongs to the current feature branch and is inside the expected repository/worktree parent. If uncertain, STOP and ask the user. Then remove it (`git worktree remove <path>`) and report the removed path.

7. MEMORY PERSISTENCE (SECOND BRAIN - CODE-COMMIT INGEST CHECKLIST):
   - CRITICAL SKILL LOAD: Before proceeding with the update, you MUST explicitly ensure the `using-second-brain` skill is loaded in your context. If you haven't read it in this session, read `.sumela/skills/using-second-brain/SKILL.md` now. Then read `docs/second-brain/wiki/_SCHEMA.md` (it is NOT pre-loaded at session start; the agent loads it automatically here, before any wiki write, without waiting for user input).
   - Execute this 8-item CODE-COMMIT INGEST checklist in order. Skipping any applicable item is a violation:
     1. **Core: `active-project-context.md`** - update current project/sprint snapshot; reflect new state, remove completed items.
     2. **Overlay: domain/entity page** - if the project has `domain-entities.md` (or equivalent) and new domain entities/value objects were introduced, update it following `_SCHEMA.md` and the existing page structure.
     3. **Overlay: API/interface registry** - if the project has `api-registry.md` (or equivalent) and APIs, public interfaces, CLIs, events, or contracts changed, update it following `_SCHEMA.md` and the existing page structure.
     4. **Core: `architecture-decisions.md`** - if any architectural decisions were made (new pattern, library swap, layer change), add a new AD entry following `_SCHEMA.md` and the existing page structure.
     5. **Core: `tech-debt-and-known-issues.md`** - add TD entries for deferred work, mark resolved ones using the page's existing convention.
     6. **Overlay: history/archive page** - if this commit closes a sprint, milestone, or release and the project has `wiki/archive/sprint-history.md` (or equivalent), add a compact row following `_SCHEMA.md` and the existing table structure. Do NOT hardcode project-specific columns; copy the page's established format.
     7. **Core: `_LOG.md`** - append a `code-commit` entry in parse-friendly format with feature summary and commit hash. Format is enforced by `_SCHEMA.md`.
     8. **Core: `_SEARCH_INDEX.md`** - update rows for any wiki pages modified or created in steps 1-6. Add new rows for new pages, update Key Terms/Tags for modified pages. Format is defined in `_SCHEMA.md`.
   - **SESSION SUMMARY (chat_history) — MANDATORY, in addition to items 1-8.** Items 1-8 record durable FACTS into the curated wiki (ADRs, registries, `_LOG`); they do NOT capture the session's conversational narrative. So ALSO write this session's **session summary** and ingest it into Qdrant `chat_history`, following `using-second-brain` `<session_summary_protocol>` (load `using-second-brain` if not already). This guarantees EVERY finished task leaves a "who did what, decided what (+ rationale), produced which spec/plan" record — even when no `context-handoff` fired this session. Stamp `developer` (`git config user.name`), `domains` (`.sumela/local.md`), and `spec_artifact`/`plan_artifact` if this task produced/used them. Be substantive, not lip-service.
   - IF you create a completely NEW concept page during this step, you MUST link it in `_INDEX.md`.
   - SILENT LINT (final step - do not block on findings):
     - Scan wiki/ for broken `[[wikilinks]]` (target file missing).
     - Scan for orphan pages (zero inbound links, excluding special files).
     - Report issues IF ANY; stay silent if clean. Do NOT block branch completion on lint issues - only warn.

8. DEPLOYMENT PROMPT (OPTIONAL - ALWAYS ASK):
   - After the Second Brain update is complete, present this question to the user in the configured interaction language (English reference):
     "Branch closed and the Second Brain is updated. Want to ship these changes to production? (Yes -> I'll start the `shipping-and-launch` steps / No -> we finish here)"
   - If YES: Invoke the `shipping-and-launch` skill immediately.
   - If NO: Proceed directly to Step 9 without invoking any other skill. Do not ask again.
   - IMPORTANT: This is ALWAYS asked - even for small tasks. The user decides; the agent never assumes.

9. FINAL REPORTING (MANDATORY):
   - Explicitly inform the user, in the configured interaction language, that the entire workflow is complete.
   - You MUST clearly state that the Second Brain (`active-project-context.md` and `_LOG.md`) has been successfully updated with the latest context. (e.g., "Done — the code was committed successfully and the Second Brain memory is updated.")
</execution_workflow>
