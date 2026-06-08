"""
scripts/lib/memory_ingest.py — Shared ingestion utilities (v1.0)

Common helpers for wiki and code ingestion pipelines.
"""
import sys, os, re, hashlib, uuid
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


# Hostile / non-relative path patterns rejected before any filesystem touch.
# These directories the project OWNS — there is no legitimate need for globs,
# absolute/UNC/drive-qualified paths, home expansion, leading-dash (option
# injection), backslashes, quotes, or control chars. Reject them all.
_BAD_PATH_CHARS = set('*?[]"\'\\\x00')
_DRIVE_RE = re.compile(r"^[A-Za-z]:")


def get_extra_ingest_dirs(repo_root: Path) -> List[Path]:
    """Resolve the project-configured EXTRA documentation ingest directories.

    Precedence (first non-empty wins):
      1. env EXTRA_INGEST_DIRS (comma- or colon-separated, repo-relative paths)
      2. .sumela/ingest.conf — one repo-relative path per line; `#` comments and
         blank lines ignored
      3. empty (the framework default — no extra dirs)

    Mechanism in the framework, policy/values in the consumer: the framework ships
    NO paths. Every configured path is validated and must:
      * be repo-relative (no absolute, `~`, drive-letter, UNC, or backslash),
      * contain no `.`/`..`/empty segments, glob chars, quotes, or control chars,
      * resolve to a real directory STRICTLY INSIDE repo_root (symlink targets are
        resolved, so a symlinked dir pointing outside the repo is rejected),
      * not be repo_root itself.
    Invalid or missing paths are skipped with a warning on stderr; this never
    raises (best-effort, clean-tree contract shared with the wiki sync).

    Returns a de-duplicated, order-stable list of absolute Paths inside repo_root.
    """
    repo_root = repo_root.resolve()
    raw: List[str] = []
    env = os.getenv("EXTRA_INGEST_DIRS")
    if env and env.strip():
        raw = re.split(r"[,:]", env)
    else:
        conf = repo_root / ".sumela" / "ingest.conf"
        if conf.is_file():
            for line in conf.read_text(encoding="utf-8").splitlines():
                s = line.strip()
                if s and not s.startswith("#"):
                    raw.append(s)

    out: List[Path] = []
    seen = set()
    for item in raw:
        s = item.strip()
        if not s:
            continue
        if (s[0] in "/~-" or _DRIVE_RE.match(s)
                or any(c in _BAD_PATH_CHARS for c in s)
                or any(ord(c) < 32 for c in s)):
            _warn(f"extra ingest path rejected (must be a simple repo-relative dir): {item!r}")
            continue
        if any(seg in ("", ".", "..") for seg in s.split("/")):
            _warn(f"extra ingest path rejected ('.'/'..'/empty segment): {item!r}")
            continue
        cand = (repo_root / s).resolve()
        if cand == repo_root or repo_root not in cand.parents:
            _warn(f"extra ingest path escapes or equals repo root, skipped: {item!r}")
            continue
        if not cand.is_dir():
            _warn(f"extra ingest path not found (skipped): {item!r}")
            continue
        if cand in seen:
            continue
        seen.add(cand)
        out.append(cand)
    return out


def _warn(msg: str) -> None:
    print(f"[warn] {msg}", file=sys.stderr)


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
