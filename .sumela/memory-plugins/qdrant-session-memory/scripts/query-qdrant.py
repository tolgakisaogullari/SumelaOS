#!/usr/bin/env python3
"""
query-qdrant.py — Semantic Search over Qdrant Collections (v1.0-agnostic)

Usage:
    python query-qdrant.py "why was sprint 12 following feed chosen"
    python query-qdrant.py "what did we discuss last week" --limit 3 --threshold 0.75
    python query-qdrant.py "what does AuthService do" --collection code_vectors
    python query-qdrant.py "test" --host my-qdrant --port 6333 --ollama-url http://gpu:11434

What it does:
    1. Generates an embedding for the query via Ollama (qwen3-embedding:0.6b).
    2. Searches the specified Qdrant collection with cosine similarity.
    3. Prints a structured report with matched chunks, scores, and metadata.

Environment:
    OLLAMA_URL       — Ollama base URL (default: http://localhost:11434)
    QDRANT_HOST      — Qdrant host (default: localhost)
    QDRANT_PORT      — Qdrant port (default: 6333)
    QDRANT_COLLECTION — Default collection name (default: chat_history)
"""
import sys
import os
import json
import argparse

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def print_report(summary_lines: list):
    print("\n" + "=" * 60)
    print("QDRANT QUERY REPORT")
    print("=" * 60)
    for line in summary_lines:
        print(line)
    print("=" * 60 + "\n")


def report_success(query: str, collection: str, results_count: int, total_chunks: int):
    print_report([
        f"Status: SUCCESS",
        f"Query: {query}",
        f"Collection: {collection}",
        f"Matches returned: {results_count}",
        f"Total chunks in collection: {total_chunks}",
        "Action for agent: Synthesize answer from matched chunks below.",
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
    from qdrant_client.models import ScoredPoint
except ImportError:
    report_failure("Dependency", "qdrant-client not installed. Run: pip install qdrant-client")
    sys.exit(1)

DEFAULT_COLLECTION = os.getenv("QDRANT_COLLECTION", "chat_history")
DEFAULT_LIMIT = 5
DEFAULT_THRESHOLD = 0.0


def get_embedding(text: str, ollama_url: str) -> list[float]:
    resp = requests.post(
        f"{ollama_url}/api/embeddings",
        json={"model": "qwen3-embedding:0.6b", "prompt": text},
        timeout=120,
    )
    resp.raise_for_status()
    return resp.json()["embedding"]


def query_qdrant(
    query_vector: list[float],
    collection: str,
    limit: int,
    threshold: float,
    host: str,
    port: int,
) -> tuple[list, int]:
    client = QdrantClient(host=host, port=port, check_compatibility=False)

    collections = [c.name for c in client.get_collections().collections]
    if collection not in collections:
        raise ValueError(f"Collection '{collection}' not found. Available: {collections}")

    response = client.query_points(
        collection_name=collection,
        query=query_vector,
        limit=limit,
        score_threshold=threshold if threshold > 0 else None,
        with_payload=True,
    )
    results = response.points

    info = client.get_collection(collection_name=collection)
    total_chunks = info.points_count

    return results, total_chunks


def main():
    parser = argparse.ArgumentParser(
        description="Semantic search over Qdrant collections via Ollama embeddings."
    )
    parser.add_argument("query", help="Search query text")
    parser.add_argument("--collection", default=DEFAULT_COLLECTION,
                        help=f"Qdrant collection name (default: {DEFAULT_COLLECTION})")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT,
                        help=f"Max results (default: {DEFAULT_LIMIT})")
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD,
                        help="Minimum similarity score (0-1), default 0 = no filter")
    parser.add_argument("--json", action="store_true",
                        help="Output raw JSON instead of human-readable report")
    parser.add_argument("--host", default=os.getenv("QDRANT_HOST", "localhost"),
                        help="Qdrant host (default: localhost or QDRANT_HOST env)")
    parser.add_argument("--port", type=int, default=int(os.getenv("QDRANT_PORT", "6333")),
                        help="Qdrant port (default: 6333 or QDRANT_PORT env)")
    parser.add_argument("--ollama-url", default=os.getenv("OLLAMA_URL", "http://localhost:11434"),
                        help="Ollama base URL (default: http://localhost:11434 or OLLAMA_URL env)")
    args = parser.parse_args()

    if not args.query or not args.query.strip():
        report_failure("Input", "Query text cannot be empty.")
        sys.exit(1)

    try:
        embedding = get_embedding(args.query.strip(), args.ollama_url)
    except Exception as e:
        report_failure("Ollama Embedding", str(e))
        sys.exit(1)

    try:
        results, total_chunks = query_qdrant(
            query_vector=embedding,
            collection=args.collection,
            limit=args.limit,
            threshold=args.threshold,
            host=args.host,
            port=args.port,
        )
    except Exception as e:
        report_failure("Qdrant Search", str(e))
        sys.exit(1)

    if args.json:
        payload = [
            {
                "score": r.score,
                "session_id": r.payload.get("session_id"),
                "date": r.payload.get("date"),
                "topics": r.payload.get("topics"),
                "text": r.payload.get("text"),
                "chunk_index": r.payload.get("chunk_index"),
                "total_chunks": r.payload.get("total_chunks"),
            }
            for r in results
        ]
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        sys.exit(0)

    report_success(
        query=args.query,
        collection=args.collection,
        results_count=len(results),
        total_chunks=total_chunks,
    )

    for i, r in enumerate(results, 1):
        sid = r.payload.get("session_id", "n/a")
        date = r.payload.get("date", "n/a")
        topics = r.payload.get("topics", [])
        text = r.payload.get("text", "")
        print(f"\n--- Result {i} (score: {r.score:.4f}) ---")
        print(f"Session : {sid}")
        print(f"Date    : {date}")
        print(f"Topics  : {', '.join(topics) if topics else 'n/a'}")
        print(f"Text    : {text[:500]}{'...' if len(text) > 500 else ''}")

    print(f"\n[{len(results)} result(s) from {total_chunks} total chunk(s) in '{args.collection}']")
    sys.exit(0)


if __name__ == "__main__":
    main()
