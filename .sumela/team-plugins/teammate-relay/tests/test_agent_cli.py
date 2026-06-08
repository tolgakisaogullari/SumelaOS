"""Task 7 — agent-facing CLI logic: routing, fan-out gate, answer targeting."""
import pytest

from client.filequeue import FileQueue
from client.agent_cli import do_ask, do_answer, do_inbox_list


def _fq(tmp_path):
    return FileQueue(str(tmp_path / ".relay"))


def test_ask_explicit_to(tmp_path):
    fq = _fq(tmp_path)
    ids = do_ask(fq, "how does X work?", to="onur")
    assert len(ids) == 1
    obj = fq.drain_outbox()[0][1]
    assert obj == {"kind": "ask", "to": "onur", "question": "how does X work?"}


def test_ask_to_strips_leading_at(tmp_path):
    # SKILL.md uses --to @onur; the @ must be normalized to the bare id (keys/<id>.pub).
    fq = _fq(tmp_path)
    do_ask(fq, "Q", to="@onur")
    assert fq.drain_outbox()[0][1]["to"] == "onur"


def test_ask_by_domain_single_holder(tmp_path):
    fq = _fq(tmp_path)
    do_ask(fq, "Q", domain="payments", role_map={"payments": ["onur"]})
    assert [o["to"] for _, o in fq.drain_outbox()] == ["onur"]


def test_ask_domain_multiple_holders_requires_choice(tmp_path):
    fq = _fq(tmp_path)
    with pytest.raises(ValueError):           # default: asker must pick (I4)
        do_ask(fq, "Q", domain="payments", role_map={"payments": ["onur", "dana"]})


def test_ask_fanout_to_all_holders(tmp_path):
    fq = _fq(tmp_path)
    ids = do_ask(fq, "Q", domain="payments",
                 role_map={"payments": ["onur", "dana"]}, fanout=True)
    assert len(ids) == 2
    assert sorted(o["to"] for _, o in fq.drain_outbox()) == ["dana", "onur"]


def test_ask_unknown_domain_errors(tmp_path):
    with pytest.raises(ValueError):
        do_ask(_fq(tmp_path), "Q", domain="ghost", role_map={})


def test_ask_no_target_errors(tmp_path):
    with pytest.raises(ValueError):
        do_ask(_fq(tmp_path), "Q")


def test_ask_empty_question_errors(tmp_path):
    with pytest.raises(ValueError):
        do_ask(_fq(tmp_path), "   ", to="onur")


def test_answer_targets_the_asker(tmp_path):
    fq = _fq(tmp_path)
    # simulate the daemon having written an incoming question from alice
    fq.put_inbox("m1", {"kind": "question", "id": "m1", "from": "alice",
                        "untrusted": {"content": "Q?"}})
    eid = do_answer(fq, "m1", "here is the answer")
    obj = [o for _, o in fq.drain_outbox() if o["kind"] == "answer"][0]
    assert obj["to"] == "alice" and obj["ref_id"] == "m1" and obj["text"] == "here is the answer"
    _ = eid


def test_answer_unknown_id_errors(tmp_path):
    with pytest.raises(ValueError):
        do_answer(_fq(tmp_path), "nope", "x")


def test_answer_empty_errors(tmp_path):
    fq = _fq(tmp_path)
    fq.put_inbox("m1", {"id": "m1", "from": "alice"})
    with pytest.raises(ValueError):
        do_answer(fq, "m1", "  ")


def test_inbox_list(tmp_path):
    fq = _fq(tmp_path)
    fq.put_inbox("m1", {"id": "m1", "from": "alice"})
    fq.put_inbox("m2", {"id": "m2", "from": "dana"})
    assert {i["from"] for i in do_inbox_list(fq)} == {"alice", "dana"}
