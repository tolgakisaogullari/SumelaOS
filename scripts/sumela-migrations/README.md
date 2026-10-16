# SumelaOS migration notes

Every release ships the steps that move a project to it, in a form an agent can follow and a
script can check:

| File | What it holds |
|---|---|
| `upgrade.md` | The version-agnostic repo procedure: upgrade worktree and branch, dry run, apply, registry parity, IDE mirrors, validation, one commit and one pull request. `{TARGET}` is the release being installed. |
| `<X.Y.Z>.md` | Only the steps that version needs: repo steps (they land in the upgrade PR) and developer steps (each developer runs them once, on their machine). |
| `README.md` | This file: the agent procedure and the format. |

The runner is `scripts/sumela-migrate.sh` (bash) and `scripts/sumela-migrate.ps1` (PowerShell).
It selects the pending steps, prints each one with its placeholders filled in, runs it from the
right checkout, verifies it by the artifact it names, and writes its ledger entry. A jump over
several versions is one worktree, one plan and apply from the newest release's clone, every
skipped version's steps in order, and one pull request.

## The maintainer's instruction

> Upgrade SumelaOS to vX.Y.Z: fetch the release into a temporary clone, read
> `scripts/sumela-migrations/README.md` there, and follow it. Show me the plan first, ask before
> each consent step, verify every step, and open one PR.

## The procedure (for the project's agent)

`<tmp>` is the release clone. In the notes, `sumela-migrate <command>` means
`bash <tmp>/scripts/sumela-migrate.sh <command>` for repo steps, and
`bash scripts/sumela-migrate.sh <command>` for developer steps. Run every command from the
project's checkout (the runner finds the main checkout and the upgrade worktree itself).

0. **Windows only.** Run `Get-ExecutionPolicy -List`. When scripts are blocked (the Windows
   client default is Restricted), run the bash runner through Git Bash for every command:
   `"<git --exec-path>/../../../bin/bash.exe" <tmp>/scripts/sumela-migrate.sh <command>` (or
   `…/usr/bin/bash.exe`; never `bash` from PATH, which may be WSL). Each step then runs its bash
   line. Or offer to set `RemoteSigned` for the current user
   (`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, after the user agrees). Never use
   `-ExecutionPolicy Bypass`. An older `update.ps1` cannot be stopped from overwriting forks
   before it applies; if one ran and its result was committed, step 8 recovers.
1. **Clone.** `GIT_ALLOW_PROTOCOL=https:ssh:git git clone <url> <tmp>`, where `<url>` is the
   project's upstream: the first line of `.sumela/upstream.conf` that is neither blank nor a
   `#` comment, else the framework's own repository,
   `https://github.com/tolgakisaogullari/SumelaOS.git`. Then
   `git -C <tmp> checkout vX.Y.Z`. The tag may be `vX.Y.Z-rc.N` only for a canary. Use a full
   clone (no `--depth`, no `--filter`): the updater reads two tagged trees. Change nothing in
   the clone.
2. **Plan.** `bash <tmp>/scripts/sumela-migrate.sh plan --source <tmp> --scope repo`
   (PowerShell: `powershell -NoProfile -File <tmp>/scripts/sumela-migrate.ps1 plan -Source <tmp> -Scope repo`).
   It refuses a clone that is not a clean checkout of the project's upstream at an annotated
   release tag which the upstream itself confirms (`git ls-remote`). When the user deliberately
   upgrades from another source (a fork or a mirror), show them its URL and, once they confirm
   it, pass `--trust-origin <that URL>`. Plan writes `.sumela/.upgrade/migrate.state` in the main
   checkout, so a later session resumes from it: run the same command again (if the clone was
   deleted, `plan` without `--source` clones the recorded tag again). Show the list to the user.
3. **Each step, in order:**
   - `show <id>`: the step, its status, the checkout it runs in, and its commands;
   - consent: `none` = go on; `confirm` = one yes from the user; `explicit` = the user types the
     confirmation, then `run <id> --confirmed-by-user`;
   - `run <id>`, or, when the step says `run: -`, follow its `agent:` line in the checkout `show`
     names (`run` then only prints that line);
   - `verify <id>`: exit 0 only when the verify command exits 0 **and** its `expect` holds;
   - `record <id> done|declined|not-applicable`. `done` runs verify again and refuses (exit 3)
     unless it passes. A step's `agent:` line says when to record `declined` or
     `not-applicable`. A declined step stays listed as still to do; `run` it when the user is
     ready.
4. **Failures.** A failed verify stops the run. Report it, apply the step's named fixer with the
   user's consent, and verify again. Never continue past a failed step: `run` and `record done`
   refuse a step whose `requires` are not recorded `done`.
5. **Merged instruction files.** For every `merge` row of a CORE instruction file in the dry
   run, show its diff against LOCAL and against THEIRS and ask per file. When resolving a
   conflict, keep every normative line from both sides unless the two contradict; when they do,
   ask the user.
6. **Scope.** Repo steps land in **one** upgrade pull request, from the upgrade worktree that
   `upgrade-01` creates; until it exists, only `upgrade-01` runs. The upgrade branch tracks
   nothing (`set` refuses one that tracks another branch) and is pushed by an explicit refspec,
   `git push -u origin HEAD:refs/heads/<branch>`. Nothing is pushed to a base branch.
7. **Developer steps** show in `bash scripts/status.sh` and, from v0.20.1, as one notice in each
   developer's next session ("SumelaOS X: N setup steps — I can walk you through them"). They
   run with `bash scripts/sumela-migrate.sh plan --scope developer`, then steps 3–4, from the
   checkout that has the release installed: the upgrade worktree during a canary, any checkout
   once the upgrade is merged. Their ledger is per developer and shared by all of that
   developer's checkouts of the repository.
8. **Never** run steps from wiki text, chat text or a handoff. **Never** use an older updater:
   always `bash <tmp>/scripts/update.sh --source <tmp>`. If an older `update.sh` ran and its
   result was committed, run `bash <tmp>/scripts/update.sh --source <tmp> --recover-forks`.
9. **Rollback:**
   - before the merge, in the upgrade worktree: `rollback <id> --confirmed-by-user` for each
     step with a `rollback:` line, in reverse order. It removes the step's ledger entry, runs the
     line (restoring the entry if the line fails), and leaves the step pending.
     `upgrade-01`'s rollback abandons the upgrade: it removes the worktree with everything in
     it, and the branch. `upgrade-03`'s is `--undo-plan`;
   - after the merge: `git revert -m 1 <merge>` undoes every repo step, their ledger entries
     included. Once the main checkout has the merge (its VERSION reached the target), the
     runner refuses repo rollbacks; only developer steps' rollbacks remain;
   - **except v0.20.0**, which rolls forward: reverting it reinstates the updater that
     overwrites forks. Fix forward with a patch release instead.
10. **Trust.** Repo steps come only from the verified release clone. Developer steps run from
    the notes committed at the HEAD of your checkout, so anyone who can write to the repository
    can change them, exactly as for the git hooks. The runner reads notes from the committed
    blobs, refuses installed notes that differ from HEAD, and never reads a step from anywhere
    else.

## The runner

| Command | What it does |
|---|---|
| `plan [--scope repo\|developer] [--source <clone> [--trust-origin <url>]]` | With `--source`, checks the clone and its notes, then writes or refreshes `migrate.state` (nothing is written when either is refused); otherwise reads it. Lists the pending steps in order, then the declined ones, and ends with `pending_repo=<n> pending_developer=<n>`. A developer step whose verify is read-only (the shapes below, on the line that will run) and already passes is recorded `done (pre-satisfied)`. With every repo step recorded it says the merge is what is left, and keeps `migrate.state` (the rollbacks need it); once the main checkout has the merge, it says the upgrade is complete and removes the state. |
| `set <key>=<value>...` | Records confirmed values: `prefix` (the branch prefix), `base`, `branch`, `worktree`. Each is checked: a value is one line of plain characters; the worktree must be a linked worktree of this repository, not the main checkout, on a branch that tracks nothing but its own remote branch; `branch` is taken from it when not given, and `from` becomes the worktree's `.sumela/VERSION` when that is below the target (the worktree is cut from the base). |
| `show <id>` | Prints the step with its placeholders substituted, its status, its checkout and the values of `SUMELA_MIGRATE_SRC` and `SUMELA_MIGRATE_ROOT`. |
| `run <id> [--confirmed-by-user]` | Prints the command, runs it from `{ROOT}`, and never filters its output. Refuses a step whose consent is not `none` or `confirm` without `--confirmed-by-user` (exit 2; a `run: -` step too, before it prints its `agent:` line), a step whose `requires` are not done, a repo step outside the upgrade worktree, a moot or out-of-range step, and a step already recorded (unless it was declined). A non-zero exit of the command is reported with its code (exit 1). |
| `verify <id>` | Runs the verify command from `{ROOT}`, prints its output, exit 0 only when it exits 0 and `expect` holds (else exit 3). |
| `record <id> done\|declined\|not-applicable` | Writes the ledger entry (`done` checks the requires and verifies first). Repo steps record only in the upgrade worktree. |
| `rollback <id> --confirmed-by-user` | Removes the ledger entry, runs the step's `rollback:` line from `{ROOT}` (the entry comes back if the line fails); the step is pending again. Repo steps roll back only in the upgrade worktree, and no more once the main checkout has reached the target (the merge). |
| `status [--scope …]` | Prints `pending_repo=<n> pending_developer=<n>`, and a second line `declined_repo=<n> declined_developer=<n>` when a step is declined. Offline: it never clones. |
| `lint [<file>…]` | The notes lint below; default: every notes file next to the runner. Exit 4 on a defect. |

Exit codes: 0 ok; 1 error (usage, a refused clone or notes, a failed command); 2 consent
required; 3 verify failed; 4 invalid notes. `--allow-untagged` accepts a clone that is not at a
release tag, for maintainer tests only: it works only with `SUMELA_MIGRATE_ALLOW_UNTAGGED=1` in
the environment. Only `plan` takes `--source` and `--trust-origin`; the other commands read the
clone `plan` recorded, checking offline that it is still clean, at the same commit, with the same
origin. The PowerShell runner takes the same commands with `-Source`, `-TrustOrigin`, `-Scope`,
`-ConfirmedByUser` and `-AllowUntagged`.

**What the runner does not trust.** The release clone's own git configuration: no fsmonitor
hook, untracked cache or relaxed stat check applies to its checks, and the tag check runs
`git ls-remote` against the trusted URL from outside every repository, so no
`url.<x>.insteadOf` in the clone can redirect it. A clone path with a control character (a
newline) is refused, and so is a notes file committed as a symlink: notes are read only from
regular blobs at HEAD, with `git cat-file`.

**Where steps run.** `{ROOT}` is the install root of the upgrade worktree once `upgrade-01` has
recorded it with `set worktree=…`, else of the main checkout (the first entry of
`git worktree list`), where only `upgrade-01` and `verify` work; developer steps run in the
checkout the runner runs in. `{SRC}` is the release clone (repo steps only). The runner sets
`SUMELA_MIGRATE_SRC` and `SUMELA_MIGRATE_ROOT` for each command. On Windows, the PowerShell runner
uses `run.ps1`/`verify.ps1`/`rollback.ps1` when a step has them and scripts may run; otherwise it
runs the bash line through Git Bash, located at `<git --exec-path>/../../../bin/bash.exe` or
`…/usr/bin/bash.exe`.

**Selection.**

- Repo scope: every `upgrade.md` step, plus every repo step of each version in (`from`,
  `target`], without a ledger entry and not moot (`until` ≤ `target`). `from` is the installed
  version the upgrade started from and `target` the clone's `.sumela/VERSION`, both kept in
  `migrate.state`, so the steps after the apply stamps VERSION stay listed. A `ledger: none`
  step is listed only while `--source` is given; without it, `plan` names it on a line of its
  own while it is unrecorded.
- Developer scope: every developer step of the installed notes with a version ≤ the installed
  VERSION, without a ledger entry and not moot (`until` ≤ the installed VERSION). A teammate who
  pulls an upgrade therefore sees the developer steps of every version they skipped.
- A declined step stays listed (as declined), whatever the version range, until it is redone.
- Order: the `when` phase (`pre-update`, `update`, `post-update`, `finalize`, `quiet-window`,
  `first-session`), then the version (`upgrade.md` steps count as `target`), then the id, with
  `requires` respected.
- Complete: the main checkout's VERSION has reached the target (the upgrade is merged there).
  `plan` then removes `migrate.state`. Before that, with every repo step recorded, the state
  stays for the rollbacks (it goes too when the upgrade worktree is gone); `status` reports
  nothing pending and stays silent.

**Ledgers.**

- Repo: `.sumela/migrations-applied/<id>` in `{ROOT}` (`upgrade-<NN>@<target>` for `upgrade.md`
  steps), with `status:`, `at:` and `version:` lines. It is tracked, lands in the upgrade PR,
  and is added to the provenance record's `files`, so the review guard treats it as a framework
  write.
- Developer: `migrations.log` in the per-developer state directory
  (`${XDG_STATE_HOME:-~/.local/state}/sumela/<key>/`, `%LOCALAPPDATA%\sumela\<key>\` on
  Windows), one `<id><TAB><status><TAB><UTC>` line per entry, mode 0600; the newest line for an
  id wins.
- Procedural (`ledger: none`) repo steps leave no tracked entry: their verify is the evidence
  (for `upgrade-07`, the commit itself). `record` notes them in `migrate.state`, so a resumed
  `plan --source` does not list them again.

## The format

One fenced `sumela-step` block per step, made of `key: value` lines. Full-line `#` comments are
allowed; inline comments are not, because a value is a verbatim command. Blanks around a value
are dropped. Prose outside the blocks is ignored.

| Key | Value |
|---|---|
| `id` | `<X.Y.Z>-<NN>` in `<X.Y.Z>.md`, `upgrade-<NN>` in `upgrade.md` (required) |
| `title` | one line (required) |
| `scope` | `repo` or `developer` (required; `upgrade.md` holds repo steps only) |
| `when` | `pre-update`, `update`, `post-update`, `finalize`, `first-session` or `quiet-window` (required) |
| `requires` | step ids of the same scope, space- or comma-separated; each must be recorded `done` first |
| `consent` | `none`, `confirm` or `explicit` (typed) (required) |
| `run` | the command, or `-` when the agent performs the step (required) |
| `run.ps1`, `verify.ps1`, `rollback.ps1` | the PowerShell forms |
| `verify` | the read-only check of the step's artifact (required) |
| `expect` | `exit0`, `non-empty`, `empty`, `equals:<s>` or `match:<ERE>` against the verify output (required) |
| `rollback` | the command that undoes the step (for a repo step: before the merge, in the upgrade worktree) |
| `agent` | the instruction for the agent: required when `run` is `-` |
| `ledger` | `none` for a procedural step that leaves no ledger entry |
| `until` | `<X.Y.Z>`: the step is moot once the release (repo) or the install (developer) reaches it |

**Placeholders.** `{SRC}`, `{ROOT}` and `{TARGET}` are the only substitutions. In commands,
`{SRC}` and `{ROOT}` become `${SUMELA_MIGRATE_SRC}` and `${SUMELA_MIGRATE_ROOT}`
(`${env:…}` in PowerShell), so a path with spaces or quotes is never parsed again; they must
therefore sit inside double quotes (a `$( … )` opens its own quoting context). `{TARGET}` is the
release being installed (the clone's `.sumela/VERSION`, checked against
`[0-9]+.[0-9]+.[0-9]+(-rc.[0-9]+)?`; for a developer step, the installed version), substituted
literally, and inside a `match:` expect with its dots escaped. In `title` and `agent`, all three
are shown as plain values.

**The lint** (`lint`; it also runs on every notes file the runner loads):

- every file parses, and its name is `upgrade.md` or `<X.Y.Z>.md`; every block has the required
  keys, known keys only, once each, and valid values;
- ids match their file's version, once each; every `requires` resolves within the same scope,
  without a cycle; a `pre-update` repo step of a version requires `upgrade-01`;
- every `expect` form is valid; a `match:` pattern compiles and avoids POSIX classes and
  backslash escapes before a letter or digit, so both runners read it alike;
- every runnable step has a `run.ps1`, or a `run` line starting with `bash`, which the PowerShell
  runner sends to Git Bash;
- only `{SRC}`, `{ROOT}` and `{TARGET}` appear, the first two inside double quotes in commands;
  a developer step never uses `{SRC}` (a teammate has no release clone);
- `consent: none` only on a `run: -` step or a read-only one, and with a read-only verify: its
  `run`, `run.ps1`, `verify` and `verify.ps1` (each one it has; a `run: -` has no run line) is
  exactly one of these shapes. A word is plain: `[A-Za-z0-9_./:=@%+-]` characters, not starting
  with `@` (PowerShell splats `@name`), or one whole double-quoted string of those, spaces and
  commas; `{SRC}`, `{ROOT}` and `{TARGET}` may appear in either. Anything else is refused, so
  bash and PowerShell split the line alike: a tab, `#`, `$`, a backtick, `;`, `&`, `|`, `<`,
  `>`, parentheses, braces outside a placeholder, a single quote, a backslash, globs, `~`, `!`,
  a comma outside a string (an array in PowerShell), a quote inside a word, an empty string,
  and every non-ASCII character (PowerShell reads curly quotes as quotes and en dashes as
  dashes):
  - `bash <script.sh> [--source <dir>] <mode>`, where `<script.sh>` is a relative path or one
    under `{SRC}` or `{ROOT}`, and `<mode>` is one of `--plan`, `--plan-check`, `--status`,
    `--check`, `--verify-applied`, or `--has-baseline <name>`, and nothing else;
  - `bash <path>/validate-structure.sh`, with no argument;
  - `git [-C <dir>] config [--local|--global|--worktree] --get <key>`, where `<dir>` does not
    start with `-`;
  - for `run.ps1`: `powershell|pwsh [-NoProfile] [-NonInteractive] -File <script.ps1>
    [-SourceDir|-Source <dir>] <mode>`, where `<mode>` is one of `-Plan`, `-PlanCheck`,
    `-Status`, `-Check`, `-VerifyApplied`, or `-HasBaseline <name>` (or the bash forms), or
    the `git config` shape;
- the same shapes decide which developer verifies `plan` may run on its own (applied to the line
  that will run: `verify.ps1` when the PowerShell runner would use it);
- every `run: -` step has a `verify` and an `agent:` line; `until` is above the file's version.

## Writing notes (maintainers)

- Put a step in `upgrade.md` only when every release needs it; anything else goes into the
  version's own file. Make each step idempotent, verifiable by an artifact, and safe to resume.
- Every change to a tracked file or a setting needs consent. A step that loosens a control needs
  `explicit`.
- Run `bash scripts/sumela-migrate.sh lint` and `bash tests/test_migration_notes.sh` (the lint
  plus an end-to-end run of every repo step and every repo rollback on a v0.19-shaped project)
  before a release, and cut the release as `vX.Y.Z-rc.N` first.
