"""Task 6 — daemon core: ask->handshake->answer, send-then-commit, receipts, durable timeout."""
from relay_common import crypto
from client.session import SessionManager
from client.filequeue import FileQueue
from client.daemon_core import DaemonCore


def _peer(my_id, registry, tmp_path, awaiting=False):
    sk = crypto.generate_identity()
    registry[my_id] = crypto.identity_public_bytes(sk)
    sm = SessionManager(my_id, sk, lambda pid: registry[pid],
                        str(tmp_path / ("replay-%s.json" % my_id)))
    base = str(tmp_path / my_id / ".relay")
    fq = FileQueue(base)
    aw = (base + "/awaiting.json") if awaiting else None
    return DaemonCore(my_id, sm, fq, awaiting_path=aw), fq, sm


def _deliver(frames, cores, now):
    q = list(frames)
    while q:
        f = q.pop(0)
        to = f.get("to")
        if to in cores:
            q.extend(cores[to].on_incoming(f, now))


def _flush(core, cores, now):
    """Drain a core's outbox until empty, modelling send-then-commit then network delivery."""
    while True:
        works = core.process_outbox(now)
        if not works:
            return
        for w in works:
            core.commit(w)                 # production: send succeeded -> commit (track/remove)
            _deliver([w.frame], cores, now)


def _inbox(fq):
    return [o for _, o in fq.list_inbox()]


def test_full_ask_answer_flow_with_receipts(tmp_path):
    reg = {}
    a_core, a_fq, _ = _peer("alice", reg, tmp_path)
    x_core, x_fq, _ = _peer("onur", reg, tmp_path)
    cores = {"alice": a_core, "onur": x_core}
    now = 1000.0

    a_fq.put_outbox("o1", {"kind": "ask", "to": "onur", "question": "how does cancel work?"})
    _flush(a_core, cores, now)             # keyx handshake (round 1) then the question (round 2)

    qs = [o for o in _inbox(x_fq) if o["kind"] == "question"]
    assert qs and qs[0]["from"] == "alice"
    assert qs[0]["untrusted"]["content"] == "how does cancel work?"
    assert qs[0]["untrusted"]["untrusted"] is True

    # receipt cleared alice's delivery tracking -> no escalation ever
    a_core.check_timeouts(now + 10_000)
    assert not [o for o in _inbox(a_fq) if o["kind"] == "delivery-timeout"]

    # the outbox file was removed only after send (commit) — outbox now empty
    assert a_fq.drain_outbox() == []

    x_fq.put_outbox("o2", {"kind": "answer", "to": "alice", "ref_id": qs[0]["id"],
                           "text": "it splits the order"})
    _flush(x_core, cores, now)
    ans = [o for o in _inbox(a_fq) if o["kind"] == "answer"]
    assert ans and ans[0]["untrusted"]["content"] == "it splits the order"


def test_outbox_file_kept_until_sent(tmp_path):
    # process_outbox must NOT remove the file (review C1): only commit() does, after send.
    reg = {}
    a_core, a_fq, _ = _peer("alice", reg, tmp_path)
    _peer("onur", reg, tmp_path)
    a_fq.put_outbox("o1", {"kind": "ask", "to": "onur", "question": "Q"})
    works = a_core.process_outbox(1.0)     # builds a keyx; question file still present
    assert a_fq.drain_outbox(), "outbox file must remain until commit() after a confirmed send"
    assert any(w.frame["type"] == "keyx" for w in works)


def test_handshake_happens_once_per_peer(tmp_path):
    reg = {}
    a_core, a_fq, _ = _peer("alice", reg, tmp_path)
    _peer("onur", reg, tmp_path)
    a_fq.put_outbox("o1", {"kind": "ask", "to": "onur", "question": "Q1"})
    a_fq.put_outbox("o2", {"kind": "ask", "to": "onur", "question": "Q2"})
    works = a_core.process_outbox(1.0)
    assert sum(1 for w in works if w.frame["type"] == "keyx") == 1


def test_delivery_timeout_escalates_and_is_durable(tmp_path):
    reg = {}
    a_core, a_fq, a_sm = _peer("alice", reg, tmp_path, awaiting=True)
    _x_core, _x_fq, x_sm = _peer("onur", reg, tmp_path)
    # establish a session directly (no receipts)
    a_sm.on_keyx(x_sm.on_keyx(a_sm.initiate("onur")))
    assert a_sm.has_session("onur")

    a_fq.put_outbox("o1", {"kind": "ask", "to": "onur", "question": "Q"})
    for w in a_core.process_outbox(1000.0):
        a_core.commit(w)                   # sent + tracked; receipt never arrives

    a_core.check_timeouts(1000.0)
    assert not [o for o in _inbox(a_fq) if o["kind"] == "delivery-timeout"]

    # DURABILITY: a fresh core (daemon restart) reloads _awaiting and still escalates (I3)
    restarted = DaemonCore("alice", a_sm, a_fq, awaiting_path=str(tmp_path / "alice" / ".relay" / "awaiting.json"))
    restarted.check_timeouts(2000.0)
    esc = [o for o in _inbox(a_fq) if o["kind"] == "delivery-timeout"]
    assert esc and esc[0]["untrusted"]["requires_human_approval"] is True


def test_answer_clears_inbox_item(tmp_path):
    from client.agent_cli import do_answer
    reg = {}
    _core, fq, _ = _peer("alice", reg, tmp_path)
    fq.put_inbox("m1", {"kind": "question", "id": "m1", "from": "onur",
                        "untrusted": {"content": "Q?"}})
    do_answer(fq, "m1", "the answer")
    assert not [o for o in _inbox(fq) if o.get("id") == "m1"]   # answered item cleared
