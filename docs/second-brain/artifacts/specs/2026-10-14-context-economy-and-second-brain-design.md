# Context economy and second-brain correctness: program design

| | |
|---|---|
| **Status** | Program design, **revised after three adversarial reviews** with distinct lenses: [RQ] output quality and agent compliance, [RU] consumer upgrade and integration, [RT] team workflow and knowledge semantics. All 78 findings were dispositioned: 69 accepted, 9 partially accepted, none rejected. No code has changed. It reuses what the adversarially reviewed plan [FP] and wiki redesign [RD2] validated, and applies the maintainer's decisions of 2026-10-14 (D-U1 to D-U6). **Next:** the maintainer answers DEC-1, DEC-2 and DEC-5 (§8) and signs off; Release 1 then starts with the plan's wave 0, which depends on none of them. |
| **Baseline** | SumelaOS v0.19.0 (`3732308`). Flagship consumer: v0.19.0, team mode, PR-only with merge commits, 11 locally modified ("forked") CORE files, about 9 active authors, about 1,330 remote-tracking refs (119 unmerged branches), 14 checkouts. |
| **Evidence** | Maintainer-private research. It holds aggregates only and is not in this repository:<br>• [SF] session forensics: one developer's machine; 68 main sessions, 548 subagent threads, 30,256 requests and 8.31B context tokens, 2026-09-13 to 10-13<br>• [H1] specs and plans, [H2] code comments, [H3] review, [H4] carried context<br>• [CR] consumer wiki reality<br>• [FP] integrated plan<br>• [RD2] wiki redesign v2 and its 34 dispositions<br>• [K] Karpathy's LLM-wiki idea file, cited as `K:<line>`<br>• [RQ], [RU], [RT] the three reviews of this design (2026-10-14), with reproductions |
| **Markers** | `[D-U1]` to `[D-U6]` mark every change against [FP] or [RD2] that one of the decisions below caused. `[RQ-nn]`, `[RU-Xn]` and `[RT-nn]` mark passages changed by an accepted review finding. Unmarked design carries over. Citations of the form `path:line` refer to this repository at v0.19.0. |
| **Units** | Budgets are in bytes. "% of context" and "% of cost" are shares of the [SF] corpus. The lenses overlap, so the shares do not add up. |

**The maintainer's decisions (2026-10-14):** **D-U1** order: second brain, then review, then plans, comments, handoff and memory; rtk and caveman out entirely; the brevity and precedence clause dropped. **D-U2** the listed options for the four measured findings are accepted. **D-U3** per-developer state stays, redesigned for eventual consistency. **D-U4** decisions survive every session of a multi-session task, whether project- or task-scoped. **D-U5** the consumer's agent can apply every release. **D-U6** no loss of output quality.

## Summary

The context goes mostly to repetition around the knowledge, not to the knowledge itself:
- **Review:** about 26–31% of spend, much of it in full re-runs that find nothing blocking.
- **Plans:** code written twice, reviewed in 80 KB slices; 8.2% of context with their reviewers.
- **Comments:** comment-heavy code re-read on every visit, 5.3% of context.
- **Continuity:** 8.4% of context, of which the carried history itself is 0.55%.

The second brain is a correctness problem. Its boot files are 604 KB and 777 KB, 79 of 114 reads of them failed, and the decision registers cannot be read whole. Task-scoped decisions travel on copy chains most sessions never receive. Today's updater silently overwrites forked CORE files when an agent runs it, and the 0.19 hooks keep advertising that updater to every teammate [RU-C2].

The program ships in three releases, in D-U1 order:
1. **v0.20.x:** an agent-safe, merge-capable upgrade path that also defuses the old updater, with version-agnostic, machine-readable migration notes; a privacy-safe measurement baseline; and a bounded, Karpathy-faithful second brain. One durable record per task carries its rules and decisions to every session, and shows them at the point of action. Per-developer state lives in single-writer files and converges under eventual consistency.
2. **v0.21.0:** review runs through a coordinator subagent, with panels sized to risk and at most one incremental re-review round.
3. **v0.22.x:** code-light plans with a mechanical pre-check, comment discipline configured by the consumer, and a lazy, pointer-style handoff with one-call bookkeeping.

Every behavior change is guarded by a full-line normative floor, read-before-acting triggers placed in always-loaded text, deterministic fixtures, an agent-compliance evaluation against the previous text, a canary on release-candidate tags against a saved baseline, and a one-PR rollback [RQ-02][RQ-13][RU-I6]. Risk-flagged work keeps full rigor.

## Prior context consulted

- [FP], [RD2] and their dispositions; [H1]–[H4]; [SF]; [CR]; [K]; [RQ], [RU], [RT] and their reproductions.
- Verified in this repository, at every cited line: the contract, the skills cited below, `scripts/update.{sh,ps1}`, `scripts/lib/sumela-gitignore.sh`, `reconcile-registry.py`, `status.sh`, `auto-update-memory.py`, `_lib.sh`, `post-checkout`, `review-report.md`, the wiki templates, `_SCHEMA.md`, `.gitattributes`, `tests/` and CI.
- Claude Code's sub-agents documentation (2026-10-14); git 2.50.1 merge tests of the per-developer layouts and of the task-record format.

---

## 1. Problem and measured evidence

### 1.1 What fills the context

| Lens | What is measured | Share |
|---|---|---|
| Session length | requests at ≥500K tokens | 60.2% of main context [SF] |
| By tool | Bash output 27.9, Read 14.9, thinking 9.9, system prompt plus tool schemas 8.2 (the `Artifact` schema alone 4.7), MCP 2.1, visible prose 1.8 | % of all context [SF] |
| SumelaOS instruction text | eager files, skills and rules, re-sent | 10.6–14.5% of all context [SF] |
| Review | per-task review plus final panel, including main-thread handling and the fixes they trigger | ≈26–31% of spend: panel 20.9–24.6%, per-task 5.5–6.7% [H3] |
| Specs and plans | the documents (3.65%) plus their review subagents | 8.2% of context, 7.6% of cost [H1] |
| Code comments | comment lines inside code the agents read (5.3%), plus writing, fixing, reviewing and rule text (1.7%) | 7.0% of context, 6.4% of cost [H2] |
| Continuity | everything that serves cross-session memory | 8.4% of context, 7.6% of spend; the carried history itself is 0.55% [H4] |
| Second-brain reads | wiki reads in main threads | ≈1.3% of main context [SF] |

**What the measurements say:**

- **Review: the panel is the bulk** [H3]. First runs average 6 lanes. Full re-runs cost 4.7% of spend, and 23 of 30 found nothing blocking. Custom lanes cost 2.8% of spend for 12 Critical or Important findings. The main thread receives about 1.7 deliveries per lane at about 440K context. Per-task review costs about 1.3M relative cost units per task, but catches the same class of issue earlier: later panels find about 55% fewer Important issues per lane.
  - **Counter-evidence** [RQ-15]. [H3]'s severity counts are heuristics. The flagship's 50 retained review reports tell a less comfortable story: 31 are round 2 or later, 10 of those carry Critical or Important findings (2 a Critical), and later rounds hold 35 Critical plus Important findings against 39 in first rounds. §C therefore keeps D-U2's one-round cap but adds escalation rules, fix-round benchmark cases and a pre-Release-2 classification of where later-round findings come from.
- **Plans: code is written twice** [H1]. 38.9% of plan bytes are fenced code, and 67% of a plan's distinct code lines reappear verbatim in the merged code. One plan-document review costs 23.2M context tokens: the reviewer reads an 80 KB plan in slices, then explores the codebase. Median plan size doubled from August (29 → 71 KB).
- **Comments: the cost is in re-reading them** [H2]. Landed application code carries 43.3 comment lines per 100 code lines (5.9 before agents), mostly structured doc comments the project's rule calls optional. One edit in six fixes only a comment, and those fixes double the text. Reviewers flag accuracy, not volume, and rated 41 of 48 comment findings Minor. The prose rule grew from 1 to 13 lines without bending the curve.
- **Continuity: the cost is in the machinery** [H4]. The 36 KB handoff manual is loaded in 62 of 68 sessions; 9 produce a handoff. Claude Code's auto memory (a 151-line index plus topic files) is 3.5% of context, with 517 of the index's 617 loads in subagent threads. Bookkeeping runs as about 15 round trips per summary-writing session at a median 606K context (2.4% of spend). The handoff prompt (median 11.7K chars) is longer than the summary it digests (8.4K), and the next agent reads both.

### 1.2 What changed

- **Model switch (2026-09-22):** thinking per main request rose 46%, `max` effort went from 20% to 36% of requests, and cost per request rose 10%.
- **Subagents:** p50 per session went from 1.5 to 6. Their share of weekly context went from 25–33% to 48–50%.
- **Framework reads:** they rose 54% in the first 30 requests. `context-handoff` grew from 18.5 KB to 36 KB. One consumer overlay rule grew from 11.8 KB to 104 KB, 3.84% of main context.
- **Artifacts:** plans doubled in size; comment density peaked at 53 per 100 in August; the wiki boot files grew by 39 and 52 KiB a week. [SF][H1][H2][FP §1.2]

### 1.3 Why the second brain is a correctness problem first

1. **Unreadable boot files.**
   - STEP 2 reads `_INDEX.md` and `active-project-context.md` whole in every session (`.sumela/sumela-prompt.md:44-45`).
   - On the flagship they are 604 KB and 777 KB. 79 of 114 main-thread Reads failed, on the 256 KB whole-file refusal or the 25K-token cap.
   - Bootstrap sees 0.3–0.4% of each, and that part is weeks stale [CR].
2. **Growth by design.**
   - `brainstorming/SKILL.md:78` and `writing-plans/SKILL.md:104` append one link per artifact to both files.
   - `context-handoff/SKILL.md:196-199` and `:252-255` add sprint markers.
   - Only `finishing-a-development-branch/SKILL.md:72` removes anything.
   - The index is read at session start (`using-second-brain/SKILL.md:20`), not at query time as in Karpathy's pattern (K:47). Nothing is "kept current" (K:11).
   - Of the merges that touch the two files, 70% and 62% conflict [CR].
3. **Unreadable registers.**
   - Three skills say to read the decision and debt registers whole: `brainstorming/SKILL.md:23`, `writing-plans/SKILL.md:14` and `systematic-debugging/SKILL.md:14`.
   - The flagship's ADR page is at 99.1% of the refusal limit, and the TD page is 512 KB.
   - So "MUST NOT contradict existing approved decisions" (`brainstorming/SKILL.md:23`) cannot be honored.
4. **Decisions ride copy chains.**
   - v0.19 writes task-scoped decisions to the plan's `## Task Ground Rules` block, to every session summary and to every handoff prompt (`context-handoff/SKILL.md:118-128`). Each handoff carries them forward by copying the previous one, and prunes by omission (`:130-134`).
   - Only 13 of 68 sessions start from a pasted handoff [H4], and bootstrap never reads summaries (`context-handoff/SKILL.md:440-441`).
   - 68 of 69 flagship sessions start on the base checkout, and 21 switch branch mid-session [RD2 §5.2]: a rule that is printed only "for the current branch" never reaches most sessions [RT-01].
   - A task without a plan has no durable home except its newest summary.
   - The SDD implementer prompt has no field for ground rules (`subagent-driven-development/implementer-prompt.md:9-14`). Only inline `executing-plans` reads them (`executing-plans/SKILL.md:16-22`), so the subagents that do the work may never see them.
5. **Per-developer state, as written, cannot work.**
   - The template keys one bullet per developer in a shared page (`docs/second-brain/template/wiki/active-project-context.md.template:26-33`).
   - On the flagship that section is 98.7% of a 777 KB file, and 162 of its 206 entries are closed.
   - Yet 26 of 68 sessions reached it: the need is real; the design is not [CR][RD2 §5.2].
6. **An agent cannot run upgrades safely** [D-U5].
   - The updater compares only local against upstream (`scripts/update.sh:234-245`) and applies everything when the prompt reads nothing (`update.sh:404-405`; `update.ps1:335-340`). An agent's shell has no terminal, so a consumer agent running it overwrites every forked file without asking (reproduced: EOF resolves to "apply all"). `[s]kip all` still stamps the new VERSION (`update.sh:487`).
   - The 0.19 hooks print `Update: bash scripts/update.sh` on every pull or checkout that sees a newer tag (`.sumela/git-hooks/_lib.sh:625`), so that updater stays one command away for every teammate and every pre-upgrade branch. Once its result is committed, no self-heal can see the loss, and a feature PR carries it to the base without a conflict [RU-C2].
7. **Bookkeeping has no commit point** [RQ-01][RT-19].
   - The execution skills forbid commits until finishing (`executing-plans/SKILL.md:59`, `subagent-driven-development/SKILL.md:64`), and the review gate hashes the tree (`requesting-code-review/review-report.md:29`, `:73-78`: "STALE → ALWAYS re-run").
   - Finishing already commits the session summary after the code commit (`using-second-brain/SKILL.md:199`), which moves `HEAD^{tree}` away from the reviewed tree before the ship gate checks it.
   - Any design that records decisions when they are made must say when those files are committed and why that never stales a review.

### 1.4 Limits of the data

- The transcripts come from one developer. The git evidence covers the whole team (9 authors).
- Epochs confound workload with version, and the August transcripts are gone.
- Effects of 5% or less cannot be detected by A/B comparison at this team's scale. The gates therefore rest on deterministic fixtures, benchmarks and a scripted agent-compliance evaluation, with observational metrics as guardrails [RQ-13].
- The remaining pre-v0.19 transcripts age out by 2026-10-20 (DEC-1).

---

## 2. Goals and non-goals

**Goals**
- **G1. A correct second brain:** every boot read bounded and whole; registers and catalogs readable at any size; growth stopped; per-developer state that converges; task decisions that reach every session of the task, at the points where the agent acts (session start, branch switch, worktree entry, each plan task, each subagent payload) [RT-01].
- **G2. Releases an agent can apply** [D-U5]: upgrade tooling that never overwrites a fork, including when the old updater is run by mistake [RU-C2], and machine-readable migration notes a consumer agent follows across any version jump, confirming before it acts [RU-I2].
- **G3. Less repetition:** fewer review re-runs, and fewer lanes where they yield little; review traffic out of the main thread; plans without duplicated code; fewer comments to re-read; manuals and bookkeeping loaded only when used.
- **G4. Measurement:** a privacy-safe report of quality and token metrics, baselined before each behavior release, with stated directions, margins and minimum samples [RQ-14].
- **G5. No loss of output quality** [D-U6]: every reduction is guarded, benchmarked, run as a canary, checked for agent compliance against the previous text, and reversible [RQ-13].

**Non-goals** [D-U1]
- rtk and caveman. There is no integration, no detection or data-store row in `status`, no policy text, no `--what-if` gate and no experiment recipe.
- The caveman-derived parts are dropped:
  - the brevity clause;
  - the precedence (authority) line, including its managed-policy carve-out;
  - the Concise output-style option.
- No "Fast Flow" or any third execution mode. SDD keeps Checkpoint and Flow.
- No change to model or effort policy, and no reduction of rigor on risk-flagged work.
- No shared cloud. State propagates through commits and local hooks [D-U3].

**Boundaries for the implementation**
- **Always:**
  - verbatim moves;
  - `.sh`/`.ps1` twins;
  - new tests invoked from `tests/smoke.sh`;
  - success gated on artifacts: every write that a later session depends on is verified by re-reading it [RU-C3];
  - every wiki-tool reader tolerates CRLF, and every writer writes LF [RU-C3];
  - a `sumela-` prefix on every new file under `scripts/` [D-U5], because a generic name collides with host scripts and the updater would treat the host file as CORE;
  - a reserved `_` prefix on every new directory under the wiki, for the same reason [RT-12].
- **Ask first:** moving security content on-demand; raising a ratchet pin; changing a review gate's semantics (DEC-5).
- **Never:** scripts writing to `~/.claude`; Python in a core path; `-ExecutionPolicy Bypass`; consumer-specific detail in this repository.

---

## 3. Quality guardrails and quality gates [D-U6]

### 3.1 Principles

| ID | Principle | Enforced by |
|---|---|---|
| QP1 | **Move, never delete.** Normative text moves byte-identically. In a unit that changed since the previous tag, **every removed non-blank line** is either moved (declared in a move manifest) or retired by a reviewed row naming its reason and its replacement [RQ-02] | `test_normative_floor.py`, move manifests, retirement rows |
| QP2 | **On-demand only behind an explicit trigger,** and the trigger lives in **always-loaded** text (the contract or an eager skill): "READ `<file>` BEFORE `<action>`". A trigger inside a lazy skill does not count [RQ-23] | invariant pins; read-before-acting counters |
| QP3 | **Security content never goes on-demand without a security-lens review.** The SECURITY MANDATE (`sumela-prompt.md:189`), the Correctness and Security lane and the `secure-coding-standard` load stay | invariant pins |
| QP4 | **Risk-flagged work keeps full rigor:** plan code, deep per-task review in both modes, a Deep panel, a full panel for large fix deltas. A task that rewrites how rules or decisions are read or written is itself `high:public-contract`, with exact before-and-after text [RQ-03] | risk taxonomy (§4.C); benchmarks |
| QP5 | **Deterministic before probabilistic:** mechanical checks move from model reading into scripts | fixtures |
| QP6 | **Escalate freely; de-escalate only on a reviewed classification,** which a concrete risk signal overrides. The security subset of the review keyword grep is never de-escalated [RQ-16] | sizing fixtures |
| QP7 | **Measure before changing behavior.** Baselines precede each behavior release; quality metrics gate, token metrics are reported; never gate on a share the plan moves | token report; §6 |
| QP8 | **Reversible:** one upgrade PR to revert; verbatim moves restore upstream mechanically, **one component at a time** [RQ-28]; a per-developer valve for review | §3.4 |
| QP9 | **The user ranks first** (`sumela-prompt.md:19`): a full panel, plan code or a full handoff is always available on request. A recorded task rule never outranks the user's current instruction [RQ-10] | contract |
| QP10 | **Behavior, not only text** [RQ-13]. A release that changes instruction text runs the agent-compliance evaluation on the new text and on the previous text | §3.2; §6 |

### 3.2 Mechanisms and tests

| Mechanism | Guarantees | From |
|---|---|---|
| `tests/test_normative_floor.py` | **Full-line floor** [RQ-02]: in every unit that changed since the previous tag, each removed non-blank line is moved (it appears in the destination of a move-manifest row) or retired by a row `line<TAB>reason<TAB>replacement\|-`. Lines matching `MUST\|NEVER\|ALWAYS\|MANDATORY\|CRITICAL\|REQUIRED\|BEFORE\|STOP\|ONLY\|NOT\|binding\|do not` (case-insensitive) are labelled normative and need a replacement or a stated reason for none. `--suggest <unit>` prints skeleton rows that fail until filled. At release time the CHANGELOG bullet names each retiring unit and its counts, which the test checks against its own summary | v0.20.0 |
| `tests/test_contract_invariants.py` | Pins the contract's load-bearing sentences, extended every release; from v0.20.1 also every task-record read and write instruction, `context-handoff`'s MVH item 8 and `executing-plans`' "a conflict to raise" sentence [RQ-02] | v0.20.0 |
| `tests/test_eager_budget.py` + `scripts/lib/sumela-context-budgets.tsv` | Eager bytes as ratchets; a raise needs a CHANGELOG reason | v0.20.0 |
| `test_skill_structure.py`, `test_code_review_invariants.py` | Line, sibling and volume ratchets (`tests/test_skill_structure.py:53-75`). `context-handoff` gets a line ceiling set to its measured body after each edit (the test fails a stale ceiling too) and a VOLUME pin, so reflow cannot pass for a reduction [RQ-03][RU-M5]. False-positive control, anchoring, one severity model | exist; extended in v0.20.1 and v0.21.0 |
| Decision-continuity fixture (Q6) | A task across 4 sessions and 2 branches, with and without a pasted handoff, **on a base checkout, after entering a worktree and after a simulated compaction**: exact R and D ID sets reach session N, and a superseded decision is never shown as current [RT-01][RQ-08] | v0.20.1 |
| Memory-commit flow fixture | Replays the skills' real git sequence (stage code, review, record decisions, commit code, finish with each of the four options, including worktree removal): zero lost rule or decision lines, and no review made stale by bookkeeping [RQ-01][RT-02][RT-19] | v0.20.1 |
| Record merge integrity | A merge commit whose task record lost an R, D, Q or N ID present in either parent is reported by the post-merge hook, the digest's Health line and `lint --merges`, including merges made in a host UI [RT-06][RQ-12] | v0.20.1 |
| Retrieval replay (A14) | recall@20 of the prior specs and AD/TD IDs that merged specs cite, against the old path; also AD recall on cross-cutting decisions and task-decision IDs [RQ-22][RT-16] | v0.20.1 |
| **Agent-compliance evaluation** `tests/eval/compliance/` [RQ-13] | Maintainer-run, source-only. Scripted headless sessions on synthetic fixture repositories, 3 runs per scenario on the previous text and on the new text: a rule honoured in session 3 without a pasted handoff; a superseded decision not followed; a forked-skill override applied; a ground-rule conflict raised with the user, not set aside; a base-checkout start that reads the task before its first edit; a cross-cutting AD honoured. Outcomes are checked mechanically (files untouched, output that asks, transcript order) | harness and old-text baseline v0.20.0; gate from v0.20.1 |
| Shipped migration notes [RU-I3] | Every notes file parses, ids match the version, `requires` resolve, `expect` forms are valid, every runnable step has a PowerShell form, only `{SRC}`, `{ROOT}` and `{TARGET}` appear; and an end-to-end run of every repo step on a v0.19-shaped consumer with forks and a v1 record, under bash and PowerShell, including a 0.19 → latest jump | v0.20.0 |
| Merge pins `scripts/lib/sumela-merge-pins/` [RQ-21] | Per CORE instruction file, the phrases a release requires and forbids. `update.sh --plan` downgrades a clean merge that violates them to `conflict` | mechanism v0.20.0; rows per release |
| Scale fixture [RU-I12][RT-21] | The flagship's aggregate shape (≈1,300 refs, 120 unmerged branches, 14 worktrees, 500 task records, 160 summaries): digest ≤2 s, `lint --staged` ≤1 s, `task rule` ≤1 s on bash 3.2, Git Bash and PowerShell 5.1 | v0.20.1 |
| Review benchmark `tests/eval/review-bench/` | Synthetic diffs in several languages with planted Critical and Important defects plus clean controls; catch rate and false positives, old flow against new. Includes fix-round cases (a fix that breaks an unchanged caller, a partial fix, a first-round miss), misclassified-risk cases and per-task cases; every case runs ≥3 times [RQ-15][RQ-16][RQ-19] | corpus v0.20.2, gate v0.21.0 |
| Plan benchmark `tests/eval/plan-bench/` | Seeded defects: missing path, unknown symbol, missing test intent, missing final review task, spec gap; plus implement-from-plan cases scored by hidden acceptance tests [RQ-19] | v0.22.0 |
| Shadow review | In the Release 2 canary, the previous profile reviews the same diffs; uniquely verified findings are compared | v0.21.0 canary |

### 3.3 Quality metrics

Deterministic metrics (fixtures, benchmarks and the scripted evaluation; run in CI or by the maintainer):
- **Q1** fork preservation, measured **on the real checkout with its provenance record** [RU-C1];
- **Q2** registry parity;
- **Q3** normative floor and invariants;
- **Q4** digest fixture matrix;
- **Q5** retrieval replay;
- **Q6** decision continuity;
- **Q7** team-view convergence;
- **Q8** review benchmark;
- **Q9** plan benchmark;
- **Q10** comment-check fixtures;
- **Q19** agent-compliance evaluation [RQ-13].

Observational metrics (token report and artifacts; canary developer; normalized; compared with the saved baseline):
- **Q11:** Critical plus Important findings per 100 changed lines, stratified by tier, from the `findings:` and `changed_lines:` frontmatter of `.sumela/reviews/` reports. `changed_lines:` is recorded from v0.20.1 on, because the reviewed tree objects are pruned by `git gc` [RQ-14].
- **Q12:** re-review rounds per branch, and escalations.
- **Q13:** rule-violation findings per change, from `rule_refs:` (v0.20.1). It is reported only until at least 20 reports carry the field: 2 of the flagship's 50 reports cite a rule path today [RQ-14].
- **Q14:** failed verification and test runs at the final check.
- **Q15:** post-merge fix rate. This is a git-derived indicator, reported only.
- **Q16:** handoff completeness, **computed mechanically**: the prompt's rules block equals `task show --handoff-block`, the summary exists and was ingested, and the record's Continue Point was updated in that session. Plus continuity (A15) [RQ-14].
- **Q17:** procedure read before acting, including `task-records.md` before the session's first `task` write [RQ-23].
- **Q18:** implementer `NEEDS_CONTEXT`/`BLOCKED` returns per task, plan-review rounds and, from Release 3, spec-deviation findings per task stratified into code-light and full-code tasks [RQ-19].
- **Q20:** zombies: task records shown active on the base more than 7 days after their last branch merged. Target 0 [RT-05].
- **Guardrails restored from [FP §3.8]** [RQ-14]: turn inflation (requests per completed task) not above baseline by more than 5%; cache-read share ≥95% of input tokens.
- **Reported only:** A18 in-flight coverage and overlap-flag precision of the team view; A19 synthesis coverage (the share of merged specs referenced from a topic page's `## Sources`) [RT-05][RT-15].

**Gate rule** [RQ-14]. Each observational metric states a direction per release, a non-inferiority margin and a minimum sample (§6.1). The sample is at least 20 sessions per release window, and at least 20 panel runs for Release 2. A metric fails when the upper bound of the 90% bootstrap interval of its degradation exceeds its margin. "Inside the interval" never passes by itself.

### 3.4 Canary, pilot and rollback

| Stage | Who | Entry | Exit |
|---|---|---|---|
| S0 dogfood | the maintainer, in this repository and a synthetic consumer fixture, for ≥5 sessions | fixtures green | no regression in Q1–Q10; Q19 on the release candidate |
| S1 flagship canary | the maintainer's own clone, on a **release-candidate tag** `vX.Y.Z-rc.N`. The 0.19 notice and the updater's tag discovery ignore RC tags, so no teammate is prompted [RU-I6]. Sessions: ≥2 weeks and ≥20 (Release 2: ≥20 panel runs) [RQ-14] | `sumela-token-report --save-baseline pre-<version>`; benchmark baseline run; compliance baseline | every gate in §6; a spot check of 10 sampled outputs (reviews, handoffs, digests, records) against a written checklist |
| S2 team rollout | after S1 exits, the final tag is pushed and the consumer agent opens one upgrade PR from a new linked worktree (§4.A.3) | S1 exit | PR merged; migration steps verified |
| S3 four-week check | the maintainer | — | the observational gates in §6 |

**S1 in a PR-only team** [RU-I6]. The framework is vendored, so a one-developer canary needs a defined path:
1. The upgrade to the RC stays on an unmerged branch, `<prefix>upgrade-<version>-rc.<n>`, in its own worktree.
2. Canary work happens in worktrees branched from that upgrade branch, so the canary sessions run the new framework.
3. Before a feature is pushed for review, `git rebase --onto <base> <upgrade-branch> <feature>` drops the framework commit, and `git diff --name-only <base>...<feature> -- .sumela scripts docs/second-brain/template` must print nothing. The agent runs both with the developer's confirmation.
4. Task records and summaries stay in the feature. Teammates on v0.20.0 already exclude `_tasks/` and `_team/` from Qdrant (§B.7).
5. At S1 exit the RC branch is discarded; S2 upgrades from the final tag.

**Rollback triggers:** a failed deterministic gate; a verified Critical found only by the shadow (old) review; a rule or decision lost in any spot-check sample; a compliance-evaluation scenario below its gate; an observational quality metric that fails the gate rule.

**Rollback paths:**
1. **Per developer, instant:** the valve where one exists (`SUMELA_REVIEW_PROFILE=full`, §4.C).
2. **Consumer:** the agent reverts the upgrade PR (`git revert -m 1 <merge>`) and runs the release's `rollback:` steps in reverse (§4.A.3). **Exception: v0.20.0 rolls forward.** Reverting it reinstates the overwriting 0.19 updater, so a defect in v0.20.0 is fixed by a patch release [RU-M6].
3. **Upstream, per component** [RQ-28]: each component's text lives in its own units with move manifests, so a patch release can restore one component (the STEP 2 digest, the task-record instructions, one skill) without reverting the others. The per-component metrics (A4/A5 for the digest, A15 and Q6 for records, Q7 and Q20 for the team view) attribute a regression to its component.

---

## 4. Design by area (D-U1 order)

### A. Upgrade foundation [D-U5]

#### A.1 Three-way merge for forked CORE files (`scripts/update.{sh,ps1}`)

**Inputs.**
- LOCAL is the consumer's file.
- THEIRS is the new upstream file, **materialized from the release tag's tree with `git archive`**, never from the source's working tree. A `--source` with uncommitted or untracked changes under the CORE paths is refused unless `--allow-dirty-source` is given (maintainer tests only). Today `find` over a working-tree source vendors untracked files: the flagship's v1 record lists two bytecode caches [RU-I8].
- BASE is upstream at the installed version: `upstream_commit` from a v2 record (written from v0.20.0 on), else the tag `v<VERSION>` in the release clone. Tag discovery keeps only `^v[0-9]+\.[0-9]+\.[0-9]+$`, so release candidates are never picked by accident [RU-I6]. Without a BASE (a shallow clone or tarball), merging is disabled and the conservative defaults apply.

**Base validation** [RU-C1] (replaces [FP C-W14(b)]).
- A BASE is valid when its own `.sumela/VERSION` equals the installed version. For the tags that sit on later commits than their version bumps (v0.6.0, v0.11.0, v0.12.1, v0.13.0; v0.15–v0.19 are exact), the files that differ between bump and tag are `review` unless LOCAL equals one of the two versions.
- **A pre-0.20 (v1) record is never used to validate BASE.** Its `files` list is provably unreliable: on the flagship it lists all 11 files that were re-forked by hand inside the upgrade commit, and two bytecode caches. Used as a global switch, it disabled merging on the real checkout and turned about 26 rows into unresolved `review` rows, while the disposable copy that the acceptance test used had no record and passed.
- With a v2 record, a vouched file that differs from BASE is a fork **for that file** (merge or keep). Merging is disabled for the whole run only when more than half of the vouched files differ, which signals a wrong BASE, and the run names them.

**Per-file decision:**

| Case | Action | Default |
|---|---|---|
| LOCAL = THEIRS | none | — |
| LOCAL = BASE (unmodified) | apply THEIRS | automatic, because there is no local content |
| THEIRS = BASE, LOCAL ≠ BASE (fork, no upstream change) | keep LOCAL | automatic |
| all three differ, clean merge | `[m]erge`. `git merge-file` runs on temporary copies with line endings normalized, in place (in Windows PowerShell 5.1, `> out` writes UTF-16LE). A merged CORE instruction file must also pass the release's **merge pins**; a violation turns the row into `conflict` [RQ-21] | **merge** |
| all three differ, conflict | `[k]eep` LOCAL; write the conflicted result to `.sumela/.upgrade/<path>.merge` | **keep** |
| the user wants THEIRS on a fork | `[t]heirs` only, with a typed confirmation | never a default |
| upstream deleted the file (listed in `scripts/lib/sumela-removed-files.list` as `<version><TAB><path><TAB><successor\|->`) | remove only if LOCAL = BASE; otherwise keep and report. **When the list names a successor**, a forked file becomes a `carry` row: its local hunks are written to `.sumela/.upgrade/<path>.carry`, to be moved into the successor with consent, so field learnings in a retired prompt are not silently orphaned [RU-I10] | — |
| the live `_SCHEMA.md` (derived from the template) | three-way merged like any file, with BASE = the template at the installed version, under its own consent class (`--without schema`) [RU-M12] | merge |

**File modes** [RU-I7]. Every installed or merged file takes THEIRS' git mode; kept files keep LOCAL's mode. A merge copy built by redirection is 0644, and git ignores a non-executable hook: the forked `pre-commit` (which carries the secret scan) would otherwise be silently disabled for the whole team. v0.19's `chmod +x` list (`update.sh:509`) also misses `_dispatch.sh`.

**Agent mode** [D-U5], new because an agent's shell has no terminal (§1.3 item 6):
- **`--plan`** is a dry run: it writes `.sumela/.upgrade/plan.tsv` (action and diff statistics per file) and merged-file previews, and prints a summary of ≤2 KB.
  - It lists each **merged CORE instruction file**; the agent shows that file's diff against LOCAL and against THEIRS and asks per file [RQ-21].
  - It lists the IDE mirrors that need a re-sync and warns when Python is absent, because `sync-mirrors.sh --check` then exits 0 while mirrored IDEs keep the old contract [RU-I11].
  - It **refuses (exit 5) when the integration base already carries a VERSION ≥ the release**: "merge the base instead". On a pre-upgrade branch this replaces a divergent second upgrade with a merge [RU-C2].
- **`--apply-plan`** applies exactly that plan, and refuses if the tree or the clone changed since.
- **`--resolve <path> --take merged|local|theirs|keep|drop`** settles one conflict, collision or carry row after the user decides.
- **`--verify-applied`** checks the result, not the exit code: kept rows still match their recorded `local_blob`, and merged files still hold their LOCAL-only lines. **`--stage`** stages exactly the applied rows from `applied.tsv`, deletions included [RU-M4].
- **Without a terminal** and without `--apply-plan`, it refuses to touch any fork (exit 2: "run `--plan`, then `--apply-plan`"). **`--yes`** applies only unmodified files and clean merges, never `theirs`.
- Every runtime directory it or the wiki tool writes (`.sumela/.upgrade/`, `.sumela/.wiki/`, `.sumela/.handoff/`) carries its own `.gitignore` containing `*`, so a declined gitignore reconcile can never commit them [RU-M8].

**The old updater** [RU-C2]. Three layers, because the 0.19 updater stays installed on every pre-upgrade branch for weeks:
1. **A hand-off guard.** The 0.19 `update.sh` sources `scripts/lib/sumela-gitignore.sh` **from the new release clone** before its version gate (`update.sh:111-116`, called at `:147`; the gate is at `:170`). From v0.20.0 that library detects a pre-0.20 caller (`basename "$0"` is `update.sh`, `$SRC` and `$ROOT` are set, `SUMELA_UPDATER_SCHEMA` is unset) and `exec`s the new updater from the same clone in `--plan` mode, so nothing is written. Reproduced on the real 0.19 updater with forks and no terminal: fork intact, VERSION unchanged, 0 changed files. `setup.sh` sources the same file with a different `$0`.
2. **A notice that never names a bare `update.sh`.** The v0.20.0 `_lib.sh` notice reads the configured base: when the base already carries the release it says "merge `<base>`"; otherwise it names the agent procedure (`scripts/sumela-migrations/README.md` in the release).
3. **Recovery.** `update.sh --recover-forks [--from <commit>]` restores forks that an old updater overwrote and committed: OURS is the parent of the commit that bumped VERSION, limited to the paths the v1 record lists as vendored, three-way merged like any fork. The 0.19 `update.ps1` runs nothing from the new clone before it applies, so for PowerShell users this command is the recovery path.

**Other fixes:**
- **Self-healing second pass** [FP C-W14(a)]: when the working-tree `.sumela/VERSION` differs from `HEAD:.sumela/VERSION`, OURS is `HEAD:<path>`, restoring forks an old updater overwrote before commit.
- **`[s]kip all`**: today it stamps the new VERSION (`update.sh:487`). Now VERSION is stamped only when every CORE file is current, merged or deliberately kept (`kept:` in provenance); otherwise the record holds `partial_upgrade`, a plain re-run resumes, and `status` shows it.
- **Provenance**: `.sumela/.last-update.json` gains `upstream_commit`, `base_version`, `merged:` and `kept:`, and a write preserves paths that registry sync and migration ledgers added earlier in the run [RU-M4]. The self-modification guard reads it (`requesting-code-review/self-modification-guard.md:35-42`), so merged files' local hunks are still reviewed as authored.
- **Downgrade**: `--rollback-to <version>` merges with the installed version as BASE and the older one as THEIRS (the gate itself only checks equality, `update.sh:170-173`). It never installs an updater older than 0.20.0.

**Transition from v0.19 or earlier (once).** The old updater cannot merge and defaults to apply-all, so the consumer agent runs the new one from the release clone, in a **new linked worktree** cut from the integration base, so the developer's own checkout is not disturbed [RU-M3]. `--source` exists today (`update.sh:25`, `:84-86`); the PowerShell twin's parameter is `-SourceDir` (`update.ps1:25`), with `-Source` added as an alias [RU-M6]:

```text
bash <clone>/scripts/update.sh --source <clone> --plan
bash <clone>/scripts/update.sh --source <clone> --apply-plan
```

**Tests** (`tests/test_update_merge.{sh,ps1}`, ubuntu and windows-latest):
- Enter, EOF and `--yes` never overwrite a fork, `pre-commit` included;
- clean merges keep local lines; conflicts keep LOCAL with a `.merge` file;
- a wrong base disables merging; **a vouched file re-forked inside the upgrade commit stays a per-file fork** (the flagship's exact shape) [RU-C1];
- a merged hook keeps its executable mode [RU-I7]; a dirty source is refused [RU-I8]; a merge-pin violation becomes a conflict [RQ-21]; a removed fork with a successor becomes a carry row [RU-I10];
- the self-heal restores a fork; skipping leaves VERSION; the removal manifest;
- the transition on a v0.19-shaped fixture; **the real `git archive v0.19.0` updater against forks, with no terminal: 0 overwrites**; `--recover-forks` after a committed overwrite [RU-C2].

**Acceptance:** the flagship's `--plan`, **run on the real checkout with its record present** (it writes only `.sumela/.upgrade/`), lists all 11 forks as merged or kept, none overwritten [RU-C1].

#### A.2 Registry and frontmatter parity

- **Today.** `reconcile-registry.py --check` reports only unregistered and orphaned skills (`scripts/reconcile-registry.py:22`, `:32`) and leaves description drift "for /evolve to fix" (`:172`). The source repository has 1 drift (`qdrant-session-memory`); the flagship has 4.
- **New `scripts/sumela-registry-parity.{sh,ps1}`** (bash and PowerShell, so the core stays Python-optional). `--check` compares each registry `<description>` with its SKILL.md frontmatter byte for byte and exits 3 on drift. `--sync` rewrites drifted overlay entries after consent, with a diff per entry; drift in a security-routing skill is an attention row.
- **Where it runs:** `--check` in `validate-structure.sh` (pre-commit and CI); `--sync` in `update.sh`, after applying files and on the no-change branch. The four plugin registration writers copy descriptions verbatim [FP P0.5]. The PowerShell writers write UTF-8 without BOM through `[IO.File]`: Windows PowerShell 5.1's `Set-Content` writes ANSI and would corrupt the 16 non-ASCII descriptions into permanent drift [RU-M1].
- **Rule.** A description changes in the release that changes its behavior, and the same upgrade restores parity (`using-second-brain` in v0.20.1 and v0.20.2, `context-handoff` in v0.22.1).

#### A.3 Machine-readable migration notes

**Where they live** [RU-I2].
- `scripts/sumela-migrations/upgrade.md`: the **version-agnostic** repo procedure (worktree and branch, plan, apply, parity, mirrors, validate, commit and PR), parameterized by `{TARGET}`.
- `scripts/sumela-migrations/<X.Y.Z>.md`: only the steps specific to that version, each idempotent.
- `scripts/sumela-migrations/README.md`: the format and the agent procedure.
- A runner, `scripts/sumela-migrate.{sh,ps1}`, ships with them. They ship because `scripts` is a CORE_DIR; files at the `.sumela/` root do not ship, the "root-level trap" (`update.sh:189-194`).
- A 0.19 → 0.20.2 jump is therefore one worktree, one plan and apply from the 0.20.2 clone, the version-specific steps of 0.20.0, 0.20.1 and 0.20.2 in order, and **one** PR. Per-version notes that hard-code their own branch, `expect` and PR cannot compose: the 0.20.0 apply step would expect "upgrade complete 0.20.0" from a 0.20.2 clone and stop the run.

**Format.** One fenced block per step, with line-oriented `key: value` pairs that bash, awk and PowerShell parse without a YAML library:

````markdown
```sumela-step
id: 0.20.1-03
title: Record this clone's integration bases for the wiki digest
scope: developer              # repo | developer
when: first-session           # pre-update | update | post-update | finalize | first-session | quiet-window
consent: confirm              # none | confirm | explicit (typed)
run: bash .sumela/skills/using-second-brain/scripts/sumela-wiki.sh bases --detect
run.ps1: powershell -NoProfile -File .sumela/skills/using-second-brain/scripts/sumela-wiki.ps1 bases --detect
verify: git config --local --get sumela.baseRefs
expect: non-empty
rollback: git config --local --unset sumela.baseRefs
agent: Show the proposed order; write it with `bases --write` only after the user confirms.
```
````

The `#` annotations above are explanatory: the format allows full-line comments only, never inline ones, because values are verbatim commands. The only placeholders are `{SRC}`, `{ROOT}` and `{TARGET}`; the runner turns the first two into environment references, so a path with spaces or quotes is never re-parsed.

**How the consumer agent discovers the notes and follows them:**
1. **The maintainer's instruction** is one line: *"Upgrade SumelaOS to vX.Y.Z: fetch the release into a temporary clone, read `scripts/sumela-migrations/README.md` there, and follow it. Show me the plan first, ask before each consent step, verify every step, and open one PR."*
2. **Step 0, Windows only** [RU-I13]: `Get-ExecutionPolicy -List`. When scripts are blocked (the client default is Restricted), the agent runs each step's bash line through Git Bash, or offers to set `RemoteSigned` for the current user; never `-ExecutionPolicy Bypass`.
3. **The release clone** is a full clone of the URL in `.sumela/upstream.conf`, fetched with the same `GIT_ALLOW_PROTOCOL` the updater uses [RU-M9]; the repository is small, and a blob-filtered clone would fetch lazily during `git archive`. The agent checks that the tag is an annotated release tag, `v<target>` or `v<target>-rc.<n>`.
4. **`sumela-migrate plan --source <clone>`** writes `.sumela/.upgrade/migrate.state` in the main checkout (the installed version it started from, the target, the clone path, the confirmed branch prefix and worktree) [RU-I1][RU-M3][RU-M4]. A resumed or new session reads it. Selection:
   - **repo scope:** the generic procedure plus every version-specific step with a version in (from, target], without a ledger entry and not made moot by `until`;
   - **developer scope:** every shipped step with a version ≤ the installed VERSION, without a state-ledger entry and not moot. A teammate who pulls the upgrade therefore still sees the developer steps of every version they skipped. Selecting "notes above the installed VERSION" would hide them, and would also hide the post-update steps once the apply step stamps VERSION [RU-I1].
5. **Per step:** `show <id>` → consent as required → `run` → `verify <id>` (compares with `expect`; success rests on the artifact, never on the exit code alone) → `record <id> done|declined|not-applicable`.
6. **Repo-scope steps** run in the upgrade worktree and land in one PR with the `--plan` output. The branch prefix is confirmed once (host push rules may reject `sumela/`), the base candidates shown are at most 10, and the commit subject is matched as a substring, so a consumer's commit-message hook can add its own prefix [RU-M3]. Nothing is pushed to a base branch.
7. **Developer-scope steps** surface through `status` in v0.20.0 and as one digest notice from v0.20.1 ("SumelaOS X: N setup steps — I can walk you through them"), then `plan --scope developer` [RU-M6].

**Ledgers.**
- **Repo scope:** a tracked `.sumela/migrations-applied/<step-id>` file per step (`upgrade-NN@<target>` for generic steps), conflict-free like `_improvement-queue/` (`_SCHEMA.md:485`). Its writes are recorded in provenance so that the self-modification guard treats them as framework operations. No `.gitattributes` rule is needed; `update.sh` never touches that file (`update.sh:21`).
- **Developer scope:** `${XDG_STATE_HOME:-~/.local/state}/sumela/<key>/migrations.log`, where `<key>` is the first 16 hex characters of the sha256 of `<main checkout>/<install prefix>` (`%LOCALAPPDATA%\sumela\<key>` on Windows), mode 0600 inside a 0700 directory. The install prefix comes from the install root, never from the working directory [RU-M6].

**Security** [RU-M10].
- **Repo steps** run only from the shipped notes of a verified tag, never from wiki or chat text.
- **Developer steps** run from the notes installed at the consumer's HEAD, so their real trust boundary is repository write access, the same as for hooks.
- The notes lint forbids `consent: none` unless the step is `run: -` or its `run` is read-only.
- Every change to a tracked file or a setting needs consent. `status` shows how many steps are pending.

---

### B. Second-brain correctness (Karpathy-faithful, team-safe)

#### B.1 Target model

| Surface | v0.19.0 | Target |
|---|---|---|
| `_INDEX.md` | Read whole at session start (`sumela-prompt.md:44`); one paragraph per artifact | **A catalog of wiki pages:** one line per page (≤200 B), ≤8,000 B in total, with Collections lines for `catalog tasks` and `team show` [RT-15]. Read at query time through `sumela-wiki.sh catalog index` (K:47). The digest prints a head of ≤450 B [RD2 §4] |
| `active-project-context.md` | Read whole; 8 sections, including the per-developer journal | **Current state:** `## Focus` / `## Next` / `## Risks & Blockers` / `## Pointers`, ≤3,000 B. Revised in place; shown whole, from the base version [RD2 §5.1] |
| Per-developer state | `@`-bullets in the shared page | **Single-writer files** [D-U3][RT-04]: the developer's own task records carry per-task state, and `wiki/_team/<dev-key>.md` carries only the focus line. The team view is derived at read time (§B.5) |
| Task decisions | Copy chains: plan block, summary, prompt | **One task record per task**, `wiki/_tasks/<task-key>.md` [D-U4][RT-12] (§B.6) |
| Specs, plans, summaries, reviews | Paragraphs in the boot files | Catalogs generated at read time (`catalog specs\|plans\|summaries\|reviews\|tasks`) plus a folded, IDF-weighted `search` [RD2 §4.5] |
| ADR and TD registers | "Read in full" | Bounded lookups: `entry <page> --list [--grep]` (≤8 KB), `entry <page> <ID>` (all matches) and `entry <page> --next-id` [RD2 §4.4][RT-08] |
| `_SEARCH_INDEX.md` | Rows appended per update; read whole | One row per curated page, updated in place; searched, never read whole |
| `_LOG.md` | Union-merged journal (`.gitattributes:20`) | Unchanged as a journal: grep only, entry caps on added entries, no automatic `lint` pings |
| `wiki/archive/` | Defined, unused | Verbatim cold storage written by compaction; excluded from boot reads and from `wiki_pages`, searchable with `search --deep` [RT-16] |

There is one tool, `.sumela/skills/using-second-brain/scripts/sumela-wiki.{sh,ps1}`, with `fold-latin.tsv` beside it.
- It ships under the existing CODEOWNERS entry and stays out of host `scripts/` [RD2 C-W6].
- Subcommands: `digest`, `bases`, `catalog`, `search`, `entry`, `lint`, `task`, `team`, `eol` (line-ending check and re-checkout [RU-C3]), `review-tree` (the review gate's hash, DEC-5), `compact`, `resolve-legacy`; Release 3 adds `finalize`. A global `-C <dir>` runs it against another worktree [RQ-07].
- **It is called by the absolute path of the main checkout's copy** once a session leaves the main checkout. The digest header prints that path. A worktree of a branch cut before the upgrade has no copy of its own, so a relative path would fail exactly where in-flight tasks live [RT-10].
- It parses only structure, never touches the network, keeps runtime state in the gitignored `.sumela/.wiki/`, and honors `WIKI_PATH` and `SUMELA_SUMMARIES_DIR`.
- Every reader strips a trailing CR, every writer writes LF, and every write re-reads its artifact and exits non-zero when the new line is missing [RU-C3]. With Git for Windows' default `core.autocrlf=true`, a heading match on a CRLF record otherwise drops a rule and still exits 0 (reproduced).
- Read-only subcommands have full PowerShell 5.1-compatible twins with encoding pinned and the invariant culture (a Turkish locale lowercases `I` to `ı`) [RU-M2]; data-moving ones delegate to Git Bash, located at `<git --exec-path>/../../../bin/bash.exe` or `…/usr/bin/bash.exe`, never `bash` from PATH, which may be WSL [RU-I9].

#### B.2 The bootstrap digest (STEP 2)

**STEP 2 is replaced** (`sumela-prompt.md:43-55`) by one command for the agent's own shell tool (never `bash` from PowerShell, where it may be WSL). The output is ≤8,000 B and ends with a sentinel. Three fallback rungs follow [RD2 §6.1]: the twin script; inline commands per shell, which still work where the execution policy blocks scripts; a 60-line `Read` when there is no shell tool. **Rungs 2 and 3 also locate the current branch's task record and read it whole** (≤12 KB), so a failed digest never drops the task's rules [RQ-11]. The contract says "NEVER `Read` a whole wiki file at bootstrap, not even with `allow_large`", with one exception, the bounded task record [FP X9][RQ-11]. A supersession clause covers the forked skills until their text carries the new steps (§B.3) [RT-20].

The digest is generated per session from local refs: nothing is committed or merged, and no one owns its regeneration. It is trusted only when the sentinel is present. Its caps were rebalanced so the D-U3 and D-U4 sections fit [D-U3][D-U4], and so the rules cap covers the measured sizes: in-force rule lists with entry prefixes measure p50 957 B, p90 1,257 B and max 1,780 B on the flagship [RT-13]:

| # | Section | Cap (B) | Never cut |
|---|---|---:|---|
| 1 | Header: branch (≤60 B, truncated), HEAD, the base used, last fetch, **the tool's absolute path** [RT-10][RQ-11] | 300 | yes |
| 2 | Notices, at most 6 lines then "+N more — `status`": pending `/evolve` items, un-ingested sources, pending migration steps [D-U5], record-integrity and renumbering notices [RQ-12][RQ-27], one-time offers | 380 | yes |
| 3 | **Your work.** On a task branch: "Your current task `<key>` — read `<record>` before the first edit", then:<br>• the Task Ground Rules in force, verbatim (≤2,000, never cut) [RT-13];<br>• the continue point (≤200), flagged `stale` when the worktree changed after it [RT-01];<br>• **every in-force decision headline** (≤120 B each, never a superseded one), the superseded count and a cut marker to `task show` [RQ-08];<br>• the summary and handoff pointers (≤150).<br>**On a base checkout** the same block is printed for your most recently updated active or paused task, labelled "Applies when you work on `<key>` (branch `<b>`, worktree `<w>`)" [RT-01][RQ-07]. Then one line per other own task: rule and decision counts and its `digest --branch` command | 2,900 | the rules |
| 4 | Current state, from the base version: whole when within budget; an over-budget page is cut with a marker and a W01 notice, never failed [RQ-11] | 3,040 | yes, within budget |
| 5 | Catalog head, with the fixed Pointers line (160, never cut) | 450 | the Pointers line |
| 6 | **Team** (§B.5), as of the base plus pushed refs: ≤4 developers, one line each, ≤2 overlap flags [D-U3] | 400 | no |
| 7 | Recently landed: the 3 newest first-parent merges into the base | 200 | no |
| 8 | Log: the newest headers, sorted by date | 120 | no |
| 9 | Shape and health: counts, last real lint, record integrity | 120 | no |
| — | Sentinel | 80 | yes |
| | **Total** | **7,990** | never-cut maximum 5,960 |

**Robustness** [RQ-11]. Renderers bound every field a user controls: branch names are truncated, notices are capped by count, and an over-budget current state is cut with a marker. A failure without a sentinel is reserved for a broken renderer invariant, so one teammate's edit can never turn the digest off for everyone.

**Rules on a base checkout** [RT-11]. The legacy fallback (a branch with no record prints its newest summary's `## Task Ground Rules`) runs only on a non-base branch, and only from summaries added in `<nearest base>..<branch>` (first-parent) or untracked in that worktree, preferring a `branch:` match. It never prints on a base checkout and never prints a merged sibling's rules.

**Legacy current state** [RQ-24]. Until compaction, legacy mode bounds the non-"Active Work" sections to 2,500 B and says why. When the whole page is ≤16 KB and within the Read limit, the digest adds that it may be read whole later, when the task needs the rest; the bootstrap's NEVER-Read rule still applies at every size.

Variants: `digest --branch` prints section 3 (≤2,900 B) after switching branch or entering a worktree, and the post-checkout hook prints the same block (§B.6); `--wip` and `--team` print up to 4 KB each; `--fallback` prints the rungs. **Bases** [RD2 §5.2] are an ordered list in per-clone `git config sumela.baseRefs`, proposed by `bases --detect` (at most 10 candidates [RU-M3]) and confirmed once. The nearest base is chosen per branch, and "unmerged" means merged into no base. Every walk over refs is pre-filtered in one `for-each-ref --no-merged=<base> --sort=-committerdate` call with a date cut before any per-ref work [RU-I12].

**STEP 3, GATE 1 and FAMILY C** (`sumela-prompt.md:110-112`, `:126`, `:168-171`, `:177-178`): Tier-3 becomes `catalog index` → sub-index → `search`, then the matched pages.

#### B.3 Stopping growth: writer rules

| Surface | Change | Release |
|---|---|---|
| `sumela-prompt.md` STEP 2/3, supersession clause; `<context_handoff>` (`:253`) | Digest; never read boot files or registers whole; artifact paths go to the task record and summary frontmatter. "Always update Second Brain (active-project-context …)" becomes the summary plus the task record, and current state only for team-level change. New: the conditional rules wording, the re-read after a branch switch, a worktree entry or a compaction [RT-01], the READ-before trigger for `task-records.md` [RQ-23], and the memory-commit carve-out (§B.6) [RQ-01] | v0.20.1 |
| SUPERSEDED clause [RQ-05][RT-20] | It names the overridden steps (brainstorming steps 7–8; writing-plans steps 2, 4 and 5) and holds **until `brainstorming/SKILL.md` and `writing-plans/SKILL.md` contain `ARTIFACT REGISTRATION`**, a text probe, not a version: a fork that conflicts at v0.20.2 stays covered. It says `task new` as well as `task set`. The same override is repeated at the point of use, in one line of the eager, unforked `using-superpowers` | v0.20.1 |
| `brainstorming/SKILL.md:23`, `:78`, `:82` (forked) | SECOND BRAIN CHECK lists **every AD title** (`entry architecture-decisions --list`, grep only when the list is cut) and reads every AD in the feature's layers; TD keeps grep [RQ-22]. WIKI LINKING becomes ARTIFACT REGISTRATION into the task record; preflight checks the record; a `## Prior context consulted` block | v0.20.2, merge |
| `writing-plans/SKILL.md:14`, `:21-29`, `:104`, `:110` (forked) | Same pattern; Task Ground Rules go to the task record [D-U4] | v0.20.2, merge |
| `systematic-debugging/SKILL.md:14` | `entry --list --grep` | v0.20.1 |
| `finishing-a-development-branch/SKILL.md:20`, `:37`, `:66-67`, `:72`, `:80`, `:84`, `:86-94`, `:95`, `:96-99`, step 9 | **Task close-out moves before any merge, push, branch deletion or worktree removal** [RT-02][RQ-01]; item 1 revises current state in place for team-level change only; item 1b's topic-page offer ships here, in v0.20.1 [RT-08]; item 4 promotes only from the record [RT-08]; one search row per curated page; one catalog line per new page; `lint --branch`, with its summary as step-9 evidence | v0.20.1 |
| `context-handoff/SKILL.md:47-49`, `:86`, `:118-138`, `:153-157`, `:167-172`, `:196-202`, `:252-257`, `:280`, `:377-385`, `:424`, `:441`, `:457-468`, `:476` | No sprint markers or index rows; rules and decisions go to the task record; **the template placeholder and filling rule that still said "copy from the previous handoff, drop" are rewritten** [RQ-04][RT-09]; MVH item 5 retired, numbering kept. The body is 493 of 500 lines as the test counts them [RQ-29][RU-M5]; its line ceiling is set to the measured body after the edit, with a VOLUME pin beside it; the lazy split waits for Release 3 [D-U1] | v0.20.1 |
| `using-second-brain/SKILL.md:3`, `:10`, `:20-21`, `:39`, `:47`, `:66-67`, `:80`, `:99`, `:184`, `:193`, `:199`, `:265-269`, `:280` | Query-time catalog; the time trigger fixed (`:39` contradicts "never read the full `_LOG.md`"); **`:10` no longer declares a plan block for Task Ground Rules** [RQ-04]; no summary rows; `branch:` and `task:` in summary frontmatter; the summary protocol runs `task session` and `task note` [RT-09]; new sibling `task-records.md` | v0.20.1 |
| `self-improvement-curator/SKILL.md:98`, after `:146` | WIKI BUDGET GATE: revise, never append; `lint --file` | v0.20.1 |
| `using-git-worktrees`, `executing-plans` | `task attach` **before** `cd` (it finds the pre-branch record in any checkout) and its setup commit [RT-07]; `executing-plans` re-reads the rules before **each** plan task [RT-01], imports a plan's legacy block on every run and treats record, plan block and handoff as one set that must agree [RQ-05]; the memory-commit carve-out [RQ-01] | v0.20.1 |
| `subagent-driven-development` (forked) | The same per-task re-read, payload fields and carve-out; BLOCKED row (e) for ground-rule conflicts [RQ-26] | v0.20.2, merge |
| `requesting-code-review/review-report.md` (unforked) | The gate's tree hash excludes the live wiki (DEC-5); `changed_lines:` and `rule_refs:` frontmatter [RQ-01][RQ-14] | v0.20.1 |
| `.sumela/git-hooks/post-checkout`, `post-merge`, `_lib.sh` | The checkout task block and the post-merge record-integrity check [RT-01][RT-06]; v0.20.0 already changes the update notice [RU-C2] | v0.20.0, v0.20.1 |
| `qdrant-session-memory/SKILL.md:59` | Tier-3 fallback names the STEP 3 tools | v0.20.1 |
| Templates; `_SCHEMA.md` §7, §8, §10, §11, §13, §16, new §18, §19 | New index, current-state and search templates, plus `task.md.template` and `team-member.md.template`; §8's summary comment no longer says "prune the rest" [RT-09]; the §10 team-concurrency model (`_SCHEMA.md:483-486`) rewritten [D-U3] | v0.20.1; live `_SCHEMA.md` three-way merged with consent [RU-M12] |
| Defect fixes | `status.sh:116` counts only `status: pending`; `auto-update-memory.py:233-245` stops logging `lint`; `_lib.sh` sync diffs (`:153`, `:415-417`, `:429-430`, `:494-496`) gain `--no-renames` | v0.20.0 |

**Description of `using-second-brain`** (`using-second-brain/SKILL.md:3`). It becomes: "Use when ingesting a raw source, finishing a branch, linting the wiki, checking who is working on what, recording or reviewing a task's ground rules and decisions, answering a question that may reference prior work, or facing an information gap during reasoning (…)"; v0.20.2 adds "compacting", in the release that ships operation 10. The phrase "starting a session" is dropped. Parity is restored in the same upgrade (§A.2) [D-U3].

#### B.4 Index, current state and lookups

Carried from [RD2 §4–5]: sub-indexes above 25 entries per category; `catalog` at ≤16 KB with paging and `--match`; `search` with one Latin fold table in both twins, IDF weighting, bilingual terms and ≤4 KB output; `entry` returning every match for a duplicated ID (with a W10 notice), and dispatch prompts passing IDs and `entry` commands instead of "read the register". Current state has three writers: `finishing` item 1 for team-level change, `/evolve` `active-context`, and the lead at milestones. All of it parses structure only.

Changed by the reviews:
- **AD lookups favour recall** [RQ-22]. A cross-cutting decision ("all external calls go through the gateway") does not match feature nouns. The AD check lists every title without grep (the flagship's 51 ADs fit the 8 KB cap at about 150 B a line), uses grep only when the list is cut, and reads every AD in the feature's layers. An entry without a Status line prints `status: (none — in force)`, never `—`, because pages written before v0.18 are allow-by-default.
- **AD numbering across refs** [RT-08]: `entry architecture-decisions --next-id` prints the maximum `AD-NN` across every visible ref plus 1, so two feature branches that promote in the same week do not allocate the same number. W10 runs diff-scoped when the base is merged into a branch.
- **Task decisions are searchable** [RT-16]: the default `search` set includes `## Task Decisions` lines of task records, not only frontmatter and headings.
- **Collections lines** for `catalog tasks` and `team show` in `_INDEX.md`; `_tasks/` and `_team/` are non-curated, so they get no search rows and never count as orphans (W11, W12) [RT-15].

#### B.5 Per-developer state under eventual consistency [D-U3]

**[FP] DEC-7 and [RD2] C-W2 retired this section. That is reversed.** The team propagates state by commits and local hooks, and it expects eventual consistency (K:62: "branching, and collaboration for free"). The design target is per-developer state with these properties:
- bounded;
- replaced in place, never append-only;
- without conflicts across developers, and across one developer's parallel tasks;
- convergent when merges arrive in any order;
- honest about what the others can see.

**The options, evaluated.** Merge behavior was tested on git 2.50.1, by this design and by [RT].

| Criterion | (i) One bounded entry per developer in a shared page | (ii) One file per developer with a block per task (this design's first draft) | **(ii′) Per-developer state in single-writer files: the developer's task records plus one focus file** | (iii) Git-derived only |
|---|---|---|---|---|
| Bounded | Only by convention. The flagship's version became 98.7% of a 777 KB page | Per-file cap | Records ≤12,000 B each, focus file ≤600 B; the view is computed and capped | Nothing is stored |
| Cross-developer conflicts | **Edits on neighboring lines conflict, and two appends at the end conflict** (tested). Measured: 62–70% of merges touching the two boot files conflict | None by construction | **None by construction**: different files, the precedent of `_improvement-queue/` (`_SCHEMA.md:485`) | None |
| One developer, parallel tasks | Conflicts inside the developer's own entry | **Conflicts: keys sort by date, so two new tasks insert at the same place, and a tombstone next to a new block conflicts too (tested)** [RT-04] | None: one record file per task | None |
| One task, two branches | — | — | Per-branch Continue Point blocks and appends to different sections merge cleanly (tested); appends to the same section conflict and are resolved by `task merge --resolve`; a post-merge integrity check catches a lossy host-UI resolution [RT-06] | — |
| Under eventual consistency | The last merge wins per line, with no timestamps, so stale lines look current | Last writer wins per block, tombstones | Last writer wins per record by its derived `updated`; the record's `done` or `abandoned` status is the tombstone | Correct as of the last fetch, but only 7% of PRs are visible before they merge |
| Expresses focus, paused tasks, next step | Yes | Yes | Yes: status and Continue Point in the record, focus in the focus file | No |
| Survives branch deletion | Yes | Yes | Yes, once the record reached the base or a pushed ref | No |
| Stores derived data | — | **Yes:** each block duplicates the record's fields, which is why it needed `team rebuild` [RT-04] | No | — |
| **Verdict** | Rejected: measured failure | Superseded by (ii′) | **Recommended** | A complement: the digest's immediate own-work view |

**The design** (DEC-2 confirms it):
- **Per-task state lives in the developer's task records** (§B.6): `owner_key`, `status`, `title`, the per-branch Continue Point lines and a derived `updated`. Only the owner's sessions write a record; `task set --owner <key>` hands a task over [RT-18].
- **The focus file**, `docs/second-brain/wiki/_team/<dev-key>.md`, ≤600 B: frontmatter `type: team-member` and `developer_key`, and `## Focus` with ≤2 lines and their own `updated:` stamp. Written only by `team focus`, on the developer's request, and only on a non-base branch. On a base checkout the line waits in the state directory until the next memory commit on a task branch.
- **`dev-key`** is proposed from `git config user.email` (the local part) or, at the developer's choice made at detection time, a short hash; it is confirmed once (`git config --local sumela.devKey`) [RT-18].
- **The team view is derived at read time** (digest section 6, `team show`). Sources: the base; pushed refs not merged into any base and active within 14 days (at most 8, or 20 with `--all`); and, for the reader's own tasks, every local branch and worktree. Only records that changed on a ref relative to its merge-base are read from it, and the base's records are cached by tree id [RT-21][RU-I12]. Per task, the newest copy by derived `updated` wins; `done` and `abandoned` hide it. Other developers' tasks are labelled `stale` after 14 days and hidden after 30; **your own tasks are never hidden by age** [RT-18].
- **What teammates see** [RT-05]. A task becomes visible to others when its branch is pushed. On this team that usually happens at PR time, and PRs merge within minutes of their last commit, so others mostly see paused, multi-PR and recently finished tasks. That is the eventual consistency the team accepted; the header says `as of base @ <fetch time>; pushed branches included; local work is invisible`. A developer who wants earlier visibility can set `git config sumela.pushOnAttach offer`, and `task attach` then offers, confirm-then-do, to push the branch; it is off by default.
- **Conflicts.** None across developers, and none across one developer's tasks. There is no `team rebuild` and no tombstone pruning: nothing derived is stored.
- **Lint.** W20 warns when a change edits another developer's focus file or task record, outside a handover, a merge or a rebase [RT-18]; W21 reports a focus file over budget or more than 5 active tasks per developer (info); W18 is extended to send per-branch or per-developer lines in current state to the record or the focus file; W25 reports zombies (Q20).

#### B.6 Decisions across sessions: project-scoped and task-scoped [D-U4]

This builds on the v0.18–v0.19 triage (`context-handoff/SKILL.md:64-108`). Its questions Q1 ("how long does this hold?") and Q2 ("would a developer without an agent still follow it?") stay verbatim. What changes is that task-scoped items get **one durable record per task** instead of copy chains.

| Scope | Durable home | Lifetime | At finishing |
|---|---|---|---|
| Task: a ground rule (constraint, exclusion, deferral) | the task record's `## Task Ground Rules` (`R<n>`), plus a verbatim copy in each session summary and each handoff prompt | every session and branch of the task | re-checked with Q2: promoted, retired, or carried to a follow-up task |
| Task: a design or working decision | the task record's `## Task Decisions` (`D<n>`), plus the summary's `## Decisions Made` for the session that made it | the task | the same |
| Project: an architecture decision | the ADR register through operation 5's consent and numbering (`using-second-brain/SKILL.md:94-135`). The record line points at `AD-NN`. When context was too tight to ask, the marker is `AD candidate (deferred)`; a refusal is `AD declined (<date>)` | until superseded | promoted only from the record, by the close-out's batched ask; declined decisions never are [RT-08] |
| Project: other knowledge (a convention, a runbook fact) | the curated topic page, through `finishing` item 1b's offer (v0.20.1) or `/evolve` `wiki`; a deferral is marked `wiki candidate (deferred)` in the record [RT-08] | until revised | — |
| Agent workflow | an `IMP-*.md` signal | until `/evolve` | — |
| Session-local | the summary only | the session | — |

**Task record.** `docs/second-brain/wiki/_tasks/<YYYY-MM-DD>-<slug>.md`, ≤12,000 B, rules in force ≤2,000 B (W22 reports from 1,500 B, with consolidation guidance) [RT-12][RT-13].
- **Frontmatter:** `type: task`, `task`, `title`, `owner`, `owner_key`, `status: active|paused|done|abandoned`, `created`, `spec`, `plan`. **There is no shared `updated:` or `branches:` line**: both are derived, because every write stamping one shared line made every concurrent two-branch edit conflict (tested) [RT-06].
- **Entries** are one line each: `- <ID> · <date> · <by> · <text>`. `<by>` is `user` (the user stated or confirmed it) or `agent` (inferred; an `agent` rule is shown as unconfirmed and binds only after `task confirm`) [RQ-10]. Rules (`R`), decisions (`D`), open questions (`Q`) and agent notes (`N`) are **never deleted**: a lift, supersession, resolution or pruning strikes the full text through and appends its reason, `~~<entry>~~ — lifted <date>: <why>`. Striking the full text keeps a struck and an unstruck copy recognizably the same entry when two branches merge [RT-14][RQ-25].
- **Sections:** `## Task Ground Rules`; `## Task Decisions`; `## Open Questions`; `## Agent Notes`; `## Continue Point` (one `### <branch>` block per branch, its one line replaced in place by that branch's sessions, blank-line separated so two branches never touch the same lines); `## Sessions`; `## Close-out`.
- **Format** is written by the tool (`sumela-wiki.sh task new|attach|rule|lift|confirm|decide|supersede|home|question|resolve|note|prune|continue|session|set|show|list|merge|import-legacy|close|compact`); the agent decides content and scope. Writes are idempotent by normalized text, so "record when made" and the triage at handoff never add the same entry twice [RT-14]. A write to a `done` record reopens it, and the next finishing closes it again.
- **Which record.** Every command takes `--task <key>`. Without it, the record is resolved from the current worktree and branch; when that is not exactly one record, the command exits 3 and lists the candidates, and a write never creates a record silently [RQ-07][RT-07]. `paused` records are candidates, and `paused` is set only by an explicit pause or finishing option 3, never by every handoff [RT-07].
- **Over budget** [RQ-27][RT-21]. `task compact` moves struck entries and older Sessions lines verbatim into `wiki/archive/tasks/<key>-<n>.md` and leaves one stub per moved entry, so its ID stays reserved and its reference still resolves.

**Lifecycle.**
- **Create** at the first of: **the first rule or decision agreed**, the spec saved, the plan started, a handoff with no record, an explicit request [RT-07]. Before a branch exists the record is untracked in the current checkout, and the digest still finds it.
- **Attach.** `task attach --worktree <path>` runs **before** `cd`, finds the pre-branch record in the main checkout or any worktree, moves it into the worktree and adds the branch's Continue Point block. The first `task` write on a non-base branch attaches automatically, and the checkout notice says so [RT-07].
- **Record a decision when it is made** (`task decide`, `task rule`), not only at handoff: 81% of sessions start without a pasted handoff [H4], so a decision that waits for triage can die with a session that simply ends. Triage at handoff and finishing still runs and reconciles.
- **Branches.** A follow-up branch for the same task adds its own Continue Point block; a stacked branch inherits the parent's version, and git ancestry makes it the newer one. Concurrent edits from two branches that touch the same section are resolved by `task merge --resolve`: a union keyed by ID where struck beats unstruck, colliding IDs are renumbered and the record gains a Close-out line (`renumbered · D3→D7`) that the digest shows as a notice for 14 days, and each branch keeps its newest continue line [RQ-27]. New IDs are the maximum across visible refs plus 1.
- **Never hand-merge a record.** A conflict resolved in a host UI bypasses `task merge`. The post-merge hook and the digest's Health line therefore check every merge commit that touched a record: the IDs in the merge must be a superset of the union of both parents' IDs. A loss shows as a never-cut notice until `task merge --repair` restores it [RT-06][RQ-12].

**The memory-commit protocol** [RQ-01][RT-19][RT-05].
- Records, the focus file and session summaries are committed **only** in `docs(memory)` pathspec commits: `git add -- <paths> && git commit -m "docs(memory): <what>" -- <paths>` (the `git add` is needed for a new file, and `--` keeps the staged code staged).
- **Three moments:** right after `task attach` (a setup commit, like `using-git-worktrees` step 2's exception); at each handoff; at finishing's close-out. Between those moments, entries recorded with `task decide` stay in the working tree.
- These files are **never staged with code**. The commit holds no code, so the reviewer still sees the whole uncommitted code diff. This is the one stated exception to ZERO PREMATURE COMMITS, written into `executing-plans`, SDD, `using-git-worktrees` and the contract.
- **The review gate stops hashing the live wiki** (DEC-5, recommended): `reviewed_state` and the gate's recomputation exclude `docs/second-brain/wiki/` (or `WIKI_PATH`). A bookkeeping commit then never makes a review stale, and the summary commit finishing already makes (§1.3 item 7) stops staling the ship gate. Specs and plans under `artifacts/` stay inside the hash.

**How the decisions surface.**
- **Digest:** the current-task block, or on a base checkout the labelled block for your most recent task, prints the rules verbatim (never cut), every in-force decision headline, the superseded count and the continue point, with "read `<record>` before the first edit" [RT-01][RQ-08]. STEP 2 says which rules are in force and when the others bind (§B.2).
- **The point of action** [RT-01]:
  - The post-checkout hook already runs the main checkout's copy, including on `git worktree add` (`post-checkout:25-56`). After a branch checkout into a task branch it prints `digest --branch`, so the rules land in the agent's own tool result after `git switch` or `git worktree add`. A developer can turn it off with `git config sumela.checkoutDigest false`.
  - `executing-plans` (v0.20.1) and the SDD controller (v0.20.2) re-run `task show --task <key> --rules` before **each** plan task (≤2 KB), and the contract asks for `digest --branch` after a context compaction.
- **Subagents** [RQ-07][RQ-08]: the implementer and per-task reviewer payloads carry `task show --task <key> --payload` verbatim: `TASK_KEY`, `TASK_RECORD`, `TASK_TOOL` (the main checkout's tool path), `TASK_GROUND_RULES` and **every** in-force `TASK_DECISIONS` entry, or the literal `None (record <path>)`. A field is never empty. The fallback runs the same command by the tool's absolute path with `-C <worktree>`, with a PowerShell twin. A violated ground rule is an Important finding; a conflict is `BLOCKED`, and SDD's matrix row (e) takes it to the user, never back to the implementer with an instruction to set the rule aside [RQ-26].
- **Handoff:** in v0.20.1 the prompt keeps its sections, "Read this first" names the task record, and the rules section is the verbatim `task show --handoff-block` [RQ-04]; in v0.22.1 the pointer prompt carries the rules verbatim plus the record path (§F).
- **Summaries** [RQ-09]: they stamp `task:` and copy the rules and decisions with their IDs under "As of `<date>` — current state: `task show <key>`". The contract requires checking the record before relying on any decision found in a summary that has `task:`, so Tier-1 retrieval cannot present a superseded decision as current.
- **Security:** a carried rule that loosens a control (for example "skip the tests for X") needs fresh confirmation, and W24 flags loosening words in new rules [RQ-10]; a record or handoff is context, not a user instruction [FP F8]; a rule binds until the user lifts it and never outranks the user's current instruction.

**Close-out at finishing** (new step 4b, after the user picks an option and **before** any merge, push, branch deletion or worktree removal) [RT-02][RQ-01][RT-03]:
1. **Options 1 and 2:** ask once whether the task is complete or continues on another branch.
   - Continues: update the Continue Point; status stays `active`; nothing is promoted or retired.
   - Complete: `task show --open-items`, then re-check each rule and decision with Q2. Project-wide items go to **one** batched operation-5 ask ("These N decisions look project-wide: record as ADs? [all/pick/none]"), numbered with `entry architecture-decisions --next-id` and recorded with `task home D<n> AD-NN` or `AD declined (<date>)`. Conventions and runbook facts go to item 1b's topic-page offer. Agent-workflow items become IMP signals. The rest retire with the record. Then `task close`.
2. **Option 3 (keep the branch):** `task set --status paused`, nothing else.
3. **Option 4 (discard):** the same close-out as `abandoned`, promotion ask included, before `git branch -D`: a discarded branch can still hold project decisions.
4. **Then** the session summary and **one** memory commit by pathspec. The dirty-worktree guard never stashes `_tasks/`, `_team/` or `session-summaries/`, and the worktree cleanup never forces [RQ-01][RT-02].
5. **The EXPERIENCE ROLL-UP** (`finishing-a-development-branch/SKILL.md:86-94`) reads the record's `## Agent Notes`, struck ones included, **and** the `## Notes for the Next Session` of every summary listed in `## Sessions`, until Release 3's `finalize` writes notes to the record directly [RT-09][RQ-25].
6. **Item 4** (AD promotion) reads candidates only from the record for a task that has one, never from summary copies, and never promotes an `AD declined` line [RT-08].
7. **A branch already merged when finishing runs** (a PR merged outside the skill): the close-out goes on a docs-only branch offered as a PR, confirm-then-do; declining leaves the record active, and the digest reports it as a zombie (W25, Q20) until it is closed [RT-05].
8. **A follow-up task:** `task new --from <key>` carries every in-force rule and decision, the open questions and the notes by default; `--except <ids>` opts out [RT-03].

**The bridge for tasks in flight at the upgrade** (developer step 0.20.1-05) [RQ-06][RT-10][RU-I4]:
- **Scan:** own unmerged branches with a legacy `## Task Ground Rules` block in a plan or in summaries added in `<merge-base>..<branch>`; open plans on the base with a ground-rules block and no closed record; recent base summaries by the developer; untracked summaries in worktrees; at most 30 days old.
- **Association:** a summary's `plan_artifact:` → plan → branch; otherwise the summaries added on that branch.
- **Rules:** the **newest list** (the newest summary's block, or the plan block when it is newer than every summary) is the in-force set. A line seen only in older lists was pruned by omission under v0.19's rules, so it is imported struck through as "retired before import", never as in force. The user confirms the set.
- **Decisions:** v0.19 summaries record each session's own decisions, so every summary of the task contributes. The user sees them grouped by session and picks which still hold; `AD candidate (deferred)` and `AD declined` markers are always imported, because promotion depends on them.
- **Where it writes:** into the branch's worktree, or through a temporary linked worktree of the branch, with a `docs(memory)` pathspec commit, on consent. The step verifies that the record is visible from that branch, and a declined branch is recorded, not left pending.

**Fixture Q6** runs the same task across 4 sessions and 2 branches, with one handoff pasted and one not [RT-01][RQ-08]:
- **S4a**, a base checkout: the labelled block holds exactly the in-force rule IDs and decision headlines.
- **S4b**, after `git worktree add` into branch B: the checkout block and `digest --branch` hold the same exact ID sets.
- **S4c**, after a simulated compaction: `digest --branch` restores them.
- A lifted rule appears struck; a superseded decision never appears as current.
- Both merge orders give the same record; a divergent lift merges without a live duplicate [RT-14].
- Two PRs of one task: the session after the first PR still sees every rule [RT-03].
- A legacy import never revives a rule that was dropped before the newest list [RQ-06].

#### B.7 Lint, budgets, compaction, archive, Qdrant

**Lint** (`sumela-wiki.sh lint`, W01–W19 [RD2 §7.1], plus W20–W25 [D-U3][D-U4]):
- W20: an edit to another developer's focus file or task record, outside a handover, merge or rebase [RT-18].
- W21: a focus file over budget, or more than 5 active tasks per developer (info).
- W22: a task record lost an R, D, Q or N line, in a staged diff **or a merge commit** (`--merges <range>`); a record over 12,000 B; rules in force over 1,500 B (info) [RT-06][RT-13].
- W23: an active task not updated for 30 days (info).
- W24: a new rule with loosening words (skip, disable, no tests, without review, `--no-verify`): it needs the user's fresh confirmation [RQ-10].
- W25: a zombie, a record still active on the base more than 7 days after its last branch merged (info; Q20) [RT-05].
- Diff-scoped checks run in pre-commit through a guarded call in `validate-structure.sh`. They warn and never block, which matters because that script runs under `set -euo pipefail` (`scripts/validate-structure.sh:16`) and the hook blocks on a non-zero exit (`pre-commit:62`).
- Whole-file findings are info, shown in `status` and on the digest's Health line.
- `--strict --new-only` is an opt-in CI ratchet.
- **`SUMELA_DISABLE_BUDGET_WARN` silences only the budget checks.** W20, W22's integrity part and W24 always run, still as warnings: a developer annoyed by size warnings must not also lose the only detector of a lost rule [RQ-12].
- `_tasks/` and `_team/` are non-curated: no W11 or W12 findings and no search rows [RT-15].

**Budgets.** The wiki rows go into `scripts/lib/sumela-context-budgets.tsv` [RD2 §7.2]. The digest cap and the current-state budget cannot be overridden.

**Compaction** (operation 10, `compact --plan/--apply/--verify [--against <pre-sha>]`):
- All moves are verbatim, with per-rule multiset verification, link rebasing, restore from a manifest, a lock, and "reset and re-run, never hand-merge" [RD2 §7.4].
- **C6** archives the legacy current-state sections that the agent step S1 replaces (about 9.7 KB on the flagship: sprint, maintenance and infrastructure sections), verbatim and between markers, **before** S1 runs, and `--verify` covers them [RT-17].
- `--verify` compares blobs (`git cat-file`), not working-tree bytes, so a CRLF checkout cannot fail or fool it [RU-C3].
- Each compacted boot file gets one comment line at its top: "on a merge conflict here run `sumela-wiki.sh resolve-legacy`; never hand-merge" — a read-time trigger where the conflict appears [RU-I5].
- The lock matches any ref whose name contains `wiki-compact-`, so a consumer-chosen branch prefix still locks [RU-M3].
- The legacy `## Active Work (Per Developer)` body is archived verbatim. No team state is seeded from it, because that would break the single-writer rule.
- `resolve-legacy` replays the additions of in-flight branches [RD2 §7.5]. A 0.20.2 developer step, `resolve-legacy --scan`, lists the developer's own unmerged branches that touch the boot files and offers merge-base plus `resolve-legacy` for each, before their conflicts surface in a host UI [RU-I5].
- **Trade-off, stated** [RT-16]: after compaction and the archive exclusion, the old current-state prose leaves `wiki_pages` and is reachable by `search --deep` and grep only.

**Qdrant** (plugin-gated):
- `wiki/_tasks/` and `wiki/_team/` are excluded from `wiki_pages` from **v0.20.0**, anchored at the wiki root, so a teammate on v0.20.0 never ingests a canary's records and a consumer page under some other `team/` folder is never dropped [RU-I6][RT-12].
- From v0.20.2, records whose status is `done` or `abandoned` are ingested with a `status` payload: they are stable, so their decisions become retrievable without churn [RQ-09][RT-16].
- `archive/` is excluded, and `--reconcile` added, in v0.20.2.

---

### C. Review restructuring (D-U2) [D-U2][D-U6]

**Shared risk taxonomy** (`writing-plans/risk-classes.md`; referenced by writing-plans, SDD and requesting-code-review):

| Class | Meaning |
|---|---|
| `high:<class>` | money movement; authN, authZ and session or token lifecycle; cryptography and secrets; data migrations and schema changes; public contracts (external API, event schemas); IaC, CI workflows and container or IAM files; personal data |
| `mechanical:<reason>` | a closed list: rename or move without behavior change; a config value within an existing schema, **except security-relevant keys** (CORS, TLS, rate limits, permissions, authentication settings) [RQ-16]; docs only; test data only; regenerated generated code; a patch dependency bump without an API change |
| `normal` | everything else |

In v0.21.0, writing-plans gains one `**Risk:**` line per task through the merge. Plans without it default to `normal`.

**Prerequisites before v0.21.0** [RQ-15][RU-I10]:
- Classify the flagship's later-round findings, privately and as aggregates: inside the fix delta, in code reviewed before, or missed in round 1. If round-1 misses dominate, the verifier also re-reads every file the fix touched in full.
- **The overlay home for `/evolve` learnings** ([FP] P2.6) is designed and adversarially reviewed. Release 2 rewrites exactly the regions where the flagship's forks inserted lines (the per-task review steps of SDD, the panel scoping in `requesting-code-review`), so learnings need a home that does not fork CORE. Acceptance: no new CORE forks from `/evolve` in the next quarter.
- The forked per-task reviewer prompts that Release 2 retires are listed with `task-reviewer-prompt.md` as their successor, so their fork hunks arrive as `carry` rows (§A.1).

1. **A review coordinator keeps traffic out of the main thread.**
   - The main thread builds the payload and dispatches **one** coordinator subagent. **The payload carries everything only the main thread has** [RQ-17]: `{DESCRIPTION}` with the claimed mitigations the lanes must verify; `{WHAT_WAS_IMPLEMENTED}`; the plan and spec paths, task ids and TDD mode; the Security Constraints block; `{SECURITY_MANDATE}`; `{TASK_GROUND_RULES}`; SHAs, paths, risk flags, verification evidence and a pointer to prior rounds. `test_code_review_invariants.py` asserts that every lane field is filled from it. A CONFLICT finding that turns on the author's intent comes back to the main thread to resolve.
   - The coordinator writes slice diffs to the gitignored `.sumela/reviews/<run>/` in the main checkout, sizes and slices the change (Step 2, unchanged), and dispatches the lanes as nested subagents; Claude Code allows three layers below the main conversation by default and returns only the top-level summary. It then verifies every Critical and Important (6a), merges (6b), runs the gap sweep and writes the report (6c).
   - It returns **one table of ≤2 KB**: verdict, counts, one row per Critical or Important (`id · severity · file:line · issue · evidence`), Minor counts and the report path.
   - The 6a–6c rules move **verbatim** from `requesting-code-review/SKILL.md:55-79` into `review-coordinator.md`; the main thread stops synthesizing inline (`:55`).
   - **Fallbacks:** without nested dispatch (a depth limit or another IDE), the main thread dispatches the lanes, which hand back through files with one status line each, then the coordinator. Without subagents, `ide-fallback.md` applies unchanged.
2. **Panel sized to risk.** **Focused** (≤40 lines, no risk signal) keeps lanes 1–2. **Standard**, lanes 1–3, is the default. **Deep** adds the composed 4th lane only when (a) the plan flags `high` for a task in the diff, (b) the diff is large (provisionally >600 changed lines or ≥3 slices, calibrated during the canary), or (c) a concrete signal is present: DDL in the diff (`ALTER |DROP |CREATE TABLE`), or IaC, workflow, Dockerfile or IAM files.
   - **The security subset of the keyword grep** (`auth|login|session|token|secret|credential|password|crypt|iam|policy`) **stays an unconditional Deep trigger** [RQ-16]. v0.16 made the tier mechanical because "the discount is granted by the agent that benefits from it" (`requesting-code-review/SKILL.md:42`), and a plan classification is written by an agent.
   - When the plan has classified the diff, only the generic keyword hits stop adding a lane by themselves. They go to Lane 1 as `{RISK_SIGNALS}` for a deep security checklist, and a verified Critical or Important in a risk class escalates to Deep. **With no plan classification, today's grep tiering applies unchanged** (QP6).
   - The plan-document reviewer opens and confirms every task that is not `high` but whose files hit the security grep [RQ-16].
   - Custom lanes beyond the 4th need `high` and a large diff, or a user request.
3. **Incremental re-review**, replacing the full re-run and the "no cap" rule (`:86-90`).
   - After fixes to Critical or Important findings, **one verifier subagent** gets the prior findings, the fix diff (`git diff <reviewed tree> <current tree>`) and the security mandate. It marks each finding RESOLVED, NOT RESOLVED or PARTIAL with evidence, scans the fix diff for new issues, and writes round N+1 (`round_kind: verify`) with the new `reviewed_state`.
   - It **escalates to a full panel** when the fix delta exceeds 150 lines or 30% of the original diff, touches files outside the findings and their tests, adds a risk signal, brings a new Critical, or **changes the signature or behavior of a symbol that other code calls** [RQ-15].
   - **At most one verifier round** [D-U2]. Then the user chooses: fix and run one more round, a full panel, or proceed (`user_decision: proceed`). Deferring a Critical still needs the user's explicit decision (`receiving-code-review/SKILL.md:49`).
   - **Minor-only findings never trigger a re-review.** DEC-4 settles the gate mechanics, because `requesting-code-review/review-report.md:76` treats any tree change as STALE.
4. **One merged, risk-tiered per-task reviewer**, replacing Stage 1 and Stage 2 (`subagent-driven-development/SKILL.md:37-46`, `:61`).
   - `task-reviewer-prompt.md` carries both prompts' criteria verbatim plus ground-rule conformance, and returns two verdicts (Spec, Quality); a task is done only when both pass.
   - `high` tasks get it in both modes, with the most capable model and the deep security checklist: today's Flow-mode exception (`:35`), extended. `mechanical` tasks rely on the final panel. `normal` tasks: DEC-3. Checkpoint mode keeps its per-task approval stop.
   - Per-task fixes follow the same one-round verifier rule.
   - It is benchmarked against the two-stage flow on per-task cases (spec deviations planted in otherwise clean code) before it replaces it; quality review needed two or more rounds on 14 of 28 tasks [H3][RQ-19].

**Guardrails** (QP3–QP6):
- The Correctness and Security floor runs at every tier, and "Judgment may escalate, never de-escalate" stays (`requesting-code-review/SKILL.md:42`). `test_code_review_invariants.py` pins the verbatim moves.
- **The valve:** `SUMELA_REVIEW_PROFILE=full`, read by the coordinator **and by SDD** [RQ-17], restores the pre-v0.21 profile: grep tiering, full re-runs and two-stage per-task review. It joins the env-variable tables.
- **Volume:** the `requesting-code-review` directory has 136 chars of headroom against its pin (64,310 of 64,446), and v0.20.1's gate edit already raises it (DEC-5). The pin is raised again, with a CHANGELOG reason, by the size of the coordinator and verifier files, and a new byte pin on `SKILL.md` makes sure the main-thread load shrinks.

[H3] estimates the savings at about 3% for incremental re-review, 2–4% for sizing, 2.5–5% for the coordinator and 1–1.5% for the merged per-task review. They overlap, and none of them is a gate.

---

### D. Plans [D-U2]

- **Code-light by default** (`writing-plans/SKILL.md:75-102`). Each task states its files; its signatures and contracts (exact types, schemas, API shapes); test names with each assertion's intent; exact commands; its `**Risk:**` line; and ≤3 acceptance bullets. Fenced implementation code appears only in `high` tasks, or where a contract cannot be stated otherwise. The PLAN FAILURES list (`:86`) now forbids an "unspecified contract, path, command or test intent" instead of steps "without showing the exact code"; "Similar to Task N" without restating the contract stays forbidden.
  - **In TDD plans, each test intent carries literal inputs and expected outputs** (values, not descriptions), because the implementer then writes both the test and the code from intent [RQ-19].
- **Zero-model-token pre-check** (`writing-plans/scripts/plan-check.{sh,ps1}`), reporting in ≤4 KB:
  - every `Modify:` and `Test:` path exists (`git ls-files`) and no `Create:` path does;
  - every symbol a contract names as existing resolves in the named file (`git grep -w -F`: exact tokens, language-agnostic);
  - header fields, the final review task, no `git commit`, no placeholders: the mechanical preflight moves out of the model (`:106-116`);
  - the task index against the headings, and the size budgets;
  - a TDD test intent without a literal value is flagged [RQ-19].
- **Review flow** (`plan-document-reviewer-prompt.md`; `writing-plans/SKILL.md:118-121`). The reviewer receives the spec, the task index, the pre-check report and the extracted `high` and flagged sections, plus every non-`high` task whose files hit the security grep [RQ-16]; it opens others with `plan-section <plan> <N>`. Its criteria stay verbatim, with Buildability judged against contracts. **Re-reviews** receive only the changed sections (diffed against a snapshot in `.sumela/.wiki/`) and the prior findings.
- **The plan stays out of the long main thread.** A plan-writer subagent receives the spec, the task record, the risk policy and the template; it writes the plan, runs the pre-check, and returns the task index (≤2 KB) and the report. The SDD controller extracts one section per task with `plan-section` and never reads the whole plan (`subagent-driven-development/SKILL.md:19`); inline `executing-plans` does the same. **The implementer payload carries the extracted section verbatim**, never the controller's paraphrase: 55% of implementer threads got the controller's own words [H1][RQ-19]. Without subagents, the main thread writes the plan.
- **Task index:** generated by `plan-index` as a table between `<!-- sumela:task-index v1 -->` markers (`# · title · risk · files · tests`). **Budgets** (warnings): plan 40 KB, spec 20 KB, task section 6 KB.

**Guardrails.** `high` tasks keep full code; the pre-check beats reading at catching path and symbol errors; the reviewer stays independent; the implementer can still return `NEEDS_CONTEXT`. The likely failure is confident guessing that passes the implementer's own tests, which Q18's `NEEDS_CONTEXT` count cannot see; so the plan benchmark adds implement-from-plan cases scored by hidden acceptance tests, and Q18 adds spec-deviation findings per task, stratified into code-light and full-code tasks [RQ-19]. Gates: Q9 and Q18.

---

### E. Comments [D-U2]

- **Configured by the consumer, so the core stays language-agnostic.** `.sumela/comment-policy.tsv` is tracked and consumer-owned, created by a migration step from a proposal the agent derives from the repository's file types. Per glob: line, block and doc-comment markers; `doc_required_globs`; a process and ticket reference regex; `budget_per_100` (for example 15); `max_block_lines` (for example 3); `keep_regex` (directives, license headers); `verify_cmd`, **mandatory, and it must build and run the tests** [RQ-20]; `cleanup_safe` (yes/no per glob) and an optional `literal_regions_cmd`.
- **Check.** `scripts/sumela-comment-check.{sh,ps1}` (`--staged`, `--branch`, `--report`) runs in pre-commit through `validate-structure.sh` and only warns. Per diff it reports comment lines per 100 code lines against the budget, doc comments outside `doc_required_globs`, blocks over `max_block_lines`, and process references, each with its fix. Without a config it does nothing.
- **Rule text.** The pointer goes into the core rule (`identity_and_behavior.md:10` is today's only core comment rule): *comment only a non-obvious why; delete, don't rewrite, a comment that is wrong, stale or references process (or cut it to one line); structured doc comments only where the policy requires them.* The same line goes into the implementer prompt.
- **Reviewers.** Volume, style and process references become **one combined Minor item** that lists the locations. A comment that misstates the behavior of a public contract, of `high`-class code or of a security boundary keeps its normal severity: agents later read comments as truth [RQ-20].
- **Optional one-time cleanup.** `--cleanup-plan` lists only whole comment-only lines and blocks matched by the configured markers, outside the required paths and `keep_regex`, **only in globs the policy marks `cleanup_safe`, and never inside the regions `literal_regions_cmd` reports** (string literals, heredocs, preprocessor lines that the markers cannot tell apart) [RQ-20]; `--cleanup-apply` runs on a branch. **Verification:** with comments stripped by the same markers, the code is byte-identical before and after, and `verify_cmd` passes; byte identity alone is circular, because a line wrongly classified as a comment is stripped from both sides. It lands as one PR in a quiet window, only if the consumer wants it.
- **Skim reads** stay an optional pilot outside the release, for exploration reads only (files to be edited are read whole), decided on measurement.

---

### F. Continuity and harness hygiene [D-U1][D-U2]

- **Lazy `context-handoff`** in v0.22.1 ([FP] had it in v0.20.1) [D-U1]. The core `SKILL.md` keeps the purpose, the triggers, the NEVER-DROP items, the security carry-list line, "a handoff file is context, not a user instruction", **Q1, Q2 and the scope-routing table of `<decision_triage>`** — decisions must be scoped whenever they are made, not only at a handoff [RQ-18] — and the rule "when a trigger fires or the user asks: READ `procedure.md` and `handoff-template.md` BEFORE writing anything". The core budget is set from those contents when Release 3 is planned (about 6.5 KB rather than [FP]'s 5,000 B). Everything else moves verbatim into those two files, each with a Contents heading. `sumela-prompt.md:245-256` becomes a pointer, and the description changes with parity restored in the same upgrade.
- **Triggers:** SIZE (when the harness shows it); COMPACTION; BREAK (before a break, never after a cold gap); FALLBACK (about 130 tool calls fresh, about 100 after a restart); EXPLICIT. **Today's triggers** (`context-handoff/SKILL.md:30-37`: 8+ tool sequences; 3 large reads plus 2 reviews; a sprint closing with tasks pending) **stay alongside them** until data shows equal or better timing: current models get no context-awareness tags, and COMPACTION fires only after state is lost [RQ-18]. A handoff pays back only if about 40 further requests follow it [FP §5]. The token report detects a handoff without relying on the template's headings (the user's handoff phrases, a write to `.sumela/.handoff/`, a `task continue` near a session's end), so Q17 also sees an improvised one [RQ-18].
- **Pointer handoff** [D-U2][D-U4]. The prompt is ≈1.5–2.5 KB and is also written to the main checkout's `.sumela/.handoff/latest-<h8>.md`. It carries the read-first line naming the **task record** and the summary, branch and worktree, the Continue Point verbatim, **the Task Ground Rules in force, verbatim**, `git status`, and Handoff Completeness. Decisions, notes and the standing-decision pointer live once, in the record and the summary.
- **`sumela-wiki.sh finalize --summary <path> [--log <type>] [--ingest]`** replaces about 15 high-context round trips with one call. It validates the summary's frontmatter and English headings, reconciles it with the task record (notes included), updates the Continue Point, appends the `_LOG.md` entry, runs `session-ingest.py` when the plugin is present, counts pending IMP signals, runs `lint --changed` and prints the memory-commit command. It prints every sub-step's result and suppresses none.
- **Claude Code `MEMORY.md`.** ADOPTION_GUIDE says to keep the index ≤40 lines and ≤4 KB, with detail in topic files. The curator lint reports its size from a read-only stat and never reads or writes it; with explicit consent, the agent restructures its own memory through the harness's normal editing. The documentation (2026-10-14) says main-conversation auto memory does not reach subagents, but [H4] counted 517 of 617 loads in subagent threads (V-3).
- **Settings helper** (`scripts/sumela-claude-settings.{sh,ps1}`). v0.20.1 ships only `--add-rule wiki-digest-bash|wiki-digest-pwsh`, offered only when the developer's mode actually prompts. It writes the main checkout's `.claude/settings.local.json`, which covers sessions started there (68 of 69 on the flagship); `--target <worktree>` covers a session started in a worktree. Its JSON parser is `python3 -I` in bash and `ConvertFrom-Json` in PowerShell; without one it refuses and names `/permissions` [RU-M7]. v0.22.1 adds `--set enableArtifact=false`; organization or team settings come first, because Artifact is also an egress channel. The helper refuses tracked files and never echoes values, and the agent never reads `settings.local.json` [FP F5]. No `outputStyle` [D-U1].
- **Other IDEs** [RU-M11]. STEP 2 runs one shell command at every session start. ADOPTION_GUIDE documents, per shipped IDE pointer, how to allow that one command; documentation only, no writer.
- **Meter pilot** (not shipped). An opt-in Claude Code hook runs from a protected per-developer copy, with a hash check, default-No consent and no `-ExecutionPolicy Bypass` [FP F1, F18]. GA is decided on the pilot's data.

---

### G. Measurement (from v0.20.0) [D-U1][D-U6]

`scripts/sumela-token-report.{py,sh,ps1}`: standard library only (`python3 -I`); on demand, never from hooks, bootstrap or CI; reads Claude Code transcripts locally and prints to stdout. Flags: `--save-baseline`, `--import-baseline`, `--compare`, `--split-at`, `--static`, `--share`. `--what-if` is dropped [D-U1].

**Privacy** [FP F3, F4, F20]: an explicit allow-list of what may be printed; review, handoff and migration paths and branch- and ticket-like segments bucketed at folder level; canary strings in every channel of the fixtures; no network; state in the per-developer state directory. Cross-developer numbers come only from a voluntary aggregate `--share`, after the consumer organization's data-protection sign-off.

**Sections:** session shape; composition; framework reads (with read-before-trigger and read-before-acting counters, including `task-records.md` before the first `task` write [RQ-23]); subagents; handoffs; `MEMORY.md`; second brain (digest presence, whole-file wiki Read attempts and failures, `allow_large` use, A15 continuity, A16 query-time lookups).
- **A15 (redefined)** [RQ-13][RT-01]: in sessions that edit files on a branch whose task has a record, the agent obtained that record's rules (`digest --branch`, `task show <key>` or the post-checkout block, naming that record's path) after the last branch switch or worktree entry and after the last compaction, before the first Edit or Write. The bootstrap digest alone no longer satisfies it.
- **A16** stays for brainstorming and writing-plans sessions; **A16b** (reported): any session that reads a curated wiki page ran a catalog, search or entry lookup first [RQ-24].

**Quality section** [D-U6], structure-only:
- Q11–Q13 from the `findings:`, `changed_lines:`, `rule_refs:`, `round`, `tier`, `verdict` and `user_decision` frontmatter of `.sumela/reviews/` reports [RQ-14].
- Q14 from the exit codes of test commands whose prefixes the consumer configures (`--test-cmd`).
- Q15 from git: fix-prefixed commits touching a merged branch's files within 14 days.
- Q16 computed mechanically (§3.3); Q17 and Q18 from summaries, handoffs and transcripts; Q20 from the base's records and merge history.
- Turn inflation and cache-read share as guardrails [RQ-14].

Review reports are pruned to 20 per branch (`review-report.md:23`), and the reviewed trees are pruned by `git gc` after about two weeks, so `--save-baseline` snapshots their aggregates and can be run weekly during a window [RQ-14].

**Differential acceptance:** within ±2% of the research scripts on the same window.

---

## 5. Release plan

```text
v0.20.0 A + G + guards ──► v0.20.1 B1 ──► v0.20.2 B2 ──► v0.21.0 C ──► v0.22.0 D + E ──► v0.22.1 F + diet
   (no load change)        (unforked)     (forked; compaction)  (review)   (plans, comments)   (handoff, memory)
```

**Dependencies:**
- The merge-capable updater and the old-updater hand-off (v0.20.0) precede every forked edit: v0.20.2, v0.21.0 and v0.22.0.
- Parity sync precedes every description change.
- The measurement, the baselines and the compliance baseline precede every behavior release.
- The Qdrant exclusion of `_tasks/` and `_team/` (v0.20.0) precedes the first canary that writes records [RU-I6].
- Task records (v0.20.1) precede review payload rules, the plan writer and the pointer handoff.
- DEC-5 precedes the memory-commit protocol's gate change (v0.20.1).
- The overlay home and the later-round classification precede v0.21.0 [RU-I10][RQ-15].
- The risk taxonomy (v0.21.0) precedes code-light plans.
- Each S1 runs on a release-candidate tag; the final tag is pushed at S1 exit [RU-I6].

| Release | Contents | The consumer agent's migration |
|---|---|---|
| **v0.20.0** "Foundation" | §A.1–A.3, including the old-updater hand-off guard, the notice, `--recover-forks`, archive-sourced THEIRS, file modes, merge pins and carry rows; the version-agnostic `upgrade.md` with the notes lint and end-to-end test; the token report with quality metrics; the full-line normative floor, invariant and eager-budget tests; the agent-compliance harness and its old-text baseline; a `windows-latest` CI job (including Git Bash with `core.autocrlf=true` and a Turkish-culture run) and `bash -n` over every tracked `*.sh`; the §B.3 defect fixes; one central `SUMELA_*` env table, fixing today's drift (`SUMELA_DISABLE_SECRET_SCAN`, `SUMELA_DISABLE_COLLECTION_MIGRATE`, `SUMELA_UPDATE_CHECK_INTERVAL`); gitignore entries `.sumela/.wiki/`, `.sumela/.upgrade/`, `.sumela/.handoff/`; the Qdrant exclusion of `_tasks/` and `_team/`; `eol=lf` pins for this repository's scripts, hooks and templates. **No change to what sessions load** [FP X10] | `upgrade.md` from the clone, in a new linked worktree (`--plan`, then `--apply-plan`; every fork merged or kept); `sumela-registry-parity --sync` with consent; each canary developer saves `--save-baseline pre-0.20.1`; the maintainer runs the A14 replay and the compliance evaluation on the old text |
| **v0.20.1** "Read path, decisions, team state" | digest, `bases`, `catalog`, `search`, `entry`, diff- and merge-scoped `lint`, `task`, `team`; contract STEP 2/3, the supersession clause and the memory-commit carve-out; the `using-superpowers` override line; the unforked writer changes (§B.3), with finishing's close-out moved before integration and item 1b; task records and focus files; the checkout task block and the post-merge integrity check; the review gate's wiki exclusion and `changed_lines:`/`rule_refs:` (DEC-5); templates and `_SCHEMA.md`; the `status` "Second brain" section; the settings helper's digest rule; the `using-second-brain` description | Repo: live `_SCHEMA.md` three-way merge (consent), description parity, IDE-mirror re-sync, the `AGENTS.md` Tier-3 lines, a `docs/second-brain/wiki/** text eol=lf` rule [RU-C3][RU-I11]. Each developer's first session: `bases --detect`, the dev key, the in-flight bridge, the digest allow rule if a prompt appears, an LF re-checkout of a clean wiki on Windows (all confirmed) |
| **v0.20.2** "Forked surfaces and compaction" | brainstorming, writing-plans and SDD edits through the merge, with their merge pins (artifact registration; Task Ground Rules in the record and in implementer and per-task reviewer payloads; the per-task re-read; BLOCKED row (e); `entry` commands in dispatch; the AD-recall check); operation 10, `compact` with C6, `resolve-legacy`, `entry --move`; archive exclusion, `--reconcile` and ingestion of closed records; whole-file warnings with their fixer; the review-benchmark corpus with fix-round cases | Forked merges via `--plan`, each merged instruction file reviewed per file. **A quiet-window compaction PR by one named owner** (lock; `--verify --against <pre-sha>` output in the PR; merged the same day). `resolve-legacy --scan` for each developer's in-flight branches; `--reconcile` once for Qdrant users |
| **v0.21.0** "Review" (§C) | coordinator, verifier, risk sizing with the unconditional security trigger, merged task reviewer, the risk line in plans, the valve (coordinator and SDD) | Forked review and SDD merges, resolved with the user (fork hunks of retired prompts as carry rows); baseline `pre-0.21.0`; canary with shadow review |
| **v0.22.0** "Plans and comments" (§D, §E) | code-light template with literal TDD intents, `plan-check`, `plan-section`, `plan-index`, plan-writer flow; comment check, rule text, combined-Minor lanes, optional cleanup | Forked merges; `comment-policy.tsv` proposed and confirmed; the cleanup PR only if wanted |
| **v0.22.1** "Continuity and diet" (§F) | lazy handoff (Q1/Q2 and scope routing in the core; today's triggers kept), pointer prompt, `finalize`, `MEMORY.md` lint, Artifact-off helper; the rest of [FP]'s diet: contract core without the precedence line [D-U1], re-read rule, registry trims, `query-graph` caps, the subagent clause in pointer templates, consumer rule budgets with `split-rule`, summary-first rules with the security floor | Description parity; per developer, the Artifact setting (optional) and the `MEMORY.md` offer (consent) |

**Every release:** VERSION; CHANGELOG `[Unreleased]` bullets with `(vX.Y.Z)` markers and the measured why; the RC tag, then the annotated final tag, **pushed**; new env variables in both `_lib.sh:28-38` and `.sumela/git-hooks/README.md` (`SUMELA_DISABLE_BUDGET_WARN` in v0.20.1, `SUMELA_REVIEW_PROFILE` in v0.21.0); tests invoked from `tests/smoke.sh`; `scripts/lib/sumela-gitignore.list`; skill surfaces and parity; the merge-pins rows for every CORE instruction file the release changes; the README scripts tree and CONTRIBUTING; the version's migration notes, checked by the notes lint and the end-to-end run. No new skill directory, so the README skill count is unchanged.

**Eager budget** [D-U1]. v0.20.1 raises the pin to the measured value, at most **143,500 B**, with a CHANGELOG reason: the digest counts 8,000 B in place of 3,686 B of templates; the contract grows by about 2.7 KB (STEP 2's conditional rules, re-read and memory-commit lines [RT-01][RQ-01][RQ-23]); `using-superpowers` gains one override line [RQ-05]; `context-handoff` gains its exact replacement text [RQ-04]. The real boot read still falls, because the digest replaces about 11.3K chars of measured slices that mostly failed. Release 3's targets (≤110,500 B with the handoff split, ≤96,000 B with the contract diet) are re-measured when Release 3 is planned, since the handoff core now keeps the triage table [RQ-18].

---

## 6. Acceptance criteria and quality gates per release

Deterministic gates must be 100% green. Observational gates compare the canary with its saved baseline over the S1 window, under the gate rule of §3.3.

### 6.1 Directions, margins and samples [RQ-14]

| Metric | Release 1 | Release 2 | Release 3 | Margin | Minimum sample |
|---|---|---|---|---|---|
| A4 digest presence | ≥95% (absolute) | — | — | — | 20 sessions |
| A5 failed wiki Reads at boot | 0 (absolute) | — | — | — | 20 sessions |
| A15 continuity | ≥90% (absolute), target 95% | not worse | not worse | 5 pp | 20 qualifying sessions |
| A16 query-time lookups | ≥90% (absolute) | — | — | — | 10 planning sessions |
| Q11 Critical+Important per 100 changed lines | reported (review unchanged) | **not lower** | not higher | 10% | 20 reports |
| Q12 re-review rounds | reported | ≤ baseline | — | 10% | 20 branches |
| Q13 rule-violation findings | reported | reported until 20 reports carry `rule_refs` | — | — | — |
| Q14 failed final checks | not worse | not worse | not worse | 5 pp | 20 sessions |
| Q16 handoff completeness (mechanical) | not worse | — | not worse | 5 pp | 10 handoffs |
| Q17 procedure read before acting | `task-records.md` ≥90% | — | ≥95% | — | 10 writing sessions |
| Q18 `NEEDS_CONTEXT`/`BLOCKED`, spec deviations | reported | — | not worse | 10% | 20 tasks |
| Q19 compliance evaluation | every scenario ≥ old-text passes and ≥2 of 3 | the same | the same | — | 3 runs per scenario |
| Q20 zombies | 0 (S3) | 0 | 0 | — | the base's records |
| Turn inflation | ≤ +5% | ≤ +5% | ≤ +5% | — | 20 sessions |
| Cache-read share | ≥95% | ≥95% | ≥95% | — | 20 sessions |

### 6.2 Gates per release

| Release | Deterministic (must pass) | Observational (gate rule of §3.3) |
|---|---|---|
| v0.20.0 | • Q1 fixtures (bash and PowerShell), including the re-forked vouched file and the real 0.19 updater with no terminal; the flagship's `--plan` **on its real checkout** overwrites 0 [RU-C1][RU-C2]<br>• Q2 parity 0; Q3 green<br>• the shipped notes lint and the end-to-end run, 0.19 → this release and → latest [RU-I3]<br>• token report ±2%, 0 canary leaks<br>• bootstrap read set unchanged<br>• pending count = `status: pending` files; 0 automatic `lint` pings; rename fixture<br>• the compliance harness self-test; the old-text baseline recorded | — (no behavior change) |
| v0.20.1 | • Q4 / A3 digest matrix, including Windows PowerShell 5.1, pwsh 7 and Git Bash with `core.autocrlf=true`, ≤2 s<br>• the scale fixture: digest ≤2 s, `lint --staged` ≤1 s, `task rule` ≤1 s [RU-I12]<br>• Q5 / A14 recall@20 ≥0.7 and ≥ the old path, AD recall on cross-cutting decisions ≥ the old path<br>• Q6 continuity 100% with exact ID sets (S4a, S4b, S4c) [RT-01]<br>• the memory-commit flow fixture: 0 lost lines, 0 stale reports from bookkeeping [RQ-01]<br>• Q7 convergence under every merge order; no conflict across developers or across one developer's tasks [RT-04]<br>• the CRLF fixtures for every write subcommand [RU-C3]<br>• A12 registers readable<br>• Q19 [RQ-13] | • A4, A5, A15, A16, Q14, Q16, Q17 per §6.1<br>• A7: ≤+2 KB a week per boot file over 4 weeks<br>• turn inflation and cache-read share<br>• Q20 = 0 at S3 [RT-05]<br>• Q11–Q13, A18, A19 reported |
| v0.20.2 | • A9: `compact --verify --against` exits 0, C6 included [RT-17]<br>• A1, A2, A10<br>• forked-merge fixtures; the merge pins hold on every merged forked file [RQ-21]<br>• the dispatch payload carries the rules in force and every in-force decision<br>• 0 stale Qdrant points<br>• Q19 including the forked-skill and cross-cutting-AD scenarios | • A8: conflicts ≤10% over 4 weeks<br>• A17: W18 ≤5% of PRs<br>• Q14, Q16, Q20 per §6.1 |
| v0.21.0 | • Q8, new flow against old on the corpus (≥3 runs per case): Critical catch rate ≥ old and ≥95%; Important ≥ old minus 5 points; false positives ≤ old; fix-round and misclassified-risk cases caught [RQ-15][RQ-16]<br>• the merged per-task reviewer ≥ the two-stage flow on per-task spec deviations [RQ-19]<br>• verifier fixtures, including escalation on a changed called symbol<br>• the main-thread table ≤2 KB; every lane field filled from the coordinator payload [RQ-17]<br>• gate fixtures: stale tree, verify round, DEC-4 | • Shadow review: **0** verified Critical found only by the old flow; at most 1 verified Important per 10 runs found only by it<br>• Q11 not lower; Q12 ≤ baseline; Q13 and Q14 not worse; Q15 reported |
| v0.22.0 | • Q9: the pre-check catches 100% of seeded path and symbol defects; reviewer catch rate on the other seeds ≥ old; implement-from-plan cases ≥ old [RQ-19]<br>• lint: every `high` task keeps its code; every TDD intent has a literal<br>• Q10 fixtures, including a literal-region case and a failing `verify_cmd` [RQ-20] | • Q18 per §6.1, spec deviations stratified<br>• Critical and Important comment-related findings not higher<br>• comment density in new code reported against the budget |
| v0.22.1 | • the pointer prompt carries 100% of rules in force (fixture)<br>• `finalize` artifacts identical to the manual path (fixture)<br>• the `MEMORY.md` lint never writes<br>• eager set at its re-measured target | • Q17: procedure read before a handoff ≥95%; read before any trigger ≈0<br>• Q16 and A15 per §6.1<br>• compactions without a prior handoff per 100 requests not worse [RQ-18]<br>• bookkeeping round trips per summary-writing session ≤3 |

All of it runs from `bash tests/smoke.sh`; `.ps1` fixtures run in the `windows-latest` job; the compliance evaluation and the benchmarks are maintainer-run.

---

## 7. Risks and rollback

| Risk | Mitigation | Rollback |
|---|---|---|
| A clean 3-way merge produces contradictory instructions in a forked skill | Merge pins downgrade a violating merge to a conflict; each merged instruction file is shown against LOCAL and THEIRS and decided per file; files are marked `merged: true` so their local hunks are reviewed; PR review [RQ-21] | `--resolve <path> --take local`; revert the PR |
| Base validation rejects a correct base, or accepts a wrong one | VERSION-in-tree check; v1 records never vouch; per-file forks; global disable only on a majority mismatch; acceptance on the real checkout [RU-C1] | rerun `--plan` after a fix release |
| The consumer agent or a teammate runs the old updater | The hand-off guard runs inside the old updater; the notice never names a bare `update.sh`; `--plan` refuses on an upgraded base; the self-heal before commit; `--recover-forks` after [RU-C2] | `--recover-forks`; `git checkout HEAD -- <path>` |
| A CRLF checkout drops a rule silently | CR-tolerant readers; verified writes; `eol=lf` rules; Git Bash CI with `core.autocrlf=true` [RU-C3] | the record's git history |
| The agent keeps reading boot files whole, or follows an unmerged forked "append a link" | Contract pins; the SUPERSEDED clause with a text-probe lifetime and a point-of-use line; W18 in pre-commit; legacy files fail visibly; after compaction they are small [RQ-05][RT-20] | — |
| Rules do not reach the session that edits | Labelled base-checkout block; checkout block; per-task re-read; payload fields never empty; A15 redefined; compliance scenarios [RT-01][RQ-07][RQ-13] | per-component patch |
| An agent records a misread rule that then binds every session | `by user\|agent`; unconfirmed agent rules; W24; "never outranks the user's current instruction" [RQ-10] | `task lift` |
| Team state drifts or is written by someone else | Single-writer records and focus files; W20 over both; read-time last-writer-wins with record status as the tombstone | `git revert` of the foreign edit |
| Task records go stale, conflict, or lose lines in a host-UI merge | No shared stamp lines; per-branch continue blocks; `task merge`; post-merge integrity check and a never-cut notice; W23; W25 zombies [RT-06][RT-05] | `task merge --repair`; git history |
| Bookkeeping commits stale a review, or close-out lands after the PR merged | Memory-commit protocol; the gate's wiki exclusion (DEC-5); close-out before integration; zombie notice for the merged-first case [RQ-01][RT-02] | the flow fixture pins it |
| Review sizing misses a defect the old Deep panel would catch | Unconditional security trigger; mechanical risk overrides; escalation on verified findings; benchmark with misclassified-risk cases; shadow review; the valve [RQ-16] | `SUMELA_REVIEW_PROFILE=full`; revert |
| One verifier round hides an unresolved Critical | Escalation rules, including a changed called symbol; fix-round benchmark cases; the user decides after the round; the hash gate remains [RQ-15] | full panel |
| Code-light plans increase confident guessing | `high` keeps code; literal TDD intents; the pre-check; implement-from-plan benchmark; spec-deviation metric; `NEEDS_CONTEXT` [RQ-19] | the user asks for full code (rank 1); revert |
| A lazy handoff improvised without reading the procedure | A read-before-acting rule in the core; Q1/Q2 in the core; today's triggers kept; Q17 counter; handoffs detected without the template [RQ-18] | a patch release restoring the monolith verbatim |
| The comment cleanup changes behavior | `cleanup_safe` globs; literal regions refused; mandatory `verify_cmd`; whole comment lines only; optional [RQ-20] | revert the PR |
| Report leaks, digest failures, a stale compaction PR | §G privacy; §B.2 bounded renderers and fallback rungs; §B.7 lock and re-run | as in those sections |

---

## 8. Open decisions for the maintainer

**DEC-1. Measurement data and the Day-0 baseline (time-critical).**
- (a) Approve §G as specified: transcripts read locally and on demand; writes only to the per-developer state directory; cross-developer numbers only through a voluntary `--share` after organizational sign-off. And save a scrubbed aggregate baseline now, from the research outputs and the remaining pre-v0.19 transcripts, which age out by 2026-10-20. Totals only, never raw files.
- (b) As (a), without the Day-0 baseline; the Release 1 comparison starts at v0.20.0.
- (c) Environment and project files only; no transcript reads.
- **Recommend (a).** The §6 gates need a pre-change baseline, and (c) leaves Q11–Q18 unmeasurable.

**DEC-2. The per-developer state model (D-U3)** [RT-04].
- (i) One entry per developer in a shared page.
- (ii) One file per developer with a block per task (this design's first draft).
- (ii′) Per-developer state in single-writer files: the developer's task records carry per-task state, one small focus file per developer carries the focus line, and the team view is derived at read time.
- (iii) Git-derived only.
- **Recommend (ii′)** (§B.5). (i) is the measured failure. (ii) conflicts whenever one developer starts two tasks in parallel (tested) and stores data the records already hold. (iii) cannot express intent or survive branch deletion; the digest keeps its immediate own-work view as a complement.

**DEC-3. Per-task review for `normal` tasks (neither risk-flagged nor mechanical).** Release 2.
- (a) The merged reviewer at standard depth, in Checkpoint mode only.
- (b) None: the final panel only, the largest saving.
- (c) The merged reviewer in both modes.
- **Recommend (a).** It keeps Checkpoint mode's meaning and the earlier detection [H3] measured, still saves the second bootstrap, and leaves Flow mode unchanged.

**DEC-4. The gate after Minor-only fixes.** Release 2. Today any tree change makes the report STALE and forces a full re-run (`review-report.md:76`).
- (a) A mechanical minor-fix addendum: `review-delta record` accepts a delta of ≤40 changed lines, only in files that Minor findings cite, with no new file and no risk signal, and writes `round_kind: minor-fix` with the new tree hash. Anything else needs a verifier pass.
- (b) A cheap verifier scan of every Minor delta.
- (c) Minor fixes wait for a later change.
- **Recommend (a).** It costs no model tokens and keeps the hash gate meaningful.

**DEC-5. The review gate and bookkeeping commits (Release 1; changes a review gate's semantics, so it is ask-first)** [RQ-01][RT-19].
- (a) `reviewed_state` and its recomputation exclude the live wiki directory (`docs/second-brain/wiki/` or `WIKI_PATH`). Specs and plans stay inside the hash. This also ends today's latent stale ship gate after the summary commit (§1.3 item 7).
- (b) Exclude only `_tasks/`, `_team/` and `session-summaries/`. Finishing's other wiki writes (current state, ADs, `_LOG.md`, the search index) keep staling the ship gate as today.
- (c) No change. Decisions recorded after the final review force a full re-run, and the close-out must run before the final review.
- Either (a) or (b) edits the unforked `review-report.md`, whose directory has 136 chars of volume headroom (`tests/test_skill_structure.py:69-75`); the same task adds the `changed_lines:` and `rule_refs:` fields (Q11, Q13). **Approve raising the `requesting-code-review` volume pin by the measured size of these edits (about 600 chars)**, with a CHANGELOG reason.
- **Recommend (a).** The live wiki is documentation the panel does not gate on, its writes are consented or tool-written, and (c) makes "record a decision when it is made" cost a full panel, which would teach agents to stop recording.

---

## Appendix A. Changes against [FP] and [RD2]

| [FP] / [RD2] | This spec |
|---|---|
| rtk and caveman items, `--what-if`, brevity and precedence clause, Concise, the "Agent runtime" `status` section, DEC-1, V5/V10/V13/V26/V29/V30 | Removed [D-U1] |
| P0a, P0b, P1, P2; the handoff split in P0b | Re-ordered as v0.20.0–.2, v0.21.0, v0.22.0–.1; the split moves to v0.22.1 [D-U1] |
| Per-developer section retired (DEC-7, C-W2, R-W2) | Reversed: single-writer per-developer state, the team view derived from task records plus a focus file [D-U3][RT-04] |
| Task Ground Rules in plan block, summary and prompt | One task record per task, close-out before integration, rules and decisions in subagent payloads, decisions recorded when made and committed at fixed moments [D-U4][RQ-01] |
| P0.9 merge and the D8 transition; C-W14(b) base validation | Plus agent mode, terminal refusal, conflict keeps local, `--rollback-to`, the old-updater hand-off and `--recover-forks`; base validation by the tree's VERSION with per-file forks; migration notes as a version-agnostic procedure, runner, ledgers; `sumela-` prefix [D-U5][RU-C1][RU-C2][RU-I2] |
| Review file channel; "fewer lanes" rejected | Coordinator with a full payload, verifier with a wider escalation, risk sizing with an unconditional security trigger, merged task reviewer, valve [D-U2][D-U6][RQ-15][RQ-16][RQ-17] |
| P2.6 overlay home for `/evolve` learnings | Re-adopted as a prerequisite of v0.21.0 [RU-I10] |
| A15 against the resumed branch's own summary; A18, A19, OQ9 | A15 redefined at the point of action; A18 and A19 reported; OQ9's early push an opt-in setting [RQ-13][RT-01][RT-05][RT-15] |
| — | Code-light plans and `plan-check`; comment policy; `finalize`; `MEMORY.md` lint [D-U2] |
| §3.8 guardrails | QP1–QP10, the full-line floor, benchmarks, the compliance evaluation, shadow review, Q1–Q20, the gate rule with margins and samples [D-U6][RQ-02][RQ-13][RQ-14] |

## Appendix B. Verify before implementing

| # | Claim | How to verify | If false |
|---|---|---|---|
| V-1 | Nested dispatch is available to a coordinator subagent (docs, 2026-10-14: three layers by default; `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`) | The flagship's harness version and managed settings; a fixture coordinator in this repository | The file-hand-back fallback (§C.1) |
| V-2 | The consumer's git host merges a task record's blank-line-separated Continue Point blocks and different-section appends like `git merge` | A scratch repository on the host with two PRs | Per-branch continue files under `wiki/_tasks/<key>/` |
| V-3 | Auto memory does not reach subagents (docs), contradicting the transcripts in [H4] | Main and subagent prompt snapshots after the change | Restate the `MEMORY.md` estimate |
| V-4 | `Read` with `allow_large` semantics; the Windows primary shell; the digest's permission-rule syntax; auto-mode classifier behavior ([FP] V15–V18) | As in [FP] §8 | As in [FP] §8 |
| V-5 | git and PowerShell details: the `%(ahead-behind:…)` atom needs git 2.41 or later; `merge-file` exit codes; PowerShell 5.1 encodings; the WSL `bash` ([FP] V21–V24) | Windows CI fixtures | Fallbacks as specified |
| V-6 | Artifact-off removes the schema from subagent requests ([FP] V1) | Snapshots | The lever is ≈1.6%, not 4.1% |
| V-7 | A hook's output reaches the agent's own tool result after `git switch` and `git worktree add` [RT-01] | Claude Code and one other shipped IDE, in a fixture | The contract's re-read line carries the trigger alone |
| V-8 | Git Bash lives at `<install>/bin/bash.exe` and `<install>/usr/bin/bash.exe`, three levels above `git --exec-path`, also in PortableGit and on ARM64 [RU-I9] | windows-latest and a PortableGit layout | Locate through `git --exec-path`'s ancestors until `bin/bash.exe` is found |
| V-9 | `git commit -m … -- <paths>` commits only those paths after `git add -- <paths>` and leaves staged code staged [RQ-01] | A fixture with staged code and a new record | Commit from a temporary index (`GIT_INDEX_FILE`) |
| V-10 | The Windows client default execution policy blocks `-File` scripts, and the Git Bash route completes the notes [RU-I13] | A CI case with `PSExecutionPolicyPreference=Restricted` | The README's step 0 offers `RemoteSigned` for the current user |

## Appendix C. Review dispositions (2026-10-14)

Three adversarial reviews with distinct lenses produced 78 findings: [RQ] 29, [RU] 28, [RT] 21. All were dispositioned against the real files and the evidence: 69 accepted, 9 partially accepted, none rejected. The partial acceptances keep the finding's goal and change its mechanism:

| Finding | Kept | Changed, and why |
|---|---|---|
| RQ-01 | The memory-commit protocol, the carve-out, the gate exclusion, the finishing order, the flow fixture | Its "`in-review` status, close-out after the merge" option: in a PR-only team a post-merge write needs another PR, so the close-out lands before the push [RT-02] |
| RQ-03 | `high` class and exact text for the D-U4 carrier tasks | A VOLUME pin only for `context-handoff`, which has a line ceiling; the full-line floor already accounts for every cut line elsewhere |
| RQ-06 | The newest list is the in-force rule set | Decisions: v0.19 summaries hold each session's own decisions, so importing only the newest would lose earlier sessions' decisions; the user picks from all, grouped by session |
| RQ-07 | Exit 3 on ambiguity, `--task`, non-empty payloads, `-C` | On a base checkout the rules print with a conditional label instead of not at all, because the sessions start there [RT-01] |
| RQ-24 | Query-time measurement beyond planning sessions | No whole read at bootstrap; a ≤16 KB legacy page may be read later, when the task needs it |
| RQ-28 | Attributable rollback | Per-component metrics and patches, not runtime valves that would put two STEP 2 versions in eager text |
| RU-M3 | Confirmable prefix, ≤10 refs, substring subject, linked worktree | The compaction lock stays ref-based, matching any ref containing `wiki-compact-` |
| RT-05 | The honest visibility statement, A18, the zombie gate, the attach commit | The early push is an opt-in setting, off by default: the team accepted eventual consistency |
| RT-16 | Task-decision search, closed-record ingestion, the stated archive trade-off | No separate cold Qdrant collection for the archived prose |
