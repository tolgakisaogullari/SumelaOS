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
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.memory_ingest import (
    COLLECTION_BASES, resolved_collection, resolve_collection_arg, collection_or_alias_exists,
)

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

# Logical bases → purpose. The physical, per-project collection name is resolved at
# runtime (see lib.memory_ingest.resolved_collection) so two projects on one shared
# Qdrant instance never share a collection.
COLLECTION_PURPOSE = {
    "chat_history": "Conversational session memory — session-summary chunks for past-decision recall",
    "wiki_pages":   "Curated wiki content — ADRs, entity defs, sprint plans, concept pages",
    "code_chunks":  "Source code semantic chunks — file-level and symbol-level for code search",
}


def main():
    parser = argparse.ArgumentParser(
        description="Bootstrap Qdrant collections for the memory stack."
    )
    parser.add_argument("--host", default=os.getenv("QDRANT_HOST", "localhost"),
                        help="Qdrant host (default: localhost or QDRANT_HOST env)")
    parser.add_argument("--port", type=int, default=int(os.getenv("QDRANT_PORT", "6333")),
                        help="Qdrant port (default: 6333 or QDRANT_PORT env)")
    parser.add_argument("--collection", default=None,
                        help="Create only this base (chat_history|wiki_pages|code_chunks); "
                             "default: create all three.")
    args = parser.parse_args()

    client = QdrantClient(host=args.host, port=args.port)

    bases = list(COLLECTION_BASES)
    if args.collection:
        # Accept either a logical base or an already-resolved physical name; map back
        # to the base so we can look up its purpose.
        match = [b for b in COLLECTION_BASES
                 if args.collection == b or args.collection == resolved_collection(b)]
        if not match:
            print(f"ERROR: Unknown collection '{args.collection}'. Available bases: {list(COLLECTION_BASES)}")
            sys.exit(1)
        bases = match

    created = 0
    for base in bases:
        name = resolved_collection(base)
        if collection_or_alias_exists(client, name):
            print(f"[skip] '{name}' already exists.")
            continue
        client.create_collection(
            collection_name=name,
            vectors_config=VectorParams(size=EMBED_DIM, distance=DISTANCE),
        )
        print(f"[ok]   '{name}' created — {COLLECTION_PURPOSE[base]}")
        created += 1

    print(f"\nDone. {created} new collection(s); {len(bases) - created} existed.")


if __name__ == "__main__":
    main()
