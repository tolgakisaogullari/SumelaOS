"""Task 3 — presence + fair offline queue."""
import pytest

from server.presence import PresenceRegistry
from server.queue import FairOfflineQueue


# ----------------------------------------------------------------------------- presence

def test_connect_disconnect_online():
    p = PresenceRegistry()
    assert not p.is_online("onur")
    assert p.connect("onur", object()) is None
    assert p.is_online("onur")
    p.disconnect("onur")
    assert not p.is_online("onur")


def test_reconnect_displaces_old_connection():
    p = PresenceRegistry()
    c1, c2 = object(), object()
    p.connect("onur", c1)
    displaced = p.connect("onur", c2)   # same id reconnects
    assert displaced is c1              # caller closes the old one
    assert p.get("onur") is c2


def test_stale_disconnect_from_displaced_socket_ignored():
    p = PresenceRegistry()
    c1, c2 = object(), object()
    p.connect("onur", c1)
    p.connect("onur", c2)
    p.disconnect("onur", c1)            # the OLD socket reports a close
    assert p.is_online("onur") and p.get("onur") is c2   # current conn untouched


def test_online_ids_sorted():
    p = PresenceRegistry()
    p.connect("onur", object())
    p.connect("alice", object())
    assert p.online_ids() == ["alice", "onur"]


# --------------------------------------------------------------------------------- queue

def _frame(cid):
    return {"v": 1, "type": "msg", "id": cid, "ciphertext": "b64", "counter": 1}


def test_enqueue_then_drain_in_arrival_order():
    q = FairOfflineQueue()
    q.enqueue("alice", "onur", _frame("a1"), now=100)
    q.enqueue("alice", "onur", _frame("a2"), now=101)
    drained = q.drain("onur", now=102)
    assert [f["id"] for f in drained] == ["a1", "a2"]
    assert q.drain("onur", now=103) == []   # nothing left


def test_drain_only_returns_recipients_messages():
    q = FairOfflineQueue()
    q.enqueue("alice", "onur", _frame("x"), now=1)
    q.enqueue("alice", "bob", _frame("y"), now=1)
    assert [f["id"] for f in q.drain("onur", now=2)] == ["x"]


def test_ttl_expiry_surfaced_not_silently_dropped():
    q = FairOfflineQueue(ttl=10)
    q.enqueue("alice", "onur", _frame("old"), now=0)
    expired = q.purge_expired(now=100)       # well past ttl
    assert [(s, r, f["id"]) for s, r, f in expired] == [("alice", "onur", "old")]
    assert q.pending_count("onur") == 0


def test_per_pair_cap_is_fair_one_sender_cannot_evict_another():
    # M2: cap is per (sender,recipient). A flood from mallory must not evict alice's item.
    q = FairOfflineQueue(max_per_pair=3)
    q.enqueue("alice", "onur", _frame("alice-keep"), now=1)
    for i in range(10):  # mallory floods her own pair to onur
        q.enqueue("mallory", "onur", _frame("m%d" % i), now=1)
    drained_ids = {f["id"] for f in q.drain("onur", now=2)}
    assert "alice-keep" in drained_ids                      # alice survived the flood
    assert sum(1 for x in drained_ids if x.startswith("m")) == 3   # mallory capped at 3


def test_cap_drops_oldest_of_the_same_pair():
    q = FairOfflineQueue(max_per_pair=2)
    dropped = []
    for i in range(4):
        d = q.enqueue("alice", "onur", _frame("a%d" % i), now=1)
        if d is not None:
            dropped.append(d["id"])
    assert dropped == ["a0", "a1"]                          # oldest evicted first
    assert [f["id"] for f in q.drain("onur", now=2)] == ["a2", "a3"]
