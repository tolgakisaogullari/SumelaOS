#!/usr/bin/env python3
"""Dependency-free parity test for the `## Decisions Made` heading contract.

That heading is load-bearing for TWO consumers and is written by a third:
  - session-ingest.py `extract_decisions()` parses it into the Qdrant `decisions` payload,
  - context-handoff `<decision_triage>` reads it to route each decision to a durable home,
  - _SCHEMA.md's Session Summary Page Template is what agents copy when writing a summary.

If the template's heading drifts from what the parser accepts, every session summary
extracts ZERO decisions — silently, with a SUCCESS report — and the cumulative decision
trail this repo depends on quietly stops accumulating. Nothing else catches that. Run:

    python3 tests/test_decision_heading_parity.py

Exits non-zero on the first failed assertion. No pytest / third-party deps.
"""
import importlib.util
import re
import sys
import types
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
INGEST = REPO / ".sumela/memory-plugins/qdrant-session-memory/scripts/session-ingest.py"
SCHEMA = REPO / "docs/second-brain/template/wiki/_SCHEMA.md"
SKILL = REPO / ".sumela/skills/context-handoff/SKILL.md"

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def install_dep_stubs():
    """Seed sys.modules so session-ingest.py's module-level `import requests` /
    `from qdrant_client import ...` resolve without the real packages.

    Those imports call sys.exit(1) on ImportError, so without stubs this test exits 1
    wherever the pip deps are absent — including CI, which runs smoke.sh with no pip
    install. This test checks a text contract and never touches the network, so the
    stubs stay empty on purpose. Same pattern as tests/test_ingest_delete_guard.py.
    """
    sys.modules.setdefault("requests", types.ModuleType("requests"))
    qc = sys.modules.setdefault("qdrant_client", types.ModuleType("qdrant_client"))
    models = sys.modules.setdefault("qdrant_client.models",
                                    types.ModuleType("qdrant_client.models"))

    class _Any:
        def __init__(self, *a, **kw):
            pass

    if not hasattr(qc, "QdrantClient"):
        qc.QdrantClient = _Any
    qc.models = models
    for name in ("PointStruct", "Filter", "FieldCondition", "MatchValue"):
        if not hasattr(models, name):
            setattr(models, name, _Any)


def load_ingest():
    """Import session-ingest.py without running main() (it is import-guarded)."""
    install_dep_stubs()
    spec = importlib.util.spec_from_file_location("session_ingest_under_test", INGEST)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def session_summary_template(schema: str) -> str:
    """Return the fenced body of _SCHEMA.md's 'Session Summary Page Template'.

    Checking the whole file is NOT enough: the schema's own prose mentions
    `## Decisions Made` in backticks, so a substring check passes even when the real
    template heading has been translated. (That exact regression shipped once.) The
    contract is about the block agents COPY, so the test parses that block only.
    """
    marker = "### Session Summary Page Template"
    i = schema.index(marker)
    fence = schema.index("```markdown", i)
    body_start = schema.index("\n", fence) + 1
    body_end = schema.index("\n```", body_start)
    return schema[body_start:body_end]


def main():
    for path in (INGEST, SCHEMA, SKILL):
        if not path.exists():
            print(f"FAIL: missing {path.relative_to(REPO)}")
            return 1

    ingest = load_ingest()
    schema = SCHEMA.read_text(encoding="utf-8")

    try:
        template = session_summary_template(schema)
    except ValueError:
        print("FAIL: could not locate the Session Summary Page Template fenced block "
              "in _SCHEMA.md")
        return 1

    # 1. The block agents copy must carry the heading as a real heading, at line start.
    check(re.search(r"^## Decisions Made$", template, re.M) is not None,
          "the Session Summary Page Template no longer has a line-start "
          "'## Decisions Made' heading")

    # 2. ROUND-TRIP THE SHIPPED TEMPLATE: whatever the template actually contains must
    #    parse. This is the assertion that fails when the heading drifts or is translated.
    from_template = ingest.extract_decisions(template)
    check(len(from_template) >= 2,
          f"extract_decisions() found {len(from_template)} decisions in the SHIPPED "
          f"template block (expected its example bullets): {from_template!r}")
    check(all("Task/change" not in d for d in from_template),
          "extract_decisions() leaked '## Work Completed' content out of the template block")

    # 3. The documented tolerance for the '## Decisions' variant must not regress.
    variant = template.replace("## Decisions Made", "## Decisions")
    check(len(ingest.extract_decisions(variant)) == len(from_template),
          "extract_decisions() no longer accepts the '## Decisions' heading variant")

    # 4. A TRANSLATED heading must extract nothing — this is why both _SCHEMA.md and
    #    using-second-brain state the heading stays English. If this ever starts passing,
    #    the English-only rule in those docs has become wrong and must be updated.
    turkish = template.replace("## Decisions Made", "## Alınan Kararlar")
    check(ingest.extract_decisions(turkish) == [],
          "a translated heading now parses — update the 'headings stay English' rule in "
          "_SCHEMA.md and using-second-brain/SKILL.md")
    check(re.search(r"headings stay in English", schema, re.IGNORECASE) is not None,
          "_SCHEMA.md lost the 'structural headings stay in English' rule")

    # 5. The experience channel must stay in the same template block.
    check(re.search(r"^## Notes for the Next Session$", template, re.M) is not None,
          "the Session Summary Page Template lost '## Notes for the Next Session' — "
          "session-to-session experience transfer has no durable home")

    # 6. context-handoff must still reference the heading it routes from.
    skill = SKILL.read_text(encoding="utf-8")
    check("## Decisions Made" in skill,
          "context-handoff no longer references '## Decisions Made' — decision triage "
          "has lost its input")
    check("<decision_triage>" in skill,
          "context-handoff lost its <decision_triage> section")

    if failures:
        for f in failures:
            print(f"FAIL: {f}")
        return 1
    print("PASS: decision-heading parity (shipped template <-> parser <-> context-handoff)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
