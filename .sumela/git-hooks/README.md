# SumelaOS Git Hooks — Team Memory Sync

These hooks keep each developer's **local** Qdrant in sync with the session
summaries committed to git, so a decision a teammate recorded becomes
semantically searchable on your machine right after you `git pull`.

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

## Hooks

| Hook | Fires on | Range ingested |
|---|---|---|
| `post-merge` | `git merge`, merge step of `git pull` | `ORIG_HEAD..HEAD` |
| `post-checkout` | `git checkout`/`switch`, `git clone` | `prev..new` (empty-tree on clone) |
| `_lib.sh` | (sourced by both) | shared logic |

`git pull --rebase` does **not** trigger `post-merge`; rebase users are covered
by `post-checkout` when HEAD moves, and the session bootstrap surfaces summaries
not yet in local memory as a backstop.

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
| `SUMELA_DISABLE_MEMORY_SYNC` | (unset) | Set to `1` to disable the hooks for your clone |
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
husky), preserve the executable bit: `git update-index --chmod=+x <path>/post-merge <path>/post-checkout`.
