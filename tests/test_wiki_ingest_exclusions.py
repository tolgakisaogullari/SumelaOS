#!/usr/bin/env python3
"""Task records and focus files never enter `wiki_pages` (v0.20.0).

From v0.20.1 the wiki tool writes per-developer working state into the wiki: one record
per task under wiki/_tasks/ and one focus file per developer under wiki/_team/. It is
not curated project knowledge, and it changes all the time. A teammate still on v0.20.0
pulls a canary developer's records before any v0.20.1 code is installed, so this release
already keeps both directories out of the index:

  t_walk_skips_root_tasks_and_team     ingest-wiki-to-qdrant.py prunes _tasks/ and _team/
                                       directly under the wiki root, at every depth below
                                       them: neither its walk nor the points it upserts hold
                                       one, also when an extra ingest dir contains the wiki
                                       or sits at or inside one of them, and when WIKI_DIR is
                                       a symlink (each walk prunes where it arrives, checked
                                       on the directories it enters); the older exclusions
                                       still hold
  t_nested_team_folder_still_ingested  the prune is anchored at the root: a project page
                                       under wiki/runbooks/team/, runbooks/_team/ or
                                       runbooks/_tasks/, and wiki/team/, wiki/tasks/ and
                                       wiki/_teams/ at the root, are still ingested
  t_hook_filter_anchored               sumela_wiki_sync (.sumela/git-hooks/_lib.sh) starts no
                                       re-ingest and no prune for a pull that touches only
                                       those two directories, still syncs every other page,
                                       and anchors its test at the wiki path: for an install
                                       at the repository root, one whose extra ingest dir
                                       contains the wiki, one in a monorepo subdirectory
                                       whose name holds regex characters, and a custom
                                       WIKI_PATH spelled with a trailing /, a leading ./ or //

Nothing touches Qdrant, Ollama or the network. The ingest runs in-process against a stub
client that records what it would upsert (as tests/test_ingest_delete_guard.py does). The
hook runs in bash against throwaway repositories with `python3` and `curl` stubs first on
PATH: python3 records its arguments and curl reports Qdrant as up (as
tests/test_setup_memory_graph_gate.sh stubs graphify, and tests/test_hook_renames.sh both).

Run directly (python3, bash and git; no third-party packages):

    python3 -I tests/test_wiki_ingest_exclusions.py

Exit 0 = all assertions passed, 1 = a failure (printed above).
"""
import contextlib
import importlib.util
import io
import os
import shutil
import subprocess
import sys
import tempfile
import types
from pathlib import Path

sys.dont_write_bytecode = True   # loading the ingest must not write into the source tree

REPO = Path(__file__).resolve().parent.parent
INGEST = REPO / ".sumela/memory-plugins/qdrant-session-memory/scripts/ingest-wiki-to-qdrant.py"
LIB = REPO / ".sumela/git-hooks/_lib.sh"
PLUGIN_REL = ".sumela/memory-plugins/qdrant-session-memory/scripts"
WIKI = "docs/second-brain/wiki"

# Fixture pages, relative to the wiki root. Synthetic names only.
EXCLUDED = [
    "_tasks/feat-retry-cap.md",
    "_tasks/dev-a/2026/feat-deep.md",       # every depth below the root directory
    "_team/dev-a.md",
    "_team/old/dev-b.md",
]
KEPT = [
    "concepts/retry-policy.md",
    "runbooks/team/on-call.md",             # a project folder named team (the plan's case)
    "runbooks/_team/handover.md",           # the same names below the root
    "runbooks/_tasks/checklist.md",
    "team/charter.md",                      # the names without the underscore, at the root
    "tasks/backlog.md",
    "_teams/rotation.md",                   # a near miss at the root: not exactly _team
]
OLDER_EXCLUSIONS = [                        # left out before v0.20.0, and still
    "_INDEX.md", "_SEARCH_INDEX.md", "_LOG.md", "_SCHEMA.md",
    "_improvement-queue/IMP-20260105-retry.md",
]


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS  {name}")
    else:
        print(f"  FAIL  {name}")
        if detail:
            print("\n".join(f"        | {line}" for line in str(detail).splitlines()))
        check.failed += 1
check.failed = 0


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def page(title):
    return f"---\ntype: concept\ntags: fixture\n---\n\n# {title}\n\nSynthetic body text for {title}.\n"


def w(rel):
    """Repo-relative page_path of a wiki page, as the ingest keys it."""
    return f"{WIKI}/{rel}"


def leaks(page_paths, wikis=(WIKI,)):
    """The page paths under <wiki>/_tasks/ or <wiki>/_team/, for each spelling of the wiki."""
    return [pp for pp in page_paths
            if any(pp.startswith((f"{wk}/_tasks/", f"{wk}/_team/")) for wk in wikis)]


def walk_visits(mod, root):
    """(files, directories entered) of one _walk_md call. os.walk is wrapped to record each
    directory it enters, so the root prune is checked directly: the per-file guard behind it
    would otherwise hide a prune that no longer fires."""
    visited, real_walk = [], os.walk

    def recording_walk(top, *a, **kw):
        for entry in real_walk(top, *a, **kw):
            visited.append(entry[0])
            yield entry          # the same dirnames list, so in-place pruning still works
    os.walk = recording_walk
    try:
        files = list(mod._walk_md(root, set(), set()))
    finally:
        os.walk = real_walk
    return files, visited


def entered(visited, wiki_dirs):
    """The visited directories at or below <wiki>/_tasks or <wiki>/_team, per spelling."""
    bad = [Path(wd) / d for wd in wiki_dirs for d in ("_tasks", "_team")]
    return [v for v in visited if any(Path(v) == b or b in Path(v).parents for b in bad)]


# --- the ingest, in-process -------------------------------------------------------------
class FakeQdrant:
    """Records what the ingest would write. Never talks to a server."""

    def __init__(self):
        self.points = []

    def delete(self, collection_name, points_selector):
        pass

    def upsert(self, collection_name, points):
        self.points.extend(points)


class _Point:
    def __init__(self, id=None, vector=None, payload=None, **kw):
        self.id, self.vector, self.payload = id, vector, dict(payload or {})


class _Any:
    def __init__(self, *a, **kw):
        pass


def install_stubs(client):
    """Seed sys.modules so the ingest's module-level imports resolve without qdrant-client
    (and without requests where it is missing; nothing here would call it)."""
    qc = types.ModuleType("qdrant_client")
    models = types.ModuleType("qdrant_client.models")
    qc.QdrantClient = lambda *a, **kw: client
    models.PointStruct = _Point
    for name in ("Filter", "FieldCondition", "MatchValue"):
        setattr(models, name, _Any)
    qc.models = models
    sys.modules["qdrant_client"] = qc
    sys.modules["qdrant_client.models"] = models
    try:
        import requests  # noqa: F401
    except ImportError:
        sys.modules["requests"] = types.ModuleType("requests")


_loads = [0]


def load_ingest(root, extra_dirs="", wiki_dir=WIKI):
    """Load ingest-wiki-to-qdrant.py with its module-level configuration pointing at `root`.
    Returns (module, fake client)."""
    client = FakeQdrant()
    install_stubs(client)
    os.environ["SUMELA_REPO_ROOT"] = str(root)
    os.environ["SUMELA_COLLECTION_PREFIX"] = "exclusionstest"   # never persists a slug file
    os.environ["WIKI_DIR"] = wiki_dir
    for k in ("EXTRA_INGEST_DIRS", "EXTRA_INGEST_MAX_FILES", "WIKI_PAGES_COLLECTION"):
        os.environ.pop(k, None)
    if extra_dirs:
        os.environ["EXTRA_INGEST_DIRS"] = extra_dirs
    _loads[0] += 1
    spec = importlib.util.spec_from_file_location(f"ingest_wiki_exclusions_{_loads[0]}", INGEST)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    # The two preflights and the embedder would reach a live venv and a live Ollama.
    mod.qdrant_client_preflight = lambda: None
    mod.ollama_preflight = lambda url, timeout=5: None
    mod.get_embedding = lambda text, url: [0.1] * 8
    return mod, client


def run_main(mod):
    argv, sys.argv = sys.argv, [str(INGEST)]
    buf = io.StringIO()
    code = None
    try:
        with contextlib.redirect_stdout(buf):
            mod.main()
    except SystemExit as e:
        code = e.code
    finally:
        sys.argv = argv
    return code, buf.getvalue()


def ingest_tests(root):
    for rel in EXCLUDED + KEPT + OLDER_EXCLUSIONS:
        write(root / WIKI / rel, page(Path(rel).stem))
    write(root / "docs/guide.md", page("guide"))     # outside the wiki, for the extra dirs
    wiki_abs = root / WIKI                           # `root` is already a resolved path
    docs = root / "docs"

    mod, client = load_ingest(root)
    walked = [pp for _fp, pp in mod.collect_doc_files()]
    _files, visited = walk_visits(mod, mod.WIKI_DIR)
    code, out = run_main(mod)
    upserted = sorted({p.payload.get("page_path", "") for p in client.points})

    print("== t_walk_skips_root_tasks_and_team ==")
    leaked = leaks(walked)
    check(f"the walk yields nothing under the wiki root's _tasks/ or _team/ "
          f"({len(EXCLUDED)} planted, 1 to 3 levels deep)", not leaked, "\n".join(leaked))
    inside = entered(visited, [wiki_abs])
    check("the wiki walk never enters them: they are pruned at the root",
          not inside and str(wiki_abs / "runbooks/_team") in visited,
          "\n".join(inside) or "visited:\n" + "\n".join(visited))
    leaked = leaks(upserted)
    check("no point upserted into wiki_pages has a page_path under _tasks/ or _team/",
          bool(upserted) and not leaked, "\n".join(leaked) or "nothing was upserted")
    check("the ingest still exits 0 and reports SUCCESS",
          code == 0 and "Status: SUCCESS" in out, f"exit {code}\n{out}")
    older = [w(rel) for rel in OLDER_EXCLUSIONS if w(rel) in walked]
    check("the older exclusions still hold (_INDEX, _SEARCH_INDEX, _LOG, _SCHEMA, "
          "_improvement-queue/)", not older, "\n".join(older))

    # An extra dir that contains the wiki: its walk reaches the wiki root at its real path.
    files, visited = walk_visits(mod, docs)
    via_docs = [fp.resolve().relative_to(root).as_posix() for fp in files]
    leaked, inside = leaks(via_docs), entered(visited, [wiki_abs])
    check("a walk from an extra dir above the wiki passes the wiki root, never enters "
          "_tasks/ or _team/ and yields nothing from them",
          w("concepts/retry-policy.md") in via_docs and not leaked and not inside,
          "\n".join(leaked + inside) or "the walk never reached the wiki:\n" + "\n".join(via_docs))
    mod2, _client2 = load_ingest(root, extra_dirs="docs")
    with_extra = [pp for _fp, pp in mod2.collect_doc_files()]
    leaked = leaks(with_extra)
    check("with EXTRA_INGEST_DIRS=docs the ingest list still holds none of them",
          "docs/guide.md" in with_extra and not leaked,
          "\n".join(leaked) or "the extra dir was not walked:\n" + "\n".join(with_extra))

    # Extra dirs AT or INSIDE them: such a walk never passes the wiki root, so only the
    # per-file guard (the file's real path) keeps the records out.
    at_inside = [f"{WIKI}/_tasks", f"{WIKI}/_tasks/dev-a", f"{WIKI}/_team"]
    mod3, _client3 = load_ingest(root, extra_dirs=",".join(at_inside))
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        listed = [pp for _fp, pp in mod3.collect_doc_files()]
    leaked = leaks(listed)
    check(f"EXTRA_INGEST_DIRS={','.join(at_inside)} brings none of their records in",
          len(mod3.EXTRA_DIRS) == len(at_inside) and not leaked,
          "\n".join(leaked) or f"extra dirs accepted: {mod3.EXTRA_DIRS}")
    check("... and each of those extra dirs is warned about as overlapping the wiki dir",
          err.getvalue().count("overlaps the wiki dir") == len(at_inside), err.getvalue())

    # A wiki path that differs from its real path: WIKI_DIR=docs/kb, a symlink to the wiki,
    # with an extra dir above both. The wiki walk starts at the link, the extra walk reaches
    # the real directory, and each must prune where it arrives.
    kb = docs / "kb"
    try:
        os.symlink("second-brain/wiki", str(kb), target_is_directory=True)
    except (OSError, NotImplementedError) as e:
        check("a directory symlink can be created for the symlinked WIKI_DIR cases", False, e)
    else:
        symlinked_wiki_tests(root, kb, wiki_abs, docs)

    print("== t_nested_team_folder_still_ingested ==")
    missing = [w(rel) for rel in KEPT if w(rel) not in walked]
    check("the walk yields every project page under team/, _team/ and _tasks/ below the "
          "root, and team/, tasks/ and _teams/ at it", not missing, "\n".join(missing))
    missing = [w(rel) for rel in KEPT if w(rel) not in upserted]
    check("each of them reaches wiki_pages", not missing, "\n".join(missing))


def symlinked_wiki_tests(root, kb, wiki_abs, docs):
    mod4, _client4 = load_ingest(root, extra_dirs="docs", wiki_dir="docs/kb")
    listed = [pp for _fp, pp in mod4.collect_doc_files()]
    _files, via_link = walk_visits(mod4, mod4.WIKI_DIR)
    _files, via_docs = walk_visits(mod4, docs)
    leaked = leaks(listed, ("docs/kb", WIKI))
    missing = [f"docs/kb/{rel}" for rel in KEPT if f"docs/kb/{rel}" not in listed]
    check("WIKI_DIR=docs/kb (a symlink to the wiki) with EXTRA_INGEST_DIRS=docs: every "
          "project page is listed and no record", not leaked and not missing,
          "\n".join(leaked + missing))
    inside = entered(via_link, [kb, wiki_abs])
    check("... the wiki walk, which starts at the link, prunes them at the link's path",
          not inside and str(kb / "runbooks/_team") in via_link,
          "\n".join(inside) or "visited:\n" + "\n".join(via_link))
    inside = entered(via_docs, [kb, wiki_abs])
    check("... the extra walk, which reaches the real directory, prunes them there",
          not inside and str(wiki_abs) in via_docs,
          "\n".join(inside) or "visited:\n" + "\n".join(via_docs))


# --- the pull hook, in bash -------------------------------------------------------------
STUB_PYTHON3 = r"""#!/usr/bin/env bash
# Recording stub. One file per call (two background jobs may run at once): the call's
# arguments on one line, TAB-separated. Asked for the extra ingest dirs, it prints
# $WIKI_EXCL_EXTRA, one per line.
IFS="$(printf '\t')"
rec="$(mktemp "$WIKI_EXCL_CALLS/call.XXXXXX")" || exit 1
printf '%s\n' "$*" > "$rec"
case "${1:-}" in *resolve-ingest-dirs.py) [ -n "${WIKI_EXCL_EXTRA:-}" ] && printf '%s\n' "$WIKI_EXCL_EXTRA" ;; esac
exit 0
"""


class Hook:
    def __init__(self, work):
        self.stubs = work / "bin"
        self.calls = work / "calls"
        self.nohooks = work / "nohooks"
        for d in (self.stubs, self.calls, self.nohooks):
            d.mkdir(parents=True)
        write(self.stubs / "python3", STUB_PYTHON3)
        write(self.stubs / "curl", "#!/usr/bin/env bash\nexit 0\n")
        for s in ("python3", "curl"):
            os.chmod(self.stubs / s, 0o755)
        # Hermetic: a developer's opt-outs and overrides, or a git hook's GIT_DIR when this
        # runs from one, must not change the outcome.
        drop = {"WIKI_PATH", "QDRANT_HOST", "QDRANT_PORT", "GIT_DIR", "GIT_WORK_TREE",
                "GIT_INDEX_FILE", "BASH_ENV", "ENV", "CDPATH"}
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith("SUMELA_") and k not in drop}
        self.git_env = dict(self.env)
        self.env["PATH"] = f"{self.stubs}{os.pathsep}{os.environ.get('PATH', '')}"
        self.env["WIKI_EXCL_CALLS"] = str(self.calls)

    def git(self, cwd, *args):
        r = subprocess.run(["git", *args], cwd=str(cwd), env=self.git_env, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        if r.returncode != 0:
            raise RuntimeError(f"git {' '.join(args)} failed in {cwd}:\n{r.stdout}")
        return r.stdout

    def make_repo(self, top, install_rel):
        """A git repository at `top` holding an install at `install_rel` ("" = the root):
        the real _lib.sh plus empty plugin scripts (the hook only checks that they exist)."""
        install = top / install_rel if install_rel else top
        write(install / ".sumela/git-hooks/_lib.sh", LIB.read_text(encoding="utf-8"))
        for s in ("ingest-wiki-to-qdrant.py", "delete-from-qdrant.py", "resolve-ingest-dirs.py"):
            write(install / PLUGIN_REL / s, "")
        self.git(top, "-c", "init.defaultBranch=main", "init", "-q")
        for k, v in (("user.email", "test@example.com"), ("user.name", "Test"),
                     ("commit.gpgsign", "false"), ("core.autocrlf", "false"),
                     ("core.hooksPath", str(self.nohooks))):
            self.git(top, "config", k, v)
        return install

    def commit(self, top, install, add=(), change=(), delete=(), msg="fixture", wiki=WIKI):
        for rel in list(add) + list(change):
            p = install / wiki / rel
            write(p, page(Path(rel).stem) + ("Revised.\n" if rel in change else ""))
        for rel in delete:
            (install / wiki / rel).unlink()
        self.git(top, "add", "-A")
        self.git(top, "commit", "-qm", msg)
        return self.git(top, "rev-parse", "HEAD").strip()

    def changed_paths(self, top, frm, to):
        out = self.git(top, "-c", "core.quotePath=false", "diff", "--no-renames",
                       "--name-only", frm, to)
        return [line for line in out.splitlines() if line]

    def run_sync(self, top, install, frm, to, extra="", wiki_path=None):
        """sumela_wiki_sync from..to, after its background job ends → (output, calls)."""
        for f in self.calls.glob("call.*"):
            f.unlink()
        env = dict(self.env, WIKI_EXCL_EXTRA=extra)
        if wiki_path is not None:
            env["WIKI_PATH"] = wiki_path
        script = 'cd "$1" || exit 1; . "$2"; sumela_wiki_sync "$3" "$4"; wait'
        r = subprocess.run(["bash", "-c", script, "run-sync", str(top),
                            str(install / ".sumela/git-hooks/_lib.sh"), frm, to],
                           env=env, text=True, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=120)
        calls = []
        for f in sorted(self.calls.glob("call.*")):
            calls += [line.split("\t") for line in f.read_text(encoding="utf-8").splitlines() if line]
        return r.stdout, calls


def ingests(calls):
    return [c for c in calls if c and c[0].endswith("ingest-wiki-to-qdrant.py")]


def pruned(calls):
    return [c[c.index("--value") + 1] for c in calls
            if c and c[0].endswith("delete-from-qdrant.py") and "--value" in c[:-1]]


def show(out, calls):
    return "output:\n" + (out.strip() or "(none)") + "\ncalls:\n" + (
        "\n".join(" ".join(c) for c in calls) or "(none)")


def quiet(out, calls):
    """No re-ingest, no prune, no wiki-sync notice."""
    return not ingests(calls) and not pruned(calls) and "wiki changed" not in out


def hook_tests(work):
    print("== t_hook_filter_anchored ==")
    hk = Hook(work)
    found = subprocess.run(["bash", "-c", "command -v python3; command -v curl"], env=hk.env,
                           text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.split()
    check("the hook finds the recording python3 and curl stubs first on PATH",
          found == [str(hk.stubs / "python3"), str(hk.stubs / "curl")], " ".join(found))

    # An install at the repository root.
    top = work / "root-install"
    inst = hk.make_repo(top, "")
    c0 = hk.commit(top, inst, add=["concepts/retry-policy.md", "runbooks/_tasks/checklist.md",
                                   "_tasks/dev-a/2026/feat-deep.md", "_team/dev-a.md"], msg="c0")
    c1 = hk.commit(top, inst, add=["_tasks/feat-retry-cap.md", "_team/old/dev-b.md"],
                   change=["_tasks/dev-a/2026/feat-deep.md", "_team/dev-a.md"], msg="c1")
    c2 = hk.commit(top, inst, delete=["_team/dev-a.md", "_tasks/dev-a/2026/feat-deep.md"], msg="c2")
    c3 = hk.commit(top, inst, add=["runbooks/team/on-call.md", "runbooks/_team/handover.md",
                                   "team/charter.md", "tasks/backlog.md", "_teams/rotation.md"],
                   change=["runbooks/_tasks/checklist.md"], msg="c3")
    c4 = hk.commit(top, inst, change=["_tasks/feat-retry-cap.md", "concepts/retry-policy.md"],
                   delete=["_team/old/dev-b.md", "runbooks/_tasks/checklist.md"], msg="c4")

    want = sorted(w(r) for r in ("_tasks/feat-retry-cap.md", "_team/old/dev-b.md",
                                 "_tasks/dev-a/2026/feat-deep.md", "_team/dev-a.md"))
    got = sorted(hk.changed_paths(top, c0, c1))
    check("precondition: git reports the four _tasks/ and _team/ files the first pull changes",
          got == want, "\n".join(got))

    out, calls = hk.run_sync(top, inst, c0, c1)
    check("a pull that adds or changes only _tasks/ and _team/ files (1 to 3 levels deep) "
          "starts no re-ingest, prunes nothing and prints no wiki-sync notice",
          quiet(out, calls), show(out, calls))

    out, calls = hk.run_sync(top, inst, c1, c2)
    check("a pull that only deletes _tasks/ and _team/ files prunes nothing and starts no "
          "re-ingest", quiet(out, calls), show(out, calls))

    out, calls = hk.run_sync(top, inst, c2, c3)
    check("a pull that changes project pages under team/, _team/ and _tasks/ below the root, "
          "and team/, tasks/ and _teams/ at it, re-ingests them (6 updated)",
          len(ingests(calls)) == 1 and "(6 updated, 0 removed)" in out, show(out, calls))

    out, calls = hk.run_sync(top, inst, c3, c4)
    check("a mixed pull counts only the project pages (1 updated, 1 removed) and prunes only "
          "the removed project page",
          len(ingests(calls)) == 1 and "(1 updated, 1 removed)" in out
          and pruned(calls) == [w("runbooks/_tasks/checklist.md")], show(out, calls))

    # The same install with an extra ingest dir that contains the wiki: its diff reports
    # the _tasks/ and _team/ files too, and must not bring them back.
    out, calls = hk.run_sync(top, inst, c0, c1, extra="docs")
    resolved = any(c and c[0].endswith("resolve-ingest-dirs.py") for c in calls)
    check("with an extra ingest dir that contains the wiki, the _tasks/ and _team/-only pull "
          "still starts no re-ingest and prunes nothing",
          resolved and quiet(out, calls), show(out, calls))
    out, calls = hk.run_sync(top, inst, c2, c3, extra="docs")
    check("... while that extra dir's project pages still re-ingest (6 updated, deduped)",
          len(ingests(calls)) == 1 and "(6 updated, 0 removed)" in out, show(out, calls))

    # An install in a monorepo subdirectory whose name a regex would misread: as a grep -E
    # pattern, BSD grep rejects `c++` as an invalid repetition (so no page would ever sync),
    # and `(v2)` is a group, which never matches the literal parentheses.
    top = work / "monorepo"
    sub = "apps/c++ (v2)"
    inst = hk.make_repo(top, sub)
    write(top / "README.md", "fixture\n")
    m0 = hk.commit(top, inst, add=["concepts/retry-policy.md", "_team/dev-a.md"], msg="m0")
    m1 = hk.commit(top, inst, add=["_tasks/feat-retry-cap.md"], change=["_team/dev-a.md"], msg="m1")
    m2 = hk.commit(top, inst, add=["runbooks/_team/handover.md"], msg="m2")
    got = sorted(hk.changed_paths(top, m0, m1))
    want = sorted(f"{sub}/{w(r)}" for r in ("_tasks/feat-retry-cap.md", "_team/dev-a.md"))
    check("precondition: git reports the subdirectory install's _tasks/ and _team/ changes "
          "with the install's path in front", got == want, "\n".join(got))
    out, calls = hk.run_sync(top, inst, m0, m1)
    check(f"in a monorepo subdirectory ({sub}/), a _tasks/ and _team/-only pull starts no "
          "re-ingest", quiet(out, calls), show(out, calls))
    out, calls = hk.run_sync(top, inst, m1, m2)
    check("... and a project page under its runbooks/_team/ still re-ingests (1 updated)",
          len(ingests(calls)) == 1 and "(1 updated, 0 removed)" in out, show(out, calls))

    # A custom wiki location, spelled several ways in WIKI_PATH. git prints one spelling,
    # so the anchor must be the normalised path, not the raw string: a trailing slash, a
    # leading ./ or a doubled / would each leave it unmatched (a full re-ingest per pull).
    top = work / "custom-wiki"
    inst = hk.make_repo(top, "")
    kw = "notes/kb"
    k0 = hk.commit(top, inst, wiki=kw, add=["concepts/retry-policy.md", "_team/dev-a.md"], msg="k0")
    k1 = hk.commit(top, inst, wiki=kw, add=["_tasks/feat-retry-cap.md"], change=["_team/dev-a.md"],
                   msg="k1")
    k2 = hk.commit(top, inst, wiki=kw, add=["runbooks/_team/handover.md"], msg="k2")
    for spelling in ("notes/kb", "notes/kb/", "./notes/kb", "notes//kb", "././notes//kb/"):
        out1, calls1 = hk.run_sync(top, inst, k0, k1, wiki_path=spelling)
        out2, calls2 = hk.run_sync(top, inst, k1, k2, wiki_path=spelling)
        check(f"WIKI_PATH={spelling}: a _tasks/ and _team/-only pull starts no re-ingest, and a "
              "project page under runbooks/_team/ still re-ingests (1 updated)",
              quiet(out1, calls1) and len(ingests(calls2)) == 1
              and "(1 updated, 0 removed)" in out2,
              show(out1, calls1) + "\n" + show(out2, calls2))


def main():
    if shutil.which("bash") is None or shutil.which("git") is None:
        print("FAIL: this suite needs bash and git on PATH")
        sys.exit(1)
    saved = {k: os.environ.get(k) for k in (
        "SUMELA_REPO_ROOT", "SUMELA_COLLECTION_PREFIX", "WIKI_DIR", "EXTRA_INGEST_DIRS",
        "EXTRA_INGEST_MAX_FILES", "WIKI_PAGES_COLLECTION")}
    saved_modules = {k: sys.modules.get(k) for k in ("qdrant_client", "qdrant_client.models", "requests")}
    print("Task records and focus files never enter wiki_pages")
    try:
        with tempfile.TemporaryDirectory() as td:
            work = Path(td).resolve()
            ingest_tests(work / "ingest")
            hook_tests(work / "hook")
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        for k, v in saved_modules.items():
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v

    print("")
    if check.failed:
        print(f"{check.failed} assertion(s) FAILED")
        sys.exit(1)
    print("All wiki ingest exclusion assertions passed")


if __name__ == "__main__":
    main()
