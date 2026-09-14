#!/usr/bin/env python3
"""Content guards for the `secure-coding-standard` skill.

`test_skill_structure.py` checks a skill's SHAPE (line budget, one-level references,
TOC). Shape says nothing about whether the security rules inside are correct — and a
security skill that is well-shaped and wrong is worse than no skill, because the agent
follows it confidently.

Three rules in the v0.16.0 body actively produced vulnerable code:

  1. "MUST validate strict MIME-types (not just extensions)" — the MIME type in a
     multipart upload is an attacker-supplied header. An agent reading this validates
     `file.mimetype` and ships a bypassable check. The real control is magic-byte
     sniffing against an allowlist.
  2. "ALWAYS sanitize file paths and names" — stripping `../` is the textbook BROKEN
     fix for traversal (`....//` survives it). The control is resolve-then-verify
     containment under a base directory.
  3. JWT validation listed issuer/audience/expiry/signing key but not the ALGORITHM,
     leaving `alg: none` and HS/RS confusion — both full auth bypasses — unaddressed.

Two workflow defects made the checklist unfalsifiable: no way to mark an item N/A with
a reason (so an agent on a CLI project either lies about CSP or stalls), and no evidence
requirement behind a tick (so the gate self-certifies while `reviewer-correctness-
security.md` demands `File:line` for every finding on the same change).

This file pins the fixes so they cannot silently regress. Run directly:

    python3 tests/test_secure_coding_standard.py

Exits non-zero on the first failed assertion. No pytest / third-party deps.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SKILL_DIR = REPO / ".sumela/skills/secure-coding-standard"
SKILL = SKILL_DIR / "SKILL.md"
PLAYBOOK = SKILL_DIR / "owasp-playbook.md"
AGENT_THREATS = SKILL_DIR / "agent-specific-threats.md"

FAILURES = []


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}" + (f"\n         {detail}" if detail else ""))
        FAILURES.append(label)


def read(p):
    return p.read_text(encoding="utf-8") if p.is_file() else ""


skill = read(SKILL)
skill_l = skill.lower()
playbook = read(PLAYBOOK)
agent_threats = read(AGENT_THREATS)
corpus_l = (skill + playbook + agent_threats).lower()

# --------------------------------------------------------------------------
print("the three rules that produced vulnerable code are corrected")

check(
    "upload validation does not rest on the client-declared MIME type",
    "not just extensions" not in skill_l,
    "'validate strict MIME-types (not just extensions)' sends the agent to "
    "`file.mimetype` — an attacker-controlled multipart header.",
)
check(
    "upload rule in SKILL.md types from content and says the declared type proves nothing",
    ("magic byte" in skill_l or "magic-byte" in skill_l) and "attacker-supplied" in skill_l,
    "asserted against SKILL.md, not the corpus: the playbook is read only for REACHABLE "
    "categories, so a rule that lives only there does not reach the agent that skips Step 2",
)
check(
    "path traversal is containment, not sanitisation",
    "sanitize file path" not in skill_l and "sanitise file path" not in skill_l,
    "stripping `../` is the broken fix; say resolve-then-verify-containment",
)
check(
    "path rule in SKILL.md is resolve-then-verify-containment",
    ("realpath" in skill_l or "resolve" in skill_l) and "containment" in skill_l,
)
check(
    "the playbook states the containment snippet's LIMITS instead of over-claiming",
    "toctou" in playbook.lower() and "check time" in playbook.lower(),
    "the check is racy in exactly the upload directory its own comment names; a security "
    "reference that promises a guarantee it cannot make is the failure mode this file exists to stop",
)
check(
    "JWT rule in SKILL.md pins the signing algorithm",
    "algorithm" in skill_l
    and ("alg: none" in skill_l or "alg=none" in skill_l or "algorithm confusion" in skill_l),
    "issuer/audience/expiry without an algorithm allowlist leaves `alg: none` "
    "and HS/RS confusion open — both are full auth bypasses",
)

# --------------------------------------------------------------------------
print("\nthe checklist can be answered honestly and cannot be self-certified")

check(
    "checklist items can be marked N/A with a stated reason",
    "n/a" in skill_l,
    "a checklist with no legitimate N/A trains the agent to tick falsely, and "
    "that habit carries to the items that DO apply",
)
check(
    "a ticked item requires evidence (file:line or command output)",
    "evidence" in skill_l,
    "your own rule: gate on the artifact, not on exit 0",
)
check(
    "the surface triage exists and is a real gate",
    "scope the surface" in skill_l and skill_l.count("reachable") >= 3
    and "print the verdict" in skill_l,
    "a bare 'reachab' substring was already true in the pre-change file — it asserted nothing. "
    "The triage must exist AND leave an artifact, or it is a self-granted skip.",
)
check(
    "an N/A in the triage costs a stated reason",
    "n/a with no reason" in skill_l or "why nothing in this change reaches it" in skill_l,
    "unjustified N/A is how the whole gate gets marked not-applicable",
)
check(
    "there is an honest third form for a real gap",
    "not done" in skill_l,
    "with only [x] and [~], an item the agent skipped has exactly one legal output: N/A. "
    "The form rule itself manufactures the laundered skip.",
)

# --------------------------------------------------------------------------
print("\nthe confirmation gate covers control WEAKENING, not only control addition")

for term, why in [
    ("weaken", "removing/loosening an existing control is the most common agent security failure"),
    ("verify=false", "disabled TLS verification is the canonical 'temporary' weakening"),
]:
    check(f"confirmation gate names: {term}", term in skill_l, why)

# --------------------------------------------------------------------------
print("\ncross-skill contracts hold (severity owner, mandate authority, section names)")

check(
    "severity model is attributed to the skill that actually owns it",
    "receiving-code-review" in skill_l and skill_l.count("recommendations-fyi") <= 1,
    "requesting-code-review/SKILL.md itself defers: canonical in receiving-code-review -> "
    "<severity_model>. Pointing at the deferring skill sends the agent to a pointer, not a model.",
)
check(
    "SKILL.md does not tell the caller to fill {SECURITY_MANDATE}",
    "as `{security_mandate}`" not in skill_l,
    "requesting-code-review Step 4 is the SINGLE filling authority and forbids callers from "
    "filling fields — an instruction to fill it collides with a MUST in the receiving skill",
)
check(
    "the written threat-model block uses the section names the receiving skills define",
    "Security Considerations" in skill and "Security Constraints" in skill,
    "brainstorming's spec section is `Security Considerations`; writing-plans' plan header is "
    "`Security Constraints`. Inventing one name for both writes into a section nobody checks.",
)
check(
    "the planless phases have a destination for the block",
    "commit body" in skill_l,
    "the skill activates in executing-plans and TDD, where there is no spec and no plan to write into",
)

# --------------------------------------------------------------------------
print("\nproject-specific leakage is out of the language-agnostic core")

for leak in ["fcm token", "smtp credential", "report description", "raw search query"]:
    check(f"no project-specific artifact in SKILL.md: {leak}", leak not in skill_l,
          "an enumerated app-specific list reads as exhaustive — the agent infers "
          "'not on the list, therefore loggable'")

# --------------------------------------------------------------------------
print("\nsibling references exist and are named directly from SKILL.md")

check("owasp-playbook.md exists", PLAYBOOK.is_file())
check("agent-specific-threats.md exists", AGENT_THREATS.is_file())
check("owasp-playbook.md is named in SKILL.md", "owasp-playbook.md" in skill)
check("agent-specific-threats.md is named in SKILL.md", "agent-specific-threats.md" in skill)
check(
    "the files are substantive, not a keyword stub",
    len(skill.splitlines()) > 80
    and len(playbook.splitlines()) > 100
    and len(agent_threats.splitlines()) > 60,
    "every check here is a substring test; without a floor, a 9-line file that lists the "
    "keywords and says 'security is the reviewer's job' passes the whole suite",
)

# --------------------------------------------------------------------------
print("\nOWASP categories that were entirely absent are now covered")

REQUIRED = {
    "mass assignment": ["mass assignment", "over-posting"],
    "insecure deserialization": ["deserializ", "pickle"],
    "SSRF metadata / redirect bypass": ["169.254.169.254", "link-local"],
    "open redirect": ["open redirect"],
    "XXE": ["xxe", "external entit"],
    "ReDoS": ["redos", "catastrophic backtracking"],
    "zip-slip / decompression bomb": ["zip-slip", "zip slip", "decompression bomb"],
    "session fixation": ["session fixation", "rotate the session"],
    "multi-tenant scoping": ["tenant"],
    "CSPRNG for tokens": ["csprng", "math.random"],
    "timing-safe comparison": ["timing-safe", "constant-time"],
    "A09 security logging": ["security logging", "audit log"],
    "account enumeration": ["enumeration"],
    "password reset token hygiene": ["single-use", "one-time"],
    "AEAD / nonce reuse": ["aead", "nonce"],
    "NoSQL operator injection": ["$ne", "operator injection"],
    "CSRF (playbook section, not only a mention)": ["synchroniser token", "synchronizer token"],
}
for label, needles in REQUIRED.items():
    check(f"covered: {label}", any(n in corpus_l for n in needles))

# The open-redirect CONTROL shipped in the first draft was defeated by `/\evil.com` — the exact
# string the line above it named as the bypass. Pin the corrected control's distinguishing parts.
check(
    "the open-redirect control rejects the backslash and scheme-only forms",
    "/\\evil.com" in playbook and "https:/evil.com" in playbook,
    "requiring only 'empty host + one leading slash' passes both; an agent following the "
    "fix ships the vulnerability the entry is about",
)

# --------------------------------------------------------------------------
print("\nthreats specific to LLM-authored code are addressed")

for label, needles in {
    "hallucinated dependencies (slopsquatting)": ["slopsquat", "hallucinat"],
    "prompt injection in features the agent builds": ["prompt injection"],
    "secrets leaking into agent-written specs/plans": [".sumela/reviews/", "plan file"],
}.items():
    check(f"covered: {label}", any(n in agent_threats.lower() for n in needles))

print()
if FAILURES:
    print(f"FAILED: {len(FAILURES)} check(s)")
    for f in FAILURES:
        print(f"  - {f}")
    sys.exit(1)
print("All secure-coding-standard content checks pass.")
