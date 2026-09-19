# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Core framework version is tracked in `.sumela/VERSION` (consumed by `scripts/update.sh`).
Releases are also tagged `vX.Y.Z` (matching `.sumela/VERSION`) so the pull-time update
check can detect a newer upstream via `git ls-remote --tags`.

## [Unreleased]

### Changed

- **Most decisions are scoped to the TASK, and v0.18.0 had nowhere to put them (v0.19.0).** The
  triage introduced in v0.18.0 had three buckets: project-level (permanent, becomes an AD),
  agent-workflow (goes to `/evolve`), and "tactical" — which meant the session summary and nothing
  else, so it died with the session. That last bucket was doing far too much work. The decisions a
  task actually accumulates are things like *"we are not touching the corporate side in this
  task"*, *"we never edit another domain's code — we open a ticket for that team"*, *"skip the
  migration, it goes in the follow-up"*. None of those is a project truth an AD should record, and
  all of them must hold for every session of the task. v0.18.0 dropped them, which is the exact
  failure the release was written to fix.

  There is now a fourth bucket, presented as the common case rather than an edge one:
  **`## Task Ground Rules`**. They are written to the plan artifact when the task has one, to every
  session summary, and into each handoff prompt directly after the Continue Point — carried forward
  and PRUNED each handoff, with a retired rule struck through and dated rather than deleted
  silently. They retire with the task; one that turns out to hold beyond it was never task-scoped
  and goes through operation 5's normal ask instead.

  **They are enforced, not merely recorded.** `writing-plans` captures them at the moment they are
  agreed — during scoping, which is where they actually come from and where they were previously
  lost. `executing-plans` reads them before writing any code and treats a plan step that appears to
  require breaking one as a conflict to raise, not a rule to set aside. `<minimum_viable_handoff>`
  puts them in the NEVER-DROP tier beside the checkpoint: dropping a constraint leaves no visible
  gap, it produces an agent confidently doing work it was told not to do.

  This also settles a standing contradiction. `using-second-brain` declares `artifacts/` write-once
  while `context-handoff` has always appended `[CHECKPOINT]` blocks to plan files. The rule now says
  what it means: the plan BODY — intent, steps, acceptance criteria — is immutable, and there are
  exactly two designated append blocks. Rewriting a step to encode a ground rule is still a
  violation.

- **Eleven defects found when a real project upgraded into v0.18.0 (v0.19.0).** A consumer
  install ran a review panel over the vendored diff the day v0.18.0 shipped. The upgrade itself
  was clean; what it surfaced were defects inside the release, and two older ones the round
  exposed. All eleven were reproduced against this repo before being fixed.

  **A refusal could become a write one session later.** `<decision_triage>` recorded both "the
  user declined the AD capture" and "context was too tight to ask" as the same `AD candidate`
  line, and `finishing-a-development-branch` — a mandatory, non-interactive step — promoted those
  lines unconditionally. So a decision the user had explicitly refused got written at branch
  finish with no second ask, narrowing *"NEVER auto-capture without approval"* into "never without
  approval **this session**". The two outcomes are now distinct markers: `AD candidate (deferred)`
  is promotable, `AD declined (<date>)` never is, and only a fresh operation 5 ask can record it.

  **The headline feature silently no-opped on the installs that needed it most.** The AD repair
  ladder handled "page absent" and "page present but unlinked" — but not "page present, linked,
  and written before v0.18". On that page there is no `## Decisions` section and no per-entry
  `**Status:**`, so the count found nothing, the `Status is accepted` filter matched nothing, and
  the next session was told the decision record was empty while dozens of real ADs sat on disk.
  The consumer's page had 45 of them. There is now a third branch: a one-time migration that wraps
  the existing entries in the `## Conventions` + Entry-shape + `## Decisions` scaffold, keeping
  every entry BYTE-IDENTICAL, and drops the page-level `decision_id`/`decision_status` this
  release exempted. The standing-decisions filter is now allow-by-default — it excludes
  `superseded`/`deprecated` rather than requiring `accepted` — so a legacy page reads correctly
  even before it is migrated.

  **Session summaries invited free-form capture into a tracked, vector-indexed store with no
  exclusion clause.** `ingest-code-to-qdrant.py` has had `SECRET_PATTERNS` all along, but that is
  a FILENAME skip-list and cannot help prose that quotes a DSN inline. The summary path had no
  guard at all — and v0.18.0 is the release that widened what goes down it, explicitly asking for
  "commands that do not work in this repo".

  Unambiguous shapes are now masked before anything is derived from the text: DSN passwords,
  JWTs, AWS key ids and PEM blocks, on all three ingest paths (session, wiki and code). "Before
  anything derived" matters — an earlier ordering redacted only the chunks, leaving a secret
  quoted inside a `## Decisions Made` bullet in the Qdrant payload verbatim.

  Each of those four is bounded by its own grammar rather than by guessing. The DSN match ends
  where a URI authority ends, at the last `@` before `/`, `?`, `#` or whitespace, so a password
  containing `@` or `=` is masked in full while the match cannot run past the authority into the
  sentence. A PEM block must be PEM LINES — a known header, a base64 line, or a blank one, each
  possibly indented or blockquoted, which is how a key actually lands in a markdown summary.
  Loosening that body to free text (to catch encrypted keys) made prose between two separately
  MENTIONED markers match, silently deleting it; both properties are now pinned by tests.

  The `key: value` shape is deliberately NOT masked. Several rounds of tightening a matcher for it
  all kept catching ordinary sentences — "Token: rotated manually every Monday",
  "private_key: ~/.ssh/id_ed25519", "client_secret: rotated-2024-01-15" — and a false positive is
  worse than a miss here: redaction is destructive, and the chunk is the only thing the next
  session can query. That class is REPORTED instead, and reported by NAME and line number only,
  never by value: the git hooks tee this output into `.sumela/.memory-sync.log`, so echoing the
  matched line would copy the suspected secret into a second plaintext file — the guard becoming a
  leak of its own. It recognises the markdown spellings a summary actually uses
  (`- **Token:** …`, `` - `API_KEY`: … ``, `- API key: …`) as well as `NAME=value`.

  Both runs say plainly that the markdown on disk still holds the raw values and is git-tracked.
  Both instruction blocks gained the missing clause: reference a secret by name and location, never
  by value.

  **`<minimum_viable_handoff>` contradicted the labels it was supposed to qualify.** Four steps
  were still marked bare `(MANDATORY)` and two places still said `ALWAYS`, with no cross-reference
  to the ladder — an agent under context pressure could read either and both were authoritative.
  They now read `MANDATORY — degradable ONLY per <minimum_viable_handoff>`, and a degradation must
  be declared. Ladder item 5 also claimed a later lint recovers dropped index rows; it does not —
  operation 3's parity check compares the two indexes against each other, so dropping BOTH leaves
  them agreeing and nothing is flagged, and it never auto-runs or auto-fixes.

  **`## Key decisions` extracted nothing and still reported SUCCESS.** `DECISION_HEADERS` needs a
  full-line match, so any trailing word kills it. Across one 141-summary corpus, 42 summaries with
  a genuine decision section were invisible — 26 of them through English variants the v0.18.0
  English-heading pin does not address. Loosening the regex would undercut that pin and its parity
  test, so instead the silence is now audible: ingest WARNS when a `##` heading contains "decision"
  but did not match, at the moment the author can still fix it.

  **Three updater defects, all pre-existing, all silent.** `update.sh` never refreshed
  `.sumela/.update-check`, so a just-upgraded install kept being told it was behind. Files at the
  `.sumela/` ROOT are in neither `CORE_FILES` nor `CORE_DIRS` (that entry is `.sumela/rules/templates`,
  one level down), so `RULE_REGISTRY.md.template` froze in every upgrading install from v0.8.0 —
  meaning the anti-fork guidance added in v0.9.0, the rule the whole CORE/OVERLAY split exists to
  teach, reached no upgrade at all. And the updater deferred its own replacement with only a
  warning, so round N's updater ran the whole upgrade and skipped anything that became CORE in
  between; it now installs the new updater and says, unmissably, to re-run. `.last-update.json`
  also omitted the derived `_SCHEMA.md` it had just written, which made the self-modification guard
  classify that file as authored after an upgrade.

  `tests/test_session_ingest_guards.py` covers redaction, the near-miss headings and the
  root-level CORE entry; both new guards were mutation-tested.

- **A session's decisions died with the session; the handoff prompt carried none of them
  (v0.18.0).** `context-handoff` wrote decisions into the session summary, then handed the next
  agent a prompt whose only decision section was *Pending Decisions / Blockers* — open questions,
  the opposite of decisions already made. The summary's path appeared under `Second Brain Status`
  as a status line with no instruction attached, and session bootstrap reads `_INDEX.md` and
  `active-project-context.md` but never the summary. So the rationale was written, filed, and
  never read. Nothing accumulated either: each session's decisions sat in its own summary, and the
  one retrieval path that could have found them (Tier-1 `chat_history`) is explicitly best-effort,
  so a decision from session 3 silently stopped constraining session 7.

  **Decisions now get a durable home at handoff, instead of a longer prompt.** A new
  `<decision_triage>` step runs before the summary is written and routes every decision by the
  existing boundary test — *"would a developer without an agent still follow this?"*: project-level
  ones to `architecture-decisions.md` as an AD, agent-workflow ones to `_improvement-queue/` as a
  `decision`/`preference` signal, tactical ones to the summary alone. The handoff prompt then
  carries *Decisions — This Session* (each line ending in the home it was filed to) and
  *Decisions — Standing*, which POINTS at `architecture-decisions.md` rather than copying it.

  **The pointer is deliberate.** An earlier design generated the cumulative list by collecting
  `## Decisions Made` blocks out of past summaries. Two independent reviews killed it: session
  summaries are an append-only record with no retraction, so a derived "currently in force" list
  renders decisions reversed three sessions ago as current, forever, and grows monotonically. Only
  `architecture-decisions.md` carries `decision_status`/`superseded_by`. A list that lies about
  what still holds is worse than no list.

  **`context-handoff` does not write ADs itself**, though it is the moment the decisions surface.
  `using-second-brain` operation 5 already owns that path and asks *"save this decision to the
  wiki?"* before writing; AD numbers are allocated by reading the page's current maximum, an
  unlocked read-modify-write, and handoff is the most worktree-exposed moment in the system. A
  third writer would have bypassed a consent gate and raced for numbers. Triage routes to that
  workflow; if the user declines or context is too tight, the decision is carried as an
  *AD candidate* line for `finishing-a-development-branch` to promote at a calmer moment.

  **`architecture-decisions.md` now ships with a FRESH install.** It is the surface the whole design
  points at and `setup.sh`/`setup.ps1` never created it, so on a new project the pointer would have
  dangled. An install that UPGRADES into this version deliberately does not get the page from
  `update.sh`: the installer's keep-guard preserves that project's existing `_INDEX.md` /
  `_SEARCH_INDEX.md`, so dropping the page in would land it orphaned — present but unreachable from
  Tier-3 search. On those installs the first AD write creates the page and its index rows together
  (`using-second-brain` operation 5, which also repairs a page that is present but unlinked), and
  until then the handoff prompt renders "page not created yet" rather than a dangling link.

  **Two adjacent bugs fixed.** The Session Summary template's `spec_artifact`/`plan_artifact`
  pointed at `../artifacts/…`, but summaries live in `wiki/session-summaries/`, one level deeper —
  every documented value was a broken link, now `../../artifacts/…`. And `## Decisions Made` is
  parsed verbatim by `session-ingest.py` while nothing pinned the heading to English: a
  Turkish-configured project writing `## Alınan Kararlar` extracted zero decisions, silently, with
  a SUCCESS report. Both `_SCHEMA.md` and `using-second-brain` now state the rule, and
  `tests/test_decision_heading_parity.py` fails if the template heading, the parser and the skill
  ever drift apart.

  **Experience crosses the session boundary directly, not through `/evolve`.** The session summary
  gains a `## Notes for the Next Session` section and the prompt an *Agent Notes* block: dead ends
  and why they failed, tooling quirks, files that look relevant but are not, how this user prefers
  to work. An earlier draft routed the preference-shaped ones into the `_improvement-queue/` signal
  path — that was wrong. A captured signal stays `pending` until someone runs `/evolve`, and
  bootstrap shows the next session only the pending COUNT, never the content, so filing experience
  as a signal takes it OUT of circulation exactly when it is needed. Notes are carried forward and
  PRUNED at each handoff, which is what lets experience accumulate without the prompt growing
  without bound. `finishing-a-development-branch` then rolls the notes that GENERALIZE beyond the
  task up into `/evolve` signals in one batch at task end — the calm moment, and the right place to
  decide what becomes permanent.

  **Pre-existing bug found while testing this: re-running `setup.sh` destroyed every wiki page.**
  The installer is a documented re-runnable flow, but its wiki-template loop rendered
  unconditionally — a second run overwrote `active-project-context.md`, `_LOG.md`, `_INDEX.md` and
  `_SEARCH_INDEX.md` with empty templates, silently discarding sprint state and the log ledger. The
  loop now keeps any page that already exists; `_SCHEMA.md` stays the single exception, since it is
  framework-derived and `update.sh` refreshes it too. This mattered here because the feature above
  ships a page whose own rule is "never delete a decision" onto that loop.

  **Also:** a `<minimum_viable_handoff>` ladder, because this skill fires when context is already
  gone and its own mandatory steps could fail half-done — it ranks what to drop by
  irreplaceability, and the newest, most expensive items rank lowest. The `/evolve` pending-count
  command was duplicated verbatim three times in the skill body; it is now defined once. And
  `tests/test_setup_without_python.sh` seeded its throwaway installs from `scripts`/`.sumela` only,
  so a change to `docs/second-brain/template/` plus its `validate-structure.sh` requirement landed
  half-applied and failed every seeded install — the seed list now includes the template tree.

- **`secure-coding-standard` told the agent to build three bypassable controls, and its
  checklist could not be answered honestly (v0.17.0).** The skill's shape was sound — plan-time
  loading, a confirmation gate, the security-TDD exception — but the rules inside it were in
  places wrong, and a security rule that is wrong is worse than absent, because the agent follows
  it confidently.

  **Three rules produced vulnerable code.** "MUST validate strict MIME-types (not just
  extensions)" sends the agent to `file.mimetype` — a multipart header the uploader controls;
  type is now decided by MAGIC BYTES against an allowlist, with a server-generated filename,
  `Content-Disposition: attachment` and `nosniff`. "ALWAYS sanitize file paths" is the textbook
  BROKEN traversal fix (`....//` survives `..`-stripping, and `os.path.join` silently discards
  the base on an absolute input); the rule is now resolve-then-verify-CONTAINMENT, with a
  runnable example whose stated behaviour was checked against a real filesystem. JWT validation
  listed issuer/audience/expiry/signing key but not the ALGORITHM, leaving `alg: none` and
  HS/RS confusion — two full authentication bypasses — unaddressed.

  **The checklist was unfalsifiable.** There was no way to mark an item N/A, so an agent on a
  CLI project either lied about CSP or stalled — and an agent that learns to tick falsely ticks
  the items that DO apply. There was no evidence requirement either, so the gate self-certified
  with bare checkboxes while `reviewer-correctness-security.md` demanded `File:line` for every
  finding on the same change. Every line is now answered as `[x] item — file:line | command
  result` or `[~] item — N/A: reason`, and a new Step 2 scopes the categories to what the change
  actually REACHES (an all-of-system checklist in front of a five-line diff gets skipped whole).

  **The plan-time analysis never reached the reviewer.** Step 1 said "identify all external
  inputs" without saying where to put the answer, and nothing produced the `{SECURITY_MANDATE}`
  the review panel's Lane 1 expects. The threat-boundary analysis is now a written
  `Security Constraints` block in the spec or plan, and that block IS the mandate.

  **Coverage gaps closed.** Mass assignment, insecure deserialization, XXE, zip-slip and
  decompression bombs, ReDoS, open redirect, session fixation, multi-tenant scoping, CSPRNG vs
  `Math.random()` for tokens, constant-time comparison, AEAD and nonce reuse, password-reset
  token hygiene, anti-enumeration timing, and the whole of **A09 Security Logging & Monitoring**
  — none of which the skill mentioned. They live in a new `owasp-playbook.md`, written as
  BROKEN / CONTROL / TEST per class so the plausible-but-wrong fix is named next to the one that
  holds. The confirmation gate gained its most important trigger: **weakening or removing an
  existing control** (`verify=False`, a deleted auth check, `--no-verify`, a widened permission)
  — the most frequent way an agent introduces a vulnerability, and the one that never looks like
  a security change.

  **New: `agent-specific-threats.md`.** This skill is executed by an LLM, and did not address its
  own author's failure modes: hallucinated package names (slopsquatting), plausible-looking
  crypto, controls disabled to get a test green, secrets written into agent-authored specs and
  plans, insecure defaults in generated IaC/CI, treating tool output as instructions, and — for
  features the agent builds — prompt injection, authorization enforced outside the model, and
  model output handled as untrusted input.

  **Two adversarial reviews ran against the rewrite before it landed, and both found real defects.**
  The security-content lens found that the new open-redirect CONTROL ("empty host plus a path
  starting with a single `/`") was defeated by `/\evil.com` — the exact string the line above it
  named as the bypass — and by `https:/evil.com`; the corrected control requires an empty scheme,
  empty netloc and `^/[^/\]` after decoding, and the test now pins both payloads. It also showed
  the `safe_open` snippet is TOCTOU-racy in the upload directory its own comment names (race won
  on the 5th attempt), so the entry now states that limit instead of promising that no input ever
  opens a file outside the base. Further content fixes: NoSQL operator injection and CSRF had no
  playbook sections although SKILL.md pointed there for both; bcrypt was called memory-hard (it is
  CPU-hard); the CORS `endsWith` example named a domain that does not actually pass it; anchoring
  was listed first as the ReDoS control (it does not fix nested quantifiers); the SSRF reject-list
  was missing `0.0.0.0/8`, `100.64.0.0/10` and `fc00::/7` and did not require checking every
  resolved address; random GCM nonces carried no message-count bound; and the `Math.random()`
  claim was replaced with the V8 state-recovery fact that is actually demonstrable.

  The framework lens found the change's two headline claims did not hold. `requesting-code-review`
  Step 4 is the **single filling authority** for `{SECURITY_MANDATE}` and explicitly forbids
  callers from filling fields, so the instruction to pass the block as that parameter collided
  with a MUST in the receiving skill — and the stated consequence ("the reviewer checks your code
  against nothing") was false, since that skill always supplies a generic mandate. The block now
  travels through `{DESCRIPTION}` and the plan. The spec-side section name was invented:
  `brainstorming` requires **Security Considerations**, `writing-plans` requires **Security
  Constraints**, and the skill now names each correctly plus a destination for the planless phases.
  The severity model was attributed to `requesting-code-review`, which itself defers — canonical
  is `receiving-code-review` → `<severity_model>`. The Step 7 checklist had collapsed 16 items into
  five prose paragraphs answerable with five ticks, and "exactly two forms" left an agent facing a
  real gap with `N/A` as its only legal output; there are now three forms, the third being
  `[ ] NOT DONE`, and every clause is answered on its own row. Step 2's triage produced no artifact
  and needed no reason for an N/A, and its table missed three Step 3 categories outright — it now
  prints a verdict per row, costs a reason, and covers XSS/output rendering, state & concurrency
  and mass assignment. The confirmation gate's new "weakening a control" trigger sat in a preamble
  nothing re-invoked, so Step 7 opens with a mechanical `git diff | grep` sweep for it.

  **The guard test was pinning vocabulary, not behaviour** — demonstrated, not argued: a nine-line
  stub reading "Security is the reviewer's job" plus a keyword dump passed all 36 checks. The three
  corrected controls are now asserted against `SKILL.md` itself rather than the whole corpus (the
  playbook is only read for REACHABLE categories), the `"reachab"` check that was already true in
  the pre-change file is replaced by a structural one, the spec/plan needle that the file's own
  title satisfied is replaced, substance floors reject a keyword stub, and the cross-skill
  contracts above are pinned so they cannot regress silently.

  Project-specific leakage (FCM tokens, SMTP credentials, "report descriptions") is out of the
  language-agnostic core: an enumerated app-specific list reads as exhaustive, and the agent
  infers that a field not on it is loggable. The duplicated severity model now defers to
  `requesting-code-review`, which owns it. Pinned by `tests/test_secure_coding_standard.py`
  (wired into `tests/smoke.sh`, so CI runs it) — written and failing before the edit, per the
  skill-authoring Iron Law.

- **The code-review panel now reads the repo, sizes itself mechanically, and leaves evidence
  behind (v0.16.0).** Nine changes to `requesting-code-review` / `receiving-code-review`, each
  closing a way the gate could pass while doing nothing.

  **Reviewers could not read the code.** All three lanes carried `Review ONLY the provided
  {CODE_DIFF}`. A diff hunk is ±3 lines of context, so a lane could not check whether a guard
  already existed above the change, whether callers were updated, or whether a test existed
  when the test file was not in the diff — and the rule flatly **contradicted** the Integration
  lane's own instruction to run graphify `--impact` on every changed symbol, an instruction that
  requires leaving the diff. Lanes now read files, callers, tests and config freely: the diff
  defines what a lane is ACCOUNTABLE for, not what it may READ. The reading is bounded (name the
  candidate finding first; ~10 reads / 5 greps; never an unbounded `git log -p`) because one
  unbounded call evicts the diff the lane is answerable for while it keeps emitting a
  well-formed report.

  **Nothing controlled false positives.** Every lane had to emit `Strengths` and a verdict, so a
  lane with nothing to report invented something — the skill itself recorded one such case. Lanes
  now get an explicit licence to report nothing, a **failure chain** gate (every link carries a
  `File:line`; a link that reads "presumably" or "if a caller does X" means the finding is
  DROPPED, not demoted — demotion only relabels noise), and a **mandatory coverage line** naming
  what was examined and what could not be settled, so a skimmed lane and a thorough one no longer
  produce the same empty report. Verification of each Critical/Important happens **inline in the
  orchestrator** (one evidence line per finding: CONFIRMED / REJECTED / UNPROVEN) rather than in a
  second wave of subagents — the orchestrator already had repo access and the job, and a verifier
  panel would have doubled the median agent count of a gate that runs before every commit.
  **`(unproven)` keeps its original severity:** the findings verification cannot settle are
  overwhelmingly absence-of-control findings (no revocation path, no boundary test, no rollback)
  — you cannot prove a negative by opening files — so demoting them would have quietly emptied
  the security floor of exactly the class it exists to catch.

  **A large diff produced no review at all.** Over ~300 lines the skill said "STOP and ask the
  author to split the change" — but the review is mandatory before every commit and the "author"
  is the agent itself, so the rule could only deadlock or be rationalized around. 300 is now a
  **slicing unit**: the diff is cut into coherent groups and the panel runs per slice, with an
  explicit cross-slice pass afterwards. The line count is no longer self-scored — `git diff
  --numstat` is printed, and every excluded path must be printed with its line count and reason.

  **Effort now scales with risk, and the tier cannot be self-discounted.** A one-line typo fix
  used to get the same three-lane panel as a migration. Tier is decided by a printed grep over
  the changed files (`auth|token|secret|migration|schema|payment|pii|\.tf$|Dockerfile|...`): any
  hit is Deep (4 lanes), no hit and ≤40 lines is Focused (the mandatory Correctness & Security
  floor alone), everything else is Standard. **Judgment may escalate a tier; it may never
  de-escalate one** — otherwise the discount is granted by the agent that benefits from it.

  **The gate had no evidence to check.** `finishing-a-development-branch` spent two paragraphs
  begging the agent to confirm the review had run, because nothing was written down. The panel now
  writes a report to the **main checkout's** `.sumela/reviews/` — main checkout, because the
  directory is untracked and `git worktree remove` would otherwise delete the evidence
  `shipping-and-launch` is meant to gate on. It is keyed by `reviewed_state:` (a hash of what was
  actually reviewed via `git hash-object`), since a literal `worktree` marker matches itself
  forever and a gate built on it always passes. Both downstream gates now check the file, the
  hash, and the verdict — and honour a recorded `user_decision: proceed` instead of re-blocking a
  choice the user already made.

  **Two dimensions lost in the lane split are back:** reuse & simplification (Design & Contracts)
  and scope discipline / YAGNI (Lane 1, which already owns spec conformance). Both were in the
  legacy single-reviewer prompt and neither survived the split — a reviewer that only hunts bugs
  never asks whether the code needed to exist.

  **Three payload fields close three blind spots:** `{VERIFICATION_EVIDENCE}` (so lanes can catch
  "suite is green but no test reaches the new branch" — with "verification was not run" handled
  once as a Step 1 precondition instead of becoming an identical finding from every lane in every
  slice), `{PRIOR_ROUNDS}` (so a rejected false positive does not return every round and get
  re-argued; rounds converge, and a rejection whose file was touched again expires), and
  `{CHANGED_FILES}`. Step 4 is now the single authority that fills every field, so an unfilled
  `{PLACEHOLDER}` cannot reach a lane as literal text. The author's narrative is explicitly framed
  as a **claim to verify** — a security mitigation claimed in `{DESCRIPTION}` but absent from the
  code is itself a finding.

- **Eleven ideas borrowed from Qwen Code's `/review`, three of them deliberately not as written (v0.16.0).**
  Source: `QwenLM/qwen-code`, `docs/users/features/code-review.md`. Their implementation is a
  product (CLI, PR fetch, GitHub API, headless runner, cache); the review *logic* is prompt on
  both sides, so nothing here needed a new runtime dependency. Two adversarial design reviews
  ran before any of it was written and rejected the first draft outright — five of the eleven
  collided with rules added earlier in this release.

  **Taken as-is.** Findings for one root cause at several sites now aggregate into ONE finding
  listing every location, instead of a 3-slice panel reporting the same systemic issue twelve
  times. `Ready: Yes` now additionally requires verification evidence covering the diff — the
  panel could previously certify a tree nothing had executed. Findings carry a stable id
  (`r<round>.F<n>`), assigned by the orchestrator after dedupe and aggregation: never by a lane
  (ids would collide across slices) and never severity-coded (dedupe raises severity, which
  would mutate the id and orphan the previous round's ledger). Qwen's JSON-findings pipeline
  was deliberately reduced to just those ids — four consumers read their JSON, one reads ours,
  and a schema validator would have put Python on the review path.

  **Taken, but re-shaped, because copying them would have broken what they touch.**
  *Rejection asymmetry:* a REJECTED verdict now needs quoted contradicting code, a diff comment
  documenting the behaviour as deliberate, **or a scoped negative search** (pattern, where run,
  `0 hits`). That third ground is not in the source and is what makes the rule survivable: you
  cannot quote a line proving a line is missing, so without it no absence-of-control finding
  could ever be rejected, every hallucinated Critical would become permanent, and — since
  `(unproven)` keeps its severity and blocks — the re-review loop would never terminate. An
  UNPROVEN finding that survives two rounds with no new evidence and no edit to its cited file
  now goes `UNPROVEN — stale` and stops blocking, for the same reason.
  *Plausibility default:* shipped as a DEFINITION of what satisfies the failure chain's
  INPUT/STATE link (cite where the exclusion would have to live and show it absent), not as the
  carve-out it is upstream. As a carve-out it directly contradicted the failure-chain gate,
  which names "in some configuration" and "if a caller does X" as drop triggers — the exact
  phrasing a race and a retry storm require. Two unqualified contradictory rules in one block
  means the model picks whichever supports the conclusion it already wants.
  *Confidence field:* adopted; Qwen's semantics rejected. There, low confidence does not block
  and never reaches the PR. Here it must block, because the findings verification cannot settle
  are overwhelmingly absence-of-control ones. Their review is a PR comment, where noise is
  expensive; ours is a commit gate, where a miss is.
  *Test-delta attribution:* the source's rule needs a pre-change baseline run. The reduced form
  defaults to **UNATTRIBUTED** and demands the trace (test entry point, the path followed, no
  changed file on it) before a failure may be called pre-existing — an unevidenced
  "probably pre-existing" excuses a real regression in writing, which is worse than silence.
  *Gap sweep:* their iterative reverse audit became four DIFF-DERIVED searches, each printed
  with its hit count (`gap-sweep.md`) — an added field nothing reads, a removed guard nobody
  re-established, an added early exit and what no longer runs after it, a cross-slice contract.
  Open-ended "what did we miss" introspection by the orchestrator that just merged the findings
  would have been theater.

  **Cut.** Qwen's "what is NOT flagged" list lost ~60% of its content: its pre-existing clause
  was a *weaker* restatement of the ATTRIBUTION rule already in every lane (which covers
  pre-existing issues in *changed* files too), and its style clause contradicted Lane 2's
  existing "at most Minor" rule. Only the genuinely new parts survive — risk-free refactors,
  and the linter/type-checker exception scoped to what this diff introduces. Lane 2's rule was
  amended to defer rather than compete.

  **The self-modification guard is the one finding this borrowing produced rather than
  transferred.** SumelaOS had zero protection: lanes judge against "the project's loaded rules",
  those come from the working tree, and nothing flagged a diff editing `.sumela/rules/`, the
  review skills, the hooks, `AGENTS.md`, or `CODEOWNERS`. A change could loosen its own review
  unnoticed. Qwen's fix — read rules from the base branch — does not port: the primary mode here
  reviews staged/unstaged work where no base ref exists (`{HEAD_SHA}` is a worktree *label*, and
  every lane is explicitly told `git show <label>:` is not a command), the semantics are
  backwards in a repo where new rules ARE the deliverable, and the threat model is
  self-deception rather than an untrusted third-party PR. What shipped (`self-modification-guard.md`)
  announces the modification, forces Deep, and makes Lane 2 own "a change that weakens a rule is
  a finding at the severity of what it weakens" — while stating plainly what it does NOT fix:
  the modified rule was already loaded from the working tree at session start, and nothing at
  Step 1 can un-read it. It also carries a **framework-upgrade carve-out**, without which every
  consumer would pay a forced 4-lane Deep review and a false security banner on their first
  review after every `scripts/update.sh` run — `update.sh` rewrites every trigger path.

  Two more holes closed on the way: the report is refused unless `.sumela/reviews/` is actually
  gitignored (the reconcile is consent-gated, so a user who declined it would have had
  secret-quoting reports written into a tracked directory), and the shared execution-rules block
  — three byte-identical copies — now has a drift guard, since a lane running a stale copy of
  the false-positive controls still emits a perfectly well-formed report.

  The report format itself moved to `review-report.md` as a single canonical spec. Four files
  touch it — the writer, its own next-round reader, the outcome ledger, and the two gates — and
  each was restating parts of it, the same drift this release de-duplicated the severity model
  to stop.

- **Skill structure is now checked the way Anthropic's guidance measures it (v0.16.0).**
  `writing-skills` had always said `<200 words for frequently-loaded skills, <500 for others`,
  and nothing enforced it. The first attempt here enforced it — and that was a mistake, because
  the rule was wrong: the official guidance is *"keep SKILL.md body under 500 **lines**"*, a
  different unit and roughly 6-8x looser. Under the word count 19 of 22 skills looked over
  budget; under the real measure exactly one is (`init-sumela`, 607 lines).

  The wrong number was not harmless. Chasing it produced two rule violations in a single
  session, both caught by review rather than by the guard: common-path content was moved into
  sibling files so the counter would drop — a "reduction" that relocated tokens instead of
  removing them — and when that was caught, the re-baseline was justified with "only the
  measurement changed" for a file that had in fact grown by ~1000 words. A metric that measures
  the wrong thing does not merely fail to help; it pushes toward gaming it.

  `tests/test_skill_word_budget.py` is replaced by `tests/test_skill_structure.py`, which
  checks what the guidance actually says: SKILL.md under 500 lines (over-limit files pinned,
  ratchet-only); **every sibling `.md` named DIRECTLY in SKILL.md**; and a `## Contents` list on
  any reference file over 100 lines. The second check is the one that bites, and it found real
  defects the word count never could (the third found one more): Claude may preview a file with `head -100` rather than
  read it whole when it arrives there through *another* referenced file, so a rule two levels
  down can silently not apply. Three were fixed — `code-reviewer.md` was reachable from
  `requesting-code-review` only via `ide-fallback.md`; `writing-plans` named the
  `plan-document-reviewer` subagent but never its prompt file; and `brainstorming/idea-explore.md`
  (131 lines) gained a table of contents.

  Recorded for the next person who reaches for a size limit: prompt caching does not change any
  of this. Cached content still occupies the context window and still counts as input tokens
  (`total = cache_read + cache_creation + input`); caching makes a re-read cheaper, not smaller.
  And skills are not all loaded up front — only each skill's name and description are, with
  SKILL.md read when the task matches, which is exactly what `SKILL_REGISTRY.md` already does.

- **One severity model, and the merge that nearly deleted it (v0.16.0).** The model lived in two
  tables. The `requesting-code-review` one had `Section | Meaning | Required Action` headers with
  the **second and third columns swapped** on three of its four rows — the qualifiers
  ("exploitable token-lifecycle gap", "meaningful test gap") sat under `Required Action` and the
  actions sat under `Meaning`. Merging by column name, as first planned, would have moved the
  action words, dropped every qualifier, and passed a column-wise diff check: the only place the
  panel's severity thresholds were written down would have vanished silently. Adversarial review
  caught it. The tables are now merged cell by cell into a single canonical `<severity_model>` in
  `receiving-code-review` (which is invoked standalone for human and GitHub feedback, so it cannot
  be a pointer), keeping the stronger wording from each side; `requesting-code-review` points at
  it and states only the gate discriminator. Per-lane `SEVERITY STRICTNESS` lines and the
  `output_format` headings are deliberately grandfathered — they calibrate a lane, they do not
  redefine the model. The legacy single-reviewer template's third, already-drifted prose copy was
  aligned rather than left to rot behind a user-visible menu option.

### Fixed

- **Two review rounds on this release's own changes, and what they caught (v0.16.0).**
  The overhaul above was reviewed by its own panel — Deep tier, self-modification guard active
  (28 trigger paths) — across two rounds. Round 1: 4 Criticals, 9 Importants. Round 2 on the
  fixes: 1 Critical, 9 Importants. Both artifacts are in `.sumela/reviews/`. Recorded here
  because most of what it found was the author's own reasoning failing in ways a green test
  suite could not see:

  **A test that certified a comparison it never made.** `test_setup_without_python.sh`'s
  headline assertion — python and python-free renders are byte-identical — passed with the
  python renderer destroyed: the fallback caught BOTH sides and `cmp` compared bash to bash.
  Fixed with a renderer trace; mutation now goes red. The fix then shipped a second bug the
  same test was blind to: `[ -n "$VAR" ] && echo ...` as `render_template`'s last command
  returns 1 with the variable unset, and `set -euo pipefail` aborted every real install. Every
  test case set the variable. The smoke suite caught it (30→16), and a case with the variable
  unset now pins it.

  **A locale fix that fixed nothing.** The first fix put `LC_ALL=C` on a `printf`, which emits
  identical bytes in every locale, while the `case` glob that actually collates kept running
  under the ambient one. In any UTF-8 locale the "cannot transliterate" warning fired on every
  plain-ASCII domain name. Now `tr -d '\040-\176'` — the locale is on the tool that inspects
  the bytes. Verified across `C`, `en_US.UTF-8` and `tr_TR.UTF-8`. Fixing it would also have
  made the stdout-pollution guard vacuous (that guard only went red *because* of the spurious
  warning), so the test's domain list gained a name that legitimately cannot be transliterated.

  **The word-budget ratchet, gamed twice by its own author.** First by extracting two
  common-path files and letting the metric certify a reduction that never happened — the
  precise "fake split" the rule text forbids. When review caught that, the re-baseline was
  justified with "only the measurement changed"; `git show HEAD:…/SKILL.md | wc -w` says 2035
  under the identical metric, and the extracted content did not exist at HEAD. The skill grew
  by ~1000 words. The comment now says so, and records the >2x overage against its type budget
  as debt. The exemption mechanism was then found dodgeable by `git mv` (renaming a file to
  `*-prompt.md` dropped it from the count) and is now a declarative list, one line and one
  stated reason per file.

  **Two gates that fixed one hole by opening another.** Hardening "a `proceed` decision must
  not waive a stale hash" made `shipping-and-launch` unpassable: `git diff --staged` is empty
  after the commit, so a pre-commit report could never match at ship time. `reviewed_state` is
  now a TREE hash (`git write-tree` from the index equals `HEAD^{tree}` of the commit it
  becomes). And the self-modification guard's provenance test was unexecutable — `$SRC` is a
  local inside `update.sh` whose clone is trapped away on exit — so `update.sh` now writes
  `.sumela/.last-update.json` (version, timestamp, vendored file list) and the guard reads it.

  One verification verdict in round 1 was itself wrong and is recorded as withdrawn: a lane's
  collation claim was REJECTED on evidence contaminated by the reviewer's own shell locale.
  An environment-dependent probe is not the "quoted contradicting code" the rejection rule
  demands.

- **The bash installer no longer requires Python 3, and README no longer claims otherwise (v0.16.0).**
  `scripts/setup.sh`'s `render_template()` called `python3 -c` **unguarded**, on the CORE path —
  `AGENTS.md`, `.sumela/RULE_REGISTRY.md`, every rule and domain template. Every other Python
  caller in the repo is guarded and degrades silently (`update.sh`, `validate-structure.sh`, all
  the git hooks); the install was the single unguarded one, and it is the one a first-time user
  hits. README promised *"the core framework needs only git and any AI coding agent — nothing
  else"*. It did not.

  The dependency was a choice, not a necessity: `scripts/setup.ps1` already renders the same
  templates with literal replacement and no Python at all. The fix is a bash fallback using
  parameter substitution — **not `sed`**, which was the entire basis of the "too fragile for
  shell" argument that had kept this open. `${c//pat/rep}` has no regex, no delimiter and no
  backreference semantics, so `&`, `|`, `/`, backslashes, newlines, `→` and glob metacharacters
  in a value are all literal; verified on bash 3.2.57, the macOS system bash and the oldest
  target, where `${!TMPL_@}` also works (3.2 has no associative arrays).

  Writing the test first surfaced a second, larger bug: **presence is not capability**. The
  test's stub interpreter sits on PATH and is executable and still exits 127 — which is exactly
  what a pyenv or asdf shim for an uninstalled version does, a far more common real-world state
  than "no Python at all". Every `command -v python3` guard in the installer would have sailed
  straight past it. All optional Python paths now probe through one cached `have_python()`
  helper that actually runs the interpreter.

  `slugify()` gets the same treatment, with an honest caveat rather than a silent divergence:
  the fallback transliterates the Latin-1 and Turkish letters these taxonomies use (verified
  identical to the NFKD path on Turkish and accented domain names), and *announces* when a
  non-ASCII name may slug differently, because `init-sumela` pins slug parity between the two
  install routes as a hard contract. The plugin-registry append degrades the same way.

  Pinned by `tests/test_setup_without_python.sh` (wired into `tests/smoke.sh`), which asserts
  the install SUCCEEDS without Python **and that both renders are byte-identical** — the second
  assertion is the one that keeps a fallback honest over time. It also pins that `--hooks-only`
  stays Python-free: it already was, by exiting before any render, so a preflight placed at the
  top of the file would have newly broken the `/onboardSumela` teammate path.

  README is corrected in the three places that were wrong, not just the headline one, and
  `init-sumela` now says to check registry parity by hand rather than report an import as
  "proven" when the reconcile could not run.

- **The stale `superpowers:` skill prefix no longer reaches live rules (v0.16.0).** 21 occurrences
  across 7 rule files addressed skills as `superpowers:<name>` — an upstream plugin namespace
  SumelaOS does not use; `SKILL_REGISTRY.md` addresses every skill by bare name. One of the seven,
  `.sumela/rules/operational_excellence_maintenance.md.template`, is copied by `init-sumela` into a
  **live, loaded rule**, and it sat in neither `CORE_FILES` nor any `CORE_DIRS` entry (`CORE_DIRS`
  covers `.sumela/rules/templates/`, one level below it) — so the fix would have shipped to fresh
  installs and never reached an upgraded one. It is now named explicitly in both `scripts/update.sh`
  and `scripts/update.ps1`. The `.superpowers/` runtime gitignore patterns and the
  `using-superpowers` skill are untouched (neither matches the `superpowers:` prefix).

- **A failed Qdrant delete no longer leaves a stale tail and reports SUCCESS (v0.15.0).** Both bulk
  ingests refresh a file idempotently as DELETE-by-filter then UPSERT. The delete sat in a
  `try/except` that printed `[warn] delete failed for <path>` and then **fell through to the
  upsert**, and a delete failure was recorded in neither failure set — so the run printed
  `Ingested: <path>`, reported `Status: SUCCESS` and exited **0**.

  Point ids are deterministic per `(file, chunk_index)`, so upserting over a failed delete
  rewrites indices `0..n-1` but **cannot remove a longer tail from an earlier version**. A file
  that shrank from 40 chunks to 12 kept chunks 12-39 of the *old* content, carrying a stale
  `total_chunks` in their payload, and retrieval then answered confidently from code that no
  longer exists. That is precisely the silent hole the all-or-nothing rule closes on the embed
  side — the upsert branch immediately below it was already written with that care ("its points
  were deleted and NOT replaced; re-run to restore"); the delete branch was not.

  A delete is now **retried once** — a lost *response* is not a failed *request*, and skipping the
  upsert after a delete that did land server-side would remove the entry from the index entirely,
  which is worse than the stale tail this guard exists to prevent. A delete that fails twice
  **skips the upsert**, is collected in a `delete_failed` set, and is named in the report
  (`Files/Pages left STALE (delete failed, upsert skipped): N`). The warning says only what is
  known — the entry "may be STALE or partially removed" — rather than claiming it was left
  unchanged, which the client cannot verify. Fixed in **both** twins.

  **The exit code required a second fix that review caught.** Skipping the upsert leaves
  `total_chunks == 0`, and the exit was derived from `qdrant_ok = total_chunks > 0` — so a delete
  that failed for *every* file (a dropped payload index, a permission change, a read-only
  collection — a whole-corpus failure mode, unlike an embed failure) exited **`1`**, which the
  plugin README maps to "could not run — fix the dependency named in the report". No dependency is
  broken there and the report names none: `ensure_collection` had already answered. The exit now
  derives from whether the run *reached the write stage* (`qdrant_ok or upsert_failed or
  delete_failed`), so that case is `2`. Fixing it in Python means the hand-maintained
  `setup-memory.{sh,ps1}` twins need no edit — they already branch correctly on `2`. Relatedly,
  `Qdrant upsert:` now reads `SKIPPED` rather than `FAILED` when no upsert was ever attempted, and
  the pull-time hooks (`_lib.sh`) no longer collapse `2` into `WARN: … ingest failed` — that is
  the path a delete failure actually reaches in the field, and it was burying an actionable,
  re-runnable state behind a backend-outage message.

- **An all-zero or non-finite embedding is no longer stored (v0.15.0).** `get_embedding` validated
  only the vector's WIDTH. llama-server emits a **correctly sized all-zero** vector on internal
  embedding failures (both when the model is loaded without embedding support and when
  `llama_get_embeddings_*` returns nothing), and Ollama's L2 normalization does not turn that into
  an error — `sum == 0` yields `norm = 1/1e-12` and `0 * 1e12` is still `0`, so no NaN or Inf ever
  surfaces. The result was a 200 carrying a well-formed 1024-dim vector of zeros that passed every
  check, was upserted as a normal point, and then sat in the corpus answering COSINE queries from
  nothing. Same family as the empty-array soft failure the width check already covered; this was
  the half it was blind to. `get_embedding` now rejects a vector that is all-zero or contains a
  non-finite component, so the caller records it as a failed chunk and the all-or-nothing rule
  leaves the file untouched. Centralized in the lib, so the ingest, session and query paths all
  inherit it.

  The rejection is **not retried**, via a dedicated `EmbeddingRejected(ValueError)`. Review measured
  the naive version: a runner loaded without embedding support returns zeros for *every* chunk, so
  a retry spends 2 requests and a full `SUMELA_EMBED_RETRY_DELAY` per chunk — at 20k chunks over 4
  workers, hours of pure sleeping in a detached process launched from a git hook, to reach the same
  rejection. That is verbatim the cost hole `ollama_preflight` exists to prevent, and the preflight
  cannot see this one (`GET /api/tags` answers fine). Measured after the fix: one HTTP call, no
  sleep. A 500 from a dead runner is still retried — that one really is transient.

  Covered by two suites, both wired into `tests/smoke.sh` and therefore CI:
  `tests/test_ingest_delete_guard.py` (22 assertions; **16 fail against the old code**, while its 6
  healthy-path controls pass in both directions, so the test measures the guard and not itself — it
  loads each ingest against a stub Qdrant and a stub Ollama, no live service) and the extended
  `tests/test_embedding_bounds.py` (**3 new assertions fail against the old lib**, plus a
  false-positive guard asserting a sparse-but-valid vector is still accepted).

  The delete-guard suite was **mutation-tested**, and the first cut failed it: with every file
  failing the delete, `qdrant_ok` is already False and the other failure sets are already empty, so
  both `delete_failed` terms were short-circuited and a mutant that dropped either one survived
  with all assertions green. A mixed scenario (one entry stale, the rest healthy) is the only shape
  that exercises them, and it is the only shape that produces the `2` the contract promises. Both
  mutants are now killed.

  Also removed: `upserted_ok` in the code twin, assigned and added to but never read since it was
  introduced, and absent from the wiki twin — leaving two parallel tracking sets where one was
  live and one inert.

### Added

- **`SUMELA_GRAPHIFY_VIZ` (v0.14.0)** — opt back in to graphify's interactive `graph.html` on the
  pull-time graph refresh when the graph is above graphify's ~5000-node viz limit. Unset by
  default (see the `Fixed` entry below for why forcing it was removed). Only an affirmative value
  turns it on: `0`, `false`, `no` and `off` all read as off, so a stale export cannot silently
  restore the cost. Documented in `.sumela/git-hooks/README.md` and the graphify plugin README.

- **Self-activating bootstrap on `@`-attach — reliable opt-in adoption without auto-loading
  (v0.12.0).** Field finding from a multi-IDE project where not every developer uses SumelaOS:
  attaching `.sumela/sumela-prompt.md` to a turn via `@`-reference did NOT run
  `<session_bootstrap>` — the agent treated the file as passive reference material and answered
  the literal task (e.g. "git pull") *unless* the user also said "follow the flow". Root cause:
  the bootstrap trigger was framed as session-state ("at the first user turn of every session"),
  which an attached document cannot reason about, so a concurrent literal task always won. A new
  `<activation>` block at the very top of `sumela-prompt.md` (before `<role>`) makes the file
  self-activating — its presence in context IS the activation signal, framed as a read-time
  imperative to execute now (not docs to read/remember) — and the `<session_bootstrap>` trigger
  now also fires "the moment this file enters your context (e.g. attached via `@`-reference)".
  Stays **opt-in**: no `CLAUDE.md`/`SessionStart` forcing, so developers who don't use the
  framework are untouched; activation happens only when one deliberately attaches the file.
  **Idempotent** — run once per session; if registries + eager skills are already in context it
  skips straight to the request, so a pinned/re-attached file does not re-run STEP 0–5 or
  re-emit STEP 2's one-per-session notifications. **Defers to `<authority_hierarchy>`** (an
  explicit user instruction may waive bootstrap; task triviality/urgency is NOT a waiver), keeps
  STEP 0 a non-blocking offer, and keeps bootstrap **silent** (tool calls visible, no narration/
  manifest). Design validated by two independent distinct-lens reviews (consistency +
  adversarial) before merge; verified end-to-end in a real project: attach-alone → full
  bootstrap; plain follow-up → no spurious re-bootstrap; re-attach in same session → idempotent
  skip; FAMILY A (`chat_history`) + FAMILY B (Graphify) retrieval routing intact.

- **Lifecycle-anchored memory retrieval — gates fire on workflow moments, not just
  question-semantics (v0.10.0).** Until now retrieval was driven purely by the question-
  semantic FAMILY A/B/C routing, so memory was consulted only when the agent recognized an
  information gap in what it was *asked* — never anchored to where it *was* in the workflow.
  A new `<workflow_retrieval_gates>` block in `sumela-prompt.md` adds three lifecycle anchors
  (additive to FAMILY A/B/C; all SOFT / best-effort, no enforcement hook): GATE 1 task-intake
  fires on `brainstorming` entry → consult Tier-3 `_SEARCH_INDEX` + Tier-1b `wiki_pages`
  before raw recon; GATE 2 impact-before-contract-change runs `query-graph.py <symbol>
  --impact` before changing a pre-existing symbol's signature (covers all six code-writing
  skills via the eager block plus a mirrored trigger in
  `subagent-driven-development/implementer-prompt.md`); GATE 3 find-code-by-behavior promotes
  `code_chunks` semantic search to a first-class route, ahead of a blind grep, when the symbol
  name is unknown. FAMILY A (`chat_history`) is demoted from MANDATORY to **best-effort**
  (skip when known-empty, note once per session) — routing re-aimed at where the data actually
  lives (`code_chunks`, `wiki_pages`); FAMILY B/C stay MANDATORY, with mirrors aligned in
  `using-second-brain` and `using-superpowers`. A script-side per-session dedup cache is added
  to `query-graph.py` and `query-qdrant.py` (gitignored `.sumela/.retrieval-cache.json`) so
  repeated identical queries within a session are skipped. **Language-agnostic by design:** no
  per-language parsing in core — contract-change judgment lives in the agent/graphify, and the
  gates stay deliberately soft prose with no enforcement hook (documented follow-up if soft
  prose underfires: a narrow git rename/delete-only mechanical leg).

- **Checkpoint vs Flow review mode — per-task review is now the user's choice (v0.9.0).**
  Field feedback from the first real project run: not every user wants a reviewer
  dispatch + approval stop after EVERY task; some prefer one comprehensive review at the
  end. `subagent-driven-development` (new Step 0) and `executing-plans` (Step 2) now ask
  ONCE at execution start: **Checkpoint mode** (default/recommended — per-task Stage-1
  spec + Stage-2 quality/security reviews and a per-task approval gate) or **Flow mode**
  (tasks run back-to-back with one-line progress notes; ONE comprehensive
  `requesting-code-review` covers everything at the end). Guardrails: Flow mode is valid
  ONLY via explicit user opt-in (never self-selected; no answer = Checkpoint), the final
  comprehensive review is mandatory in BOTH modes, plan `## Checkpoint:` blocks still run
  their verifications, and Flow mode still stops on verification failures, ambiguity, or
  auth/security-boundary tasks (those also get Stage-1/Stage-2 even in Flow mode). The
  `identity_and_behavior` per-task-gate rule, `requesting-code-review` cadence notes, and
  the `RULE_REGISTRY.md.template` rule description are updated to the same contract
  (already-installed projects keep their generated RULE_REGISTRY.md — the registry
  description drift there is cosmetic; the rule file itself is replaced by update.sh).

- **Phase-transition rule sync — STEP 4 is no longer bootstrap-only (v0.9.0).** Field
  feedback: rules loaded at session bootstrap (often `[Phase: <none-yet>]`) were never
  re-evaluated when `writing-plans` or an execution skill activated a new phase, so
  phase/stack/domain-conditional rules (e.g. `architecture_patterns` at planning) could
  silently stay unloaded. The canonical contract now lives in `sumela-prompt.md` STEP 4
  (re-run on EVERY phase/stack/domain change), `using-superpowers` STEP 4 enforces it on
  every skill load, and the four core phase skills (`brainstorming`, `writing-plans`,
  `executing-plans`, `subagent-driven-development`) carry their own PHASE RULE SYNC
  backstop step referencing `.sumela/RULE_REGISTRY.md` explicitly.

- **Information-gap routing FAMILY C — project-reference / how-to questions (v0.8.0).** The
  eager `<information_gap_routing>` block (loaded every session) only had FAMILY A
  (past-decision / "why" → Qdrant `chat_history`) and FAMILY B (call-graph / impact →
  Graphify); a present-tense PROJECT-REFERENCE / how-to question ("how do we scaffold a
  service here", "which port does X use", "is there a runbook for Y") matched neither, so
  no tier fired before the skill loaded — the agent risked answering from training or a
  blind grep instead of the project's curated docs. New FAMILY C routes these to Tier-3
  (`_SEARCH_INDEX.md` keyword, mandatory) escalating to Tier-1b (Qdrant `wiki_pages`
  semantic), with the Self-Check now auditing it too. Criteria are tight to avoid
  false positives (fires ONLY for project-specific reference/how-to; excludes general
  programming questions, in-progress edits, plain conversation, and anything already in
  A/B). Also closes two adjacent gaps: Tier-1c (`code_chunks` semantic) is now an eager
  escalation under FAMILY B when the graph is too narrow; and cold-start guards skip an
  empty/unreachable `chat_history` (FAMILY A) or unindexed docs (FAMILY C) with a one-line
  note instead of running empty queries. Trigger definitions stay canonical in the eager
  layer; `using-second-brain`'s decision tree is updated as operational detail only (no
  drift). Eager-layer growth: 18 lines added / 7 replaced (net +11).

### Fixed

- **The pull-time graph sync no longer forces an unreadable `graph.html` (v0.14.0).** Field
  finding from a consuming repo: every `git pull` that touched code pinned a core for minutes.
  The cause was not the graph rebuild — `graphify update`'s AST extraction is already parallel
  (`ProcessPoolExecutor`, workers = `cpu_count`) — but what SumelaOS did *after* it. graphify
  skips the interactive `graph.html` above its ~5000-node viz limit; both
  `auto-update-memory.py` and `setup-memory.{sh,ps1}` treated that skip as an incomplete build,
  raised `GRAPHIFY_VIZ_NODE_LIMIT` above the real node count, and re-ran `graphify cluster-only .`
  to force it. That is a **second full Louvain pass plus a huge HTML write on every pull**:
  measured on a 193k-node / 305k-edge repo, **~226 MB** of HTML that no browser can open, with
  clustering — single-threaded by nature, no flag parallelizes it — run twice.

  Nothing in the retrieval path reads that file. Tier-2 is `query-graph.py`, which reads
  `graph.json`; the `graphify-insights` wiki page is generated from `GRAPH_REPORT.md`. The viz
  was pure cost. The forcing is removed in all three places and **success now gates on
  `graph.json`** — the artifact the query path actually consumes — with the skipped viz reported
  as a NOTE (`INFO`, not `WARN`/`todo`: on a large repo it is the expected outcome, not a chore).
  Small repos are unaffected: under the limit graphify still writes the viz natively and that
  path still reports "incl. interactive graph.html".

  The capability is kept as an opt-in rather than deleted: `SUMELA_GRAPHIFY_VIZ=1` restores the
  forced regeneration for the pull-time sync, and the exact manual command
  (`GRAPHIFY_VIZ_NODE_LIMIT=<nodes+1000> graphify cluster-only .`) is printed in the note. Only a
  non-empty value other than `0` enables it, so a stale `SUMELA_GRAPHIFY_VIZ=0` in a shell profile
  cannot silently re-enable the cost.

  **The success gate is `graph.json` AND a zero exit code, not the artifact alone.** The review
  panel caught a first cut of this change that dropped the `build_rc`/`$built` term from
  `setup-memory.{sh,ps1}`: a failed `graphify update` running over a *stale* `graph.json` from an
  earlier build would then have printed "Code graph built" and "Nothing left to do by hand", and
  on a large repo — where `graph.html` never exists — that is the default path, not an edge case.
  Both terms are now required, matching `auto-update-memory.py`, which never dropped its rc check.

  The skipped-viz note only says what it can establish: above the limit it names the limit, below
  it it says the missing file is *unexpected* rather than prescribing the raise-the-limit remedy,
  and after a failed opt-in regeneration it says so instead of suggesting the flag the user
  already set.

  Covered by two suites, both wired into `tests/smoke.sh` and therefore CI:
  `tests/test_graph_viz_not_forced.py` (23 assertions; 5 fail against the old code — no
  `cluster-only`, no `GRAPHIFY_VIZ_NODE_LIMIT` in the child env, exactly one subprocess call, the
  note points at the opt-in, `=0` stays off) and `tests/test_setup_memory_graph_gate.sh`
  (9 assertions against a stubbed `graphify` on `PATH`, no real CLI needed; 4 fail against the old
  code). Between them they pin the gates that must NOT change: a missing `graph.html` is still a
  success, a missing `graph.json` is still a failure even when graphify exits 0, and a non-zero
  exit is still a failure even when a stale `graph.json` is on disk.

- **`git worktree add` no longer re-embeds the entire code base (v0.13.0).** Field finding from a
  consuming repo: creating a worktree queued **17,387 files** for re-embedding — the whole
  tree — pinning `ollama serve` at 68% CPU with no progress 28 minutes after the last log
  line, and every upsert failing with a 500 from `/api/embeddings`. Root cause: `git
  worktree add` hands `post-checkout` an **all-zero previous HEAD**, byte-for-byte the same
  signal `git clone` gives, and the hook mapped both to the empty-tree diff so every tracked
  file counted as "added". Correct for a clone; wrong for a worktree, where nothing the
  derived caches are built from has changed.

  `post-checkout` now discriminates via a new `_sumela_is_linked_worktree` (`--git-dir` vs
  `--git-common-dir`, compared on **normalized physical paths** — git returns them in mixed
  forms depending on cwd, `/abs/.git` vs `../.git` from a subdirectory, and a raw string
  compare misreads the main checkout as a worktree). On worktree creation **every** sync is
  skipped — the three Qdrant syncs, the collection migrate, and `graph_sync` — leaving only
  the rate-limited update check.

  `graph_sync` is skipped for the same reason as the rest, which took measuring to
  establish: `setup.sh` wires a **relative** `core.hooksPath`, git resolves it against the
  **main** working tree, so `git worktree add` runs the *main checkout's* hook and
  `SUMELA_INSTALL_ROOT` is the main checkout even though cwd is the worktree. Every derived
  cache — Qdrant collections and `graphify-out/` alike — belongs to the main checkout, whose
  tree a new worktree does not touch. An earlier revision of this fix kept `graph_sync` on
  the mistaken premise that the graph was per-worktree; it would have forced a full graphify
  rebuild of the main checkout on every `git worktree add`.

  Clone behaviour, in-worktree checkouts, and main-checkout checkouts are unchanged. Opt back
  in with `SUMELA_WORKTREE_SYNC=1` — its own variable, not a reuse of the permanently
  `export`ed `SUMELA_PULL_CODE_REINGEST`, which would have disabled the guard for anyone who
  set it once. The skip notice is gated on Qdrant actually being reachable (the plugin
  directory is tracked in git, so its presence proves nothing).

  Covered by `tests/test_post_checkout_worktree.sh` (7 cases / 19 assertions, wired into CI):
  5 assertions fail against the old hook; case 5b calls `_sumela_is_linked_worktree` directly
  from a subdirectory — the only level where the mixed path forms occur — and fails if the
  normalization is dropped; case 7 pins the relative-`core.hooksPath` install-root fact the
  whole design rests on, which the absolute path used by the other cases cannot show.

  Two pre-existing gaps found while doing this and documented in
  `.sumela/git-hooks/README.md` rather than papered over here: `chat_history` has no
  initial-population path outside a hooks-wired clone (every other hook path is
  range-incremental, and `setup-memory.sh` seeds only `wiki_pages`), and a checkout inside a
  worktree indexes the **main** checkout's content because the ingest resolves the
  worktree's changed paths under main's tree. The worktree empty-tree diff masked the first
  by accident — the same accident being fixed here.

- **`session-ingest.py` reported success after a failed ingest (v0.13.0).** The companion to
  the embedding fix above, found by reviewing this release: the two bulk ingests got the new
  three-valued exit contract, but the summary path kept `sys.exit(0)` on every failure — it
  printed `WARNING: Qdrant upsert failed` and still told its caller it had succeeded. That
  caller is the pull hook, so the observable result was the silent "memory did not update"
  the field report described. It now exits `1` when an embed or the upsert fails, matching
  the `PARTIAL` status it was already printing. Deliberately **two**-valued, not three: one
  summary is atomic (every embedding is computed before the old points are deleted), so there
  is no partial state for a `2` to describe. `_lib.sh` already invoked it as
  `python3 "$ingest" ... || echo "WARN: ingest failed"` inside a detached background
  subshell, so a non-zero exit is what the caller always expected and git is still never
  failed. It also gained the `ollama_preflight` its two siblings got, so a stopped backend is
  reported once instead of being rediscovered chunk by chunk while sleeping through the retry
  budget. The plugin README's "Graceful Degradation" section documented the old
  exit-0 behaviour and is corrected.

- **Python bytecode caches were not ignored in consuming repos (v0.13.0).** This repo's own
  `.gitignore` carries the generic `__pycache__/` rule, but `scripts/lib/sumela-gitignore.list`
  — the single source setup/update seed into a consuming project's `.gitignore` — did not, so
  running any memory script left untracked `__pycache__/` directories under `.sumela/` in every
  non-Python project (a .NET or Node consumer has no reason to ignore Python artifacts). Added
  as `.sumela/**/__pycache__/`, scoped to `.sumela/` on purpose: this is SumelaOS's own runtime
  artifact, not a rule about the consumer's source tree.

- **`.sumela/.heal-last` was committed as a tracked file (v0.13.0).** The withdrawal of the
  self-healing index correctly deleted the four `.gitignore` / `sumela-gitignore.list` entries
  for its runtime markers, but the same commit also committed one of those markers — a bare
  unix timestamp — leaving a stray tracked file that no code writes any more and that every
  consuming repo would inherit. Removed; the ignore-rule deletions stay, since nothing
  references those paths.

- **Embedding: an over-long chunk killed the Ollama model runner and silently punched
  holes in the index (v0.13.0).** Field finding from a consuming repo: one ingest run
  lost **2496 chunks across 617 files** while reporting `SUCCESS`. Ollama loads an
  embedding model with `n_batch = n_ubatch = 2048`, and an embedding model is
  **non-causal** — bidirectional attention needs the whole sequence in ONE ubatch, so
  llama.cpp cannot split an over-long prompt: it aborts (`SIGTRAP`), the runner process
  dies, and Ollama answers `500` to that request *and to every other request in flight*
  (`MAX_WORKERS = 4`, so one bad chunk took three innocent neighbours with it). Bisected
  and reproduced deterministically on `qwen3-embedding:0.6b`: 1970 tokens → `200`, 2104
  tokens → `500`, cache-cold. Nothing caught it because `chunk_text` budgets **words**
  while the limit is in **tokens** — the two differ by 2-7x, and a whitespace-free file
  (minified bundle, base64 blob, single-line generated file) collapses to ONE "word" and
  sails past any word budget. Four independent defects, all fixed:
  - `get_embedding` now sends `options.num_batch` (default 8192, `SUMELA_EMBED_NUM_BATCH`)
    — verified A/B, same input `500` → `200`.
  - `chunk_text` now hard-bounds every emitted chunk, splitting on a **UTF-8 byte**
    budget when words cannot. The bound is `bytes + 2`, provable because byte-level BPE
    (what Qwen uses) never emits a token covering less than one byte. A character-based
    bound was tried first and **shipped broken through two commits**: it under-counts
    every multi-byte script by up to 4x, and a review reproduced live 500s on ordinary
    CJK — which is the worst case in practice because CJK has no word spaces, so a
    paragraph collapses to one "word" and always takes the split path. The ASCII-only
    regression test could not see it. The token budget is **derived** from `num_batch`
    (90%) instead of configured beside it, so lowering one cannot silently invalidate
    the other, and the split accumulates whole characters so a codepoint is never cut.
  - `get_embedding` retries once: a neighbour killed as collateral damage succeeds on the
    second attempt after Ollama restarts the runner.
  - **Ingest is now all-or-nothing per file/page.** Previously a failed chunk was skipped
    and the survivors were upserted *after deleting every existing point for that file* —
    silently replacing a complete index entry with a partial one, and reporting `SUCCESS`.
    A silently incomplete entry is worse than a stale one: retrieval answers confidently
    from a file it only half knows. Files with any failed chunk are now left untouched,
    counted in the report, and the run exits non-zero.

  Also consolidates three private copies of `get_embedding` (and two of `chunk_text`) into
  `lib/memory_ingest.py`. `session-ingest.py` and `query-qdrant.py` each shadowed the
  shared helpers, so fixing the lib alone would have left the session-summary path **and
  the query path** — which embeds caller-supplied text — still crashing. Covered by a new
  dependency-free `tests/test_embedding_bounds.py` (wired into `tests/smoke.sh`, so CI
  runs it) that pins the real measurements, the whitespace-free case, `num_batch` presence
  and the retry contract.


- **graphify plugin: rebuilds hard-failed without an LLM key on repos with docs (v0.9.1).**
  Field report from a consuming repo (graphify CLI 0.8.35, 308 non-code doc/image files):
  `auto-update-memory.py` invoked `graphify .` / `graphify . --update`, which in current
  graphify attempts SEMANTIC extraction of doc/paper/image files and hard-fails without
  an LLM API key — so the pull/checkout auto-rebuild silently died (`graphify=FAIL`),
  contradicting the plugin's "AST-only by design, no API key" contract. Verified
  empirically and switched every invocation to the no-LLM `update <path>` subcommand,
  which also works as the FIRST build (confirmed with no pre-existing graph.json):
  `auto-update-memory.py` (`run_graphify` + docstring + `--graph-only` help),
  `setup-memory.sh` / `setup-memory.ps1` first-build blocks and fallback hints, the
  plugin README/SKILL.md (incl. the prerequisites line), `ADOPTION_GUIDE.md`,
  `sync-graphify-to-obsidian.py`'s error hint, and `context-handoff`. `--force` is
  deliberately NOT hard-coded (graphify's fewer-nodes guard protects against a broken
  parse wiping the graph); `GRAPHIFY_FORCE=1` in the env passes through to the
  subprocess for deleting refactors. (Adversarial review also killed a hint suggesting
  `update . --no-cluster` over an existing graph — verified destructive: it strips all
  community assignments from graph.json.)

- **graphify plugin: `query-graph.py` crashed on Python < 3.10 (v0.9.1).** The
  `dict | None` / `str | None` annotations were evaluated at class-definition time
  (`TypeError: unsupported operand type(s) for |`). Added
  `from __future__ import annotations` (matching `auto-update-memory.py`).

- **Agent could start coding without `brainstorming` — eager DEVELOPMENT GATE added (v0.9.0).**
  Field feedback: given a detailed task description, the agent skipped `brainstorming` and
  wrote code directly. Root cause: the no-code-before-approved-design HARD-GATE lived only
  INSIDE the lazy `brainstorming` skill — if the dispatcher never matched/loaded it, no
  eager HARD gate existed (`identity_and_behavior`'s "Plan-Driven Output" was only a soft
  nudge); and a detailed request reads as "design already chosen → skip". Fix at three
  layers: (1) `sumela-prompt.md` `<skill_resolution>` gains an eager DEVELOPMENT GATE —
  implementation code requires an active implementation skill working from an approved plan,
  `systematic-debugging` for bug fixes, or explicit user consent for a trivial direct edit;
  anything else is a dispatch failure that re-runs `using-superpowers` STEP 4; (2)
  `using-superpowers` intent anchors + forbidden rationalizations now state that a highly
  detailed request is brainstorming INPUT (it speeds the loop), never an approved spec;
  (3) the `brainstorming` routing `description` (frontmatter + SKILL_REGISTRY, in parity)
  says the same, so the dispatcher match itself can no longer be rationalized away.

- **`secure-coding-standard` was not loaded during planning (v0.9.0).** Field feedback:
  a plan was written without the standard in context. `writing-plans` (new Step 0) and
  `brainstorming` (new Step 0) now MANDATE reading
  `.sumela/skills/secure-coding-standard/SKILL.md` before any spec/plan output — for
  EVERY plan, not just "security-flavored" ones. The skill's routing `description`
  (frontmatter + `SKILL_REGISTRY.md`, kept in parity) now advertises the plan-time
  entry point, and `sumela-prompt.md` `<skill_resolution>` SECURITY MANDATE is aligned
  (unconditional for code work; the sensitive-surface list no longer reads as the only
  trigger). `executing-plans` Step 2 likewise loads it unconditionally.

- **Specs/plans invisible in git and the IDE Changes view (v0.9.0).** Root cause found
  in a real install: the standard VisualStudio/.NET `.gitignore` ships a generic
  `artifacts/` build-output pattern that matches ANY directory named `artifacts` — so
  `docs/second-brain/artifacts/{specs,plans}/` files never appeared in `git status` or
  the Source Control Changes panel. Three-layer fix: (1)
  `scripts/lib/sumela-gitignore.list` (single source for setup/update, both shells)
  gains `!docs/second-brain/artifacts/` + `!docs/second-brain/artifacts/**` re-include
  negations, appended at the end of `.gitignore` where they win; (2) `init-sumela`
  Step 3.6b now reads that same `.list` (per-line guards) instead of its own drifted
  inline copy — also picking up the previously missing `.sumela/.update-check`; (3)
  `brainstorming`/`writing-plans` gain a mandatory post-save VISIBILITY CHECK: decide on
  `git check-ignore -q` EXIT CODE only (exit 1 = visible = success; `-v` output alone is
  misleading because it also prints the `!…` negation as a "match"), remediate by
  re-appending the negations at the END of the install-root `.gitignore`, and STOP with
  a warning if a parent dir (e.g. `docs/`) is itself ignored. Artifacts must also be
  written with the IDE's file-write tool so the IDE change tracker registers them.

### Security

- **Hardened the pull-time update check (v0.7.1).** Post-review fixes to the v0.7.0
  `sumela_update_check`: (1) the upstream tag probe now runs in a **detached background**
  process and prints the notice synchronously from cache — macOS ships no `timeout`, and
  the previous inline `git ls-remote` could stall a `git pull` on an unreachable/slow
  upstream (a fresh release now surfaces on the *next* pull instead); (2) the probe (and
  the updater's clone) run with `GIT_ALLOW_PROTOCOL=https:ssh:git` so a poisoned (tracked)
  `.sumela/upstream.conf` can't execute code via git's `ext::`/`file::` transport, plus
  `GIT_TERMINAL_PROMPT=0` + ssh `BatchMode` so it never prompts for credentials;
  (3) a corrupt/garbled cache version field is ignored instead of surfacing in the notice.
  README documents the trust boundary (CODEOWNERS-protect `.sumela/upstream.conf`).

### Added

- **Pull-time "newer SumelaOS available" notice.** Adopters now find out automatically
  when the framework has a newer release instead of having to remember to run the
  updater. `post-merge`/`post-checkout` run a new best-effort `sumela_update_check`
  (`.sumela/git-hooks/_lib.sh`): it lists the upstream's release tags via
  `git ls-remote --tags` (the developer's own git auth — works for public AND private
  upstreams, no clone) and, if a newer `vX.Y.Z` than `.sumela/VERSION` exists, prints a
  one-line non-blocking notice pointing at `bash scripts/update.sh`. The probe is
  rate-limited to once per `SUMELA_UPDATE_CHECK_INTERVAL` (default 24h) via the
  gitignored `.sumela/.update-check` cache; the notice keeps showing every pull (from
  cache) until you update. Best-effort: offline / no git / no upstream tags → silent,
  never blocks a git op. Opt out with `SUMELA_DISABLE_UPDATE_CHECK=1`. The upstream URL
  lives in a new tracked `.sumela/upstream.conf` (single source, fork-overridable) that
  `scripts/update.{sh,ps1}` now also read. Releases are tagged `vX.Y.Z` from now on so
  the check has something to compare against.

- **`post-commit` hook — memory sync survives conflicted merges.** A conflicted
  `git merge`/`git pull` does NOT run `post-merge` (git stops at the conflict and runs
  the COMMIT hooks on the manual resolution commit instead), so until now a conflicted
  pull never refreshed the local Qdrant `code_chunks`/`chat_history`/`wiki_pages` or the
  code graph — a teammate's conflicting changes silently never reached your semantic
  index. The new `post-commit` closes that gap: it runs the same four sync functions as
  `post-merge` (for `HEAD^1..HEAD`) but ONLY when HEAD is a merge commit (≥2 parents),
  and is an immediate `exit 0` no-op on every ordinary commit. No double-firing — a clean
  merge creates its commit without running commit hooks (only `post-merge` fires); a
  conflicted merge skips `post-merge` and only `post-commit` fires — verified empirically
  on git 2.x. Known gaps documented (not conflated): `git merge --squash` (single-parent,
  not detectable by parent count) and `git pull --rebase` (not a merge) remain covered by
  the next clean merge/checkout + session bootstrap; `git commit --amend` on a merge commit
  harmlessly re-runs the idempotent sync. Wired through `setup.{sh,ps1}` (direct + monorepo
  dispatcher), `update.sh`, the CI shell-lint loop, and `.sumela/git-hooks/README.md`.

- **Extra documentation ingest paths** — adopting projects can index authoritative docs that
  live OUTSIDE `docs/second-brain/wiki/` (architecture docs, ADR dirs, API references) into the
  same Qdrant `wiki_pages` Tier-1 index, on the same pull-time/background/gated terms as the
  wiki — without copying them into the wiki (no drift). Mechanism in the framework, policy in
  the consumer: the framework ships an EMPTY default and NO project-specific paths. Configure
  per project via `.sumela/ingest.conf` (tracked, one repo-relative dir per line; copy the
  shipped `.sumela/ingest.conf.example`) or the `EXTRA_INGEST_DIRS` env var (comma/colon-
  separated; wins when set). A single resolver (`lib/memory_ingest.get_extra_ingest_dirs`,
  exposed to bash/PowerShell via `resolve-ingest-dirs.py`) does all resolution + validation so
  the three callers never drift: paths must be repo-relative and resolve to a real dir strictly
  inside the repo (absolute / `~` / `..` / globs / drive-letters / leading-dash / symlink-escape
  all rejected; missing skipped with a warning, never fails a pull). Docs only — `.md` files,
  symlink-safe walk (no following dir symlinks; per-file repo-containment re-check), deduped by
  resolved path; the code corpus is untouched. A per-run file cap (`EXTRA_INGEST_MAX_FILES`,
  default 5000) plus `.git`/`node_modules`/`vendor` skips bound the background re-embed.
  `sumela_wiki_sync` expands its change scope + orphan-prune to the extra dirs; `setup-memory`
  seeds them on first bring-up; `status.{sh,ps1}` report them. Documented in `ADOPTION_GUIDE.md`
  (incl. the trust note: a tracked path is a team-wide decision — CODEOWNERS-protect in team
  mode). Covered by `tests/test_extra_ingest_dirs.py`.

- **Rich, queryable session memory** — session summaries now carry structured metadata so
  memory answers "which developer did what, in which domain, when". A canonical
  `session-summary` page type + template lands in `_SCHEMA.md` (frontmatter: `developer`,
  `developer_email`, `domains`, `spec_artifact`, `plan_artifact`, `session_date`,
  `session_topics`; required detailed sections). `session-ingest.py` ingests these into the
  `chat_history` payload (incl. `date_int` for range filters); `query-qdrant.py` gains
  `--developer` / `--domain` / `--since` / `--until` filters plus a filter-only listing mode
  (`"*"` query → all matches via scroll, not top-K). The post-merge hook passes the commit's
  git author/date as `--fallback-developer`/`--fallback-date` so even un-stamped summaries are
  attributed. `sumela-prompt.md` routes who/when/domain questions to these filters (git log as
  the authoritative commit-level fallback).
- **Session summary written at task completion, not only on handoff** — the
  `<session_summary_protocol>` is now canonical in `using-second-brain` (single source);
  `context-handoff` references it, and `finishing-a-development-branch` Step 7 also writes +
  ingests a session summary. Previously a clean task finish with no context-pressure handoff
  left no conversational `chat_history` record (only curated-wiki ADR/commit-log updates).

- **Business-domain rule scope** — a third rule axis, orthogonal to stack scope.
  In team mode, setup / `/initSumela` asks the project's domain taxonomy (e.g. Card,
  Payments); each domain gets a tracked `RULE_REGISTRY.md` `<domain_scopes>` entry +
  a `.sumela/rules/domains/<slug>.md` rule file (generated from a new
  `domain_standards.md.empty` template). Which domain(s) a developer works in is
  per-developer and untracked (`.sumela/local.md` `domains:`); `sumela-prompt.md`
  STEP 4 loads the union of matching domain rules (a developer can be `backend` +
  `Card` at once), warning-and-skipping any domain not in the taxonomy. The Context
  Manifest gains a `[Domain: …]` header. `reconcile-registry.py` and
  `validate-structure.sh` now enforce domain rule↔registry parity (and `--stats`
  reports `domain_rules`).
- **`/onboardSumela` teammate onboarding** — a new skill (the single source of truth)
  for a developer who pulls an already-installed repo. It wires git hooks, sets the
  per-developer interaction language + domains in `.sumela/local.md`, and offers the
  optional memory runtime — without re-running install or touching team-wide config
  (use `/initSumela` only for first-time install). A non-nagging `STEP 0` onboarding
  gate in `sumela-prompt.md` detects a fresh clone (hooks unwired AND no `local.md`)
  and offers it once, deferring to the skill rather than duplicating its steps.
- **Parallel code-review panel** — `requesting-code-review` now dispatches three
  lane reviewers concurrently instead of one generalist: Correctness & Security
  (incl. auth/credential token lifecycle + security-boundary tests), Design &
  Contracts (conventions, architecture, API/contract stability, backward-compat),
  and Integration & Operations (cross-module impact via graphify, performance,
  data/persistence, observability/rollback, test coverage). The orchestrator then
  synthesizes the lanes — dedupes overlapping findings, surfaces `CONFLICT`s, and
  applies an AND-gate (any lane's Critical blocks commit/merge). New lane templates:
  `reviewer-correctness-security.md`, `reviewer-design-contracts.md`,
  `reviewer-integration-ops.md`; the legacy single-reviewer `code-reviewer.md` is
  retained as an IDE/degraded fallback. SDD's final review (Step 5) inherits the
  panel automatically; its per-task Stage-1/Stage-2 reviews are unchanged.
- **`reconcile-registry.py --stats`** — prints the canonical skill counts
  (`skill_workflows`, `loadable_skills`, `plugin_skills`) as the single source of
  truth for any number quoted in docs.
- **README skill-count drift guard** — `validate-structure.sh` compares the README
  `<!-- sumela:skill-count -->` marker against `--stats` and fails on mismatch, so
  the documented count can never silently diverge when a skill is added/removed
  (silent no-op in user projects, where README isn't present).
- **"How SumelaOS Extends Superpowers" README section** — an evidence-based,
  honest side-by-side vs [obra/superpowers](https://github.com/obra/superpowers)
  (21 vs 14 skill workflows, the review panel, rules/memory/governance layers — and
  where Superpowers is still broader on harness count).

### Changed

- **Context Manifest triggers narrowed** — the manifest now prints only on explicit
  user request (`/context`) and immediately before high-stakes actions (commit,
  code-review dispatch, finishing a branch, shipping, `/evolve`). It no longer
  prints at session start or on every phase transition, removing the "first output
  must be the manifest" mandate. Cuts recurring output tokens and per-turn latency
  while keeping the GAP-visibility checkpoint where it matters; spec trimmed in
  `sumela-prompt.md`. Dependent references (using-superpowers, RULE_REGISTRY
  template, AGENTS.md template, init-sumela, README) updated to match.

- **Qdrant `code_chunks` now refreshes incrementally on every pull, automatically.**
  `sumela_code_sync` previously gated the heavy whole-tree re-embed behind a 14-day
  staleness check that PROMPTED `[y/N]` on an interactive pull (default No) or printed
  a notice on a non-interactive one — so semantic code search routinely drifted up to
  two weeks stale on an active repo. It now re-embeds just the files that changed in the
  pull (`ingest-code-to-qdrant.py --changed-file <list>`), in the background, with no
  prompt — the same cheap/non-blocking terms as `sumela_wiki_sync`. The ingest script
  self-creates the `code_chunks` collection if missing and promotes an incremental run
  to a FULL walk when the collection is empty, so the first pull after setup builds the
  whole corpus (and `setup-memory` no longer leaves it for a manual/prompted build).
  `SUMELA_PULL_CODE_REINGEST=1` is repurposed to force a full tree re-embed on a pull;
  `SUMELA_DISABLE_CODE_SYNC=1` still turns the whole thing off. The freshness decision
  is now ground-truth (the script checks the collection's real `points_count`) rather
  than the `.code-chunks-synced` marker — which fixes a false-negative where an index
  built outside the hook (manual run / first setup) left the marker unwritten, so the
  hook claimed code_chunks "has never been built" on every pull even with a full
  collection (and the command it suggested, the standalone ingest, never wrote the
  marker, so the warning was unsilenceable). The marker is retired: nothing reads or
  writes it now (per-ingest timestamps live in `.sumela/.memory-sync.log`); its
  `.gitignore` entry is kept only so leftover files from older installs aren't
  committed. Docstring, `qdrant-session-memory/SKILL.md`, and `setup-memory.{sh,ps1}`
  updated to match.

### Removed

- **`SUMELA_CODE_REINGEST_DAYS`** — the code_chunks staleness threshold is gone now that
  re-embedding is incremental-on-every-pull. Anyone who set it can drop it (it is silently
  ignored); use `SUMELA_PULL_CODE_REINGEST=1` to force a full re-embed instead.

### Fixed

- **`.gitignore` runtime-artifact entries now reach UPGRADED installs, not just fresh ones
  (v0.7.2).** `.gitignore` is OVERLAY (the updater never overwrites it), so a managed
  pattern that a release added to setup's seed block — e.g. `.sumela/.update-check` in
  0.7.1 — landed only on fresh installs; projects upgrading via `update.{sh,ps1}` never
  got it, leaving the hook's cache file UNTRACKED (status noise / accidental-commit risk).
  Root cause was structural: the managed list lived only inside `setup.{sh,ps1}`, and even
  setup's own "backfill newer entries" guard was a hand-maintained subset that had drifted
  (it listed `.sumela/_migration/` + `AGENTS.md.bak*` but not the newer cache files). Fix:
  the managed patterns now live in ONE language-agnostic source,
  `scripts/lib/sumela-gitignore.list`, read by `setup.sh`/`setup.ps1` (seed + full backfill)
  AND by a new idempotent reconcile step in `update.sh`/`update.ps1` (adds only patterns
  absent anywhere in `.gitignore`, never duplicates an existing entry, never touches the
  user's own lines; diff + consent, auto on `--yes`, shown-only on `--dry-run`; creates
  `.gitignore` if absent; monorepo-subdir aware). Adding a future runtime-artifact pattern
  is now a one-line edit to the shared list that reaches fresh and upgraded installs alike.

- **Qdrant ingestion no longer silently no-ops in adopted projects.** The Qdrant plugin's
  `get_repo_root()` (`memory-plugins/qdrant-session-memory/scripts/lib/memory_ingest.py`)
  hard-coded "three levels up" from the module, which resolved to the *plugin* directory
  (`.sumela/memory-plugins/qdrant-session-memory`) rather than the repository root. In every
  project that vendored SumelaOS, `WIKI_DIR`/`SRC_DIR` then pointed under the plugin dir
  (so wiki/code ingest found nothing) and `relative_to(REPO_ROOT)` raised on real doc paths —
  the `wiki_pages`/`code_chunks` collections stayed permanently empty while `setup-memory`
  still reported them "ready" and `query-qdrant` returned 0 results forever, so Tier-1
  semantic memory was non-functional with no error on the happy path. `get_repo_root()` now
  walks up to the first ancestor containing `.git` or a top-level `.sumela/` (matching what
  the PowerShell scripts already do), honors a `SUMELA_REPO_ROOT` override, and keeps the old
  three-levels-up only as a last-resort fallback — correct in both the framework's own repo
  and vendored adoptions. Covered by `tests/test_get_repo_root.py` (run in `tests/smoke.sh`).

- **Graphify build no longer reports false success or silently skips `graph.html`.**
  `setup-memory.{sh,ps1}`, `auto-update-memory.py`, and a downstream sync error message used
  `graphify update .` — the incremental path — for the initial build, and the setup scripts
  suppressed all output (`*> $null` / `>/dev/null 2>&1`) and declared "Code graph built" on
  exit 0 alone. On any repo over graphify's ~5000-node viz limit, the interactive `graph.html`
  was skipped with a warning the user never saw, yet setup still reported success. Now:
  - **All paths** use the canonical `graphify .` for the first build (`graphify . --update` only
    for incremental re-runs — `--update` is a flag, not the legacy `update` subcommand).
  - **`setup-memory.{sh,ps1}` (interactive setup):** output is no longer suppressed, so graphify's
    own viz/limit warnings reach the user; the "Code graph built" success is gated on `graph.html`
    actually existing, not exit 0; when graphify skips the viz on a large graph, setup reads the
    real node count, raises `GRAPHIFY_VIZ_NODE_LIMIT` above it, and regenerates the viz via
    `graphify cluster-only .` — falling back to a flagged to-do with the exact command if it still
    can't, never a fake "built".
  - **`auto-update-memory.py` (the git-hook / background path):** same canonical command + viz
    auto-raise/regenerate; graphify's own viz/`graph.html` warnings are best-effort echoed from
    captured output (and a `cluster-only` failure is reported with its exit code), while the
    structured report ALWAYS carries an explicit `note:` line distinguishing "graph updated" (the
    query-critical `graph.json` is fresh) from "interactive `graph.html` skipped" + the exact
    remediation. A skipped viz is reported, not silently treated as full success, and not treated as
    a hard failure (which would falsely fail the background hook on every large-repo commit).
  - The graphify plugin README now documents the AST-only nature (semantic extraction needs a
    generative backend SumelaOS does not wire up), that Tier-2 queries work off `graph.json` even
    when the viz is skipped, and why `graphify-out/` is gitignored.

## [0.4.0] - 2026-06-02

### Added — less manual work, monorepo support

- **Auto-reconcile `SKILL_REGISTRY.md`** — `scripts/reconcile-registry.py` registers
  on-disk skills missing from the registry (verbatim description, `activation="lazy"`)
  and reports orphans; run by `update.sh` with consent.
- **Health report** — `scripts/status.sh` / `status.ps1`: one read-only command for
  version, governance, structure, registry/mirror/shared-rule drift, improvement-queue
  count, git-hook wiring, secret scanner, and memory plugins. Every issue lists its fix.
- **Secret governance** — if `gitleaks` is installed, the pre-commit hook scans staged
  changes and blocks on a finding (silent if absent; `SUMELA_DISABLE_SECRET_SCAN=1` to
  disable; tool/version errors never block). Setup seeds a `.gitignore` secret baseline.
- **Monorepo support** — hooks self-anchor to their install dir (subdir installs now
  validate their own subtree instead of silently no-op'ing). Multiple installs in one
  repo auto-promote to a root dispatcher (`.sumela-hooks/` + `_dispatch.sh`) that runs
  every install's hooks. Org-shared rules live once in `.sumela-shared/rules/`;
  `scripts/sync-shared-rules.py` distributes + registers them (universal) into each
  install (run by setup / update; drift surfaced by `status.sh`).
- **OpenCode IDE support** — `.opencode/AGENTS.md.template` pointer; wired into
  `setup.sh` / `setup.ps1` (template list, IDE map, multiselect, `--ides`) and the
  README Supported-IDEs table, completing the IDE matrix the README already advertised.
- **One-step memory runtime** — `scripts/setup-memory.sh` / `.ps1`: opting into a
  memory plugin no longer leaves the developer to install Qdrant/Ollama/graphify by
  hand. It auto-installs the cheap/safe deps (pip) and CONFIRMS-and-runs the invasive
  steps (start Qdrant via Docker, pull the Ollama embedding model, install the graphify
  CLI), reuses anything already present, then creates the Qdrant collections + builds
  the initial graph. Idempotent; non-interactive mode prints every exact command
  instead of running it; `/initSumela` and `setup.sh`/`.ps1` invoke it after copying
  the plugins (skip with `SUMELA_SKIP_MEMORY_SETUP=1`, e.g. in CI / the smoke test).
  It is also the **add-a-plugin-later** path: since bootstrap copies all plugin
  files, `setup-memory.sh --plugins <name>` registers a not-yet-enabled plugin in
  `SKILL_REGISTRY.md` and brings its runtime up — no re-init needed. All script
  output is English (framework artifacts stay language-neutral); the `/initSumela`
  consent prompt is rendered in the developer's configured interaction language.
- **End-to-end smoke test** — `tests/smoke.sh` runs `setup.sh` against a throwaway
  copy and asserts the contract (AGENTS.md + every selected IDE pointer generated, a
  plugin registered exactly once, no unrendered placeholders, structure + reconcile
  pass) and that a second run is idempotent. Wired into the opt-in CI workflow; this
  is the first FUNCTIONAL test of the self-modifying setup pipeline (was parse-only).
- **Signal taxonomy expanded** (`self-improvement-curator`) — two new capture types:
  `resolution` (agent-originated: a bug/problem the agent fixes itself → capture the
  GENERALIZED class-level lesson, never the one-off instance) and `preference` (a
  proactive standing user instruction, distinct from a reactive `correction`). Wired
  in lockstep across the prompt, registries, schema, and queue README.
- **Pull-time code-graph refresh** — `post-merge`/`post-checkout` now also run
  `sumela_graph_sync`: when a pull/checkout brings CODE changes, it refreshes the
  local graphify graph in the background via `auto-update-memory.py --graph-only`
  (a new graph-only mode that writes ONLY the gitignored graph dir — no wiki sync,
  no `_LOG.md` append, so a pull never dirties the tree). Self-gating, non-blocking,
  opt-out with `SUMELA_DISABLE_GRAPH_SYNC=1`.
- **Pull-time Qdrant content refresh** — the pull hooks also keep the Qdrant semantic
  collections (whose embeddings would otherwise lag the git-current tracked files) in
  sync: `sumela_wiki_sync` re-ingests `wiki_pages` when a CURATED page changed
  (session-summaries + underscore-special files like `_LOG.md` excluded, so a
  union-merged log alone never triggers it; default on, opt-out
  `SUMELA_DISABLE_WIKI_SYNC=1`). `sumela_code_sync` keeps `code_chunks` honest: it
  PRUNES orphans for removed code files cheaply on every pull, but the heavy whole-tree
  re-embed is no longer all-or-nothing — when code_chunks is STALE
  (> `SUMELA_CODE_REINGEST_DAYS`, default 14) it PROMPTS for approval on an interactive
  pull (default No, 30s timeout) or prints a non-blocking notice otherwise;
  `SUMELA_PULL_CODE_REINGEST=1` forces it, `SUMELA_DISABLE_CODE_SYNC=1` turns it off.
- **Qdrant orphan pruning** — new `delete-from-qdrant.py` (delete points by a payload
  key). `wiki_sync`/`code_sync` call it for pages/files DELETED upstream, so a removed
  wiki page or source file stops surfacing in semantic search. `chat_history` is
  deliberately exempt — a removed session summary does not retract a past decision.
  All syncs remain background, best-effort, Qdrant-reachability-gated, and write only
  the Qdrant cache — never the tracked tree.
- **Richer memory-sync log** — the pull-time summary ingest now reports WHO (git
  author) and WHICH tasks (filename + `session_topics`) each arriving summary
  belongs to, inline (up to 10) and in `.sumela/.graph-sync.log`/`.memory-sync.log`.

### Fixed

- **Existing-project install completeness** — the README agent prompt now delegates
  the copy to the maintained `bootstrap.sh`/`.ps1` (no more hand-list drift; bootstrap
  now also copies `docs/second-brain/template/` and the new `.opencode/`), and
  `/initSumela` gained Step 3.6b (`.gitattributes` union-merge + `.gitignore` secret
  baseline) so both install paths reach full parity with `setup.sh`.
- **English-only framework artifacts (global-ready)** — removed hardcoded Turkish from
  the agent-control surface: the prompt's routing/trigger examples, skill trigger
  phrases + user-facing example prompts (`self-improvement-curator`, `using-second-brain`,
  `context-handoff`, `idea-explore`, `finishing-a-development-branch`), the plugin
  trigger lines, the `_SCHEMA.md` template (fully translated, section numbers + enums
  preserved), and the two ingest scripts' examples. Triggers are now English + "the
  equivalent in any language"; instructions that said "respond in Turkish" now say
  "in the configured interaction language". Setup-script output is English; the agent
  still renders all user-facing text in the developer's chosen language.

- **`status.sh` / `status.ps1` hook detection** now recognizes all three wiring forms
  the monorepo work introduced (root, subdir `<rel>/.sumela/git-hooks`, and the
  `.sumela-hooks` dispatcher — verifying this install is registered) instead of only
  the root form; the fix it suggests is rerunning setup (correct for every topology).
- **`setup.ps1` plugin registration is now idempotent** — guards on an existing
  `<name>` before appending, matching `setup.sh`; re-running with a plugin selected no
  longer duplicates its `<skill>` block in `SKILL_REGISTRY.md`.
- **Bootstrap scripts hardened** — `bootstrap.sh` uses `set -euo pipefail`, surfaces
  clone failures, fails loudly on the essential payload, and cleans up via `trap`;
  `bootstrap.ps1` reaches parity (copies all IDE templates + `.gitkeep` dirs, real
  error/next-step output) instead of being a minimal stub.
- **`.sumela/VERSION` bumped to 0.4.0** so `update.sh`'s version gate and `status.sh`
  reflect the post-0.3.0 core (it had stayed at 0.3.0 while features landed).

## [0.3.0] - 2026-06-01

### Added — team enablement

- **Shared session memory** — `session-ingest.py` is idempotent (deterministic point
  IDs, delete-by-session); `post-merge`/`post-checkout` git hooks re-ingest teammates'
  committed session summaries into each developer's local Qdrant on pull.
- **Team-safe wiki** — `_LOG.md` uses git `union` merge; the self-improvement queue is
  a directory (`_improvement-queue/`, one `IMP-YYYYMMDD-<short>.md` per signal, no
  shared counter); `active-project-context.md` per-developer "Active Work" convention.
- **`/evolve` governance** — `governance: solo|team` (AGENTS.md §8). In team mode,
  rule/skill/schema changes route through a PR (`proposed` status + reconcile) and a
  `.github/CODEOWNERS` block guards the agent-control surface.
- **Enforcement** — `validate-structure.sh` runs via a `.sumela/git-hooks/pre-commit`
  hook (scoped, bypassable) and an opt-in GitHub Actions workflow (`setup.sh --ci`).
- **Per-developer config** — gitignored `.sumela/local.md` overrides only
  `interaction_language`; code naming/documentation stay team-wide.
- **Upgrade path** — `.sumela/VERSION` + `scripts/update.sh` / `update.ps1` refresh the
  framework CORE (prompt, skills, scripts, hooks, universal rules, schema, templates)
  without touching the project OVERLAY (AGENTS.md, stack rules, wiki, registries,
  governance/CI choices), with per-file diff + consent.
- **IDE mirror sync** — `scripts/sync-mirrors.sh` regenerates verbatim IDE mirrors
  from `sumela-prompt.md`; drift is checked by pre-commit + CI.

### Changed

- `core.hooksPath` is wired for every git repo (memory hooks self-gate); the CI
  workflow is opt-in (not auto-imposed).
- Reconciled the language protocol: project code follows the configured
  naming/documentation languages; only framework artifacts + commit messages stay English.

## [0.2.0] - 2026-05-22

### Added
- `init-sumela` skill: `/initSumela` command for automatic brownfield adoption
  - Auto-detects tech stack from manifest files (csproj, package.json, go.mod, Cargo.toml, etc.)
  - Identifies architecture pattern from directory structure (Clean Arch, MVC, microservices, monorepo, etc.)
  - Detects code conventions from existing source files (naming, error handling, validation, testing)
  - Generates AGENTS.md, RULE_REGISTRY.md, rules, wiki pages, and IDE pointers in one pass
  - Interactive confirmation before writing any files
- **Proactive Qdrant session context (STEP 3c)**: Agent silently queries Qdrant before starting non-trivial tasks
  - Checks past sessions for relevant decisions, lessons, and context
  - 5 scenarios: task start, entity encounter, architecture decision, debugging, file history
  - Mirrors Graphify's proactive impact analysis pattern

### Fixed
- Subagent-driven-development: added independent review option (4th choice after task completion)
- Graphify plugin: corrected installation to `uv tool install graphifyy` (PyPI, not npm)
- Graphify plugin: added "No API Key Required for Queries" clarification
- **Proactive impact analysis (STEP 3b)**: Agent now queries graphify before code changes to detect affected dependents

## [0.1.0] - 2026-05-22

### Added
- 27 universal agent skills (brainstorming, planning, TDD, debugging, code review, shipping, etc.)
- 7 universal rules + stack-specific rule templates (empty + best-practice variants)
- Second-brain wiki template with Karpathy LLM Wiki pattern (raw_sources → artifacts → wiki)
- Memory plugins: Qdrant session memory (Tier-1), Graphify code graph (Tier-2)
- Setup scripts: setup.sh (Bash), setup.ps1 (PowerShell) with interactive and non-interactive modes
- Validation script: validate-structure.sh
- IDE pointer templates: Claude Code, Cursor, Cline, Kilo Code, Trae
- ADOPTION_GUIDE with greenfield, brownfield, and team onboarding modes
- Self-improvement loop: `/evolve` command for capturing corrections and friction signals
- Context Manifest protocol for session-start transparency
- Phase-to-rule matrix for automatic rule loading based on active phase and stack scope
