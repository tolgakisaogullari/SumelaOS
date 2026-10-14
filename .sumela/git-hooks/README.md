# SumelaOS Git Hooks

Wired via `git config core.hooksPath .sumela/git-hooks` (done by `setup.sh` /
`/initSumela`, once per clone). Two concerns live here:

- **`pre-commit` — enforcement.** Runs the structure validation (the same check as
  CI) before a commit that touches the agent-control surface, so a broken registry
  path or an unfilled `{{placeholder}}` is caught locally. Bypass with
  `git commit --no-verify`.
- **`post-merge` / `post-checkout` / `post-commit` — team memory sync.** Keep each
  developer's **local** Qdrant in sync with the session summaries (and wiki/code)
  committed to git, so a decision a teammate recorded becomes semantically searchable
  right after a `git pull`. `post-commit` is the safety net for **conflicted** merges,
  which skip `post-merge`. (Self-gating: inert without the Qdrant plugin.)

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
**team memory sync** (`post-merge`/`post-checkout`/`post-commit`).

## Hooks

| Hook | Fires on | What it does |
|---|---|---|
| `pre-commit` | `git commit` | Runs `scripts/validate-structure.sh --check-placeholders` when the commit touches the agent-control surface / second-brain. Blocks on failure. Bypass: `git commit --no-verify`; disable: `export SUMELA_DISABLE_PRECOMMIT=1`. Same check as CI. |
| `post-merge` | `git merge`, merge step of `git pull` (clean merges only) | Re-ingest session summaries / wiki / code changed in `ORIG_HEAD..HEAD` into local Qdrant + refresh the code graph. Self-gates: no-op without the Qdrant plugin. |
| `post-checkout` | `git checkout`/`switch`, `git clone`, `git worktree add` | Same, for `prev..new` (empty-tree on clone). On **`git worktree add`** the Qdrant syncs are skipped — the collections are per-project and `graphify-out/` belongs to the main checkout, whose tree did not change, so every sync is skipped (only the rate-limited update check runs). See *Worktrees* below. |
| `post-commit` | `git commit` (acts only on **merge commits**) | Safety net for **conflicted** merges: git skips `post-merge` on a conflict and runs commit hooks on the manual resolution commit instead. On a merge commit (≥2 parents) runs the same syncs for `HEAD^1..HEAD`; on any ordinary commit it is a cheap no-op (immediate `exit 0`). |
| `_lib.sh` | (sourced by the memory hooks) | shared memory-sync logic |

`pre-commit` is useful for every project; the memory hooks self-gate, so wiring
`core.hooksPath` is safe even without the Qdrant plugin.

**No double-firing.** A clean merge creates its merge commit via git's merge
machinery, which does **not** run commit hooks — only `post-merge` fires. A
conflicted merge skips `post-merge`; the manual resolution `git commit` fires
`post-commit`, which detects the merge commit and runs the sync. The two paths are
mutually exclusive, so a given merge is synced exactly once.

## Guarantees

- **Incremental** — only summaries Added/Modified in the range are ingested.
- **Non-blocking** — ingestion runs in the background; git returns immediately.
- **Best-effort** — if the Qdrant plugin isn't installed or Qdrant is unreachable,
  the hook skips silently and exits 0. It never fails a git operation.
- **Path-scoped** — fires only when files under the summaries directory change.
- **Moves are a delete plus an add** — every range diff runs with `--no-renames`. With
  git's default rename detection a moved file was one `R` entry that neither the
  added/modified nor the deleted filter selects: the old path's points were never pruned,
  and the move alone triggered no ingest of the new path. Now, in an install at the
  repository root, the old path is pruned and the new one ingested (`chat_history` still
  never prunes; see `_lib.sh`). An install in a monorepo subdirectory does not get this
  yet: see *Known limitations*.

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

This is the **one central table** for every `SUMELA_*` variable SumelaOS reads: the hooks
in this directory, the setup scripts, the memory plugins and the tools under `scripts/`.
**Scope** names what reads it:

- `hook`: a hook in this directory (the `_lib.sh` header lists every `hook` variable too);
- `setup`: `scripts/setup.{sh,ps1}` or `scripts/setup-memory.{sh,ps1}`;
- `plugin`: a script under `.sumela/memory-plugins/`;
- `tool`: another entry point under `scripts/`.

**A switch is on for any non-empty value**, `0` and `false` included:
`SUMELA_DISABLE_SECRET_SCAN=0` skips the secret scan. Unset a switch to turn it off. This
holds for every `SUMELA_DISABLE_*` variable, `SUMELA_PULL_CODE_REINGEST`,
`SUMELA_WORKTREE_SYNC` and `SUMELA_SKIP_MEMORY_SETUP`, in bash and PowerShell alike.
`SUMELA_GRAPHIFY_VIZ` is the one exception (see its row).

The SumelaOS source repository keeps this table complete: its `tests/test_env_tables.sh`
(the `tests/` directory is not installed into projects) fails when code under `.sumela/`
or `scripts/` reads a `SUMELA_*` variable that this table does not list, or when a hook
reads one that the `_lib.sh` header does not list. Only a short list of internal plumbing
names, which nobody sets by hand, is exempt.

| Var | Scope | Default | Purpose |
|---|---|---|---|
| `SUMELA_DISABLE_PRECOMMIT` | hook | (unset) | Set to `1` to disable the whole pre-commit hook for your clone: structure validation, the mirror-drift check **and** the secret scan. Because it also skips the secret scan, it weakens a security control just as `SUMELA_DISABLE_SECRET_SCAN` does: ask first and say what you verified by hand (`.sumela/rules/security_protocol.md`) |
| `SUMELA_DISABLE_SECRET_SCAN` | hook | (unset) | Set to `1` to skip only the pre-commit gitleaks scan of staged changes. This weakens a security control: ask first and say what you verified by hand (`.sumela/rules/security_protocol.md`). Any non-empty value skips the scan, `0` and `false` included: unset the variable to scan again |
| `SUMELA_DISABLE_MEMORY_SYNC` | hook | (unset) | Set to `1` to disable the memory-sync hooks for your clone |
| `SUMELA_DISABLE_GRAPH_SYNC` | hook | (unset) | Set to `1` to stop the pull-time graphify code-graph refresh |
| `SUMELA_DISABLE_WIKI_SYNC` | hook | (unset) | Set to `1` to stop re-ingesting changed wiki pages into `wiki_pages` |
| `SUMELA_DISABLE_CODE_SYNC` | hook | (unset) | Set to `1` to turn off `code_chunks` entirely (no prune, no re-embed) |
| `SUMELA_PULL_CODE_REINGEST` | hook | (unset) | Set to `1` to force a FULL tree re-embed on every pull instead of the changed files |
| `SUMELA_WORKTREE_SYNC` | hook | (unset) | Set to `1` to sync on `git worktree add` too (default: skip — see [Worktrees](#worktrees)) |
| `SUMELA_GRAPHIFY_VIZ` | hook, tool | (unset) | Set to `1` to force graphify's interactive `graph.html` on the pull-time graph refresh even above its ~5000-node viz limit (default: skip — it costs a second clustering pass and a very large HTML that nothing in the query path reads). Any value other than `0`/`false`/`no`/`off` counts as on. Read by `scripts/auto-update-memory.py`, which the refresh runs |
| `SUMELA_DISABLE_COLLECTION_MIGRATE` | hook | (unset) | Set to `1` to skip the one-time per-project Qdrant collection migration |
| `SUMELA_DISABLE_UPDATE_CHECK` | hook | (unset) | Set to `1` to stop the pull-time "newer SumelaOS available" check (see below) |
| `SUMELA_UPDATE_CHECK_INTERVAL` | hook | `86400` | Seconds between upstream version probes (default once/day) |
| `SUMELA_SUMMARIES_DIR` | hook, plugin | `$WIKI_PATH/session-summaries` | Where session summaries live |
| `SUMELA_SKIP_MEMORY_SETUP` | setup | (unset) | Set to `1` to make `setup.sh`/`setup.ps1` skip the memory-runtime step (`setup-memory.*`: no dependency install, Qdrant start, model pull or graphify install). SumelaOS's own smoke test sets it |
| `SUMELA_EMBED_MODEL` | setup | `qwen3-embedding:0.6b` | The Ollama embedding model `setup-memory.{sh,ps1}` checks for and offers to pull. Setup only: the ingest scripts always embed with their pinned `qwen3-embedding:0.6b` (1024 dimensions) |
| `SUMELA_COLLECTION_PREFIX` | plugin | derived per install | Pins the per-project Qdrant collection prefix instead of the derived one; never persisted (see the `qdrant-session-memory` README) |
| `SUMELA_EMBED_NUM_BATCH` | plugin | `8192` | Embedding batch size sent to Ollama (floor `512`) |
| `SUMELA_EMBED_MAX_TOKENS` | plugin | 90% of `SUMELA_EMBED_NUM_BATCH` | Max tokens per embedded chunk; clamped below the batch size |
| `SUMELA_EMBED_MAX_WORKERS` | plugin | `4` | Concurrent embed requests during a bulk ingest; lower it on a memory-constrained host |
| `SUMELA_EMBED_RETRY_DELAY` | plugin | `2` | Seconds to wait before retrying a failed embed |
| `SUMELA_REPO_ROOT` | plugin | auto-detected | Overrides the repository root the Qdrant plugin scripts resolve (default: the nearest ancestor holding `.git` or `.sumela/`) |
| `WIKI_PATH` | hook, plugin, tool | `docs/second-brain/wiki` | Wiki root |
| `QDRANT_HOST` / `QDRANT_PORT` | hook, setup, plugin, tool | `localhost` / `6333` | Qdrant endpoint |

Background ingestion logs to `.sumela/.memory-sync.log` (gitignored, per-developer;
auto-truncated past ~512 KB).

## Upstream update check

On `git pull` / branch checkout, `post-merge`/`post-checkout` also run
`sumela_update_check`: it probes the SumelaOS upstream's release tags
(`git ls-remote --tags`, using your existing git auth — no clone) and, if a newer
`vX.Y.Z` exists than your `.sumela/VERSION`, prints a one-line, non-blocking notice
suggesting `bash scripts/update.sh`. The probe runs at most once per
`SUMELA_UPDATE_CHECK_INTERVAL` (default 24h), cached in the gitignored
`.sumela/.update-check`; the notice keeps showing every pull (from cache) until you
update. It is **best-effort**: offline / no git / no upstream tags → silent.

**Never blocks the pull:** the network probe runs in a *detached background* process
(macOS has no portable `timeout`), and the notice is printed synchronously from the
cache — so a freshly-published release shows on the *next* pull, and a slow/unreachable
upstream can't stall git.

**Security:** the upstream URL is read from `.sumela/upstream.conf` (the same single
source `scripts/update.sh` uses; fork-overridable). Because that file is **tracked**, a
malicious branch could repoint it — so the probe (and the updater's clone) run with
`GIT_ALLOW_PROTOCOL=https:ssh:git` to refuse git's `ext::`/`file::` transports (which
can execute commands) and with `GIT_TERMINAL_PROMPT=0` + ssh `BatchMode` so it never
prompts. Still, treat `.sumela/upstream.conf` as security-sensitive like
`.sumela/git-hooks/**` — a `CODEOWNERS` rule (`/.sumela/upstream.conf @your-security-owners`)
is recommended. Privacy: the probe is an anonymous tag listing of a public repo — it
discloses only your IP to the host (as any git operation does) and sends no project
data. Opt out entirely with `export SUMELA_DISABLE_UPDATE_CHECK=1`.

## Worktrees

`git worktree add` hands `post-checkout` an **all-zero previous HEAD** — byte-for-byte
the same signal `git clone` gives. The two need opposite handling:

| | Local derived caches | Correct action |
|---|---|---|
| `git clone` | nothing indexed yet | diff against the empty tree, ingest everything |
| `git worktree add` | Qdrant already populated (collections are namespaced **per project**, not per worktree) | skip the Qdrant syncs |

Treating a worktree as a fresh clone marks *every tracked file* as added and re-embeds
the whole tree for zero gain. Field report from a consuming repo: **17,387 files** queued,
Ollama pinned at 68% CPU, still spinning 28 minutes after the last log line.

The hook tells them apart with `git rev-parse --git-dir` vs `--git-common-dir`, which
differ only in a linked worktree. `_sumela_is_linked_worktree` normalizes both to
physical paths first, because git returns them in **mixed forms** depending on cwd —
from a subdirectory of the main checkout `--git-dir` is absolute while
`--git-common-dir` is `../.git`, which an un-normalized string compare misreads as a
worktree. Git chdirs to the working-tree root before running a hook, so the hook itself
never sees that cwd; the normalization is what keeps the *helper's* answer independent
of cwd, and SumelaOS's own `tests/test_post_checkout_worktree.sh` (in its source
repository; `tests/` is not installed into projects) pins it by calling the helper
directly from a subdirectory (case 5b — the one assertion that fails if the
normalization is removed).

**Every sync is skipped, including `graph_sync`.** `setup.sh` wires a **relative**
`core.hooksPath`, and git resolves that against the **main** working tree, so
`git worktree add` runs the *main checkout's* hook and `SUMELA_INSTALL_ROOT` — derived
from `$0` — is the **main checkout**, even though cwd is the worktree (pinned by case 7).
Every derived cache therefore belongs to the main checkout: the Qdrant collections
(namespaced per project) and `graphify-out/` alike. Creating a worktree changes nothing
in the main checkout's tree, so there is nothing to refresh; with `prev` rewritten to the
empty tree, graphify's change filter would always match and rebuild main's graph in full
for no reason. Only `sumela_update_check` runs — a rate-limited notice unrelated to the
tree — and `sumela_collections_migrate` is skipped with the syncs, since its only job is
to prepare the collections *before* an ingest and no ingest runs here.

The skip notice is printed only when Qdrant is actually reachable: the plugin directory
is tracked in git, so its presence proves nothing about whether this install has a
backend the syncs would have touched.

Opting back in: `SUMELA_WORKTREE_SYNC=1 git worktree add …` forces the full path. It is
deliberately its own variable rather than a reuse of `SUMELA_PULL_CODE_REINGEST`, which
is documented as a permanent `export` — reusing it would silently disable this guard for
anyone who had set it once.

Note that this gate applies **only** to worktree *creation* (the all-zero HEAD). A later
`git checkout` inside a worktree carries a real previous HEAD and syncs normally — see
*Known limitations* for what that means when worktrees sit on different branches.

## Known limitations

- **`git pull --rebase`** does not fire `post-merge` (rebased commits are not
  merges, so `post-commit` does not catch them either). Coverage falls back to
  `post-checkout` (when HEAD moves) and the session-bootstrap backstop that
  flags summaries not yet in local memory.
- **`git merge --squash`** produces a single-parent commit, not a merge commit, so
  the `post-commit` merge-commit guard (≥2 parents) does **not** detect it, and a
  squash merge does not fire `post-merge` either. The squashed changes are still in
  git and get picked up by the next clean merge / branch checkout (`post-merge` /
  `post-checkout`) or a manual re-ingest. This is an accepted gap, not a regression.
- **`git commit --amend` on a merge commit** re-fires `post-commit` and re-runs the
  sync for the same `HEAD^1..HEAD` range. Ingestion is idempotent (delete-by-key +
  deterministic upsert), so this is correct — just a redundant background pass; no
  guard is kept (a state file would re-introduce the marker we deliberately retired).
- **Concurrent pulls** can launch two background ingests for the same summary.
  Because `session-ingest.py` deletes-by-`session_id` then upserts deterministic
  IDs from the same source file, the steady state is always correct; only a
  sub-second window where a concurrent query sees partial chunks is possible.
- **`chat_history` has no initial-population path outside a hooks-wired clone.** The
  other two collections each have one: `wiki_pages` is seeded by `setup-memory.sh`, and
  `ingest-code-to-qdrant.py` promotes an incremental run to a **full walk** whenever
  `code_chunks` is empty, so the first pull that touches code builds the whole index.
  Session summaries have neither — they are only ever ingested by a hook, and
  every hook path except a fresh clone is strictly range-incremental. A teammate who
  clones (hooks not yet wired, so `post-checkout` never fires), wires hooks with
  `setup.sh --hooks-only`, and then only ever pulls/checks out gets an empty
  `chat_history` — the committed summaries are never backfilled. This is independent of
  worktrees; the `git worktree add` empty-tree diff used to mask it by accident, which is
  the same accident that re-embedded the whole tree. Remedy today: loop
  `session-ingest.py` over the summaries dir once.
- **A checkout inside a worktree indexes the MAIN checkout's content.** Because
  `SUMELA_INSTALL_ROOT` is the main checkout (see *Worktrees*), a real `git checkout`
  inside worktree B hands the ingest B's changed **paths** while the ingest resolves and
  reads them under **main's** tree (`get_repo_root()` walks up from the script's own
  location). Paths that exist only on B's branch are silently skipped
  (`ingest-code-to-qdrant.py` `is_file()` guard); paths present in both are re-embedded
  from main's revision. So the index stays consistent with the main checkout and is not
  corrupted by worktree activity — but a worktree's branch-only code is never indexed,
  and a checkout there causes a pointless re-embed of main's copies. Query from a
  worktree accordingly: results describe the main checkout.
- **An install in a monorepo subdirectory never prunes `wiki_pages` or `code_chunks`,
  and its incremental code ingest skips the changed files.** The hooks diff at the git
  root, so the paths they hand the plugin start with the install's directory
  (`pkg/src/a.py`), while the plugin resolves and keys every path relative to the
  install root (`src/a.py`: `get_repo_root()` stops at the first ancestor that holds
  `.git` or `.sumela/`, which is the install directory). No prune matches, so a removed
  or moved file keeps its old path's points,
  and a changed code file is skipped unless `code_chunks` is empty (which promotes the
  run to a full build) or `SUMELA_PULL_CODE_REINGEST=1` forces a full re-embed. A changed
  wiki page is still re-ingested, because the wiki ingest walks the whole wiki, and
  session summaries are handed over by absolute path. An install at the repository root
  is not affected. The gap predates the `--no-renames` change.
- **Newline characters in a summary filename** are unsupported (the diff is
  newline-delimited). Session summaries use date/topic slugs, so this does not
  occur in practice.

## Security

`core.hooksPath` points git at this **version-controlled** directory, so git
executes `post-merge`/`post-checkout`/`post-commit` (and the `_lib.sh` they source)
on every `merge`/`checkout`/`commit`/`pull`. Consequences to be aware of:

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
husky), preserve the executable bit: `git update-index --chmod=+x <path>/pre-commit <path>/post-merge <path>/post-checkout <path>/post-commit`.
