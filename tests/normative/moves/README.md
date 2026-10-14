# Normative moves

`tests/test_normative_floor.py` checks that every non-blank line removed from a unit since the
previous release tag was either moved or retired. This directory declares the moves. Retirements
live in `../retirements/` (see its README).

## Format

There is one file per release, named for the release the change ships in, without the `v`:
`<X.Y.Z>.tsv`, for example `0.20.1.tsv`. Each row has two TAB-separated fields:

```text
src_unit<TAB>dst_unit
```

- `src_unit` is the unit the lines left, given as its slug or its path (see the table below).
- `dst_unit` is where the lines went: a unit slug or a unit path, or a file that is not a unit
  but still works as instruction text. That is a Markdown file (its name holds `.md`, as in
  `task.md.template`) under `.sumela/` or `docs/second-brain/template/`, or a root `*.template`
  file such as `CLAUDE.md.template`. The file must exist, and git must not ignore it.

Any other destination fails, for example `CHANGELOG.md`, a test file or a note that no session
reads. A line parked there no longer instructs anyone, so it is a retirement: write its row in
`../retirements/`.

Blank lines and lines that start with `#` are comments.

## What a row accounts for

A row lets a line removed from `src_unit` pass when the same line was added to `dst_unit` since
the reference tag. Lines are compared stripped of leading and trailing whitespace. Each added copy
accounts for one removed copy. So a destination that already held the line does not count, and
neither does an edited copy: a move is verbatim. A row that accounts for no removed line is stale,
and it fails.

A line moved within its own unit needs no row. Moving it to another place in the file, or to
another `*.md` file of the same skill directory, is not a removal.

## Lines moved out of the units

A line moved to a file that is not a unit leaves the floor: the test does not watch that file,
so a later edit there goes unchecked. `--summary` lists every such line under its release, and
at release time the CHANGELOG bullet names the count per source unit, next to the retirement
counts (see `../retirements/README.md`):

```text
moved out: <slug> <k>
```

## Units

| Unit | Slug |
|---|---|
| `.sumela/sumela-prompt.md` | `sumela-prompt` |
| `.sumela/skills/<name>/` (every `*.md` in it) | `<name>` |
| `.sumela/memory-plugins/<p>/` (every `*.md` in it) | `<p>` |
| `.sumela/rules/<rule>.md` (the 7 core rules) | `<rule>` |
| `AGENTS.md.template` | `agents-md-template` |
| `docs/second-brain/template/wiki/_SCHEMA.md` | `wiki-schema` |

## Which files count

A file counts while its release is newer than the reference tag. The reference tag is the previous
final tag: `git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-rc.*' HEAD`. Files of
older releases are history: they stay in the repository, and the test ignores them.

The test reads the files git would track: committed ones, and new ones that no ignore rule
covers. Ignored files, and OS or editor droppings such as `.DS_Store`, `name~` or `.name.swp`,
never count. Any other file here fails as an unexpected entry.

## Example

A release moves the task-record instructions out of the contract into a sibling file of
`using-second-brain`. `0.20.1.tsv` holds one row:

```text
sumela-prompt	using-second-brain
```

Every contract line that now appears verbatim in `.sumela/skills/using-second-brain/` passes.
Every line that was reworded on the way needs a retirement row instead.
