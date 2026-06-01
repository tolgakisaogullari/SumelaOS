# Self-Improvement Queue (`_improvement-queue/`)

The agent's cross-session learning. Filled silently by the `self-improvement-curator`
skill and reviewed via the `/evolve` slash command. Canonical schema: `_SCHEMA.md`
Section 15.

## Why a directory (not one file)

Each captured signal is its **own file**. On a team, multiple developers' agents
capture signals concurrently — one-file-per-signal means concurrent captures touch
different files, so they **never merge-conflict**. There is **no shared `IMP-NNN`
counter** (a shared counter collides when two people capture at once). State
(pending/applied/...) lives in each file's frontmatter, so changing a status is an
edit to one small file, not a contended rewrite of a monolith.

## File naming = the ID

```
IMP-YYYYMMDD-<short>.md
```

- `IMP-` prefix — greppable, signals "improvement entry".
- `YYYYMMDD` — capture date (chronological, sortable in `ls`).
- `<short>` — 4 lowercase base36 chars (`0-9a-z`) generated locally with no
  coordination. Before writing, the agent checks the filename does not already
  exist; on the rare clash it regenerates. This is a "human-friendly GUID":
  collision-free without a shared counter, yet short enough to say in review
  ("apply IMP-20260601-a3f8").

The `id:` frontmatter field MUST equal the filename stem. The filename is the
single source of truth — there is no counter to increment anywhere.

Only `IMP-*.md` files are entries. This `README.md` is not an entry; all state
queries glob `IMP-*.md` so they never count the README.

## Entry format

Frontmatter holds the scannable metadata; the body holds the human-readable prose.

```markdown
---
id: IMP-20260414-a3f8
detected: 2026-04-14
signal_type: correction          # correction | confirmation | decision | friction | challenge
scope: rule                      # rule | skill | wiki | schema | active-context
target: .sumela/rules/backend_standards.md
provider_context: claude-opus-4-8
confidence: high                 # high | medium | low (low is never written)
status: pending                  # pending | applied | superseded | rejected
---

## Proposed Change

EF Core queries with 3+ joins must explicitly declare `AsSplitQuery()`.

## Evidence

Session 2026-04-14: N+1 + Cartesian explosion caught; user approved AsSplitQuery.
```

**Status-specific frontmatter (added in place when status changes):**

| Status | Extra fields |
|---|---|
| `applied` | `applied: YYYY-MM-DD`, `last_validated: YYYY-MM-DD`, `challenges: [IMP-ID, ...]` |
| `superseded` | `superseded_by: IMP-ID`, `superseded_at: YYYY-MM-DD` |
| `rejected` | `rejected_at: YYYY-MM-DD`, `rejection_reason: <text>` |
| `pending` (deferred) | `deferred_at: YYYY-MM-DD` (status stays `pending`) |
| `signal_type: challenge` | `supersedes: IMP-ID` (the applied entry it challenges) |

## Lifecycle

- Entries are created `status: pending`. Never auto-applied — `/evolve` is the
  human approval gate.
- Status changes are edits to the entry's frontmatter **in place** (the file does
  not move). `superseded`/`rejected` entries are **kept** (historical accuracy);
  never delete an entry manually.
- Querying state is a directory scan, e.g. pending count:
  `grep -l "^status: pending" IMP-*.md | wc -l`

See `_SCHEMA.md` Section 15 for signal types, confidence thresholds, the
challenge/supersede flow, the dual-approval model, and `_LOG.md` integration.
