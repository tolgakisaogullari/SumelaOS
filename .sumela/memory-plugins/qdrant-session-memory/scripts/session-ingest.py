#!/usr/bin/env python3
"""
session-ingest.py — Session Memory Ingestion Pipeline (v2.3-agnostic)

Usage:
    python session-ingest.py <session_summary_md_path>
    python session-ingest.py <path> --collection chat_history --ollama-url http://localhost:11434

What it does:
    1. Reads the session summary markdown.
    2. Extracts structured metadata: session_date, topics, decisions, affected_files.
    3. Chunks the body (512 words, 50 overlap), token-bounded — see lib.memory_ingest.
    4. Generates embeddings via Ollama (qwen3-embedding:0.6b).
    5. Deletes any prior points for this session, then upserts the fresh chunks
       into Qdrant 'chat_history' with enriched payload (idempotent re-ingest).
    6. Prints a structured status report for the agent to relay to the user.

Payload schema per chunk:
    text          : str    (the chunk body)
    session_id    : str    (filename without .md)
    date          : str    (ISO date, from frontmatter or today)
    date_int      : int     (YYYYMMDD form of `date` for range filtering; 0 if unparseable)
    developer     : str    (who did the work — frontmatter `developer`, else --fallback-developer, else "unknown")
    developer_email: str   (frontmatter `developer_email`, else "")
    domains       : list   (frontmatter `domains` — the session's domain context)
    spec_artifact : str    (frontmatter `spec_artifact` path, else "")
    plan_artifact : str    (frontmatter `plan_artifact` path, else "")
    topics        : list   (from frontmatter session_topics)
    decisions     : list   (extracted from a "## Decisions" / "## Decisions Made" block)
    affected_files: list   (any file paths mentioned in the chunk that match common code patterns)
    chunk_index   : int
    total_chunks  : int

These extra fields make `chat_history` queryable by developer / domain / date range
(see query-qdrant.py --developer/--domain/--since/--until). Summaries written before this
feature lack them and won't match a filter until re-ingested; the post-merge hook only
re-ingests summaries Added/Modified in a pulled range, so pre-existing ones backfill only
when re-committed (or via a one-time manual re-ingest of wiki/session-summaries/).

Environment:
    OLLAMA_URL       — Ollama base URL (default: http://localhost:11434)
    QDRANT_HOST      — Qdrant host (default: localhost)
    QDRANT_PORT      — Qdrant port (default: 6333)
    QDRANT_COLLECTION — Collection name (default: chat_history)
"""
import sys
import os
import re
import uuid
import hashlib
import argparse
from datetime import datetime
from pathlib import Path
from typing import List

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.memory_ingest import (
    resolve_collection_arg, project_slug, qdrant_client_preflight,
    # chunk_text/get_embedding live in the lib so the embedding-input bounds they carry
    # apply to EVERY path. Private copies here and in query-qdrant.py were the reason a
    # fix to the lib alone would have left the summary and query paths still crashing.
    chunk_text, get_embedding, ollama_preflight,
    # A session summary is prose that may quote a DSN or a token inline, and it lands in a
    # git-TRACKED file AND a vector index later sessions surface verbatim. The code path has
    # a filename skip-list; this is the prose equivalent for the summary path.
    redact_secrets, flag_possible_secrets,
)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def print_report(summary_lines: list):
    print("\n" + "=" * 60)
    print("SESSION INGEST REPORT")
    print("=" * 60)
    for line in summary_lines:
        print(line)
    print("=" * 60 + "\n")


def report_success(session_id: str, chunk_count: int, qdrant_ok: bool, decisions_n: int, files_n: int,
                   developer: str = "unknown", domains: list = None, redacted: list = None,
                   unmatched_headings: list = None, summary_path: str = "",
                   possible_secrets: list = None):
    extra = []
    if redacted:
        kinds = ", ".join(sorted(set(redacted)))
        extra.append(f"SECRETS REDACTED BEFORE INDEXING: {len(redacted)} ({kinds})")
        extra.append(f"  Masked in what {'was' if qdrant_ok else 'would have been'} indexed, but")
        extra.append(f"  {summary_path or 'the summary'} on disk still contains the RAW values and is")
        extra.append("  git-tracked. Scrub the file — that copy is the one that gets committed,")
        extra.append("  and any later re-ingest of it starts from the raw text again.")
    if possible_secrets:
        extra.append(f"POSSIBLE CREDENTIALS — NOT modified, review these {len(possible_secrets)} line(s):")
        for line in possible_secrets[:5]:
            extra.append(f"  {line}")
        if len(possible_secrets) > 5:
            extra.append(f"  ... and {len(possible_secrets) - 5} more")
        extra.append("  Names and line numbers only — the values are deliberately not echoed,")
        extra.append("  because this report is tee'd into .sumela/.memory-sync.log. A 'key: value'")
        extra.append("  shape is not separable from ordinary prose, so these are reported rather")
        extra.append("  than rewritten: masking a sentence would corrupt the only copy the next")
        extra.append("  session can query. Check these lines before you commit the file.")
    if unmatched_headings:
        extra.append("DECISION HEADINGS NOT PARSED: " + ", ".join(unmatched_headings))
        extra.append("  These look like decision sections but do not match the expected")
        extra.append("  '## Decisions Made' / '## Decisions' heading, so nothing was extracted")
        extra.append(f"  FROM THEM ({decisions_n} decision(s) were extracted from elsewhere in this")
        extra.append("  summary). Rename the heading, or those decisions stay unsearchable.")
    print_report(extra + [
        f"Status: {'SUCCESS' if qdrant_ok else 'PARTIAL'}",
        f"Session ID: {session_id}",
        f"Developer: {developer}",
        f"Domains: {', '.join(domains) if domains else '(none)'}",
        f"Chunks created: {chunk_count}",
        f"Decisions extracted: {decisions_n}",
        f"Affected files mentioned: {files_n}",
        f"Qdrant upsert: {'OK' if qdrant_ok else 'FAILED (fallback to markdown)'}",
        "Action for agent: Relay this summary to the user.",
    ])


def report_failure(stage: str, reason: str):
    print_report([
        "Status: FAILED",
        f"Stage: {stage}",
        f"Reason: {reason}",
        "Action for agent: Inform the user of the failure.",
    ])

try:
    import requests
except ImportError:
    report_failure("Dependency", "requests not installed. Run: pip install requests")
    sys.exit(1)

try:
    from qdrant_client import QdrantClient
    from qdrant_client.models import PointStruct, Filter, FieldCondition, MatchValue
except ImportError:
    report_failure("Dependency", "qdrant-client not installed. Run: pip install qdrant-client")
    sys.exit(1)

# Common code-file path patterns (Windows + POSIX)
FILE_PATTERN = re.compile(
    r"\b(?:src|tests|docs|scripts|nginx)[\\/][\w\-\.\\/]+\.(?:cs|ts|tsx|js|jsx|py|md|json|yml|yaml|sql|csproj)\b",
    re.IGNORECASE,
)

# Decision section heading variants
DECISION_HEADERS = (
    re.compile(r"^##\s+Decisions?\s+Made\s*$", re.IGNORECASE | re.MULTILINE),
    re.compile(r"^##\s+Decisions?\s*$", re.IGNORECASE | re.MULTILINE),
)


def deterministic_id(key: str, chunk_index: int) -> str:
    """Process-independent point ID derived from (key, chunk_index).

    Re-ingesting the same summary upserts (overwrites) the same points instead
    of creating duplicates — this is what makes the post-merge ingest hook safe
    to run on every pull. `key` is the session_id (summary filename without
    extension), so summary filenames MUST be unique across the project.
    """
    hex_str = hashlib.sha256(f"{key}_{chunk_index}".encode("utf-8")).hexdigest()[:32]
    return str(uuid.UUID(hex=hex_str))


def extract_frontmatter(content: str) -> dict:
    fm = {}
    if not content.startswith("---"):
        return fm
    parts = content.split("---", 2)
    if len(parts) < 3:
        return fm
    for line in parts[1].strip().splitlines():
        # Skip full-line comments; tolerate a trailing " # comment" on a value (agents
        # sometimes copy the annotated template verbatim). " #" (space-hash) avoids
        # clipping a '#' that is part of a value (e.g. "c#-migration").
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" in line:
            k, v = line.split(":", 1)
            v = v.split(" #", 1)[0].strip()
            fm[k.strip()] = v
    return fm


def _strip_fenced(content: str) -> str:
    """Blank out fenced code blocks, keeping line count so line numbers stay usable.

    A `## Decisions Made` inside a fence is an EXAMPLE — `_SCHEMA.md`'s own session-summary
    template is exactly that. Without this, a summary that quotes the template supplies the
    whole `decisions` payload from boilerplate while the report shows a healthy count.
    """
    # An UNCLOSED fence would otherwise blank everything after it — a truncated pasted
    # transcript above the decisions section made extract_decisions return [] with a SUCCESS
    # report. If the fences are unbalanced the document is not reliably fenced, so strip nothing.
    if sum(1 for ln in content.splitlines()
           if ln.lstrip().startswith("```") or ln.lstrip().startswith("~~~")) % 2 != 0:
        return content

    out, in_fence = [], False
    for line in content.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
            out.append("")
            continue
        out.append("" if in_fence else line)
    return "\n".join(out)


def extract_decisions(content: str) -> List[str]:
    """Find a Decisions section and pull out bullet points (fenced examples ignored)."""
    content = _strip_fenced(content)
    for pattern in DECISION_HEADERS:
        m = pattern.search(content)
        if not m:
            continue
        rest = content[m.end():]
        next_h = re.search(r"^##\s+", rest, re.MULTILINE)
        block = rest[: next_h.start()] if next_h else rest
        bullets = re.findall(r"^\s*[-*]\s+(.+)$|^\s*\d+\.\s+(.+)$", block, re.MULTILINE)
        flat = [a or b for a, b in bullets if (a or b)]
        return [d.strip() for d in flat if d.strip()]
    return []


DECISION_WORD = re.compile(r"(?i)\bdecisions?\b")


def find_unparsed_decision_headings(content: str) -> List[str]:
    """Headings that look like a decision section but did not match DECISION_HEADERS.

    `## Key decisions`, `## Scope decisions`, `## Decisions (sprint 12)` are all English,
    all obviously decision sections, and all invisible to the anchored patterns above —
    extract_decisions() returns [] and the run still reports SUCCESS. Loosening the regex
    would undercut the "keep the heading verbatim" contract the schema and its parity test
    pin, so instead make the silence audible: name the near-miss at ingest time, where the
    author can still fix it, rather than leaving it to surface as an empty query months later.
    """
    misses = []
    # Reuse the same stripper: it carries the unbalanced-fence guard, so an unclosed fence
    # cannot make `in_fence` stick and silence every warning after it.
    for line in _strip_fenced(content).splitlines():
        if not line.startswith("## ") or line.startswith("###"):
            continue                      # H2 only: ### Pending Decisions is a sub-section, not a miss
        if not DECISION_WORD.search(line):
            continue
        if any(pat.match(line) for pat in DECISION_HEADERS):
            continue
        misses.append(line.strip())
    return misses


def extract_affected_files(text: str) -> List[str]:
    matches = set(m.group(0).replace("\\", "/") for m in FILE_PATTERN.finditer(text))
    return sorted(matches)


def main():
    parser = argparse.ArgumentParser(
        description="Ingest a session summary markdown into Qdrant."
    )
    parser.add_argument("summary_path", help="Path to session summary markdown file")
    parser.add_argument("--collection", default="chat_history",
                        help="Qdrant collection: a logical base (chat_history) resolves to the "
                             "per-project physical name; QDRANT_COLLECTION env overrides.")
    parser.add_argument("--ollama-url", default=os.getenv("OLLAMA_URL", "http://localhost:11434"),
                        help="Ollama base URL (default: http://localhost:11434 or OLLAMA_URL env)")
    parser.add_argument("--host", default=os.getenv("QDRANT_HOST", "localhost"),
                        help="Qdrant host (default: localhost or QDRANT_HOST env)")
    parser.add_argument("--port", type=int, default=int(os.getenv("QDRANT_PORT", "6333")),
                        help="Qdrant port (default: 6333 or QDRANT_PORT env)")
    parser.add_argument("--fallback-developer", default="",
                        help="Used as `developer` when the summary frontmatter has none "
                             "(the post-merge hook passes the commit's git author here).")
    parser.add_argument("--fallback-date", default="",
                        help="Used as `session_date` when frontmatter has none (ISO YYYY-MM-DD).")
    args = parser.parse_args()

    # Preflight: qdrant-client>=1.12 required (a git pull bumps requirements, not the venv).
    # Report one actionable line instead of a traceback before any embedding work.
    preflight = qdrant_client_preflight()
    if preflight:
        report_failure("qdrant-client", preflight)
        sys.exit(1)

    # Resolve the logical base to the per-project physical collection, and the slug
    # used to namespace point IDs + stamp payloads (so two projects on one shared
    # Qdrant never collide). See lib.memory_ingest.
    collection = resolve_collection_arg(args.collection)
    slug = project_slug()

    summary_path = args.summary_path
    if not os.path.exists(summary_path):
        report_failure("File I/O", f"File not found: {summary_path}")
        sys.exit(1)

    with open(summary_path, "r", encoding="utf-8") as f:
        text = f.read()

    fm = extract_frontmatter(text)
    session_date = fm.get("session_date") or args.fallback_date or datetime.now().strftime("%Y-%m-%d")

    def _list_field(key):
        """Parse a frontmatter value that may be a YAML inline list or comma string."""
        raw = fm.get(key, "")
        return [t.strip() for t in raw.strip("[]").replace("'", "").replace('"', "").split(",") if t.strip()]

    topics = _list_field("session_topics")
    domains = _list_field("domains")
    developer = (fm.get("developer") or args.fallback_developer or "unknown").strip()
    developer_email = fm.get("developer_email", "").strip()
    spec_artifact = fm.get("spec_artifact", "").strip()
    plan_artifact = fm.get("plan_artifact", "").strip()
    # date_int (YYYYMMDD) for Qdrant Range filtering; 0 if the date isn't a clean ISO date.
    try:
        date_int = int(datetime.strptime(session_date.strip(), "%Y-%m-%d").strftime("%Y%m%d"))
    except (ValueError, AttributeError):
        date_int = 0
    # splitext (not .replace) so filenames containing ".md" mid-name aren't mangled.
    session_id = os.path.splitext(os.path.basename(summary_path))[0]

    # Redact FIRST. Everything below is derived from `text` — the chunks that get embedded,
    # but also the `decisions` payload field and the affected-file list — and an earlier
    # ordering redacted only the chunks, so a secret quoted inside a `## Decisions Made`
    # bullet still reached Qdrant verbatim while the report claimed the index was clean.
    # Redaction masks values in place; it removes no heading and no bullet, so extraction
    # counts exactly what it would have counted before.
    # Flag on the ORIGINAL text: redaction can collapse a multi-line PEM block into a single
    # token, after which every reported line number points at the wrong line of the file the
    # report is asking the user to open. Values are never echoed either way.
    possible = flag_possible_secrets(text)
    text, redacted = redact_secrets(text)

    decisions = extract_decisions(text)
    affected_files = extract_affected_files(text)
    unmatched = find_unparsed_decision_headings(text)

    if redacted:
        print(f"[session-ingest] Redacted {len(redacted)} secret-shaped value(s) before indexing.")
    if possible:
        print(f"[session-ingest] WARNING: {len(possible)} line(s) look like credential assignments "
              "(reported, NOT modified).")
    if unmatched:
        print(f"[session-ingest] WARNING: decision-like heading(s) not parsed: {', '.join(unmatched)}")

    chunks = chunk_text(text)
    if not chunks:
        # Bail BEFORE the delete below: an empty summary would otherwise wipe the prior
        # session's points and upsert nothing in their place.
        print("[session-ingest] Summary body is empty — nothing to ingest, index unchanged.")
        report_success(session_id, 0, False, len(decisions), len(affected_files),
                       redacted=redacted, unmatched_headings=unmatched, summary_path=summary_path,
                       possible_secrets=possible)
        sys.exit(0)
    print(f"[session-ingest] Chunked into {len(chunks)} chunks.")
    print(f"[session-ingest] Decisions extracted: {len(decisions)}")
    print(f"[session-ingest] Affected files: {len(affected_files)}")

    # Preflight the embedding backend BEFORE any work. Without it a stopped Ollama is
    # discovered one chunk at a time, each attempt sleeping through its retry budget in a
    # detached background process launched from a git hook. Exit 1 = could-not-run, which
    # is what the pull hook logs as "ingest failed" (see _lib.sh sumela_memory_sync).
    backend_error = ollama_preflight(args.ollama_url)
    if backend_error:
        print(f"[session-ingest] {backend_error}")
        report_success(session_id, len(chunks), False, len(decisions), len(affected_files),
                       developer=developer, domains=domains, redacted=redacted,
                       unmatched_headings=unmatched, summary_path=summary_path,
                       possible_secrets=possible)

        sys.exit(1)

    qdrant_ok = False
    try:
        client = QdrantClient(host=args.host, port=args.port, check_compatibility=False)
        points = []
        for i, chunk in enumerate(chunks):
            embedding = get_embedding(chunk, args.ollama_url)
            chunk_files = extract_affected_files(chunk) or affected_files
            points.append(
                PointStruct(
                    id=deterministic_id(f"{slug}::{session_id}", i),
                    vector=embedding,
                    payload={
                        "text": chunk,
                        "session_id": session_id,
                        "project_slug": slug,
                        "date": session_date,
                        "date_int": date_int,
                        "developer": developer,
                        "developer_email": developer_email,
                        "domains": domains,
                        "spec_artifact": spec_artifact,
                        "plan_artifact": plan_artifact,
                        "topics": topics,
                        "decisions": decisions,
                        "affected_files": chunk_files,
                        "chunk_index": i,
                        "total_chunks": len(chunks),
                    },
                )
            )
        # Delete any prior points for this session BEFORE upserting fresh ones.
        # Deterministic IDs make re-ingest overwrite indices 0..N-1, but if an
        # edited summary now yields FEWER chunks, the old higher-index points
        # would be orphaned. Delete-by-session_id then upsert guarantees the
        # collection exactly mirrors the current summary — which is what the
        # post-merge ingest hook relies on. Embeddings are computed above, so by
        # the time we delete we are committed to a successful re-insert.
        client.delete(
            collection_name=collection,
            points_selector=Filter(
                must=[FieldCondition(key="session_id", match=MatchValue(value=session_id))]
            ),
        )
        client.upsert(collection_name=collection, points=points)
        qdrant_ok = True
        print(f"[session-ingest] Replaced session '{session_id}' with {len(points)} chunks in Qdrant '{collection}'.")
    except Exception as e:
        print(f"[session-ingest] WARNING: Qdrant upsert failed: {e}")
        print("[session-ingest] Fallback: markdown summary already exists; will retry on next run.")

    report_success(session_id, len(chunks), qdrant_ok, len(decisions), len(affected_files),
                   developer=developer, domains=domains, redacted=redacted,
                   unmatched_headings=unmatched, summary_path=summary_path,
                       possible_secrets=possible)

    # Exit code must MATCH the report: this used to always exit 0, so a failed embed or a
    # failed upsert printed "WARNING" and still told the caller it had succeeded — the
    # silent "memory did not update" the field report described. There is no exit-2
    # (ran-but-stale) case here the way there is for the bulk ingests: one summary is
    # ingested atomically (every embedding is computed BEFORE the delete above), so the
    # outcome is binary. 0 = ingested, 1 = could not.
    sys.exit(0 if qdrant_ok else 1)


if __name__ == "__main__":
    main()
