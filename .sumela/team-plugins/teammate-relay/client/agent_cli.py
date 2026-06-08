"""Task 7 — agent-facing CLI logic (ask / inbox / answer).

These NEVER touch the socket — they only read/write the file-queue (`FileQueue`); the daemon
does the crypto + networking. Routing resolves ONLY against the committed, CODEOWNERS-gated
team role map (never self-asserted local domains — review I2). Default is asker-selects-one;
fan-out is explicit opt-in and warns that every holder then sees the question (review I4).
"""

from __future__ import annotations

import uuid
from typing import Dict, List, Optional, Tuple

from client.filequeue import FileQueue


def resolve_recipients(
    to: Optional[str],
    domain: Optional[str],
    role_map: Dict[str, List[str]],
    fanout: bool,
) -> Tuple[List[str], Optional[str]]:
    """Return (recipients, error). Explicit `to` wins; else resolve `domain` via the role map."""
    if to:
        return [to.lstrip("@")], None      # accept both "@onur" and "onur" -> bare id
    if domain:
        holders = role_map.get(domain, [])
        if not holders:
            return [], "no teammate owns domain %r (check the committed role map)" % domain
        if len(holders) == 1:
            return holders, None
        if fanout:
            return holders, None
        return [], ("domain %r has multiple holders %s — pick one with --to, "
                    "or use --fanout (every holder then sees the question)" % (domain, holders))
    return [], "specify --to <teammate> or --domain <domain>"


def do_ask(fq: FileQueue, question: str, *, to: Optional[str] = None,
           domain: Optional[str] = None, role_map: Optional[Dict[str, List[str]]] = None,
           fanout: bool = False) -> List[str]:
    if not question or not question.strip():
        raise ValueError("question must not be empty")
    recipients, err = resolve_recipients(to, domain, role_map or {}, fanout)
    if err:
        raise ValueError(err)
    ids = []
    for r in recipients:
        eid = uuid.uuid4().hex
        fq.put_outbox(eid, {"kind": "ask", "to": r, "question": question})
        ids.append(eid)
    return ids


def do_answer(fq: FileQueue, message_id: str, text: str) -> str:
    """Reply to a received question. The recipient is the asker (`from` of the inbox item)."""
    if not text or not text.strip():
        raise ValueError("answer must not be empty")
    for path, obj in fq.list_inbox():
        if obj.get("id") == message_id:
            eid = uuid.uuid4().hex
            fq.put_outbox(eid, {"kind": "answer", "to": obj["from"],
                                "ref_id": message_id, "text": text})
            fq.remove(path)        # clear the answered item (no re-answer / unbounded growth, I5)
            return eid
    raise ValueError("no inbox item with id %r" % message_id)


def do_inbox_list(fq: FileQueue) -> List[dict]:
    """Pending received items (questions/answers), each already UNTRUSTED-wrapped by the daemon."""
    return [obj for _, obj in fq.list_inbox()]
