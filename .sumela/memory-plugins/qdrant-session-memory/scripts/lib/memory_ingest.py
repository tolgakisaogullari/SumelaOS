"""
scripts/lib/memory_ingest.py — Shared ingestion utilities (v1.0)

Common helpers for wiki and code ingestion pipelines.
"""
import sys, os, hashlib, uuid
from pathlib import Path
from typing import List

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def get_repo_root() -> Path:
    """Return the repository root.

    Robust across layouts:
      * this framework repo (plugin sits under .sumela/memory-plugins/), and
      * an adopted project where the plugin is vendored under
        .sumela/memory-plugins/<plugin>/scripts/lib/.
    Resolution order: SUMELA_REPO_ROOT env → first ancestor containing .git or a
    top-level .sumela dir → legacy three-levels-up fallback.

    The legacy "three levels up" returned the PLUGIN dir, not the repo root, in
    every layout — silently breaking wiki/code ingestion in adopted projects.
    """
    env = os.getenv("SUMELA_REPO_ROOT")
    if env:
        return Path(env).resolve()
    p = Path(__file__).resolve()
    for parent in p.parents:
        # Walking up from .sumela/memory-plugins/<plugin>/scripts/lib/, no
        # intermediate dir has a .sumela child, so the first match is the real
        # repo root (which contains <repo>/.sumela). .git covers repos that do
        # not keep .sumela at the top level. Never matches the plugin dir.
        if (parent / ".git").exists() or (parent / ".sumela").is_dir():
            return parent
    return p.parent.parent.parent


def chunk_text(text: str, size: int = 512, overlap: int = 50) -> List[str]:
    words = text.split()
    if len(words) <= size:
        return [text] if text.strip() else []
    chunks = []
    start = 0
    while start < len(words):
        end = min(start + size, len(words))
        chunks.append(" ".join(words[start:end]))
        start += size - overlap
    return chunks


def get_embedding(text: str, ollama_url: str, model: str = "qwen3-embedding:0.6b", timeout: int = 120) -> List[float]:
    import requests
    resp = requests.post(
        f"{ollama_url}/api/embeddings",
        json={"model": model, "prompt": text},
        timeout=timeout,
    )
    resp.raise_for_status()
    return resp.json()["embedding"]


def deterministic_id(key: str, chunk_index: int) -> str:
    """Generate a deterministic, process-independent UUID point ID."""
    hex_str = hashlib.sha256(f"{key}_{chunk_index}".encode("utf-8")).hexdigest()[:32]
    return str(uuid.UUID(hex=hex_str))


def print_report(title: str, summary_lines: list):
    print("\n" + "=" * 60)
    print(title)
    print("=" * 60)
    for line in summary_lines:
        print(line)
    print("=" * 60 + "\n")
