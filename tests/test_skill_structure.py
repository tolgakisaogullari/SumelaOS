#!/usr/bin/env python3
"""Skill structure guards, measured the way Anthropic's own guidance measures.

Replaces an earlier `test_skill_word_budget.py` that counted WORDS against a 500-word
limit. That was the wrong unit and a far stricter number than the official guidance,
which says:

    "Keep SKILL.md body under 500 lines for optimal performance."
    "Keep references one level deep from SKILL.md."
    "For reference files longer than 100 lines, include a table of contents."
      — https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

Under the wrong unit, 19 of 22 skills looked over budget. Under the real one, exactly
one is. The false pressure was not harmless: chasing it produced two rule violations in
a single session — common-path content moved into sibling files so the counter would
drop (a "reduction" that relocated tokens instead of removing them), and then a
re-baseline justified with "only the measurement changed" when the skill had in fact
grown. Both were caught by review, not by the guard. A metric that measures the wrong
thing does not merely fail to help; it actively pushes toward gaming.

What is actually checked here:

  1. SKILL.md body <= 500 lines. Anything over is pinned at its current size and may
     only shrink — new work does not get to make a known-oversized file worse.

  2. Every sibling .md a skill directory contains is named DIRECTLY in SKILL.md.
     This is the one that bites: Claude may read a file only partially (a `head -100`
     preview) when it arrives there through another referenced file, so a rule buried
     in a second-level file can silently not apply. One level keeps files read whole.

  3. Reference files over 100 lines carry a table of contents, so a partial read still
     shows the full scope of what the file covers.

Prompt caching does not change any of this. Cached content still occupies the context
window and still counts as input tokens (total = cache_read + cache_creation + input);
caching makes re-reading CHEAPER, not SMALLER.

Run directly:

    python3 tests/test_skill_structure.py

Exits non-zero on the first failed assertion. No pytest / third-party deps.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SKILLS = REPO / ".sumela/skills"
PLUGINS = REPO / ".sumela/memory-plugins"

# Official guidance.
MAX_LINES = 500
TOC_THRESHOLD = 100

# Skills already over the line limit when this guard landed. RATCHET ONLY: lower a
# number when the file shrinks, never raise it. Each entry names what should move out.
CEILINGS = {
    # Interactive install walkthrough. The per-stack and per-domain branches, the
    # brownfield merge and the final report template are all conditional paths that
    # belong in sibling files reached directly from SKILL.md.
    "init-sumela": 602,
}

# A line count alone records reductions that never happened: moving 150 lines into a
# sibling, or reflowing hard-wrapped prose into long lines, both "shrink" SKILL.md
# while a consumer loads the same content or more. VOLUME is the bound that survives
# both — non-blank characters across the whole skill directory. Ratchet-only, same as
# CEILINGS. A number here going DOWN is a real reduction; a line count going down is
# not necessarily one.
VOLUME = {
    # Measured, not guessed. Lower each as the skill genuinely shrinks.
    "init-sumela": 38440,
    "requesting-code-review": 64446,
}


def directory_volume(skill_dir):
    total = 0
    for f in sorted(skill_dir.rglob("*")):
        if f.is_file() and f.suffix in {".md", ".sh", ".cmd", ".py", ".dot"}:
            total += sum(len(l.strip()) for l in f.read_text(encoding="utf-8").splitlines())
    return total

# Files a skill directory holds that SKILL.md is not expected to name: payloads that
# are dispatched to a subagent rather than read by the parent, and READMEs.
# Nothing is exempt by filename inside a SKILL directory — renaming a reference file
# to README.md used to dodge both loops. A memory PLUGIN's README is different: it is
# the plugin's user-facing documentation, not a file the skill body directs Claude to.
def _exempt_from_reference_check(skill_md, sib):
    return sib.name == "README.md" and "memory-plugins" in skill_md.as_posix()


PAYLOAD_GLOBS = ("*.md", "*.sh", "*.cmd", "*.py", "*.dot")

# A file that SKILL_REGISTRY.md registers with its own <path> is a skill in its own
# right, addressed by the registry rather than by the directory it happens to sit in.
REGISTERED = set()
_reg = REPO / ".sumela/SKILL_REGISTRY.md"
if _reg.is_file():
    import re as _re

    for _m in _re.finditer(r"<path>([^<]+)</path>", _reg.read_text(encoding="utf-8")):
        REGISTERED.add((REPO / _m.group(1).strip()).resolve())

_CORPUS = None


def _repo_corpus():
    """Every text file that could name a payload. A utility script is legitimately
    called from a git hook or from scripts/, not only from its own skill."""
    global _CORPUS
    if _CORPUS is None:
        parts = []
        for ext in ("*.md", "*.sh", "*.ps1", "*.py", "*.cmd", "*.template", "*.yml"):
            for f in REPO.rglob(ext):
                if ".git/" in f.as_posix() or "node_modules" in f.as_posix():
                    continue
                try:
                    parts.append(f.read_text(encoding="utf-8", errors="ignore"))
                except OSError:
                    pass
        _CORPUS = "\n".join(parts)
    return _CORPUS


FAILURES = []


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}" + (f"\n         {detail}" if detail else ""))
        FAILURES.append(label)


def rel(p):
    return str(p.relative_to(REPO))


def references(body, filename):
    """Is `filename` REFERENCED here, or merely mentioned?

    A bare substring test passes on a collision (`report.md` inside
    `review-report.md`) and on a name sitting in an HTML comment that tells the
    reader NOT to open it. Require a whole-token match, outside comments.
    """
    stripped = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    return re.search(
        r"(^|[\s`\[(/])" + re.escape(filename) + r"([\s`\]),.:;]|$)", stripped, re.M
    ) is not None


skill_files = sorted(SKILLS.glob("*/SKILL.md")) + sorted(PLUGINS.glob("*/SKILL.md"))

# --------------------------------------------------------------------------
print(f"SKILL.md body <= {MAX_LINES} lines")
for skill_md in skill_files:
    name = skill_md.parent.name
    raw = skill_md.read_text(encoding="utf-8")
    body = re.sub(r"\A---.*?^---\s*$", "", raw, count=1, flags=re.S | re.M)
    lines = len(body.strip().splitlines())
    limit = CEILINGS.get(name, MAX_LINES)
    label = f"{name}: {lines} lines" + (f" (pinned at {limit})" if name in CEILINGS else "")
    check(label, lines <= limit, f"limit {limit}; split conditional sections into siblings named from SKILL.md")
    if name in CEILINGS and lines < limit:
        check(
            f"{name}: ceiling is stale ({lines} < {limit})",
            False,
            f"the file shrank — lower the ceiling to {lines} so the ratchet holds",
        )

# --------------------------------------------------------------------------
print("\nskill directory volume (catches relocation and reflow, which lines do not)")
for skill_md in skill_files:
    name = skill_md.parent.name
    if name not in VOLUME:
        continue
    vol = directory_volume(skill_md.parent)
    check(f"{name}: {vol} chars (pinned at {VOLUME[name]})", vol <= VOLUME[name],
          "moving content to a sibling or reflowing prose does not reduce this")
    if vol < VOLUME[name] - 2000:
        check(f"{name}: volume pin is stale ({vol} << {VOLUME[name]})", False,
              f"lower it to {vol} so the ratchet holds")

# --------------------------------------------------------------------------
print("\nreferences are one level deep from SKILL.md")
for skill_md in skill_files:
    body = skill_md.read_text(encoding="utf-8")
    for sib in sorted(skill_md.parent.rglob("*.md")):
        if sib == skill_md or _exempt_from_reference_check(skill_md, sib):
            continue
        if sib.resolve() in REGISTERED:
            continue  # its own registered skill, reached via the registry
        check(
            f"{skill_md.parent.name}/{sib.name} named directly in SKILL.md",
            references(body, sib.name),
            "reachable only through another referenced file — Claude may preview such "
            "a file with `head -100` instead of reading it, so rules in it can silently "
            "not apply. Name it from SKILL.md.",
        )

# --------------------------------------------------------------------------
# A utility script is EXECUTED, not read into context, so the partial-read hazard does
# not apply and it need not be named in SKILL.md. It must still be reachable from
# SOMEWHERE in the skill, or it is dead weight shipped to every consumer.
print("\nexecutable payloads are reachable from somewhere in the skill")
for skill_md in skill_files:
    d = skill_md.parent
    corpus = _repo_corpus()
    for g in ("*.sh", "*.cmd", "*.py", "*.dot"):
        for payload in sorted(d.rglob(g)):
            check(
                f"{d.name}/{payload.name} is referenced by some file in the skill",
                payload.name in corpus,
                "no file in the skill names it — an orphan shipped to every install",
            )

# --------------------------------------------------------------------------
print(f"\nreference files over {TOC_THRESHOLD} lines carry a table of contents")
_toc_seen = 0
for skill_md in skill_files:
    for sib in sorted(skill_md.parent.rglob("*.md")):
        if sib == skill_md:
            continue
        text = sib.read_text(encoding="utf-8")
        n = len(text.splitlines())
        if n <= TOC_THRESHOLD:
            continue
        _toc_seen += 1
        # Must be a real heading, near the top: a TOC below the fold is invisible to
        # the partial read it exists to serve, and a fenced block that merely contains
        # the words is not a TOC at all.
        head = "\n".join(text.splitlines()[:20])
        head = re.sub(r"^---.*?^---", "", head, flags=re.S | re.M)
        has_toc = re.search(r"(?mi)^#{1,3}\s+(contents|içindekiler)\b", head) is not None
        check(
            f"{skill_md.parent.name}/{sib.name} ({n} lines) has a table of contents",
            has_toc,
            "a partial read of a long reference file must still show its full scope",
        )

check("the TOC section examined at least one file", _toc_seen > 0,
      "no reference file is over 100 lines — the section asserted nothing")

print()
if FAILURES:
    print(f"FAILED: {len(FAILURES)} check(s)")
    for f in FAILURES:
        print(f"  - {f}")
    sys.exit(1)
print("All skill structure checks pass.")
