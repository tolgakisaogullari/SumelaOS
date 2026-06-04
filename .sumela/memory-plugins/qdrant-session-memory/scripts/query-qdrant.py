#!/usr/bin/env python3
"""
query-qdrant.py — Semantic Search over Qdrant Collections (v1.0-agnostic)

Usage:
    python query-qdrant.py "why was sprint 12 following feed chosen"
    python query-qdrant.py "what did we discuss last week" --limit 3 --threshold 0.75
    python query-qdrant.py "what does AuthService do" --collection code_vectors
    # Per-developer / per-domain / per-date filters (session-summary metadata):
    python query-qdrant.py "card limit" --developer "Tolga" --domain Card     # filtered semantic search
    python query-qdrant.py "*" --developer "Tolga" --since 2026-06-01         # FILTER-ONLY listing (all matches)
    python query-qdrant.py "" --domain Card --since 2026-06-01 --until 2026-06-07

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
    from qdrant_client.models import ScoredPoint, Filter, FieldCondition, MatchValue, Range
except ImportError:
    report_failure("Dependency", "qdrant-client not installed. Run: pip install qdrant-client")
    sys.exit(1)


def _iso_to_int(d: str):
    """'2026-06-04' -> 20260604, else None."""
    from datetime import datetime
    try:
        return int(datetime.strptime(d.strip(), "%Y-%m-%d").strftime("%Y%m%d"))
    except (ValueError, AttributeError):
        return None


def build_filter(developer: str = "", domain: str = "", since: str = "", until: str = ""):
    """Build a Qdrant Filter from session-summary payload fields (chat_history).

    developer/domain -> exact match (domains is a list; Qdrant matches array membership).
    since/until -> Range on the integer `date_int` field (YYYYMMDD). Returns None if no
    filter was requested.
    """
    must = []
    if developer:
        must.append(FieldCondition(key="developer", match=MatchValue(value=developer)))
    if domain:
        must.append(FieldCondition(key="domains", match=MatchValue(value=domain)))
    gte = _iso_to_int(since) if since else None
    lte = _iso_to_int(until) if until else None
    if gte is not None or lte is not None:
        must.append(FieldCondition(key="date_int", range=Range(gte=gte, lte=lte)))
    return Filter(must=must) if must else None

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
    query_vector,
    collection: str,
    limit: int,
    threshold: float,
    host: str,
    port: int,
    query_filter=None,
) -> tuple[list, int]:
    """Semantic search (optionally filtered) when query_vector is given; pure
    metadata listing via scroll when query_vector is None (filter-only mode)."""
    client = QdrantClient(host=host, port=port, check_compatibility=False)

    collections = [c.name for c in client.get_collections().collections]
    if collection not in collections:
        raise ValueError(f"Collection '{collection}' not found. Available: {collections}")

    if query_vector is None:
        # Filter-only listing: gather ALL points matching the filter (not top-K), paging
        # through scroll until exhausted — e.g. "everything developer X did last week".
        # A session is chunked into many points, so we must not stop at the first page;
        # the caller dedups by session_id. HARD_CAP guards against a runaway scan.
        HARD_CAP = 10000
        results = []
        offset = None
        while True:
            batch, offset = client.scroll(
                collection_name=collection,
                scroll_filter=query_filter,
                limit=256,
                offset=offset,
                with_payload=True,
                with_vectors=False,
            )
            results.extend(batch)
            if offset is None or len(results) >= HARD_CAP:
                break
    else:
        response = client.query_points(
            collection_name=collection,
            query=query_vector,
            query_filter=query_filter,
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
    parser.add_argument("query", nargs="?", default="",
                        help="Search query text. Omit (or pass '*') for a FILTER-ONLY listing "
                             "(lists ALL points matching the --developer/--domain/--since/--until "
                             "filter, not top-K by similarity).")
    parser.add_argument("--collection", default=DEFAULT_COLLECTION,
                        help=f"Qdrant collection name (default: {DEFAULT_COLLECTION})")
    parser.add_argument("--limit", type=int, default=None,
                        help=f"Max results. Semantic search default {DEFAULT_LIMIT}; filter-only "
                             "listing default = ALL matching sessions (deduped).")
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD,
                        help="Minimum similarity score (0-1), default 0 = no filter")
    parser.add_argument("--developer", default="",
                        help="Filter to a developer (exact match on the `developer` payload field).")
    parser.add_argument("--domain", default="",
                        help="Filter to a domain (matches membership of the `domains` list).")
    parser.add_argument("--since", default="",
                        help="Filter to sessions on/after this ISO date (YYYY-MM-DD).")
    parser.add_argument("--until", default="",
                        help="Filter to sessions on/before this ISO date (YYYY-MM-DD).")
    parser.add_argument("--json", action="store_true",
                        help="Output raw JSON instead of human-readable report")
    parser.add_argument("--host", default=os.getenv("QDRANT_HOST", "localhost"),
                        help="Qdrant host (default: localhost or QDRANT_HOST env)")
    parser.add_argument("--port", type=int, default=int(os.getenv("QDRANT_PORT", "6333")),
                        help="Qdrant port (default: 6333 or QDRANT_PORT env)")
    parser.add_argument("--ollama-url", default=os.getenv("OLLAMA_URL", "http://localhost:11434"),
                        help="Ollama base URL (default: http://localhost:11434 or OLLAMA_URL env)")
    args = parser.parse_args()

    query_filter = build_filter(args.developer, args.domain, args.since, args.until)
    query_text = args.query.strip()
    filter_only = query_text in ("", "*")

    if filter_only and query_filter is None:
        report_failure("Input", "Provide a query, or a filter (--developer/--domain/--since/--until) "
                                "for a filter-only listing.")
        sys.exit(1)

    embedding = None
    if not filter_only:
        try:
            embedding = get_embedding(query_text, args.ollama_url)
        except Exception as e:
            report_failure("Ollama Embedding", str(e))
            sys.exit(1)

    try:
        results, total_chunks = query_qdrant(
            query_vector=embedding,
            collection=args.collection,
            limit=(args.limit if args.limit is not None else DEFAULT_LIMIT),
            threshold=args.threshold,
            host=args.host,
            port=args.port,
            query_filter=query_filter,
        )
    except Exception as e:
        report_failure("Qdrant Search", str(e))
        sys.exit(1)

    truncated = 0
    if filter_only:
        # Collapse chunks → one row per session (keep the lowest chunk_index as the
        # representative), newest first. Then apply --limit as a max-SESSIONS cap
        # (default: show all). This is what makes "everything X did" complete.
        def _ci(r):
            c = r.payload.get("chunk_index")
            return c if isinstance(c, int) else float("inf")  # missing index never wins over a real chunk 0
        by_session = {}
        for r in results:
            sid = r.payload.get("session_id")
            if sid not in by_session or _ci(r) < _ci(by_session[sid]):
                by_session[sid] = r
        # `or ""` (not get default) so an explicit None `date` can't crash the sort;
        # session_id is a stable tiebreaker for same-date sessions.
        results = sorted(
            by_session.values(),
            key=lambda r: (r.payload.get("date") or "", r.payload.get("session_id") or ""),
            reverse=True,
        )
        if args.limit is not None and args.limit > 0 and len(results) > args.limit:
            truncated = len(results) - args.limit
            results = results[: args.limit]

    if args.json:
        payload = [
            {
                "score": getattr(r, "score", None),   # None in filter-only (scroll) mode
                "session_id": r.payload.get("session_id"),
                "date": r.payload.get("date"),
                "developer": r.payload.get("developer"),
                "developer_email": r.payload.get("developer_email"),
                "domains": r.payload.get("domains"),
                "spec_artifact": r.payload.get("spec_artifact"),
                "plan_artifact": r.payload.get("plan_artifact"),
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
        query=(query_text or "(filter-only listing)"),
        collection=args.collection,
        results_count=len(results),
        total_chunks=total_chunks,
    )

    for i, r in enumerate(results, 1):
        sid = r.payload.get("session_id", "n/a")
        date = r.payload.get("date", "n/a")
        dev = r.payload.get("developer", "n/a")
        domains = r.payload.get("domains", [])
        spec = r.payload.get("spec_artifact", "")
        plan = r.payload.get("plan_artifact", "")
        topics = r.payload.get("topics", [])
        text = r.payload.get("text", "")
        score = getattr(r, "score", None)
        header = f"(score: {score:.4f})" if score is not None else "(filter match)"
        print(f"\n--- Result {i} {header} ---")
        print(f"Session  : {sid}")
        print(f"Date     : {date}")
        print(f"Developer: {dev}")
        print(f"Domains  : {', '.join(domains) if domains else 'n/a'}")
        if spec:
            print(f"Spec     : {spec}")
        if plan:
            print(f"Plan     : {plan}")
        print(f"Topics   : {', '.join(topics) if topics else 'n/a'}")
        print(f"Text     : {text[:500]}{'...' if len(text) > 500 else ''}")

    if filter_only:
        print(f"\n[{len(results)} session(s) matched the filter "
              f"({total_chunks} total chunk(s) in '{args.collection}', unfiltered)]")
        if truncated:
            print(f"[NOTE: {truncated} more matching session(s) hidden by --limit; "
                  f"raise --limit or omit it to see all.]")
    else:
        print(f"\n[{len(results)} result(s) from {total_chunks} total chunk(s) in '{args.collection}']")
    sys.exit(0)


if __name__ == "__main__":
    main()
