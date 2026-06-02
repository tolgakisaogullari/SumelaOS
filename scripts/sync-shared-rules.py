#!/usr/bin/env python3
"""
sync-shared-rules.py — distribute org/monorepo-shared rules into THIS install.

In a monorepo (or any repo with several SumelaOS installs), rules that every package
must obey shouldn't be copy-pasted into each install by hand. Put them ONCE in
`.sumela-shared/rules/*.md` at the repo/monorepo root; this script materialises them
into the current install and registers them so the normal rule loader picks them up:

  * Copies each `.sumela-shared/rules/<name>.md` to `<install>/.sumela/rules/<name>.md`
    with a managed-marker header (so it's clear they are synced, not hand-authored,
    and so `update.sh` / a human leaves them alone — edit the source, then re-sync).
  * Registers each in this install's `RULE_REGISTRY.md` as
    `<rule activation="universal" applies_phases="all">` if absent. Universal rules
    are picked up by the matrix formula automatically, so NO phase/stack judgement is
    needed — which is exactly why shared org rules can be auto-registered (project- and
    stack-specific rules still go through /evolve).
  * Reports (never deletes) a synced rule whose source has disappeared.

Anchoring: self-locates the nearest `.sumela/` upward (the install), then finds the
nearest ancestor containing `.sumela-shared/rules/` (the shared root). No shared root
or no shared rules -> nothing to do (exit 0).

Usage:
  python3 scripts/sync-shared-rules.py            # sync content + register; report orphans
  python3 scripts/sync-shared-rules.py --check     # report only; exit 1 if out of sync
"""
import sys
import os
import re

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

CHECK = "--check" in sys.argv[1:]
MARKER = ("<!-- SUMELA-SHARED-RULE: synced from .sumela-shared/rules/{name} — edit there, "
          "then run scripts/sync-shared-rules.(sh|ps1). Do not edit here. -->")
MARKER_PREFIX = "<!-- SUMELA-SHARED-RULE:"


def find_up(start, probe_isdir=None, probe_isfile=None):
    cur = os.path.abspath(start)
    while True:
        if probe_isdir and os.path.isdir(os.path.join(cur, probe_isdir)):
            return cur
        if probe_isfile and os.path.isfile(os.path.join(cur, probe_isfile)):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return None
        cur = parent


INSTALL = find_up(os.getcwd(), probe_isdir=".sumela")
if not INSTALL:
    print("sync-shared-rules: no .sumela/ found from this directory upward.")
    sys.exit(0)

SHARED_ROOT = find_up(INSTALL, probe_isdir=os.path.join(".sumela-shared", "rules"))
SHARED_DIR = os.path.join(SHARED_ROOT, ".sumela-shared", "rules") if SHARED_ROOT else None
if not SHARED_DIR or not os.path.isdir(SHARED_DIR):
    print("sync-shared-rules: no .sumela-shared/rules/ found above this install — nothing to do.")
    sys.exit(0)

RULES_DIR = os.path.join(INSTALL, ".sumela", "rules")
REGISTRY = os.path.join(INSTALL, ".sumela", "RULE_REGISTRY.md")
os.makedirs(RULES_DIR, exist_ok=True)


def describe(text):
    """Best-effort one-line description: first '# Heading' or first prose line."""
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith(MARKER_PREFIX) or s.startswith("<!--"):
            continue
        if s.startswith("#"):
            return s.lstrip("# ").strip()
        return s
    return ""


def desired_content(name, src_text):
    return MARKER.format(name=name) + "\n" + src_text


# --- Gather shared rules and compute drift ----------------------------------
shared = []  # (name, src_path, desired_text, description)
for entry in sorted(os.listdir(SHARED_DIR)):
    if not entry.endswith(".md"):
        continue
    src = os.path.join(SHARED_DIR, entry)
    if not os.path.isfile(src):
        continue
    with open(src, encoding="utf-8") as f:
        src_text = f.read()
    shared.append((entry, src, desired_content(entry, src_text), describe(src_text)))

reg_text = ""
if os.path.isfile(REGISTRY):
    with open(REGISTRY, encoding="utf-8") as f:
        reg_text = f.read()
# Match real <path> entries only: a path never contains '<', so [^<]* won't span the
# literal "<path>" tokens that appear in the registry's <usage> prose (e.g. "cat <path>").
registered_paths = {p.strip() for p in re.findall(r"<path>([^<]*)</path>", reg_text)}

content_drift = []     # (name) target missing or differs
needs_register = []    # (name, description, relpath)
for name, _src, desired, desc in shared:
    relpath = f".sumela/rules/{name}"
    target = os.path.join(RULES_DIR, name)
    cur = None
    if os.path.isfile(target):
        with open(target, encoding="utf-8") as f:
            cur = f.read()
    if cur != desired:
        content_drift.append(name)
    if relpath not in registered_paths:
        needs_register.append((name, desc, relpath))

# Orphans: synced shared rules (managed marker) whose source no longer exists.
shared_names = {n for n, _s, _d, _x in shared}
orphans = []
if os.path.isdir(RULES_DIR):
    for entry in sorted(os.listdir(RULES_DIR)):
        if not entry.endswith(".md") or entry in shared_names:
            continue
        p = os.path.join(RULES_DIR, entry)
        try:
            with open(p, encoding="utf-8") as f:
                head = f.read(200)
        except OSError:
            continue
        if head.startswith(MARKER_PREFIX):
            orphans.append(entry)

if not content_drift and not needs_register and not orphans:
    print("sync-shared-rules: this install is in sync with .sumela-shared/rules/.")
    sys.exit(0)

for n in content_drift:
    print(f"  shared rule out of date: {n}")
for n, _d, _p in needs_register:
    print(f"  shared rule not registered: {n}")
for n in orphans:
    print(f"  ORPHAN synced shared rule (source gone): .sumela/rules/{n}")

if CHECK:
    print("sync-shared-rules: OUT OF SYNC (run: python3 scripts/sync-shared-rules.py).")
    sys.exit(1)

# --- Apply: write content, then register --------------------------------------
for name, _src, desired, _desc in shared:
    target = os.path.join(RULES_DIR, name)
    cur = None
    if os.path.isfile(target):
        with open(target, encoding="utf-8") as f:
            cur = f.read()
    if cur != desired:
        with open(target, "w", encoding="utf-8") as f:
            f.write(desired)
        print(f"sync-shared-rules: synced .sumela/rules/{name}")

if needs_register:
    if not reg_text:
        print(f"sync-shared-rules: {REGISTRY} not found — content synced, but register the "
              f"{len(needs_register)} rule(s) via /evolve.", file=sys.stderr)
    else:
        block = ""
        for name, desc, relpath in needs_register:
            if "</description>" in desc or "</rule>" in desc or ">" in name or "<" in name:
                print(f"  SKIP register (reserved tag in metadata): {name}", file=sys.stderr)
                continue
            block += (
                '\n<rule activation="universal" applies_phases="all">\n'
                f"<name>{os.path.splitext(name)[0]}</name>\n"
                f"<description>{desc}</description>\n"
                f"<path>{relpath}</path>\n"
                f"</rule>\n"
            )
        if block:
            # Insert before the phase matrix if present, else before the closing tag.
            anchor = "<phase_to_rule_matrix>"
            if anchor not in reg_text:
                anchor = "</rules_system>"
            if anchor in reg_text:
                reg_text = reg_text.replace(anchor, block + "\n" + anchor, 1)
                with open(REGISTRY, "w", encoding="utf-8") as f:
                    f.write(reg_text)
                print(f"sync-shared-rules: registered {block.count('<rule ')} shared rule(s) as universal.")
            else:
                print("sync-shared-rules: could not find an insert point in RULE_REGISTRY.md — "
                      "register the rule(s) via /evolve.", file=sys.stderr)

if orphans:
    print(f"sync-shared-rules: {len(orphans)} orphan(s) above were NOT removed — delete them by "
          "hand (and their RULE_REGISTRY entry) if the shared rule was intentionally retired.")
sys.exit(0)
