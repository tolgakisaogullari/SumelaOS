"""
scripts/lib/memory_ingest.py — Shared ingestion utilities (v1.0)

Common helpers for wiki and code ingestion pipelines.
"""
import sys, os, re, hashlib, uuid
from pathlib import Path
from typing import List

# --- qdrant-client version preflight ----------------------------------------
# The scripts use APIs added in qdrant-client 1.12 (check_compatibility=,
# get_aliases, update_collection_aliases, count(exact=)). A `git pull` that bumps
# requirements.txt does NOT touch a developer's venv, so a teammate on an older
# client would otherwise hit a raw traceback (migration) or a silent-empty
# retrieval (resolver points at a namespaced collection migration never created).
# Every entry script preflights this and prints ONE actionable line instead.
REQUIRED_QDRANT_CLIENT = (1, 12, 0)


def qdrant_client_status() -> "tuple[str, str | None]":
    """('ok' | 'old' | 'missing', installed_version_or_None). 'old' when the installed
    qdrant-client predates REQUIRED_QDRANT_CLIENT. Never raises."""
    try:
        import qdrant_client  # noqa: F401
    except Exception:
        return ("missing", None)
    try:
        from importlib.metadata import version, PackageNotFoundError
        try:
            v = version("qdrant-client")
        except PackageNotFoundError:
            return ("ok", None)  # importable but no dist metadata — don't false-alarm
    except Exception:
        return ("ok", None)
    nums = re.findall(r"\d+", v)
    parts = tuple(int(n) for n in nums[:3])
    return ("old", v) if parts < REQUIRED_QDRANT_CLIENT else ("ok", v)


def qdrant_client_preflight() -> "str | None":
    """None when the client is OK; otherwise a one-line, actionable message string
    (no traceback) that an entry script can print/report before exiting."""
    status, v = qdrant_client_status()
    if status == "ok":
        return None
    req = ".".join(map(str, REQUIRED_QDRANT_CLIENT))
    if status == "missing":
        return (f"SumelaOS memory: qdrant-client not installed (need >={req}). "
                f"Run: bash scripts/setup-memory.sh")
    return (f"SumelaOS memory: qdrant-client {v} is too old (need >={req}). "
            f"Run: bash scripts/setup-memory.sh")

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


# --- Per-project collection namespacing -------------------------------------
# A single Qdrant instance is shared across EVERY SumelaOS project on a machine
# (one `sumela-qdrant` container). The three logical collections (chat_history,
# wiki_pages, code_chunks) must therefore be namespaced per-project, or two
# projects silently intermingle their chunks AND a prune in project Y deletes a
# same-path point in project X (file_path/page_path are repo-relative, so
# `src/index.ts` collides). We derive a stable per-install slug and expose every
# collection as `{slug}__{base}`.
#
# Single source of truth: ALL scripts resolve a logical base name through
# resolve_collection_arg(), so the prefix is computed in exactly ONE place (never
# re-derived in bash). The three bare base names are treated as logical aliases
# that resolve to the physical, namespaced collection — callers (skills, hooks)
# keep passing `code_chunks` and get isolation for free.
COLLECTION_BASES = ("chat_history", "wiki_pages", "code_chunks")

# Per-base env override (full physical name). Honored for back-compat / power
# users who pin an explicit collection; otherwise the namespaced default wins.
_BASE_ENV = {
    "chat_history": "QDRANT_COLLECTION",
    "wiki_pages": "WIKI_PAGES_COLLECTION",
    "code_chunks": "CODE_CHUNKS_COLLECTION",
}


def _sanitize_slug(name: str, max_len: "int | None" = 32) -> str:
    """Reduce an arbitrary string to a Qdrant-safe, stable slug component:
    lowercase ASCII [a-z0-9-], runs collapsed to a single '-', trimmed, optionally
    capped at max_len chars. Returns '' if nothing survives (the DERIVE path falls
    back + always appends a full-strength hash, so an empty/degenerate basename never
    collides). The env-override path passes max_len=None: an explicit user prefix must
    NOT be silently truncated, or two distinct long prefixes sharing a 32-char head
    would collapse to the same collection namespace."""
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    if max_len is not None:
        s = s[:max_len]
    return s.strip("-")


def _slug_file(repo_root: Path) -> Path:
    # Gitignored (see scripts/lib/sumela-gitignore.list → .sumela/_migration/), so
    # the slug is machine-local and never committed. Persisted ONCE: re-deriving on
    # every run would silently re-bucket a project into a fresh empty collection the
    # day the derivation algorithm changes in an upgrade — persisting pins it.
    return repo_root / ".sumela" / "_migration" / "collection-prefix"


# Cache keyed by (install root, env-prefix) so changing SUMELA_COLLECTION_PREFIX within
# one process is honored rather than returning a stale first-seen slug.
_slug_cache: "dict[tuple, str]" = {}


def _persist_slug(root: Path, slug: str) -> None:
    """Write the DERIVED slug to the prefix file so the bash pull-hook gate can read it
    WITHOUT re-deriving (closing the two-language drift gap). Only the derived slug is
    persisted — never the SUMELA_COLLECTION_PREFIX env value, or a one-off env use would
    become STICKY (silently re-bucketing the project after the env is unset). For an
    env pin the bash gate's slug won't match the marker and it harmlessly re-runs the
    (idempotent, state-gated) migration. Best-effort + a no-op when already current."""
    f = _slug_file(root)
    try:
        if f.is_file() and f.read_text(encoding="utf-8").strip() == slug:
            return
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(slug + "\n", encoding="utf-8")
    except OSError:
        pass  # best-effort; an unwritable .sumela just means we re-derive (same value)


def project_slug(repo_root: "Path | None" = None) -> str:
    """Stable per-install collection-prefix slug.

    Precedence: SUMELA_COLLECTION_PREFIX env (explicit, wins) → persisted
    .sumela/_migration/collection-prefix → derive from the install root's basename
    + an 8-hex digest of its absolute path. The effective slug is then persisted (so
    the bash hook gate reads it rather than re-deriving) and cached per process. The
    install root (the dir containing .sumela, via get_repo_root) is the project
    identity: it distinguishes sibling monorepo-subdir installs that share one git
    toplevel, which a git-toplevel-based slug would wrongly collide.
    """
    root = (repo_root or get_repo_root()).resolve()
    env = (os.getenv("SUMELA_COLLECTION_PREFIX") or "").strip()
    key = (str(root), env)
    if key in _slug_cache:
        return _slug_cache[key]

    if env:
        # Explicit user pin — sanitize but do NOT truncate (avoid two long prefixes
        # colliding on a shared 32-char head). NOT persisted (see _persist_slug).
        slug = _sanitize_slug(env, max_len=None) or "default"
    else:
        slug = ""
        f = _slug_file(root)
        try:
            if f.is_file():
                slug = f.read_text(encoding="utf-8").strip()
        except OSError:
            slug = ""
        if not slug:
            base = _sanitize_slug(root.name) or "repo"
            digest = hashlib.sha256(str(root).encode("utf-8")).hexdigest()[:8]
            slug = f"{base}-{digest}"
        _persist_slug(root, slug)  # persist only the DERIVED slug, never the env pin

    _slug_cache[key] = slug
    return slug


def resolved_collection(base: str, repo_root: "Path | None" = None) -> str:
    """Physical collection name for a logical base. A per-base env override (full
    name) wins for back-compat; otherwise `{project_slug}__{base}`."""
    override = os.getenv(_BASE_ENV.get(base, ""), "")
    if override and override.strip():
        return override.strip()
    return f"{project_slug(repo_root)}__{base}"


def collection_or_alias_exists(client, name: str, aliases=None) -> bool:
    """True if `name` exists as a collection OR as an alias. An ADOPTED legacy
    collection is reachable only through an alias of the namespaced name, which a plain
    collection listing (get_collections) does NOT include — so a collection_exists-only
    check would wrongly conclude the name is free and recreate an empty collection over
    a working alias (the data-loss this feature exists to prevent). `aliases` may be a
    pre-fetched list of (alias_name, collection_name) tuples to avoid a round-trip.
    Takes a LIVE qdrant client; qdrant_client is never imported at module load here."""
    try:
        if client.collection_exists(name):
            return True
    except Exception:
        pass
    try:
        if aliases is None:
            aliases = [(a.alias_name, a.collection_name) for a in client.get_aliases().aliases]
    except Exception:
        return False
    return any(an == name for an, _ in (aliases or []))


def resolve_collection_arg(name: str, repo_root: "Path | None" = None) -> str:
    """Resolve a --collection argument: a known logical base → its namespaced
    physical name; anything else (an already-physical or custom name) → unchanged.
    This lets callers keep passing `code_chunks` while staying project-isolated."""
    if name in COLLECTION_BASES:
        return resolved_collection(name, repo_root)
    return name


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
