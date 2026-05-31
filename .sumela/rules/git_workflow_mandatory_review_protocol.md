# GIT WORKFLOW & MANDATORY REVIEW PROTOCOL (THE GATEKEEPER)

## 🚧 ZERO UNREVIEWED COMMITS
* **Pre-Commit Requirement:** You are strictly forbidden from executing `git commit` or `git merge` without first presenting a **"Pre-Commit Review Summary"** to the user.
* **Review Content:** Before any commit, you must:
    1. Run `git diff --cached` (or equivalent) to see exactly what is being committed.
    2. Provide a bulleted list of changes and their architectural impact.
    3. Explicitly ask the user: *"I have reviewed these changes. Shall I proceed with the commit/merge?"*

## 🔄 BRANCH & WORKTREE MANAGEMENT
* **Branch Isolation:** When using `superpowers:using-git-worktrees` or creating new branches, never merge back to `main` or `master` until the feature is fully verified by the `superpowers:verification-before-completion` skill.
* **Clean History:** Avoid "WIP" (Work In Progress) commits on the main branch. Ensure all commits follow the **Conventional Commits** standard (e.g., `feat:`, `fix:`, `refactor:`).

## 🕵️ MANDATORY REVIEW SKILL (SUPERPOWERS:REQUESTING-CODE-REVIEW)
* **Skill Enforcement:** For any complex feature or refactoring, you **MUST** invoke the `superpowers:requesting-code-review` skill before finalizing the task. 
* **Self-Critique:** During the review, actively look for:
    * Violation of any of the 10 established Project Rules.
    * Unnecessary files or "debug" code left behind.
    * Potential performance regressions in ORM or frontend/mobile components.

## 🛠️ SUPERPOWERS INTEGRATION
* **Execution Phase:** During `superpowers:executing-plans`, if a step involves a git action, pause and report the status of the `uncommitted changes`.
* **Merge Gate:** Before a merge command, verify that the `CorrelationId` and `Logging` standards (from Rule 10) are implemented in the new code.

# Windows CMD Worktree Path Navigation

On Windows cmd.exe, when navigating to git worktree paths, use
`cd e:\path\to\worktree` (without /d flag, without quotes) instead of
`cd /d "e:\path\to\worktree"`. The `/d` flag combined with quoted paths
containing `.worktrees` segments causes "The filename, directory name, or
volume label syntax is incorrect" errors. For subsequent commands in the
same line, use `&&` chaining: `cd e:\path && git add .`

# Windows CMD: git commit with Special Characters

## Rule (Agent CLI Workflow)

`git commit -m` fails on Windows CMD when the message contains em-dashes (`—`),
non-ASCII characters, or parentheses — the shell misparses them as file arguments,
producing `pathspec '...' did not match any file(s)`.

**Agent solution — temp file pattern:**

1. Use the `Write` tool to create `.commit_msg.txt` with the full commit message.
2. Run: `git commit -F .commit_msg.txt`
3. Run: `del .commit_msg.txt`

```
Write → .commit_msg.txt
git commit -F .commit_msg.txt
del .commit_msg.txt
```

**Why not `git commit -m`?** CMD cannot reliably escape em-dashes or multi-line
strings. The temp-file approach is the only safe path for agent CLI commits with
rich messages. This rule targets **agent CLI** commits exclusively — human
developers can use IDE source control.

# Stash Lifecycle Transparency

When stashing dirty work during branch finish/merge flows:

1. **Immediate report:** After `git stash`, state:
   - Stash name/message (e.g., `stash@{0}: WIP on feature-xyz`)
   - Files captured in the stash
   - Why the stash was necessary (uncommitted changes blocking merge/checkout)
   - Planned cleanup point (before final commit, before handoff, etc.)

2. **Pre-completion inspect:** Before marking the task complete:
   - Run `git stash list` to show current stash stack.
   - Run `git stash show -p stash@{N}` to inspect contents.
   - Apply only still-relevant hunks/files.
   - Drop obsolete stash entries after explaining what was kept or discarded.

3. **Never leave orphaned stashes:** If a stash is no longer needed, drop it and confirm.
