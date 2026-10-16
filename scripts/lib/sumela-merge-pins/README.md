# Merge pins

A clean three-way merge can still be wrong. `git merge-file` keeps your local lines and takes
upstream's changes, but it does not know that a line your fork deleted was a safety rule, or that
a line your fork kept was retired on purpose. A merge pin names text that a merged CORE
instruction file must contain, or must not contain, after an upgrade [RQ-21].

`scripts/update.sh` reads the pins from the **new release's** tree (never from your install), so a
release always checks its own merges.

## Format

One file per pinned CORE file: `scripts/lib/sumela-merge-pins/<name>.pins`, where `<name>` is any
readable name (for example the skill's directory name). UTF-8, LF line endings (a CR before a line
end is ignored).

```text
# path: .sumela/skills/example-skill/SKILL.md
# since: 0.20.1
require	<literal text the merged file must contain>
forbid	<literal text the merged file must not contain>
```

- `# path: <CORE path>`: exactly one such line, the file's path relative to the install root. A
  pins file without exactly one `# path:` line pins nothing.
- `# since: <version>`: the release that added the pin. Informational.
- `require<TAB><literal>` and `forbid<TAB><literal>` rows, any number, in any order. The literal is
  everything after the first TAB, matched byte for byte (case-sensitive) as a substring of one line
  of the merged file. It cannot span lines.
- Other lines starting with `#`, and blank lines, are ignored.
- A row the updater cannot read (no TAB, an empty literal, a kind other than `require` or `forbid`)
  counts as a violation, never as a pass.

## What the updater does with them

- Pins apply to a **merge** result, the row where you and upstream both changed the file and
  `git merge-file` merged cleanly, and to an edited `.merge` you install with `[m]erged`.
- They do not apply to `apply` (upstream's own copy, which satisfies its own pins), nor to files
  that are kept (your copy is never rewritten).
- The first violation turns a `merge` row into a `conflict` with the reason
  `pin: missing <literal>` or `pin: forbidden <literal>`. Your file stays as it is, the merged
  result goes to `.sumela/.upgrade/<path>.merge` and the reason to `.sumela/.upgrade/<path>.pin`.
  You then decide: keep yours, install an edited merge, or take upstream's copy.

## Ownership

A pins file arrives with the release that changes its CORE file: the task that rewrites an
instruction file owns that file's pins, otherwise the release task does. Pin the sentences whose
loss would change behavior (a security rule, a gate, a "never" clause), not wording.
