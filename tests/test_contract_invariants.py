#!/usr/bin/env python3
"""Contract invariants: the load-bearing sentences of the instruction text, pinned.

Some sentences carry the framework: the activation imperative, the authority ranks, the
SECURITY MANDATE, the DEVELOPMENT GATE, the two NEVER lines of signal capture. An edit that
rewords one of them changes what every consumer's agent does, and before this suite nothing
noticed. Each `tests/invariants/<name>.pins` file pins one unit (one file):

    # unit: <repo path>                 the first line, always
    require<TAB><literal>               the literal occurs in the unit
    forbid<TAB><literal>                the literal does not occur
    count<TAB><n><TAB><literal>         the literal occurs exactly n times

Blank lines and lines that start with '#' are comments. A literal is compared byte for byte
after reading CRLF as LF. A pins file with no rows fails: it would assert nothing.

Rewording a pinned sentence is allowed and reviewed: edit the pin in the same change. The
release that rewrites the contract extends its pins file (spec section 3.2).

A self-test runs first. It checks the parser and each row kind on synthetic files, then
MUTATES the real pinned units in memory: for every row of every pins file it deletes the
lines that hold a required literal, breaks one character of it, or adds a forbidden or
counted one, and requires the check to fail each time. So no pin can silently stop biting.
A pins file that does not parse, a unit that does not load and a row that already fails are
left to the check, which runs next and names the problem.

Usage (Python is optional in this repository; run it isolated):
    python3 -I tests/test_contract_invariants.py                 # self-test, then the check
    python3 -I tests/test_contract_invariants.py --self-test     # the self-test only
    python3 -I tests/test_contract_invariants.py --no-self-test  # the check only
Exit: 0 every pin holds; 1 a pin or the self-test failed; 2 usage error. Standard library only.
"""
import re
import shutil
import sys
import tempfile
from pathlib import Path, PurePosixPath

REPO = Path(__file__).resolve().parent.parent
PINS_DIR = "tests/invariants"
KINDS = ("require", "forbid", "count")
UNIT_RE = re.compile(r"^# unit: (\S.*)$")


def parse_pins(text, where):
    """(unit, rows, problems). rows: (lineno, kind, n, literal); n is None unless count."""
    lines = text.split("\n")
    problems, rows = [], []
    first = lines[0].rstrip("\r").lstrip("\ufeff") if lines else ""
    m = UNIT_RE.match(first)
    unit = m.group(1).strip() if m else None
    if unit is None:
        problems.append("%s:1: the first line must be '# unit: <repo path>'" % where)
    for lineno, raw in enumerate(lines[1:], 2):
        row = raw.rstrip("\r")
        if not row.strip() or row.startswith("#"):
            continue
        kind, sep, rest = row.partition("\t")
        if not sep or kind not in KINDS:
            problems.append("%s:%d: a row starts with require, forbid or count, then a TAB"
                            % (where, lineno))
            continue
        n = None
        literal = rest
        if kind == "count":
            num, sep2, literal = rest.partition("\t")
            if not sep2 or not num.isdigit():
                problems.append("%s:%d: count<TAB><n><TAB><literal> needs a whole number n"
                                % (where, lineno))
                continue
            n = int(num)
        if not literal.strip():
            problems.append("%s:%d: empty literal" % (where, lineno))
            continue
        rows.append((lineno, kind, n, literal))
    if unit is not None and not rows and not problems:
        problems.append("%s: no rows; a pins file must assert something" % where)
    return unit, rows, problems


def load_unit(repo, unit, where):
    """(text, problem). The unit must be a file inside the repository, UTF-8."""
    pure = PurePosixPath(unit)
    if pure.is_absolute() or ".." in pure.parts or "\\" in unit:
        return None, "%s: unit %r must be a repository path without '..'" % (where, unit)
    path = Path(repo) / unit
    if not path.is_file():
        return None, "%s: unit %s does not exist (renamed? move the pins with it)" % (where, unit)
    try:
        text = path.read_bytes().decode("utf-8")
    except UnicodeDecodeError as exc:
        return None, "%s: unit %s is not UTF-8 (%s)" % (where, unit, exc)
    return text.lstrip("\ufeff").replace("\r\n", "\n"), None


def failing_rows(rows, text):
    """[(lineno, kind, literal, why)] for the rows that do not hold on text."""
    out = []
    for lineno, kind, n, literal in rows:
        found = text.count(literal)
        if kind == "require" and found == 0:
            out.append((lineno, kind, literal, "missing"))
        elif kind == "forbid" and found:
            out.append((lineno, kind, literal, "present %d time(s)" % found))
        elif kind == "count" and found != n:
            out.append((lineno, kind, literal, "found %d time(s), pinned %d" % (found, n)))
    return out


def short(literal, width=110):
    return literal if len(literal) <= width else literal[:width - 3] + "..."


def run_check(repo):
    """(problems, report, summary). Never prints."""
    repo = Path(repo)
    problems, report = [], []
    pins_files = sorted((repo / PINS_DIR).glob("*.pins"))
    if not pins_files:
        return ["no pins files in %s/" % PINS_DIR], report, "0 pins checked"
    held = 0
    for pf in pins_files:
        where = pf.relative_to(repo).as_posix()
        try:
            content = pf.read_bytes().decode("utf-8")
        except UnicodeDecodeError as exc:
            problems.append("%s: not UTF-8 (%s)" % (where, exc))
            continue
        unit, rows, parse_problems = parse_pins(content, where)
        problems.extend(parse_problems)
        if unit is None:
            continue
        text, problem = load_unit(repo, unit, where)
        if problem:
            problems.append(problem)
            continue
        fails = failing_rows(rows, text)
        for lineno, kind, literal, why in fails:
            problems.append("%s:%d: %s %s in %s: %s" % (where, lineno, kind, why, unit, short(literal)))
        held += len(rows) - len(fails)
        if not fails:
            report.append("ok   %s: %d pin(s) hold in %s" % (where, len(rows), unit))
    summary = "%d pins hold across %d file(s)" % (held, len(pins_files))
    return problems, report, summary


# --------------------------------------------------------------------------
# self-test
# --------------------------------------------------------------------------
def self_test():
    print("self-test (contract invariants)")
    failed = []

    def verdict(name, good, detail=()):
        print("  %s %s" % ("ok  " if good else "FAIL", name))
        if not good:
            failed.append(name)
            for line in detail:
                print("         " + line)

    unit_text = ("# Demo contract\n"
                 "You MUST load the standard BEFORE drafting code.\n"
                 "NEVER include secrets in evidence.\n"
                 "Rank one. Rank one.\n")
    good_pins = ("# unit: docs/unit.md\n"
                 "# comment line\n\n"
                 "require\tYou MUST load the standard BEFORE drafting code.\n"
                 "forbid\tskip the standard\n"
                 "count\t2\tRank one.\n")
    cases = [
        # (name, unit bytes or None, pins text, expect_pass, needle in the output)
        ("valid pins hold", unit_text, good_pins, True, "3 pins hold across 1 file(s)"),
        ("a deleted MUST line fails", unit_text.replace(
            "You MUST load the standard BEFORE drafting code.\n", ""), good_pins, False,
         "require missing"),
        ("a reworded pinned phrase fails", unit_text.replace("MUST load", "should load"),
         good_pins, False, "require missing"),
        ("a forbidden phrase fails", unit_text + "You may skip the standard.\n", good_pins, False,
         "forbid present 1 time(s)"),
        ("a count above its pin fails", unit_text + "Rank one.\n", good_pins, False,
         "found 3 time(s), pinned 2"),
        ("a count below its pin fails", unit_text.replace("Rank one. Rank one.", "Rank one."),
         good_pins, False, "found 1 time(s), pinned 2"),
        ("CRLF unit and CRLF pins hold", unit_text.replace("\n", "\r\n"),
         good_pins.replace("\n", "\r\n"), True, "3 pins hold"),
        ("a missing unit header fails", unit_text, good_pins.split("\n", 1)[1], False,
         "the first line must be '# unit: <repo path>'"),
        ("an unknown row kind fails", unit_text, good_pins + "requires\tYou MUST\n", False,
         "a row starts with require, forbid or count"),
        ("a count without a number fails", unit_text, good_pins + "count\tx\tRank one.\n",
         False, "needs a whole number n"),
        ("an empty literal fails", unit_text, good_pins + "require\t \n", False,
         "empty literal"),
        ("a pins file with no rows fails", unit_text, "# unit: docs/unit.md\n# nothing\n", False,
         "no rows"),
        ("a missing unit file fails", None, good_pins, False, "does not exist"),
        ("a unit outside the repository fails", unit_text,
         good_pins.replace("docs/unit.md", "../unit.md", 1), False, "without '..'"),
    ]
    tmp = tempfile.mkdtemp(prefix="sumela-invariants-selftest-")
    try:
        for i, (name, unit, pins, expect_pass, needle) in enumerate(cases):
            repo = Path(tmp) / ("case%02d" % i)
            (repo / PINS_DIR).mkdir(parents=True)
            (repo / "docs").mkdir()
            if unit is not None:
                (repo / "docs/unit.md").write_bytes(unit.encode("utf-8"))
            (repo / PINS_DIR / "unit.pins").write_bytes(pins.encode("utf-8"))
            problems, report, summary = run_check(repo)
            out = problems + report + [summary]
            verdict(name, (not problems) == expect_pass and any(needle in x for x in out), out)
        empty = Path(tmp) / "empty"
        (empty / PINS_DIR).mkdir(parents=True)
        problems, _, _ = run_check(empty)
        verdict("no pins files at all fails", any("no pins files" in p for p in problems), problems)

        # The mutation pass on synthetic files: it bites a holding pin, and it leaves a pins
        # file that does not parse to the check, so the check's message is the one printed.
        repo = Path(tmp) / "mutate-good"
        (repo / PINS_DIR).mkdir(parents=True)
        (repo / "docs").mkdir()
        (repo / "docs/unit.md").write_bytes(unit_text.encode("utf-8"))
        (repo / PINS_DIR / "unit.pins").write_bytes(good_pins.encode("utf-8"))
        mutations, holding, unbitten = mutation_pass(repo)
        verdict("the mutation pass breaks each holding synthetic pin (%d mutations)" % mutations,
                holding == 3 and mutations == 5 and not unbitten, unbitten)
        (repo / PINS_DIR / "unit.pins").write_bytes(
            (good_pins + "requires\tYou MUST\n").encode("utf-8"))
        mutations, holding, unbitten = mutation_pass(repo)
        problems, _, _ = run_check(repo)
        verdict("a pins file that does not parse is skipped by the mutation pass, and the check "
                "names the bad row", (mutations, holding, unbitten) == (0, 0, [])
                and any("a row starts with require, forbid or count" in p for p in problems),
                problems)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # Mutation: every real pin must fail when the text it guards is broken.
    mutations, holding, unbitten = mutation_pass(REPO)
    if holding:
        verdict("each real pin fails when its text is broken (%d mutations)" % mutations,
                mutations > 0 and not unbitten, unbitten or ["no mutation ran"])
    else:
        print("  skip each real pin fails when its text is broken: no real pin holds now, "
              "so the check below fails and says why")
    return failed


def mutation_pass(repo):
    """(mutations, holding, unbitten): break the text each holding pin guards, in memory, and
    record the pins the break does not fail. A pins file that does not parse, a unit that does
    not load and a row that already fails are the check's to report, with the actionable
    message, so they are skipped here and are no self-test failure. With no holding row the
    check itself fails (no pins files, a parse or load problem, or every row failing)."""
    repo = Path(repo)
    mutations, holding, unbitten = 0, 0, []
    for pf in sorted((repo / PINS_DIR).glob("*.pins")):
        where = pf.relative_to(repo).as_posix()
        unit, rows, problems = parse_pins(pf.read_bytes().decode("utf-8", "replace"), where)
        text, problem = load_unit(repo, unit, where) if unit else (None, "no unit")
        if problems or problem:
            continue  # the real check reports it; there is nothing sound to mutate
        for row in rows:
            if failing_rows([row], text):
                continue  # already failing: the real check reports it
            holding += 1
            lineno, kind, n, literal = row
            variants = []
            if kind == "require":
                variants.append(("delete its line(s)", "\n".join(
                    l for l in text.split("\n") if literal not in l)))
                mid = len(literal) // 2
                broken = literal[:mid] + ("y" if literal[mid] == "x" else "x") + literal[mid + 1:]
                variants.append(("break one character", text.replace(literal, broken)))
            else:
                variants.append(("add one occurrence", text + "\n" + literal + "\n"))
                if kind == "count" and n:
                    variants.append(("remove one occurrence", text.replace(literal, "", 1)))
            for label, mutated in variants:
                mutations += 1
                if not failing_rows([row], mutated):
                    unbitten.append("%s:%d %s: %s does not fail it" % (where, lineno, kind, label))
    return mutations, holding, unbitten


def main(argv):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    except (AttributeError, ValueError):
        pass
    args = set(argv)
    if args - {"--self-test", "--no-self-test"} or {"--self-test", "--no-self-test"} <= args:
        print("usage: python3 -I tests/test_contract_invariants.py [--self-test | --no-self-test]")
        return 2
    if "--no-self-test" not in args:
        failed = self_test()
        if failed:
            print("FAILED: the self-test shows the pin checker is broken (%d case(s))" % len(failed))
            return 1
        if "--self-test" in args:
            print("self-test passed")
            return 0
        print()
    problems, report, summary = run_check(REPO)
    print("contract invariants (%s/*.pins)" % PINS_DIR)
    for line in report:
        print("  " + line)
    for p in problems:
        print("  FAIL " + p)
    print(summary)
    if problems:
        print("FAILED: %d invariant check(s)" % len(problems))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
