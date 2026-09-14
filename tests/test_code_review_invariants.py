#!/usr/bin/env python3
"""Dependency-free structural guards for the code-review skill pair.

These pin the contracts of `requesting-code-review` / `receiving-code-review` that
are invisible to every other check in the repo — `validate-structure.sh` only asserts
the skill DIRECTORIES exist, and `reconcile-registry.py` only compares frontmatter
descriptions. Everything below is a rule that was once wrong in this repo, or that
silently rots the moment someone edits one of the six files by hand.

Contracts pinned here:

  * DIFF IS SCOPE, NOT EVIDENCE — no lane may carry the old "Review ONLY the provided
    {CODE_DIFF}" restriction. That bullet made repo reading forbidden, which (a) left
    lanes unable to check callers/guards/tests outside the ±3 lines of hunk context
    and (b) directly contradicted the Integration lane's own instruction to run
    graphify `--impact` on every changed symbol.

  * FALSE-POSITIVE CONTROL — every lane must sanction a zero-findings result and must
    gate Critical/Important behind a cited failure chain. Without the first, a lane
    with nothing to report invents something; without the second, "it looks racy"
    reaches the author as a blocker.

  * ANCHORING — every lane must treat {DESCRIPTION}/{WHAT_WAS_IMPLEMENTED} as the
    author's CLAIMS. The author of that text also wrote the code under review.

  * ONE SEVERITY MODEL — the qualifier wording ("what makes a finding Critical") must
    live in exactly ONE file. It used to sit in two tables whose columns disagreed,
    plus a third prose copy in the legacy template that had already drifted.

  * NO STALE PLUGIN NAMESPACE — `superpowers:<skill>` is an upstream plugin prefix
    SumelaOS does not use; SKILL_REGISTRY addresses every skill by bare name.

  * THE H2 FIX MUST REACH UPGRADED INSTALLS — `.sumela/rules/*.md.template` is not
    under any CORE_DIRS entry (CORE_DIRS has `.sumela/rules/templates`, one level
    down), so it propagates on upgrade ONLY if named in CORE_FILES explicitly.

  * THE REVIEW ARTIFACT IS PER-DEVELOPER — `.sumela/reviews/` must be gitignored via
    the single source list (so it reaches fresh installs AND upgrades, both shells).

Run directly:

    python3 tests/test_code_review_invariants.py

Exits non-zero on the first failed assertion. No pytest / third-party deps.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SKILLS = REPO / ".sumela/skills"
REQ = SKILLS / "requesting-code-review"
RECV = SKILLS / "receiving-code-review"

LANES = [
    REQ / "reviewer-correctness-security.md",
    REQ / "reviewer-design-contracts.md",
    REQ / "reviewer-integration-ops.md",
]

FAILURES = []


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}" + (f"\n         {detail}" if detail else ""))
        FAILURES.append(label)


def read(path):
    return path.read_text(encoding="utf-8")


def rel(path):
    return str(path.relative_to(REPO))


# --------------------------------------------------------------------------
# 1. Diff is scope, not evidence
# --------------------------------------------------------------------------
print("diff is scope, not evidence")
for lane in LANES:
    body = read(lane)
    check(
        f"{rel(lane)}: no diff-only restriction",
        "Review ONLY the provided" not in body,
        "the 'Review ONLY the provided {CODE_DIFF}' bullet forbids the repo reading "
        "that C1 requires and that the Integration lane's graphify step depends on",
    )
    check(
        f"{rel(lane)}: states SCOPE vs EVIDENCE",
        "SCOPE vs EVIDENCE" in body,
    )
    check(
        f"{rel(lane)}: bounds the reading budget",
        "READING BUDGET" in body,
        "unbounded 'read the repo freely' lets one `git log -p` evict the diff the "
        "lane is accountable for",
    )

# --------------------------------------------------------------------------
# 2. False-positive control
# --------------------------------------------------------------------------
print("false-positive control")
for lane in LANES:
    body = read(lane)
    check(
        f"{rel(lane)}: zero findings sanctioned",
        "ZERO FINDINGS IS A VALID" in body,
    )
    check(
        f"{rel(lane)}: failure-chain gate present",
        "FAILURE-CHAIN GATE" in body,
    )
    check(
        f"{rel(lane)}: coverage line required",
        "COVERAGE LINE" in body,
        "without it, a skimmed lane and a thorough lane produce the same empty report",
    )

# --------------------------------------------------------------------------
# 2b. The shared execution-rules block must not drift between lanes
# --------------------------------------------------------------------------
# Three byte-identical copies live in three files. Nothing else notices when one
# copy is edited and the others are not, and a lane running a stale copy of the
# false-positive controls fails silently — it still emits a well-formed report.
# The copies are NOT extracted to one file on purpose: this is common-path content
# every lane needs, so per the repo's own rule the guard is the fix, not the split.
print("shared execution-rules block")
import hashlib


def shared_block(path):
    body = read(path)
    start = body.index("- SCOPE vs EVIDENCE")
    # Everything from here to SPECIFIC REFERENCES is shared; what follows it
    # (SEVERITY STRICTNESS and any lane extras) is deliberate per-lane calibration.
    end = body.index("- SPECIFIC REFERENCES", start)
    return body[start:end]


digests = {}
for lane in LANES:
    try:
        digests[rel(lane)] = hashlib.md5(shared_block(lane).encode()).hexdigest()
    except ValueError:
        digests[rel(lane)] = "MARKERS-MISSING"
check(
    "shared execution-rules block is byte-identical across all three lanes",
    len(set(digests.values())) == 1 and "MARKERS-MISSING" not in digests.values(),
    "; ".join(f"{k}={v[:12]}" for k, v in digests.items()),
)

# --------------------------------------------------------------------------
# 3. Anchoring — the author's narrative is a claim
# --------------------------------------------------------------------------
print("anchoring control")
for lane in LANES:
    body = read(lane)
    check(
        f"{rel(lane)}: author narrative marked as claims",
        "AUTHOR'S CLAIMS" in body,
    )

print("calibration counterweights")
for lane in LANES:
    body = read(lane)
    check(
        f"{rel(lane)}: input/state link is DEFINED, not carved out",
        "WHAT SATISFIES THE INPUT/STATE LINK" in body,
        "without it the plausibility list contradicts the failure-chain gate, which "
        "names 'in some configuration' as a drop trigger — and a race IS one",
    )
    check(
        f"{rel(lane)}: explicit not-a-finding list",
        "NOT A FINDING" in body,
    )
    check(
        f"{rel(lane)}: test failures default to UNATTRIBUTED",
        "UNATTRIBUTED" in body,
        "a confident 'pre-existing' with no trace excuses a real regression in "
        "writing, which is strictly worse than saying nothing",
    )

# --------------------------------------------------------------------------
# 4. Exactly one severity model
# --------------------------------------------------------------------------
print("one severity model")
# Exactly one severity TABLE may exist. A lane's own one-line `SEVERITY STRICTNESS`
# calibration is deliberately grandfathered — it tunes that lane's threshold, it does
# not redefine the model — but a second TABLE is the drift this check exists to stop.
tables = sorted(
    p for p in (REPO / ".sumela").rglob("*.md") if "| Critical |" in read(p)
)
check(
    "severity table exists exactly once",
    tables == [RECV / "SKILL.md"],
    "expected only .sumela/skills/receiving-code-review/SKILL.md; got "
    + (", ".join(rel(h) for h in tables) if tables else "nothing"),
)
QUALIFIER = "exploitable token-lifecycle gap"
recv_body = read(RECV / "SKILL.md")
check(
    "canonical table keeps the 'what qualifies' column",
    "What qualifies" in recv_body,
    "the two source tables had their columns SWAPPED relative to their headers; a "
    "merge by column name drops every qualifier and the loss is silent",
)
for phrase in [
    "silent breaking contract change",
    "meaningful test gap",
    "Optional; author may ignore at their discretion",
    "unless technically disproven",
]:
    check(
        f"canonical table preserves: {phrase!r}",
        phrase in recv_body,
    )
check(
    "receiving-code-review owns the model (no back-pointer loop)",
    "severity model used by `requesting-code-review`" not in recv_body,
    "receiving pointed at requesting while requesting pointed back at receiving",
)
check(
    "requesting-code-review does not restate the model",
    QUALIFIER not in read(REQ / "SKILL.md"),
)

# --------------------------------------------------------------------------
# 5. Large diffs are sliced, never refused
# --------------------------------------------------------------------------
print("large diffs are sliced, not refused")
req_body = read(REQ / "SKILL.md")
check(
    "no 'stop and ask the author to split' gate",
    "ask the author to split the change" not in req_body,
    "refusing a large diff produces ZERO review; the author is the agent itself, so "
    "the rule can only be deadlocked or rationalized around",
)
check(
    "slicing instruction present",
    "SLICE" in req_body,
)
check(
    "line count is mechanical and printed",
    "--numstat" in req_body,
    "a self-scored 'meaningful logic lines' number is graded by the agent that "
    "benefits from a smaller one",
)
check(
    "tier may escalate but never de-escalate",
    re.search(r"never de-?escalate", req_body, re.IGNORECASE) is not None,
)

# --------------------------------------------------------------------------
# 6. Review artifact
# --------------------------------------------------------------------------
print("review artifact")
# The report format is a contract between FOUR files: requesting-code-review writes
# it and reads it back for {PRIOR_ROUNDS}, receiving-code-review writes the outcome
# ledger into it, and the two ship/finish gates validate it. It is defined once.
report_spec = REQ / "review-report.md"
check(
    "canonical report spec exists",
    report_spec.is_file(),
)
spec_body = read(report_spec) if report_spec.is_file() else ""
check(
    "artifact keyed by a TREE hash, not a diff stream or a self-matching literal",
    "reviewed_state" in spec_body and "write-tree" in spec_body,
    "a literal 'worktree' marker matches itself forever (gate always passes); a DIFF "
    "hash fails the other way — `git diff --staged` is empty after the commit, so a "
    "pre-commit report could never match at ship time. A tree hash survives both.",
)
check(
    "gate takes the NEWEST report, not any that passes",
    "NEWEST" in spec_body,
    "several retained reports can share a reviewed_state while disagreeing on the "
    "verdict; scanning for one that passes merges an outstanding Critical",
)
check(
    "artifact survives `git worktree remove`",
    "git-common-dir" in spec_body,
    ".sumela/reviews/ is untracked, so it is deleted with the worktree — taking the "
    "evidence shipping-and-launch is supposed to gate on",
)
check(
    "report is refused when .sumela/reviews/ is not gitignored",
    "check-ignore" in spec_body,
    "update.sh's gitignore reconcile is consent-gated; a user who declined it would "
    "otherwise get secret-quoting reports written into a TRACKED directory",
)
# No second copy of the frontmatter field list anywhere.
# `.sumela/reviews/` holds the reports themselves — they CONTAIN the frontmatter,
# they do not define it. Excluded, or the guard fires on its own output.
restaters = sorted(
    p
    for p in (REPO / ".sumela").rglob("*.md")
    if "reviewed_state:" in read(p)
    and p != report_spec
    and ".sumela/reviews/" not in p.as_posix()
)
check(
    "report frontmatter defined in exactly one file",
    not restaters,
    "also restated in: " + ", ".join(rel(r) for r in restaters),
)
gitignore_list = read(REPO / "scripts/lib/sumela-gitignore.list")
check(
    ".sumela/reviews/ in the single-source gitignore list",
    ".sumela/reviews/" in gitignore_list,
    "only this list reaches fresh installs (setup.sh/setup.ps1) AND upgrades "
    "(update.sh/update.ps1)",
)
check(
    ".sumela/reviews/ in the framework repo's own .gitignore",
    ".sumela/reviews/" in read(REPO / ".gitignore"),
)

# --------------------------------------------------------------------------
# 7. No stale plugin namespace
# --------------------------------------------------------------------------
print("no stale plugin namespace")
stale = []
for path in list((REPO / ".sumela").rglob("*.md")) + list(
    (REPO / ".sumela").rglob("*.template")
):
    for n, line in enumerate(read(path).splitlines(), 1):
        if "superpowers:" in line:
            stale.append(f"{rel(path)}:{n}")
check(
    "no `superpowers:` prefix survives under .sumela/",
    not stale,
    "still present at: " + ", ".join(stale),
)
check(
    "the using-superpowers skill still exists (strip must not have eaten it)",
    (SKILLS / "using-superpowers/SKILL.md").is_file(),
)

# --------------------------------------------------------------------------
# 8. The rules template must propagate on upgrade
# --------------------------------------------------------------------------
print("upgrade propagation")
TEMPLATE = ".sumela/rules/operational_excellence_maintenance.md.template"
for script in ["scripts/update.sh", "scripts/update.ps1"]:
    check(
        f"{script} lists the rules template in CORE_FILES",
        TEMPLATE in read(REPO / script),
        "CORE_DIRS covers .sumela/rules/templates/, one level BELOW this file, so an "
        "edit here never reaches an existing install unless named explicitly",
    )

print()
if FAILURES:
    print(f"FAILED: {len(FAILURES)} invariant(s) broken")
    for f in FAILURES:
        print(f"  - {f}")
    sys.exit(1)
print("All code-review invariants hold.")
