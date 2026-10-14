#!/usr/bin/env python3
"""Normalize one agent session's transcript for the agent-compliance checks.

Part of tests/eval/compliance (source-only, maintainer-run). Run isolated:

    python3 -I transcript.py --out <dir> --root <main checkout> --cwd <session dir> < raw-stdout

Input, the agent command's stdout, detected from its first non-empty line:
  * Claude Code `--output-format stream-json --verbose`: one JSON object per line;
  * plain event lines, for any other agent CLI: `<kind>\t<text>`, kind one of say, shell, read,
    edit, write, agent, ask, result, final; the text escapes backslash, newline, tab and carriage
    return as \\\\, \\n, \\t and \\r. Other lines are ignored.

Output, in <dir>:
  events.tsv    seq, kind, ctx (main|sub: a subagent's event), mod (1 = it modifies files: an edit, a
                write, or a shell command that writes), tool (for a result: the kind of the call it
                answers, else -), head (one line). One row per event in transcript order, seq from 1.
  ev/<seq>.txt  the event's full text: the command, the path, the tool output, the message, the
                subagent's prompt.
  ev/<seq>.units  for a message (say, final): its sentences, one per line, in order, with fenced code
                blocks left out. A rule restated inside a fence (a handoff block, a quoted plan) is
                quoted text, not something the agent said to the user. A paragraph's soft-wrapped lines
                are joined; a list item, heading, table row or quote starts a new sentence.
  final.txt     the session's final reply.
  handoff.txt   the handoff prompt the session gave (empty when none): the last fenced block holding
                "Session Handoff", else the last fenced block mentioning a handoff; the final reply
                is searched first, then the agent's earlier messages.

Paths of read, edit and write events are made relative to --root when they lie inside it.
Exit codes: 0 ok; 1 no event could be read; 2 usage.
"""

import argparse
import json
import os
import re
import sys

PLAIN = re.compile(r"^(say|shell|read|edit|write|agent|ask|result|final)\t(.*)$")
CALLS = {"shell", "read", "edit", "write", "agent", "ask", "other"}

# A shell command "writes" when it redirects into a file or runs a file-changing command. Quoted
# strings and heredoc bodies are ignored first, so `grep "->" x` or a heredoc's text does not count.
QUOTED = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"")
QUOTED_TARGET = re.compile(r"(>{1,2}\|?[ \t]*)(?:\"([^\"]*)\"|'([^']*)')")  # a quoted redirection target
WRITE_CMD = re.compile(
    r"\bsed\b[^|;&\n]*\s-[a-zA-Z]*i"
    r"|\bperl\b[^|;&\n]*\s-[a-zA-Z]*i"
    r"|(?:^|[\s;&|(])(?:tee|apply_patch|patch|cp|mv|rm|touch|truncate|dd|install)(?=\s|$)"
    r"|\bgit\s+(?:apply|mv|rm|restore|checkout\s+--)(?=\s|$)"
)
# A redirection into /dev/ or a temporary directory changes no project file.
REDIRECT = re.compile(r"(?<![-=<>&0-9])>{1,2}\|?[ \t]*(?!&)(?!/dev/|/tmp/|/private/tmp/|/var/folders/|\$\{?TMPDIR)[^\s;&|<>]")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
# A line that starts its own block: a list item, a heading, a block quote or a table row.
BLOCK_START = re.compile(r"^ {0,3}(?:[-*+][ \t]|[0-9]{1,9}[.)][ \t]|#{1,6}(?:[ \t]|$)|>|\|)")
# A sentence ends at . ! or ?, after any closing quotes, brackets or emphasis, before white space.
SENTENCE_END = re.compile("(?<=[.!?])[\"'”’)\\]*_`]*\\s+")


def shell_writes(cmd):
    lines = []
    for line in cmd.splitlines():
        lines.append(line)
        if "<<" in line:
            break
    text = QUOTED_TARGET.sub(lambda m: m.group(1) + (m.group(2) if m.group(2) is not None else m.group(3)).replace(" ", "_"),
                             "\n".join(lines))
    text = QUOTED.sub("''", text)
    return bool(WRITE_CMD.search(text) or REDIRECT.search(text))


def unescape(s):
    out, i, n = [], 0, len(s)
    table = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\"}
    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            out.append(table.get(s[i + 1], "\\" + s[i + 1]))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


class Normalizer:
    def __init__(self, root, cwd):
        self.cwd = cwd
        self.roots = []
        for r in (root, os.path.realpath(root)):
            r = os.path.normpath(r)
            if r not in self.roots:
                self.roots.append(r)
        self.events = []  # (kind, ctx, mod, tool, text)

    def rel(self, path):
        if not path:
            return path
        p = os.path.normpath(path if os.path.isabs(path) else os.path.join(self.cwd, path))
        for cand in (p, os.path.realpath(p)):
            for r in self.roots:
                if cand == r:
                    return "."
                if cand.startswith(r + os.sep):
                    return cand[len(r) + 1:]
        return p

    def add(self, kind, text, ctx="main", tool="-"):
        text = text if isinstance(text, str) else ("" if text is None else str(text))
        if kind in ("read", "edit", "write"):
            text = self.rel(text)
        mod = 1 if kind in ("edit", "write") or (kind == "shell" and shell_writes(text)) else 0
        self.events.append((kind, ctx, mod, tool, text))
        return kind

    # --- Claude Code stream-json -----------------------------------------------------------------
    @staticmethod
    def call(name, inp):
        if not isinstance(inp, dict):
            inp = {}
        if name in ("Bash", "PowerShell"):
            return "shell", inp.get("command", "")
        if name == "Read":
            return "read", inp.get("file_path", "")
        if name in ("Edit", "MultiEdit"):
            return "edit", inp.get("file_path", "")
        if name == "NotebookEdit":
            return "edit", inp.get("notebook_path", "")
        if name == "Write":
            return "write", inp.get("file_path", "")
        if name in ("Task", "Agent"):
            return "agent", inp.get("prompt", "")
        if name == "AskUserQuestion":
            parts = []
            for q in inp.get("questions") or []:
                if isinstance(q, dict):
                    parts.append(str(q.get("question", "")))
                    for o in q.get("options") or []:
                        if isinstance(o, dict):
                            parts.append("- " + str(o.get("label", "")))
            return "ask", "\n".join(parts)
        return "other", name + " " + json.dumps(inp, ensure_ascii=False, sort_keys=True)

    @staticmethod
    def result_text(content):
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts = []
            for c in content:
                if isinstance(c, dict) and c.get("type") == "text":
                    parts.append(str(c.get("text", "")))
                elif isinstance(c, str):
                    parts.append(c)
            return "\n".join(parts)
        return ""

    def stream_json(self, lines):
        pending = {}
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if not isinstance(obj, dict):
                continue
            kind = obj.get("type")
            ctx = "sub" if obj.get("parent_tool_use_id") else "main"
            message = obj.get("message") if isinstance(obj.get("message"), dict) else {}
            content = message.get("content")
            if kind == "assistant":
                if isinstance(content, str):
                    content = [{"type": "text", "text": content}]
                for item in content if isinstance(content, list) else []:
                    if not isinstance(item, dict):
                        continue
                    if item.get("type") == "text":
                        self.add("say", item.get("text", ""), ctx)
                    elif item.get("type") == "tool_use":
                        k, text = self.call(str(item.get("name", "")), item.get("input"))
                        pending[item.get("id")] = self.add(k, text, ctx)
            elif kind == "user":
                for item in content if isinstance(content, list) else []:
                    if isinstance(item, dict) and item.get("type") == "tool_result":
                        tool = pending.get(item.get("tool_use_id"), "-")
                        self.add("result", self.result_text(item.get("content")), ctx, tool)
            elif kind == "result" and isinstance(obj.get("result"), str):
                self.add("final", obj["result"])

    # --- plain event lines -------------------------------------------------------------------------
    def plain(self, lines):
        last_call = "-"
        for line in lines:
            m = PLAIN.match(line.rstrip("\r\n"))
            if not m:
                continue
            kind, text = m.group(1), unescape(m.group(2))
            if kind == "result":
                self.add("result", text, "main", last_call)
                last_call = "-"
            else:
                self.add(kind, text)
                last_call = kind if kind in CALLS else "-"

    # --- outputs -------------------------------------------------------------------------------------
    def final_text(self):
        for kind, ctx, _, _, text in reversed(self.events):
            if kind == "final":
                return text
        for kind, ctx, _, _, text in reversed(self.events):
            if kind == "say" and ctx == "main":
                return text
        return ""

    def handoff(self):
        texts = [self.final_text()] + [t for k, c, _, _, t in reversed(self.events) if k == "say" and c == "main"]
        for want in (lambda b: "Session Handoff" in b, lambda b: "handoff" in b.lower()):
            for text in texts:
                for block in reversed(fenced_blocks(text)):
                    if want(block):
                        return block
        return ""

    def write(self, out):
        os.makedirs(os.path.join(out, "ev"), exist_ok=True)
        with open(os.path.join(out, "events.tsv"), "w", encoding="utf-8", newline="\n") as f:
            for seq, (kind, ctx, mod, tool, text) in enumerate(self.events, 1):
                head = (text.strip().splitlines() or ["-"])[0].replace("\t", " ")[:200] or "-"
                f.write("%d\t%s\t%s\t%d\t%s\t%s\n" % (seq, kind, ctx, mod, tool, head))
                with open(os.path.join(out, "ev", "%d.txt" % seq), "w", encoding="utf-8", newline="\n") as e:
                    e.write(text)
                if kind in ("say", "final"):
                    with open(os.path.join(out, "ev", "%d.units" % seq), "w", encoding="utf-8", newline="\n") as u:
                        u.writelines(s + "\n" for s in message_units(text))
        for name, text in (("final.txt", self.final_text()), ("handoff.txt", self.handoff())):
            with open(os.path.join(out, name), "w", encoding="utf-8", newline="\n") as f:
                f.write(text + ("\n" if text and not text.endswith("\n") else ""))


def fenced_blocks(text):
    blocks, cur, fence = [], [], None
    for line in text.splitlines():
        m = FENCE.match(line)
        if fence is None:
            if m:
                fence, cur = m.group(1), []
        elif m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
            blocks.append("\n".join(cur))
            fence = None
        else:
            cur.append(line)
    return blocks


def message_units(text):
    """The sentences of one message, fenced code blocks left out (an unclosed fence runs to the end,
    as Markdown renders it). Paragraphs end at blank lines; a block-starting line begins a new one."""
    units, group, fence = [], [], None

    def flush():
        if group:
            joined = " ".join(part.strip() for part in group)
            units.extend(s.strip().replace("\t", " ") for s in SENTENCE_END.split(joined) if s.strip())
            del group[:]

    for line in text.splitlines():
        m = FENCE.match(line)
        if fence is not None:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
                fence = None
            continue
        if m:
            flush()
            fence = m.group(1)
            continue
        if not line.strip():
            flush()
            continue
        if BLOCK_START.match(line):
            flush()
        group.append(line)
    flush()
    return units


def main(argv):
    ap = argparse.ArgumentParser(description="Normalize an agent transcript for the compliance checks.")
    ap.add_argument("--out", required=True, help="directory for events.tsv, ev/, final.txt, handoff.txt")
    ap.add_argument("--root", required=True, help="the fixture's main checkout")
    ap.add_argument("--cwd", required=True, help="the directory the session ran in")
    try:
        args = ap.parse_args(argv)
    except SystemExit:
        return 2
    raw = sys.stdin.buffer.read().decode("utf-8", "replace")
    lines = raw.splitlines()
    first = next((l.strip() for l in lines if l.strip()), "")
    n = Normalizer(args.root, args.cwd)
    if first.startswith("{"):
        n.stream_json(lines)
    else:
        n.plain(lines)
    if not n.events:
        sys.stderr.write("transcript.py: no event could be read (not Claude Code stream-json, not event lines)\n")
        return 1
    n.write(args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
