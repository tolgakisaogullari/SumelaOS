# Evaluation harnesses (source-only)

Maintainer-run measurements behind the quality gates of the Release-1 plan
(`docs/second-brain/artifacts/plans/2026-10-14-r1-second-brain-foundation-plan.md`, §6.2).

- **Not shipped.** `tests/` is not one of the updater's CORE directories, so nothing here reaches a consumer.
- **Not run by CI.** The evaluations read a private clone or call a model, so CI never runs them. CI runs only their self-tests, which `tests/smoke.sh` discovers.

| Path | Gate | What it measures | Self-test |
|---|---|---|---|
| `wiki-retrieval-replay.sh` | Q5 / A14 | Whether the second brain's read path surfaces the prior specs, plans and decisions that merged specs cite | `tests/test_replay_harness.sh` |
| `compliance/` | Q19 | Whether an agent following the instruction text honours rules and decisions across sessions; see `compliance/README.md` | `tests/test_compliance_harness.sh` |

## Retrieval replay (A14)

### The question

When an agent starts a spec, does the second brain put in front of it the prior work that the spec ends up citing? The replay answers this from history, without a model.

It takes the newest N specs merged into a base branch. It rebuilds the second brain as it stood when each spec was written, and queries it with the spec's title alone. It then counts how many of the spec's citations appear among the first 20 candidates.

- **`--path old`** measures the v0.19 read path: the boot files. The v0.20.0 baseline (R1-15) uses it.
- **`--path new`** measures the v0.20.1 lookups `catalog` and `search`. The v0.20.1 gate (R1-33) uses it.

### Usage

```bash
bash tests/eval/wiki-retrieval-replay.sh --repo <clone> --n 30 --path old|new \
     [--base <ref>] [--terms-file <f>] [--wiki-dir <path>] [--wiki-tool <path>]
```

| Option | Meaning |
|---|---|
| `--repo <clone>` | The top level of a full git clone, with a work tree or bare. The harness never writes to it. A subdirectory is refused (exit 2), and so are shallow and partial clones (exit 3). |
| `--n <N>` | How many of the newest merged specs to replay. Default 30. |
| `--path old\|new` | Which read path to measure. Default `old`. |
| `--base <ref>` | The branch whose first-parent history holds the merged specs. Default `origin/HEAD`, else `HEAD`; in a clone with a work tree, that fallback prints a note, because `HEAD` may be a feature branch whose unmerged specs would count as merged. **Pass a commit SHA** to pin the window, so that an old-path and a new-path run replay exactly the same specs. |
| `--terms-file <f>` | Extra query terms; see the line formats below. |
| `--wiki-dir <path>` | The repo-relative wiki directory. Default `$WIKI_PATH`, else `docs/second-brain/wiki`. Specs and plans are read from the sibling `artifacts/` directory. |
| `--wiki-tool <path>` | The `sumela-wiki.sh` that `--path new` runs. Default: the copy in this checkout, `.sumela/skills/using-second-brain/scripts/sumela-wiki.sh`, which ships in v0.20.1. |

Terms-file lines take four forms:

- `<words>` adds the words to every spec's query.
- `<spec-file-name><TAB><words>` adds them to that one spec.
- `-<words>` drops the words from every spec's title words. Use it, for example, to drop "design" or "the" for a wiki in your language.
- A line starting with `#` is a comment.

### What is measured

**The window.** The specs are the newest N `*.md` files added under `<artifacts>/specs/` on the base's first-parent history:

- a spec that came in through a merge counts at the merge;
- a renamed spec is not a new one;
- specs on unmerged branches are never replayed, and neither is a spec added and removed again on a branch before its merge;
- a spec removed and added again counts once, at its newest addition;
- `README.md`, names starting with `.` or `_`, and files that are not `*.md` are not specs.

**The parent commit.** For each spec, the parent commit P is the first parent of the commit that added the file. That is the tree its author worked on. It may be on the feature branch, so P is not necessarily the base before the merge. The spec's text is read as merged. When only a merge commit adds the file, P is the merge's first parent; any other spec whose adding commit cannot be found stops the run (exit 1). Paths are matched literally, so `x[1].md` never stands for `x1.md`.

**The cited set.** The cited set holds two kinds of item:

- the spec and plan files the spec references, as markdown links (including same-directory links), wikilinks or bare paths;
- the `AD-n` and `TD-n` IDs it names. `AD-05` and `AD-5` are the same ID.

An item counts only if it already existed at P: the file was present, or the ID appeared somewhere in the wiki or the artifacts. This excludes the spec's own new decisions and its own later plan, which no read path could have surfaced. A spec added by a root commit therefore has nothing prior to it. It is replayed but not scored.

**Cross-cutting ADs** [RQ-22] are the ADs that at least 3 of the N specs cite as prior context. An AD counts for a spec only if it already existed at that spec's P, so an AD that one of the N specs introduces counts only its later citers. TD IDs are never cross-cutting. The cross-cutting ADs get their own figure, because a decision such as "all outbound calls go through one client" does not match a feature's nouns.

**The terms.** The query is built from the spec's H1, or from its file name without the date if it has no H1:

- Latin letters are folded to ASCII and lower-cased, so `İade`, `IADE` and `iade` match each other.
- Letters of other scripts are kept as written, including Latin Extended-C, Glagolitic, Coptic and Tifinagh (U+2C00–2DFF).
- Non-ASCII punctuation separates words:
  - U+0080–00BF (the no-break space, guillemets, the middle dot, `©`), and `×` and `÷`;
  - U+2000–2BFF (dashes, quotes, the ellipsis, arrows and other symbols) and U+2E00–2E7F (supplemental punctuation);
  - the CJK punctuation of U+3000–303F, such as the ideographic space, `、`, `。` and the corner brackets, but not the characters of that block that are parts of words, such as the iteration mark `々`;
  - the fullwidth punctuation of U+FF01–FF65, such as `（`, `）`, `：` and `，`.
- A term is a word of at least 3 characters (not bytes) that is not a number. At most 8 words are taken from the title.
- The terms file then adds and drops words.

**The old path.** The harness reads `_INDEX.md`, `active-project-context.md` and `_SEARCH_INDEX.md` at P:

1. A line matches when it contains a term as a fixed string. This is `grep -i -F`, but with folding applied to the line as well as to the terms. So the baseline is grep at its best, and the new path has to beat that.
2. Lines rank by the number of distinct terms they contain, then by file order and line number.
3. The candidates are the spec and plan links and the AD/TD IDs on the ranked lines, in that order. The spec under replay is never its own candidate.

A boot file that is a committed symlink is not read (see "Read-only, private, offline"). A parent commit with no boot file contributes no candidates and is counted: one note on standard error gives the count, and the run is refused (exit 3) when no parent commit has a boot file. A typo in `--wiki-dir`, or a `WIKI_PATH` exported for another project, would otherwise score 0.000 and pass for a weak baseline.

**The new path.** The harness extracts the wiki and the artifacts at P into a temp tree. It runs the tool on that tree with `-C <tree>`, three times: `search "<terms>"`, `catalog specs --match "<terms>"` and `catalog plans --match "<terms>"`. A spec with no terms gets no tool call.

- It reads R1-18's documented output shapes: catalog lines `<date> · <slug> · <H1>` and search lines `<score> · <path> · <terms> · <first line>`. For a search hit on a wiki page, it takes the IDs from the first matching line.
- The three lists are interleaved in this order: the first search hit, the first spec, the first plan, then the second of each, and so on.
- If no output line of the whole run parses, the run fails rather than scoring 0.
- The tool sees only the replay tree. `WIKI_PATH` is set to the replayed wiki directory, and `SUMELA_SUMMARIES_DIR` is unset, so live summaries are never read. `GIT_CEILING_DIRECTORIES` keeps any git repository around the temp directory out of its reach.
- Its standard error is never dropped. Each distinct line it printed is shown once, prefixed `wiki-retrieval-replay: sumela-wiki.sh:`. If a call fails, the run stops (exit 1) and shows that call's last lines.
- A parent commit without the wiki directory is counted the way the old path counts missing boot files, with the same note and the same refusal.

> This part was written against the plan's contract, before the tool existed, and has been tested only with a stub. R1-33 must check it against the real tool first.

**The scores.** Per spec, recall is the share of its cited set that appears among the path's first 20 distinct candidates. The run reports two figures:

- `recall@20` is the mean of that recall over the specs whose cited set is not empty.
- `crosscut_recall@20` is the same mean, restricted to the cross-cutting ADs, over the specs that cite one.

Either figure is `n/a` when no spec qualifies.

### Output and exit codes

Standard output gets exactly one line of aggregates. It names no spec, term, ID, path or branch:

```text
recall@20=<x> crosscut_recall@20=<y> specs=<n> path=<old|new>
```

`specs=<n>` is the number of specs replayed. Error messages on standard error may name files or refs of the clone.

Standard error also carries notes, each prefixed `wiki-retrieval-replay: note:`. They report that:

- the default base fell back to `HEAD`;
- k of n parent commits had no boot file (old path) or no wiki directory (new path);
- files hidden by an `export-ignore` attribute were read with `git cat-file`;
- committed symlinks were left out of the replay trees.

The wiki tool's own standard error follows them (see "The new path").

| Exit | Meaning |
|---|---|
| 0 | OK |
| 1 | Error: git or the wiki tool failed, the tool's output never parsed, or the commit that added a spec was not found |
| 2 | Usage, including a `--repo` below the top level of its clone |
| 3 | Precondition refused: not a git repository, a shallow or partial clone, unknown base, no merged specs, no boot file (old path) or wiki directory (new path) at any parent commit, or no wiki tool for `--path new` |

### Read-only, private, offline

- **Nothing is written to the clone.** Each parent commit's files reach a temp directory through `git archive`. Files that an `export-ignore` attribute hides from the archive are read with `git cat-file`, and the run says so. The temp directory is removed on exit, also after an error.
- **Committed symlinks are left out.** A link may point anywhere, the clone included. So the harness deletes every symlink from the replay trees, never fills one in, never writes through one, and says how many it left out.
- **No git call can write either.** Every git call runs with optional locks, auto-gc and background maintenance off.
- **Shallow and partial clones are refused (exit 3).** A shallow clone's boundary commit would seem to add every older spec, so the window would hold the wrong specs. In a partial clone, git fetches a missing blob from the remote on demand, and only recent git releases honour the switch that turns this off. Run `git fetch --unshallow`, or use a full clone.
- **Offline.** There are no network or model calls.
- **Cost.** A synthetic history with 1 MB boot files replays 30 specs in about 11 seconds on a laptop.
- **Keep the record private.** Store the result line together with its window privately: the clone, the base SHA, N and the terms file. This repository is public; never commit them here.

### Running it for a release

1. **v0.20.0 baseline (R1-15).** Fix the window first: `git -C <clone> rev-parse <base>`. Then run the old path:

   ```bash
   bash tests/eval/wiki-retrieval-replay.sh --repo <clone> --n 30 --path old --base <sha> [--terms-file <f>]
   ```

   Keep the line privately, with the SHA, N and the terms file.

2. **v0.20.1 gate (R1-33).** Run from a checkout of the release candidate, where `sumela-wiki.sh` exists. Use the same clone, `--base <sha>`, `--n` and terms file, with `--path new`. The gate passes when:
   - `recall@20` is at least 0.7 and at least the old path's;
   - `crosscut_recall@20` is at least the old path's.

**A planned third figure** [RT-16]: from v0.20.1, the plan adds a figure for the task-decision IDs that merged plans cite. The harness does not compute it yet, because it needs the ID format of R1-19's task records.

### Limits

- **Title-only queries.** The query is the spec's title alone. A real session also has the user's request and the conversation.
- **Substring matching.** Matching follows `grep -F`: a term matches inside a longer word, so "port" matches "report".
- **Scripts.** Letters outside the Latin fold table match only as written, and their case is not folded. A script written without spaces between words matches only as whole runs between punctuation. Punctuation outside the blocks listed under "The terms" counts as part of a word.
- **Symlinks.** A boot file or wiki page committed as a symlink is not replayed, even when its target is inside the repository.
- **Identity by file name.** Specs and plans are identified by file name, so two files with the same name in different directories count as one item.
- **ID forms.** Only `AD-n` and `TD-n` are recognised. In a range such as `AD-01..AD-12`, only the two ends are recognised.

### Self-test

`tests/test_replay_harness.sh` builds synthetic histories in which every citation's retrievability is known by construction, and checks each figure against a hand-computed value. It covers:

- the merge-commit parent, the time point (nothing later than P is read), the prior filter and the cross-cutting subset;
- ranking, and the cut at exactly 20 on both paths: a cited item at slot 20 counts and one at slot 21 does not;
- the new path's interleave order;
- the term rules (characters, separators, the 8-word cap), ID forms, the terms file, CRLF, a byte-order mark and `export-ignore`;
- the window rules, bare and `origin/HEAD` clones, and the base window;
- the new path through stub tools: its environment, its standard error, and a tree that never holds the spec under replay;
- missing or truncated inputs, usage and precondition exits, and the cleanup of the temp directory;
- the read-only guarantee, also with committed symlinks that point into the clone, with a check that its write detector really detects writes;
- output that is aggregates only.

It needs only bash and git, runs in under half a minute, and runs in `tests/smoke.sh` through test discovery.
