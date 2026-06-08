"""Task 6/7 — file-queue IPC + single-instance lock."""
import os

import pytest

from client.filequeue import FileQueue
from client.lock import SingleInstanceLock, AlreadyRunning


def test_outbox_roundtrip(tmp_path):
    q = FileQueue(str(tmp_path / ".relay"))
    q.put_outbox("o1", {"to": "onur", "body": "Q?"})
    drained = q.drain_outbox()
    assert len(drained) == 1
    path, obj = drained[0]
    assert obj["to"] == "onur"
    q.remove(path)
    assert q.drain_outbox() == []


def test_inbox_roundtrip(tmp_path):
    q = FileQueue(str(tmp_path / ".relay"))
    q.put_inbox("i1", {"from": "alice", "content": "answer"})
    items = q.list_inbox()
    assert len(items) == 1 and items[0][1]["from"] == "alice"


def test_atomic_write_leaves_no_tmp_and_skips_tmp(tmp_path):
    base = str(tmp_path / ".relay")
    q = FileQueue(base)
    q.put_outbox("o1", {"x": 1})
    files = os.listdir(os.path.join(base, "outbox"))
    assert files == ["o1.json"]                      # no leftover .tmp
    # a stray .tmp must be ignored by readers
    open(os.path.join(base, "outbox", ".wip-foo.tmp"), "w").write("partial{")
    assert [obj for _, obj in q.drain_outbox()] == [{"x": 1}]


def test_ordering_is_stable(tmp_path):
    q = FileQueue(str(tmp_path / ".relay"))
    for i in range(3):
        q.put_inbox("i%d" % i, {"n": i})
    assert [obj["n"] for _, obj in q.list_inbox()] == [0, 1, 2]


# ----------------------------------------------------------------------- single-instance

def test_single_instance_lock_blocks_second(tmp_path):
    p = str(tmp_path / ".relay" / "daemon.pid")
    first = SingleInstanceLock(p).acquire()
    try:
        with pytest.raises(AlreadyRunning):
            SingleInstanceLock(p).acquire()
    finally:
        first.release()


def test_lock_released_allows_reacquire(tmp_path):
    p = str(tmp_path / ".relay" / "daemon.pid")
    with SingleInstanceLock(p):
        pass
    # after release, a new instance can acquire
    second = SingleInstanceLock(p).acquire()
    second.release()
