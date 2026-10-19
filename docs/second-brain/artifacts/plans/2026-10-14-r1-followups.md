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
| ~~R1-03~~ | ~~F9~~ | ~~An interrupted record write leaves a temp file that is not gitignored~~ — resolved in R1-07 (`.sumela/*.sumela-tmp.*` in the gitignore list) |
| R1-31 | review 4 | Filtering `_tasks/`/`_team/` deletions leaves points indexed before v0.20.0 un-pruned until R1-38's `--reconcile`; R1-38 must narrow this filter when closed records become ingestible, and the 0.20.0 notes should say existing `_tasks/`/`_team/` pages stop being indexed |
| R1-08 | verify-2 #1 | Test gap: no lint case for a quote opened mid-word (`--source a"b --check"`); the code refuses it, but mutant `sh_quote_in_word` survives — add the case to both suites |
| R1-08 | verify-2 #2 | Nit: URL normalisation treats a local `x` and `x.git` as the same repository, so `--trust-origin` cannot name a local `x.git` fork of upstream `x` (safe: the plan is refused) |
| R1-03 | via R1-04 | The provenance library does not clean up its own scratch directory when interrupted (R1-04 routes template-less `mktemp -d` into its work dir as a workaround) |
| R1-31 | review 6 | Pre-existing: an extra ingest dir that contains the wiki brings back `_INDEX`, `_LOG`, `_SEARCH_INDEX`, `_SCHEMA` and `_improvement-queue/` (apply the resolved-path exclusion to the wiki-only exclusions too) |

## B. Pre-existing defects found during Release 1 work

1. **Windows PowerShell 5.1 cannot parse five shipped scripts** (found by R1-02):
   `scripts/setup.ps1`, `setup-memory.ps1`, `status.ps1`, `sync-mirrors.ps1`, `update.ps1`. They
   are UTF-8 without a BOM and contain non-ASCII characters, so 5.1 reads them as ANSI and a
   string ends early. `powershell -File scripts/setup.ps1` (as ADOPTION_GUIDE documents) fails
   on such machines. The CI 5.1 parse step tolerates exactly these five by name; each owner
   deletes its line when fixing the file. **Fixed in R1-07:** `setup.ps1`, `setup-memory.ps1`
   (ASCII-only, removed from the exemption list). Remaining: `update.ps1` → R1-06; `status.ps1`
   → R1-11; `sync-mirrors.ps1` needs a task.
1b. **MUST FIX BEFORE v0.20.0 SHIPS — `setup.ps1` writes ANSI on Windows PowerShell 5.1.** Now
   that 5.1 can parse it, its ~50 `Get-Content`/`Set-Content`/`Add-Content` calls use 5.1's
   default ANSI encoding: template copies survive byte for byte, but text the script itself
   writes (em-dash markers, non-ASCII project values) lands as cp1252, and validate's
   post-setup marker check would flag the `.gitignore` marker. Replace them with
   `[IO.File]` UTF-8-without-BOM reads/writes (R1-07 follow-up; assign to R1-14 at the latest).
1c. **Tests talk to the real local Qdrant.** Setup/update fixtures (incl. smoke's setup runs)
   create collections on `localhost:6333` when Qdrant is up; about 19 all-empty test groups
   (`inst-*`, `proj-*`, `skipall-*`, `applyall-*`, `a-*` …) were found on the maintainer's
   machine. Every fixture must export `QDRANT_HOST=127.0.0.1 QDRANT_PORT=1` (R1-04's `fx_env`
   already does); then offer the maintainer a one-time cleanup of the empty test groups.
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

7b. **Git for Windows' awk (MSYS2 gawk) opens files and stdin in TEXT mode** (found by the
   Windows CI run of R1-07): any bash script that reads a tracked file with awk and writes the
   result back silently turns CRLF into LF there. R1-07 now passes `-v BINMODE=3` to every awk
   and refuses a rendering that lost CRs. **Audit every other awk that rewrites files** —
   `scripts/update.sh` (R1-04; its one Windows failure may be this), `scripts/sumela-migrate.sh`,
   `scripts/lib/sumela-provenance.sh`, `scripts/lib/sumela-gitignore.sh`, the hooks — and
   apply the same rule, with a stub-awk test like R1-07's.
8. **Hooks checked out with CRLF on Windows**: a v0.19 install on Windows (core.autocrlf=true)
   has CRLF hook scripts (`env: bash\r`), which the R1-08 e2e hit through a rollback's
   `git checkout`. R1-12's eol pins fix new checkouts; existing installs need the pins plus a
   re-checkout of the hooks during the upgrade (decide in R1-14's notes).

## C. Operational notes

- **R1-06 must:** add the v0.20 updater marker (`Write-SumelaRecord`) to `update.ps1` (without it
  a release would never install its own PowerShell updater), and mirror R1-04's
  `--allow-untagged-source`, exit 6 (re-run pending) and the temporary-index HEAD read.
- **R1-10 must:** import the Day-0 baseline, which sits under the full-length sha256 state key,
  not R1-03's 16-character key.
- **Release tasks (R1-14/R1-32/R1-41) must:** keep the token report's framework-file manifest
  current (it fails once VERSION passes the last tag), and add a scripted equivalent for any new
  `run: -` migration step (the notes e2e names it otherwise).
- R1-08's `0.20.0-01` rollback (`--drop-baseline`) has no end-to-end test until R1-10 exists.

- The compliance harness (R1-13b) refuses Claude Code older than 2.1.257 unless
  `--allow-unfenced-reads` is passed; update Claude Code before the R1-15 old-text baseline.
  The baseline and the candidate must run on the same version.
- CI runs the Git Bash suites twice (plain and tr-TR); watch the windows job's 60-minute limit.
- Release bullets (R1-14, R1-32, R1-41) must also carry `moved out: <slug> <k>` when lines move
  to a non-unit instruction file; the normative-floor gate prints the exact text.
