#!/usr/bin/env python3
"""Eager-context budget: the bytes every session reads before its first answer, as ratchets.

The eager set is what the bootstrap reads in every session, before the user's question is
answered: the pointer files, the contract, both registries, the per-developer settings, the
two STEP 2 wiki pages, the two eager skills and the two universal rules, plus the output of
the STEP 2 commands. It was measured at 134,641 B on v0.19.0. Nothing kept it from growing:
one release doubled `context-handoff` and nothing failed.

`scripts/lib/sumela-context-budgets.tsv` pins it (format in the file's header). Checked here:

  1. Every `eager-member` and `file` row: the file exists and is at most its pin (bytes, and
     lines / max_line when pinned).
  2. The `eager-total` row: the sum of the eager-member sizes plus the `eager-const` rows is
     at most the pin. Prints `eager <sum>/<pin> B`.
  3. Stale pins: a pin more than 2,000 B above the measured value fails ("lower it"), so a
     reduction is locked in instead of becoming headroom for the next growth.
  4. Loosening: against the baseline table, a raised pin (bytes, lines or max_line), a pin
     replaced by '-', a row turned overridable, or a dropped row (a file leaving the eager set
     takes its bytes out of the total unseen) needs, once .sumela/VERSION is past the
     previous tag (the release task), a `(vX.Y.Z)` bullet in CHANGELOG [Unreleased] that
     contains "eager budget". Before that, the change is reported and passes, so intermediate
     tasks stay green.

The baseline is the previous tag's table. When that tag predates the table, it is the table
as the first commit since the tag that added it, so the cycle that introduces the table is
checked too; until that commit exists the report says "not checked". Sizes are counted with
CRLF read as LF, so a Windows checkout measures what Linux measures. The previous tag comes from
    git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-rc.*' HEAD
and no tag is a FAILURE, not a skip: without it a raise cannot be checked (fetch tags; CI
checks out with fetch-depth: 0).

A self-test runs first: it builds throwaway git repositories with a tag and proves that each
check fails when it should (an over-budget file, an over-budget sum, a stale pin, a raised,
unpinned, overridable or dropped row at release time without its CHANGELOG reason, the same
against the commit that added the table, a malformed row, no tag).

Usage (Python is optional in this repository; run it isolated):
    python3 -I tests/test_eager_budget.py                 # self-test, then the check
    python3 -I tests/test_eager_budget.py --self-test     # the self-test only
    python3 -I tests/test_eager_budget.py --no-self-test  # the check only
Exit: 0 all checks pass; 1 a check or the self-test failed, or no reference tag; 2 usage error.
Standard library only.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TSV = "scripts/lib/sumela-context-budgets.tsv"
STALE_MARGIN = 2000
COLUMNS = ("kind", "key", "bytes", "lines", "max_line", "overridable", "reason")
CHECKED_KINDS = ("eager-member", "eager-const", "eager-total", "file")
TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


# --------------------------------------------------------------------------
# helpers shared by the check and the self-test
# --------------------------------------------------------------------------
def git(repo, args, env=None):
    proc = subprocess.run(["git", "-C", str(repo)] + list(args), stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, env=env)
    return proc.returncode, proc.stdout, proc.stderr.decode("utf-8", "replace").strip()


def reference_tag(repo, env=None):
    """(tag, error). The previous final tag reachable from HEAD; release candidates excluded."""
    rc, out, err = git(repo, ["describe", "--tags", "--abbrev=0", "--match", "v[0-9]*",
                              "--exclude", "*-rc.*", "HEAD"], env)
    if rc != 0:
        return None, err or "git describe failed"
    return out.decode("utf-8", "replace").strip(), ""


def as_version(text):
    m = VERSION_RE.match(text or "")
    return tuple(int(x) for x in m.groups()) if m else None


def normalized(data):
    """Bytes as an LF checkout holds them: CRLF counts as LF."""
    return data.replace(b"\r\n", b"\n")


def measure(path):
    data = normalized(path.read_bytes())
    lines = data.split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    return len(data), len(lines), max((len(x) for x in lines), default=0)


def parse_table(text, where):
    """(rows, problems). rows: dicts keyed by COLUMNS plus 'lineno'."""
    rows, problems = [], []
    for lineno, raw in enumerate(text.split("\n"), 1):
        row = raw.rstrip("\r")
        if not row.strip() or row.startswith("#"):
            continue
        fields = row.split("\t")
        if len(fields) != len(COLUMNS):
            problems.append("%s:%d: expected %d TAB-separated columns (%s), got %d"
                            % (where, lineno, len(COLUMNS), " ".join(COLUMNS), len(fields)))
            continue
        rec = dict(zip(COLUMNS, fields))
        rec["lineno"] = lineno
        if rec["overridable"] not in ("yes", "no"):
            problems.append("%s:%d: overridable must be yes or no, got %r"
                            % (where, lineno, rec["overridable"]))
        if rec["kind"] in CHECKED_KINDS or rec["kind"].startswith("eager-"):
            if rec["kind"] not in CHECKED_KINDS:
                problems.append("%s:%d: unknown eager kind %r (expected one of %s)"
                                % (where, lineno, rec["kind"], ", ".join(CHECKED_KINDS)))
                continue
            if not rec["bytes"].isdigit():
                problems.append("%s:%d: bytes must be a whole number, got %r"
                                % (where, lineno, rec["bytes"]))
                continue
            bad = [c for c in ("lines", "max_line") if not (rec[c] == "-" or rec[c].isdigit())]
            if bad:
                problems.append("%s:%d: %s must be a whole number or -" % (where, lineno, bad[0]))
                continue
            if not rec["key"]:
                problems.append("%s:%d: empty key" % (where, lineno))
                continue
            rows.append(rec)
    return rows, problems


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


def baseline(repo, tag, env=None):
    """(rows, name, note): the table that loosening is checked against.

    The previous tag's table; when the tag predates the table, the table as the first commit
    since the tag that added it. rows is None when neither exists, and note then says why."""
    rc, old, _ = git(repo, ["cat-file", "blob", "%s:%s" % (tag, TSV)], env)
    if rc == 0:
        return parse_table(old.decode("utf-8", "replace"), "%s:%s" % (tag, TSV))[0], tag, ""
    rc, out, err = git(repo, ["log", "--diff-filter=A", "--reverse", "--format=%H",
                              "%s..HEAD" % tag, "--", TSV], env)
    commits = out.decode("ascii", "replace").split() if rc == 0 else []
    if not commits:
        why = err.splitlines()[-1] if rc != 0 and err else "no commit since %s adds it" % tag
        return None, "", "%s has no %s, and %s" % (tag, TSV, why)
    first = commits[0]
    rc, old, err = git(repo, ["cat-file", "blob", "%s:%s" % (first, TSV)], env)
    if rc != 0:
        return None, "", "cannot read %s at %s: %s" % (TSV, first[:12], err)
    return (parse_table(old.decode("utf-8", "replace"), "%s:%s" % (first[:12], TSV))[0],
            first[:12], " (the commit that added %s; %s has none)" % (TSV, tag))


def loosened(old_rows, rows):
    """Changes against the baseline rows that loosen a budget, one string each: a raised pin,
    a pin replaced by '-', a row turned overridable, a dropped row."""
    now = dict(((r["kind"], r["key"]), r) for r in rows)
    out = []
    for old in old_rows:
        label = "%s %s" % (old["kind"], old["key"])
        new = now.get((old["kind"], old["key"]))
        if new is None:
            out.append("dropped %s (pinned at %s B)" % (label, old["bytes"]))
            continue
        if int(new["bytes"]) > int(old["bytes"]):
            out.append("raised %s %s -> %s B" % (label, old["bytes"], new["bytes"]))
        for col in ("lines", "max_line"):
            if old[col] == "-":
                continue
            if new[col] == "-":
                out.append("unpinned %s %s (was %s)" % (label, col, old[col]))
            elif int(new[col]) > int(old[col]):
                out.append("raised %s %s %s -> %s" % (label, col, old[col], new[col]))
        if old["overridable"] == "no" and new["overridable"] == "yes":
            out.append("made %s overridable" % label)
    return out


# --------------------------------------------------------------------------
# the check
# --------------------------------------------------------------------------
def run_check(repo, env=None):
    """Returns (problems, report_lines, summary_line). Never prints."""
    repo = Path(repo)
    problems, report = [], []
    table = repo / TSV
    if not table.is_file():
        return ["%s is missing" % TSV], report, "eager ?/? B"
    rows, parse_problems = parse_table(table.read_text(encoding="utf-8"), TSV)
    problems.extend(parse_problems)

    seen = set()
    for rec in rows:
        ident = (rec["kind"], rec["key"])
        if ident in seen:
            problems.append("%s:%d: duplicate row %s %s" % (TSV, rec["lineno"], ident[0], ident[1]))
        seen.add(ident)

    members = [r for r in rows if r["kind"] == "eager-member"]
    consts = [r for r in rows if r["kind"] == "eager-const"]
    totals = [r for r in rows if r["kind"] == "eager-total"]
    files = [r for r in rows if r["kind"] == "file"]
    if not members:
        problems.append("%s has no eager-member rows" % TSV)
    if len(totals) != 1 or (totals and totals[0]["key"] != "*"):
        problems.append("%s needs exactly one 'eager-total *' row" % TSV)

    eager_sum = 0
    for rec in members + files:
        path = repo / rec["key"]
        label = rec["key"] if rec["kind"] == "eager-member" else "file " + rec["key"]
        if not path.is_file():
            problems.append("%s: pinned file is missing (renamed? move the row with it)" % label)
            continue
        size, nlines, longest = measure(path)
        if rec["kind"] == "eager-member":
            eager_sum += size
        pin = int(rec["bytes"])
        if size > pin:
            problems.append("%s: over budget, %d > %d B" % (label, size, pin))
        elif pin - size > STALE_MARGIN:
            problems.append("%s: stale pin, %d B pinned for %d B (lower it to %d)"
                            % (label, pin, size, size))
        else:
            report.append("ok   %s %d/%d B" % (label, size, pin))
        if rec["lines"] != "-" and nlines > int(rec["lines"]):
            problems.append("%s: %d lines > %s pinned" % (label, nlines, rec["lines"]))
        if rec["max_line"] != "-" and longest > int(rec["max_line"]):
            problems.append("%s: a %d B line > %s B pinned" % (label, longest, rec["max_line"]))
    for rec in consts:
        eager_sum += int(rec["bytes"])
        report.append("ok   const %s %s B" % (rec["key"], rec["bytes"]))

    summary = "eager %d/? B" % eager_sum
    if len(totals) == 1:
        pin = int(totals[0]["bytes"])
        summary = "eager %d/%d B" % (eager_sum, pin)
        if eager_sum > pin:
            problems.append("eager set over budget: %d > %d B" % (eager_sum, pin))
        elif pin - eager_sum > STALE_MARGIN:
            problems.append("eager-total: stale pin, %d B pinned for %d B (lower it to %d)"
                            % (pin, eager_sum, eager_sum))

    # Loosening against the baseline: the previous tag's table, or the commit that added it.
    tag, err = reference_tag(repo, env)
    if not tag:
        detail = err.splitlines()[-1] if err else "git describe printed nothing"
        problems.append("no reference tag (%s): fetch tags; CI checks out with fetch-depth: 0"
                        % detail)
        return problems, report, summary
    tag_m = TAG_RE.match(tag)
    if not tag_m:
        problems.append("reference tag %s is not vX.Y.Z" % tag)
        return problems, report, summary
    tag_version = tuple(int(x) for x in tag_m.groups())
    old_rows, base, note = baseline(repo, tag, env)
    if old_rows is None:
        report.append("raises: not checked (%s)" % note)
        return problems, report, summary
    changes = loosened(old_rows, rows)
    if not changes:
        report.append("raises: none vs %s%s" % (base, note))
        return problems, report, summary
    if note:
        report.append("baseline %s%s" % (base, note))
    version_file = repo / ".sumela/VERSION"
    version = version_file.read_text(encoding="utf-8").strip() if version_file.is_file() else ""
    current = as_version(version)
    if current is None or current <= tag_version:
        for c in changes:
            report.append("info %s vs %s (the release task needs a (vX.Y.Z) CHANGELOG bullet "
                          "containing \"eager budget\")" % (c, base))
        return problems, report, summary
    changelog = repo / "CHANGELOG.md"
    text = changelog.read_text(encoding="utf-8") if changelog.is_file() else ""
    marker = "(v%s)" % version
    reasons = [b for b in unreleased_bullets(text) if marker in b and "eager budget" in b.lower()]
    if reasons:
        for c in changes:
            report.append("ok   %s vs %s (reason in the %s CHANGELOG bullet)" % (c, base, marker))
    else:
        for c in changes:
            problems.append("%s vs %s without a reason. Add a %s bullet to CHANGELOG "
                            "[Unreleased] that contains \"eager budget\" and says why"
                            % (c, base, marker))
    return problems, report, summary


# --------------------------------------------------------------------------
# self-test: throwaway repositories with a tag
# --------------------------------------------------------------------------
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


def write(root, files):
    for rel, content in files.items():
        p = Path(root) / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(content.encode("utf-8") if isinstance(content, str) else content)


def fixture_git(root, repo, env, steps):
    """Run fixture git steps with no hooks, no signing and a fixed identity."""
    hooks = Path(root) / "no-hooks"
    hooks.mkdir(exist_ok=True)
    base = ["-c", "init.defaultBranch=main", "-c", "core.hooksPath=" + str(hooks),
            "-c", "commit.gpgsign=false", "-c", "tag.gpgSign=false", "-c", "core.autocrlf=false",
            "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid"]
    for step in steps:
        rc, _, err = git(repo, base + step, env)
        if rc != 0:
            raise RuntimeError("fixture git %s failed: %s" % (step[0], err))


def make_repo(root, name, files, tag="v0.1.0", later=None):
    """A repository whose first commit holds files (tagged when tag is set); later, when set,
    is committed on top of it, untagged."""
    repo = Path(root) / name
    repo.mkdir(parents=True)
    home = Path(root) / "home"
    home.mkdir(exist_ok=True)
    env = fixture_env(str(home))
    write(repo, files)
    steps = [["init", "-q"], ["add", "-A"], ["commit", "-q", "-m", "base"]]
    if tag:
        steps.append(["tag", tag])
    fixture_git(root, repo, env, steps)
    if later:
        write(repo, later)
        fixture_git(root, repo, env, [["add", "-A"], ["commit", "-q", "-m", "later"]])
    return repo, env


def fixture_table(rows):
    head = "# fixture table\n#kind\tkey\tbytes\tlines\tmax_line\toverridable\treason\n"
    return head + "".join("\t".join(r) + "\n" for r in rows)


def merged_files(*parts):
    out = {}
    for part in parts:
        out.update(part)
    return out


def self_test():
    """Returns a list of failed case names; prints one line per case."""
    print("self-test (eager budget)")
    failed = []
    base_rows = [
        ("eager-member", "a.md", "100", "-", "-", "no", "fixture member"),
        ("eager-member", "b.md", "200", "-", "-", "no", "fixture member"),
        ("eager-const", "tail", "10", "-", "-", "no", "fixture constant"),
        ("eager-total", "*", "310", "-", "-", "no", "fixture total"),
        ("file", "a.md", "100", "2", "-", "no", "fixture file pin"),
    ]
    base = {
        "a.md": "a" * 99 + "\n",
        "b.md": "b" * 199 + "\n",
        TSV: fixture_table(base_rows),
        ".sumela/VERSION": "0.1.0\n",
        "CHANGELOG.md": "# Changelog\n\n## [Unreleased]\n\n### Changed\n\n- **Base (v0.1.0).** Text.\n",
    }
    no_table = dict((k, v) for k, v in base.items() if k != TSV)
    unrelated = "- **Other (v0.2.0).** Unrelated change.\n"

    def rows_with(**changes):
        out = []
        for r in base_rows:
            key = "%s %s" % (r[0], r[1])
            out.append(tuple(changes.get(key, r)))
        return out

    def with_version(files, version, changelog_extra):
        files[".sumela/VERSION"] = version + "\n"
        if changelog_extra is not None:
            files["CHANGELOG.md"] = ("# Changelog\n\n## [Unreleased]\n\n### Changed\n\n"
                                     + changelog_extra + "\n- **Base (v0.1.0).** Text.\n")
        return files

    def raised_tree(version, changelog_extra):
        return with_version({
            "b.md": "b" * 249 + "\n",
            TSV: fixture_table(rows_with(**{
                "eager-member b.md": ("eager-member", "b.md", "250", "-", "-", "no", "grew"),
                "eager-total *": ("eager-total", "*", "360", "-", "-", "no", "grew")})),
        }, version, changelog_extra)

    def dropped_tree(version, changelog_extra):
        # b.md leaves the eager set and the total drops by its size: a smaller number, unseen.
        rows = [r for r in rows_with(**{"eager-total *": ("eager-total", "*", "110", "-", "-",
                                                          "no", "smaller")})
                if r[:2] != ("eager-member", "b.md")]
        return with_version({TSV: fixture_table(rows)}, version, changelog_extra)

    def released(**changes):
        return with_version({TSV: fixture_table(rows_with(**changes))}, "0.2.0", unrelated)

    cases = [
        # (name, edits applied after the tag, expect_pass, substrings the output must contain)
        ("an untouched tree passes with eager 310/310", {}, True, "eager 310/310 B"),
        ("a member over its pin fails", {"a.md": "a" * 100 + "\n"}, False, "a.md: over budget"),
        ("a sum over the total fails while each member fits",
         {TSV: fixture_table(rows_with(**{"eager-total *": ("eager-total", "*", "300", "-", "-",
                                                            "no", "too low")}))},
         False, "eager set over budget"),
        ("a stale member pin fails",
         {TSV: fixture_table(rows_with(**{
             "eager-member a.md": ("eager-member", "a.md", "2101", "-", "-", "no", "loose"),
             "eager-total *": ("eager-total", "*", "2311", "-", "-", "no", "loose")}))},
         False, "a.md: stale pin"),
        ("a stale total pin fails",
         {TSV: fixture_table(rows_with(**{"eager-total *": ("eager-total", "*", "2311", "-", "-",
                                                            "no", "loose")}))},
         False, "eager-total: stale pin"),
        ("a pinned line count is enforced",
         {TSV: fixture_table(rows_with(**{"file a.md": ("file", "a.md", "100", "0", "-", "no",
                                                        "no lines")}))},
         False, "lines > 0 pinned"),
        ("a missing member file fails", {"a.md": None}, False, "pinned file is missing"),
        ("a malformed row fails",
         {TSV: fixture_table(base_rows) + "eager-member\tc.md\t5\t-\tno\tsix columns\n"},
         False, "expected 7 TAB-separated columns"),
        ("CRLF counts as LF", {"a.md": "a" * 98 + "\r\n" + "\r\n"}, True, "eager 310/310 B"),
        ("a raise before the release task passes and is reported",
         raised_tree("0.1.0", None), True, "info raised eager-member b.md 200 -> 250 B vs v0.1.0"),
        ("a raise at release time without a CHANGELOG reason fails",
         raised_tree("0.2.0", unrelated), False,
         "raised eager-member b.md 200 -> 250 B vs v0.1.0 without a reason"),
        ("a raise at release time with a reason for another version fails",
         raised_tree("0.2.0", "- **Bigger (v0.1.9).** The eager budget rose.\n"), False,
         "without a reason"),
        ("a raise at release time with an 'eager budget' bullet passes",
         raised_tree("0.2.0", "- **Bigger (v0.2.0).** The eager budget was raised to 360 B:\n"
                              "  the second member gained a section.\n"), True,
         "reason in the (v0.2.0) CHANGELOG bullet"),
        ("a dropped member row before the release task passes and is reported",
         dropped_tree("0.1.0", None), True,
         ["eager 110/110 B", "info dropped eager-member b.md (pinned at 200 B) vs v0.1.0"]),
        ("a dropped member row at release time without a CHANGELOG reason fails",
         dropped_tree("0.2.0", unrelated), False,
         "dropped eager-member b.md (pinned at 200 B) vs v0.1.0 without a reason"),
        ("a dropped member row at release time with an 'eager budget' bullet passes",
         dropped_tree("0.2.0", "- **Lighter (v0.2.0).** b.md leaves the eager budget: it now\n"
                               "  loads on demand.\n"), True,
         "ok   dropped eager-member b.md (pinned at 200 B) vs v0.1.0 (reason in the (v0.2.0)"),
        ("a lines pin replaced by '-' at release time without a reason fails",
         released(**{"file a.md": ("file", "a.md", "100", "-", "-", "no", "unpinned")}), False,
         "unpinned file a.md lines (was 2) vs v0.1.0 without a reason"),
        ("a row turned overridable at release time without a reason fails",
         released(**{"file a.md": ("file", "a.md", "100", "2", "-", "yes", "overridable")}), False,
         "made file a.md overridable vs v0.1.0 without a reason"),
        ("a lowered pin at release time needs no reason",
         released(**{"file a.md": ("file", "a.md", "100", "1", "-", "no", "tighter")}), True,
         "raises: none vs v0.1.0"),
    ]
    # The tag predates the table: (name, files committed after the tag or None, edits,
    # expect_pass, substrings).
    late_cases = [
        ("with no table at the tag, the commit that added it is the baseline: an unchanged "
         "table passes", {TSV: fixture_table(base_rows)}, {}, True,
         ["raises: none vs ", " (the commit that added %s; v0.1.0 has none)" % TSV]),
        ("with no table at the tag, a raise at release time without a reason fails against the "
         "commit that added it", {TSV: fixture_table(base_rows)}, raised_tree("0.2.0", unrelated),
         False, ["raised eager-member b.md 200 -> 250 B vs ", "without a reason",
                 " (the commit that added %s; v0.1.0 has none)" % TSV]),
        ("with no table at the tag, a dropped row at release time without a reason fails "
         "against the commit that added it", {TSV: fixture_table(base_rows)},
         dropped_tree("0.2.0", unrelated), False,
         ["dropped eager-member b.md (pinned at 200 B) vs ", "without a reason"]),
        ("with no table at the tag and no commit that adds it, raises are reported as not checked",
         None, merged_files({TSV: fixture_table(base_rows)}, raised_tree("0.2.0", unrelated)),
         True, "raises: not checked (v0.1.0 has no %s, and no commit since v0.1.0 adds it)" % TSV),
    ]
    runs = [(name, base, None, edits, expect_pass, needles)
            for name, edits, expect_pass, needles in cases]
    runs += [(name, no_table, later, edits, expect_pass, needles)
             for name, later, edits, expect_pass, needles in late_cases]
    tmp = tempfile.mkdtemp(prefix="sumela-eager-selftest-")
    try:
        for i, (name, tagged, later, edits, expect_pass, needles) in enumerate(runs):
            repo, env = make_repo(tmp, "case%02d" % i, tagged, later=later)
            for rel, content in edits.items():
                if content is None:
                    (repo / rel).unlink()
                else:
                    write(repo, {rel: content})
            problems, report, summary = run_check(repo, env)
            text = "\n".join(problems + report + [summary])
            needles = [needles] if isinstance(needles, str) else needles
            good = (not problems) == expect_pass and all(n in text for n in needles)
            print("  %s %s" % ("ok  " if good else "FAIL", name))
            if not good:
                failed.append(name)
                for line in (problems + report + [summary]):
                    print("         " + line)
        # No tag at all: the raise check cannot run, which is a failure, not a skip.
        repo, env = make_repo(tmp, "untagged", base, tag=None)
        problems, _, _ = run_check(repo, env)
        good = any("fetch-depth: 0" in p for p in problems)
        print("  %s %s" % ("ok  " if good else "FAIL", "no reference tag fails"))
        if not good:
            failed.append("no reference tag fails")
            for line in problems:
                print("         " + line)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return failed


# --------------------------------------------------------------------------
def main(argv):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    except (AttributeError, ValueError):
        pass
    args = set(argv)
    unknown = args - {"--self-test", "--no-self-test"}
    if unknown or {"--self-test", "--no-self-test"} <= args:
        print(__doc__.split("\n\n")[0])
        print("usage: python3 -I tests/test_eager_budget.py [--self-test | --no-self-test]")
        return 2
    failed = []
    if "--no-self-test" not in args:
        failed = self_test()
        if failed:
            print("FAILED: the self-test shows the budget guard is broken (%d case(s))" % len(failed))
            return 1
        if "--self-test" in args:
            print("self-test passed")
            return 0
        print()
    problems, report, summary = run_check(REPO)
    print("eager budget (%s)" % TSV)
    for line in report:
        print("  " + line)
    for p in problems:
        print("  FAIL " + p)
    print(summary)
    if problems:
        print("FAILED: %d budget check(s)" % len(problems))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
