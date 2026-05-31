#!/usr/bin/env python3
"""
ingest-wiki-to-qdrant.py — Wiki Page Ingestion Pipeline (v1.1)

Usage:
    python .openskills/memory-plugins/qdrant-session-memory/scripts/ingest-wiki-to-qdrant.py

What it does:
    1. Walks docs/second-brain/wiki/ for all .md files (excluding special files).
    2. Parses YAML frontmatter (type, tags, date_updated).
    3. Chunks body via naive word-level split (512 tokens, 50 overlap).
    4. Generates embeddings via Ollama (qwen3-embedding:0.6b) in parallel.
    5. Deletes existing points for the page (idempotency) and upserts new chunks
       into Qdrant 'wiki_pages' collection with structured payload.
    6. Prints a structured status report for the agent to relay to the user.

Payload schema per point:
    text          : str    (the chunk body)
    page_path     : str    (relative path from wiki root)
    page_title    : str    (filename without .md)
    page_type     : str    (from frontmatter 'type')
    tags          : list   (from frontmatter 'tags')
    date_updated  : str    (from frontmatter 'date_updated' or today)
    chunk_index   : int
    total_chunks  : int

Environment:
    OLLAMA_HOST defaults to http://localhost:11434
    QDRANT_HOST defaults to localhost:6333
    QDRANT_PORT defaults to 6333
    WIKI_PAGES_COLLECTION defaults to wiki_pages
    WIKI_DIR defaults to docs/second-brain/wiki (relative to repo root)
"""
import sys, os
from datetime import datetime
from pathlib import Path
from typing import List
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.memory_ingest import get_repo_root, chunk_text, get_embedding, deterministic_id, print_report

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def report_success(pages_ingested: int, chunk_count: int, qdrant_ok: bool):
    print_report("WIKI INGEST REPORT", [
        f"Status: {'SUCCESS' if qdrant_ok else 'PARTIAL'}",
        f"Pages ingested: {pages_ingested}",
        f"Total chunks: {chunk_count}",
        f"Qdrant upsert: {'OK' if qdrant_ok else 'FAILED'}",
    ])


def report_failure(stage: str, reason: str):
    print_report("WIKI INGEST REPORT", [
        "Status: FAILED",
        f"Stage: {stage}",
        f"Reason: {reason}",
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

OLLAMA_URL = os.getenv("OLLAMA_HOST", "http://localhost:11434")
QDRANT_HOST = os.getenv("QDRANT_HOST", "localhost")
QDRANT_PORT = int(os.getenv("QDRANT_PORT", "6333"))
COLLECTION_NAME = os.getenv("WIKI_PAGES_COLLECTION", "wiki_pages")
CHUNK_SIZE = 512
OVERLAP = 50
MAX_WORKERS = 4

REPO_ROOT = get_repo_root()
WIKI_DIR = REPO_ROOT / os.getenv("WIKI_DIR", "docs/second-brain/wiki")
EXCLUDED_FILES = {
    "_INDEX.md",
    "_SEARCH_INDEX.md",
    "_LOG.md",
    "_IMPROVEMENT_QUEUE.md",
    "_SCHEMA.md",
}


def extract_frontmatter(content: str) -> tuple[dict, str]:
    fm = {}
    body = content
    if not content.startswith("---"):
        return fm, body
    parts = content.split("---", 2)
    if len(parts) < 3:
        return fm, body
    for line in parts[1].strip().splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip()
    return fm, parts[2]


def main():
    if not WIKI_DIR.exists():
        report_failure("Input", f"Wiki directory not found: {WIKI_DIR}")
        sys.exit(1)

    client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT, check_compatibility=False)

    md_files = sorted(WIKI_DIR.rglob("*.md"))
    total_chunks = 0
    pages_ingested = 0

    # Collect all chunks first for parallel embedding
    all_jobs = []  # (page_path, page_title, fm, chunk_index, chunk_text, total_chunks)
    for md_path in md_files:
        if md_path.name in EXCLUDED_FILES:
            continue

        page_path = md_path.relative_to(REPO_ROOT).as_posix()
        page_title = md_path.stem

        with open(md_path, "r", encoding="utf-8") as f:
            content = f.read()

        fm, body = extract_frontmatter(content)
        chunks = chunk_text(body, CHUNK_SIZE, OVERLAP)
        if not chunks:
            continue

        for i, chunk in enumerate(chunks):
            all_jobs.append((page_path, page_title, fm, i, chunk, len(chunks)))

    if not all_jobs:
        report_success(0, 0, True)
        sys.exit(0)

    # Parallel embedding generation
    print(f"[info] Embedding {len(all_jobs)} chunks via Ollama (workers={MAX_WORKERS})...")
    embedding_map = {}  # key -> (embedding, Exception)
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_key = {}
        for page_path, page_title, fm, i, chunk, total in all_jobs:
            key = (page_path, i)
            future = executor.submit(get_embedding, chunk, OLLAMA_URL)
            future_to_key[future] = key

        for future in as_completed(future_to_key):
            key = future_to_key[future]
            try:
                embedding_map[key] = future.result()
            except Exception as e:
                embedding_map[key] = e

    # Group by page_path for idempotent delete + upsert
    pages = {}
    for page_path, page_title, fm, i, chunk, total in all_jobs:
        key = (page_path, i)
        emb = embedding_map.get(key)
        if isinstance(emb, Exception):
            print(f"[warn] embedding failed for {page_path} chunk {i}: {emb}")
            continue
        pages.setdefault(page_path, []).append({
            "page_title": page_title,
            "fm": fm,
            "chunk_index": i,
            "chunk": chunk,
            "total_chunks": total,
            "embedding": emb,
        })

    for page_path, chunks_data in pages.items():
        # Delete existing points for this page
        try:
            client.delete(
                collection_name=COLLECTION_NAME,
                points_selector=Filter(
                    must=[FieldCondition(key="page_path", match=MatchValue(value=page_path))]
                ),
            )
        except Exception as e:
            print(f"[warn] delete failed for {page_path}: {e}")

        points = []
        for cd in chunks_data:
            point_id = deterministic_id(page_path, cd["chunk_index"])
            fm = cd["fm"]
            page_type = fm.get("type", "concept")
            tags_raw = fm.get("tags", "")
            tags = [t.strip().strip("'\"[]") for t in tags_raw.split(",") if t.strip()] if tags_raw else []
            date_updated = fm.get("date_updated", datetime.now().strftime("%Y-%m-%d"))
            points.append(
                PointStruct(
                    id=point_id,
                    vector=cd["embedding"],
                    payload={
                        "text": cd["chunk"],
                        "page_path": page_path,
                        "page_title": cd["page_title"],
                        "page_type": page_type,
                        "tags": tags,
                        "date_updated": date_updated,
                        "chunk_index": cd["chunk_index"],
                        "total_chunks": cd["total_chunks"],
                    },
                )
            )

        try:
            client.upsert(collection_name=COLLECTION_NAME, points=points)
            total_chunks += len(points)
            pages_ingested += 1
            print(f"  Ingested: {page_path} ({len(points)} chunks)")
        except Exception as e:
            print(f"[warn] upsert failed for {page_path}: {e}")

    qdrant_ok = total_chunks > 0
    report_success(pages_ingested, total_chunks, qdrant_ok)
    sys.exit(0 if qdrant_ok else 1)


if __name__ == "__main__":
    main()
