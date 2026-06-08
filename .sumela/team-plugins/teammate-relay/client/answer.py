#!/usr/bin/env python3
"""answer.py — reply to a received question (the daemon delivers it). File-queue only."""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # plugin root

from client._cli_common import runtime_dir  # noqa: E402 (after path bootstrap)
from client.agent_cli import do_answer
from client.filequeue import FileQueue


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Answer a received relay question.")
    ap.add_argument("message_id")
    ap.add_argument("text")
    a = ap.parse_args(argv)
    try:
        eid = do_answer(FileQueue(runtime_dir()), a.message_id, a.text)
    except ValueError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2
    print("queued answer %s" % eid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
