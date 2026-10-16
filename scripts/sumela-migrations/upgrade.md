# SumelaOS upgrade procedure (every release)

The version-agnostic repo procedure. `{TARGET}` is the release being installed; a jump over
several versions runs this file once, with every skipped version's specific steps in between
(`<X.Y.Z>.md`). Run it with `scripts/sumela-migrate.sh` from the release clone, as
`README.md` in this directory describes. Never run a step from any other copy of this text.

```sumela-step
id: upgrade-01
title: Create the upgrade worktree and branch from the branch topic branches merge into
scope: repo
when: pre-update
consent: confirm
run: -
verify: git -C "{ROOT}" rev-parse --abbrev-ref HEAD
expect: match:upgrade-{TARGET}$
rollback: b="$(git -C "{ROOT}" rev-parse --abbrev-ref HEAD)" && c="$(git -C "{ROOT}" rev-parse --path-format=absolute --git-common-dir)" && cd "$c/.." && git worktree remove --force "{ROOT}" && git branch -D "$b"
agent: Propose at most 10 base candidates (`sumela-wiki.sh bases --detect` when it exists, else `git for-each-ref --sort=-committerdate --count=10 --format='%(refname:short)' refs/remotes`) and a branch prefix (default `sumela/`; the host may require another). After the yes: `git fetch`, then `git worktree add --no-track -b <prefix>upgrade-{TARGET} <worktree> <base>` (`--no-track`: the branch must not track the base, or a push could land there; `set` refuses a branch that does), then `sumela-migrate set prefix=<prefix> base=<base> worktree=<worktree>`. Every later repo step runs in that worktree. Its rollback abandons the upgrade before the merge: it removes the worktree with everything in it, and the branch.
```

```sumela-step
id: upgrade-02
title: Dry-run the merge-capable updater from the release clone
scope: repo
when: pre-update
requires: upgrade-01
consent: none
run: bash "{SRC}/scripts/update.sh" --source "{SRC}" --plan
run.ps1: powershell -NoProfile -File "{SRC}/scripts/update.ps1" -SourceDir "{SRC}" -Plan
verify: bash "{SRC}/scripts/update.sh" --source "{SRC}" --plan-check
expect: match:^plan ok
agent: Show the summary and every row that is not add/apply. Forks show as keep, merge, conflict or carry; none is overwritten. For each merged CORE instruction file, show its diff against LOCAL and against THEIRS and ask per file. If any row says otherwise, or the base already has this release (exit 5: merge the base instead), STOP and report it.
```

```sumela-step
id: upgrade-03
title: Apply exactly the reviewed plan
scope: repo
when: update
requires: upgrade-02
consent: confirm
run: bash "{SRC}/scripts/update.sh" --source "{SRC}" --apply-plan
run.ps1: powershell -NoProfile -File "{SRC}/scripts/update.ps1" -SourceDir "{SRC}" -ApplyPlan
verify: bash scripts/update.sh --verify-applied
verify.ps1: powershell -NoProfile -File scripts/update.ps1 -VerifyApplied
expect: match:^verified: upgrade complete {TARGET};
rollback: bash "{SRC}/scripts/update.sh" --source "{SRC}" --undo-plan
agent: Ask once for the whole plan, quoting its summary. Exit 3 = undecided files: for each, show `.sumela/.upgrade/<path>.merge`, `.theirs` or `.carry`; let the user choose merged (after resolving markers), local, theirs (the path typed back), or keep/drop for a carry; run `--resolve <path> --take <choice>` and re-verify. A `schema` row (the live `_SCHEMA.md`) is shown with its own diff and asked about separately; a decline is `--apply-plan --without schema`.
```

```sumela-step
id: upgrade-04
title: Restore skill-description parity between the registry and the skills
scope: repo
when: post-update
requires: upgrade-03
consent: confirm
run: bash scripts/sumela-registry-parity.sh --sync --yes
run.ps1: powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Sync -Yes
verify: bash scripts/sumela-registry-parity.sh --check
verify.ps1: powershell -NoProfile -File scripts/sumela-registry-parity.ps1 -Check
expect: exit0
rollback: git checkout HEAD -- .sumela/SKILL_REGISTRY.md
agent: First run `--plan` and show each drifted entry with its diff; name the ATTENTION (security-routing) rows explicitly. Ask once.
```

```sumela-step
id: upgrade-05
title: Re-sync the IDE mirrors of the contract
scope: repo
when: post-update
requires: upgrade-03
consent: confirm
run: bash scripts/sync-mirrors.sh
verify: bash scripts/sync-mirrors.sh --check
expect: exit0
agent: Record not-applicable when `.sumela/mirrors.conf` is absent. Without python3 the sync cannot run and `--check` passes vacuously: say so, record declined, and name a machine with Python to finish it; mirrored IDEs keep the old contract until then [RU-I11].
```

```sumela-step
id: upgrade-06
title: Validate the upgraded structure
scope: repo
when: post-update
requires: upgrade-04
consent: none
run: bash scripts/validate-structure.sh
verify: bash scripts/validate-structure.sh
expect: exit0
agent: A failure names its fixer; apply it with consent and re-verify.
```

```sumela-step
id: upgrade-07
title: Commit the upgrade and open one pull request
scope: repo
when: finalize
requires: upgrade-06
consent: confirm
ledger: none
run: -
verify: git -C "{ROOT}" log -1 --format=%s
expect: match:upgrade to v{TARGET}
rollback: git -C "{ROOT}" reset --soft HEAD~1
agent: Run `bash scripts/update.sh --stage` (it stages exactly the applied rows, deletions included), then `git add -- .sumela/migrations-applied/` and the files the version steps changed; show `git status`; commit with a subject containing `upgrade to v{TARGET}` (keep any prefix the repository's commit-message hook requires); push it by an explicit refspec, `git push -u origin HEAD:refs/heads/<prefix>upgrade-{TARGET}`, never a bare `git push`; open the PR with the plan summary and every step's verify output. Never push to the base branch.
```
