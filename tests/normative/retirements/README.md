# Normative retirements

`tests/test_normative_floor.py` checks that every non-blank line removed from a unit since the
previous release tag was either moved or retired. This directory holds the retirements: one
reviewed row per removed line that is not moved verbatim. Moves are declared in `../moves/`, which
also lists the units and their slugs.

## Format

There is one directory per release, named for the release the change ships in, without the `v`.
Inside it there is one file per unit, named for the unit's slug: `<X.Y.Z>/<unit-slug>.tsv`, for
example `0.20.1/sumela-prompt.tsv`. Each row has three TAB-separated fields:

```text
line<TAB>reason<TAB>replacement
```

- `line` is the removed line, stripped of leading and trailing whitespace, otherwise verbatim.
  Write one row per removed copy.
- `reason` says why the line goes. It is required.
- `replacement` names the text or the place that now carries what the line said. Write `-` when
  nothing does.

A line is **normative** when it matches
`MUST|NEVER|ALWAYS|MANDATORY|CRITICAL|REQUIRED|BEFORE|STOP|ONLY|NOT|binding|do not`
(whole words, any case). A normative line needs a replacement, or a reason that says why there is
none and contains `no replacement`, for example `no replacement: the step it gated is gone`.

Blank lines are skipped. A line that starts with `#` and holds no TAB is a comment. A removed
Markdown heading still becomes a row, because a row always holds TABs.

## What fails

- A removed line with neither a move nor a row ("unaccounted").
- A reflowed paragraph, until each original line has a row. Joining two lines removes both of
  them; the usual row is `reflowed` with the new line as the replacement.
- A placeholder left in a row: `REASON?` or `REPLACEMENT?`.
- A stale row, one that accounts for no removed line: the line is still in the unit, the row has a
  typo, or there are more rows than removed copies.
- A file named for a slug that is not a unit.

Rows count while their release is newer than the reference tag (see `../moves/README.md`).

## Writing rows

```bash
python3 -I tests/test_normative_floor.py --suggest <unit>   # skeleton rows, with placeholders
python3 -I tests/test_normative_floor.py --summary          # per-release counts
```

`--suggest` takes a slug, a unit path or a file inside a unit. It names the file to append to;
`--release X.Y.Z` picks another release. Before the release task, with no rows filed yet, the
release it names is a guess (the next patch release), and it says so: pass `--release` for the
release the change ships in. Replace every placeholder before you commit.

The test reads the files git would track; ignored files and OS or editor droppings never count
(see `../moves/README.md`).

## The release gate

When `.sumela/VERSION` moves past the reference tag, in the release task, CHANGELOG `[Unreleased]`
must hold one `(vX.Y.Z)` bullet that names every unit with retirements in that release, with its
counts, and every unit with lines moved out of the units (see `../moves/README.md`):

```text
normative: <slug> <n>/<m>
moved out: <slug> <k>
```

Here `n` is the number of retired normative lines, `m` the number of all retired lines of that
unit, and `k` the number of its lines moved to a file that is not a unit. `--summary` prints the
exact text to paste. A bullet that only says "normative" fails, and so do counts the rows do not
have. Before the release task the gate is silent, so intermediate tasks stay green.

At release time every row must be filed under `.sumela/VERSION`. Rows filed for a release that is
newer than the reference tag but older than VERSION fail, because no release gate would ever cover
them. Rows filed for a release newer than VERSION fail too: they account for lines removed in the
release being cut, and once its tag exists they would turn stale. Move them into the directory of
the release being cut.
