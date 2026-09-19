#!/usr/bin/env python3
"""Dependency-free tests for the session-ingest guards added in v0.19.0.

Two silent-failure classes this guards:

  1. SECRET LEAK. A session summary is prose that may quote a DSN or token inline, and
     `context-handoff` now explicitly invites "commands that do not work in this repo"
     into it. That text lands in a git-TRACKED file AND in a vector index later sessions
     surface verbatim. The code-ingest path has a filename skip-list; the summary path
     had nothing. redact_secrets() is the prose equivalent.

  2. SILENT ZERO. DECISION_HEADERS needs a full-line match, so `## Key decisions` extracts
     nothing while the run still reports SUCCESS. find_unparsed_decision_headings() names
     the near-miss at ingest time instead of letting it surface as an empty query later.

Also pins `.sumela/RULE_REGISTRY.md.template` into both updaters' CORE list: files at the
`.sumela/` ROOT are in neither CORE_FILES nor CORE_DIRS, which froze that template in every
upgrading install from v0.8.0 on. Run:

    python3 tests/test_session_ingest_guards.py

Exits non-zero on the first failed assertion. No pytest / third-party deps.
"""
import importlib.util
import sys
import types
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPTS = REPO / ".sumela/memory-plugins/qdrant-session-memory/scripts"
INGEST = SCRIPTS / "session-ingest.py"

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def load_ingest():
    """Import session-ingest.py with its pip deps stubbed (see test_decision_heading_parity)."""
    sys.modules.setdefault("requests", types.ModuleType("requests"))
    qc = sys.modules.setdefault("qdrant_client", types.ModuleType("qdrant_client"))
    models = sys.modules.setdefault("qdrant_client.models", types.ModuleType("qdrant_client.models"))

    class _Any:
        def __init__(self, *a, **kw):
            pass

    if not hasattr(qc, "QdrantClient"):
        qc.QdrantClient = _Any
    for name in ("PointStruct", "Filter", "FieldCondition", "MatchValue"):
        if not hasattr(models, name):
            setattr(models, name, _Any)

    sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location("session_ingest_guards_under_test", INGEST)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def test_redaction(ingest):
    redact = ingest.redact_secrets
    flag = ingest.flag_possible_secrets

    # HIGH-CONFIDENCE shapes are masked: these are not ambiguous in prose.
    cases = [
        ("psql postgres://app:hunter2@db:5432/x", "dsn-password", "hunter2"),
        ("Bearer eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM0.SflKxwRJSMeKKF2QT", "jwt", "SflKxwRJSMeKKF2QT"),
        ("key AKIA1234567890ABCDEF", "aws-key-id", "AKIA1234567890ABCDEF"),
    ]
    for text, kind, secret in cases:
        out, found = redact(text)
        check(kind in found, f"redact_secrets missed {kind!r} in {text!r} (found {found!r})")
        check(secret not in out, f"redact_secrets left the raw secret in output: {out!r}")

    # A DSN must stay structurally readable — the note is useless if the separators vanish.
    out, _ = redact("psql postgres://app:hunter2@db:5432/x")
    check("postgres://app:[REDACTED:dsn-password]@db:5432/x" in out,
          f"DSN redaction mangled the separators: {out!r}")

    # Credential-only DSNs (redis/celery/amqp) have an EMPTY username, and a password may
    # itself contain '@'. Both forms used to slip through while still counting as handled.
    # Assert on the whole rewritten string, not on `secret not in out`: with "p@ss" that
    # substring test passes while "ss" is still embedded, which green-lit a real leak once.
    for dsn, expected in [
        ("redis://:s3cr3tpw@cache:6379/0", "redis://:[REDACTED:dsn-password]@cache:6379/0"),
        ("amqp://:guestpw@rabbit/",        "amqp://:[REDACTED:dsn-password]@rabbit/"),
        ("postgres://u:pa=ss@h/x",         "postgres://u:[REDACTED:dsn-password]@h/x"),
        # A '@' inside the password is common (P@ssw0rd!); userinfo ends at the LAST '@'.
        ("mongodb://admin:P@ssw0rd!@cluster0.net/db",
         "mongodb://admin:[REDACTED:dsn-password]@cluster0.net/db"),
    ]:
        out, found = redact(dsn)
        check(out == expected and "dsn-password" in found,
              f"DSN redaction wrong for {dsn!r}: got {out!r} ({found!r}), want {expected!r}")

    # A TEMPLATE is not a secret. Source code is full of these, and masking them put a
    # "SECRETS REDACTED" line on every ordinary repo while making the chunk differ from the file.
    for tmpl in ['f"postgres://{user}:{pwd}@{host}/{db}"', '"https://%s:%s@%s/db" % (u,p,h)',
                 'url = f"redis://:{pw}@{host}"', "postgres://u:$PW@h/db"]:
        out, found = redact(tmpl)
        check(out == tmpl and found == [],
              f"redact_secrets masked a DSN template: {tmpl!r} -> {out!r} ({found!r})")

    # Userinfo splits at the FIRST colon: a password containing ':' used to split at the LAST
    # one, leaving its leading part embedded while the report counted a clean redaction.
    out, found = redact("mysql://root:My:Secret:Pw@db/x")
    check(out == "mysql://root:[REDACTED:dsn-password]@db/x" and "dsn-password" in found,
          f"DSN userinfo split at the wrong colon: {out!r}")

    # The match must stop at the authority: a following sentence is not part of the DSN.
    out, _ = redact("use postgres://app:pw@db, notify=ops@corp.com please")
    check(out == "use postgres://app:[REDACTED:dsn-password]@db, notify=ops@corp.com please",
          f"DSN redaction ran past the authority into the sentence: {out!r}")

    # A URL that merely contains a colon must not be mistaken for credentials.
    out, found = redact("see http://example.com/a:b path")
    check(found == [] and out == "see http://example.com/a:b path",
          f"redact_secrets fired on an ordinary URL: {out!r}")

    # The PEM pattern must NOT span prose. Redaction runs BEFORE extraction and chunking, so an
    # over-greedy match silently deletes decisions, file references and whole sections while the
    # run still reports SUCCESS.
    doc = ("Mentions -----BEGIN RSA PRIVATE KEY----- in prose.\n\n"
           "## Decisions Made\n- keep the retry budget at 3\n\n"
           "## Work Completed\n- src/app.py rewritten\n\n"
           "The -----END RSA PRIVATE KEY----- marker is also discussed.\n")
    out, found = redact(doc)
    check("## Decisions Made" in out and "src/app.py" in out and found == [],
          "the PEM pattern swallowed prose between two mentioned markers — "
          f"redacted={found!r}")

    # The regression that got through once: a span whose only punctuation is ':' and ',' —
    # exactly what an encrypted-PEM header looks like, and exactly what ordinary notes about
    # keys look like too.
    colonish = ("-----BEGIN RSA PRIVATE KEY----- is the marker\n"
                "- keys start with that line\n"
                "- Proc-Type: 4,ENCRYPTED appears when encrypted\n"
                "- we rotate them yearly\n"
                "- the closing line is -----END RSA PRIVATE KEY-----\n")
    out, found = redact(colonish)
    check(out == colonish and found == [],
          f"the PEM pattern ate prose whose only punctuation is ':' and ',': {out!r}")

    # A key in a summary arrives indented, fenced or blockquoted — the shapes markdown
    # produces. Missing those means the report says "nothing redacted" while the key is
    # embedded verbatim.
    B, E = "-----BEGIN RSA PRIVATE KEY-----", "-----END RSA PRIVATE KEY-----"
    body = "MIIEowIBAAKCAQEAx3Zs9k2mQabcdef=="
    for label, block in [
        ("plain",       f"{B}\n{body}\n{E}"),
        ("indented",    f"    {B}\n    {body}\n    {E}"),
        ("blockquote",  f"> {B}\n> {body}\n> {E}"),
        ("trailing ws", f"{B} \n{body}  \n{E}"),
        ("short tail",  f"{B}\n{body}\nAB==\n{E}"),
    ]:
        out, found = redact(block)
        check("private-key" in found and body not in out,
              f"PEM redaction missed the {label} form: {found!r}")

    # ...while a REAL encrypted key still matches.
    enc = ("-----BEGIN RSA PRIVATE KEY-----\n"
           "Proc-Type: 4,ENCRYPTED\n"
           "DEK-Info: AES-128-CBC,ABC123\n\n"
           "MIIEowIBAAKCAQEAx3Zs9k2mQabcdef==\n"
           "-----END RSA PRIVATE KEY-----")
    out, found = redact(enc)
    check("private-key" in found and "MIIEowIBAAKCAQEA" not in out,
          f"an encrypted PEM block was not redacted: {found!r}")

    # A REAL PEM block is still caught.
    pem = ("-----BEGIN RSA PRIVATE KEY-----\n"
           "MIIEowIBAAKCAQEAx3Zs9k2mQ==\n"
           "-----END RSA PRIVATE KEY-----")
    out, found = redact(pem)
    check("private-key" in found and "MIIEowIBAAKCAQEA" not in out,
          f"a real PEM block was not redacted: {found!r}")

    # AMBIGUOUS `key: value` is REPORTED, never rewritten. Every shape test that caught the
    # real secrets also caught sentences like these, and redaction is destructive: the chunk
    # is the only thing the next session can query.
    prose = [
        "- Token: rotated manually every Monday",
        "password: see the vault entry",
        "private_key: ~/.ssh/id_ed25519",
        "auth = middleware/auth2.ts",
        "token: $GITHUB_TOKEN_2024",
        "- client_secret: rotated-2024-01-15",
        "- password: reset-instructions/step2.md",
    ]
    for line in prose:
        out, found = redact(line)
        check(out == line and found == [],
              f"redact_secrets rewrote ordinary prose: {line!r} -> {out!r} ({found!r})")

    # ...but the credential-shaped ones are still surfaced for a human to check.
    for line in ["API_KEY=sk-abc12345defg", "SECRET_KEY=abc123", "DJANGO_SECRET_KEY = xyz",
                 "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI", "access_token=abc", "db_password=hunter2"]:
        check(flag(line), f"flag_possible_secrets missed a credential assignment: {line!r}")

    # The VALUE must never be echoed: this report is tee'd into .sumela/.memory-sync.log by
    # the git hooks, so printing the matched line would copy the secret into a second
    # persistent plaintext file — the guard becoming a leak of its own.
    hits = flag("AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI\n- password: hunter2SuperSecret")
    check(len(hits) == 2, f"expected two hits, got {hits!r}")
    check(all("wJalrXUtnFEMI" not in h and "hunter2SuperSecret" not in h for h in hits),
          f"flag_possible_secrets echoed a secret VALUE into its output: {hits!r}")
    check(all(h.startswith("line ") for h in hits),
          f"flag_possible_secrets output lost its line-number anchor: {hits!r}")

    # A prose summary writes credentials in markdown, not shell syntax.
    for md in ["- **Token:** ghp_abc", "**Password:** hunter2", "- `API_KEY`: sk-abc",
               "- API key: sk-live-x", "client secret: xyz"]:
        check(flag(md), f"flag_possible_secrets missed a markdown credential form: {md!r}")

    for quiet in ["ran make build -- it failed on node 18", "the tokenizer: works fine",
                  "passwords: rotated quarterly", "a token is required",
                  "see the vault for details"]:
        check(flag(quiet) == [], f"flag_possible_secrets fired on prose: {quiet!r}")


def test_near_miss_headings(ingest):
    find = ingest.find_unparsed_decision_headings

    # The canonical headings parse, so they must NOT be reported as near-misses.
    for good in ["## Decisions Made\n- a\n", "## Decisions\n- a\n", "## decisions made\n- a\n"]:
        check(find(good) == [], f"canonical heading reported as a near-miss: {good!r}")
        check(len(ingest.extract_decisions(good)) == 1,
              f"canonical heading stopped parsing: {good!r}")

    # These are the real-world variants that silently extracted nothing.
    for bad in ["## Key decisions", "## Scope decisions", "## Decisions (sprint 12)",
                "## Key design decisions", "## Mid-session decisions"]:
        doc = f"# S\n\n{bad}\n- a\n- b\n\n## Work Completed\n- x\n"
        check(ingest.extract_decisions(doc) == [],
              f"{bad!r} unexpectedly parses now — if the regex was loosened on purpose, "
              "update this test and the 'keep the heading verbatim' rule together")
        check(find(doc) == [bad],
              f"near-miss not reported for {bad!r}: {find(doc)!r}")

    # A fenced `## Decisions Made` is an EXAMPLE — _SCHEMA.md's own session-summary template is
    # exactly that — so it must not supply the decisions payload.
    quoted = ("# S\n\n```markdown\n## Decisions Made\n- TEMPLATE EXAMPLE\n```\n\n"
              "## Decisions Made\n- the real one\n")
    got = ingest.extract_decisions(quoted)
    check(got == ["the real one"],
          f"extract_decisions took its payload from a fenced example: {got!r}")

    # An UNCLOSED fence must not blank the rest of the document: a truncated pasted transcript
    # above the decisions section made extract_decisions return [] with a SUCCESS report.
    truncated = "# S\n\n```\nsome pasted transcript that was cut off\n\n## Decisions Made\n- the real one\n"
    got = ingest.extract_decisions(truncated)
    check(got == ["the real one"],
          f"an unclosed fence swallowed the decisions section: {got!r}")

    # A heading with no decision word is not a near-miss (that class is covered by the
    # English-heading rule + test_decision_heading_parity, not by this heuristic).
    check(find("## Work Completed\n- x\n") == [],
          "unrelated heading reported as a decision near-miss")

    # A CONFORMING summary must stay silent. `### Pending Decisions / Blockers` is a legitimate
    # sub-section and a `## Key decisions` inside a code fence is an example, not a section —
    # warning about either told the author decisions were unsearchable when they were not.
    conforming = ("## Decisions Made\n- a\n\n"
                  "### Pending Decisions / Blockers\n- q\n\n"
                  "```markdown\n## Key decisions\n- example\n```\n")
    check(find(conforming) == [],
          f"conforming summary produced a false near-miss warning: {find(conforming)!r}")

    # And the secret guard must reach the DECISIONS payload, not just the embedded chunks.
    redacted_doc, _ = ingest.redact_secrets("## Decisions Made\n- use postgres://u:pw123456@h\n")
    got = ingest.extract_decisions(redacted_doc)
    check(got and "pw123456" not in got[0],
          f"a secret quoted in a decision bullet survived into the payload: {got!r}")


def test_root_level_core_file():
    """Files at the .sumela/ ROOT are in neither CORE_FILES nor CORE_DIRS."""
    for updater in ("scripts/update.sh", "scripts/update.ps1"):
        text = (REPO / updater).read_text(encoding="utf-8")
        check(".sumela/RULE_REGISTRY.md.template" in text,
              f"{updater} no longer carries .sumela/RULE_REGISTRY.md.template in its CORE list — "
              "a root-level framework file will freeze in every upgrading install")


def main():
    if not INGEST.exists():
        print(f"FAIL: missing {INGEST.relative_to(REPO)}")
        return 1
    ingest = load_ingest()
    test_redaction(ingest)
    test_near_miss_headings(ingest)
    test_root_level_core_file()

    if failures:
        for f in failures:
            print(f"FAIL: {f}")
        return 1
    print("PASS: session-ingest guards (secret redaction, near-miss headings, root CORE file)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
