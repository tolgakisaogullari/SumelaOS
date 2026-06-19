#!/usr/bin/env python3
"""
migrate-collections.py — migrate a pre-namespacing Qdrant install to per-project
collections.

Before per-project namespacing, every SumelaOS project on a machine shared one
Qdrant instance AND the same three bare collections (chat_history / wiki_pages /
code_chunks). Two projects intermingled, and a prune in one could delete a
same-path point in the other. The ingest/query scripts now resolve each logical
base to `{project_slug}__{base}`. This script bridges EXISTING installs whose data
still lives in the bare collections.

For each base, given the project's resolved physical name and the legacy bare name:
  * physical already exists (collection or alias) → nothing to do (already migrated).
  * no legacy bare collection           → nothing to migrate (lazy-built later).
  * legacy bare collection exists        → decide ADOPT vs REBUILD:
      - ADOPT  (zero-copy): create an alias  physical → legacy. Used when the legacy
               data is confidently THIS project's (payload `project_slug` matches, or
               — for unstamped pre-feature data — repo-relative paths/sessions still
               exist on disk and no other project has namespaced this base yet).
      - REBUILD: create a fresh empty physical collection; existing lazy mechanisms
               (setup seed / first-pull full walk / pull-time re-ingest) repopulate
               it. Used when the legacy data looks like it belongs to ANOTHER project
               (foreign `project_slug`, low path overlap, or another project already
               aliased/namespaced this base). Never adopts another project's data.

Idempotent: records its per-(Qdrant instance, slug) decisions in
.sumela/_migration/qdrant-collections.json and no-ops on re-run. Best-effort: if
Qdrant or qdrant-client is unavailable it prints a notice and exits 0 (never fails a
caller such as update.sh / a git hook).

Usage:
    python migrate-collections.py                 # auto-decide per base, then migrate
    python migrate-collections.py --dry-run       # show intended actions, change nothing
    python migrate-collections.py --adopt         # force ADOPT for every legacy base
    python migrate-collections.py --rebuild       # force REBUILD (fresh) for every base
    python migrate-collections.py --gc            # drop orphaned legacy bare collections
    python migrate-collections.py --force         # re-evaluate even if state says done

Environment: QDRANT_HOST (default localhost), QDRANT_PORT (default 6333).
"""
import argparse
import json
import os
import re
import signal
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.memory_ingest import (
    COLLECTION_BASES, get_repo_root, project_slug, resolved_collection,
    collection_or_alias_exists,
)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

EMBED_DIM = 1024  # Qwen3-Embedding-0.6B — must match setup-qdrant.py / the ingest scripts.
SAMPLE_SIZE = 64  # points sampled from a legacy collection for provenance detection.
OVERLAP_ADOPT_THRESHOLD = 0.5  # ≥ this fraction of sampled paths/sessions still on disk → ours.
LOCK_STALE_SECONDS = 300  # a lock dir older than this is assumed orphaned (crashed run) and stolen.
CLIENT_TIMEOUT = 30  # bound Qdrant ops so a reachable-but-wedged server can't hang `git pull`.
EX_DEFERRED = 75  # exit code (EX_TEMPFAIL): migration did NOT settle this run (lock held / partial).
                  # The pull hook reads this and SKIPS the Qdrant syncs for this pull so an
                  # ingest can't pre-create a namespaced collection and pre-empt a pending adopt.
_DRIVE_RE = re.compile(r"^[A-Za-z]:")
_HELD_LOCK = None  # set while this process holds the migration lock (for the signal handler).


def _is_clean_relpath(val: str) -> bool:
    """Reject a payload-supplied identity (file_path / session_id) before using it in a
    filesystem stat. Payloads are scrolled back from Qdrant and are NOT trusted: a
    crafted absolute / '..' / backslash value must never let the provenance stat escape
    repo_root (matches the path hardening in lib.memory_ingest.get_extra_ingest_dirs)."""
    if not val or val[0] in "/~" or _DRIVE_RE.match(val) or "\\" in val:
        return False
    return not any(seg in ("", "..") for seg in val.split("/"))

# Payload field that carries a repo-relative identity we can check against the disk,
# per base (for UNSTAMPED legacy data — the strong signal is the project_slug stamp).
_IDENTITY_FIELD = {
    "code_chunks": "file_path",
    "wiki_pages": "page_path",
    "chat_history": "session_id",
}


def _state_path(repo_root: Path) -> Path:
    return repo_root / ".sumela" / "_migration" / "qdrant-collections.json"


def _marker_path(repo_root: Path) -> Path:
    # Cheap "already migrated" sentinel the pull-time git hooks stat (without spawning
    # python) to no-op on every pull after the one-time migration. Content is a single
    # line "<host>:<port>\t<slug>" — the (Qdrant instance, project) the migration is
    # done for; a changed endpoint/slug simply re-runs the idempotent migration.
    return repo_root / ".sumela" / "_migration" / ".migrated"


def _write_marker(repo_root: Path, qdrant_key: str, slug: str) -> None:
    p = _marker_path(repo_root)
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(f"{qdrant_key}\t{slug}\n", encoding="utf-8")
    except OSError:
        pass  # best-effort; without the marker the hook just re-checks state next pull


def _acquire_lock(repo_root: Path):
    """Atomic mkdir lock so two concurrent runs (e.g. a pull-hook firing on both
    post-merge and post-checkout, or two terminals) don't race adopt-vs-rebuild on the
    same physical name and leave a split-brain. Returns the lock Path on success, or
    None if another run holds it (caller skips). A lock older than LOCK_STALE_SECONDS is
    assumed orphaned by a crashed run and stolen once."""
    lock = repo_root / ".sumela" / "_migration" / ".lock"
    try:
        lock.parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        return None
    for _ in range(2):  # at most one steal attempt
        try:
            lock.mkdir()
            return lock
        except FileExistsError:
            try:
                age = time.time() - lock.stat().st_mtime
            except OSError:
                return None
            if age > LOCK_STALE_SECONDS:
                try:
                    lock.rmdir()
                    continue  # retry the mkdir
                except OSError:
                    return None
            return None
        except OSError:
            return None
    return None


def _release_lock(lock) -> None:
    global _HELD_LOCK
    if lock is None:
        return
    try:
        lock.rmdir()
    except OSError:
        pass
    if _HELD_LOCK == lock:
        _HELD_LOCK = None


def _install_lock_signal_handlers() -> None:
    """Release the lock on SIGTERM/SIGINT — the default SIGTERM disposition terminates
    WITHOUT running `finally`, which would otherwise orphan the lock for up to
    LOCK_STALE_SECONDS (e.g. update.sh killed by a CI timeout). On signal: release, then
    re-raise the default action so exit status is unchanged."""
    def _handler(signum, _frame):
        _release_lock(_HELD_LOCK)
        signal.signal(signum, signal.SIG_DFL)
        os.kill(os.getpid(), signum)
    for _sig in (signal.SIGTERM, signal.SIGINT):
        try:
            signal.signal(_sig, _handler)
        except (ValueError, OSError):
            pass  # not in main thread / unsupported — finally still covers normal exit


def _load_state(repo_root: Path) -> dict:
    p = _state_path(repo_root)
    try:
        if p.is_file():
            data = json.loads(p.read_text(encoding="utf-8"))
            return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError, ValueError):
        pass
    return {}


def _save_state(repo_root: Path, state: dict) -> None:
    p = _state_path(repo_root)
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    except OSError as e:
        print(f"[warn] could not persist migration state: {e}")


def _aliases(client):
    """All aliases as (alias_name, collection_name) tuples; [] on any API hiccup."""
    try:
        return [(a.alias_name, a.collection_name) for a in client.get_aliases().aliases]
    except Exception:
        return []


def _disk_overlap(client, legacy: str, base: str, repo_root: Path):
    """Fraction of a legacy collection's sampled identities that still exist on disk,
    plus whether any sample carried a project_slug stamp and which slug(s). Returns
    (overlap_or_None, stamped_slugs_set). overlap is None when nothing checkable was
    sampled (empty collection / unknown base)."""
    field = _IDENTITY_FIELD.get(base)
    try:
        points, _ = client.scroll(collection_name=legacy, limit=SAMPLE_SIZE,
                                  with_payload=True, with_vectors=False)
    except Exception:
        return None, set()
    if not points:
        return None, set()

    stamped = set()
    checked = matched = 0
    # Wiki root env names diverge across the codebase: the git hooks/this script use
    # WIKI_PATH (+ SUMELA_SUMMARIES_DIR), while the wiki INGESTER honors WIKI_DIR. Try
    # all so a project that relocated its wiki via EITHER var still verifies correctly.
    wiki_root = os.getenv("WIKI_PATH") or os.getenv("WIKI_DIR") or "docs/second-brain/wiki"
    summaries_dir = repo_root / os.getenv("SUMELA_SUMMARIES_DIR", wiki_root + "/session-summaries")
    # If the summaries dir isn't where we expect (a project relocated its wiki, or the
    # hook ran without the project's WIKI_PATH/SUMELA_SUMMARIES_DIR env), we CANNOT
    # verify chat_history provenance from disk. Treat it as UNVERIFIABLE (overlap None)
    # rather than counting every session as a miss — a false 0% would destructively
    # REBUILD the project's own session memory instead of adopting it.
    summaries_checkable = (base != "chat_history") or summaries_dir.is_dir()
    for p in points:
        payload = p.payload or {}
        s = payload.get("project_slug")
        if s:
            stamped.add(s)
        val = payload.get(field) if field else None
        if not isinstance(val, str) or not val:
            continue
        # Never stat an untrusted payload path that escapes the repo (provenance
        # spoofing / traversal). Skip it — neither counted nor matched.
        if not _is_clean_relpath(val):
            continue
        if base == "chat_history":
            if not summaries_checkable:
                continue  # don't count — leaves overlap None (unverifiable)
            exists = (summaries_dir / f"{val}.md").is_file()
        else:
            exists = (repo_root / val).exists()
        checked += 1
        if exists:
            matched += 1
    overlap = (matched / checked) if checked else None
    return overlap, stamped


def _decide(client, base: str, legacy: str, slug: str, repo_root: Path,
            collections: list, force_adopt: bool, force_rebuild: bool):
    """Return ('adopt'|'rebuild', reason). Never adopts data that looks foreign."""
    if force_adopt:
        return "adopt", "forced (--adopt)"
    if force_rebuild:
        return "rebuild", "forced (--rebuild)"

    # If another project already aliased the legacy collection, adopting it too would
    # re-share it (the exact bug we're fixing) — rebuild fresh instead.
    for an, cn in _aliases(client):
        if cn == legacy and an != resolved_collection(base):
            return "rebuild", f"legacy '{legacy}' is already adopted by another project (alias '{an}')"

    # An EMPTY legacy collection has nothing to preserve — rebuild a fresh OWN
    # collection rather than aliasing the shared bare one. Two projects both adopting
    # the same empty bare (e.g. setup-qdrant pre-created an empty code_chunks for each)
    # would re-intermingle through their aliases — the exact bug this feature prevents.
    # exact=True: an APPROXIMATE count can read 0 on a freshly-restarted or not-yet-
    # indexed collection that actually holds data — and a false "empty" would REBUILD
    # (discard) real data, most painfully chat_history. The one exact count per base is
    # negligible.
    try:
        legacy_count = client.count(collection_name=legacy, exact=True).count
    except Exception:
        legacy_count = None
    if legacy_count == 0:
        return "rebuild", "legacy collection is empty — fresh namespaced collection (nothing to adopt)"

    overlap, stamped = _disk_overlap(client, legacy, base, repo_root)

    if stamped:
        if stamped == {slug}:
            return "adopt", "payload project_slug matches this project"
        return "rebuild", f"payload project_slug belongs to another project ({sorted(stamped)})"

    # Unstamped pre-feature data: use disk overlap + whether another project has
    # already namespaced this base.
    other_ns = any(c.endswith(f"__{base}") and c != resolved_collection(base) for c in collections)
    if overlap is None:
        # Empty or no checkable identities. Adopt only if we're plausibly the sole
        # (first) project for this base; otherwise rebuild to avoid stealing.
        if other_ns:
            return "rebuild", "unverifiable legacy data and another project already namespaced this base"
        return "adopt", "legacy collection empty/unverifiable; first migration on this instance"
    if overlap >= OVERLAP_ADOPT_THRESHOLD:
        return "adopt", f"{overlap:.0%} of sampled legacy paths still exist in this repo"
    return "rebuild", f"only {overlap:.0%} of sampled legacy paths exist here — looks like another project's data"


def _create_alias(client, models, physical: str, legacy: str) -> None:
    client.update_collection_aliases(change_aliases_operations=[
        models.CreateAliasOperation(
            create_alias=models.CreateAlias(collection_name=legacy, alias_name=physical)
        )
    ])


def _create_empty(client, models, physical: str) -> None:
    client.create_collection(
        collection_name=physical,
        vectors_config=models.VectorParams(size=EMBED_DIM, distance=models.Distance.COSINE),
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="Migrate bare Qdrant collections to per-project namespaced ones.")
    ap.add_argument("--host", default=os.getenv("QDRANT_HOST", "localhost"))
    ap.add_argument("--port", type=int, default=int(os.getenv("QDRANT_PORT", "6333")))
    ap.add_argument("--dry-run", action="store_true", help="Show intended actions; change nothing.")
    ap.add_argument("--adopt", action="store_true", help="Force ADOPT (alias) for every legacy base.")
    ap.add_argument("--rebuild", action="store_true", help="Force REBUILD (fresh empty) for every base.")
    ap.add_argument("--gc", action="store_true", help="Drop orphaned legacy bare collections (no alias points at them).")
    ap.add_argument("--force", action="store_true", help="Re-evaluate even if state says already migrated.")
    args = ap.parse_args()

    if args.adopt and args.rebuild:
        print("migrate-collections: --adopt and --rebuild are mutually exclusive.")
        return 2

    try:
        from qdrant_client import QdrantClient
        from qdrant_client import models
    except ImportError:
        print("migrate-collections: qdrant-client not installed — skipping (nothing migrated).")
        return 0

    try:
        client = QdrantClient(host=args.host, port=args.port,
                              check_compatibility=False, timeout=CLIENT_TIMEOUT)
        collections = [c.name for c in client.get_collections().collections]
    except Exception as e:
        print(f"migrate-collections: Qdrant not reachable at {args.host}:{args.port} — skipping ({e}).")
        return 0

    repo_root = get_repo_root()
    slug = project_slug(repo_root)
    qdrant_key = f"{args.host}:{args.port}"
    forcing = args.adopt or args.rebuild or args.force or args.gc

    state = _load_state(repo_root)
    done = (state.get("qdrant") == qdrant_key and state.get("slug") == slug
            and isinstance(state.get("bases"), dict)
            and all(b in state["bases"] for b in COLLECTION_BASES))
    if done and not forcing:
        print(f"migrate-collections: already migrated (slug '{slug}' on {qdrant_key}). "
              f"Use --force / --adopt / --rebuild to re-evaluate.")
        # Re-stamp the cheap hook sentinel: state says done but the (gitignored,
        # best-effort) marker may have been deleted — without this the pull hook
        # would re-spawn python every pull forever.
        _write_marker(repo_root, qdrant_key, slug)
        return 0

    if args.gc:
        return _gc(client, collections, args.dry_run)

    # Serialize mutating runs (dry-run mutates nothing, so it needs no lock).
    global _HELD_LOCK
    lock = None if args.dry_run else _acquire_lock(repo_root)
    if lock is None and not args.dry_run:
        # Another migrate (e.g. update.sh) holds the lock. Signal DEFERRED so the pull
        # hook skips this pull's Qdrant syncs rather than letting an ingest pre-create a
        # namespaced collection and pre-empt the in-progress adopt.
        print("migrate-collections: another migration is in progress — deferring (skipping this run).")
        return EX_DEFERRED
    _HELD_LOCK = lock
    _install_lock_signal_handlers()
    try:
        return _migrate(client, models, repo_root, slug, qdrant_key, collections, args)
    finally:
        _release_lock(lock)


def _migrate(client, models, repo_root, slug, qdrant_key, collections, args) -> int:
    aliases = _aliases(client)
    # Start fresh every run: decisions must reflect ONLY this run's outcomes, so a
    # base that errors below is ABSENT (len < bases) and the marker is withheld for a
    # retry. Seeding from prior state could keep a stale entry and let a partial run
    # write a premature "done" marker. Re-evaluation is idempotent.
    decisions = {}
    print(f"migrate-collections: project slug '{slug}' on Qdrant {qdrant_key}")

    for base in COLLECTION_BASES:
        physical = resolved_collection(base, repo_root)
        legacy = base

        if collection_or_alias_exists(client, physical, aliases):
            print(f"  [skip] {base}: '{physical}' already present.")
            decisions[base] = "present"
            continue

        # Refresh the collection list (a prior iteration may have created one).
        try:
            collections = [c.name for c in client.get_collections().collections]
        except Exception:
            pass

        if not client.collection_exists(legacy):
            print(f"  [fresh] {base}: no legacy '{legacy}' — '{physical}' will be built on demand.")
            decisions[base] = "fresh"
            continue

        action, reason = _decide(client, base, legacy, slug, repo_root, collections,
                                 args.adopt, args.rebuild)

        if args.dry_run:
            print(f"  [dry-run] {base}: would {action.upper()} → {reason}")
            continue

        try:
            if action == "adopt":
                _create_alias(client, models, physical, legacy)
                print(f"  [adopt] {base}: alias '{physical}' → '{legacy}' ({reason})")
            else:
                _create_empty(client, models, physical)
                print(f"  [rebuild] {base}: created empty '{physical}' ({reason})")
                if base == "chat_history":
                    print(f"           NOTE: session summaries deleted from git but intentionally "
                          f"retained in the old '{legacy}' are NOT carried over — they will only "
                          f"reappear for summaries still present on disk as they re-ingest.")
                else:
                    print(f"           '{physical}' repopulates via the normal seed / first-pull build.")
            decisions[base] = action
            aliases = _aliases(client)
        except Exception as e:
            print(f"  [warn] {base}: {action} failed ({e}); will retry on next run.")

    if args.dry_run:
        print("migrate-collections: --dry-run — no changes written.")
        return 0

    state = {
        "qdrant": qdrant_key,
        "slug": slug,
        "migrated_at": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
        "bases": decisions,
    }
    _save_state(repo_root, state)
    # Drop the cheap hook sentinel only when EVERY base is resolved — a partial run
    # (a base errored) leaves no marker so the next pull retries.
    settled = len(decisions) == len(COLLECTION_BASES)
    if settled:
        _write_marker(repo_root, qdrant_key, slug)
    print("migrate-collections: done." if settled
          else "migrate-collections: incomplete — some bases unresolved; will retry.")
    # DEFERRED when not fully settled so the pull hook skips this pull's Qdrant syncs
    # (a partial-state ingest could pre-create a namespaced collection for an unresolved
    # base and pre-empt its pending adopt).
    return 0 if settled else EX_DEFERRED


def _gc(client, collections: list, dry_run: bool) -> int:
    """Drop legacy bare collections (chat_history/wiki_pages/code_chunks) that NO alias
    points at — orphans left behind after every project rebuilt rather than adopted."""
    # CRITICAL: an ADOPTED collection is the SOLE copy of that project's data, reachable
    # only via its alias. We must NOT treat it as an orphan. _aliases() swallows errors
    # and returns [] — if we trusted that here, a transient get_aliases() failure would
    # make every adopted bare collection look orphaned and we'd delete live data. So
    # fetch aliases DIRECTLY and ABORT on any failure rather than risk a false orphan.
    try:
        aliased_targets = {a.collection_name for a in client.get_aliases().aliases}
    except Exception as e:
        print(f"migrate-collections --gc: could not enumerate aliases ({e}); "
              f"aborting (refusing to risk deleting adopted data).")
        return 0
    orphans = [b for b in COLLECTION_BASES if b in collections and b not in aliased_targets]
    if not orphans:
        print("migrate-collections --gc: no orphaned legacy collections.")
        return 0
    print(f"migrate-collections --gc: orphaned legacy collections (no alias points at them): {orphans}")
    if dry_run:
        print("  --dry-run: would delete the above; nothing removed.")
        return 0
    for name in orphans:
        try:
            client.delete_collection(collection_name=name)
            print(f"  [gc] dropped '{name}'")
        except Exception as e:
            print(f"  [warn] could not drop '{name}': {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
