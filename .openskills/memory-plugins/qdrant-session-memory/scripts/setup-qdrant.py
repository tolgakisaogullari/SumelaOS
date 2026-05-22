#!/usr/bin/env python3
"""
setup-qdrant.py — Multi-collection bootstrap for Qdrant memory stack (v2.3-agnostic).

Creates three collections (idempotent — skips existing ones):
  - chat_history   : conversational session memory (session-summary chunks)
  - wiki_pages     : curated wiki page chunks (decisions, entities, sprint plans)
  - code_chunks    : source code semantic chunks (file/symbol-level)

All collections use 1024-dim cosine vectors to match Qwen3-Embedding-0.6B.

Usage:
    python setup-qdrant.py
    python setup-qdrant.py --host my-qdrant --port 6333
    python setup-qdrant.py --collection chat_history  # create single collection

Environment:
    QDRANT_HOST  — Qdrant host (default: localhost)
    QDRANT_PORT  — Qdrant port (default: 6333)
"""
import sys
import os
import argparse

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

try:
    from qdrant_client import QdrantClient
    from qdrant_client.models import Distance, VectorParams
except ImportError:
    print("ERROR: qdrant-client not installed. Run: pip install qdrant-client")
    sys.exit(1)

EMBED_DIM = 1024  # Qwen3-Embedding-0.6B
DISTANCE = Distance.COSINE

COLLECTIONS = [
    ("chat_history", "Conversational session memory — session-summary chunks for past-decision recall"),
    ("wiki_pages",   "Curated wiki content — ADRs, entity defs, sprint plans, concept pages"),
    ("code_chunks",  "Source code semantic chunks — file-level and symbol-level for code search"),
]


def main():
    parser = argparse.ArgumentParser(
        description="Bootstrap Qdrant collections for the memory stack."
    )
    parser.add_argument("--host", default=os.getenv("QDRANT_HOST", "localhost"),
                        help="Qdrant host (default: localhost or QDRANT_HOST env)")
    parser.add_argument("--port", type=int, default=int(os.getenv("QDRANT_PORT", "6333")),
                        help="Qdrant port (default: 6333 or QDRANT_PORT env)")
    parser.add_argument("--collection", default=None,
                        help="Create only this collection (default: create all three)")
    args = parser.parse_args()

    client = QdrantClient(host=args.host, port=args.port)

    collections = COLLECTIONS
    if args.collection:
        collections = [(n, d) for n, d in COLLECTIONS if n == args.collection]
        if not collections:
            print(f"ERROR: Unknown collection '{args.collection}'. Available: {[n for n, _ in COLLECTIONS]}")
            sys.exit(1)

    created = 0
    for name, purpose in collections:
        if client.collection_exists(name):
            print(f"[skip] '{name}' already exists.")
            continue
        client.create_collection(
            collection_name=name,
            vectors_config=VectorParams(size=EMBED_DIM, distance=DISTANCE),
        )
        print(f"[ok]   '{name}' created — {purpose}")
        created += 1

    print(f"\nDone. {created} new collection(s); {len(collections) - created} existed.")


if __name__ == "__main__":
    main()
