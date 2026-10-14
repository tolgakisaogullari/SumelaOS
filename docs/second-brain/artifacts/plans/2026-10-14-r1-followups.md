# Release 1 follow-ups (open items found while implementing)

Companion to `2026-10-14-r1-second-brain-foundation-plan.md`. Each item names where it was
found and the task that should absorb it. Remove an item in the commit that resolves it.

## A. Review findings not yet applied

The fix agents received a truncated findings list for two tasks. All critical and important
findings were applied; these minor ones were not.

| Task | Finding | Summary |
|---|---|---|
| R1-13b | R13b-07 | A quoted `{PROMPT}` placeholder is accepted and silently corrupts runs |
| R1-13b | R13b-08 | `$CMP_DIR` is a logical path containing `//` on a default macOS `TMPDIR` |
| R1-13b | R13b-09 | The rule-phrase list misses common paraphrases (false fails in C3, C5) |
| R1-13b | R13b-10 | The shell write heuristic over-detects and misses writes (C5 ordering) |
| R1-13b | R13b-11 | Mismatched baselines only warn; the bypass refusal misses `--permission-mode auto` |
| R1-13b | R13b-12 | A duplicated `--scenario` reuses run directories with a confusing error |
| R1-13b | R13b-13 | Small accuracy gaps: XDG wording, handoff-file fallback scope, a hidden missing-handoff note, no re-read of the saved result |
| R1-03 | F8 | The `files` reader turns non-array shapes into paths (only the visible part was applied) |
| R1-03 | F9 | An interrupted record write leaves a temp file that is not gitignored |

## B. Pre-existing defects found during Release 1 work

1. **Windows PowerShell 5.1 cannot parse five shipped scripts** (found by R1-02):
   `scripts/setup.ps1`, `setup-memory.ps1`, `status.ps1`, `sync-mirrors.ps1`, `update.ps1`. They
   are UTF-8 without a BOM and contain non-ASCII characters, so 5.1 reads them as ANSI and a
   string ends early. `powershell -File scripts/setup.ps1` (as ADOPTION_GUIDE documents) fails
   on such machines. The CI 5.1 parse step tolerates exactly these five by name; each owner
   deletes its line when fixing the file. `update.ps1` → R1-06; the other four need a task.
2. **Consumer CI template** in `scripts/setup.sh:~1212` and `scripts/setup.ps1:~990` parses
   `.ps1` files with a loop that never enters `.sumela/` on Linux, and its `bash -n` skips the
   installed hooks. Owner: R1-07 or R1-28.
3. **pre-commit skips renames and deletions**: `.sumela/git-hooks/pre-commit` uses
   `git diff --cached --diff-filter=ACM`, so a commit whose only agent-surface changes are
   renames or deletions is not validated (R1-12 review F7, verified, not applied).
4. **Control-weakening list**: add `SUMELA_DISABLE_PRECOMMIT=1` to the lists in
   `.sumela/skills/secure-coding-standard/SKILL.md` (line ~16 and the step-7 grep ~99) and in
   `.sumela/rules/security_protocol.md` (R1-12 review F2).
5. **Monorepo-subdirectory installs**: the `wiki_pages` and `code_chunks` prunes never match
   and the incremental code ingest skips changed files, because the hook passes
   repo-root-relative paths (R1-12 review F6).
6. **Self-modification guard**: the gitignored provenance record outlives the upgrade commit,
   so the guard vouches for any changed path listed in its `files` (R1-03). Consider with the
   Release 2 review work.
7. **Doc alignment**: the plan's R1-03 text and the spec still describe the wider
   "preserve every path in `files`" rule; the library header is the narrower, correct one.

## C. Operational notes

- The compliance harness (R1-13b) refuses Claude Code older than 2.1.257 unless
  `--allow-unfenced-reads` is passed; update Claude Code before the R1-15 old-text baseline.
  The baseline and the candidate must run on the same version.
- CI runs the Git Bash suites twice (plain and tr-TR); watch the windows job's 60-minute limit.
- Release bullets (R1-14, R1-32, R1-41) must also carry `moved out: <slug> <k>` when lines move
  to a non-unit instruction file; the normative-floor gate prints the exact text.
