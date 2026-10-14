#!/usr/bin/env python3
"""Normative floor (QP1, move, never delete): no instruction line disappears unaccounted.

The framework's instruction text is the product. A line deleted from a skill, the contract,
a core rule, AGENTS.md.template or _SCHEMA.md changes what every consumer's agent does, and
nothing else in the repository notices. A floor over keyword lines only is not enough either:
an earlier, narrower keyword set covered 29 of 405 non-blank `context-handoff` lines, and
missed the only line of `executing-plans` that tells the agent to read the task's ground rules.

So the floor is full-line. In every unit that changed since the reference tag, every removed
non-blank line counts. Lines are compared stripped of leading and trailing ASCII whitespace,
as a multiset per unit, so a line moved within its unit (to another place, or to another file
of the same skill directory) is not a removal. Every removed line must be either

  (a) MOVED: a row `src_unit<TAB>dst_unit` in tests/normative/moves/<release>.tsv, with the
      same stripped line added to the destination since the reference tag. The destination
      is a unit, or a file that still works as instruction text: a Markdown file (its name
      holds `.md`) under .sumela/ or docs/second-brain/template/, or a root *.template file.
      Anything else (CHANGELOG.md, a test file, a note no session reads) fails: that line is
      retired, not moved. Lines moved out of the units leave the floor, so --summary lists
      them and the release bullet names them; or
  (b) RETIRED: a row `line<TAB>reason<TAB>replacement|-` in
      tests/normative/retirements/<release>/<unit-slug>.tsv, one row per removed copy.

A reflowed paragraph therefore removes every original line, and each needs its row. A line
that matches the keyword set below is labelled normative: its row needs a replacement, or a
reason that says why there is none ("no replacement: ..."). Placeholders (REASON?,
REPLACEMENT?) fail. A row that accounts for no removed line is stale and fails.

Units and their slugs (formats in tests/normative/*/README.md):
  .sumela/sumela-prompt.md                     sumela-prompt
  .sumela/skills/<name>/ (every *.md)          <name>
  .sumela/memory-plugins/<p>/ (every *.md)     <p>
  .sumela/rules/<rule>.md (the 7 core rules)   <rule>
  AGENTS.md.template                           agents-md-template
  docs/second-brain/template/wiki/_SCHEMA.md   wiki-schema

Reference: the previous final tag,
    git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-rc.*' HEAD
No tag is a FAILURE, not a skip (fetch tags; CI checks out with fetch-depth: 0). Rows count
when their <release> is newer than the reference tag; older ones are history. Row files are
the ones git would track (ignored files, and OS or editor droppings such as .DS_Store, x~ or
.x.swp, never count).

Release gate: once .sumela/VERSION is past the reference tag (the release task), every row
must be filed under VERSION, and CHANGELOG [Unreleased] must hold one (v<VERSION>) bullet that
names every unit with retirements in that release, with its counts, `normative: <slug> <n>/<m>`
(n normative lines of m retired), and every unit with lines moved out of the units,
`moved out: <slug> <k>`, exactly as --summary prints them. A bullet that only says "normative"
fails. Before the release task the gate is silent, so intermediate tasks stay green.

A self-test runs first: it builds throwaway git repositories with a tag and proves that each
rule fails when it should and passes when it should.

Usage (Python is optional in this repository; run it isolated):
    python3 -I tests/test_normative_floor.py                 # self-test, then the check
    python3 -I tests/test_normative_floor.py --suggest UNIT  # skeleton rows for a unit
    python3 -I tests/test_normative_floor.py --summary       # per-release counts
    options: --self-test (the self-test only), --no-self-test, --release X.Y.Z (with --suggest)
Exit: 0 pass (or the helper printed its output); 1 a check or the self-test failed, or no
reference tag; 2 usage error (bad option, unknown unit). Standard library only.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path, PurePosixPath

REPO = Path(__file__).resolve().parent.parent
FLOOR_DIR = "tests/normative"
NORMATIVE = re.compile(
    r"\b(MUST|NEVER|ALWAYS|MANDATORY|CRITICAL|REQUIRED|BEFORE|STOP|ONLY|NOT|binding|do not)\b",
    re.IGNORECASE)
WS = " \t\r\n\f\v"
TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
TOKEN_RE = re.compile(r"normative:\s*`?([A-Za-z0-9_.+-]+)`?\s+(\d+)\s*/\s*(\d+)")
MOVED_OUT_RE = re.compile(r"moved out:\s*`?([A-Za-z0-9_.+-]+)`?\s+(\d+)")
# OS and editor droppings that never count as row files: .DS_Store, .x.swp, .#x, x~, #x#.
DROPPING_RE = re.compile(r"^(\..*|.*~|#.*#)$")
# Instruction text is Markdown: x.md, x.md.template, x.md.example, x.md.best-practice.
MARKDOWN_NAME_RE = re.compile(r"\.md(\.|$)")
SURFACE_DIRS = (".sumela/", "docs/second-brain/template/")

CONTRACT = ".sumela/sumela-prompt.md"
AGENTS_TEMPLATE = "AGENTS.md.template"
SCHEMA = "docs/second-brain/template/wiki/_SCHEMA.md"
SKILLS = ".sumela/skills/"
PLUGINS = ".sumela/memory-plugins/"
RULES = ".sumela/rules/"
CORE_RULES = ("engineering_philosophy", "identity_and_behavior", "architecture_patterns",
              "audit_and_output", "security_protocol", "git_workflow_mandatory_review_protocol",
              "self_improvement_protocol")
FIXED_UNITS = {CONTRACT: "sumela-prompt", AGENTS_TEMPLATE: "agents-md-template",
               SCHEMA: "wiki-schema"}
PATHSPECS = [CONTRACT, SKILLS.rstrip("/"), PLUGINS.rstrip("/"), RULES.rstrip("/"),
             AGENTS_TEMPLATE, SCHEMA]


class FloorError(Exception):
    pass


# --------------------------------------------------------------------------
# units, lines, git
# --------------------------------------------------------------------------
def unit_of(path):
    """(slug, unit path) when a repository path belongs to a unit, else None."""
    if path in FIXED_UNITS:
        return FIXED_UNITS[path], path
    for base in (SKILLS, PLUGINS):
        if path.startswith(base) and path.endswith(".md"):
            name, sep, _ = path[len(base):].partition("/")
            if sep and name:
                return name, base + name + "/"
    if path.startswith(RULES) and path.endswith(".md") and path[len(RULES):-3] in CORE_RULES:
        return path[len(RULES):-3], path
    return None


def stripped_lines(data):
    text = data.decode("utf-8", "surrogateescape")
    if text.startswith("\ufeff"):
        text = text[1:]
    return [s for s in (raw.strip(WS) for raw in text.split("\n")) if s]


def as_version(text):
    m = VERSION_RE.match(text or "")
    return tuple(int(x) for x in m.groups()) if m else None


def git(repo, args, env=None, data=None):
    proc = subprocess.run(["git", "-C", str(repo)] + list(args), input=data,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    return proc.returncode, proc.stdout, proc.stderr.decode("utf-8", "replace").strip()


def reference_tag(repo, env=None):
    rc, out, err = git(repo, ["describe", "--tags", "--abbrev=0", "--match", "v[0-9]*",
                              "--exclude", "*-rc.*", "HEAD"], env)
    if rc != 0:
        return None, (err.splitlines()[-1] if err else "git describe printed nothing")
    return out.decode("utf-8", "replace").strip(), ""


def cat_blobs(repo, oids, env):
    uniq = sorted(set(oids))
    if not uniq:
        return {}
    rc, out, err = git(repo, ["cat-file", "--batch"], env, ("\n".join(uniq) + "\n").encode("ascii"))
    if rc != 0:
        raise FloorError("git cat-file failed: %s" % err)
    blobs, pos = {}, 0
    for oid in uniq:
        nl = out.find(b"\n", pos)
        head = out[pos:nl].split() if nl >= 0 else []
        if len(head) != 3:
            raise FloorError("git cat-file: unexpected output for %s" % oid)
        start = nl + 1
        size = int(head[2])
        blobs[oid] = out[start:start + size]
        pos = start + size + 1
    return blobs


def files_at(repo, ref, env):
    """{path: bytes} of every unit file at ref."""
    rc, out, err = git(repo, ["ls-tree", "-r", "-z", ref, "--"] + PATHSPECS, env)
    if rc != 0:
        raise FloorError("git ls-tree %s failed: %s" % (ref, err))
    wanted = []
    for rec in out.split(b"\0"):
        meta, _, raw = rec.partition(b"\t")
        parts = meta.split()
        if len(parts) != 3 or parts[1] != b"blob":
            continue
        path = raw.decode("utf-8", "surrogateescape")
        if unit_of(path):
            wanted.append((path, parts[2].decode("ascii")))
    blobs = cat_blobs(repo, [oid for _, oid in wanted], env)
    return {path: blobs[oid] for path, oid in wanted}


def listed_files(repo, env, pathspecs):
    """Sorted repository paths git would track under pathspecs: tracked, or new and not ignored."""
    rc, out, err = git(repo, ["ls-files", "-z", "-c", "-o", "--exclude-standard", "--"]
                       + list(pathspecs), env)
    if rc != 0:
        raise FloorError("git ls-files failed: %s" % err)
    return sorted(set(raw.decode("utf-8", "surrogateescape") for raw in out.split(b"\0") if raw))


def files_now(repo, env):
    """{path: bytes} of every unit file in the working tree (tracked, or new and not ignored)."""
    files = {}
    for path in listed_files(repo, env, PATHSPECS):
        full = Path(repo) / path
        if unit_of(path) and full.is_file():
            files[path] = full.read_bytes()
    return files


def instruction_surface(path):
    """True for a file outside the units that still works as instruction text: a Markdown file
    under .sumela/ or docs/second-brain/template/, or a root *.template file."""
    if "/" not in path:
        return path.endswith(".template")
    name = path.rsplit("/", 1)[1]
    return path.startswith(SURFACE_DIRS) and MARKDOWN_NAME_RE.search(name) is not None


def group(files):
    """({slug: Counter of lines}, {slug: unit path}, problems)."""
    units, paths, problems = {}, {}, []
    for path in sorted(files):
        slug, upath = unit_of(path)
        if paths.setdefault(slug, upath) != upath:
            problems.append("two units share the slug %r: %s and %s" % (slug, paths[slug], upath))
            continue
        units.setdefault(slug, Counter()).update(stripped_lines(files[path]))
    return units, paths, problems


def resolve_unit(arg, known):
    """A slug, a unit path (with or without '/') or a file inside a unit -> slug, else None."""
    if arg in known:
        return arg
    bare = arg.rstrip("/")
    for slug, upath in known.items():
        if upath.rstrip("/") == bare:
            return slug
    hit = unit_of(arg)
    return hit[0] if hit and hit[0] in known else None


def unreleased_bullets(changelog):
    """Top-level list items under '## [Unreleased]', each with its whitespace collapsed."""
    lines = changelog.replace("\r\n", "\n").split("\n")
    start = next((i + 1 for i, l in enumerate(lines)
                  if re.match(r"^##\s+\[Unreleased\]", l, re.IGNORECASE)), None)
    if start is None:
        return []
    bullets, cur = [], None
    for line in lines[start:]:
        if re.match(r"^##\s", line):
            break
        if re.match(r"^#{1,6}\s", line):
            if cur is not None:
                bullets.append(cur)
            cur = None
            continue
        if re.match(r"^[-*+]\s", line):
            if cur is not None:
                bullets.append(cur)
            cur = [line]
        elif cur is not None:
            cur.append(line)
    if cur is not None:
        bullets.append(cur)
    return [" ".join(" ".join(b).split()) for b in bullets]


def bullet_tokens(bullet):
    """The count tokens a CHANGELOG bullet holds, in the canonical form --summary prints."""
    tokens = set("normative: %s %d/%d" % (s, int(n), int(m))
                 for s, n, m in TOKEN_RE.findall(bullet))
    tokens.update("moved out: %s %d" % (s, int(k)) for s, k in MOVED_OUT_RE.findall(bullet))
    return tokens


def token_line(tokens):
    return "; ".join(tokens)


def short(text, width=160):
    return text if len(text) <= width else text[:width - 3] + "..."


# --------------------------------------------------------------------------
# rows
# --------------------------------------------------------------------------
class Row(object):
    def __init__(self, release, where, order, **fields):
        self.release, self.where, self.order = release, where, order
        self.__dict__.update(fields)


def row_lines(path):
    return path.read_bytes().decode("utf-8", "surrogateescape").split("\n")


def load_rows(repo, tag_version, env=None):
    """(moves, retirements, problems) from releases newer than the reference tag.

    Row files are the files git would track under tests/normative/moves and .../retirements, so
    an ignored file never counts and a new, unstaged row file does. OS and editor droppings
    (DROPPING_RE) are skipped even when no ignore rule covers them."""
    moves, rets, problems, misnamed = [], [], [], set()
    for where in listed_files(repo, env, [FLOOR_DIR + "/moves", FLOOR_DIR + "/retirements"]):
        parts = where[len(FLOOR_DIR) + 1:].split("/")
        full = Path(repo) / where
        if any(DROPPING_RE.match(p) for p in parts) or not full.is_file():
            continue  # a dropping, or a tracked file deleted from the working tree
        if len(parts) < 2:
            problems.append("%s: unexpected entry; this path must be a directory" % where)
            continue
        if parts[1:] == ["README.md"]:
            continue
        if parts[0] == "moves":
            release = parts[1][:-4] if len(parts) == 2 and parts[1].endswith(".tsv") else ""
            if not as_version(release):
                problems.append("%s: unexpected entry; moves files are named <X.Y.Z>.tsv" % where)
                continue
            if as_version(release) <= tag_version:
                continue
            for lineno, raw in enumerate(row_lines(full), 1):
                row = raw.rstrip("\r")
                if not row.strip(WS) or row.startswith("#"):
                    continue
                fields = [f.strip(WS) for f in row.split("\t")]
                if len(fields) != 2 or not all(fields):
                    problems.append("%s:%d: expected src_unit<TAB>dst_unit" % (where, lineno))
                    continue
                moves.append(Row(release, "%s:%d" % (where, lineno),
                                 (as_version(release), where, lineno), src=fields[0],
                                 dst=fields[1]))
            continue
        release = parts[1]
        if len(parts) < 3 or not as_version(release):
            entry = "%s/retirements/%s" % (FLOOR_DIR, release)
            if entry not in misnamed:
                misnamed.add(entry)
                problems.append("%s: unexpected entry; retirements live in "
                                "<X.Y.Z>/<unit-slug>.tsv" % entry)
            continue
        if len(parts) != 3 or not parts[2].endswith(".tsv"):
            problems.append("%s: unexpected entry; expected <unit-slug>.tsv" % where)
            continue
        if as_version(release) <= tag_version:
            continue
        for lineno, raw in enumerate(row_lines(full), 1):
            row = raw.rstrip("\r")
            if not row.strip(WS) or (row.startswith("#") and "\t" not in row):
                continue
            fields = row.rsplit("\t", 2)
            if len(fields) != 3:
                problems.append("%s:%d: expected line<TAB>reason<TAB>replacement|-"
                                % (where, lineno))
                continue
            rets.append(Row(release, "%s:%d" % (where, lineno),
                            (as_version(release), where, lineno), slug=parts[2][:-4],
                            line=fields[0].strip(WS), reason=fields[1].strip(WS),
                            replacement=fields[2].strip(WS)))
    moves.sort(key=lambda r: r.order)
    rets.sort(key=lambda r: r.order)
    return moves, rets, problems


# --------------------------------------------------------------------------
# the analysis
# --------------------------------------------------------------------------
class Analysis(object):
    def __init__(self):
        self.fatal = None
        self.tag = self.version = ""
        self.tag_version = None
        self.known = {}          # slug -> unit path, at the tag or now
        self.changed = []        # slugs whose line multiset changed
        self.removed = {}        # slug -> Counter of removed lines
        self.unaccounted = {}    # slug -> Counter left after moves and retirements
        self.moved = Counter()   # slug -> lines accounted by moves
        self.retired = Counter()  # slug -> lines accounted by retirements
        self.counts = {}         # (release, slug) -> [normative, retired]
        self.move_counts = Counter()  # release -> lines moved
        self.moved_out = {}      # (release, slug) -> {destination file: Counter of lines}
        self.releases = set()    # releases newer than the tag that hold rows
        self.problems = []

    def out_count(self, release=None, slug=None):
        """Lines moved out of the units, for one release and/or one slug."""
        return sum(sum(c.values()) for (r, s), dests in self.moved_out.items()
                   if release in (None, r) and slug in (None, s) for c in dests.values())


def gate_tokens(a, release):
    """The tokens the (v<release>) CHANGELOG bullet holds, as --summary prints them."""
    tokens = ["normative: %s %d/%d" % (slug, n, m)
              for (rel, slug), (n, m) in sorted(a.counts.items()) if rel == release]
    tokens.extend("moved out: %s %d" % (slug, a.out_count(release, slug))
                  for slug in sorted(set(s for (rel, s) in a.moved_out if rel == release)))
    return tokens


def destination(arg, a, ref_units, now_units, repo, env):
    """(key, Counter of lines added since the tag, problem). key is ('unit', slug) or
    ('file', path) for a file outside the units that still works as instruction text."""
    slug = resolve_unit(arg, a.known)
    if slug is not None:
        return ("unit", slug), now_units.get(slug, Counter()) - ref_units.get(slug, Counter()), None
    pure = PurePosixPath(arg)
    path = pure.as_posix()
    if pure.is_absolute() or ".." in pure.parts or "\\" in arg or path == ".":
        return None, None, "destination %r is neither a unit nor a repository file path" % arg
    if not instruction_surface(path):
        return None, None, ("destination %s is not an instruction surface (a unit, a Markdown file "
                            "under .sumela/ or docs/second-brain/template/, or a root *.template "
                            "file); retire the line instead" % path)
    if not (Path(repo) / path).is_file():
        return None, None, "destination %s does not exist" % path
    if path not in listed_files(repo, env, [":(literal)" + path]):
        return None, None, "destination %s is ignored by git, so no checkout has it" % path
    now = Counter(stripped_lines((Path(repo) / path).read_bytes()))
    rc, out, _ = git(repo, ["cat-file", "blob", "%s:%s" % (a.tag, path)], env)
    ref = Counter(stripped_lines(out)) if rc == 0 else Counter()
    return ("file", path), now - ref, None


def analyze(repo, env=None):
    a = Analysis()
    try:
        analyze_into(a, Path(repo), env)
    except FloorError as exc:
        a.fatal = str(exc)
    return a


def analyze_into(a, repo, env):
    tag, err = reference_tag(repo, env)
    if not tag:
        a.fatal = "no reference tag (%s): fetch tags; CI checks out with fetch-depth: 0" % err
        return
    m = TAG_RE.match(tag)
    if not m:
        a.fatal = "reference tag %s is not vX.Y.Z" % tag
        return
    a.tag, a.tag_version = tag, tuple(int(x) for x in m.groups())
    ref_units, ref_paths, p_ref = group(files_at(repo, tag, env))
    now_units, now_paths, p_now = group(files_now(repo, env))
    a.problems.extend(p_ref + p_now)
    a.known = dict(ref_paths)
    for slug, upath in now_paths.items():
        if a.known.setdefault(slug, upath) != upath:
            a.problems.append("unit %r is %s at %s but %s now" % (slug, a.known[slug], tag, upath))
    empty = Counter()
    a.changed = sorted(s for s in a.known if ref_units.get(s, empty) != now_units.get(s, empty))
    for slug in a.changed:
        gone = ref_units.get(slug, empty) - now_units.get(slug, empty)
        if gone:
            a.removed[slug] = gone
    remaining = dict((s, Counter(c)) for s, c in a.removed.items())

    moves, rets, problems = load_rows(repo, a.tag_version, env)
    a.problems.extend(problems)

    # (a) moves: each copy added to the destination accounts for one removed copy.
    pools = {}
    for mv in moves:
        a.releases.add(mv.release)
        src = resolve_unit(mv.src, a.known)
        if src is None:
            a.problems.append("%s: unknown source unit %r" % (mv.where, mv.src))
            continue
        key, added, problem = destination(mv.dst, a, ref_units, now_units, repo, env)
        if problem:
            a.problems.append("%s: %s" % (mv.where, problem))
            continue
        if key == ("unit", src):
            a.problems.append("%s: a move within one unit needs no row" % mv.where)
            continue
        pool = pools.setdefault(key, added)
        rem = remaining.get(src, Counter())
        taken = Counter()
        for line in sorted(rem):
            take = min(rem[line], pool[line])
            if take > 0:
                rem[line] -= take
                pool[line] -= take
                taken[line] += take
        used = sum(taken.values())
        if used == 0:
            a.problems.append("%s: stale move row: %s -> %s accounts for no removed line (the "
                              "destination must gain the line verbatim)" % (mv.where, mv.src, mv.dst))
        a.moved[src] += used
        a.move_counts[mv.release] += used
        if used and key[0] == "file":
            # Out of the units: the floor no longer covers these lines, so the release names them.
            dests = a.moved_out.setdefault((mv.release, src), {})
            dests.setdefault(key[1], Counter()).update(taken)

    # (b) retirements: one row per removed copy.
    for r in rets:
        a.releases.add(r.release)
        if r.slug not in a.known:
            a.problems.append("%s: unknown unit slug %r (the file name is the unit slug; see "
                              "%s/retirements/README.md)" % (r.where, r.slug, FLOOR_DIR))
            continue
        if not r.line:
            a.problems.append("%s: empty line field" % r.where)
            continue
        normative = NORMATIVE.search(r.line) is not None
        if not r.reason or "REASON?" in r.reason:
            a.problems.append("%s: fill in the reason (REASON?)" % r.where)
        if not r.replacement or "REPLACEMENT?" in r.replacement:
            a.problems.append("%s: fill in the replacement, or - when nothing replaces the line "
                              "(REPLACEMENT?)" % r.where)
        elif normative and r.replacement == "-" and "no replacement" not in r.reason.lower():
            a.problems.append("%s: a normative line retired with '-' needs a reason that says why "
                              "none exists ('no replacement: <why>')" % r.where)
        rem = remaining.get(r.slug)
        if rem and rem[r.line] > 0:
            rem[r.line] -= 1
            a.retired[r.slug] += 1
            tally = a.counts.setdefault((r.release, r.slug), [0, 0])
            tally[0] += int(normative)
            tally[1] += 1
            continue
        if now_units.get(r.slug, empty)[r.line]:
            why = "the line is still in %s" % a.known[r.slug]
        elif not ref_units.get(r.slug, empty)[r.line]:
            why = ("%s has no such line at %s (a row holds the removed line, stripped, verbatim)"
                   % (a.known[r.slug], tag))
        else:
            why = "more rows than removed copies, or a move already accounts for the line"
        a.problems.append("%s: stale row: %s" % (r.where, why))

    a.unaccounted = dict((s, +c) for s, c in remaining.items() if +c)

    # Release gate: every row is filed under VERSION, and the CHANGELOG bullet carries the counts.
    vfile = repo / ".sumela/VERSION"
    a.version = vfile.read_text(encoding="utf-8").strip() if vfile.is_file() else ""
    current = as_version(a.version)
    if current is not None and current > a.tag_version:
        for rel in sorted(a.releases, key=as_version):
            if as_version(rel) < current:
                a.problems.append("rows filed for %s, which is newer than %s but older than VERSION "
                                  "%s, so no release gate covers them: move them to %s/"
                                  % (rel, a.tag, a.version, a.version))
            elif as_version(rel) > current:
                a.problems.append("rows filed for %s, newer than VERSION %s, account for lines "
                                  "removed in %s: move them to %s/"
                                  % (rel, a.version, a.version, a.version))
        expected = gate_tokens(a, a.version)
        cfile = repo / "CHANGELOG.md"
        text = cfile.read_text(encoding="utf-8") if cfile.is_file() else ""
        marker = "(v%s)" % a.version
        found = [bullet_tokens(b) for b in unreleased_bullets(text) if marker in b]
        want = set(expected)
        if want and not any(f == want for f in found):
            a.problems.append("CHANGELOG [Unreleased] needs one %s bullet that names every retiring "
                              "unit with its counts, and every unit with lines moved out of the "
                              "units: %s" % (marker, token_line(expected)))
        stray = sorted(set().union(*found) - want) if found else []
        if stray:
            a.problems.append("a %s CHANGELOG bullet names counts the rows do not have: %s "
                              "(expected: %s)" % (marker, token_line(stray),
                                                  token_line(expected) or "none"))


# --------------------------------------------------------------------------
# output
# --------------------------------------------------------------------------
def render(a):
    """(lines, ok) for the check."""
    if a.fatal:
        return ["FAIL " + a.fatal], False
    out = ["normative floor vs %s: %d units, %d changed" % (a.tag, len(a.known), len(a.changed))]
    for slug in a.changed:
        removed = sum(a.removed.get(slug, Counter()).values())
        left = sum(a.unaccounted.get(slug, Counter()).values())
        gone = a.out_count(slug=slug)
        out.append("  %s: %d removed = %d moved + %d retired + %d unaccounted%s"
                   % (slug, removed, a.moved[slug], a.retired[slug], left,
                      " (%d moved out of the units; see --summary)" % gone if gone else ""))
    for slug in sorted(a.unaccounted):
        out.append("  FAIL %s (%s): removed lines with no move and no retirement row:"
                   % (slug, a.known[slug]))
        for line, k in sorted(a.unaccounted[slug].items()):
            label = "normative" if NORMATIVE.search(line) else "plain"
            out.append("         [%s]%s %s" % (label, " x%d" % k if k > 1 else "", short(line)))
        out.append("       restore the line, declare a move, or retire it; skeleton rows: "
                   "python3 -I tests/test_normative_floor.py --suggest %s" % slug)
    for p in a.problems:
        out.append("  FAIL " + p)
    total = sum(sum(c.values()) for c in a.unaccounted.values())
    out.append("%d unaccounted removed lines vs %s" % (total, a.tag))
    return out, total == 0 and not a.problems


def render_summary(a):
    if a.fatal:
        return ["FAIL " + a.fatal]
    out = ["normative summary vs %s (VERSION %s)" % (a.tag, a.version or "unknown")]
    if not a.releases:
        out.append("  no move or retirement rows in releases newer than %s" % a.tag)
    for rel in sorted(a.releases, key=as_version):
        gate = " (gated now: VERSION is %s)" % rel if rel == a.version else ""
        out.append("release %s%s" % (rel, gate))
        out.append("  moved lines: %d" % a.move_counts[rel])
        for (r, slug), dests in sorted(a.moved_out.items()):
            if r != rel:
                continue
            for dst, lines in sorted(dests.items()):
                out.append("  moved out of the units (the floor no longer covers them): %s %d -> %s"
                           % (slug, sum(lines.values()), dst))
                for line, k in sorted(lines.items()):
                    label = "normative" if NORMATIVE.search(line) else "plain"
                    out.append("      [%s]%s %s"
                               % (label, " x%d" % k if k > 1 else "", short(line)))
        tokens = gate_tokens(a, rel)
        for t in tokens:
            out.append("  " + t)
        out.append("  CHANGELOG (v%s) bullet: %s"
                   % (rel, token_line(tokens) or "nothing to name (no retirements, nothing moved "
                                                  "out of the units)"))
    return out


def default_release(a):
    """(release, guessed). At release time it is VERSION; before, the newest release with rows;
    with neither, the next patch release, which is only a guess."""
    current = as_version(a.version)
    if current is not None and current > a.tag_version:
        return a.version, False
    if a.releases:
        return max(a.releases, key=as_version), False
    major, minor, patch = a.tag_version
    return "%d.%d.%d" % (major, minor, patch + 1), True


def suggest(a, unit_arg, release=None):
    """(lines to print) or None for an unknown unit."""
    slug = resolve_unit(unit_arg, a.known)
    if slug is None:
        return None
    target, guessed = (release, False) if release else default_release(a)
    rows = []
    for line, k in sorted(a.unaccounted.get(slug, Counter()).items()):
        replacement = "REPLACEMENT?" if NORMATIVE.search(line) else "-"
        rows.extend(["%s\tREASON?\t%s" % (line, replacement)] * k)
    path = "%s/retirements/%s/%s.tsv" % (FLOOR_DIR, target, slug)
    if guessed:
        where = ["# Append to %s." % path,
                 "# %s is a guess (VERSION %s is the tag, and no row names a release yet): pass"
                 % (target, a.version or "(none)"),
                 "# --release X.Y.Z for the release this change ships in."]
    else:
        where = ["# Append to %s (the release this change ships in;" % path,
                 "# --release X.Y.Z picks another)."]
    head = ["# %d unaccounted removed line(s) of %s (%s) vs %s"
            % (len(rows), slug, a.known[slug], a.tag)] + where + [
        "# Replace every placeholder. REASON? says why the line goes; for a normative line with",
        "# no replacement write 'no replacement: <why>'. REPLACEMENT? names the text or place that",
        "# now carries the rule, or - when nothing does. A line that now lives in another unit is",
        "# a move instead: %s/moves/<release>.tsv, src_unit<TAB>dst_unit." % FLOOR_DIR,
    ]
    return head + rows


# --------------------------------------------------------------------------
# self-test: throwaway repositories with a tag
# --------------------------------------------------------------------------
FIX = {
    CONTRACT: ("# Contract\n\n"
               "You MUST read the registry before answering.\n"
               "Context line without keywords.\n"
               "First half of a paragraph that wraps\n"
               "onto a second line here.\n"
               "Keep this line.\n"),
    SKILLS + "demo/SKILL.md": ("---\nname: demo\n---\n# Demo\n\n"
                               "NEVER skip the demo step.\nA demo sentence.\n"
                               "Shared pointer line.\n"),
    SKILLS + "demo/extra.md": "# Extra\n\nExtra material.\n",
    SKILLS + "other/SKILL.md": "# Other\n\nOther skill text.\n",
    PLUGINS + "plug/SKILL.md": "# Plug\n\nPlugin text line.\n",
    RULES + "identity_and_behavior.md": "# Identity\n\nRule text line.\n",
    RULES + "backend_standards.md": "# Generated overlay, not a unit\n\nOverlay line.\n",
    AGENTS_TEMPLATE: "# Agents\n\nAgents template line.\n",
    SCHEMA: "# Schema\n\nSchema line.\n",
    "CLAUDE.md.template": "# Pointer\n\nShared pointer line.\n",
    ".gitignore": ".sumela/local.md\n*.scratch\n",
    ".sumela/VERSION": "0.1.0\n",
    "CHANGELOG.md": ("# Changelog\n\n## [Unreleased]\n\n### Changed\n\n"
                     "- **Base (v0.1.0).** Text.\n\n## [0.0.1] - 2026-01-01\n\n- Old.\n"),
    FLOOR_DIR + "/moves/README.md": "fixture\n",
    FLOOR_DIR + "/retirements/README.md": "fixture\n",
}
MUST = "You MUST read the registry before answering."
PLAIN = "Context line without keywords."
HALF1, HALF2 = "First half of a paragraph that wraps", "onto a second line here."


def fixture_env(home):
    """Isolate fixture git calls from the developer's config, hooks and any GIT_DIR."""
    env = dict(os.environ)
    for var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR",
                "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE",
                "GIT_CEILING_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS",
                "GIT_CONFIG_COUNT"):
        env.pop(var, None)
    env.update({"HOME": home, "XDG_CONFIG_HOME": home, "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": os.devnull, "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"})
    return env


def write_files(root, files):
    for rel, content in files.items():
        path = Path(root) / rel
        if content is None:
            if path.exists():
                path.unlink()
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content.encode("utf-8"))


def make_repo(root, name, files, tag):
    repo = Path(root) / name
    repo.mkdir(parents=True)
    home = Path(root) / "home"
    home.mkdir(exist_ok=True)
    env = fixture_env(str(home))
    hooks = Path(root) / "no-hooks"
    hooks.mkdir(exist_ok=True)
    write_files(repo, files)
    base = ["-c", "init.defaultBranch=main", "-c", "core.hooksPath=" + str(hooks),
            "-c", "commit.gpgsign=false", "-c", "tag.gpgSign=false", "-c", "core.autocrlf=false",
            "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid"]
    steps = [["init", "-q"], ["add", "-A"], ["commit", "-q", "-m", "base"]]
    if tag:
        steps.append(["tag", tag])
    for step in steps:
        rc, _, err = git(repo, base + step, env)
        if rc != 0:
            raise RuntimeError("fixture git %s failed: %s" % (step[0], err))
    return repo, env


def remove_tree(path):
    for root, _, files in os.walk(str(path)):
        for name in files:
            try:
                os.chmod(os.path.join(root, name), 0o600)
            except OSError:
                pass
    shutil.rmtree(str(path), ignore_errors=True)


def edit(path, old, new=""):
    """FIX[path] with its line `old` replaced by `new` (lines, without newlines)."""
    text = FIX[path]
    assert old + "\n" in text, old
    return {path: text.replace(old + "\n", new + ("\n" if new else ""), 1)}


def retire(release, slug, *rows):
    return {"%s/retirements/%s/%s.tsv" % (FLOOR_DIR, release, slug):
            "# fixture rows\n" + "".join("\t".join(r) + "\n" for r in rows)}


def changelog(bullet):
    return {"CHANGELOG.md": FIX["CHANGELOG.md"].replace(
        "### Changed\n\n", "### Changed\n\n" + bullet + "\n", 1)}


def merged(*parts):
    out = {}
    for p in parts:
        out.update(p)
    return out


def self_test_cases():
    joined = HALF1 + " " + HALF2
    released = {".sumela/VERSION": "0.2.0\n"}
    gate_rows = retire("0.2.0", "sumela-prompt", (MUST, "STEP 1 reads it", "STEP 1, first read"),
                       (PLAIN, "the digest replaces it", "-"))
    gate_tree = merged({CONTRACT: FIX[CONTRACT].replace(MUST + "\n", "").replace(PLAIN + "\n", "")},
                       gate_rows, released)
    moved_out = merged(edit(SKILLS + "demo/SKILL.md", "A demo sentence."),
                       {"CLAUDE.md.template": FIX["CLAUDE.md.template"] + "A demo sentence.\n",
                        FLOOR_DIR + "/moves/0.2.0.tsv": "demo\tCLAUDE.md.template\n"})
    return [
        # (name, edits after the tag, expect_ok, needles in the output)
        ("an untouched tree passes", {}, True, ["0 unaccounted removed lines vs v0.1.0"]),
        ("a deleted MUST line fails", edit(CONTRACT, MUST), False,
         ["[normative] " + MUST, "1 unaccounted"]),
        ("a deleted line with no keyword fails", edit(CONTRACT, PLAIN), False,
         ["[plain] " + PLAIN]),
        ("a line moved within its file passes",
         {CONTRACT: FIX[CONTRACT].replace(MUST + "\n", "") + MUST + "\n"}, True,
         ["0 unaccounted"]),
        ("a line moved to another file of its skill passes",
         merged(edit(SKILLS + "demo/SKILL.md", "A demo sentence."),
                {SKILLS + "demo/extra.md": FIX[SKILLS + "demo/extra.md"] + "A demo sentence.\n"}),
         True, ["0 unaccounted"]),
        ("a retired line with a filled row passes",
         merged(edit(CONTRACT, PLAIN), retire("0.2.0", "sumela-prompt",
                                              (PLAIN, "the digest replaces it", "-"))),
         True, ["sumela-prompt: 1 removed = 0 moved + 1 retired"]),
        ("a stale row fails",
         retire("0.2.0", "sumela-prompt", ("Keep this line.", "gone soon", "-")), False,
         ["stale row: the line is still in"]),
        ("a mistyped row fails as stale",
         merged(edit(CONTRACT, PLAIN), retire("0.2.0", "sumela-prompt",
                                              ("Context line without keyword.", "typo", "-"))),
         False, ["has no such line", "[plain] " + PLAIN]),
        ("a reflowed paragraph fails without rows",
         edit(CONTRACT, HALF1 + "\n" + HALF2, joined), False, ["2 unaccounted"]),
        ("a reflowed paragraph passes with a row per original line",
         merged(edit(CONTRACT, HALF1 + "\n" + HALF2, joined),
                retire("0.2.0", "sumela-prompt", (HALF1, "reflowed", joined),
                       (HALF2, "reflowed", joined))), True, ["0 unaccounted"]),
        ("a normative line retired with '-' must say why there is no replacement",
         merged(edit(CONTRACT, MUST), retire("0.2.0", "sumela-prompt",
                                             (MUST, "shorter contract", "-"))),
         False, ["'no replacement: <why>'"]),
        ("a normative line retired with 'no replacement: ...' passes",
         merged(edit(CONTRACT, MUST), retire("0.2.0", "sumela-prompt",
                                             (MUST, "no replacement: STEP 1 already reads it", "-"))),
         True, ["0 unaccounted"]),
        ("placeholder rows fail",
         merged(edit(CONTRACT, MUST), retire("0.2.0", "sumela-prompt",
                                             (MUST, "REASON?", "REPLACEMENT?"))),
         False, ["fill in the reason", "fill in the replacement"]),
        ("a move to another unit fails without a moves row",
         merged(edit(SKILLS + "demo/SKILL.md", "A demo sentence."),
                {SKILLS + "other/SKILL.md": FIX[SKILLS + "other/SKILL.md"] + "A demo sentence.\n"}),
         False, ["[plain] A demo sentence."]),
        ("a move to another unit passes with a moves row",
         merged(edit(SKILLS + "demo/SKILL.md", "A demo sentence."),
                {SKILLS + "other/SKILL.md": FIX[SKILLS + "other/SKILL.md"] + "A demo sentence.\n",
                 FLOOR_DIR + "/moves/0.2.0.tsv": "# fixture\ndemo\tother\n"}),
         True, ["demo: 1 removed = 1 moved + 0 retired"]),
        ("a move whose destination copy is not verbatim fails",
         merged(edit(SKILLS + "demo/SKILL.md", "A demo sentence."),
                {SKILLS + "other/SKILL.md": FIX[SKILLS + "other/SKILL.md"] + "A demo sentence!\n",
                 FLOOR_DIR + "/moves/0.2.0.tsv": "demo\t.sumela/skills/other/\n"}),
         False, ["stale move row", "[plain] A demo sentence."]),
        ("a move to CHANGELOG.md fails: it is not an instruction surface",
         merged(edit(SKILLS + "demo/SKILL.md", "A demo sentence."),
                {"CHANGELOG.md": FIX["CHANGELOG.md"] + "A demo sentence.\n",
                 FLOOR_DIR + "/moves/0.2.0.tsv": "demo\tCHANGELOG.md\n"}),
         False, ["destination CHANGELOG.md is not an instruction surface",
                 "[plain] A demo sentence."]),
        ("a move to a new file under tests/ fails: it is not an instruction surface",
         merged(edit(SKILLS + "demo/SKILL.md", "A demo sentence."),
                {"tests/attic.txt": "A demo sentence.\n",
                 FLOOR_DIR + "/moves/0.2.0.tsv": "demo\ttests/attic.txt\n"}),
         False, ["destination tests/attic.txt is not an instruction surface"]),
        ("a move to a file under .sumela/ that is not Markdown fails",
         merged(edit(SKILLS + "demo/SKILL.md", "A demo sentence."),
                {".sumela/notes.conf": "A demo sentence.\n",
                 FLOOR_DIR + "/moves/0.2.0.tsv": "demo\t.sumela/notes.conf\n"}),
         False, ["destination .sumela/notes.conf is not an instruction surface"]),
        ("a move into a file git ignores fails",
         merged(edit(SKILLS + "demo/SKILL.md", "A demo sentence."),
                {".sumela/local.md": "A demo sentence.\n",
                 FLOOR_DIR + "/moves/0.2.0.tsv": "demo\t.sumela/local.md\n"}),
         False, ["destination .sumela/local.md is ignored by git"]),
        ("a move to a root *.template passes and is reported as moved out of the units",
         merged(edit(SKILLS + "demo/SKILL.md", "A demo sentence."),
                {"CLAUDE.md.template": FIX["CLAUDE.md.template"] + "A demo sentence.\n",
                 FLOOR_DIR + "/moves/0.2.0.tsv": "demo\tCLAUDE.md.template\n"}),
         True, ["demo: 1 removed = 1 moved + 0 retired + 0 unaccounted (1 moved out of the units"]),
        ("a move to a new Markdown template under docs/second-brain/template/ passes",
         merged(edit(SKILLS + "demo/SKILL.md", "A demo sentence."),
                {"docs/second-brain/template/wiki/task.md.template": "# Task\n\nA demo sentence.\n",
                 FLOOR_DIR + "/moves/0.2.0.tsv":
                     "demo\tdocs/second-brain/template/wiki/task.md.template\n"}),
         True, ["(1 moved out of the units"]),
        ("a move onto a copy the destination already held fails as stale",
         merged(edit(SKILLS + "demo/SKILL.md", "Shared pointer line."),
                {FLOOR_DIR + "/moves/0.2.0.tsv": "demo\tCLAUDE.md.template\n"}),
         False, ["stale move row", "[plain] Shared pointer line."]),
        ("rows of a release not newer than the tag do not count",
         merged(edit(CONTRACT, PLAIN), retire("0.1.0", "sumela-prompt",
                                              (PLAIN, "filed too early", "-"))),
         False, ["[plain] " + PLAIN]),
        ("every unit kind is covered, and a generated overlay rule is not a unit",
         merged(edit(PLUGINS + "plug/SKILL.md", "Plugin text line."),
                edit(RULES + "identity_and_behavior.md", "Rule text line."),
                edit(AGENTS_TEMPLATE, "Agents template line."), edit(SCHEMA, "Schema line."),
                edit(RULES + "backend_standards.md", "Overlay line.")),
         False, ["FAIL plug ", "FAIL identity_and_behavior ", "FAIL agents-md-template ",
                 "FAIL wiki-schema ", "4 unaccounted"]),
        ("an unknown unit slug fails",
         retire("0.2.0", "no-such-unit", ("Some line.", "why", "-")), False,
         ["unknown unit slug 'no-such-unit'"]),
        ("a misnamed release directory fails",
         {FLOOR_DIR + "/retirements/v0.2.0/sumela-prompt.tsv": "x\ty\t-\n"}, False,
         ["unexpected entry"]),
        ("a stray file git would track in moves/ fails",
         {FLOOR_DIR + "/moves/notes.txt": "demo\tother\n"}, False,
         ["moves/notes.txt: unexpected entry"]),
        ("OS and editor droppings and ignored files under tests/normative do not count",
         {FLOOR_DIR + "/moves/.DS_Store": "\x00\x01Bud1",
          FLOOR_DIR + "/retirements/.DS_Store": "\x00\x01Bud1",
          FLOOR_DIR + "/retirements/0.2.0/sumela-prompt.tsv~": "",
          FLOOR_DIR + "/retirements/0.2.0/.sumela-prompt.tsv.swp": "\x00swap",
          FLOOR_DIR + "/moves/notes.scratch": "not a row file\n"}, True,
         ["0 unaccounted removed lines vs v0.1.0"]),
        ("a CRLF checkout of an unchanged unit passes",
         {CONTRACT: FIX[CONTRACT].replace("\n", "\r\n")}, True, ["0 unaccounted"]),
        ("release gate: a bullet that only says 'normative' fails",
         merged(gate_tree, changelog("- **Trim (v0.2.0).** Normative retirements reviewed.\n")),
         False, ["needs one (v0.2.0) bullet", "normative: sumela-prompt 1/2"]),
        ("release gate: a bullet with the wrong counts fails",
         merged(gate_tree, changelog("- **Trim (v0.2.0).** normative: sumela-prompt 2/2\n")),
         False, ["names counts the rows do not have"]),
        ("release gate: a wrapped bullet with the exact counts passes",
         merged(gate_tree, changelog("- **Trim (v0.2.0).** Two contract lines retired\n"
                                     "  (normative:\n  `sumela-prompt` 1/2).\n")),
         True, ["0 unaccounted"]),
        ("release gate: rows of an untagged older release fail at release time",
         merged(gate_tree, {".sumela/VERSION": "0.3.0\n"},
                changelog("- **Trim (v0.3.0).** No retirements of its own.\n")),
         False, ["older than VERSION 0.3.0"]),
        ("release gate: rows filed for a release newer than VERSION fail at release time",
         merged(edit(CONTRACT, PLAIN), retire("0.3.0", "sumela-prompt",
                                              (PLAIN, "the digest replaces it", "-")), released),
         False, ["rows filed for 0.3.0, newer than VERSION 0.2.0, account for lines removed in "
                 "0.2.0: move them to 0.2.0/"]),
        ("release gate: lines moved out of the units must be named in the bullet",
         merged(moved_out, released), False,
         ["needs one (v0.2.0) bullet", "moved out: demo 1"]),
        ("release gate: a bullet with the retirement and the moved-out counts passes",
         merged(moved_out, gate_tree,
                changelog("- **Trim (v0.2.0).** normative: sumela-prompt 1/2; one demo line now\n"
                          "  lives in the pointer template (moved out: `demo` 1).\n")),
         True, ["0 unaccounted"]),
        ("release gate: a moved-out count the moves do not have fails",
         merged(moved_out, gate_tree,
                changelog("- **Trim (v0.2.0).** normative: sumela-prompt 1/2;\n"
                          "  moved out: demo 2\n")),
         False, ["names counts the rows do not have: moved out: demo 2"]),
    ]


def self_test():
    print("self-test (normative floor)")
    failed = []

    def verdict(name, good, detail):
        print("  %s %s" % ("ok  " if good else "FAIL", name))
        if not good:
            failed.append(name)
            for line in detail:
                print("         " + line)

    tmp = tempfile.mkdtemp(prefix="sumela-floor-selftest-")
    try:
        base, env = make_repo(tmp, "base", FIX, "v0.1.0")
        for i, (name, edits, expect_ok, needles) in enumerate(self_test_cases()):
            repo = Path(tmp) / ("case%02d" % i)
            shutil.copytree(str(base), str(repo), symlinks=True)
            write_files(repo, edits)
            lines, ok = render(analyze(repo, env))
            text = "\n".join(lines)
            verdict(name, ok == expect_ok and all(n in text for n in needles), lines)

        # --suggest round trip: its rows fail until the placeholders are filled.
        repo = Path(tmp) / "suggest"
        shutil.copytree(str(base), str(repo), symlinks=True)
        write_files(repo, edit(CONTRACT, MUST))
        before = analyze(repo, env)
        out = suggest(before, CONTRACT) or []
        named = suggest(before, CONTRACT, "0.2.0") or []
        rows = [l for l in out if not l.startswith("#")]
        target = "%s/retirements/0.1.1/sumela-prompt.tsv" % FLOOR_DIR
        good = (rows == [MUST + "\tREASON?\tREPLACEMENT?"] and any(target in l for l in out)
                and any("0.1.1 is a guess" in l for l in out)
                and any("retirements/0.2.0/sumela-prompt.tsv" in l for l in named)
                and not any("guess" in l for l in named))
        write_files(repo, {target: "\n".join(out) + "\n"})
        lines, ok = render(analyze(repo, env))
        good = good and not ok and "fill in the reason (REASON?)" in "\n".join(lines)
        filled = "\n".join(out).replace("REASON?\tREPLACEMENT?", "no replacement: covered\t-")
        write_files(repo, {target: filled + "\n"})
        lines2, ok2 = render(analyze(repo, env))
        verdict("--suggest rows fail until their placeholders are filled, and a guessed "
                "release says so", good and ok2, out + named + lines + lines2)

        # No tag: a failure that says how to fix it, not a skip.
        repo, env2 = make_repo(tmp, "untagged", FIX, None)
        lines, ok = render(analyze(repo, env2))
        verdict("no reference tag fails", not ok and "fetch-depth: 0" in lines[0], lines)
    finally:
        remove_tree(tmp)
    return failed


# --------------------------------------------------------------------------
def main(argv):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    except (AttributeError, ValueError):
        pass
    parser = argparse.ArgumentParser(
        prog="python3 -I tests/test_normative_floor.py",
        description="Normative floor: every removed line of a changed unit is moved or retired.")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--self-test", action="store_true", help="run the self-test only")
    mode.add_argument("--no-self-test", action="store_true", help="run the check only")
    mode.add_argument("--summary", action="store_true", help="print per-release counts")
    mode.add_argument("--suggest", metavar="UNIT", help="print skeleton rows for a unit")
    parser.add_argument("--release", metavar="X.Y.Z", help="with --suggest: the target release")
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        return 0 if exc.code == 0 else 2
    if args.release and not (args.suggest and as_version(args.release)):
        print("--release X.Y.Z goes with --suggest")
        return 2

    if args.summary or args.suggest:
        a = analyze(REPO)
        if a.fatal:
            print("FAIL " + a.fatal)
            return 1
        if args.summary:
            print("\n".join(render_summary(a)))
            return 0
        lines = suggest(a, args.suggest, args.release)
        if lines is None:
            print("unknown unit %r; units: %s" % (args.suggest, ", ".join(sorted(a.known))))
            return 2
        print("\n".join(lines))
        return 0

    if not args.no_self_test:
        failed = self_test()
        if failed:
            print("FAILED: the self-test shows the floor check is broken (%d case(s))" % len(failed))
            return 1
        if args.self_test:
            print("self-test passed")
            return 0
        print()
    lines, ok = render(analyze(REPO))
    print("\n".join(lines))
    if not ok:
        print("FAILED: the normative floor does not hold")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
