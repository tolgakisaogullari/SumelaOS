#!/usr/bin/env python3
"""Token report v1 (R1-09): discovery, privacy, sections.

scripts/sumela-token-report.py reads a developer's local Claude Code transcripts, so privacy is
its first requirement: it prints aggregates and allow-listed labels only. This suite builds
throwaway installs (a git repository with .sumela/, a HOME, a CLAUDE_CONFIG_DIR and an
XDG_STATE_HOME, all under one temporary directory) and synthetic transcripts in the JSONL
shapes Claude Code writes. Nothing outside the temporary directory is read or written; the
developer's own ~/.claude is never touched (HOME is redirected for every run).

  t_canaries_never_leak            canaries in every channel (user, assistant and thinking text,
                                   tool inputs and outputs, paths, branch names, ticket-shaped
                                   IDs, review/handoff/upgrade paths, worktree names, tool, MCP,
                                   agent and model names, attachments, task records, cwd, session
                                   ids) never reach stdout, --json, --static or the state seam;
                                   the report writes no file
  t_no_network                     socket.socket raises: the report still runs; no network module
  t_exit_codes_0_2_1               0 ok; 2 no transcripts / no session (with the --static hint);
                                   1 outside an install, usage error, internal error (generic)
  t_compaction_subagent_powershell_worktree_windows_paths
  t_claude_config_dir_honoured
  t_state_key_matches_bash         the Python key equals scripts/lib/sumela-state.sh's (R1-03)
  t_digest_and_boot_reads_detected A4, A5, allow_large, A6
  t_a15_not_satisfied_by_bootstrap_digest_alone
  t_malformed_lines_counted_not_fatal
  plus: label_path's allow-list, the sanitizer (trailing newlines included), the research
  model's arithmetic (totals and carried chars by hand), --until/--since, handoffs and
  R_continuation (a bare mention is no request), the SumelaOS-session filter, linked and
  removed worktrees' transcript directories, A16/A16b/Q17, hostile text that must not make a
  regex backtrack, git's stderr and tracing, --static, the wrappers, and the framework manifest
  against the source (strict once .sumela/VERSION is past the previous final tag).

Run:  python3 -I tests/test_token_report.py
Exit 0 = all assertions passed, 1 = a failure (printed above). Standard library only.
"""
import contextlib
import importlib.util
import io
import json
import os
import re
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "scripts" / "sumela-token-report.py"
SH = REPO / "scripts" / "sumela-token-report.sh"
PS1 = REPO / "scripts" / "sumela-token-report.ps1"
STATE_LIB = REPO / "scripts" / "lib" / "sumela-state.sh"
BUDGETS = REPO / "scripts" / "lib" / "sumela-context-budgets.tsv"
UTC = timezone.utc
FAILS = []


def check(name, cond, detail=""):
    print(("  PASS  " if cond else "  FAIL  ") + name + ("" if cond or not detail else "  (" + str(detail)[:400] + ")"))
    if not cond:
        FAILS.append(name)


def load_module():
    spec = importlib.util.spec_from_file_location("sumela_token_report_under_test", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


M = load_module()


# ---------------------------------------------------------------------------- transcripts
class Tx:
    """One synthetic Claude Code transcript: one line per content block, one message id (and
    one usage record) per API request, tool results in user lines, as Claude Code writes them."""

    def __init__(self, cwd, branch="main", sid="s0", t0=None, version="2.1.300", ctx=20000):
        self.cwd, self.branch, self.sid, self.version = cwd, branch, sid, version
        self.t = t0 or datetime(2026, 10, 1, 9, 0, 0, tzinfo=UTC)
        self.lines = []
        self.n = 0
        self.ctx = ctx

    def _stamp(self, step):
        self.t += timedelta(seconds=step)
        return self.t.strftime("%Y-%m-%dT%H:%M:%S.000Z")

    def _uid(self):
        self.n += 1
        return "%s-u%05d" % (self.sid, self.n)

    def _base(self, typ, step=20):
        return {"type": typ, "timestamp": self._stamp(step), "uuid": self._uid(), "parentUuid": None,
                "sessionId": self.sid, "cwd": self.cwd, "gitBranch": self.branch, "version": self.version,
                "isSidechain": False, "userType": "external"}

    def raw(self, s):
        self.lines.append(s)

    def user(self, text, **kw):
        d = self._base("user")
        d["message"] = {"role": "user", "content": text}
        d.update(kw)
        self.lines.append(json.dumps(d))
        return d["uuid"]

    def usage(self, grow, out, think, ctx=None):
        self.ctx = ctx if ctx is not None else self.ctx + grow
        cr = int(self.ctx * 0.9)
        cc = self.ctx - cr - 3
        return {"input_tokens": 3, "cache_creation_input_tokens": cc, "cache_read_input_tokens": cr, "output_tokens": out,
                "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": cc},
                "output_tokens_details": {"thinking_tokens": think}, "service_tier": "standard"}

    def assistant(self, blocks, grow=3000, out=200, think=50, model="claude-opus-5-5", step=20, ctx=None, usage=None):
        mid = "msg_%s_%05d" % (self.sid, self.n + 1)
        u = usage if usage is not None else self.usage(grow, out, think, ctx)
        for b in blocks:
            d = self._base("assistant", step)
            step = 1
            d["message"] = {"id": mid, "type": "message", "role": "assistant", "model": model, "content": [b], "usage": u}
            d["requestId"] = "req_" + mid
            d["effort"] = "high"
            self.lines.append(json.dumps(d))
        return mid

    def say(self, text, **kw):
        return self.assistant([{"type": "text", "text": text}], **kw)

    def tool(self, name, inp, result="ok", is_error=False, tur=None, branch_after=None, **kw):
        tid = "toolu_%s_%05d" % (self.sid, self.n + 1)
        self.assistant([{"type": "tool_use", "id": tid, "name": name, "input": inp}], **kw)
        if branch_after:
            self.branch = branch_after
        d = self._base("user", 5)
        d["message"] = {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "content": result,
                                                     "is_error": is_error}]}
        if tur is not None:
            d["toolUseResult"] = tur
        self.lines.append(json.dumps(d))
        return d["uuid"]

    def compact(self, preserved=(), summary="summary of the earlier conversation"):
        d = self._base("system")
        d.update({"subtype": "compact_boundary", "content": "Conversation compacted", "level": "info",
                  "compactMetadata": {"trigger": "auto", "preTokens": self.ctx, "preservedMessages": {"allUuids": list(preserved)}}})
        self.lines.append(json.dumps(d))
        self.ctx = 30000
        d = self._base("user")
        d["isCompactSummary"] = True
        d["message"] = {"role": "user", "content": summary}
        self.lines.append(json.dumps(d))

    def attach(self, att, rendered=None):
        d = self._base("attachment", 1)
        d["attachment"] = att
        if rendered is not None:
            d["rendered"] = [{"content": rendered}]
        self.lines.append(json.dumps(d))

    def snapshot(self, sp_chars=12000, tools=("Bash", "Read", "Edit", "Write", "Agent")):
        self.attach({"type": "prompt_snapshot", "systemPrompt": ["s" * sp_chars],
                     "tools": [{"name": t, "description": "d" * 300, "schema": {"type": "object"}} for t in tools]})

    def contract(self):
        """The bootstrap's read of the contract: this is what makes a session a SumelaOS session."""
        return self.tool("Read", {"file_path": self.cwd + "/.sumela/sumela-prompt.md"}, "c" * 4000)

    def text(self):
        return "\n".join(self.lines) + "\n"


def slug(path):
    return re.sub(r"[/\\:.]", "-", str(path))


class Fx:
    """A throwaway install: HOME, the default CLAUDE_CONFIG_DIR (HOME/.claude), XDG_STATE_HOME and
    a git repository holding .sumela/, all under <base>."""

    def __init__(self, base, name="proj", sub="", home_name="home"):
        self.base = Path(base)
        self.base.mkdir(parents=True, exist_ok=True)
        self.home = self.base / home_name
        self.home.mkdir(exist_ok=True)
        self.state = self.base / "state"
        self.cfg = self.home / ".claude"
        self.repo = self.base / name
        self.repo.mkdir()
        self.root = self.repo / sub if sub else self.repo
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "dev@example.com")
        self.git("config", "user.name", "Dev Example")
        (self.root / ".sumela").mkdir(parents=True)
        (self.root / ".sumela" / "VERSION").write_text("0.20.0\n")
        (self.root / "src").mkdir(exist_ok=True)
        (self.root / "src" / "a.txt").write_text("x\n")
        self.git("add", "-A")
        self.git("commit", "-qm", "init")

    def env(self, **kw):
        e = {k: v for k, v in os.environ.items()
             if not k.startswith("GIT_") and k not in ("CLAUDE_CONFIG_DIR", "XDG_STATE_HOME", "LOCALAPPDATA", "HOME")}
        e.update(HOME=str(self.home), XDG_STATE_HOME=str(self.state), GIT_CONFIG_NOSYSTEM="1")
        e.update({k: str(v) for k, v in kw.items() if v is not None})
        for k in [k for k, v in kw.items() if v is None]:
            e.pop(k, None)
        return e

    def git(self, *args, cwd=None):
        return subprocess.run(["git", "-C", str(cwd or self.repo)] + list(args), check=True, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, env=self.env()).stdout.decode()

    def pdir(self, path=None, cfg=None):
        d = Path(cfg or self.cfg) / "projects" / slug(path or self.root)
        d.mkdir(parents=True, exist_ok=True)
        return d

    def session(self, tx, cfg=None, path=None):
        (self.pdir(path, cfg) / (tx.sid + ".jsonl")).write_text(tx.text(), encoding="utf-8")

    def subagent(self, sid, agent_id, tx, meta, cfg=None):
        d = self.pdir(None, cfg) / sid / "subagents"
        d.mkdir(parents=True, exist_ok=True)
        (d / ("agent-" + agent_id + ".jsonl")).write_text(tx.text(), encoding="utf-8")
        (d / ("agent-" + agent_id + ".meta.json")).write_text(json.dumps(meta), encoding="utf-8")

    def tx(self, sid, **kw):
        return Tx(str(self.root), sid=sid, **kw)

    def run(self, *args, cwd=None, **envkw):
        p = subprocess.run([sys.executable, "-I", str(SCRIPT)] + list(args), cwd=str(cwd or self.root),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env(**envkw))
        return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")

    def json(self, *args, **kw):
        rc, out, err = self.run("--json", *args, **kw)
        try:
            return rc, json.loads(out), err
        except ValueError:
            return rc, {}, err + out


def sec(rep, *path):
    cur = rep.get("sections", {})
    for p in path:
        if not isinstance(cur, dict) or p not in cur:
            return None
        cur = cur[p]
    return cur


@contextlib.contextmanager
def in_process(fx, cwd=None, **envkw):
    """Run the module in this process with the fixture's environment and working directory."""
    saved_env, saved_cwd = dict(os.environ), os.getcwd()
    os.environ.clear()
    os.environ.update(fx.env(**envkw))
    os.chdir(str(cwd or fx.root))
    try:
        yield
    finally:
        os.chdir(saved_cwd)
        os.environ.clear()
        os.environ.update(saved_env)


def call_main(args):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = M.main(list(args))
    return rc, out.getvalue(), err.getvalue()


def tmpdir():
    return Path(tempfile.mkdtemp(prefix="sumela-tr-")).resolve()


def snapshot_tree(root, skip=()):
    out = {}
    for dp, dns, fns in os.walk(str(root)):
        if any(dp == str(s) or dp.startswith(str(s) + os.sep) for s in skip):
            continue
        for fn in fns:
            p = os.path.join(dp, fn)
            st = os.lstat(p)
            out[p] = (st.st_size, st.st_mtime_ns)
    return out


# ---------------------------------------------------------------------------- t_canaries_never_leak
CANARIES = ["ZqUserCanary", "ZqAsstCanary", "ZqThinkCanary", "ZqCmdCanary", "ZqOutCanary", "zqpathcanary", "zqdircanary",
            "zqfilecanary", "zqbranchcanary", "CNRY-4821", "zqticket", "zqextcnry", "zqskillcanary", "zqrulecanary",
            "zqmcpcanary", "ZqToolCanary", "zqagentcanary", "zqmodelcanary", "ZqHookCanary", "zqattachcanary",
            "zqsidcanary", "zqrepocanary", "zqhomecanary", "zqreviewcanary", "zqhandoffcanary", "zqupgradecanary",
            "zqwikicanary", "zqsumcanary", "zqspeccanary", "zqartdircanary", "zqtaskcanary", "zqwtcanary", "zqcwtcanary",
            "zqversioncanary", "zqmsgmodelcanary", "zqinstrcanary", "zqqueuedcanary", "zqsummarycanary",
            "zqagentpromptcanary", "zqdomaincanary", "zqgrepcanary", "zqeditcanary", "zqmemorycanary",
            "zq\u00f6\u015fcanary", "zqpluginscanary", "zqcorefilecanary", "zqsubcanary", "zqstaticcanary", "zqoutside"]


def build_canary_fixture(base):
    fx = Fx(base, name="proj-zqrepocanary", home_name="zqhomecanary")
    r = str(fx.root)
    # a linked worktree whose directory and branch carry canaries
    fx.git("worktree", "add", "-q", "-b", "feat/zqbranchcanary-CNRY-4821", str(fx.repo / ".worktrees" / "zqwtcanary"))
    wt = str(fx.repo / ".worktrees" / "zqwtcanary")
    # a task record for that branch (A15), with canaries in its name and text
    tasks = fx.root / "docs" / "second-brain" / "wiki" / "_tasks"
    tasks.mkdir(parents=True)
    (tasks / "2026-10-14-zqtaskcanary.md").write_text(
        "---\ntype: task\ntitle: zqtaskcanary CNRY-4821\n---\n\n# Task\n\n## Task Ground Rules\n- R1 \u00b7 2026-10-14 \u00b7 user \u00b7 "
        "zqtaskcanary rule\n\n## Continue Point\n\n### feat/zqbranchcanary-CNRY-4821\n- 2026-10-14 \u00b7 next zqtaskcanary\n",
        encoding="utf-8")
    (fx.root / "scripts" / "lib").mkdir(parents=True)
    shutil.copy(str(BUDGETS), str(fx.root / "scripts" / "lib" / "sumela-context-budgets.tsv"))
    (fx.root / "AGENTS.md").write_text("zqstaticcanary pointer text\n")

    t = fx.tx("zqsidcanary-0001", branch="feat/zqbranchcanary-CNRY-4821", version="zqversioncanary")
    t.snapshot(tools=("Bash", "Read", "ZqToolCanary", "mcp__zqmcpcanary__zqtool"))
    t.attach({"type": "instructions", "files": [{"path": r + "/CLAUDE.md", "content": "pointer", "type": "Project"},
                                                {"path": "/elsewhere/zqinstrcanary/CLAUDE.md", "content": "zqinstrcanary", "type": "User"},
                                                {"path": str(fx.home) + "/.claude/projects/x/memory/MEMORY.md",
                                                 "content": "zqmemorycanary index", "type": "AutoMem"}]},
             rendered="pointer zqinstrcanary zqmemorycanary index")
    t.attach({"type": "file", "filename": r + "/.sumela/sumela-prompt.md", "displayPath": ".sumela/sumela-prompt.md"},
             rendered="contract text")
    t.attach({"type": "file", "filename": r + "/zqattachcanary/notes.md", "displayPath": "zqattachcanary/notes.md"},
             rendered="zqattachcanary attached")
    t.attach({"type": "hook_additional_context", "hookName": "ZqHookCanary", "hookEvent": "SessionStart"},
             rendered="ZqHookCanary context")
    t.attach({"type": "queued_command", "commandMode": "prompt", "prompt": "zqqueuedcanary"}, rendered="zqqueuedcanary")
    t.attach({"type": "skill_listing", "content": "- zqskillcanary: zqskillcanary does things\n- brainstorming: x\n",
              "skillCount": 2}, rendered="- zqskillcanary: zqskillcanary does things")
    t.contract()
    t.user("ZqUserCanary please fix CNRY-4821 in src/zqpathcanary/app.py for Ms. Zq\u00f6\u015fcanary")
    t.assistant([{"type": "thinking", "thinking": "ZqThinkCanary private reasoning", "signature": "sig"}])
    t.say("ZqAsstCanary I will look at zqfilecanary.md and the zqticket-77 ticket", model="claude-zqmsgmodelcanary")
    t.tool("Bash", {"command": "cat src/zqpathcanary/app.py | grep ZqCmdCanary && echo CNRY-4821", "description": "ZqCmdCanary"},
           "ZqOutCanary line\nCNRY-4821\n")
    t.tool("Read", {"file_path": r + "/src/zqdircanary/zqfilecanary.py"}, "ZqOutCanary code")
    t.tool("Read", {"file_path": r + "/zqdircanary/notes.zqextcnry"}, "ZqOutCanary")
    t.tool("Read", {"file_path": "/Users/zqoutside/secret/zqfilecanary.md"}, "ZqOutCanary")
    t.tool("Read", {"file_path": r + "/.sumela/skills/zqskillcanary/SKILL.md"}, "ZqOutCanary overlay skill")
    t.tool("Read", {"file_path": r + "/.sumela/skills/brainstorming/zqcorefilecanary-notes.md"}, "ZqOutCanary")
    t.tool("Read", {"file_path": r + "/.sumela/skills/brainstorming/SKILL.md"}, "b" * 3000)
    t.tool("Read", {"file_path": r + "/.sumela/rules/zqrulecanary/security_protocol.md"}, "ZqOutCanary")
    t.tool("Read", {"file_path": r + "/.sumela/rules/zqrulecanary.md"}, "ZqOutCanary")
    t.tool("Read", {"file_path": r + "/.sumela/memory-plugins/zqpluginscanary/SKILL.md"}, "ZqOutCanary")
    t.tool("Read", {"file_path": r + "/.sumela/reviews/feat-zqbranchcanary-zqreviewcanary-r2.md"}, "ZqOutCanary review")
    t.tool("Read", {"file_path": r + "/.sumela/.upgrade/zqupgradecanary/plan.txt"}, "ZqOutCanary")
    t.tool("Read", {"file_path": r + "/docs/second-brain/wiki/zqwikicanary.md"}, "ZqOutCanary page")
    t.tool("Read", {"file_path": r + "/docs/second-brain/wiki/session-summaries/2026-10-14-zqsumcanary.md"}, "ZqOutCanary")
    t.tool("Read", {"file_path": r + "/docs/second-brain/wiki/zqsubcanary/zqsubcanary.md"}, "ZqOutCanary")
    t.tool("Read", {"file_path": r + "/docs/second-brain/artifacts/zqartdircanary/x.md"}, "ZqOutCanary")
    t.tool("Read", {"file_path": r + "/src/zq\u00f6\u015fcanary/x.py"}, "ZqOutCanary")
    t.tool("Read", {"file_path": wt + "/src/zqpathcanary.py"}, "ZqOutCanary")
    t.tool("Read", {"file_path": r + "/.claude/worktrees/zqcwtcanary/.sumela/skills/context-handoff/SKILL.md"}, "h" * 2000)
    t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh digest --branch"},
           "rules from docs/second-brain/wiki/_tasks/2026-10-14-zqtaskcanary.md: zqtaskcanary rule")
    t.tool("Grep", {"pattern": "zqgrepcanary", "path": r + "/src/zqpathcanary"}, "ZqOutCanary match")
    t.tool("Edit", {"file_path": wt + "/src/zqpathcanary.py", "old_string": "zqeditcanary", "new_string": "zqeditcanary2"}, "ok")
    t.tool("Write", {"file_path": r + "/docs/second-brain/artifacts/specs/2026-10-14-zqspeccanary.md", "content": "zqspeccanary"}, "ok")
    t.tool("Write", {"file_path": r + "/.sumela/.handoff/2026-10-14-zqhandoffcanary.md",
                     "content": "## Session Handoff \u2014 2026-10-14\nzqhandoffcanary\n### Handoff Completeness\nFull\n"}, "ok")
    t.tool("WebFetch", {"url": "https://zqdomaincanary.example/CNRY-4821", "prompt": "ZqCmdCanary"}, "ZqOutCanary page")
    t.tool("mcp__zqmcpcanary__zqtool", {"query": "ZqCmdCanary"}, "ZqOutCanary mcp " * 400)
    t.tool("ZqToolCanary", {"x": "ZqCmdCanary"}, "ZqOutCanary custom " * 400)
    t.tool("Agent", {"description": "zqagentpromptcanary", "prompt": "You are the Implementer subagent zqagentpromptcanary",
                     "subagent_type": "zqagentcanary"}, "ZqOutCanary agent result", tur={"status": "completed"})
    t.tool("Skill", {"skill": "zqskillcanary", "args": "ZqCmdCanary"}, "Launching skill: zqskillcanary")
    t.user("<command-name>/zqskillcanary</command-name>")
    t.user("Base directory for this skill: " + r + "/.sumela/skills/zqskillcanary\n\nzqskillcanary body", isMeta=True)
    t.compact(preserved=[], summary="zqsummarycanary ZqUserCanary CNRY-4821")
    t.say("ZqAsstCanary after compaction " + "y" * 900)
    fx.session(t)
    # a subagent with a custom type and model, and canaries in its prompt and output
    s = Tx(wt, branch="feat/zqbranchcanary-CNRY-4821", sid="zqsidcanary-0001")
    s.user("You are the Implementer subagent for Task 3: zqagentpromptcanary CNRY-4821")
    s.tool("Bash", {"command": "cat " + wt + "/src/zqpathcanary.py"}, "ZqOutCanary")
    s.say("Status: DONE zqagentpromptcanary")
    fx.subagent("zqsidcanary-0001", "a1zqsubcanary", s, {"agentType": "zqagentcanary", "model": "claude-zqmodelcanary",
                                                         "description": "zqagentpromptcanary CNRY-4821", "spawnDepth": 1})
    return fx


def t_canaries_never_leak():
    print("== t_canaries_never_leak")
    base = tmpdir()
    try:
        fx = build_canary_fixture(base)
        before = snapshot_tree(base, skip=[fx.state])
        outs = {}
        for args in ([], ["--json"], ["--all-sessions"], ["--all-sessions", "--json"], ["--static"], ["--static", "--json"],
                     ["--until", "2026-10-01T09:05:00Z", "--json"]):
            rc, out, err = fx.run(*args)
            outs[" ".join(args) or "(text)"] = (rc, out, err)
        rc, rep, err = fx.json()
        check("the canary fixture reports (exit 0)", rc == 0, err)
        check("the report saw the canary session", sec(rep, "data_quality", "sessions_included") == 1, sec(rep, "data_quality"))
        check("every label passed the allow-list (labels_redacted = 0)", sec(rep, "data_quality", "labels_redacted") == 0,
              sec(rep, "data_quality", "labels_redacted"))
        check("every line of the fixture was processed (unprocessable_lines = 0)",
              sec(rep, "data_quality", "unprocessable_lines") == 0, sec(rep, "data_quality"))
        files = sec(rep, "framework_reads", "by_file") or {}
        for want in (".sumela/skills/brainstorming/SKILL.md", ".sumela/skills/<overlay>/*.md", ".sumela/rules/<overlay>/*.md",
                     ".sumela/<runtime>/*.md", ".sumela/<runtime>/*.txt", ".sumela/skills/brainstorming/*.md",
                     "docs/second-brain/wiki/<page>/*.md", "docs/second-brain/wiki/session-summaries/*.md",
                     "docs/second-brain/artifacts/<dir>/*.md", ".sumela/skills/context-handoff/SKILL.md",
                     ".sumela/memory-plugins/<overlay>/*.md", ".sumela/sumela-prompt.md"):
            check("framework reads label the canary path as %s" % want, want in files, sorted(files))
        check("the subagent's custom type prints as <custom>", "<custom>" in (sec(rep, "subagents", "by_agent_type") or {}))
        check("the subagent's custom model prints as <other>", "<other>" in (sec(rep, "subagents", "by_model") or {}))
        check("the custom tool and the MCP tool print as other and mcp:other",
              {"tool_result:other", "tool_result:mcp:other"} <= set(sec(rep, "composition", "all", "shares_pct") or {}))
        check("A15 saw the canary branch's record", (sec(rep, "second_brain", "a15_continuity") or {}).get("n") == 1)
        # the state seam (R1-10 writes baselines through it): a saved report holds no canary either
        with in_process(fx):
            path = M.write_state_file(str(fx.root), "token-report/canary-check.json", M.render_json(rep).encode())
        st = os.stat(path)
        check("the state seam writes 0600", stat.S_IMODE(st.st_mode) == 0o600, oct(st.st_mode))
        check("…inside a 0700 directory", stat.S_IMODE(os.stat(os.path.dirname(path)).st_mode) == 0o700)
        check("…under XDG_STATE_HOME/sumela/<key>/, never under ~/.claude",
              path.startswith(str(fx.state) + "/sumela/") and "/.claude/" not in path, path)
        saved = ""
        for dp, _, fns in os.walk(str(fx.state)):
            for fn in fns:
                saved += Path(dp, fn).read_text(encoding="utf-8", errors="replace")
        outs["state directory"] = (0, saved, "")
        leaks = []
        for label, (rc, out, err) in outs.items():
            low = (out + "\n" + err).lower()
            for c in CANARIES:
                if c.lower() in low:
                    leaks.append("%s: %s" % (label, c))
            for p in (str(base), str(fx.home), str(fx.repo)):
                if p in out or p in err:
                    leaks.append("%s: an absolute fixture path" % label)
        check("no canary in stdout, stderr, --json, --static or the state directory (0 leaks)", not leaks, leaks[:12])
        check("every run exited 0 or 2", all(v[0] in (0, 2) for k, v in outs.items() if k != "state directory"),
              {k: v[0] for k, v in outs.items()})
        check("the outputs are ASCII", all(v[1].isascii() for v in outs.values()))
        after = snapshot_tree(base, skip=[fx.state])
        check("the report wrote no file outside the state directory", before == after,
              sorted(set(after) ^ set(before))[:5])
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


# ---------------------------------------------------------------------------- simple sessions
def basic_session(fx, sid="s1", n=6, **kw):
    t = fx.tx(sid, **kw)
    t.snapshot()
    t.user("start the session")
    t.contract()
    for i in range(n):
        t.say("working %d" % i)
    fx.session(t)
    return t


def t_no_network():
    print("== t_no_network")
    base = tmpdir()
    try:
        fx = Fx(base)
        basic_session(fx)
        src = SCRIPT.read_text(encoding="utf-8")
        mods = re.findall(r"^\s*(?:import|from)\s+([A-Za-z0-9_.]+)", src, re.M)
        net = {"socket", "ssl", "http", "urllib", "ftplib", "smtplib", "poplib", "imaplib", "telnetlib", "xmlrpc",
               "asyncio", "requests", "urllib3", "selectors"}
        check("the report imports no network module", not (set(m.split(".")[0] for m in mods) & net), mods)
        saved = (socket.socket, socket.create_connection, socket.getaddrinfo)

        def boom(*a, **k):
            raise AssertionError("network access")

        class NoSocket(socket.socket):
            def __init__(self, *a, **k):
                raise AssertionError("network access")
        socket.socket, socket.create_connection, socket.getaddrinfo = NoSocket, boom, boom
        try:
            with in_process(fx):
                rc, out, err = call_main(["--json"])
        finally:
            socket.socket, socket.create_connection, socket.getaddrinfo = saved
        check("with socket.socket raising, the report still runs (exit 0)", rc == 0, err)
        check("…and prints its report", '"status": "ok"' in out)
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


def t_exit_codes_0_2_1():
    print("== t_exit_codes_0_2_1")
    base = tmpdir()
    try:
        fx = Fx(base)
        rc, out, err = fx.run()
        check("no transcripts for this install: exit 2", rc == 2, (rc, err))
        check("…with the --static hint", "--static" in out, out)
        rc, rep, _ = fx.json()
        check("…and --json says no_transcripts with the hint", rc == 2 and rep.get("status") == "no_transcripts"
              and "--static" in rep.get("hint", ""), rep)
        basic_session(fx)
        rc, out, err = fx.run()
        check("a SumelaOS session: exit 0", rc == 0, err)
        check("…nothing on stderr", err == "", err)
        rc, out, err = fx.run("--since", "2027-01-01")
        check("no session in the window: exit 2", rc == 2, (rc, err))
        check("…with the --static hint", "--static" in out, out)
        rc, out, err = fx.run(cwd=str(base))
        check("outside any install: exit 1", rc == 1, (rc, out))
        check("…one generic line on stderr, nothing on stdout", out == "" and len(err.strip().splitlines()) == 1, err)
        nogit = base / "nogit-zqpathcanary"
        (nogit / ".sumela").mkdir(parents=True)
        p = subprocess.run([sys.executable, "-I", str(SCRIPT)], cwd=str(nogit), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           env=fx.env(GIT_CEILING_DIRECTORIES=str(base)))
        err = p.stderr.decode()
        check("an install git cannot read: exit 1, one fixed line naming no path (git's own message is not printed)",
              p.returncode == 1 and len(err.strip().splitlines()) == 1 and "zqpathcanary" not in err
              and "git status" in err and p.stdout == b"", err)
        wtb = fx.repo / ".worktrees" / "zqbrokenwt"
        fx.git("worktree", "add", "-q", "-b", "zqbroken", str(wtb))
        shutil.rmtree(str(fx.repo / ".git" / "worktrees" / "zqbrokenwt"))
        rc, out, err = fx.run(cwd=str(wtb))
        check("a worktree whose git link is broken: exit 1 and one fixed stderr line naming no path",
              rc == 1 and len(err.strip().splitlines()) == 1 and str(base) not in err and "zqbroken" not in err, err)
        rc, out, err = fx.run(GIT_TRACE2="1", GIT_TRACE="1", GIT_TRACE_SETUP="1")
        check("git tracing in the environment: nothing reaches stderr", rc == 0 and err == "", err[:300])
        trace = base / "zqtrace.json"
        rc, out, err = fx.run(GIT_TRACE2_EVENT=str(trace))
        check("…and a trace2 event target gets no record of the tool's git calls", rc == 0 and not trace.exists(), err[:200])
        rc, out, err = fx.run("--bogus")
        check("a usage error: exit 1 with the usage", rc == 1 and "usage:" in err and out == "", (rc, err))
        rc, out, err = fx.run("--until", "not-a-date")
        check("an invalid date: exit 1", rc == 1, (rc, err))
        rc, out, err = fx.run("--help")
        check("--help: exit 0 with the usage", rc == 0 and "usage:" in out, (rc, out))
        rc, out, err = fx.run("--static")
        check("--static without the budget table: exit 2", rc == 2 and "sumela-context-budgets.tsv" in out, (rc, out))
        # an internal error prints a generic line only: the exception's text could carry data
        saved = M.parse_corpus

        def broken(*a, **k):
            raise RuntimeError("zqerrcanary /Users/someone/secret CNRY-4821")
        M.parse_corpus = broken
        try:
            with in_process(fx):
                rc, out, err = call_main([])
        finally:
            M.parse_corpus = saved
        check("an internal error: exit 1", rc == 1, (rc, err))
        check("…stdout empty, one generic stderr line naming only the class",
              out == "" and err.strip() == "sumela-token-report: could not run (internal error: RuntimeError); no data was printed", err)
        check("…the exception's text never printed", "zqerrcanary" not in err and "CNRY" not in err and "/Users" not in err)
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


# ---------------------------------------------------------------------------- compaction, subagents, PowerShell, worktrees, Windows
def t_compaction_subagent_powershell_worktree_windows_paths():
    print("== t_compaction_subagent_powershell_worktree_windows_paths")
    base = tmpdir()
    try:
        fx = Fx(base)
        r = str(fx.root)
        t = fx.tx("s1")
        t.snapshot()
        keep = t.user("the task: " + "p" * 1000)
        t.contract()
        t.tool("Read", {"file_path": r + "/.sumela/skills/context-handoff/SKILL.md"}, "h" * 5000)
        t.say("ok")
        t.compact(preserved=[keep])
        t.say("after the compaction")
        t.tool("PowerShell", {"command": "Get-Content -Path .sumela\\skills\\using-second-brain\\SKILL.md -TotalCount 40"}, "u" * 3000)
        t.tool("PowerShell", {"command": "gc docs\\second-brain\\wiki\\_INDEX.md | Select-Object -First 5"}, "i" * 500)
        t.tool("Read", {"file_path": r + "/.claude/worktrees/feat-zqwt/.sumela/skills/writing-plans/SKILL.md"}, "w" * 1500)
        t.tool("Read", {"file_path": r + "/.worktrees/feat-zqwt2/src/app.py"}, "code")
        t.tool("Agent", {"description": "task 3", "prompt": "You are the Implementer subagent for Task 3"}, "DONE",
               tur={"status": "completed"})
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh task close 2026-10-14-x --promoted D1"}, "closed")
        fx.session(t)
        s = Tx(r, sid="s1")
        s.user("You are the Implementer subagent for Task 3: implement it")
        s.tool("Read", {"file_path": r + "/.sumela/skills/subagent-driven-development/implementer-prompt.md"}, "x" * 800)
        s.compact()
        s.tool("SubagentHandback", {"message": "Status: DONE_WITH_CONCERNS\nall good"}, "ok")
        fx.subagent("s1", "a1", s, {"agentType": "general-purpose", "model": "claude-sonnet-4-5", "spawnDepth": 1})
        s2 = Tx(r, sid="s1")
        s2.user("Explore the code")
        s2.say("found it")
        fx.subagent("s1", "a2", s2, {"agentType": "Explore"})
        rc, rep, err = fx.json()
        check("exit 0", rc == 0, err)
        check("one compaction in the main thread", sec(rep, "session_shape", "compactions", "main") == 1,
              sec(rep, "session_shape", "compactions"))
        check("…and one in a subagent", sec(rep, "subagents", "compactions") == 1)
        check("two subagent threads", sec(rep, "subagents", "threads") == 2, sec(rep, "subagents"))
        roles = sec(rep, "subagents", "by_role") or {}
        check("roles from the framework's prompt phrases: implementer and explore",
              roles.get("implementer", {}).get("threads") == 1 and roles.get("explore", {}).get("threads") == 1, roles)
        check("agent types and models print from the fixed lists",
              set(sec(rep, "subagents", "by_agent_type") or {}) == {"general-purpose", "Explore"}
              and set(sec(rep, "subagents", "by_model") or {}) == {"claude-sonnet-4-5", "<none>"},
              (sec(rep, "subagents", "by_agent_type"), sec(rep, "subagents", "by_model")))
        ti = sec(rep, "guardrails", "turn_inflation") or {}
        check("the implementer's handback status counts as a completed task; task close is reported, never added",
              ti.get("completed_tasks") == 1 and ti.get("task_close_calls") == 1, ti)
        files = sec(rep, "framework_reads", "by_file") or {}
        check("PowerShell Get-Content reads are framework reads", ".sumela/skills/using-second-brain/SKILL.md" in files, sorted(files))
        check("…gc too (the wiki index)", "docs/second-brain/wiki/_INDEX.md" in files, sorted(files))
        check("a Claude Code worktree path prints without its name", ".sumela/skills/writing-plans/SKILL.md" in files, sorted(files))
        rc, out, _ = fx.run()
        check("worktree names never print", "zqwt" not in out)
        tot = sec(rep, "totals", "main") or {}
        # the preserved prompt (1,000+ chars) survives the compaction: carried by every request
        n_req = tot.get("requests")
        user_carried = (tot.get("carried_chars_by_group") or {}).get("user")
        check("a preserved message is carried by every request after the compaction too",
              user_carried is not None and user_carried >= 1010 * n_req, (user_carried, n_req))
        # ---- Windows paths, in process: git cannot produce a drive-letter root on this machine
        win_root = "C:/Users/dev/proj"
        pdir = Path(base, "wincfg", "projects", "C--Users-dev-proj")
        pdir.mkdir(parents=True)
        w = Tx("C:\\Users\\dev\\proj", sid="w1")
        w.snapshot()
        w.user("hello")
        w.tool("Read", {"file_path": "C:\\Users\\dev\\proj\\.sumela\\sumela-prompt.md"}, "c" * 400)
        w.tool("Read", {"file_path": "c:\\users\\dev\\proj\\docs\\second-brain\\wiki\\_INDEX.md"}, "i" * 400)
        w.tool("PowerShell", {"command": "Get-Content \"C:\\Users\\dev\\proj\\.sumela\\skills\\context-handoff\\SKILL.md\""}, "h" * 900)
        w.tool("Bash", {"command": "cat /c/Users/dev/proj/.sumela/rules/security_protocol.md"}, "r" * 300)
        w.tool("Read", {"file_path": "C:\\Users\\dev\\proj\\.claude\\worktrees\\zqwinwt\\.sumela\\skills\\writing-plans\\SKILL.md"}, "w" * 300)
        (pdir / "w1.jsonl").write_text(w.text(), encoding="utf-8")
        inst = M.Install(win_root, [(win_root, None)], "", str(Path(base, "wincfg")), "C:/Users/dev",
                         [(str(pdir), win_root, True)], {"main"})
        opts = M.Opts()
        wrep = M.report_from_install(inst, opts)
        check("Windows: the contract read by a drive-letter path makes a SumelaOS session",
              sec(wrep, "data_quality", "sessions_included") == 1, sec(wrep, "data_quality"))
        wf = sec(wrep, "framework_reads", "by_file") or {}
        for want in (".sumela/sumela-prompt.md", "docs/second-brain/wiki/_INDEX.md", ".sumela/skills/context-handoff/SKILL.md",
                     ".sumela/rules/security_protocol.md", ".sumela/skills/writing-plans/SKILL.md"):
            check("Windows: %s labelled from a backslash, lower-case or /c/ path" % want, want in wf, sorted(wf))
        check("Windows: a whole-file read of the index by a lower-case path counts for A5",
              (sec(wrep, "second_brain", "a5_whole_file_reads") or {}).get("attempts") == 1)
        check("Windows: an outside drive is <outside>", M.label_path("D:\\zq\\x.md", inst.roots) == "<outside>/*.md")
        check("Windows: the slug maps the drive colon and backslashes",
              "C--Users-dev-proj" in M.slugs("C:/Users/dev/proj") and "C--Users-dev-proj" in M.slugs("C:\\Users\\dev\\proj"))
        check("Windows: labels_redacted = 0", sec(wrep, "data_quality", "labels_redacted") == 0)
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


def t_claude_config_dir_honoured():
    print("== t_claude_config_dir_honoured")
    base = tmpdir()
    try:
        fx = Fx(base)
        alt = base / "altcfg"
        for sid in ("a1", "a2"):
            t = fx.tx(sid)
            t.contract()
            t.say("x")
            fx.session(t, cfg=alt)
        basic_session(fx, sid="decoy")
        rc, rep, err = fx.json(CLAUDE_CONFIG_DIR=str(alt))
        check("CLAUDE_CONFIG_DIR is read (2 sessions there)", rc == 0 and sec(rep, "data_quality", "sessions_included") == 2,
              (rc, err, sec(rep, "data_quality")))
        rc, rep, err = fx.json()
        check("without it, ~/.claude is read (the 1 session there)", rc == 0 and sec(rep, "data_quality", "sessions_included") == 1,
              (rc, err))
        empty = base / "emptycfg"
        empty.mkdir()
        rc, rep, err = fx.json(CLAUDE_CONFIG_DIR=str(empty))
        check("an empty CLAUDE_CONFIG_DIR: exit 2, never a fall-back to ~/.claude", rc == 2 and rep.get("status") == "no_transcripts")
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


def t_state_key_matches_bash():
    print("== t_state_key_matches_bash")
    base = tmpdir()
    try:
        fx = Fx(base)
        fx.git("worktree", "add", "-q", "-b", "topic", str(base / "wt"))
        mono = Fx(base / "m", name="mono", sub="svc/a")
        uni = Fx(base / "u", name="\u00f6 \u015f dir")
        cases = [(fx, fx.root, fx.root), (fx, base / "wt", base / "wt"), (fx, fx.root / "src", fx.root),
                 (mono, mono.root, mono.root), (uni, uni.root, uni.root)]
        for f, cwd, root in cases:
            p = subprocess.run(["bash", "-c", '. "$1"; cd "$2" && sumela_state_dir', "_", str(STATE_LIB), str(cwd)],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=f.env())
            want = p.stdout.decode("utf-8", "surrogateescape").strip()
            with in_process(f, cwd=str(cwd)):
                got = M.state_dir(str(root))
                found = M.find_install_root(None)
            label = str(cwd)[len(str(base)):]
            check("Python's state directory equals sumela_state_dir (%s)" % label, p.returncode == 0 and got == want, (want, got))
            check("…the install root is found from the working directory (%s)" % label, found is not None)
        with in_process(fx, XDG_STATE_HOME="relative/dir"):
            got = M.state_dir(str(fx.root))
        check("a relative XDG_STATE_HOME is ignored, as in bash", got.startswith(str(fx.home) + "/.local/state/sumela/"), got)
        with in_process(fx):
            try:
                M.write_state_file(str(fx.root), "../escape.json", b"x")
                refused = False
            except M.Failure:
                refused = True
            p = M.write_state_file(str(fx.root), "a.json", b"one")
            p2 = M.write_state_file(str(fx.root), "a.json", b"two")
        check("write_state_file refuses '..'", refused)
        check("write_state_file replaces in place", p == p2 and Path(p).read_bytes() == b"two")
        check("…and leaves no temporary file", not [n for n in os.listdir(os.path.dirname(p)) if "sumela-tmp" in n])
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


# ---------------------------------------------------------------------------- second brain
def t_digest_and_boot_reads_detected():
    print("== t_digest_and_boot_reads_detected")
    base = tmpdir()
    try:
        fx = Fx(base)
        r = str(fx.root)
        t = fx.tx("s1")
        t.contract()
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh digest"}, "digest output")
        t.tool("Read", {"file_path": r + "/docs/second-brain/wiki/_INDEX.md"},
               "<tool_use_error>File content (604.0KB) exceeds maximum allowed size (256KB).</tool_use_error>", is_error=True)
        t.tool("Read", {"file_path": r + "/docs/second-brain/wiki/active-project-context.md", "offset": 1, "limit": 50}, "a" * 900)
        t.tool("Bash", {"command": "cat docs/second-brain/wiki/active-project-context.md | head -50"}, "a" * 700)
        t.tool("Grep", {"pattern": "Sprint", "path": r + "/docs/second-brain/wiki/_INDEX.md"}, "match")
        t.tool("Read", {"file_path": r + "/docs/second-brain/wiki/architecture-decisions.md", "allow_large": True}, "d" * 3000)
        fx.session(t)
        t2 = fx.tx("s2")
        t2.contract()
        for i in range(11):
            t2.say("step %d" % i)
        t2.tool("Bash", {"command": "bash scripts/sumela-wiki.sh digest"}, "late digest")
        fx.session(t2)
        t3 = fx.tx("s3")
        t3.contract()
        t3.tool("PowerShell", {"command": "pwsh -NoProfile -File scripts/sumela-wiki.ps1 -C ..\\wt digest --branch"}, "x")
        t3.tool("Bash", {"command": "grep -n 'sumela-wiki digest' docs/notes.md"}, "x")
        fx.session(t3)
        rc, rep, err = fx.json()
        check("exit 0", rc == 0, err)
        sb = sec(rep, "second_brain") or {}
        check("A4: a digest among the first 10 requests in 2 of 3 sessions",
              sb.get("a4_digest_in_first_10_requests", {}).get("k") == 2 and sb["a4_digest_in_first_10_requests"].get("n") == 3,
              sb.get("a4_digest_in_first_10_requests"))
        a5 = sb.get("a5_whole_file_reads", {})
        check("A5: two whole-file reads of wiki special files, one refused at the size limit",
              a5.get("attempts") == 2 and a5.get("failures") == 1 and a5.get("size_refused") == 1, a5)
        check("A5: the failure is a boot-time one and its file is labelled",
              a5.get("failures_first_30_requests") == 1 and
              (a5.get("by_file") or {}).get("docs/second-brain/wiki/_INDEX.md", {}).get("failures") == 1, a5)
        check("A5: a ranged read is not a whole-file read",
              "docs/second-brain/wiki/active-project-context.md" not in (a5.get("by_file") or {}))
        check("allow_large: one call, on a wiki file", sb.get("allow_large_reads") == {"calls": 1, "on_wiki_files": 1},
              sb.get("allow_large_reads"))
        a6 = sb.get("a6_calls_naming_boot_files", {})
        check("A6: four calls name the boot files (Read, Read, cat, Grep), in one session",
              a6.get("calls") == 4 and a6.get("sessions") == 1 and a6.get("calls_by_file") == {"_INDEX.md": 2, "active-project-context.md": 2},
              a6)
        calls = sb.get("wiki_tool_calls", {})
        check("wiki tool calls: 2 digests and 1 digest --branch (a grep for the phrase is no call)",
              calls.get("digest") == 2 and calls.get("digest_branch") == 1, calls)
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


def t_a15_not_satisfied_by_bootstrap_digest_alone():
    print("== t_a15_not_satisfied_by_bootstrap_digest_alone")
    base = tmpdir()
    try:
        fx = Fx(base)
        r = str(fx.root)
        rec = "2026-10-14-zqa15task.md"
        tasks = fx.root / "docs" / "second-brain" / "wiki" / "_tasks"
        tasks.mkdir(parents=True)
        (tasks / rec).write_text("---\ntype: task\n---\n\n# Task\r\n\r\n## Task Ground Rules\r\n\r\n## Continue Point\r\n\r\n"
                                 "### feat/zqa15branch\r\n- 2026-10-14 \u00b7 next\r\n\r\n### feat/zqa15second\r\n- 2026-10-14 \u00b7 next\r\n"
                                 "\r\n## Sessions\r\n", encoding="utf-8")
        block = "Task rules (from docs/second-brain/wiki/_tasks/%s):\n- R1 rule" % rec
        br = "feat/zqa15branch"

        def edit(t):
            t.tool("Edit", {"file_path": r + "/src/a.txt", "old_string": "x", "new_string": "y"}, "ok")

        # S1: the bootstrap digest (no --branch) names the record: not enough
        t = fx.tx("s1", branch=br)
        t.contract()
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh digest"}, block)
        edit(t)
        fx.session(t)
        # S2: digest --branch naming the record, then the edit: satisfied
        t = fx.tx("s2", branch=br)
        t.contract()
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh digest --branch"}, block)
        edit(t)
        fx.session(t)
        # S3: digest --branch, then a compaction, then the edit: not satisfied
        t = fx.tx("s3", branch=br)
        t.contract()
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh digest --branch"}, block)
        t.compact()
        edit(t)
        fx.session(t)
        # S4: the rules obtained on the base, then a branch switch, then the edit: not satisfied
        t = fx.tx("s4", branch="main")
        t.contract()
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh digest --branch"}, block)
        t.tool("Bash", {"command": "git switch " + br}, "Switched to branch", branch_after=br)
        edit(t)
        fx.session(t)
        # S5: the post-checkout block names the record after the switch: satisfied
        t = fx.tx("s5", branch="main")
        t.contract()
        t.tool("Bash", {"command": "git checkout " + br}, "Switched to branch\n" + block, branch_after=br)
        edit(t)
        fx.session(t)
        # S6: an edit on a branch without a record does not qualify
        t = fx.tx("s6", branch="feat/no-record")
        t.contract()
        edit(t)
        fx.session(t)
        # S7: task show naming the record: satisfied
        t = fx.tx("s7", branch=br)
        t.contract()
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh task show --task 2026-10-14-zqa15task --rules"}, block)
        edit(t)
        fx.session(t)
        # S8: the rules shown on the main checkout, then a cd into the branch's linked worktree (no
        # gitBranch change recorded), then an edit there: not satisfied (a worktree entry)
        wt = base / "wt15"
        fx.git("worktree", "add", "-q", "-b", br, str(wt))
        t = fx.tx("s8", branch="main")
        t.contract()
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh task show --task 2026-10-14-zqa15task"}, block)
        t.tool("Bash", {"command": "cd ../wt15 && git status"}, "On branch")
        t.tool("Edit", {"file_path": str(wt) + "/src/a.txt", "old_string": "x", "new_string": "y"}, "ok")
        fx.session(t)
        # S9: the same, but digest --branch after the cd: satisfied
        t = fx.tx("s9", branch="main")
        t.contract()
        t.tool("Bash", {"command": "cd " + str(wt)}, "")
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh digest --branch"}, block)
        t.tool("Edit", {"file_path": str(wt) + "/src/a.txt", "old_string": "x", "new_string": "y"}, "ok")
        fx.session(t)
        # S10: a session working in the worktree prefixes its commands with cd <wt>: no new entry
        t = Tx(str(wt), sid="s10", branch=br)
        t.contract()
        t.tool("Bash", {"command": "cd " + str(wt) + " && bash scripts/sumela-wiki.sh digest --branch"}, block)
        t.tool("Bash", {"command": "cd " + str(wt) + " && git status"}, "On branch")
        t.tool("Edit", {"file_path": str(wt) + "/src/a.txt", "old_string": "x", "new_string": "y"}, "ok")
        fx.session(t)
        # S11: a path checkout (git checkout .) is no branch switch
        t = fx.tx("s11", branch=br)
        t.contract()
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh digest --branch"}, block)
        t.tool("Bash", {"command": "git checkout ."}, "Updated 1 path")
        edit(t)
        fx.session(t)
        # S12: an explicit switch whose block prints at once; gitBranch shows it one line later
        t = fx.tx("s12", branch="main")
        t.contract()
        t.tool("Bash", {"command": "git switch " + br}, "Switched to branch\n" + block)
        t.branch = br
        t.say("now on the branch")
        edit(t)
        fx.session(t)
        # S13: a temp-file write first is no edit on the branch; the repo edit follows the rules
        t = fx.tx("s13", branch=br)
        t.contract()
        t.tool("Write", {"file_path": "/tmp/scratch-notes.md", "content": "notes"}, "ok")
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh digest --branch"}, block)
        edit(t)
        fx.session(t)
        # S14: task show --task <key> whose output prints the rules but not the record's path
        t = fx.tx("s14", branch=br)
        t.contract()
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh task show --task 2026-10-14-zqa15task --rules"}, "- R1 rule")
        edit(t)
        fx.session(t)
        # S15: digest --branch naming the record by its key only
        t = fx.tx("s15", branch=br)
        t.contract()
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh digest --branch"}, "Your current task 2026-10-14-zqa15task, rules:\n- R1")
        edit(t)
        fx.session(t)
        # S16: git worktree add prints the block (R1-22b); the cd into that new worktree keeps it
        t = fx.tx("s16", branch="main")
        t.contract()
        t.tool("Bash", {"command": "git worktree add .worktrees/zqa15add -b feat/zqa15second"}, "Preparing worktree\n" + block)
        t.tool("Bash", {"command": "cd .worktrees/zqa15add"}, "")
        t.branch = "feat/zqa15second"
        t.tool("Edit", {"file_path": r + "/.worktrees/zqa15add/src/a.txt", "old_string": "x", "new_string": "y"}, "ok")
        fx.session(t)
        # S17: EnterWorktree's own result carries the block
        t = fx.tx("s17", branch="main")
        t.contract()
        t.tool("EnterWorktree", {"name": "zqa15second"}, "Entered the worktree\n" + block, branch_after="feat/zqa15second")
        t.tool("Edit", {"file_path": r + "/src/a.txt", "old_string": "x", "new_string": "y"}, "ok")
        fx.session(t)
        rc, rep, err = fx.json()
        a15 = sec(rep, "second_brain", "a15_continuity") or {}
        check("exit 0", rc == 0, err)
        check("sixteen sessions edit on a branch whose task has a record (a CRLF record is read)", a15.get("n") == 16, a15)
        check("twelve obtained the rules after the last switch, worktree entry or compaction", a15.get("k") == 12, a15)
        # each case on its own, so a regression names the rule it broke
        want = {"s1": False, "s2": True, "s3": False, "s4": False, "s5": True, "s7": True, "s8": False, "s9": True,
                "s10": True, "s11": True, "s12": True, "s13": True, "s14": True, "s15": True, "s16": True, "s17": True}
        opts = M.Opts()
        with in_process(fx):
            inst = M.discover(opts)
            inst.until = None
            cp = M.parse_corpus(inst)
        got = {th.sid: (th.x.a15_ok if th.x.a15_qual else None) for th in cp.threads if th.kind == "main"}
        for sid, ok in sorted(want.items(), key=lambda kv: int(kv[0][1:])):
            check("A15 case %s: %s" % (sid, "satisfied" if ok else "not satisfied"), got.get(sid) is ok, got.get(sid))
        check("A15 case s6: an edit on a branch without a record does not qualify", got.get("s6") is None, got.get("s6"))
        check("the record count is reported", a15.get("task_records_with_branch_blocks") == 1, a15)
        rc, out, _ = fx.run()
        check("the branch and the record never print", "zqa15" not in out.lower())
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


def t_planning_lookups_and_task_records():
    print("== t_planning_lookups_and_task_records (A16, A16b, Q17)")
    base = tmpdir()
    try:
        fx = Fx(base)
        r = str(fx.root)
        wiki = "bash scripts/sumela-wiki.sh "
        t = fx.tx("p1")
        t.contract()
        t.tool("Skill", {"skill": "brainstorming"}, "Launching skill: brainstorming")
        t.tool("Bash", {"command": wiki + "catalog specs --match login"}, "x")
        t.tool("Write", {"file_path": r + "/docs/second-brain/artifacts/specs/2026-10-14-x.md", "content": "spec"}, "ok")
        fx.session(t)
        t = fx.tx("p2")
        t.contract()
        t.user("Base directory for this skill: " + r + "/.sumela/skills/writing-plans\n\nbody", isMeta=True)
        t.tool("Write", {"file_path": r + "/docs/second-brain/artifacts/plans/2026-10-14-x.md", "content": "plan"}, "ok")
        t.tool("Bash", {"command": wiki + "search \"login\""}, "x")
        fx.session(t)
        t = fx.tx("p3")
        t.contract()
        t.tool("Bash", {"command": wiki + "entry architecture-decisions.md --list"}, "x")
        t.tool("Read", {"file_path": r + "/docs/second-brain/wiki/topic-page.md"}, "page")
        fx.session(t)
        t = fx.tx("p4")
        t.contract()
        t.tool("Read", {"file_path": r + "/docs/second-brain/wiki/insights/note.md"}, "page")
        t.tool("Read", {"file_path": r + "/docs/second-brain/wiki/topic-page.md"}, "page")
        fx.session(t)
        t = fx.tx("p5")
        t.contract()
        t.tool("Read", {"file_path": r + "/.sumela/skills/using-second-brain/task-records.md"}, "procedure")
        t.tool("Bash", {"command": wiki + "task show"}, "x")
        t.tool("Bash", {"command": wiki + "task rule \"no new deps\" --by user"}, "x")
        fx.session(t)
        t = fx.tx("p6")
        t.contract()
        t.tool("Bash", {"command": wiki + "task --task 2026-10-14-x decide \"use the queue\""}, "x")
        t.tool("Read", {"file_path": r + "/.sumela/skills/using-second-brain/task-records.md"}, "procedure")
        fx.session(t)
        t = fx.tx("p7")
        t.contract()
        t.tool("Skill", {"skill": "writing-plans"}, "Launching skill: writing-plans")
        t.tool("Bash", {"command": wiki + "entry architecture-decisions.md AD-12"}, "x")
        t.tool("Write", {"file_path": r + "/docs/second-brain/artifacts/plans/2026-10-15-y.md", "content": "plan"}, "ok")
        fx.session(t)
        t = fx.tx("p8")
        t.contract()
        t.tool("Bash", {"command": wiki + "entry tech-debt-and-known-issues.md TD-3 --move archive"}, "x")
        t.tool("Read", {"file_path": r + "/docs/second-brain/wiki/topic-page.md"}, "page")
        fx.session(t)
        rc, rep, err = fx.json()
        sb = sec(rep, "second_brain") or {}
        check("exit 0", rc == 0, err)
        check("A16: 1 of 3 planning sessions ran catalog, search or entry --list before the first artifact write "
              "(entry <id> is no such lookup)",
              sb.get("a16_lookup_before_planning_artifact", {}).get("n") == 3 and sb["a16_lookup_before_planning_artifact"].get("k") == 1,
              sb.get("a16_lookup_before_planning_artifact"))
        check("A16b: 1 of 3 sessions reading a curated page looked up first (entry --move is no lookup)",
              sb.get("a16b_lookup_before_curated_page_read", {}).get("n") == 3 and sb["a16b_lookup_before_curated_page_read"].get("k") == 1,
              sb.get("a16b_lookup_before_curated_page_read"))
        q17 = sb.get("q17_task_records_read_before_first_task_write", {})
        check("Q17: task-records.md read before the first task write in 1 of 2 writing sessions (task show is no write)",
              q17.get("n") == 2 and q17.get("k") == 1, q17)
        check("…and the framework-reads section carries the same Q17 counter",
              sec(rep, "framework_reads", "read_before_acting", "task_records_read_before_first_task_write") == q17)
        calls = sb.get("wiki_tool_calls", {})
        check("wiki tool calls: catalog, search, entry --list, task show, two task writes",
              (calls.get("catalog"), calls.get("search"), calls.get("entry_list"), calls.get("task_show"), calls.get("task_write"))
              == (1, 1, 1, 1, 2), calls)
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


def t_handoffs_and_continuation():
    print("== t_handoffs_and_continuation")
    base = tmpdir()
    try:
        fx = Fx(base)
        r = str(fx.root)
        heading = "## Session Handoff \u2014 2026-10-14\n"
        # H1: the user asks; the skill runs; the template's handoff is printed (Full)
        t = fx.tx("h1")
        t.contract()
        t.user("the context is getting long, please prepare a handoff for a new session")
        t.tool("Skill", {"skill": "context-handoff"}, "Launching skill: context-handoff")
        t.user("Base directory for this skill: " + r + "/.sumela/skills/context-handoff\n\n" + "s" * 30000, isMeta=True)
        t.say(heading + "body " * 300 + "\n### Handoff Completeness\n\"Full\"\n")
        fx.session(t)
        # H2: the manual read at boot (no trigger), then an improvised handoff file without the heading
        t = fx.tx("h2")
        t.contract()
        t.tool("Read", {"file_path": r + "/.sumela/skills/context-handoff/SKILL.md"}, "m" * 36000)
        t.say("working")
        t.tool("Write", {"file_path": r + "/.sumela/.handoff/2026-10-14-ab12cd34.md", "content": "next: finish the parser " * 40}, "ok")
        fx.session(t)
        # H2b: the agent invokes the skill itself (its own trigger): the body is no read "before any trigger"
        t = fx.tx("h2b")
        t.contract()
        t.tool("Skill", {"skill": "context-handoff"}, "Launching skill: context-handoff")
        t.user("Base directory for this skill: " + r + "/.sumela/skills/context-handoff\n\n" + "m" * 1000, isMeta=True)
        fx.session(t)
        # H4: a bare mention ("a new session cookie") with a long, structured reply is no handoff
        t = fx.tx("h4")
        t.contract()
        t.user("fix the bug where a new session cookie is not set after the handoff to the payment page")
        t.say("## Findings\n" + "explanation " * 120)
        fx.session(t)
        # H3: starts from a pasted handoff (a continuation), edits, then task continue at its end
        t = fx.tx("h3", ctx=60000)
        t.user(heading + "pasted " * 200)
        t.contract()
        t.tool("Read", {"file_path": r + "/docs/second-brain/artifacts/plans/x.md"}, "p" * 4000, grow=40000)
        t.tool("Edit", {"file_path": r + "/src/a.txt", "old_string": "x", "new_string": "y"}, "ok", grow=5000)
        r_at_edit = t.ctx
        t.say("done")
        t.tool("Bash", {"command": "bash scripts/sumela-wiki.sh task continue \"wire the CLI\""}, "ok")
        fx.session(t)
        rc, rep, err = fx.json()
        h = sec(rep, "handoffs") or {}
        check("exit 0", rc == 0, err)
        check("three handoffs detected, one per session", h.get("detected") == 3 and h.get("sessions_with_a_handoff") == 3, h)
        check("signals: template 1, user phrase 1, handoff file 1, task continue near the end 1",
              h.get("by_signal") == {"template": 1, "user_phrase": 1, "handoff_file": 1, "task_continue_near_end": 1},
              h.get("by_signal"))
        check("two were improvised (no template heading)", h.get("detected_without_the_template_heading") == 2, h)
        check("Full share: 1 of 1 template handoffs", h.get("full_share_of_template_handoffs", {}).get("k") == 1
              and h["full_share_of_template_handoffs"].get("n") == 1, h.get("full_share_of_template_handoffs"))
        check("one continuation session; R_continuation is its context at the first edit",
              h.get("continuation_sessions") == 1 and (h.get("r_continuation_tokens") or {}).get("p50") == r_at_edit,
              (h.get("r_continuation_tokens"), r_at_edit))
        ch = sec(rep, "framework_reads", "context_handoff") or {}
        check("context-handoff/ read before any trigger in 1 session (the boot read), 36,000 chars",
              ch.get("sessions_reading_before_any_trigger") == 1 and ch.get("chars_read_before_any_trigger_total") == 36000, ch)
        check("…three sessions read it at all; the agent's own Skill call is a trigger, a bare mention is none",
              ch.get("sessions_reading") == 3 and ch.get("sessions_with_a_trigger") == 2, ch)
        rba = sec(rep, "framework_reads", "read_before_acting", "handoff_procedure_read_before_handoff") or {}
        check("Q17: the procedure was read before 2 of the 3 handoffs", rba.get("n") == 3 and rba.get("k") == 2, rba)
        check("Q17: after the last trigger in 1 of 3 (the boot read alone does not count there)",
              rba.get("after_last_trigger_k") == 1, rba)
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


def t_sumela_session_filter():
    print("== t_sumela_session_filter")
    base = tmpdir()
    try:
        fx = Fx(base)
        r = str(fx.root)
        a = fx.tx("a")
        a.contract()
        a.say("x")
        fx.session(a)
        b = fx.tx("b")
        b.attach({"type": "file", "filename": r + "/.sumela/sumela-prompt.md", "displayPath": ".sumela/sumela-prompt.md"},
                 rendered="contract")
        b.say("x")
        fx.session(b)
        c = fx.tx("c")
        c.say("no contract here")
        fx.session(c)
        d = fx.tx("d")
        d.tool("Bash", {"command": "cat .sumela/sumela-prompt.md"}, "contract")
        fx.session(d)
        e = fx.tx("e")
        e.attach({"type": "edited_text_file", "filename": r + "/.sumela/sumela-prompt.md"}, rendered="diff")
        e.say("x")
        fx.session(e)
        rc, rep, err = fx.json()
        dq = sec(rep, "data_quality") or {}
        check("sessions that read (Read, cat) or attach the contract count", dq.get("sessions_included") == 3, dq)
        check("the rest are excluded and counted (an edit notice is no read)",
              (dq.get("excluded_sessions") or {}).get("not_a_sumela_session") == 2, dq)
        orphan = Tx(r, sid="gone")
        orphan.user("You are the Implementer subagent for Task 1")
        orphan.say("Status: DONE")
        fx.subagent("gone", "o1", orphan, {"agentType": "general-purpose"})
        rc, rep, err = fx.json()
        check("an orphan subagent thread (no main transcript) is counted, not included",
              sec(rep, "data_quality", "orphan_subagent_threads") == 1 and sec(rep, "subagents", "threads") == 0,
              (sec(rep, "data_quality"), sec(rep, "subagents", "threads")))
        rc, rep, err = fx.json("--all-sessions")
        check("--all-sessions counts every session", sec(rep, "data_quality", "sessions_included") == 5)
        check("…and the orphan subagent thread, as the research scripts did", sec(rep, "subagents", "threads") == 1
              and sec(rep, "data_quality", "orphan_subagent_threads_included") is True, sec(rep, "subagents"))
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


def t_linked_worktree_transcripts():
    print("== t_linked_worktree_transcripts (and --main-checkout-only)")
    base = tmpdir()
    try:
        fx = Fx(base)
        wt = base / "proj-feature"
        fx.git("worktree", "add", "-q", "-b", "feat/zqwtdirbranch", str(wt))
        basic_session(fx, sid="m1")
        t = Tx(str(wt), sid="w1", branch="feat/zqwtdirbranch")
        t.contract()
        t.say("in the worktree")
        fx.session(t, path=wt)
        rc, rep, err = fx.json()
        dq = sec(rep, "data_quality") or {}
        check("the main checkout's and the linked worktree's transcript directories are both read",
              rc == 0 and dq.get("project_dirs_scanned") == 2 and dq.get("sessions_included") == 2, (rc, err, dq))
        check("…and the worktree's sessions are counted apart", dq.get("sessions_from_linked_worktree_dirs") == 1, dq)
        gone = str(fx.root) + "/.worktrees/zqgonewt"          # a worktree folder git no longer lists
        t = Tx(gone, sid="g1", branch="feat/zqgone")
        t.contract()
        t.say("in a removed worktree")
        fx.session(t, path=gone)
        rc, rep, err = fx.json()
        dq = sec(rep, "data_quality") or {}
        check("a removed nested worktree's transcript directory is still read",
              dq.get("project_dirs_scanned") == 3 and dq.get("sessions_from_linked_worktree_dirs") == 2, dq)
        rc, rep, err = fx.json("--main-checkout-only")
        dq = sec(rep, "data_quality") or {}
        check("--main-checkout-only reads the main checkout's directory only (the research scripts' scope)",
              rc == 0 and dq.get("project_dirs_scanned") == 1 and dq.get("sessions_included") == 1, dq)
        rc, out, _ = fx.run()
        check("the worktree's directory name and branch never print", "proj-feature" not in out and "zqwtdir" not in out)
        rc, rep, err = fx.json(cwd=str(wt))
        check("run from inside the linked worktree, the report finds the same sessions",
              rc == 0 and sec(rep, "data_quality", "sessions_included") == 3, (rc, err))
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


def t_malformed_lines_counted_not_fatal():
    print("== t_malformed_lines_counted_not_fatal")
    base = tmpdir()
    try:
        fx = Fx(base)
        t = fx.tx("s1")
        t.contract()
        t.raw("{not json")
        t.raw("")
        t.raw("[1, 2, 3]")
        t.raw('{"type": "assistant", "message": {"id": "x", "content": [')
        t.raw('{"type": "assistant", "message": "a string"}')
        t.raw('{"type": "assistant", "message": {"id": "m9", "usage": {"input_tokens": "12"}, "content": "text"}}')
        t.raw('{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "nope", "content": 5}]}}')
        t.raw('{"type": "attachment", "attachment": {"type": "instructions", "files": "x"}, "rendered": 7}')
        t.raw('{"type": "system", "subtype": "compact_boundary", "compactMetadata": "x"}')
        t.raw('{"type": "assistant", "timestamp": "yesterday", "message": {"id": "m8", "model": "<synthetic>", '
              '"usage": {"input_tokens": 5}, "content": [{"type": "tool_use", "id": 3, "name": 7, "input": "x"}]}}')
        # unhashable values where strings are expected: guarded, never a TypeError
        t.raw('{"type": "assistant", "uuid": ["u"], "gitBranch": {"b": 1}, "cwd": 5, "message": {"id": ["m7"], "usage": '
              '{"input_tokens": 9}, "content": [{"type": "tool_use", "id": ["t7"], "name": ["Read"], "input": {"file_path": ["x"]}}]}}')
        t.raw('{"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": ["t7"], "content": [{"type": "text", "text": 5}]}]}}')
        t.raw('{"type": "system", "subtype": "compact_boundary", "compactMetadata": {"preservedMessages": {"allUuids": 7}}}')
        t.raw('{"type": "attachment", "attachment": {"type": "instructions", "files": 7}, "rendered": [{"content": "x"}]}')
        t.raw('{"type": "assistant", "message": {"id": "m6", "usage": {"input_tokens": 4}, "content": [{"type": "tool_use", '
              '"id": "t6", "name": "MultiEdit", "input": {"file_path": "a", "edits": 3}}]}}')
        t.raw('{"type": "assistant", "timestamp": "0001-01-01T00:00:00+05:00", "message": {"id": "o1", "usage": {"input_tokens": 5}, "content": []}}')
        t.raw('{"type": "assistant", "timestamp": "9999-12-31T23:59:59-05:00", "message": {"id": "o2", "usage": {"input_tokens": 5}, "content": []}}')
        t.raw('{"type": "assistant", "message": {"id": "o3", "usage": {"input_tokens": 1e999, "cache_read_input_tokens": Infinity}, "content": []}}')
        t.raw('{"type": "assistant", "message": {"id": "o4", "usage": {"input_tokens": 1' + "0" * 400 + '}, "content": []}}')
        t.raw('{"type": "assistant", "message": {"id": "o5", "usage": {"input_tokens": NaN, "output_tokens": -7}, "content": []}}')
        t.raw('{"type": "assistant", "version": "2.1.300\\n", "message": {"id": "o6", "usage": {"input_tokens": 4}, "content": []}}')
        t.say("still fine")
        p = fx.pdir() / "s1.jsonl"
        data = t.text().encode("utf-8") + b"\xff\xfe\xfa not utf-8\n"
        p.write_bytes(data)
        rc, rep, err = fx.json()
        dq = sec(rep, "data_quality") or {}
        check("malformed lines do not stop the report (exit 0)", rc == 0, err)
        check("three malformed lines counted (bad JSON, truncated, not UTF-8); blank lines are not malformed",
              dq.get("malformed_lines") == 3, dq)
        check("one non-object line counted", dq.get("non_object_lines") == 1, dq)
        check("the synthetic message is not a request", dq.get("synthetic_or_zero_usage_messages", 0) >= 1, dq)
        check("the session still counts", dq.get("sessions_included") == 1, dq)
        check("unhashable and odd shapes are handled, not counted as unprocessable", dq.get("unprocessable_lines") == 0, dq)
        check("extreme timestamps and token counts (1e999, Infinity, NaN, 10**400) do not stop the report",
              rc == 0 and dq.get("sessions_included") == 1, dq)
        check("a version with a trailing newline is not printed", dq.get("claude_code_versions") == ["2.1.300"], dq)
        sub_dir = fx.pdir() / "s1" / "subagents"
        sub_dir.mkdir(parents=True)
        (sub_dir / "agent-x.jsonl").write_text(fx.tx("s1").text() + json.dumps({"type": "user", "message": {"content": "hi"}}) + "\n")
        (sub_dir / "agent-x.meta.json").write_text('{"agentType": ["list"], "model": {"m": 1}}')
        rc, rep, err = fx.json()
        check("a meta.json with unhashable values does not stop the report", rc == 0, err)
        # the per-line safety net: an unexpected shape costs one line, never the report
        saved = M.attachment

        def odd(th, d, uuid):
            raise TypeError("zqshapecanary")
        M.attachment = odd
        try:
            with in_process(fx):
                rc, out, err = call_main(["--json"])
        finally:
            M.attachment = saved
        rep = json.loads(out) if out else {}
        check("an exception inside one line is counted (unprocessable_lines) and the report still exits 0",
              rc == 0 and sec(rep, "data_quality", "unprocessable_lines", ) >= 1 and "zqshapecanary" not in out + err, (rc, err))
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


# ---------------------------------------------------------------------------- the model, reproducibly
def t_hostile_text_stays_linear():
    print("== t_hostile_text_stays_linear")
    import time
    # Sizes at which the unbounded forms took seconds (cubic or quadratic backtracking): a regression
    # fails here instead of hanging the suite. The bounded forms are instant.
    pats = [("COMPLETENESS", M.COMPLETENESS, "### Handoff Completeness" + "\n \n" * 500 + "!"),
            ("STATUS_RE", M.STATUS_RE, "Status:" + " " * 30000 + "x"),
            ("REDIRECT_HANDOFF", M.REDIRECT_HANDOFF, ">" + "<a>" * 20000),
            ("HANDOFF_SHAPE", M.HANDOFF_SHAPE, "\n" * 30000 + "x"),
            ("HANDOFF_HEADING", M.HANDOFF_HEADING, "#" + " " * 100000 + "x"),
            ("HANDOFF_PHRASE", M.HANDOFF_PHRASE, "yeni session" + "a" * 100000 + " " * 1000),
            ("split_shell heredocs", None, "cat " + "<< " * 40000)]
    for name, rx, text in pats:
        t0 = time.time()
        if rx is None:
            M.split_shell(text)
        else:
            rx.search(text)
        dt = time.time() - t0
        check("%s on hostile text runs in under a second (%.2fs)" % (name, dt), dt < 1.0)
    base = tmpdir()
    try:
        fx = Fx(base)
        t = fx.tx("s1")
        t.contract()
        t.user("please prepare a handoff for a new session")
        t.say("### Handoff Completeness" + "\n \n" * 500 + "! " * 500)
        t.tool("Bash", {"command": "cat <<EOF > out.txt\n" + "<a>" * 20000 + "\nEOF"}, "ok")
        s2 = Tx(str(fx.root), sid="s1")
        s2.user("You are the Implementer subagent for Task 1")
        s2.say("Status:" + " " * 30000 + "DONE")
        fx.subagent("s1", "a1", s2, {"agentType": "general-purpose"})
        fx.session(t)
        t0 = time.time()
        rc, out, err = fx.run("--json")
        dt = time.time() - t0
        check("a transcript full of hostile text reports in seconds (%.1fs)" % dt, rc == 0 and dt < 20, (rc, err[:200]))
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


def t_research_model_by_hand():
    print("== t_research_model_by_hand (totals, carried chars, >=500K, --until, --since)")
    base = tmpdir()
    try:
        fx = Fx(base)
        r = str(fx.root)
        t = fx.tx("s1", t0=datetime(2026, 10, 2, 8, 0, 0, tzinfo=UTC))
        keep = t.user("u" * 1000)                                                  # k=0, preserved
        t.tool("Read", {"file_path": r + "/.sumela/sumela-prompt.md"}, "c" * 2000, ctx=100000)  # req 1, result at k=1
        t.assistant([{"type": "text", "text": "a" * 300}, {"type": "text", "text": "b" * 200}], ctx=200000)  # req 2, two blocks
        t.assistant([{"type": "text", "text": "z"}], model="<synthetic>",
                    usage={"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0})
        t.say("d" * 100, ctx=600000)                                               # req 3, >=500K
        t.compact(preserved=[keep], summary="s" * 400)                             # at k=3
        t.say("e" * 50, ctx=40000)                                                 # req 4
        t.say("late", ctx=50000, step=3600 * 24 * 10)                              # req 5, ten days later
        fx.session(t)
        rc, rep, err = fx.json("--until", "2026-10-05")
        tot = sec(rep, "totals", "main") or {}
        check("exit 0", rc == 0, err)
        check("--until drops the late line: 4 requests (two blocks of one message are one; synthetic dropped)",
              tot.get("requests") == 4, tot)
        check("context tokens are input + cache creation + cache read, summed",
              tot.get("context_tokens") == 100000 + 200000 + 600000 + 40000, tot.get("context_tokens"))
        check("lines after --until are counted", sec(rep, "data_quality", "lines_after_until") == 1, sec(rep, "data_quality"))
        carried = tot.get("carried_chars_by_group") or {}
        raw = tot.get("raw_chars_by_group") or {}
        # user: the 1,000-char prompt, re-sent by requests 1-3, preserved, then by request 4 (4 sends);
        #       the 400-char summary arrives after the boundary and is re-sent by request 4 (1 send)
        check("carried user chars: 1,000 x 4 + 400 x 1", carried.get("user") == 1000 * 4 + 400, carried)
        # tr_read: the 2,000-char result arrives after request 1, re-sent by requests 2 and 3
        check("carried Read chars: 2,000 x 2 (the compaction drops it)", carried.get("tr_read") == 2000 * 2, carried)
        # assistant text: 300 + 200 re-sent by request 3; the synthetic message's "z" is context too
        # (it is no request); the 100 chars after request 3 are never re-sent before the boundary
        check("assistant text: (300 + 200 + 1) x 1", carried.get("asst_text") == 501, carried)
        check("raw chars are counted once", raw.get("user") == 1400 and raw.get("tr_read") == 2000, raw)
        ge = sec(rep, "session_shape", "ge_500k", "main") or {}
        check(">=500K share of main context = 600,000 / 940,000",
              abs((ge.get("context_pct") or 0) - 100.0 * 600000 / 940000) < 1e-6 and ge.get("requests_pct") == 25.0, ge)
        check("the calibration falls back to the research defaults on a tiny corpus",
              sec(rep, "calibration", "fit_status") == "defaults"
              and sec(rep, "calibration", "tokens_per_char", "tr_read") == 0.42
              and sec(rep, "calibration", "tokens_per_char", "image") == 0.25, sec(rep, "calibration"))
        rc, rep, err = fx.json("--since", "2026-10-03")
        check("--since drops a session that started before it", rc == 2 and
              (sec(rep, "data_quality", "excluded_sessions") or {}).get("before_since") == 1, (rc, sec(rep, "data_quality")))
        # the regression itself, on a known linear relation: coefficients come back exactly
        rows = [([float(i % 7), float((i * 3) % 11), 1.0], 0.4 * (i % 7) + 0.25 * ((i * 3) % 11) + 5.0) for i in range(120)]
        fit = M.ols_multi(rows, ["a", "b", "intercept"])
        check("ols_multi recovers known coefficients", fit and abs(fit["a"] - 0.4) < 1e-9 and abs(fit["b"] - 0.25) < 1e-9
              and abs(fit["intercept"] - 5.0) < 1e-9, fit)
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


# ---------------------------------------------------------------------------- the allow-list itself
def t_label_path_allow_list():
    print("== t_label_path_allow_list")
    R = "/r/proj"
    roots = [R]
    cases = [
        (R + "/src/zq/app.py", "src/**/*.py"), ("zqdir/app.py", "<dir>/**/*.py"), ("README.md", "<root>/*.md"),
        ("./src/x.ts", "src/**/*.ts"), ("/Users/x/zq.md", "<outside>/*.md"), ("~/notes/zq.md", "<outside>/*.md"),
        ("/r/proj-other/x.md", "<outside>/*.md"), (R, "<root>/*<noext>"), ("", "<none>"), (None, "<none>"),
        (".sumela/sumela-prompt.md", ".sumela/sumela-prompt.md"), ("AGENTS.md", "AGENTS.md"), (R + "/CLAUDE.md", "CLAUDE.md"),
        ("src/CLAUDE.md", "src/**/*.md"),
        (".sumela/skills/brainstorming/SKILL.md", ".sumela/skills/brainstorming/SKILL.md"),
        (".sumela/skills/brainstorming/scripts/server.cjs", ".sumela/skills/brainstorming/scripts/server.cjs"),
        (".sumela/skills/brainstorming/zqnotes.md", ".sumela/skills/brainstorming/*.md"),
        (".sumela/skills/brainstorming/proj-4821.md", ".sumela/skills/brainstorming/*.md"),
        (".sumela/skills/using-second-brain/task-records.md", ".sumela/skills/using-second-brain/task-records.md"),
        (".sumela/skills/zqoverlay/SKILL.md", ".sumela/skills/<overlay>/*.md"),
        (".sumela/skills/qdrant-session-memory/SKILL.md", ".sumela/skills/<overlay>/*.md"),
        (".sumela/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py",
         ".sumela/memory-plugins/qdrant-session-memory/scripts/query-qdrant.py"),
        (".sumela/memory-plugins/zq/SKILL.md", ".sumela/memory-plugins/<overlay>/*.md"),
        (".sumela/rules/security_protocol.md", ".sumela/rules/security_protocol.md"),
        (".sumela/rules/templates/backend_standards.md.empty", ".sumela/rules/templates/backend_standards.md.empty"),
        (".sumela/rules/zqsub/security_protocol.md", ".sumela/rules/<overlay>/*.md"),
        (".sumela/rules/zqrule.md", ".sumela/rules/<overlay>/*.md"), (".sumela/rules/domains/acme.md", ".sumela/rules/<overlay>/*.md"),
        (".sumela/reviews/feat-zq-1.md", ".sumela/<runtime>/*.md"), (".sumela/.handoff/latest-ab12.md", ".sumela/<runtime>/*.md"),
        (".sumela/.upgrade/plan.json", ".sumela/<runtime>/*.json"), (".sumela/VERSION", ".sumela/<runtime>/*<noext>"),
        ("docs/second-brain/wiki/_INDEX.md", "docs/second-brain/wiki/_INDEX.md"),
        ("docs/second-brain/wiki/zqpage.md", "docs/second-brain/wiki/<page>/*.md"),
        ("docs/second-brain/wiki/session-summaries/2026-zq.md", "docs/second-brain/wiki/session-summaries/*.md"),
        ("docs/second-brain/wiki/_tasks/2026-10-14-zq.md", "docs/second-brain/wiki/_tasks/*.md"),
        ("docs/second-brain/artifacts/specs/zq.md", "docs/second-brain/artifacts/specs/*.md"),
        ("docs/second-brain/artifacts/zqdir/zq.md", "docs/second-brain/artifacts/<dir>/*.md"),
        ("docs/second-brain/artifacts/zq.md", "docs/second-brain/artifacts/<dir>/*.md"),
        (".worktrees/feat-zq/src/a.py", "src/**/*.py"), (".claude/worktrees/zq/AGENTS.md", "AGENTS.md"),
        (R + "/worktrees/feat-CNRY-1/.sumela/sumela-prompt.md", ".sumela/sumela-prompt.md"),
        ("src/app.zqcanry", "src/**/*.<other>"), ("src/Makefile", "src/**/*<noext>"), ("src/app.PY", "src/**/*.py"),
        ("C:\\Users\\dev\\proj\\x.md", "<outside>/*.md"),
    ]
    for p, want in cases:
        got = M.label_path(p, roots)
        check("label_path(%r) = %s" % (p, want), got == want, got)
        check("…and the sanitizer accepts it", M.valid_path_label(got), got)
    # every label_path output is a valid label, over adversarial inputs
    weird = ["a/b/c/d/e/f.md", "../../etc/passwd", "~", "/", "C:", "C:/", "\\\\server\\share\\x.md", ".sumela/", ".sumela",
             ".sumela/skills/", ".sumela/skills/brainstorming", "docs/second-brain/wiki/", "docs/second-brain/wiki/x/y/z.md",
             "docs/second-brain/artifacts/specs", "x" * 400 + ".md", "\u00f6\u015f/\u0130.md", "a b/c d.md", "src/.env",
             ".sumela/rules/templates/zq.md", ".sumela/rules/templates/", "$(rm -rf)/x", "`x`/y", "src/x.tar.gz"]
    bad = [w for w in weird if not M.valid_path_label(M.label_path(w, roots))]
    check("every label_path output passes the independent check", not bad, [(w, M.label_path(w, roots)) for w in bad])
    for lab in ("src/zq/**/*.py", "zq/**/*.py", ".sumela/skills/brainstorming/zq.md", ".sumela/rules/zq/x.md",
                "docs/second-brain/wiki/zq/*.md", "<root>/*.zqcanry", "feat/login", "CNRY-4821"):
        check("the independent check refuses %r" % lab, not M.valid_path_label(lab))


def t_sanitize_redacts_unknown():
    print("== t_sanitize_redacts_unknown")
    rep = {"schema": M.SCHEMA, "status": "ok", "generated_utc": "2026-10-14T00:00:00Z",
           "sections": {"data_quality": {"labels_redacted": 0, "claude_code_versions": ["2.1.3", "zqver", "2.1.300\n"],
                                         "window": {"until": "2026-10-14T00:00:00Z\n"}},
                        "framework_reads": {"by_file": {"zq/secret.md": {"reads": 1}, "AGENTS.md": {"reads": 2},
                                                        "<root>/*.md\n": {"reads": 1},
                                                        ".sumela/skills/brainstorming/SKILL.md\n": {"reads": 1}}},
                        "other": {"Bad Key": 1, "ok_key": "zqstring", "nested": {"feat/branch": 3}, "snake_key\n": 1},
                        "composition": {"all": {"shares_pct": {"tool_result:Bash\n": 1.0, "tool_result:Bash": 2.0}}},
                        "subagents": {"by_model": {"claude-opus-5-5": {"threads": 1}, "claude-zq": {"threads": 1},
                                                   "claude-opus-4\n": {"threads": 1}}}}}
    clean = M.finalize(rep)
    text = json.dumps(clean)
    check("an unknown path label, key, string, version and model are redacted",
          all(s not in text for s in ("zq/secret.md", "Bad Key", "zqstring", "zqver", "feat/branch", "claude-zq\"")), text)
    check("a trailing newline never passes a validator (versions, date-times, labels, keys, models)", "\\n" not in text, text)
    check("…allowed ones survive", "AGENTS.md" in text and "claude-opus-5-5" in text and "2.1.3" in text, text)
    check("…and every redaction is counted", sec(clean, "data_quality", "labels_redacted") == 13, sec(clean, "data_quality"))


def t_static_footprint():
    print("== t_static_footprint")
    base = tmpdir()
    try:
        fx = Fx(base)
        (fx.root / "scripts" / "lib").mkdir(parents=True)
        shutil.copy(str(BUDGETS), str(fx.root / "scripts" / "lib" / "sumela-context-budgets.tsv"))
        (fx.root / "AGENTS.md").write_bytes(b"line one\r\nline two\r\n")
        rc, rep, err = fx.json("--static")
        eager = sec(rep, "static_footprint", "eager_set") or {}
        check("--static: exit 0 without any transcript", rc == 0, err)
        check("--static measures the live AGENTS.md (CRLF read as LF)", eager.get("AGENTS.md", {}).get("bytes") == 18
              and eager["AGENTS.md"].get("live") is True, eager.get("AGENTS.md"))
        check("--static falls back to the template when the live file is absent (CLAUDE.md)",
              eager.get("CLAUDE.md", {}).get("live") is False, eager.get("CLAUDE.md"))
        check("--static reports the pinned eager total", sec(rep, "static_footprint", "eager_total_pinned_bytes") == 134641)
        rc, out, err = fx.run("--static")
        check("--static text output", rc == 0 and "Static footprint" in out, out[:200])
        tsv = fx.root / "scripts" / "lib" / "sumela-context-budgets.tsv"
        tsv.write_text(tsv.read_text(encoding="utf-8").replace("\t457\t", "\t45\u00b2\t"), encoding="utf-8")
        rc, rep, err = fx.json("--static")
        check("--static: a non-ASCII digit in the budget table is no number (exit 0, no pin)",
              rc == 0 and (sec(rep, "static_footprint", "eager_set") or {}).get("CLAUDE.md", {}).get("pinned_bytes", 0) is None,
              (rc, err[:200]))
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


def t_wrappers():
    print("== t_wrappers (sh, ps1)")
    base = tmpdir()
    try:
        fx = Fx(base)
        basic_session(fx)
        p = subprocess.run(["bash", str(SH), "--json"], cwd=str(fx.root), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=fx.env())
        rc, out, _ = fx.run("--json")
        strip = lambda s: re.sub(r'"generated_utc": "[^"]*"', "", s)
        check("sh wrapper: the report's exit code and output", p.returncode == 0 and strip(p.stdout.decode()) == strip(out),
              p.stderr.decode()[:300])
        p = subprocess.run(["bash", str(SH), "--since", "2030-01-01"], cwd=str(fx.root), stdout=subprocess.PIPE, env=fx.env())
        check("sh wrapper: passes exit 2 through", p.returncode == 2)
        nopy = base / "nopy"
        nopy.mkdir()
        os.symlink(shutil.which("dirname"), str(nopy / "dirname"))
        p = subprocess.run([shutil.which("bash"), str(SH)], cwd=str(fx.root), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           env=fx.env(PATH=str(nopy)))
        check("sh wrapper without Python: exit 1, 'optional tool: needs Python >=3.9'",
              p.returncode == 1 and "optional tool: needs Python >=3.9" in p.stderr.decode(), (p.returncode, p.stderr.decode()))
        old = base / "oldpy"
        old.mkdir()
        (old / "python3").write_text("#!/bin/sh\nexit 1\n")
        os.chmod(str(old / "python3"), 0o755)
        os.symlink(sys.executable, str(old / "python"))
        os.symlink(shutil.which("dirname"), str(old / "dirname"))
        p = subprocess.run([shutil.which("bash"), str(SH), "--help"], cwd=str(fx.root), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, env=fx.env(PATH=str(old)))
        check("sh wrapper: a python3 that fails the probe falls through to python",
              p.returncode == 0 and "usage:" in p.stdout.decode(), (p.returncode, p.stderr.decode()))
        check("ps1 wrapper is ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI)", PS1.read_bytes().isascii())
        check("the report itself is ASCII-only", SCRIPT.read_bytes().isascii())
        src = PS1.read_text()
        check("ps1 wrapper never bypasses the execution policy", "Bypass" not in src)
        check("ps1 wrapper probes python3, py -3, python and sets PYTHONUTF8",
              "@('python3'), @('py', '-3'), @('python')" in src and "$env:PYTHONUTF8 = '1'" in src)
        pwsh = shutil.which("pwsh") or (str(Path.home() / ".local/bin/pwsh") if (Path.home() / ".local/bin/pwsh").exists() else None)
        if not pwsh:
            print("  SKIP  ps1 wrapper runs (pwsh unavailable)")
            return
        p = subprocess.run([pwsh, "-NoProfile", "-NonInteractive", "-File", str(PS1), "--json"], cwd=str(fx.root),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=fx.env())
        check("ps1 wrapper (pwsh): the report's exit code and output",
              p.returncode == 0 and strip(p.stdout.decode()) == strip(out), p.stderr.decode()[:300])
        p = subprocess.run([pwsh, "-NoProfile", "-NonInteractive", "-File", str(PS1), "--since", "2030-01-01"], cwd=str(fx.root),
                           stdout=subprocess.PIPE, env=fx.env())
        check("ps1 wrapper (pwsh): passes exit 2 through", p.returncode == 2)
        p = subprocess.run([pwsh, "-NoProfile", "-NonInteractive", "-Command",
                            "Remove-Item Env:PYTHONUTF8 -ErrorAction SilentlyContinue; & $env:T_PS1 --help | Out-Null; "
                            "'unset:' + (Test-Path Env:PYTHONUTF8); $env:PYTHONUTF8 = '0'; & $env:T_PS1 --help | Out-Null; "
                            "'kept:' + $env:PYTHONUTF8"], cwd=str(fx.root), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           env=fx.env(T_PS1=str(PS1)))
        o = p.stdout.decode()
        check("ps1 wrapper (pwsh): a caller's PYTHONUTF8 is left as it was (unset stays unset, 0 stays 0)",
              "unset:False" in o and "kept:0" in o, (o, p.stderr.decode()[:200]))
        p = subprocess.run([pwsh, "-NoProfile", "-NonInteractive", "-File", str(PS1)], cwd=str(fx.root),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=fx.env(PATH=str(nopy)))
        check("ps1 wrapper (pwsh) without Python: exit 1, 'optional tool: needs Python >=3.9'",
              p.returncode == 1 and "optional tool: needs Python >=3.9" in p.stderr.decode(), (p.returncode, p.stderr.decode()))
    finally:
        shutil.rmtree(str(base), ignore_errors=True)


def t_core_manifest_matches_source():
    print("== t_core_manifest_matches_source")
    dirs = set()
    for kind in ("skills", "memory-plugins"):
        for d in (REPO / ".sumela" / kind).iterdir():
            if d.is_dir() and (d / "SKILL.md").exists():
                dirs.add(kind + "/" + d.name)
    check("the report's core skills and plugins are exactly the framework's", set(M.CORE_SKILLS) == dirs,
          sorted(set(M.CORE_SKILLS) ^ dirs))
    planned = {"skills/using-second-brain/task-records.md", "skills/using-second-brain/compaction.md"}
    stale = [u + "/" + f for u, fs in M.CORE_SKILL_FILES.items() for f in fs
             if not (REPO / ".sumela" / u / f).is_file() and u + "/" + f not in planned]
    check("every manifest file exists in the framework (task-records.md, compaction.md are planned)", not stale, stale)
    rules = set()
    for p in (REPO / ".sumela" / "rules").rglob("*"):
        if p.is_file():
            rules.add(str(p.relative_to(REPO / ".sumela" / "rules")).replace(os.sep, "/"))
    check("every framework rule file is a core rule", rules <= set(M.CORE_RULES), sorted(rules - set(M.CORE_RULES)))
    # Framework files the manifest does not name print as "*.<ext>": safe, but the report loses
    # them by name. As in tests/test_eager_budget.py, that is reported while a release is under
    # way and fails once .sumela/VERSION is past the previous final tag (the release task adds them).
    tracked = subprocess.run(["git", "-C", str(REPO), "ls-files", "--", ".sumela/skills", ".sumela/memory-plugins"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode("utf-8", "replace").split("\n")
    missing = []
    for line in tracked:
        parts = line.strip().split("/")
        if len(parts) >= 4 and parts[1] + "/" + parts[2] in M.CORE_SKILL_FILES:
            if "/".join(parts[3:]) not in M.CORE_SKILL_FILES[parts[1] + "/" + parts[2]]:
                missing.append("/".join(parts[1:]))
    tag = subprocess.run(["git", "-C", str(REPO), "describe", "--tags", "--abbrev=0", "--match", "v[0-9]*",
                          "--exclude", "*-rc.*", "HEAD"], stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode().strip()
    version = (REPO / ".sumela" / "VERSION").read_text(encoding="utf-8").strip() if (REPO / ".sumela" / "VERSION").exists() else ""
    as_tuple = lambda v: tuple(int(x) for x in v.split(".")) if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", v) else None
    releasing = bool(tag) and as_tuple(tag[1:]) is not None and as_tuple(version) is not None and as_tuple(version) > as_tuple(tag[1:])
    if releasing:
        check("every tracked framework skill or plugin file is in the report's manifest (release %s)" % version, not missing, missing)
    elif missing:
        print("  NOTE  framework files the manifest does not name yet (they print as *.<ext>; the release task adds them): %s"
              % missing[:10])
    else:
        check("every tracked framework skill or plugin file is in the report's manifest", True)


def main():
    if not SCRIPT.is_file():
        print("FAIL: %s missing" % SCRIPT)
        return 1
    for t in (t_label_path_allow_list, t_sanitize_redacts_unknown, t_canaries_never_leak, t_no_network, t_exit_codes_0_2_1,
              t_compaction_subagent_powershell_worktree_windows_paths, t_claude_config_dir_honoured, t_state_key_matches_bash,
              t_digest_and_boot_reads_detected, t_a15_not_satisfied_by_bootstrap_digest_alone,
              t_planning_lookups_and_task_records, t_handoffs_and_continuation, t_sumela_session_filter, t_linked_worktree_transcripts,
              t_malformed_lines_counted_not_fatal, t_hostile_text_stays_linear, t_research_model_by_hand, t_static_footprint, t_wrappers,
              t_core_manifest_matches_source):
        try:
            t()
        except Exception as e:      # a crashing case is a failure, never a skip
            import traceback
            traceback.print_exc()
            check(t.__name__ + " ran to the end", False, type(e).__name__)
    print()
    print("  %d failed" % len(FAILS) if FAILS else "  all passed")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
