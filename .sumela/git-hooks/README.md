# SumelaOS Git Hooks

Wired via `git config core.hooksPath .sumela/git-hooks` (done by `setup.sh` /
`/initSumela`, once per clone). Two concerns live here:

- **`pre-commit` — enforcement.** Runs the structure validation (the same check as
  CI) before a commit that touches the agent-control surface, so a broken registry
  path or an unfilled `{{placeholder}}` is caught locally. Bypass with
  `git commit --no-verify`.
- **`post-merge` / `post-checkout` — team memory sync.** Keep each developer's
  **local** Qdrant in sync with the session summaries committed to git, so a
  decision a teammate recorded becomes semantically searchable right after a
  `git pull`. (Self-gating: inert without the Qdrant plugin.)

```
teammate's session ──commit summary.md──► git (shared source of truth)
                                            │
                            git pull / merge ▼
                                       post-merge hook
                                            │  (changed summaries only)
                                            ▼
                                  session-ingest.py ──► YOUR local Qdrant
```

The markdown summaries in git are the shared source of truth; your Qdrant is a
derived local cache. These hooks are the cache-invalidation step.

This directory holds two independent concerns: **enforcement** (`pre-commit`) and
**team memory sync** (`post-merge`/`post-checkout`).

## Hooks

| Hook | Fires on | What it does |
|---|---|---|
| `pre-commit` | `git commit` | Runs `scripts/validate-structure.sh --check-placeholders` when the commit touches the agent-control surface / second-brain. Blocks on failure. Bypass: `git commit --no-verify`; disable: `export SUMELA_DISABLE_PRECOMMIT=1`. Same check as CI. |
| `post-merge` | `git merge`, merge step of `git pull` | Re-ingest changed session summaries (`ORIG_HEAD..HEAD`) into local Qdrant. Self-gates: no-op without the Qdrant plugin. |
| `post-checkout` | `git checkout`/`switch`, `git clone` | Same, for `prev..new` (empty-tree on clone). |
| `_lib.sh` | (sourced by the memory hooks) | shared memory-sync logic |

`pre-commit` is useful for every project; the memory hooks self-gate, so wiring
`core.hooksPath` is safe even without the Qdrant plugin. `git pull --rebase` does
**not** trigger `post-merge`; rebase users are covered by `post-checkout` when HEAD
moves, and the session bootstrap surfaces summaries not yet in local memory.

## Guarantees

- **Incremental** — only summaries Added/Modified in the range are ingested.
- **Non-blocking** — ingestion runs in the background; git returns immediately.
- **Best-effort** — if the Qdrant plugin isn't installed or Qdrant is unreachable,
  the hook skips silently and exits 0. It never fails a git operation.
- **Path-scoped** — fires only when files under the summaries directory change.

Re-ingesting is safe because `session-ingest.py` uses deterministic point IDs
(delete-by-session + upsert), so a summary is never duplicated in Qdrant.

## Installation

Hooks in `.git/hooks/` are not version-controlled, so this directory is wired in
via git's `core.hooksPath`:

```bash
git config core.hooksPath .sumela/git-hooks
```

`scripts/setup.sh` / `setup.ps1` (and `/initSumela`) run this for you. Each
developer runs it once per clone.

## Configuration (environment variables)

| Var | Default | Purpose |
|---|---|---|
| `SUMELA_DISABLE_PRECOMMIT` | (unset) | Set to `1` to disable the pre-commit validation hook for your clone |
| `SUMELA_DISABLE_MEMORY_SYNC` | (unset) | Set to `1` to disable the memory-sync hooks for your clone |
| `SUMELA_SUMMARIES_DIR` | `$WIKI_PATH/session-summaries` | Where session summaries live |
| `WIKI_PATH` | `docs/second-brain/wiki` | Wiki root |
| `QDRANT_HOST` / `QDRANT_PORT` | `localhost` / `6333` | Qdrant endpoint |

Background ingestion logs to `.sumela/.memory-sync.log` (gitignored, per-developer;
auto-truncated past ~512 KB).

## Known limitations

- **`git pull --rebase`** does not fire `post-merge`. Coverage falls back to
  `post-checkout` (when HEAD moves) and the session-bootstrap backstop that
  flags summaries not yet in local memory.
- **Concurrent pulls** can launch two background ingests for the same summary.
  Because `session-ingest.py` deletes-by-`session_id` then upserts deterministic
  IDs from the same source file, the steady state is always correct; only a
  sub-second window where a concurrent query sees partial chunks is possible.
- **Newline characters in a summary filename** are unsupported (the diff is
  newline-delimited). Session summaries use date/topic slugs, so this does not
  occur in practice.

## Security

`core.hooksPath` points git at this **version-controlled** directory, so git
executes `post-merge`/`post-checkout` (and the `_lib.sh` they source) on every
`merge`/`checkout`/`pull`. Consequences to be aware of:

- A `git clone` alone does **not** auto-run these hooks: `core.hooksPath` is local
  config that each developer sets once per clone (via setup). Cloning untrusted
  code does not execute them.
- **But** once wired, pulling or checking out an **untrusted branch** runs the
  *then-current* hook scripts before you review the diff. Treat changes under
  `.sumela/git-hooks/**` as security-sensitive.
- Recommended: protect this directory with a `CODEOWNERS` rule
  (`/.sumela/git-hooks/ @your-security-owners`) so hook changes require explicit
  review, and audit hook diffs in PRs.

If you copy these hooks into another hooks path manually (e.g. when merging with
husky), preserve the executable bit: `git update-index --chmod=+x <path>/pre-commit <path>/post-merge <path>/post-checkout`.
