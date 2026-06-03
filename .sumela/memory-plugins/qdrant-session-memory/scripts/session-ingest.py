#!/usr/bin/env python3
"""
session-ingest.py — Session Memory Ingestion Pipeline (v2.3-agnostic)

Usage:
    python session-ingest.py <session_summary_md_path>
    python session-ingest.py <path> --collection chat_history --ollama-url http://localhost:11434

What it does:
    1. Reads the session summary markdown.
    2. Extracts structured metadata: session_date, topics, decisions, affected_files.
    3. Chunks the body (512 tokens, 50 overlap).
    4. Generates embeddings via Ollama (qwen3-embedding:0.6b).
    5. Deletes any prior points for this session, then upserts the fresh chunks
       into Qdrant 'chat_history' with enriched payload (idempotent re-ingest).
    6. Prints a structured status report for the agent to relay to the user.

Payload schema per chunk:
    text          : str    (the chunk body)
    session_id    : str    (filename without .md)
    date          : str    (ISO date, from frontmatter or today)
    topics        : list   (from frontmatter session_topics)
    decisions     : list   (extracted from a "## Decisions" / "## Decisions Made" block)
    affected_files: list   (any file paths mentioned in the chunk that match common code patterns)
    chunk_index   : int
    total_chunks  : int

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
from typing import List

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def print_report(summary_lines: list):
    print("\n" + "=" * 60)
    print("SESSION INGEST REPORT")
    print("=" * 60)
    for line in summary_lines:
        print(line)
    print("=" * 60 + "\n")


def report_success(session_id: str, chunk_count: int, qdrant_ok: bool, decisions_n: int, files_n: int):
    print_report([
        f"Status: {'SUCCESS' if qdrant_ok else 'PARTIAL'}",
        f"Session ID: {session_id}",
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

CHUNK_SIZE = 512
OVERLAP = 50

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


def chunk_text(text: str, size: int = CHUNK_SIZE, overlap: int = OVERLAP) -> List[str]:
    words = text.split()
    if len(words) <= size:
        return [text]
    chunks = []
    start = 0
    while start < len(words):
        end = min(start + size, len(words))
        chunks.append(" ".join(words[start:end]))
        start += size - overlap
    return chunks


def get_embedding(text: str, ollama_url: str) -> List[float]:
    resp = requests.post(
        f"{ollama_url}/api/embeddings",
        json={"model": "qwen3-embedding:0.6b", "prompt": text},
        timeout=120,
    )
    resp.raise_for_status()
    return resp.json()["embedding"]


def extract_frontmatter(content: str) -> dict:
    fm = {}
    if not content.startswith("---"):
        return fm
    parts = content.split("---", 2)
    if len(parts) < 3:
        return fm
    for line in parts[1].strip().splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip()
    return fm


def extract_decisions(content: str) -> List[str]:
    """Find a Decisions section and pull out bullet points."""
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


def extract_affected_files(text: str) -> List[str]:
    matches = set(m.group(0).replace("\\", "/") for m in FILE_PATTERN.finditer(text))
    return sorted(matches)


def main():
    parser = argparse.ArgumentParser(
        description="Ingest a session summary markdown into Qdrant."
    )
    parser.add_argument("summary_path", help="Path to session summary markdown file")
    parser.add_argument("--collection", default=os.getenv("QDRANT_COLLECTION", "chat_history"),
                        help="Qdrant collection name (default: chat_history or QDRANT_COLLECTION env)")
    parser.add_argument("--ollama-url", default=os.getenv("OLLAMA_URL", "http://localhost:11434"),
                        help="Ollama base URL (default: http://localhost:11434 or OLLAMA_URL env)")
    parser.add_argument("--host", default=os.getenv("QDRANT_HOST", "localhost"),
                        help="Qdrant host (default: localhost or QDRANT_HOST env)")
    parser.add_argument("--port", type=int, default=int(os.getenv("QDRANT_PORT", "6333")),
                        help="Qdrant port (default: 6333 or QDRANT_PORT env)")
    args = parser.parse_args()

    summary_path = args.summary_path
    if not os.path.exists(summary_path):
        report_failure("File I/O", f"File not found: {summary_path}")
        sys.exit(1)

    with open(summary_path, "r", encoding="utf-8") as f:
        text = f.read()

    fm = extract_frontmatter(text)
    session_date = fm.get("session_date", datetime.now().strftime("%Y-%m-%d"))
    topics = (
        [t.strip() for t in fm.get("session_topics", "").strip("[]").replace("'", "").split(",") if t.strip()]
        if "session_topics" in fm
        else []
    )
    # splitext (not .replace) so filenames containing ".md" mid-name aren't mangled.
    session_id = os.path.splitext(os.path.basename(summary_path))[0]

    decisions = extract_decisions(text)
    affected_files = extract_affected_files(text)

    chunks = chunk_text(text)
    print(f"[session-ingest] Chunked into {len(chunks)} chunks.")
    print(f"[session-ingest] Decisions extracted: {len(decisions)}")
    print(f"[session-ingest] Affected files: {len(affected_files)}")

    qdrant_ok = False
    try:
        client = QdrantClient(host=args.host, port=args.port, check_compatibility=False)
        points = []
        for i, chunk in enumerate(chunks):
            embedding = get_embedding(chunk, args.ollama_url)
            chunk_files = extract_affected_files(chunk) or affected_files
            points.append(
                PointStruct(
                    id=deterministic_id(session_id, i),
                    vector=embedding,
                    payload={
                        "text": chunk,
                        "session_id": session_id,
                        "date": session_date,
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
            collection_name=args.collection,
            points_selector=Filter(
                must=[FieldCondition(key="session_id", match=MatchValue(value=session_id))]
            ),
        )
        client.upsert(collection_name=args.collection, points=points)
        qdrant_ok = True
        print(f"[session-ingest] Replaced session '{session_id}' with {len(points)} chunks in Qdrant '{args.collection}'.")
    except Exception as e:
        print(f"[session-ingest] WARNING: Qdrant upsert failed: {e}")
        print("[session-ingest] Fallback: markdown summary already exists; will retry on next run.")

    report_success(session_id, len(chunks), qdrant_ok, len(decisions), len(affected_files))
    sys.exit(0)


if __name__ == "__main__":
    main()
