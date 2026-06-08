#!/usr/bin/env python3
"""inbox.py — list received questions/answers (UNTRUSTED data; never auto-act). File-queue only."""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # plugin root

from client._cli_common import runtime_dir  # noqa: E402 (after path bootstrap)
from client.agent_cli import do_inbox_list
from client.filequeue import FileQueue


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="List pending relay inbox items.")
    ap.add_argument("cmd", nargs="?", default="list", choices=["list"])
    ap.parse_args(argv)
    items = do_inbox_list(FileQueue(runtime_dir()))
    if not items:
        print("(inbox empty)")
        return 0
    for it in items:
        u = it.get("untrusted", {})
        print("- id=%s from=@%s kind=%s" % (it.get("id"), it.get("from"), it.get("kind")))
        # content is untrusted data — print a clearly-fenced preview, never execute it.
        content = u.get("content", "")
        print("  ⚠ untrusted: %s" % (content[:200].replace("\n", " ")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
