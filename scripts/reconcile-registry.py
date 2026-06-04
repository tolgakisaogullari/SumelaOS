#!/usr/bin/env python3
"""
reconcile-registry.py — keep SKILL_REGISTRY.md in sync with the skills on disk.

After a framework update (or any time), this registers any core skill that exists
on disk but is missing from the registry, and flags registry entries whose file is
gone. It removes the old "reconcile the registry by hand" homework.

Scope:
  * Handles core skills only: `.sumela/skills/<name>/SKILL.md` (one frontmatter
    `name` + `description` each). New entries get activation="lazy" and the
    description is copied VERBATIM from the skill's frontmatter (the parity contract).
  * Does NOT touch memory-plugin entries (`.sumela/memory-plugins/.../SKILL.md`) —
    those are managed by setup, conditional on plugin selection.
  * Does NOT auto-delete orphan entries (a missing path may be an intentionally
    not-yet-copied plugin) — it reports them for the human to resolve.
  * Does NOT handle RULE_REGISTRY.md — rules need phase/stack/activation metadata
    that isn't in the rule files; reconcile those via /initSumela or /evolve.

Usage:
  python3 scripts/reconcile-registry.py            # add missing skill entries; report orphans
  python3 scripts/reconcile-registry.py --check     # report only; exit 1 if out of sync
  python3 scripts/reconcile-registry.py --stats     # print canonical skill counts (source of truth for docs)
"""
import sys
import os
import re

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

CHECK = "--check" in sys.argv[1:]
STATS = "--stats" in sys.argv[1:]


def find_root(start):
    cur = os.path.abspath(start)
    while cur != os.path.dirname(cur):
        if os.path.isdir(os.path.join(cur, ".sumela")):
            return cur
        cur = os.path.dirname(cur)
    return None


ROOT = find_root(os.getcwd())
if not ROOT:
    print("reconcile-registry: no .sumela/ found from this directory upward.")
    sys.exit(0)

REGISTRY = os.path.join(ROOT, ".sumela", "SKILL_REGISTRY.md")
SKILLS_DIR = os.path.join(ROOT, ".sumela", "skills")
RULE_REGISTRY = os.path.join(ROOT, ".sumela", "RULE_REGISTRY.md")
DOMAINS_DIR = os.path.join(ROOT, ".sumela", "rules", "domains")
if not os.path.isfile(REGISTRY):
    print(f"reconcile-registry: {REGISTRY} not found — nothing to do.")
    sys.exit(0)


def domain_rule_parity():
    """Domain-conditional rule <-> file parity.

    The `.sumela/rules/domains/` path prefix is exclusive to domain rules, so a
    registered <path> under it identifies a domain rule without needing the
    activation attribute. Returns (missing_files, unregistered_files):
      * missing_files     — registered in RULE_REGISTRY.md but absent on disk
      * unregistered_files — present under .sumela/rules/domains/ but not registered
    Returns ([], []) when there is nothing to check (no generated RULE_REGISTRY.md).
    """
    if not os.path.isfile(RULE_REGISTRY):
        return [], []
    with open(RULE_REGISTRY, encoding="utf-8") as f:
        rr = f.read()
    reg_paths = set(
        m.strip() for m in re.findall(r"<path>\s*(\.sumela/rules/domains/[^<]+?)\s*</path>", rr)
    )
    disk_paths = set()
    if os.path.isdir(DOMAINS_DIR):
        for entry in sorted(os.listdir(DOMAINS_DIR)):
            if entry.endswith(".md") and os.path.isfile(os.path.join(DOMAINS_DIR, entry)):
                disk_paths.add(f".sumela/rules/domains/{entry}")
    missing = sorted(p for p in reg_paths if not os.path.isfile(os.path.join(ROOT, p)))
    unregistered = sorted(disk_paths - reg_paths)
    return missing, unregistered


def read_frontmatter(path):
    """Return (name, description) from a SKILL.md frontmatter, or (None, None)."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if not text.startswith("---"):
        return None, None
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None, None
    fm = parts[1]
    name = desc = None
    for line in fm.splitlines():
        m = re.match(r"\s*name\s*:\s*(.+?)\s*$", line)
        if m and name is None:
            name = m.group(1).strip().strip('"').strip("'")
        m = re.match(r'\s*description\s*:\s*(.+?)\s*$', line)
        if m and desc is None:
            desc = m.group(1).strip()
            if (desc.startswith('"') and desc.endswith('"')) or (desc.startswith("'") and desc.endswith("'")):
                desc = desc[1:-1]
    return name, desc


with open(REGISTRY, encoding="utf-8") as f:
    reg_text = f.read()

reg_blocks = re.findall(r"<skill\b[^>]*>(.*?)</skill>", reg_text, re.S)
registered_names = set()
registered_paths = []
for b in reg_blocks:
    n = re.search(r"<name>(.*?)</name>", b, re.S)
    p = re.search(r"<path>(.*?)</path>", b, re.S)
    if n:
        registered_names.add(n.group(1).strip())
    if p:
        registered_paths.append(p.group(1).strip())

# --stats: emit the canonical skill counts (the single source of truth for any
# number quoted in docs). README's drift guard (validate-structure.sh) compares
# the numbers it prints against these, so docs can never silently diverge.
if STATS:
    dir_count = 0
    if os.path.isdir(SKILLS_DIR):
        for entry in sorted(os.listdir(SKILLS_DIR)):
            if os.path.isfile(os.path.join(SKILLS_DIR, entry, "SKILL.md")):
                dir_count += 1
    loadable = [p for p in registered_paths if p.startswith(".sumela/skills/")]
    plugins = [p for p in registered_paths if "memory-plugins/" in p]
    # Domain rules live in RULE_REGISTRY.md (not the skill registry) — count their
    # registered paths under the exclusive .sumela/rules/domains/ prefix.
    dom_count = 0
    if os.path.isfile(RULE_REGISTRY):
        with open(RULE_REGISTRY, encoding="utf-8") as f:
            dom_count = len(re.findall(r"<path>\s*\.sumela/rules/domains/[^<]+?</path>", f.read()))
    print(f"skill_workflows={dir_count}")      # one SKILL.md dir = one workflow
    print(f"loadable_skills={len(loadable)}")   # registry skills/ paths (incl. sub-skills)
    print(f"plugin_skills={len(plugins)}")      # memory-plugin entries (conditional)
    print(f"domain_rules={dom_count}")          # domain-conditional rule entries (team taxonomy)
    sys.exit(0)

# 1) Skills on disk (core skills dir) missing from the registry.
unregistered = []  # (name, description, relpath)
if os.path.isdir(SKILLS_DIR):
    for entry in sorted(os.listdir(SKILLS_DIR)):
        skill_md = os.path.join(SKILLS_DIR, entry, "SKILL.md")
        if not os.path.isfile(skill_md):
            continue
        name, desc = read_frontmatter(skill_md)
        if not name:
            continue
        relpath = os.path.relpath(skill_md, ROOT).replace(os.sep, "/")
        # Skip if EITHER the name OR the path is already registered. The path guard
        # prevents a silent duplicate when a skill's frontmatter `name` has drifted
        # from its registry <name> (that parity drift is for /evolve to fix, not us).
        if name in registered_names or relpath in registered_paths:
            continue
        desc = desc or ""
        # The registry is pseudo-XML parsed by regex; a closing tag inside the
        # description/name would corrupt the block. Refuse rather than emit broken XML.
        if "</description>" in desc or "</skill>" in desc or "</name>" in name:
            print(f"  SKIP (reserved tag in metadata, register by hand): {name}  ({relpath})")
            continue
        unregistered.append((name, desc, relpath))

# 2) Registry entries whose path no longer exists (orphans) — report, don't delete.
orphans = [p for p in registered_paths if not os.path.isfile(os.path.join(ROOT, p))]

# 3) Domain-conditional rule <-> file parity (RULE_REGISTRY.md). Not auto-fixable
#    here (a domain rule needs a scope name + description + matrix row written
#    together by setup / init-sumela / onboard-sumela / evolve) — report only.
dom_missing, dom_unregistered = domain_rule_parity()

if not unregistered and not orphans and not dom_missing and not dom_unregistered:
    print("reconcile-registry: SKILL_REGISTRY.md is in sync with skills on disk.")
    sys.exit(0)

for name, _desc, relpath in unregistered:
    print(f"  unregistered skill: {name}  ({relpath})")
for p in orphans:
    print(f"  ORPHAN registry entry (path missing): {p}")
for p in dom_missing:
    print(f"  MISSING domain rule file (registered in RULE_REGISTRY, not on disk): {p}")
for p in dom_unregistered:
    print(f"  UNREGISTERED domain rule file (on disk, no RULE_REGISTRY entry): {p}")

if CHECK:
    print("reconcile-registry: registry is OUT OF SYNC (run: python3 scripts/reconcile-registry.py).")
    sys.exit(1)

# Apply: insert new <skill> entries before </available_skills>.
if unregistered:
    tag = "</available_skills>"
    if tag not in reg_text:
        print("reconcile-registry: could not find </available_skills> — not modifying.", file=sys.stderr)
        sys.exit(1)
    block = ""
    for name, desc, relpath in unregistered:
        block += (
            f'\n<skill activation="lazy">\n'
            f"<name>{name}</name>\n"
            f"<description>{desc}</description>\n"
            f"<path>{relpath}</path>\n"
            f"</skill>\n"
        )
    reg_text = reg_text.replace(tag, block + "\n" + tag, 1)
    with open(REGISTRY, "w", encoding="utf-8") as f:
        f.write(reg_text)
    print(f"reconcile-registry: registered {len(unregistered)} skill(s) (activation=lazy).")

if orphans:
    print(f"reconcile-registry: {len(orphans)} orphan entry(ies) above were NOT removed — "
          "delete them by hand if the skill was intentionally removed, or restore the file.")
if dom_missing or dom_unregistered:
    print(f"reconcile-registry: {len(dom_missing) + len(dom_unregistered)} domain rule parity "
          "issue(s) above were NOT auto-fixed — resolve via /onboardSumela or /evolve "
          "(register the rule + add its <domain_scopes> row + matrix cell, or remove the file).")
sys.exit(0)
