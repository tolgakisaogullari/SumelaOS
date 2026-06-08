#!/usr/bin/env python3
"""ask.py — queue a question for a teammate (the daemon delivers it). File-queue only."""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # plugin root

from client._cli_common import role_map, runtime_dir  # noqa: E402 (after path bootstrap)
from client.agent_cli import do_ask
from client.filequeue import FileQueue


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Ask a teammate a question via the relay.")
    ap.add_argument("question")
    ap.add_argument("--to", help="explicit teammate id")
    ap.add_argument("--domain", help="route by committed role/domain")
    ap.add_argument("--fanout", action="store_true",
                    help="send to ALL holders of the domain (each then sees the question)")
    a = ap.parse_args(argv)
    try:
        ids = do_ask(FileQueue(runtime_dir()), a.question, to=a.to, domain=a.domain,
                     role_map=role_map(), fanout=a.fanout)
    except ValueError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2
    print("queued %d question(s): %s" % (len(ids), ", ".join(ids)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
