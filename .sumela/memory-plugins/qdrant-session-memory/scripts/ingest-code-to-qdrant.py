#!/usr/bin/env python3
"""
ingest-code-to-qdrant.py — Source Code Ingestion Pipeline (v1.1)

Usage:
    python .sumela/memory-plugins/qdrant-session-memory/scripts/ingest-code-to-qdrant.py

What it does:
    1. Walks src/ for code files (.cs, .ts, .tsx, .py, .go, .rs, .java, .js, .jsx).
    2. Excludes build artifacts, dependencies, generated files, and secrets.
    3. Reads file contents and chunks if > 512 tokens.
    4. Generates embeddings via Ollama (qwen3-embedding:0.6b) in parallel.
    5. Deletes existing points for the file (idempotency) and upserts new chunks
       into Qdrant 'code_chunks' collection with structured payload.
    6. Prints a structured status report for the agent to relay to the user.

Payload schema per point:
    text          : str    (the chunk body)
    file_path     : str    (relative path from repo root)
    file_type     : str    (extension without dot)
    chunk_index   : int
    total_chunks  : int

Environment:
    OLLAMA_HOST defaults to http://localhost:11434
    QDRANT_HOST defaults to localhost:6333
    QDRANT_PORT defaults to 6333
    CODE_CHUNKS_COLLECTION defaults to code_chunks
    SRC_DIR defaults to src (relative to repo root)
    CODE_PATTERNS defaults to *.cs,*.ts,*.tsx,*.py,*.go,*.rs,*.java,*.js,*.jsx
"""
import sys, os, fnmatch
from pathlib import Path
from typing import List
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.memory_ingest import get_repo_root, chunk_text, get_embedding, deterministic_id, print_report

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def report_success(files_ingested: int, chunk_count: int, qdrant_ok: bool):
    print_report("CODE INGEST REPORT", [
        f"Status: {'SUCCESS' if qdrant_ok else 'PARTIAL'}",
        f"Files ingested: {files_ingested}",
        f"Total chunks: {chunk_count}",
        f"Qdrant upsert: {'OK' if qdrant_ok else 'FAILED'}",
    ])


def report_failure(stage: str, reason: str):
    print_report("CODE INGEST REPORT", [
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
COLLECTION_NAME = os.getenv("CODE_CHUNKS_COLLECTION", "code_chunks")
CHUNK_SIZE = 512
OVERLAP = 50
MAX_WORKERS = 4

REPO_ROOT = get_repo_root()
SRC_DIR = REPO_ROOT / os.getenv("SRC_DIR", "src")
CODE_PATTERNS = tuple(
    p.strip()
    for p in os.getenv(
        "CODE_PATTERNS",
        "*.cs,*.ts,*.tsx,*.py,*.go,*.rs,*.java,*.js,*.jsx",
    ).split(",")
)

EXCLUDED_DIRS = {
    "bin",
    "obj",
    "node_modules",
    "dist",
    "build",
    ".venv",
    "venv",
    "__pycache__",
    "site-packages",
    ".git",
    ".idea",
    ".vscode",
}

EXCLUDED_PATTERNS = (
    "*.generated.*",
    "*.designer.*",
    "*.min.js",
    "*.min.css",
)

SECRET_PATTERNS = (
    ".env",
    ".env.*",
    "appsettings*.json",
    "secrets.json",
    "*.key",
    "*.pem",
    "*.pfx",
    "*.p12",
    "*.mobileprovision",
)


def should_skip_file(file_path: Path) -> bool:
    """Return True if the file should not be ingested."""
    name = file_path.name
    parts = set(file_path.parts)

    if parts & EXCLUDED_DIRS:
        return True

    for pat in EXCLUDED_PATTERNS:
        if fnmatch.fnmatch(name, pat):
            return True

    for pat in SECRET_PATTERNS:
        if fnmatch.fnmatch(name, pat):
            return True

    return False


def main():
    if not SRC_DIR.exists():
        report_failure("Input", f"Source directory not found: {SRC_DIR}")
        sys.exit(1)

    client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT, check_compatibility=False)

    code_files = []
    for pattern in CODE_PATTERNS:
        code_files.extend(SRC_DIR.rglob(pattern))
    code_files = sorted(set(code_files))

    # Collect all chunks first for parallel embedding
    all_jobs = []  # (rel_path, file_type, chunk_index, chunk_text, total_chunks)
    for code_path in code_files:
        if should_skip_file(code_path):
            continue

        rel_path = code_path.relative_to(REPO_ROOT).as_posix()
        file_type = code_path.suffix.lstrip(".")

        with open(code_path, "r", encoding="utf-8") as f:
            content = f.read()

        if not content.strip():
            continue

        chunks = chunk_text(content, CHUNK_SIZE, OVERLAP)
        if not chunks:
            continue

        for i, chunk in enumerate(chunks):
            all_jobs.append((rel_path, file_type, i, chunk, len(chunks)))

    if not all_jobs:
        report_success(0, 0, True)
        sys.exit(0)

    # Parallel embedding generation
    print(f"[info] Embedding {len(all_jobs)} chunks via Ollama (workers={MAX_WORKERS})...")
    embedding_map = {}
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_key = {}
        for rel_path, file_type, i, chunk, total in all_jobs:
            key = (rel_path, i)
            future = executor.submit(get_embedding, chunk, OLLAMA_URL)
            future_to_key[future] = key

        for future in as_completed(future_to_key):
            key = future_to_key[future]
            try:
                embedding_map[key] = future.result()
            except Exception as e:
                embedding_map[key] = e

    # Group by rel_path for idempotent delete + upsert
    files = {}
    for rel_path, file_type, i, chunk, total in all_jobs:
        key = (rel_path, i)
        emb = embedding_map.get(key)
        if isinstance(emb, Exception):
            print(f"[warn] embedding failed for {rel_path} chunk {i}: {emb}")
            continue
        files.setdefault(rel_path, []).append({
            "file_type": file_type,
            "chunk_index": i,
            "chunk": chunk,
            "total_chunks": total,
            "embedding": emb,
        })

    total_chunks = 0
    files_ingested = 0

    for rel_path, chunks_data in files.items():
        # Delete existing points for this file
        try:
            client.delete(
                collection_name=COLLECTION_NAME,
                points_selector=Filter(
                    must=[FieldCondition(key="file_path", match=MatchValue(value=rel_path))]
                ),
            )
        except Exception as e:
            print(f"[warn] delete failed for {rel_path}: {e}")

        points = []
        for cd in chunks_data:
            point_id = deterministic_id(rel_path, cd["chunk_index"])
            points.append(
                PointStruct(
                    id=point_id,
                    vector=cd["embedding"],
                    payload={
                        "text": cd["chunk"],
                        "file_path": rel_path,
                        "file_type": cd["file_type"],
                        "chunk_index": cd["chunk_index"],
                        "total_chunks": cd["total_chunks"],
                    },
                )
            )

        try:
            client.upsert(collection_name=COLLECTION_NAME, points=points)
            total_chunks += len(points)
            files_ingested += 1
            print(f"  Ingested: {rel_path} ({len(points)} chunks)")
        except Exception as e:
            print(f"[warn] upsert failed for {rel_path}: {e}")

    qdrant_ok = total_chunks > 0
    report_success(files_ingested, total_chunks, qdrant_ok)
    sys.exit(0 if qdrant_ok else 1)


if __name__ == "__main__":
    main()
