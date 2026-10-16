#!/usr/bin/env python3
"""sumela-token-report: what fills the context of this install's Claude Code sessions.

SumelaOS v0.20.0+. An optional tool: standard library only, Python 3.9 or later, always run
isolated. It runs on demand only, never from a git hook, the bootstrap or CI:

    python3 -I scripts/sumela-token-report.py [options]
    bash scripts/sumela-token-report.sh [options]           (finds python3, py -3 or python)
    pwsh -File scripts/sumela-token-report.ps1 [options]    (Windows PowerShell 5.1 or pwsh 7)

It reads this install's local Claude Code transcripts, makes no network call, writes no file and
prints aggregates to stdout.

Options:
  --root <dir>          the install root (default: the nearest ancestor of the working
                        directory that holds .sumela/)
  --since <when>        only sessions whose first API request is at or after <when>
  --until <when>        ignore every transcript line stamped after <when> (the research scripts'
                        CUTOFF). <when> is YYYY-MM-DD (UTC; for --until the end of that day) or
                        an ISO 8601 date-time (UTC when it carries no offset).
  --all-sessions        also count sessions that never read or attached .sumela/sumela-prompt.md,
                        and orphan subagent threads (the research scripts counted both)
  --main-checkout-only  read the main checkout's transcript directory only, not those of
                        sessions started inside a linked worktree (the research scripts' scope)
  --json                the same report as JSON (floats to 6 decimals), plus the raw totals
  --static              no transcripts needed (another IDE): the eager set this install loads,
                        from scripts/lib/sumela-context-budgets.tsv measured on the live files

Exit codes:
  0  the report was printed
  2  degraded, with a --static hint: no Claude Code transcripts for this install (another IDE?)
     or no session in the window; or --static without the budget table
  1  could not run: one generic line on stderr and no data (usage errors too)

Discovery. Transcripts come from ${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<slug>/ for the main
checkout and every linked worktree (and the install directory inside each, for an install in a
subdirectory). A slug is the absolute path with "/", "\\", ":" and "." mapped to "-"; the
same path with every non-alphanumeric character mapped to "-" is tried too. Main threads are
<slug>/*.jsonl; subagent threads are <slug>/<session>/subagents/**/*.jsonl (journal.jsonl
excluded), with their .meta.json. A session counts as a SumelaOS session when its main thread
reads (Read, or cat/sed/head/tail/Get-Content in a shell) or attaches (an @-mention, an
instructions or nested-memory load) .sumela/sumela-prompt.md. Besides the transcripts the report
reads git's list of checkouts, sumela.baseRefs and origin/HEAD (to tell base from topic
branches), the Continue Point headings of the task records (A15) and, for --static, file sizes.

Privacy: an explicit allow-list decides what may be printed.
  * Numbers, and labels from fixed vocabularies only: tool names from a fixed list (MCP tools are
    "mcp:other", any other unknown tool "other"), subagent types and roles, model ids of the
    published shapes ("<other>" otherwise), branch classes ("base" or "topic", never a name),
    Claude Code and SumelaOS versions (digits and dots), the window's UTC date-times.
  * label_path() is the only way a path reaches the output. Framework structure survives (core
    skills, plugins and rules by name, the files the framework ships inside them, the wiki's
    special files and folders, the artifact folders); every name a consumer chose (directories,
    files, overlay skills and rules, wiki pages, worktree names, review, handoff and upgrade
    paths) collapses to a class such as "<dir>/**/*.py", "<root>/*.md", "<outside>/*.md" or
    ".sumela/<runtime>/*.md". Extensions print only from a fixed list (".<other>" otherwise).
  * Never printed: message text, prompts, thinking, code, tool inputs and outputs, file
    contents, branch names, ticket-like strings, session ids, people's names, the cwd.
  * Before anything is printed, sanitize() checks every key and string of the finished report
    against the allow-list a second, independent time and replaces whatever fails with
    "<redacted>", counted in data_quality.labels_redacted (which should always read 0).
  * Errors print one generic line (an exception's class name at most), never its message. git's
    own messages are not printed either (they name paths): the fixed line says to run git status
    in the install to see them. Git tracing is switched off for the tool's git calls.

Sections:
  data_quality     files, malformed, non-object and unprocessable lines, Claude Code versions,
                   the window (first and last request, --since, --until), excluded sessions
  session_shape    requests, peak and first-reply context per session; the share of requests,
                   context and cost at >=500K tokens; compactions per 100 requests; idle
                   re-writes (cache creation beyond context growth, after a gap over 60 minutes)
                   per active hour; the branch class each session starts on
  composition      calibrated tokens per group as a share of context tokens: tool results and
                   inputs by tool, assistant text, carried thinking, system prompt and tool
                   schemas, instructions, attachments, listings; the framework's shares
  framework_reads  framework chars read in the first 30 requests and per session; re-reads of a
                   path within one compaction segment per 100 requests; context-handoff/ chars
                   read before any trigger (a trigger: the user's handoff request, /context-handoff,
                   the agent's own Skill(context-handoff) call, a compaction); the Q17
                   read-before-acting counters: the handoff procedure read before each handoff
                   (anywhere before it and in its compaction segment, the pre-0.20 baseline's
                   definitions, and after the last trigger, which an eager boot read alone never
                   satisfies), task-records.md before the first task write; the 25 framework files
                   read most, by label
  guardrails       cache-read share of input tokens; turn inflation = requests per completed task,
                   a completed task being an implementer subagent that returned DONE or
                   DONE_WITH_CONCERNS (the one unit every window has; task close calls are
                   reported beside it, never added)
  subagents        threads, requests, context and cost shares, inherited bootstrap, first and
                   peak context; by type, by role (from the framework's prompt phrases), by model
  handoffs         detected handoffs: the template's heading, the user's handoff request (the
                   skill's trigger phrases, never a bare mention) answered by a long reply that
                   carries a fenced block or headings, a write to .sumela/.handoff/, a task
                   continue in the session's last 10 requests (signals within 15 minutes are one
                   handoff); their size; the Full share; R_continuation (the context at the first
                   edit of a session that starts from a handoff: a pasted handoff, or a
                   .sumela/.handoff/ file named or read early)
  memory_md        MEMORY.md loads in main and subagent threads, observed size, carried share; the
                   index file itself when present
  second_brain     A4 a digest among the first 10 requests; A5 whole-file Read attempts and
                   failures on the wiki special files and registers; allow_large reads; A6 calls
                   naming the boot files; A15 (main threads: in a file of a checkout, the first
                   Edit or Write on a branch whose task record has a Continue Point block for it,
                   after the last branch switch, worktree entry or compaction, comes after a
                   digest --branch, task show or checkout-block output naming that record, by
                   path or key, or a task show given its key; the bootstrap digest alone does
                   not count. A switch is git switch, a checkout of a branch, or a gitBranch change
                   nothing explained; an entry is EnterWorktree, ExitWorktree or a cd into another
                   checkout, and a worktree git worktree add just created keeps that add's block);
                   A16 a catalog, search or entry --list lookup before a brainstorming or
                   writing-plans session's first spec or plan write; A16b a catalog, search or
                   entry lookup (entry --move is a write) before the first read of a curated page
                   (a wiki page that is no special file and lies in no wiki folder); Q17 for
                   task-records.md; wiki tool calls by subcommand
  calibration      the tokens-per-char coefficients, their fit and the price multipliers
  totals           (--json only) raw sums per scope, for the differential
On v0.20.0 the second-brain counters measure the old read path (no digest, no task records), so
v0.20.1's effect is testable against them.

Reproducibility. The request accounting (one request per message.id; synthetic and zero-usage
messages dropped; context = input + cache creation + cache read tokens), the carried-context
model (an item is re-sent by every later request until the next compact_boundary; preserved
messages survive it), the delta calibration (main-thread consecutive same-segment request pairs,
ordinary least squares; image fixed at 0.25 tokens per char; 0.42 for a group the fit drops) and
the system-prompt fit (the first request of every thread) are the research scripts'
(forensics.py, baseline.py, headline.py), ported unchanged in effect. The differential: in the
flagship's main checkout, with the research run's cutoff C,
    bash scripts/sumela-token-report.sh --all-sessions --main-checkout-only --until C --json
and compare, within +-2%:
    requests, context    sections.totals.{main,subagent}.requests, .context_tokens
                         (forensics sec2["<corpus>:main"|":sub"].n_req, .sum_ctx_tokens)
    tokens per char      sections.calibration.tokens_per_char (sec2[...main].delta_calib)
    Bash, Read, thinking, system + tools, visible text (headline.py)
                         composition.all.shares_pct["tool_result:Bash"], ["tool_result:Read"],
                         ["thinking_carried"], ["system_prompt_and_tool_schemas"], ["assistant_text"]
    MCP, listings        composition.all.mcp_results_pct, .harness_listings_pct
    SumelaOS instruction composition.all.sumela_instruction_content_pct.lower_read_tool_only
    text (core reads     (headline "conservative") and .upper_with_shell_readers ("full");
    + attached)          main threads only: composition.main.sumela_instruction_content_pct
    wiki reads           composition.main.framework_reads_by_area_pct.wiki
    >=500K               session_shape.ge_500k.{main,subagent}.context_pct, .requests_pct, .cost_pct
    auto memory          memory_md.auto_memory_with_topic_files_carried_share_of_context_pct.all
    idle re-writes       session_shape.idle_rewrites.main.cost_units_gt_60m_share_pct
    inherited bootstrap  subagents.inherited_bootstrap_share_of_subagent_context_pct
    cost units           totals.{main,subagent,all}.cost_units

Seam for R1-10 (quality metrics and baselines): SECTION_BUILDERS lists the sections in order;
VALUE_OPTS and FLAG_OPTS list the options; state_dir() and write_state_file() are the only way
this tool may write, into the per-developer state directory of scripts/lib/sumela-state.sh (the
same key, computed here in Python).
"""

import collections
import hashlib
import json
import math
import os
import re
import shlex
import subprocess
import sys
from datetime import datetime, timedelta, timezone

SCHEMA = "sumela-token-report/report v1"

# ---------------------------------------------------------------------------- allow-lists
GENERIC_TOP = frozenset("src lib libs test tests docs scripts app apps packages services cmd internal pkg web api infra deploy config build tools".split())
WIKI_SPECIAL = frozenset({"_INDEX.md", "_SEARCH_INDEX.md", "_LOG.md", "_SCHEMA.md", "active-project-context.md",
                          "architecture-decisions.md", "tech-debt-and-known-issues.md"})
WIKI_DIRS = frozenset({"session-summaries", "_tasks", "_team", "archive", "summaries", "insights", "index", "_improvement-queue"})
FW_FILES = frozenset({".sumela/sumela-prompt.md", ".sumela/SKILL_REGISTRY.md", ".sumela/RULE_REGISTRY.md", "AGENTS.md", "CLAUDE.md",
                      ".sumela/local.md"})

# The files the framework ships inside its skills and plugins. Inside a core skill a path prints
# only when it is one of these; anything else a consumer put there prints as "*.<ext>".
_SKILL_FILES = {
    "skills/brainstorming": "SKILL.md idea-explore.md spec-document-reviewer-prompt.md visual-companion.md "
                            "scripts/frame-template.html scripts/helper.js scripts/server.cjs scripts/start-server.cmd "
                            "scripts/start-server.sh scripts/stop-server.cmd scripts/stop-server.sh",
    "skills/context-handoff": "SKILL.md",
    "skills/dispatching-parallel-agents": "SKILL.md",
    "skills/executing-plans": "SKILL.md",
    "skills/finishing-a-development-branch": "SKILL.md",
    "skills/init-sumela": "SKILL.md",
    "skills/onboard-sumela": "SKILL.md",
    "skills/performance-optimization": "SKILL.md",
    "skills/receiving-code-review": "SKILL.md",
    "skills/requesting-code-review": "SKILL.md code-reviewer.md gap-sweep.md ide-fallback.md lane-composition.md review-report.md "
                                     "reviewer-correctness-security.md reviewer-design-contracts.md reviewer-integration-ops.md "
                                     "self-modification-guard.md",
    "skills/secure-coding-standard": "SKILL.md agent-specific-threats.md owasp-playbook.md",
    "skills/self-improvement-curator": "SKILL.md",
    "skills/shipping-and-launch": "SKILL.md",
    "skills/subagent-driven-development": "SKILL.md code-quality-reviewer-prompt.md implementer-prompt.md spec-reviewer-prompt.md",
    "skills/systematic-debugging": "SKILL.md condition-based-waiting.md defense-in-depth.md find-polluter.cmd find-polluter.sh root-cause-tracing.md",
    "skills/test-driven-development": "SKILL.md testing-anti-patterns.md",
    "skills/using-git-worktrees": "SKILL.md",
    "skills/using-second-brain": "SKILL.md task-records.md compaction.md",
    "skills/using-superpowers": "SKILL.md",
    "skills/verification-before-completion": "SKILL.md",
    "skills/writing-plans": "SKILL.md plan-document-reviewer-prompt.md",
    "skills/writing-skills": "SKILL.md graphviz-conventions.dot persuasion-principles.md",
    "memory-plugins/graphify-code-graph": "README.md SKILL.md requirements.txt scripts/query-graph.py scripts/sync-graphify-to-obsidian.py",
    "memory-plugins/qdrant-session-memory": "README.md SKILL.md requirements.txt scripts/delete-from-qdrant.py "
                                            "scripts/ingest-code-to-qdrant.py scripts/ingest-wiki-to-qdrant.py "
                                            "scripts/lib/memory_ingest.py scripts/migrate-collections.py scripts/query-qdrant.py "
                                            "scripts/resolve-ingest-dirs.py scripts/session-ingest.py scripts/setup-qdrant.py",
}
CORE_SKILL_FILES = {k: frozenset(v.split()) for k, v in _SKILL_FILES.items()}
CORE_SKILLS = frozenset(CORE_SKILL_FILES)          # "skills/<name>" and "memory-plugins/<name>"
CORE_RULES = frozenset("""architecture_patterns.md audit_and_output.md engineering_philosophy.md
git_workflow_mandatory_review_protocol.md identity_and_behavior.md security_protocol.md self_improvement_protocol.md
operational_excellence_maintenance.md operational_excellence_maintenance.md.template backend_standards.md
frontend_standards.md mobile_standards.md domain_standards.md templates/backend_standards.md.best-practice
templates/backend_standards.md.empty templates/domain_standards.md.empty templates/frontend_standards.md.best-practice
templates/frontend_standards.md.empty templates/mobile_standards.md.best-practice templates/mobile_standards.md.empty
templates/operational_excellence_maintenance.md.best-practice templates/operational_excellence_maintenance.md.empty""".split())
EXT_OK = frozenset("""md mdx txt rst adoc json jsonl yml yaml toml ini cfg conf env properties xml html htm css scss
sass less js mjs cjs jsx ts mts cts tsx vue svelte py pyi ipynb rb go rs java kt kts scala groovy swift m mm c h cc
cpp cxx hpp cs csx csproj sln props targets fs fsx vb php pl pm lua r sql sh bash zsh fish ps1 psm1 psd1 bat cmd
gradle lock log csv tsv svg png jpg jpeg gif webp ico pdf dot template example empty proto graphql gql tf tfvars
hcl mod sum patch diff gitignore gitkeep dockerfile makefile razor cshtml xaml resx config editorconfig""".split())

TOOL_NAMES = frozenset("""Bash PowerShell Read Write Edit MultiEdit NotebookEdit NotebookRead Grep Glob LS Agent Skill
WebFetch WebSearch ToolSearch AskUserQuestion TodoWrite ExitPlanMode EnterPlanMode EnterWorktree ExitWorktree Monitor
SendMessage TaskStop TaskOutput BashOutput KillShell SubagentHandback StructuredOutput Workflow Artifact ArtifactData
ArtifactComments ListAgents ReportFindings Cron""".split())
TOOL_LABELS = TOOL_NAMES | {"mcp:other", "other"}
AGENT_TYPES = frozenset({"general-purpose", "workflow-subagent", "Explore", "Plan", "statusline-setup", "output-style-setup",
                         "claude-code-guide", "claude", "fork", "<custom>", "<none>"})
ROLES = ("implementer", "per_task_review", "final_panel", "doc_review", "explore", "workflow", "other")
MODEL_RE = re.compile(r"^(?:claude-(?:opus|sonnet|haiku|fable)-[0-9]+(?:-[0-9]+)?(?:-[0-9]{8})?"
                      r"|claude-[0-9]+(?:-[0-9]+)?-(?:opus|sonnet|haiku)(?:-[0-9]{8})?)(?:\[1m\])?\Z")
MODEL_ALIASES = frozenset({"opus", "sonnet", "haiku", "fable", "inherit", "<other>", "<none>"})
# Every allow-list pattern ends in \Z, never $: in Python, $ also matches before a final newline.
VERSION_RE = re.compile(r"^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,6}\Z")
DATETIME_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z")
SNAKE_RE = re.compile(r"^[a-z][a-z0-9_]{0,63}\Z")

# ---------------------------------------------------------------------------- path labels
def _ext(p):
    m = re.search(r"\.([a-z0-9]{1,12})$", p.lower())
    if not m:
        return "<noext>"
    return "." + m.group(1) if m.group(1) in EXT_OK else ".<other>"


_DRIVE = re.compile(r"^(?:[A-Za-z]:/|/[A-Za-z]/)")


def _under(p, r):
    """p is r or lies below it; drive-letter roots compare case-insensitively (Windows)."""
    n = len(r)
    if len(p) < n or (len(p) > n and p[n] != "/"):
        return False
    if _DRIVE.match(r):
        return p[:n].lower() == r.lower()
    return p[:n] == r


def label_path(p, roots, core_skills=CORE_SKILLS, core_rules=CORE_RULES):
    """Framework structure survives; anything a consumer named (directories, files, branches,
    tickets, domains) collapses to a class. Branch-bearing runtime paths never print."""
    if not isinstance(p, str) or not p.strip():
        return "<none>"
    p = p.strip().replace("\\", "/")
    for r in roots:
        if _under(p, r):
            p = p[len(r):].lstrip("/")
            break
    else:
        if p.startswith(("/", "~")) or re.match(r"^[A-Za-z]:/", p):
            return "<outside>/*" + _ext(p)
    p = re.sub(r"^(\./)+", "", p)
    p = re.sub(r"^(\.worktrees|worktrees|\.claude/worktrees)/[^/]+/", "", p)   # the worktree name carries the branch
    if p in FW_FILES:
        return p
    m = re.match(r"^\.sumela/(skills|memory-plugins)/([^/]+)/(.+)$", p)
    if m:
        unit = m.group(1) + "/" + m.group(2)
        if unit not in core_skills:
            return f".sumela/{m.group(1)}/<overlay>/*" + _ext(p)
        rest = m.group(3) if m.group(3) in CORE_SKILL_FILES.get(unit, ()) else "*" + _ext(p)
        return f".sumela/{m.group(1)}/{m.group(2)}/{rest}"
    if p.startswith(".sumela/rules/"):
        return p if p[len(".sumela/rules/"):] in core_rules else ".sumela/rules/<overlay>/*" + _ext(p)
    if p.startswith(".sumela/"):
        return ".sumela/<runtime>/*" + _ext(p)      # reviews/, .handoff/, .upgrade/, .wiki/: names embed branches
    if p.startswith("docs/second-brain/wiki/"):
        rest = p[len("docs/second-brain/wiki/"):]
        if rest in WIKI_SPECIAL:
            return "docs/second-brain/wiki/" + rest
        top = rest.split("/", 1)[0]
        return f"docs/second-brain/wiki/{top if top in WIKI_DIRS else '<page>'}/*" + _ext(p)
    if p.startswith("docs/second-brain/artifacts/"):
        top = p.split("/")[3] if p.count("/") >= 4 else "<file>"
        return f"docs/second-brain/artifacts/{top if top in ('specs', 'plans', 'reviews') else '<dir>'}/*" + _ext(p)
    top = p.split("/", 1)[0] if "/" in p else None
    return ("<root>/*" if top is None else (top if top in GENERIC_TOP else "<dir>") + "/**/*") + _ext(p)


# The second, independent check of a path label (sanitize): the only shapes label_path produces.
_EXT_PAT = "(?:\\.(?:" + "|".join(sorted(EXT_OK)) + ")|<noext>|\\.<other>)"
_CLASS_LABEL = re.compile(
    r"^(?:<none>"
    r"|\.sumela/(?:skills|memory-plugins)/<overlay>/\*" + _EXT_PAT +
    r"|\.sumela/rules/<overlay>/\*" + _EXT_PAT +
    r"|\.sumela/<runtime>/\*" + _EXT_PAT +
    r"|docs/second-brain/artifacts/(?:specs|plans|reviews|<dir>)/\*" + _EXT_PAT +
    r"|(?:<root>|<outside>)/\*" + _EXT_PAT +
    r"|docs/second-brain/wiki/(?:" + "|".join(re.escape(d) for d in sorted(WIKI_DIRS)) + r"|<page>)/\*" + _EXT_PAT +
    r"|(?:" + "|".join(sorted(GENERIC_TOP)) + r"|<dir>)/\*\*/\*" + _EXT_PAT +
    r")\Z")
_STAR_EXT = re.compile(r"^\*" + _EXT_PAT + r"\Z")


def valid_path_label(s):
    if not isinstance(s, str):
        return False
    if s in FW_FILES or _CLASS_LABEL.match(s):
        return True
    if s.startswith("docs/second-brain/wiki/"):
        return s[len("docs/second-brain/wiki/"):] in WIKI_SPECIAL
    if s.startswith(".sumela/rules/"):
        return s[len(".sumela/rules/"):] in CORE_RULES
    m = re.fullmatch(r"\.sumela/(skills|memory-plugins)/([^/\n]+)/([^\n]+)", s)
    if m:
        unit = m.group(1) + "/" + m.group(2)
        return unit in CORE_SKILLS and (m.group(3) in CORE_SKILL_FILES[unit] or bool(_STAR_EXT.match(m.group(3))))
    return False


# ---------------------------------------------------------------------------- research model
# Ported from the research scripts (forensics.py, baseline.py), unchanged in effect, so the
# differential acceptance can compare like with like.
PRICE = {"inp": 1.0, "cc5": 1.25, "cc1h": 2.0, "cr": 0.1, "out": 5.0}   # relative to base input price
IMG_TOKENS = 1500
DEFAULT_COEF = 0.42
IMAGE_COEF = 0.25
DEFAULT_SYS_COEF = 0.25
DELTA_GROUPS = ("tr_bash", "tr_read", "tr_other", "tu", "asst_text", "att", "user", "image")
FIT_TERMS = DELTA_GROUPS + ("think_prev", "per_item", "d_sys_chars", "intercept")
READER_VERBS = frozenset({"cat", "sed", "head", "tail", "less", "more", "bat", "nl"})
PS_READER_VERBS = frozenset({"get-content", "gc", "cat", "type"})
PS_VALUE_PARAMS = frozenset({"-totalcount", "-tail", "-head", "-first", "-last", "-encoding", "-delimiter",
                             "-readcount", "-stream", "-filter", "-include", "-exclude"})
PS_PATH_PARAMS = frozenset({"-path", "-literalpath", "-lp", "-pspath"})
TRIVIAL = frozenset({"cd", "pushd", "popd", "export", "set", "unset", "source", ".", "true", "false", ":", "sleep",
                     "echo", "printf", "for", "while", "until", "if", "fi", "done", "do", "then", "else", "elif", "esac",
                     "case", "[", "[[", "test", "local", "declare", "read", "shift", "return", "exit", "trap", "wait",
                     "mkdir", "touch", "clear", "type", "which", "}", ")", "in", "function"})
PREFIX_SKIP = frozenset({"sudo", "time", "nohup", "command", "builtin", "exec", "caffeinate", "stdbuf", "env", "noglob"})
WT_RE = re.compile(r"^(?:\.worktrees|\.claude/worktrees|worktrees)/[^/]+/")
FW_NAMES = frozenset({"AGENTS.md", "CLAUDE.md", "CLAUDE_LEGACY.md"})
SKILL_LINE_RE = re.compile(r"^- ([A-Za-z0-9:_.\-]{1,80}): ")
FRAMEWORK_SKILL_NAMES = frozenset(k.split("/", 1)[1] for k in CORE_SKILL_FILES)
LISTING_PREFIX = ("skill_listing:", "att:deferred_tools_delta", "att:agent_listing_delta", "att:mcp_instructions_delta", "instr:")


def pctl(vals, q):
    if not vals:
        return None
    v = sorted(vals)
    k = (len(v) - 1) * q
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return v[int(k)]
    return v[f] + (v[c] - v[f]) * (k - f)


def dist(vals):
    vals = [x for x in vals if x is not None]
    if not vals:
        return {"n": 0}
    return {"n": len(vals), "p50": pctl(vals, .5), "p90": pctl(vals, .9), "mean": sum(vals) / len(vals), "max": max(vals)}


def pct(a, b):
    return 100.0 * a / b if b else None


def share(k, n):
    return {"n": n, "k": k, "share_pct": pct(k, n)}


def parse_ts(s):
    if not isinstance(s, str):
        return None
    try:
        dt = datetime.fromisoformat(s.strip().replace("Z", "+00:00"))
        dt = dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)            # overflows here for 0001-01-01+05:00, never later
    except (ValueError, OverflowError):
        return None


def iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if dt else None


def ext_of(p):
    b = os.path.basename(p)
    if "." in b[1:]:
        e = b.rsplit(".", 1)[1].lower()
        if re.match(r"^[a-z0-9]{1,8}$", e):
            return "." + e
    return "<noext>"


def _int(v):
    """A token count: a non-negative number below 10**13, else 0 (never an overflow later)."""
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return 0
    return int(v) if 0 <= v < 1e13 else 0             # False for NaN; infinities and huge values fail too


def fw_bucket(p, root, home, cfg_projects):
    """The research scripts' path classes, for counting only: the label returned here is internal
    and never printed. Classes: fw, fw-nested, fw-user, automem, spill, app, tmp, claude-home,
    other-project, outside, none."""
    if not isinstance(p, str) or not p.strip():
        return ("<none>", "none")
    p = p.strip().replace("\\", "/")
    if p.startswith("~/"):
        p = home + p[1:]
    if ("/.claude/projects/" in p or p.startswith(cfg_projects)) and "/memory/" in p:
        return ("claude-auto-memory/" + ("MEMORY.md" if p.endswith("/MEMORY.md") else "*" + ext_of(p)), "automem")
    if ("/.claude/projects/" in p or p.startswith(cfg_projects)) and "/tool-results/" in p:
        return ("spill", "spill")
    if p == home + "/.claude/CLAUDE.md":
        return ("~/.claude/CLAUDE.md", "fw-user")
    for marker in (".sumela/", "docs/second-brain/"):
        i = p.find(marker)
        if i >= 0 and (i == 0 or p[i - 1] == "/"):
            return (re.sub(r"[^A-Za-z0-9._/\-]", "_", p[i:])[:160], "fw")
    rel = None
    if root and _under(p, root):
        rel = p[len(root):].lstrip("/")
    elif not p.startswith("/") and not p.startswith("..") and not re.match(r"^[A-Za-z]:/", p):
        rel = p[2:] if p.startswith("./") else p
    if rel is not None:
        rel = WT_RE.sub("", rel)
        for marker in (".sumela/", "docs/second-brain/"):
            if rel.startswith(marker):
                return (re.sub(r"[^A-Za-z0-9._/\-]", "_", rel)[:160], "fw")
        b = os.path.basename(rel)
        if b in FW_NAMES:
            if "/" not in rel:
                return (b, "fw")
            return ("nested/**/" + b, "fw-nested")
        return ("<app>", "app")
    if p.startswith(("/tmp/", "/private/tmp/", "/var/folders/", "/private/var/")):
        return ("<tmp>", "tmp")
    if p.startswith(home + "/.claude/"):
        return ("<claude-home>", "claude-home")
    if p.startswith(home + "/Projects/"):
        return ("<other-project>", "other-project")
    return ("<outside>", "outside")


def fw_like(cls):
    return cls in ("fw", "fw-nested", "automem", "fw-user")


def tool_group(name):
    if not isinstance(name, str):
        return "other"
    if name.startswith("mcp__"):
        return "mcp:other"
    if name in ("Agent", "Task"):
        return "Agent"
    if name.startswith("Cron"):
        return "Cron"
    return name if name in TOOL_NAMES else "other"


def delta_group(cat):
    if cat == "tr:Bash":
        return "tr_bash"
    if cat == "tr:Read":
        return "tr_read"
    if cat.startswith("tr:"):
        return "tr_other"
    if cat.startswith("tu:"):
        return "tu"
    if cat == "asst_text":
        return "asst_text"
    if cat == "image":
        return "image"
    if cat.startswith(("att:", "instr:", "skill_listing:", "attfile:", "nested_memory:", "hook_ctx", "queued:")):
        return "att"
    return "user"


COMP_FIXED = frozenset({"assistant_text", "thinking_carried", "system_prompt_and_tool_schemas", "instructions:framework",
                        "instructions:auto_memory_index", "instructions:auto_memory_topic", "instructions:user_global",
                        "instructions:wrapper", "instructions:other", "attached_file:framework", "attached_file:other",
                        "nested_memory:framework", "nested_memory:other", "skill_listing:sumela", "skill_listing:builtin",
                        "skill_listing:anthropic-skills", "skill_listing:header", "skill_listing:other",
                        "harness_listing:deferred_tools", "harness_listing:agents", "harness_listing:mcp_instructions",
                        "attachment:other", "user_prompt", "task_notification", "peer_message", "skill_body", "slash_cmd",
                        "local_cmd_out", "user_meta", "scheduled_prompt", "compact_summary", "image", "hook_context",
                        "queued_other", "other"})


def comp_group(cat):
    if cat.startswith("tr:"):
        return "tool_result:" + cat[3:]
    if cat.startswith("tu:"):
        return "tool_input:" + cat[3:]
    if cat == "asst_text":
        return "assistant_text"
    if cat.startswith("instr:"):
        lab = cat[6:]
        if "claude-auto-memory/MEMORY.md" in lab:
            return "instructions:auto_memory_index"
        if "claude-auto-memory" in lab:
            return "instructions:auto_memory_topic"
        if lab == "~/.claude/CLAUDE.md":
            return "instructions:user_global"
        if lab == "<wrapper>":
            return "instructions:wrapper"
        if lab.startswith("other("):
            return "instructions:other"
        return "instructions:framework"
    if cat.startswith("attfile:"):
        return "attached_file:framework" if not cat[8:].startswith("<") else "attached_file:other"
    if cat.startswith("nested_memory:"):
        return "nested_memory:framework" if not cat[14:].startswith("<") else "nested_memory:other"
    if cat.startswith("skill_listing:"):
        return cat
    if cat == "att:deferred_tools_delta":
        return "harness_listing:deferred_tools"
    if cat == "att:agent_listing_delta":
        return "harness_listing:agents"
    if cat == "att:mcp_instructions_delta":
        return "harness_listing:mcp_instructions"
    if cat.startswith("att:"):
        return "attachment:other"
    if cat in ("user_prompt", "queued:user-prompt"):
        return "user_prompt"
    if cat in ("task_notification", "queued:task-notification"):
        return "task_notification"
    if cat in ("peer_message", "queued:peer-message"):
        return "peer_message"
    if cat in ("skill_body", "slash_cmd", "local_cmd_out", "user_meta", "scheduled_prompt", "compact_summary", "image"):
        return cat
    if cat == "hook_ctx":
        return "hook_context"
    if cat == "queued:other":
        return "queued_other"
    return "other"


def classify_user_text(s, is_meta, origin_kind=None):
    if not isinstance(s, str):
        return "user_prompt"
    if origin_kind == "peer":
        return "peer_message"
    if origin_kind == "scheduled":
        return "scheduled_prompt"
    if "Base directory for this skill" in s[:400]:
        return "skill_body"
    if "<command-name>" in s[:300] or "<command-message>" in s[:300]:
        return "slash_cmd"
    if "<local-command-stdout>" in s[:300] or "<local-command-caveat>" in s[:300]:
        return "local_cmd_out"
    if "<task-notification>" in s[:200]:
        return "task_notification"
    if is_meta:
        return "user_meta"
    return "user_prompt"


def tr_text(content):
    """tool_result content -> (text, n_images)"""
    if isinstance(content, str):
        return content, 0
    if isinstance(content, list):
        parts, ni = [], 0
        for x in content:
            if not isinstance(x, dict):
                continue
            if x.get("type") == "text":
                t = x.get("text")
                parts.append(t if isinstance(t, str) else "")
            elif x.get("type") == "image":
                ni += 1
        return "".join(parts), ni
    return "", 0


def ols_multi(rows, names):
    """rows: list of (x_vector, y). Returns {name: coef, "_r2", "_n"}, or None when singular.
    Columns that are (almost) always zero are dropped (forensics.py, unchanged)."""
    if not rows:
        return None
    keep = [i for i in range(len(names)) if sum(1 for x, _ in rows if x[i]) >= 30 or names[i] == "intercept"]
    rows = [([x[i] for i in keep], y) for x, y in rows]
    names = [names[i] for i in keep]
    k = len(names)
    A = [[0.0] * k for _ in range(k)]
    B = [0.0] * k
    for x, y in rows:
        for i in range(k):
            xi = x[i]
            if xi == 0:
                continue
            B[i] += xi * y
            Ai = A[i]
            for j in range(k):
                Ai[j] += xi * x[j]
    M = [A[i][:] + [B[i]] for i in range(k)]
    for i in range(k):
        piv = max(range(i, k), key=lambda r: abs(M[r][i]))
        M[i], M[piv] = M[piv], M[i]
        if abs(M[i][i]) < 1e-9:
            return None
        for r in range(k):
            if r != i:
                f = M[r][i] / M[i][i]
                if f:
                    for c in range(i, k + 1):
                        M[r][c] -= f * M[i][c]
    coef = [M[i][k] / M[i][i] for i in range(k)]
    ys = [y for _, y in rows]
    mean = sum(ys) / len(ys)
    ss_tot = sum((y - mean) ** 2 for y in ys)
    ss_res = sum((y - sum(c * xi for c, xi in zip(coef, x))) ** 2 for x, y in rows)
    out = dict(zip(names, coef))
    out["_r2"] = 1 - ss_res / ss_tot if ss_tot else None
    out["_n"] = len(rows)
    return out


# ---------------------------------------------------------------------------- shell commands
HEREDOC_RE = re.compile(r"<<-?[ \t]{0,8}(['\"]?)([A-Za-z0-9_]+)\1")


def split_shell(cmd):
    """Split a shell command into segments; each segment is a list of pipeline stage strings.
    Quote-, $()-, backtick- and heredoc-aware (heredoc bodies are skipped). forensics.py."""
    segs, cur, buf = [], [], []
    i, n = 0, len(cmd)
    q = None
    depth = 0
    heredocs = []

    def flush_stage():
        s = "".join(buf).strip()
        buf.clear()
        if s:
            cur.append(s)

    def flush_seg():
        flush_stage()
        if cur:
            segs.append(list(cur))
        cur.clear()
    while i < n:
        c = cmd[i]
        if q:
            buf.append(c)
            if c == "\\" and q == '"' and i + 1 < n:
                buf.append(cmd[i + 1])
                i += 2
                continue
            if c == q:
                q = None
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            if cmd[i + 1] == "\n":
                i += 2
                buf.append(" ")
                continue
            buf.append(c)
            buf.append(cmd[i + 1])
            i += 2
            continue
        if c in ('"', "'"):
            q = c
            buf.append(c)
            i += 1
            continue
        if c == "`":
            j = cmd.find("`", i + 1)
            j = n - 1 if j < 0 else j
            buf.append(cmd[i:j + 1])
            i = j + 1
            continue
        if c == "$" and i + 1 < n and cmd[i + 1] == "(":
            depth += 1
            buf.append("$(")
            i += 2
            continue
        if depth > 0:
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            buf.append(c)
            i += 1
            continue
        if c == "#" and (not buf or buf[-1] in (" ", "\t")) and not "".join(buf).strip().endswith("$"):
            j = cmd.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "<" and cmd.startswith("<<", i) and not cmd.startswith("<<<", i):
            m = HEREDOC_RE.match(cmd, i)
            if m:
                heredocs.append(m.group(2))
                buf.append(cmd[i:m.end()])
                i = m.end()
                continue
        if c == "\n":
            flush_seg()
            i += 1
            while heredocs:
                d = heredocs.pop(0)
                while i < n:
                    j = cmd.find("\n", i)
                    line = cmd[i:] if j < 0 else cmd[i:j]
                    i = n if j < 0 else j + 1
                    if line.strip() == d:
                        break
            continue
        if cmd.startswith("&&", i) or cmd.startswith("||", i):
            flush_seg()
            i += 2
            continue
        if c == ";":
            flush_seg()
            i += 1
            continue
        if c == "|":
            flush_stage()
            i += 2 if cmd.startswith("|&", i) else 1
            continue
        if c == "&":
            prev = buf[-1] if buf else ""
            if prev in (">", "<") or cmd.startswith("&>", i):
                buf.append(c)
                i += 1
                continue
            flush_seg()
            i += 1
            continue
        buf.append(c)
        i += 1
    flush_seg()
    return segs


def toks_of(stage):
    try:
        t = shlex.split(stage, posix=True)
    except ValueError:
        t = stage.split()
    out = []
    for x in t:
        while x.startswith("(") or x.startswith("{"):
            x = x[1:]
        if x:
            out.append(x)
    return out


def strip_prefixes(toks):
    i = 0
    while i < len(toks):
        t = toks[i]
        if t in ("!", "then", "do", "else", "elif", "{", "(", "(("):
            i += 1
            continue
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            depth = t.count("$(") + t.count("`") - t.count(")")
            i += 1
            while depth > 0 and i < len(toks):
                depth += toks[i].count("$(") + toks[i].count("(") - toks[i].count(")") - (1 if toks[i].endswith("`") else 0)
                i += 1
            continue
        if t in ("timeout", "gtimeout"):
            i += 1
            while i < len(toks) and toks[i].startswith("-"):
                i += 2 if toks[i] in ("-s", "-k", "--signal", "--kill-after") else 1
            if i < len(toks) and re.match(r"^\d+(\.\d+)?[smhd]?$", toks[i]):
                i += 1
            continue
        if t == "nice":
            i += 1
            if i < len(toks) and toks[i] == "-n":
                i += 2
            continue
        if t in PREFIX_SKIP:
            i += 1
            while i < len(toks) and (toks[i].startswith("-") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[i])):
                i += 1
            continue
        break
    return toks[i:]


def read_paths(verb0, toks):
    """Files a reader verb (cat, sed, head, tail, less, more, bat, nl) prints. forensics.py."""
    args = toks[1:]
    res = []
    skip_next = False
    clean = []
    for a in args:
        if skip_next:
            skip_next = False
            continue
        if a in (">", ">>", "<", "2>", "2>>", "&>"):
            skip_next = True
            continue
        if a.startswith(("<", ">", "2>", "&>")):
            continue
        clean.append(a)
    args = clean
    if verb0 == "sed":
        script_seen = any(a in ("-e", "-f") or a.startswith("--expression") for a in args)
        j = 0
        while j < len(args):
            a = args[j]
            if a in ("-e", "-f"):
                j += 2
                continue
            if a.startswith("-"):
                j += 1
                continue
            if not script_seen:
                script_seen = True
                j += 1
                continue
            res.append(a)
            j += 1
        return res
    if verb0 in ("head", "tail"):
        j = 0
        while j < len(args):
            a = args[j]
            if a in ("-n", "-c"):
                j += 2
                continue
            if a.startswith("-") or re.match(r"^\+?\d+$", a):
                j += 1
                continue
            res.append(a)
            j += 1
        return res
    if verb0 in ("cat", "less", "more", "bat", "nl"):
        return [a for a in args if not a.startswith("-")]
    return []


def split_ps(cmd):
    """The stages of a PowerShell command line: split on unquoted ; | newline && ||."""
    stages, buf, q = [], [], None
    i, n = 0, len(cmd)
    while i < n:
        c = cmd[i]
        if q:
            buf.append(c)
            if c == q:
                q = None
            i += 1
            continue
        if c in ("'", '"'):
            q = c
            buf.append(c)
        elif c == "`" and i + 1 < n:
            buf.append(cmd[i:i + 2])
            i += 2
            continue
        elif c in ";|\n\r" or cmd.startswith("&&", i):
            s = "".join(buf).strip()
            if s:
                stages.append(s)
            buf = []
            if cmd.startswith(("&&", "||"), i):
                i += 1
        else:
            buf.append(c)
        i += 1
    s = "".join(buf).strip()
    if s:
        stages.append(s)
    return stages


def ps_toks(stage):
    try:
        t = shlex.split(stage, posix=False)
    except ValueError:
        t = stage.split()
    return [x[1:-1] if len(x) >= 2 and x[0] == x[-1] and x[0] in "\"'" else x for x in t]


def ps_read_paths(toks):
    res = []
    j = 1
    while j < len(toks):
        a = toks[j]
        al = a.lower()
        if al in PS_PATH_PARAMS:
            if j + 1 < len(toks):
                res.extend(x for x in toks[j + 1].split(",") if x)
            j += 2
            continue
        if a.startswith("-"):
            j += 2 if al in PS_VALUE_PARAMS else 1
            continue
        res.extend(x for x in a.split(",") if x)
        j += 1
    return res


WIKI_TOOL_RE = re.compile(r"(?:^|/)sumela-wiki(?:\.sh|\.ps1)?$")
LAUNCHERS = frozenset({"bash", "sh", "zsh", "pwsh", "pwsh.exe", "powershell", "powershell.exe", "&", "."})
WIKI_VALUE_OPTS = frozenset({"-C", "--task", "--worktree", "--branch", "--by", "--home", "--spec", "--plan", "--from",
                             "--except", "--status", "--owner", "--type", "--limit", "--since", "--before", "--match", "--grep"})
TASK_READS = frozenset({"show", "list"})


def stages_of(cmd, shell):
    """Token lists of every command stage, prefixes stripped."""
    out = []
    if not isinstance(cmd, str) or not cmd.strip():
        return out
    if shell == "ps":
        for st in split_ps(cmd):
            t = ps_toks(st)
            if t:
                out.append(t)
        return out
    try:
        segs = split_shell(cmd)
    except Exception:
        segs = [[cmd]]
    for seg in segs:
        for stg in seg:
            t = strip_prefixes(toks_of(stg))
            if t:
                out.append(t)
    return out


def wiki_flags(stage_list):
    """What sumela-wiki calls a command makes: digest, digest_branch, catalog, search, entry,
    entry_list, task_show, task_list, task_write, task_continue, task_close, team, lint, bases."""
    flags = set()
    for toks in stage_list:
        if not toks:
            continue
        first = toks[0].replace("\\", "/")
        if WIKI_TOOL_RE.search(first):
            idx = 0
        elif os.path.basename(first).lower() in LAUNCHERS:       # bash, pwsh -File, & "<path>", . <path>
            idx = next((i for i in range(1, min(len(toks), 8)) if WIKI_TOOL_RE.search(toks[i].replace("\\", "/"))), None)
        else:
            idx = None                                          # grep 'sumela-wiki digest' is no call
        if idx is None:
            continue
        args = [a for a in toks[idx + 1:]]
        j = 0
        while j < len(args) and args[j].startswith("-"):
            j += 2 if args[j] in WIKI_VALUE_OPTS else 1
        if j >= len(args):
            continue
        sub, rest = args[j], args[j + 1:]
        if sub == "digest":
            flags.add("digest_branch" if "--branch" in rest else "digest")
        elif sub in ("catalog", "search"):
            flags.add(sub)
        elif sub == "entry":
            flags.add("entry_move" if "--move" in rest else ("entry_list" if "--list" in rest else "entry"))
        elif sub == "task":
            r = 0
            while r < len(rest) and rest[r].startswith("-"):
                r += 2 if rest[r] in WIKI_VALUE_OPTS else 1
            ts = rest[r] if r < len(rest) else ""
            if ts == "show":
                flags.add("task_show")
            elif ts in TASK_READS or not ts:
                flags.add("task_list")
            else:
                flags.add("task_write")
                if ts == "continue":
                    flags.add("task_continue")
                if ts == "close" and "--abandoned" not in rest:
                    flags.add("task_close")
        elif sub in ("team", "lint", "bases"):
            flags.add(sub)
    return flags


def git_moves(stage_list, branch_names=frozenset()):
    """({'switch', 'worktree'}, [paths]): 'switch' for a git switch, or a git checkout that
    surely moves this work tree to a branch (-b, -B, --detach, --orphan, '-', or a known branch
    name; never a path checkout); 'worktree' for git worktree add, with the paths it creates."""
    kinds, added = set(), []
    for toks in stage_list:
        if not toks or os.path.basename(toks[0].replace("\\", "/")).lower() not in ("git", "git.exe"):
            continue
        j, elsewhere = 1, False
        while j < len(toks) and toks[j].startswith("-"):
            if toks[j] in ("-C", "--git-dir", "--work-tree"):
                elsewhere = True
            j += 2 if toks[j] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace") else 1
        if j >= len(toks):
            continue
        sub, rest = toks[j], toks[j + 1:]
        if sub == "worktree" and rest[:1] == ["add"]:
            kinds.add("worktree")
            k = 1
            while k < len(rest):
                if rest[k] in ("-b", "-B", "--reason"):
                    k += 2
                elif rest[k].startswith("-"):
                    k += 1
                else:
                    added.append(rest[k])
                    break
        elif elsewhere:
            continue                            # a checkout in another work tree does not move this one
        elif sub == "switch" and not any(t in ("-h", "--help") for t in rest):
            kinds.add("switch")
        elif sub == "checkout" and "--" not in rest and not any(t in ("-p", "--patch") for t in rest):
            names = [t for t in rest if not t.startswith("-")]
            if (any(t in ("-b", "-B", "--detach", "--orphan") for t in rest) or rest == ["-"]
                    or (len(names) == 1 and names[0] in branch_names)):
                kinds.add("switch")
    return kinds, added


def cd_targets(stage_list):
    """The directories cd, pushd and Set-Location move to."""
    out = []
    for toks in stage_list:
        if len(toks) >= 2 and toks[0].lower() in ("cd", "pushd", "set-location", "sl", "chdir"):
            t = [a for a in toks[1:] if not a.startswith("-")]
            if t:
                out.append(t[-1])
    return out


def task_show_keys(stage_list):
    """The record keys sumela-wiki task show was given (--task <key> or a positional key)."""
    keys = []
    for toks in stage_list:
        if "task" not in toks or "show" not in toks:
            continue
        for i, t in enumerate(toks):
            if t == "--task" and i + 1 < len(toks):
                keys.append(toks[i + 1])
        i = toks.index("show")
        rest = [a for a in toks[i + 1:] if not a.startswith("-")]
        if rest and re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}-", rest[0]):
            keys.append(rest[0])
    return [k for k in keys if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,120}", k)]


def record_mentions(text, env):
    """The task records a tool output names, by path (_tasks/<key>.md) or by key."""
    found = set(TASK_REC_RE.findall(text))
    for key in env.record_keys:
        if key in text and re.search(r"(?<![A-Za-z0-9._-])" + re.escape(key) + r"(?![A-Za-z0-9_-])", text):
            found.add(key + ".md")
    return found


# ---------------------------------------------------------------------------- second-brain text
# Bounded on purpose: transcript text is arbitrary, and an unbounded \s* next to $ or ^ backtracks.
HANDOFF_HEADING = re.compile(r"(?m)^#{1,3}[ \t]{0,8}Session Handoff\b")
COMPLETENESS = re.compile(r"(?m)^#{2,4}[ \t]{0,8}Handoff Completeness[ \t]{0,8}\r?\n(?:[ \t]{0,8}\r?\n){0,3}[ \t>*_\"'`-]{0,20}(\w+)")
# A request for a handoff, in the skill's own trigger phrases (any language: English and Turkish
# here), never a bare mention ("a new session cookie" is no request).
HANDOFF_PHRASE = re.compile(
    r"(?i)\b(?:prepare|write|create|make|generate|give|produce|draft|need|want|do|start)\b[^.\n?!]{0,40}?\bhand[\s-]?off\b"
    r"|\bhand[\s-]?off\b[^.\n?!]{0,25}?\b(?:prompt|please|now)\b"
    r"|\bcontext[\s-]hand[\s-]?off\b"
    r"|\b(?:continue|start|move|switch|resume)\b[^.\n?!]{0,20}?\b(?:new|fresh|next)\s+session\b"
    r"|\bnew\s+session\b[^.\n?!]{0,20}?\b(?:prompt|hand[\s-]?off)\b"
    r"|\bis\s+(?:the\s+)?context\s+(?:window\s+)?full\b"
    r"|\bhand[\s-]?off\b[^.\n?!]{0,20}?\b(?:haz|yaz|ver|olu)"
    r"|\byeni[ \t]{1,3}(?:bir[ \t]{1,3})?(?:oturum|session)\w{0,8}[ \t]{1,3}(?:\w{1,12}[ \t]{1,3})?(?:devam|ge\u00e7)"
    r"|\bdevret\b")
HANDOFF_SHAPE = re.compile(r"(?m)^[ \t]{0,8}(?:```|~~~|#{1,4}[ \t])")     # a reply that carries a block or headings
HANDOFF_FILE_RE = re.compile(r"(?:^|[\s/\"'=])\.sumela[/\\]\.handoff[/\\]")
REDIRECT_HANDOFF = re.compile(r">{1,2}[ \t]{0,4}[\"']?[^\s;&|]{0,300}?\.sumela[/\\]\.handoff[/\\]")
TASK_REC_RE = re.compile(r"_tasks[/\\]([A-Za-z0-9][A-Za-z0-9._-]{0,120}\.md)")
SKILL_BASE_RE = re.compile(r"Base directory for this skill:\s*(\S+)")
STATUS_RE = re.compile(r"\bStatus:[ \t]{0,8}[*_`]{0,4}[ \t]{0,8}(DONE_WITH_CONCERNS|DONE|BLOCKED|NEEDS_CONTEXT)\b")
BOOT_NAMES = ("_INDEX.md", "active-project-context.md")
NAME_RE = {
    "_INDEX.md": re.compile(r"(?<![A-Za-z0-9_])_INDEX\.md"),
    "active-project-context.md": re.compile(r"active-project-context\.md"),
}
EDIT_TOOLS = frozenset({"Edit", "Write", "MultiEdit", "NotebookEdit"})
ROLE_RULES = (
    ("final_panel", ("expert, strict code review agent", "requesting-code-review/code-reviewer")),
    ("per_task_review", ("spec compliance reviewer", "spec-reviewer-prompt", "code quality reviewer", "code-quality-reviewer-prompt")),
    ("final_panel", ("of a parallel code-review panel", "lane 1 of a parallel", "lane 2 of a parallel", "lane 3 of a parallel",
                     "reviewer-correctness-security", "reviewer-design-contracts", "reviewer-integration-ops", "lane-composition")),
    ("doc_review", ("spec document reviewer", "spec-document-reviewer-prompt", "plan document reviewer", "plan-document-reviewer-prompt")),
    ("implementer", ("implementer subagent", "you are the implementer", "implementer-prompt")),
)


def classify_role(first_prompt, agent_type):
    """A subagent's role from the framework's own prompt-template phrases. The prompt is read in
    memory and dropped; only the role label is kept."""
    s = (first_prompt or "").lower()
    for role, phrases in ROLE_RULES:
        if any(p in s for p in phrases):
            return role
    if agent_type == "Explore":
        return "explore"
    if agent_type == "workflow-subagent":
        return "workflow"
    return "other"


def handoff_full(text):
    m = COMPLETENESS.search(text)
    return bool(m) and m.group(1).lower() == "full"


# ---------------------------------------------------------------------------- threads
class Thread:
    def __init__(self, kind, sid, path, root):
        self.kind, self.sid, self.path, self.root = kind, sid, path, root
        self.reqs = []
        self.req_by_id = {}
        self.all_items = []        # [cat, chars, tag, add_k, uuid, mult]
        self.seg = []
        self.seg_chars = 0
        self.k = 0
        self.peak_ctx = -1
        self.compactions = []
        self.ts = []
        self.tool_uses = {}
        self.sys_snapshots = []
        self.read_events = []      # (internal label, cls, chars, how, k)
        self.versions = collections.Counter()
        self.models = collections.Counter()
        self.misc = collections.Counter()
        self.lines = 0
        self.cum_think = 0
        self.uuids = set()
        self.tools_chars = None
        self.sp_chars = None
        self.since = collections.Counter()
        self.meta = {}
        self.x = None

    def add(self, cat, chars, tag=None, uuid=None):
        if chars <= 0:
            return None
        it = [cat, chars, tag, self.k, uuid, 0]
        self.seg.append(it)
        self.all_items.append(it)
        self.seg_chars += chars
        self.since[delta_group(cat)] += chars
        self.since["_n_items"] += 1
        return it

    def close_seg(self, preserved=frozenset()):
        keep = []
        for it in self.seg:
            it[5] += self.k - it[3]
            if it[4] in preserved:
                it[3] = self.k
                keep.append(it)
        self.seg = keep
        self.seg_chars = 0
        self.cum_think = 0
        self.since = collections.Counter()
        self.since["_reset"] = 1
        for it in keep:
            self.seg_chars += it[1]


class Extras:
    """Per-thread state for the counters the research scripts did not have. Holds text only
    transiently (a subagent's first prompt, until its role is classified)."""

    def __init__(self, th, env):
        self.th, self.env = th, env
        self.c = collections.Counter()
        self.seq = 0
        self.ts = None
        self.seen_path, self.seen_exact = set(), set()
        self.sumela = False
        self.first_prompt = None
        self.status = None
        self.start_branch = self.last_branch = None
        self.switched = False
        self.evidence, self.checked = set(), set()
        self.a15_qual, self.a15_ok = False, True
        self.tr_read = False
        self.task_write_first = None
        self.lookup_seen = False
        self.planning = False
        self.first_artifact_write = None
        self.first_curated = None
        self.digest_first10 = False
        self.signals = []
        self.task_continues = []
        self.proc_seq = self.proc_seg = None
        self.pending_phrase = None
        self.trigger = False
        self.ch_total = self.ch_before = 0
        self.first_prompt_seen = False
        self.continuation = False
        self.first_edit_ctx = None
        self.boot_calls = 0
        self.a5_failed = False
        self.memory_loads = 0
        self.memory_sizes = []
        self.cwd = None
        self.cur_ck = None              # the checkout the session's working directory is in
        self.pending_confirm = False    # an explicit switch or entry the gitBranch or cwd has not shown yet
        self.added_wt = set()           # worktrees git worktree add created since the last boundary
        self.trigger_seq = None
        self.plan_lookup_seen = False

    # -- boundaries (branch switch, worktree entry, compaction) for A15
    def boundary(self):
        self.evidence = set()
        self.checked = set()
        self.added_wt = set()

    def transition(self, explicit):
        """A branch switch or worktree entry. An explicit one (a tool call) wipes the evidence at
        once; the gitBranch or cwd change that follows only confirms it, so the checkout block it
        printed survives. A change nothing explained wipes it too."""
        if explicit:
            self.boundary()
            self.pending_confirm = True
        elif not self.pending_confirm:
            self.boundary()

    def enter(self, ck, explicit):
        """The session's working directory moved into checkout ck (None: outside every checkout)."""
        if ck is None or ck == self.cur_ck:
            return
        prev, self.cur_ck = self.cur_ck, ck
        if prev is None and not explicit:
            return                              # the session's first working directory
        if ck in self.added_wt:
            self.pending_confirm = True         # its git worktree add printed the block at the entry (R1-22b)
            return
        self.transition(explicit)

    def set_trigger(self):
        self.trigger = True
        self.trigger_seq = self.seq

    def procedure_read(self, chars):
        self.ch_total += chars
        if not self.trigger:
            self.ch_before += chars
        self.proc_seq, self.proc_seg = self.seq, len(self.th.compactions)

    def signal(self, kind, size, full=False):
        before = self.proc_seq is not None
        same = before and self.proc_seg == len(self.th.compactions)
        after = before and self.trigger_seq is not None and self.proc_seq >= self.trigger_seq
        self.signals.append((self.seq, self.ts, kind, size, full, before, same, after))

    def skill(self, name):
        if not isinstance(name, str):
            return
        name = name.strip().split(":")[-1]
        if name in ("brainstorming", "writing-plans"):
            self.planning = True
        if name == "context-handoff":
            if self.th.kind == "main":
                self.set_trigger()              # the agent decided a trigger condition holds
            self.procedure_read(0)

    def edit(self, fp, inp):
        th, env = self.th, self.env
        lab = label_path(fp, env.roots)
        if lab.startswith(("docs/second-brain/artifacts/specs/", "docs/second-brain/artifacts/plans/")) and self.first_artifact_write is None:
            self.first_artifact_write = self.plan_lookup_seen
        texts = []
        for key in ("content", "new_string", "new_source"):
            v = inp.get(key)
            if isinstance(v, str):
                texts.append(v)
        for e in inp.get("edits") if isinstance(inp.get("edits"), list) else []:
            if isinstance(e, dict) and isinstance(e.get("new_string"), str):
                texts.append(e["new_string"])
        body = "\n".join(texts)
        rawp = fp.replace("\\", "/") if isinstance(fp, str) else ""
        if th.kind == "main":
            if "/.sumela/.handoff/" in "/" + rawp:
                self.signal("handoff_file", len(body) or None)
            if HANDOFF_HEADING.search(body) and "{DATE}" not in body:
                self.signal("template", len(body), handoff_full(body))
            absolute = rawp.startswith(("/", "~")) or re.match(r"^[A-Za-z]:/", rawp) is not None
            if absolute and not any(_under(rawp, r) for r in env.roots):
                return                          # a file outside every checkout (a temp file, auto memory) is no edit on a branch
            if self.first_edit_ctx is None and th.reqs:
                self.first_edit_ctx = th.reqs[-1]["ctx"]
            self.pending_confirm = False
            branch = env.branch_of(rawp) or self.last_branch
            if branch and branch not in self.checked:
                self.checked.add(branch)
                recs = env.records.get(branch)
                if recs:
                    self.a15_qual = True
                    if not (recs & self.evidence):
                        self.a15_ok = False

    def tool_use(self, name, grp, inp, info):
        th = self.th
        c = self.c
        if grp in ("Bash", "PowerShell"):
            cmd = inp.get("command")
            cmd = cmd if isinstance(cmd, str) else ""
            stages = stages_of(cmd, "ps" if grp == "PowerShell" else "sh")
            flags = wiki_flags(stages)
            moves, added = git_moves(stages, self.env.branch_names)
            info["evidence_cmd"] = bool(flags & {"digest_branch", "task_show"} or moves)
            if "task_show" in flags:
                info["task_keys"] = task_show_keys(stages)
            for f in flags:
                c["wiki_call|" + f] += 1
            if th.kind == "main":
                if "digest" in flags or "digest_branch" in flags:
                    if th.k <= 10:
                        self.digest_first10 = True
                if flags & {"catalog", "search", "entry", "entry_list"}:
                    self.lookup_seen = True
                if flags & {"catalog", "search", "entry_list"}:
                    self.plan_lookup_seen = True
                if "task_write" in flags and self.task_write_first is None:
                    self.task_write_first = self.tr_read
                if "task_close" in flags:
                    c["task_close"] += 1
                if "task_continue" in flags:
                    before = self.proc_seq is not None
                    after = before and self.trigger_seq is not None and self.proc_seq >= self.trigger_seq
                    self.task_continues.append((self.seq, self.ts, th.k, before,
                                                before and self.proc_seg == len(th.compactions), after))
                for path in added:
                    self.added_wt.add(self.checkout_key(path))
                if "switch" in moves:
                    self.transition(True)
                for target in cd_targets(stages):
                    self.enter(self.checkout_key(target), True)
                if HANDOFF_HEADING.search(cmd) and "{DATE}" not in cmd:
                    self.signal("template", len(cmd), handoff_full(cmd))
                if ".handoff" in cmd and REDIRECT_HANDOFF.search(cmd):
                    self.signal("handoff_file", None)
            self.names(cmd)
        elif grp == "Read":
            fp = inp.get("file_path")
            self.names(fp)
            if inp.get("allow_large"):
                c["allow_large"] += 1
                if isinstance(fp, str) and label_path(fp, self.env.roots).startswith("docs/second-brain/wiki/"):
                    c["allow_large_wiki"] += 1
        elif grp in ("Grep", "Glob"):
            self.names(" ".join(str(inp.get(k) or "") for k in ("path", "glob", "pattern")))
        elif grp in EDIT_TOOLS:
            fp = inp.get("file_path") or inp.get("notebook_path")
            self.edit(fp if isinstance(fp, str) else "", inp)
        elif grp == "Skill":
            self.skill(inp.get("skill") or inp.get("command"))
        elif name in ("EnterWorktree", "ExitWorktree") and th.kind == "main":
            self.transition(True)
            info["evidence_cmd"] = name == "EnterWorktree"     # its result may carry the checkout block

    def checkout_key(self, path):
        """The checkout a cd target or a new worktree path lies in; relative paths resolve
        against the session's working directory."""
        t = path.replace("\\", "/")
        if not (t.startswith("/") or re.match(r"^[A-Za-z]:/", t)) and self.cwd:
            t = self.cwd.replace("\\", "/").rstrip("/") + "/" + t
        parts = []
        for seg in t.split("/"):
            if seg == "..":
                if parts:
                    parts.pop()
            elif seg and seg != ".":
                parts.append(seg)
        t = ("/" if t.startswith("/") else "") + "/".join(parts)
        return self.env.checkout_of(t) or t

    def names(self, s):
        if not isinstance(s, str) or not s or self.th.kind != "main":
            return
        for n in BOOT_NAMES:
            if NAME_RE[n].search(s):
                self.c["boot_call|" + n] += 1
                self.boot_calls += 1

    def read_result(self, labels, chars, is_err):
        """Internal fw labels a successful read returned (Read, shell readers)."""
        th = self.th
        if is_err:
            return
        for bk in labels:
            if bk == ".sumela/sumela-prompt.md":
                self.sumela = True
            if th.kind != "main":
                continue
            if bk.startswith(".sumela/skills/context-handoff/"):
                self.procedure_read(chars // max(1, len(labels)))
            if bk == ".sumela/skills/using-second-brain/task-records.md":
                self.tr_read = True
            if bk.startswith(".sumela/.handoff/") and th.k <= 10:
                self.continuation = True
            if bk in (".sumela/skills/brainstorming/SKILL.md", ".sumela/skills/writing-plans/SKILL.md"):
                self.planning = True
            if bk.startswith("docs/second-brain/wiki/") and self.first_curated is None:
                rest = bk[len("docs/second-brain/wiki/"):]
                top = rest.split("/", 1)[0]
                if rest not in WIKI_SPECIAL and top not in WIKI_DIRS:
                    self.first_curated = self.lookup_seen

    def user_text(self, s, cls):
        th = self.th
        if th.kind == "sub":
            if self.first_prompt is None and cls != "skill_body":
                self.first_prompt = s[:20000]
            return
        if cls == "skill_body":
            m = SKILL_BASE_RE.search(s[:400])
            if m:
                name = m.group(1).replace("\\", "/").rstrip("/").rsplit("/", 1)[-1]
                if name in ("brainstorming", "writing-plans"):
                    self.planning = True
                if name == "context-handoff":
                    self.procedure_read(len(s))
            return
        if cls == "slash_cmd":
            if "context-handoff" in s[:300]:
                self.set_trigger()
                self.procedure_read(0)
            for n in ("brainstorming", "writing-plans"):
                if n in s[:300]:
                    self.planning = True
            return
        if cls != "user_prompt":
            return
        phrase = bool(HANDOFF_PHRASE.search(s))
        if not self.first_prompt_seen:
            self.first_prompt_seen = True
            if HANDOFF_HEADING.search(s) or HANDOFF_FILE_RE.search(s) or (phrase and len(s) >= 1500):
                self.continuation = True
                phrase = False         # a pasted handoff starts this session; it asks for none
        if phrase:
            self.set_trigger()
            self.pending_phrase = th.k

    def assistant_text(self, s):
        th = self.th
        if th.kind == "sub":
            for m in STATUS_RE.finditer(s):
                self.status = m.group(1)
            return
        if HANDOFF_HEADING.search(s) and "{DATE}" not in s:
            self.signal("template", len(s), handoff_full(s))
        if self.pending_phrase is not None:
            if th.k - self.pending_phrase > 3:
                self.pending_phrase = None
            elif len(s) >= 800 and HANDOFF_SHAPE.search(s):
                self.signal("user_phrase", len(s), handoff_full(s))
                self.pending_phrase = None


def process_thread(th, env):
    x = th.x
    root = th.root
    home, cfgp = env.home, env.cfg_projects
    with open(th.path, "rb") as fh:
        for raw in fh:
            if not raw.strip():
                continue
            th.lines += 1
            try:
                d = json.loads(raw)
            except Exception:
                th.misc["bad_json"] += 1
                continue
            if not isinstance(d, dict):
                th.misc["non_object"] += 1
                continue
            try:
                handle_line(th, env, d, x, root, home, cfgp)
            except (TypeError, AttributeError, KeyError, ValueError, IndexError, OverflowError):
                th.misc["unprocessable"] += 1      # an unexpected shape: counted, never fatal
    th.close_seg()
    first_sp = next((s[0] for s in th.sys_snapshots if s[0]), None)
    first_tools = next((s[1] for s in th.sys_snapshots if s[1]), None)
    for r in th.reqs:
        sp = r["sp_chars"] if r["sp_chars"] else first_sp
        tl = r["tools_chars"] if r["tools_chars"] else first_tools
        r["sp_chars"], r["tools_chars"] = sp, tl
        r["sys_chars"] = (sp or 0) + (tl or 0) if (sp or tl) else None


def handle_line(th, env, d, x, root, home, cfgp):
    """One transcript line (the research loop body, unchanged in effect)."""
    t = d.get("type")
    ts = parse_ts(d.get("timestamp"))
    if ts and env.until and ts > env.until:
        th.misc["after_until"] += 1
        return
    if ts:
        th.ts.append(ts)
        x.ts = ts
    uuid = d.get("uuid")
    uuid = uuid if isinstance(uuid, str) and uuid else None     # items keep it for the preserved-message check
    if uuid:
        th.uuids.add(uuid)
    x.seq += 1
    gb = d.get("gitBranch")
    if isinstance(gb, str) and gb:
        if x.start_branch is None:
            x.start_branch = gb
        elif gb != x.last_branch:
            x.switched = True
            x.transition(False)
        x.last_branch = gb
    cwd = d.get("cwd")
    if isinstance(cwd, str) and cwd:
        x.cwd = cwd
        if cwd not in env.cwd_seen:
            env.note_cwd(cwd, th.slug_dir)
        if th.kind == "main":
            x.enter(env.checkout_of(cwd), False)
    if t == "system":
        st = d.get("subtype")
        if st == "compact_boundary":
            cm = d.get("compactMetadata") if isinstance(d.get("compactMetadata"), dict) else {}
            pm = cm.get("preservedMessages") if isinstance(cm.get("preservedMessages"), dict) else {}
            allu = pm.get("allUuids") if isinstance(pm.get("allUuids"), list) else []
            pres = set(u for u in allu if isinstance(u, str))
            th.compactions.append({"ts": ts, "pre": cm.get("preTokens"), "trigger": cm.get("trigger"), "k": th.k})
            th.close_seg(frozenset(pres))
            x.seen_path, x.seen_exact = set(), set()
            x.boundary()
            x.pending_confirm = False
            x.set_trigger()
        return
    if t == "assistant":
        m = d.get("message") if isinstance(d.get("message"), dict) else {}
        mid = m.get("id") or d.get("requestId") or ("line%d" % th.lines)
        u = m.get("usage") if isinstance(m.get("usage"), dict) else {}
        model = m.get("model")
        if d.get("version"):
            th.versions[str(d.get("version"))] += 1
        inp, cc, cr, out = (_int(u.get(k)) for k in ("input_tokens", "cache_creation_input_tokens",
                                                      "cache_read_input_tokens", "output_tokens"))
        otd = u.get("output_tokens_details") if isinstance(u.get("output_tokens_details"), dict) else {}
        think = _int(otd.get("thinking_tokens"))
        if not isinstance(mid, (str, int)):
            mid = "line%d" % th.lines
        if mid not in th.req_by_id:
            if model == "<synthetic>" or (inp + cc + cr + out) == 0:
                th.misc["synthetic_or_zero_usage"] += 1
                th.req_by_id[mid] = None
            else:
                if th.reqs and th.reqs[-1]["_seg"] == len(th.compactions):
                    th.cum_think += th.reqs[-1]["think"]
                ccd = u.get("cache_creation") if isinstance(u.get("cache_creation"), dict) else {}
                r = {"ts": ts, "inp": inp, "cc": cc, "cr": cr, "ctx": inp + cc + cr, "out": out,
                     "cc5": _int(ccd.get("ephemeral_5m_input_tokens")), "cc1h": _int(ccd.get("ephemeral_1h_input_tokens")),
                     "think": think, "model": model if isinstance(model, str) else None,
                     "est_chars": th.seg_chars, "cum_think": th.cum_think, "_seg": len(th.compactions),
                     "added": dict(th.since), "sp_chars": th.sp_chars, "tools_chars": th.tools_chars, "vis": 0}
                th.since = collections.Counter()
                th.reqs.append(r)
                th.req_by_id[mid] = r
                th.models[r["model"]] += 1
                if r["ctx"] > th.peak_ctx:
                    th.peak_ctx = r["ctx"]
                th.k += 1
        else:
            r = th.req_by_id[mid]
            if r is not None:
                if out > r["out"]:
                    r["out"] = out
                if think > r["think"]:
                    r["think"] = think
        content = m.get("content")
        cur_req = th.req_by_id.get(mid)
        if isinstance(content, list):
            for it in content:
                if not isinstance(it, dict):
                    continue
                ty = it.get("type")
                if ty == "text":
                    s = it.get("text") if isinstance(it.get("text"), str) else ""
                    th.add("asst_text", len(s), None, uuid)
                    if cur_req is not None:
                        cur_req["vis"] += len(s)
                    x.assistant_text(s)
                elif ty == "tool_use":
                    name = it.get("name")
                    grp = tool_group(name)
                    inp_obj = it.get("input")
                    try:
                        ilen = len(json.dumps(inp_obj, ensure_ascii=False))
                    except Exception:
                        ilen = 0
                    info = {"grp": grp}
                    iobj = inp_obj if isinstance(inp_obj, dict) else {}
                    if grp in ("Bash", "PowerShell"):
                        cmd = iobj.get("command") if isinstance(iobj.get("command"), str) else ""
                        info["reads"] = shell_reads(cmd, "ps" if grp == "PowerShell" else "sh", root, home, cfgp)
                        info["exact"] = ("B", cmd)
                    elif grp == "Read":
                        fp = iobj.get("file_path") if isinstance(iobj.get("file_path"), str) else ""
                        bk, cls = fw_bucket(fp, root, home, cfgp)
                        ranged = iobj.get("offset") is not None or iobj.get("limit") is not None
                        info["read"] = (bk, cls)
                        info["exact"] = ("R", fp, str(iobj.get("offset")), str(iobj.get("limit")))
                        wl = label_path(fp, env.roots)
                        if wl.startswith("docs/second-brain/wiki/") and wl[len("docs/second-brain/wiki/"):] in WIKI_SPECIAL and not ranged:
                            info["whole"] = wl
                    elif grp == "Agent" and th.kind == "main":
                        x.c["agent_calls"] += 1
                    elif grp == "SubagentHandback" and th.kind == "sub":
                        msg = iobj.get("message")
                        if isinstance(msg, str):
                            x.assistant_text(msg)
                    if isinstance(it.get("id"), (str, int)):
                        th.tool_uses[it.get("id")] = info
                    x.tool_use(name, grp, iobj, info)
                    th.add("tu:" + grp, ilen, None, uuid)
        return
    if t == "user":
        m = d.get("message") if isinstance(d.get("message"), dict) else {}
        is_meta = bool(d.get("isMeta"))
        okind = None
        if d.get("turnOrigin") == "peer" or (isinstance(d.get("origin"), dict) and d["origin"].get("kind") == "peer"):
            okind = "peer"
        elif d.get("turnOrigin") == "scheduled":
            okind = "scheduled"
        content = m.get("content")
        if d.get("isCompactSummary"):
            s = content if isinstance(content, str) else tr_text(content)[0]
            th.add("compact_summary", len(s), None, uuid)
            return
        if isinstance(content, str):
            cls = classify_user_text(content, is_meta, okind)
            th.add(cls, len(content), None, uuid)
            x.user_text(content, cls)
            return
        if not isinstance(content, list):
            return
        for it in content:
            if not isinstance(it, dict):
                continue
            ty = it.get("type")
            if ty == "text":
                s = it.get("text") if isinstance(it.get("text"), str) else ""
                cls = classify_user_text(s, is_meta, okind)
                th.add(cls, len(s), None, uuid)
                x.user_text(s, cls)
            elif ty == "image":
                th.add("image", IMG_TOKENS * 4, None, uuid)
            elif ty == "tool_result":
                tool_result(th, it, uuid)
        return
    if t == "attachment":
        attachment(th, d, uuid)
        return


def shell_reads(cmd, shell, root, home, cfgp):
    """(internal label, class, how) for each file a shell command's reader verbs print."""
    res = []
    if not cmd.strip():
        return res
    for toks in stages_of(cmd, shell):
        v = toks[0]
        if shell == "ps":
            if v.lower() in PS_READER_VERBS:
                for p in ps_read_paths(toks):
                    res.append(fw_bucket(p, root, home, cfgp) + (v.lower(),))
        elif v in READER_VERBS:
            for p in read_paths(v, toks):
                res.append(fw_bucket(p, root, home, cfgp) + (v,))
    return res


def tool_result(th, it, uuid):
    x = th.x
    tid = it.get("tool_use_id")
    info = (th.tool_uses.get(tid) if isinstance(tid, (str, int)) else None) or {"grp": "other"}        # the research's "unknown": the same calibration group
    grp = info["grp"]
    text, ni = tr_text(it.get("content"))
    chars = len(text)
    if ni:
        th.add("image", ni * IMG_TOKENS * 4, None, uuid)
    is_err = bool(it.get("is_error"))
    tag = None
    labels = []
    if grp in ("Bash", "PowerShell") and "reads" in info:
        reads = info["reads"]
        fw = [r for r in reads if fw_like(r[1])]
        if reads:
            shr = chars / len(reads)
            for (bk, cls, how) in reads:
                th.read_events.append((bk, cls, shr, "shell", th.k))
        if fw:
            tag = ("bash", "fwread", tuple(sorted(set(r[0] for r in fw))))
            labels = sorted(set(r[0] for r in fw))
        if info.get("evidence_cmd") and th.kind == "main" and not is_err:
            x.evidence.update(record_mentions(text, th.x.env))
            x.evidence.update(k + ".md" for k in info.get("task_keys", ()))
    elif grp == "Read" and "read" in info:
        bk, cls = info["read"]
        tag = ("read", bk, cls)
        th.read_events.append((bk, cls, chars, "Read", th.k))
        if fw_like(cls):
            labels = [bk]
    if info.get("evidence_cmd") and grp not in ("Bash", "PowerShell") and th.kind == "main" and not is_err:
        x.evidence.update(record_mentions(text, th.x.env))     # EnterWorktree's result
    th.add("tr:" + grp, chars, tag, uuid)
    # successful framework reads: re-reads, the contract, Q17, A16b (baseline.py observer)
    err2 = is_err or text[:20].startswith("<tool_use_error>")
    if labels and not err2:
        c = x.c
        c["fw_read_calls"] += 1
        c["fw_read_calls_chars"] += chars
        if any(p in x.seen_path for p in labels):
            c["fw_reread_path"] += 1
            c["fw_reread_path_chars"] += chars
        x.seen_path.update(labels)
        ek = info.get("exact")
        if ek is not None:
            if ek in x.seen_exact:
                c["fw_reread_exact"] += 1
                c["fw_reread_exact_chars"] += chars
            x.seen_exact.add(ek)
    x.read_result(labels, chars, err2)
    if "whole" in info and th.kind == "main":
        head = text[:600]
        if "exceeds maximum allowed size" in head and (err2 or chars < 2000):
            oc = "size_refused"
        elif "exceeds maximum allowed tokens" in head and (err2 or chars < 2000):
            oc = "token_capped"
        elif err2:
            oc = "other_error"
        else:
            oc = "ok"
        wl = info["whole"]
        x.c["a5|" + wl + "|attempts"] += 1
        x.c["a5_outcome|" + oc] += 1
        if oc != "ok":
            x.c["a5|" + wl + "|failures"] += 1
            x.a5_failed = True
            if th.k < 30:
                x.c["a5_failures_first_30"] += 1


def attachment(th, d, uuid):
    x, env = th.x, th.x.env
    root, home, cfgp = th.root, env.home, env.cfg_projects
    a = d.get("attachment") if isinstance(d.get("attachment"), dict) else {}
    at = a.get("type")
    r = d.get("rendered")
    rchars = 0
    if isinstance(r, list):
        for y in r:
            if isinstance(y, dict):
                cc_ = y.get("content")
                if isinstance(cc_, str):
                    rchars += len(cc_)
                elif isinstance(cc_, list):
                    rchars += sum(len(z.get("text") or "") for z in cc_ if isinstance(z, dict) and isinstance(z.get("text"), (str, type(None))))
    elif isinstance(r, str):
        rchars = len(r)
    if at == "prompt_snapshot":
        sp = a.get("systemPrompt")
        tl = a.get("tools")
        spc = 0
        if isinstance(sp, list):
            for y in sp:
                if isinstance(y, str):
                    spc += len(y)
                elif isinstance(y, dict):
                    spc += len(y.get("text")) if isinstance(y.get("text"), str) else len(json.dumps(y, ensure_ascii=False))
        elif isinstance(sp, str):
            spc = len(sp)
        if isinstance(tl, list):
            th.tools_chars = len(json.dumps(tl, ensure_ascii=False))
        th.sys_snapshots.append((spc, th.tools_chars, th.k))
        th.sp_chars = spc
        return
    if at in ("file", "nested_memory", "compact_file_reference"):      # the contract attached (@-mention, nested load)
        for key in ("displayPath", "filename", "path"):
            v = a.get(key)
            if isinstance(v, str) and fw_bucket(v, root, home, cfgp)[0] == ".sumela/sumela-prompt.md":
                x.sumela = True
    files = [f for f in a.get("files") if isinstance(f, dict)] if isinstance(a.get("files"), list) else []
    if at == "instructions":
        for f in files:
            if isinstance(f, dict) and fw_bucket(f.get("path") or "", root, home, cfgp)[0] == ".sumela/sumela-prompt.md":
                x.sumela = True
    if rchars <= 0:
        return
    if at == "instructions":
        tot = sum(len(f.get("content") or "") for f in files if isinstance(f.get("content"), (str, type(None)))) or 1
        acc = 0
        for f in files:
            content = f.get("content") if isinstance(f.get("content"), str) else ""
            bk, cls = fw_bucket(f.get("path") if isinstance(f.get("path"), str) else "", root, home, cfgp)
            if cls == "fw":
                lab = bk
            elif cls == "fw-nested":
                lab = "nested " + os.path.basename(bk)
            elif cls in ("fw-user", "automem"):
                lab = bk
            else:
                lab = "other(" + cls + ")"
            shr = int(rchars * len(content) / tot)
            acc += shr
            th.add("instr:" + lab, shr, ("instr", lab), uuid)
            if lab == "claude-auto-memory/MEMORY.md":
                x.memory_loads += 1
                x.memory_sizes.append(len(content))
        if rchars - acc > 0:
            th.add("instr:<wrapper>", rchars - acc, None, uuid)
    elif at == "file":
        bk, cls = fw_bucket(a.get("displayPath") or a.get("filename") or "", root, home, cfgp)
        lab = bk if fw_like(cls) or cls == "fw-nested" else "<" + cls + ">"
        th.add("attfile:" + lab, rchars, ("attfile", lab), uuid)
    elif at == "nested_memory":
        bk, cls = fw_bucket(a.get("path") or a.get("displayPath") or "", root, home, cfgp)
        lab = bk if fw_like(cls) or cls == "fw-nested" else "<" + cls + ">"
        th.add("nested_memory:" + lab, rchars, ("nested", lab), uuid)
    elif at == "hook_additional_context":
        th.add("hook_ctx", rchars, None, uuid)
    elif at == "queued_command":
        mode = a.get("commandMode")
        origin = a.get("origin") if isinstance(a.get("origin"), dict) else {}
        if mode == "task-notification":
            lab = "queued:task-notification"
        elif origin.get("kind") == "peer":
            lab = "queued:peer-message"
        elif mode == "prompt":
            lab = "queued:user-prompt"
        else:
            lab = "queued:other"
        th.add(lab, rchars, None, uuid)
    elif at == "skill_listing":
        content = a.get("content") if isinstance(a.get("content"), str) else ""
        per = collections.Counter()
        curname = None
        for line in content.split("\n"):
            mm = SKILL_LINE_RE.match(line)
            if mm:
                curname = mm.group(1)
            nm = curname or "<header>"
            if nm in FRAMEWORK_SKILL_NAMES:
                cls = "sumela"
            elif nm.startswith("anthropic-skills:"):
                cls = "anthropic-skills"
            elif nm == "<header>":
                cls = "header"
            elif re.match(r"^[a-z][a-z0-9-]*$", nm) and nm in BUILTIN_SKILLS:
                cls = "builtin"
            else:
                cls = "other"
            per[(cls, nm)] += len(line) + 1
        tot = sum(per.values()) or 1
        for (cls, nm), v in per.items():
            th.add("skill_listing:" + cls, int(rchars * v / tot), None, uuid)
    else:
        th.add("att:" + str(at), rchars, None, uuid)


BUILTIN_SKILLS = frozenset({"update-config", "keybindings-help", "code-review", "simplify", "fewer-permission-prompts", "loop",
                            "schedule", "claude-api", "workflow-authoring", "run", "plugin-authoring", "init", "security-review",
                            "dataviz", "artifact-design", "artifact-diagramming", "artifact-capabilities", "review", "pr-comments",
                            "statusline", "compact", "debug", "insights", "batch", "verify", "remember", "stuck"})


# ---------------------------------------------------------------------------- discovery
GIT_ENV_DROP = ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_PREFIX")


class Failure(Exception):
    """Could not run: the message is a fixed sentence written here, never data."""


class UsageError(Exception):
    pass


def git(root, *args):
    """(exit code, stdout). git's stderr is captured and never printed: its messages name
    paths; a failure is reported in one fixed sentence that says how to see git's reason."""
    env = {k: v for k, v in os.environ.items() if k not in GIT_ENV_DROP and not k.startswith("GIT_TRACE")}
    # A developer's trace settings (GIT_TRACE*, trace2.* in git config) would make git log this
    # tool's commands and paths; 0 turns every target off, whatever the config says.
    env.update(GIT_TRACE="0", GIT_TRACE2="0", GIT_TRACE2_EVENT="0", GIT_TRACE2_PERF="0")
    try:
        p = subprocess.run(["git", "-C", root] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    except OSError:
        return 127, ""
    return p.returncode, p.stdout.decode("utf-8", "surrogateescape")


def find_install_root(given):
    if given:
        r = os.path.abspath(given)
        return r if os.path.isdir(os.path.join(r, ".sumela")) else None
    p = os.path.abspath(os.getcwd())
    while True:
        if os.path.isdir(os.path.join(p, ".sumela")):
            return p
        parent = os.path.dirname(p)
        if parent == p:
            return None
        p = parent


def _norm(p):
    p = p.replace("\\", "/")
    return p.rstrip("/") if len(p) > 1 else p


def slugs(path):
    p = path.rstrip("/\\") or path
    return {re.sub(r"[/\\:.]", "-", p), re.sub(r"[^A-Za-z0-9]", "-", p)}


def _git_lines(root, *args):
    rc, out = git(root, *args)
    if rc != 0:
        return None
    return [ln.rstrip("\r") for ln in out.split("\n") if ln.rstrip("\r")]


def state_dir(root, create=False):
    """The per-developer state directory of scripts/lib/sumela-state.sh, computed the same way:
    <base>/sumela/<the first 16 hex chars of sha256("<main checkout>/<install prefix>")>.
    None when git cannot answer. --create makes it 0700."""
    common = _git_lines(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not common or len(common) != 1 or not re.match(r"^(/|[A-Za-z]:/)", common[0]):
        return None
    pref = _git_lines(root, "rev-parse", "--show-prefix")
    if pref is None:
        return None
    c = common[0][:-5] if common[0].endswith("/.git") else common[0]
    pr = pref[0] if pref else ""
    pr = pr[:-1] if pr.endswith("/") else pr
    key = hashlib.sha256((c + "/" + pr).encode("utf-8", "surrogateescape")).hexdigest()[:16]
    if os.name == "nt" or sys.platform.startswith(("cygwin", "msys")):
        base = os.environ.get("LOCALAPPDATA")
        if not base:
            return None
        d = os.path.join(base, "sumela", key)
    else:
        base = os.environ.get("XDG_STATE_HOME") or ""
        if not base.startswith("/"):
            home = os.environ.get("HOME")
            if not home:
                return None
            base = home + "/.local/state"
        d = base + "/sumela/" + key
    if create:
        old = os.umask(0o077)
        try:
            os.makedirs(d, mode=0o700, exist_ok=True)
        finally:
            os.umask(old)
        if os.name != "nt":
            os.chmod(d, 0o700)
    return d


def write_state_file(root, rel, data):
    """R1-10's seam, the only write this tool may make: <state dir>/<rel>, 0600 inside 0700
    directories, through a temporary file in the same directory and a rename. <rel> is made of
    [A-Za-z0-9._-]+ segments. Returns the path."""
    segs = rel.split("/")
    if not segs or any(not re.fullmatch(r"[A-Za-z0-9._-]+", s) or s in (".", "..") for s in segs):
        raise Failure("invalid state file name")
    d = state_dir(root, create=True)
    if d is None:
        raise Failure("no per-developer state directory (no git work tree)")
    for s in segs[:-1]:
        d = os.path.join(d, s)
        old = os.umask(0o077)
        try:
            os.makedirs(d, mode=0o700, exist_ok=True)
        finally:
            os.umask(old)
    path = os.path.join(d, segs[-1])
    tmp = os.path.join(d, "." + segs[-1] + ".sumela-tmp.%d" % os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    if os.name != "nt":
        os.chmod(path, 0o600)
    return path


class Install:
    """Where to look and how to label: the roots (checkouts, install directories), the
    transcript directories, the branch of each linked worktree, the task records' branches."""

    def __init__(self, root, checkouts, prefix, cfg, home, project_dirs, base_names):
        self.root = root
        self.checkouts = checkouts            # [(path, branch|None)], main first
        self.prefix = prefix
        self.cfg = cfg
        self.home = home
        self.cfg_projects = _norm(os.path.join(cfg, "projects")) + "/"
        self.project_dirs = project_dirs      # [(transcript dir, its root, main checkout?)]
        self.base_names = base_names
        roots = set()
        for path, _ in checkouts:
            for v in (path, path + "/" + prefix if prefix else None):
                if v:
                    roots.add(_norm(v))
                    rp = _norm(os.path.realpath(v)) if os.path.exists(v) else None
                    if rp:
                        roots.add(rp)
        for r in list(roots):
            m = re.match(r"^([A-Za-z]):(/.*)?$", r)
            if m:
                roots.add("/" + m.group(1).lower() + (m.group(2) or ""))
        self._roots = set(r for r in roots if r and r != "/" and not re.match(r"^[A-Za-z]:/?$", r))
        self.roots = sorted(self._roots, key=len, reverse=True)
        self.wt_branch = [(_norm(p), b) for p, b in checkouts[1:] if b]
        self.records = collections.defaultdict(set)
        self.record_keys = set()
        self.branch_names = frozenset()
        self.cwd_seen = set()
        self.until = None

    def note_cwd(self, cwd, slug_dir):
        """A session's cwd becomes a root when Claude Code keyed this transcript directory by it."""
        self.cwd_seen.add(cwd)
        if slug_dir and os.path.basename(slug_dir) in slugs(cwd):
            r = _norm(cwd)
            if r and r != "/" and r not in self._roots:
                self._roots.add(r)
                self.roots = sorted(self._roots, key=len, reverse=True)

    def branch_of(self, path):
        for p, b in self.wt_branch:
            if path and _under(path, p):
                return b
        return None

    def checkout_of(self, path):
        """The checkout a path lies in: the longest checkout root above it. A worktree folder of a
        checkout (.worktrees/<name>, worktrees/<name>, .claude/worktrees/<name>) is a checkout of
        its own, even when git no longer lists it. None outside every checkout."""
        p = _norm(path) if isinstance(path, str) and path else ""
        best = None
        for c, _ in self.checkouts:
            if p and _under(p, c) and (best is None or len(c) > len(best)):
                best = c
        if best is not None:
            m = re.match(r"^(?:\.worktrees|worktrees|\.claude/worktrees)/[^/]+", p[len(best):].lstrip("/"))
            if m:
                best = best + "/" + m.group(0)
        return best

    def load_records(self):
        """branch -> {record file name}, from the Continue Point blocks of every checkout's records."""
        seen = set()
        for path, _ in self.checkouts:
            base = path + "/" + self.prefix if self.prefix else path
            d = os.path.join(base, "docs", "second-brain", "wiki", "_tasks")
            if not os.path.isdir(d) or os.path.realpath(d) in seen:
                continue
            seen.add(os.path.realpath(d))
            for name in sorted(os.listdir(d)):
                fp = os.path.join(d, name)
                if not name.endswith(".md") or not os.path.isfile(fp) or os.path.getsize(fp) > 1 << 20:
                    continue
                try:
                    with open(fp, "r", encoding="utf-8", errors="replace") as fh:
                        lines = fh.read().split("\n")
                except OSError:
                    continue
                incp = False
                for ln in lines:
                    ln = ln.rstrip("\r")
                    if ln.startswith("## "):
                        incp = ln.strip() == "## Continue Point"
                    elif incp and ln.startswith("### "):
                        b = ln[4:].strip()
                        if b:
                            self.records[b].add(name)
                            self.record_keys.add(name[:-3])

    def branch_class(self, b):
        return "base" if b in self.base_names else "topic"


def discover(opts):
    root = find_install_root(opts.root)
    if root is None:
        raise Failure("no SumelaOS install found (no .sumela/ above the working directory; use --root)")
    root = _norm(root)
    lines = _git_lines(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not lines or len(lines) != 1 or not re.match(r"^(/|[A-Za-z]:/)", lines[0]):
        raise Failure("git cannot read the repository at the install root (run git status there to see git's reason; "
                      "git 2.31 or later is required)")
    main = lines[0][:-5] if lines[0].endswith("/.git") else lines[0]
    pref = _git_lines(root, "rev-parse", "--show-prefix") or [""]
    prefix = pref[0].rstrip("/") if pref else ""
    entries = []                         # [path, branch] per worktree, as git lists them
    rc, out = git(root, "worktree", "list", "--porcelain")
    if rc == 0:
        for ln in out.split("\n"):
            ln = ln.rstrip("\r")
            if ln.startswith("worktree "):
                entries.append([_norm(ln[9:]), None])
            elif ln.startswith("branch ") and entries:
                b = ln[7:]
                entries[-1][1] = b[11:] if b.startswith("refs/heads/") else b
    main = _norm(main)
    checkouts = [(main, next((b for p, b in entries if p == main), None))]
    checkouts += [(p, b) for p, b in entries if p != main]
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    cfg = os.path.abspath(cfg)
    home = _norm(os.path.expanduser("~"))
    pdirs, seen = [], set()
    for n, (path, _) in enumerate(checkouts):
        if n and opts.main_only:
            break
        for cand in (path + "/" + prefix if prefix else None, path):
            if not cand:
                continue
            variants = {cand}
            if os.path.exists(cand):
                variants.add(_norm(os.path.realpath(cand)))
            for v in sorted(variants):
                for s in sorted(slugs(v)):
                    d = os.path.join(cfg, "projects", s)
                    if os.path.isdir(d) and not os.path.islink(d):
                        rp = os.path.realpath(d)
                        if rp not in seen:
                            seen.add(rp)
                            pdirs.append((d, v, n == 0))
    if not opts.main_only:
        # Sessions started in a worktree folder of the main checkout that git no longer lists (a
        # removed worktree) keep their transcript directory: <main slug>--worktrees-<name> etc.
        prefixes = tuple(sl + suffix for sl in slugs(checkouts[0][0]) for suffix in ("--worktrees-", "-worktrees-", "--claude-worktrees-"))
        try:
            names = sorted(os.listdir(os.path.join(cfg, "projects")))
        except OSError:
            names = []
        for nm in names:
            d = os.path.join(cfg, "projects", nm)
            if nm.startswith(prefixes) and os.path.isdir(d) and not os.path.islink(d) and os.path.realpath(d) not in seen:
                seen.add(os.path.realpath(d))
                pdirs.append((d, checkouts[0][0], False))
    base_names = {"main", "master", "develop", "development", "trunk"}
    rc, out = git(root, "config", "--get-all", "sumela.baseRefs")
    if rc == 0:
        for ref in out.split():
            ref = re.sub(r"^refs/(?:heads|remotes/[^/]+)/", "", ref)
            ref = re.sub(r"^[^/]+/", "", ref) if "/" in ref and not ref.startswith("refs/") else ref
            if ref:
                base_names.add(ref)
    rc, out = git(root, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD")
    if rc == 0 and out.strip():
        base_names.add(out.strip().split("/", 3)[-1])
    inst = Install(root, checkouts, prefix, cfg, home, pdirs, base_names)
    rc, out = git(root, "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes")
    if rc == 0:
        names = set()
        for ln in out.split("\n"):
            ln = ln.strip()
            if ln:
                names.add(ln)
                if "/" in ln:
                    names.add(ln.split("/", 1)[1])      # origin/x is checked out as x
        inst.branch_names = frozenset(names)
    inst.load_records()
    return inst


def list_transcripts(pdir):
    """(main files, [(session id, subagent file)]) of one transcript directory; no symlinks."""
    mains, subs = [], []
    try:
        entries = sorted(os.scandir(pdir), key=lambda e: e.name)
    except OSError:
        return mains, subs
    for e in entries:
        try:
            if e.is_file(follow_symlinks=False) and e.name.endswith(".jsonl"):
                mains.append(e.path)
            elif e.is_dir(follow_symlinks=False):
                sd = os.path.join(e.path, "subagents")
                if os.path.isdir(sd) and not os.path.islink(sd):
                    for dp, dns, fns in os.walk(sd, followlinks=False):
                        dns.sort()
                        for fn in sorted(fns):
                            fp = os.path.join(dp, fn)
                            if fn.endswith(".jsonl") and fn != "journal.jsonl" and not os.path.islink(fp):
                                subs.append((e.name, fp))
        except OSError:
            continue
    return mains, subs


# ---------------------------------------------------------------------------- corpus
class Corpus:
    def __init__(self):
        self.threads = []
        self.files = collections.Counter()


def parse_corpus(inst):
    cp = Corpus()
    for pdir, root, in_main in inst.project_dirs:
        mains, subs = list_transcripts(pdir)
        cp.files["project_dirs"] += 1
        for kind, items in (("main", [(os.path.basename(p)[:-6], p) for p in mains]), ("sub", subs)):
            for sid, p in items:
                th = Thread(kind, sid, p, root)
                th.slug_dir = pdir
                th.in_main_dir = in_main
                th.x = Extras(th, inst)
                if kind == "sub":
                    mp = p[:-6] + ".meta.json"
                    try:
                        if os.path.isfile(mp) and os.path.getsize(mp) < 1 << 20:
                            with open(mp, "rb") as fh:
                                meta = json.loads(fh.read())
                            th.meta = meta if isinstance(meta, dict) else {}
                    except Exception:
                        cp.files["unreadable_meta"] += 1
                try:
                    process_thread(th, inst)
                except OSError:
                    cp.files["unreadable_files"] += 1
                    continue
                cp.files["main_transcripts" if kind == "main" else "subagent_transcripts"] += 1
                if kind == "sub":
                    m = th.meta
                    at = m.get("agentType")
                    th.agent_type = at if isinstance(at, str) and at in AGENT_TYPES else ("<none>" if at is None else "<custom>")
                    md = m.get("model")
                    th.model_label = md if isinstance(md, str) and (MODEL_RE.match(md) or md in MODEL_ALIASES) else ("<none>" if md is None else "<other>")
                    th.role = classify_role(th.x.first_prompt, at if isinstance(at, str) else None)
                    th.x.first_prompt = None            # never kept past classification
                    th.meta = {}
                cp.threads.append(th)
    return cp


# ---------------------------------------------------------------------------- aggregation
def cost_units_req(r):
    return (r["inp"] * PRICE["inp"] + r["cc5"] * PRICE["cc5"] + r["cc1h"] * PRICE["cc1h"] +
            max(0, r["cc"] - r["cc5"] - r["cc1h"]) * PRICE["cc5"] + r["cr"] * PRICE["cr"] + r["out"] * PRICE["out"])


def area_of(bk):
    if bk.startswith("docs/second-brain/artifacts"):
        return "artifacts"
    if bk.startswith("docs/second-brain"):
        return "wiki"
    if bk.startswith("claude-auto-memory"):
        return "auto_memory"
    return "core"


def thread_record(th):
    """Additive counters of one thread (baseline.py's thread_record, plus the new counters)."""
    c = collections.Counter()
    reqs = th.reqs
    c["threads"] = 1
    c["n_req"] = len(reqs)
    for r in reqs:
        cu = cost_units_req(r)
        c["ctx"] += r["ctx"]
        for f in ("inp", "cc", "cc5", "cc1h", "cr", "out", "think"):
            c[f] += r[f]
        c["cost_units"] += cu
        c["vis_chars"] += r["vis"]
        c["think_carried"] += r["cum_think"]
        c["sys_chars_carried"] += (r["sp_chars"] or 0) + (r["tools_chars"] or 0)
        if r["ctx"] >= 500000:
            c["ge500_n"] += 1
            c["ge500_ctx"] += r["ctx"]
            c["ge500_cost"] += cu
    prev = None
    for r in reqs:
        if prev is not None:
            growth = max(0, r["ctx"] - prev["ctx"])
            excess = r["cc"] - growth
            gap = (r["ts"] - prev["ts"]).total_seconds() if r["ts"] and prev["ts"] else None
            gb = "na" if gap is None else ("lt_5m" if gap < 300 else ("5_60m" if gap < 3600 else "gt_60m"))
            if excess > 2000 and r["cc"] > 0.5 * r["ctx"]:
                c["rewrite_events|" + gb] += 1
                c["rewrite_tokens|" + gb] += excess
        prev = r
    ts = sorted(th.ts)
    c["active_s"] = sum((b - a).total_seconds() for a, b in zip(ts, ts[1:]) if (b - a).total_seconds() < 1800)
    c["n_compact"] = len(th.compactions)
    for cat, chars, tag, _k, _u, mult in th.all_items:
        g = comp_group(cat)
        dg = delta_group(cat)
        c["comp|%s|%s" % (g, dg)] += chars * mult
        c["raw|" + dg] += chars
        c["carried|" + dg] += chars * mult
        if cat.startswith(LISTING_PREFIX):
            c["inherited_listing|" + dg] += chars * mult
        if cat == "instr:claude-auto-memory/MEMORY.md":
            c["memory_md_carried"] += chars * mult
        if "claude-auto-memory" in cat:
            c["auto_memory_carried|" + dg] += chars * mult
        if tag and tag[0] == "read" and fw_like(tag[2]):
            c["fw_read_carried|tr_read"] += chars * mult
            c["fw_area_read|" + area_of(tag[1])] += chars * mult
        elif tag and tag[0] == "bash" and len(tag) >= 3 and tag[1] == "fwread":
            c["fw_read_carried|tr_bash"] += chars * mult
            for pth in tag[2]:
                c["fw_area_bash|" + area_of(pth)] += chars * mult / len(tag[2])
        if cat in ("attfile:.sumela/sumela-prompt.md", "instr:CLAUDE.md", "nested_memory:CLAUDE.md"):
            c["fw_attached|" + dg] += chars * mult
    for (bk, cls, chars, how, kreq) in th.read_events:
        if fw_like(cls):
            c["fw_read_events"] += 1
            c["fw_read_chars"] += chars
            if kreq < 30:
                c["fw_first_30_chars"] += chars
    c.update(th.x.c)
    return c


def calibrate(mains, threads):
    def delta_rows(ths):
        rows = []
        for th in ths:
            prev = None
            for r in th.reqs:
                if prev is not None and r["_seg"] == prev["_seg"] and not r["added"].get("_reset"):
                    a = r["added"]
                    dsys = (r["sys_chars"] or 0) - (prev["sys_chars"] or 0)
                    rows.append(([a.get(g, 0) for g in DELTA_GROUPS] + [prev["think"], a.get("_n_items", 0), dsys, 1.0],
                                 r["ctx"] - prev["ctx"]))
                prev = r
        return rows
    drows = delta_rows(mains)
    fit = ols_multi(drows, list(FIT_TERMS)) if len(drows) > 50 else None
    coef = {g: (fit.get(g, DEFAULT_COEF) if fit else DEFAULT_COEF) for g in DELTA_GROUPS}
    coef["image"] = IMAGE_COEF
    frows = []
    for th in threads:
        if th.reqs:
            r0 = th.reqs[0]
            sp, tl = r0["sp_chars"] or 0, r0["tools_chars"] or 0
            if sp and tl:
                frows.append(([sp + tl, r0["est_chars"], 1.0], r0["ctx"]))
    sysfit = ols_multi(frows, ["s", "c", "i"]) if frows else None
    sys_coef = sysfit.get("s") if sysfit and sysfit.get("s") is not None else DEFAULT_SYS_COEF
    return coef, sys_coef, fit, sysfit, len(drows)


def scope_shares(C, coef, sys_coef):
    toks = collections.Counter()
    for k, v in C.items():
        if k.startswith("comp|"):
            _, g, dg = k.split("|")
            toks[g] += v * coef.get(dg, DEFAULT_COEF)
    toks["thinking_carried"] = C["think_carried"]
    toks["system_prompt_and_tool_schemas"] = C["sys_chars_carried"] * sys_coef
    return toks


def section_composition(G, coef, sys_coef):
    out = {}
    for lab in ("all", "main", "subagent"):
        C = G[lab]
        tk = scope_shares(C, coef, sys_coef)
        den = C["ctx"]
        explained = sum(tk.values())
        shares = {g: pct(v, den) for g, v in sorted(tk.items(), key=lambda kv: (-kv[1], kv[0])) if v and den and pct(v, den) >= 0.005}
        tr = coef.get("tr_read", DEFAULT_COEF)
        att = sum(C["fw_attached|" + dg] * coef.get(dg, DEFAULT_COEF) for dg in DELTA_GROUPS)
        fwr = C["fw_read_carried|tr_read"] * tr
        fwb = C["fw_read_carried|tr_bash"] * coef.get("tr_bash", DEFAULT_COEF)
        out[lab] = {
            "context_tokens": den,
            "explained_pct": pct(explained, den),
            "shares_pct": shares,
            "mcp_results_pct": pct(sum(v for g, v in tk.items() if g.startswith("tool_result:mcp")), den),
            "harness_listings_pct": pct(sum(v for g, v in tk.items() if g.startswith(("skill_listing:", "harness_listing:"))), den),
            "framework_instructions_and_attached_pct": pct(tk.get("instructions:framework", 0) + tk.get("attached_file:framework", 0)
                                                           + tk.get("nested_memory:framework", 0), den),
            "framework_reads_pct": {"read_tool": pct(fwr, den), "read_tool_plus_shell_readers": pct(fwr + fwb, den)},
            "sumela_instruction_content_pct": {
                "lower_read_tool_only": pct(C["fw_area_read|core"] * tr + att, den),
                "upper_with_shell_readers": pct((C["fw_area_read|core"] + C["fw_area_bash|core"]) * tr + att, den)},
            "framework_reads_by_area_pct": {a: {"read_tool": pct(C["fw_area_read|" + a] * tr, den),
                                                "read_tool_plus_shell_readers": pct((C["fw_area_read|" + a] + C["fw_area_bash|" + a]) * tr, den)}
                                            for a in ("core", "wiki", "artifacts", "auto_memory")},
        }
    return out


def build_report(inst, cp, opts):
    excluded = collections.Counter()
    mains = {}
    for th in cp.threads:
        if th.kind == "main":
            mains[(th.slug_dir, th.sid)] = th
    subs_by = collections.defaultdict(list)
    orphans = []                          # subagent threads whose main thread is missing
    for th in cp.threads:
        if th.kind == "sub":
            if (th.slug_dir, th.sid) in mains:
                subs_by[(th.slug_dir, th.sid)].append(th)
            elif th.reqs:
                orphans.append(th)
    sessions = []
    epoch = datetime.min.replace(tzinfo=timezone.utc)

    def started(kv):
        th = kv[1]
        return th.reqs[0]["ts"] or epoch if th.reqs else epoch
    for key, th in sorted(mains.items(), key=started):
        if not th.reqs:
            excluded["no_requests"] += 1
            continue
        if not th.x.sumela and not opts.all_sessions:
            excluded["not_a_sumela_session"] += 1
            continue
        t0 = th.reqs[0]["ts"]
        if opts.since and t0 and t0 < opts.since:
            excluded["before_since"] += 1
            continue
        sessions.append((th, [s for s in subs_by.get(key, []) if s.reqs]))
    data_q = section_data_quality(inst, cp, sessions, excluded, len(orphans), opts)
    rep = {"schema": SCHEMA, "generated_utc": iso(datetime.now(timezone.utc)), "status": "ok", "sections": {}}
    if not sessions:
        rep["status"] = "no_sessions" if cp.files["main_transcripts"] else "no_transcripts"
        rep["sections"]["data_quality"] = data_q
        rep["hint"] = HINT_STATIC
        return rep
    mts = [m for m, _ in sessions]
    # --all-sessions counts what the research scripts counted, orphan subagent threads included
    sts = [s for _, ss in sessions for s in ss] + (orphans if opts.all_sessions else [])
    coef, sys_coef, fit, sysfit, npairs = calibrate(mts, mts + sts)
    for th in mts + sts:
        th.rec = thread_record(th)
    G = {"main": collections.Counter(), "subagent": collections.Counter()}
    for th in mts:
        G["main"].update(th.rec)
    for th in sts:
        G["subagent"].update(th.rec)
    G["all"] = G["main"] + G["subagent"]
    ctx = dict(inst=inst, sessions=sessions, mts=mts, sts=sts, G=G, coef=coef, sys_coef=sys_coef, fit=fit,
               sysfit=sysfit, npairs=npairs, opts=opts, data_quality=data_q)
    for key, builder in SECTION_BUILDERS:
        rep["sections"][key] = builder(ctx)
    return rep


HINT_STATIC = "run with --static for the framework's static footprint (no transcripts needed)"


def section_data_quality(inst, cp, sessions, excluded, orphans, opts):
    misc = collections.Counter()
    versions = set()
    for th in cp.threads:
        misc.update(th.misc)
        misc["lines"] += th.lines
        versions.update(v for v in th.versions if VERSION_RE.match(v))
    seen = collections.Counter()
    for th, _ in sessions:
        for u in th.uuids:
            seen[u] += 1
    tss = sorted(r["ts"] for th, ss in sessions for t in [th] + ss for r in t.reqs if r["ts"])
    sv = None
    try:
        with open(os.path.join(inst.root, ".sumela", "VERSION"), "r", encoding="utf-8", errors="replace") as fh:
            v = fh.readline().strip()
        sv = v if VERSION_RE.match(v) else None
    except OSError:
        pass
    return {
        "sumela_version": sv,
        "project_dirs_scanned": cp.files["project_dirs"],
        "main_transcripts": cp.files["main_transcripts"],
        "subagent_transcripts": cp.files["subagent_transcripts"],
        "unreadable_files": cp.files["unreadable_files"] + cp.files["unreadable_meta"],
        "lines": misc["lines"],
        "malformed_lines": misc["bad_json"],
        "non_object_lines": misc["non_object"],
        "unprocessable_lines": misc["unprocessable"],
        "lines_after_until": misc["after_until"],
        "synthetic_or_zero_usage_messages": misc["synthetic_or_zero_usage"],
        "claude_code_versions": sorted(versions, key=lambda s: [int(p) for p in s.split(".")]),
        "window": {"first_request_utc": iso(tss[0]) if tss else None, "last_request_utc": iso(tss[-1]) if tss else None,
                   "since": iso(opts.since), "until": iso(opts.until)},
        "sessions_included": len(sessions),
        "sessions_from_linked_worktree_dirs": sum(1 for th, _ in sessions if not th.in_main_dir),
        "subagent_threads_included": sum(len(ss) for _, ss in sessions),
        "excluded_sessions": {"not_a_sumela_session": excluded["not_a_sumela_session"], "no_requests": excluded["no_requests"],
                              "before_since": excluded["before_since"]},
        "orphan_subagent_threads": orphans,
        "orphan_subagent_threads_included": bool(opts.all_sessions),
        "all_sessions_flag": bool(opts.all_sessions),
        "main_checkout_only_flag": bool(opts.main_only),
        "duplicate_uuids_across_main_files": sum(1 for n in seen.values() if n > 1),
        "task_records_with_branch_blocks": len(set(n for s in inst.records.values() for n in s)),
        "labels_redacted": 0,
    }


def section_session_shape(ctx):
    sessions, G = ctx["sessions"], ctx["G"]
    M, S, A = G["main"], G["subagent"], G["all"]
    inst = ctx["inst"]
    out = {
        "sessions": len(sessions),
        "main_requests": M["n_req"],
        "subagent_requests": S["n_req"],
        "requests_per_session": dist([th.rec["n_req"] for th, _ in sessions]),
        "peak_context_tokens": dist([th.peak_ctx for th, _ in sessions]),
        "first_reply_context_tokens": dist([th.reqs[0]["ctx"] for th, _ in sessions]),
        "mean_context_per_request": {"main": M["ctx"] / M["n_req"] if M["n_req"] else None,
                                     "subagent": S["ctx"] / S["n_req"] if S["n_req"] else None},
        "ge_500k": {lab: {"requests_pct": pct(C["ge500_n"], C["n_req"]), "context_pct": pct(C["ge500_ctx"], C["ctx"]),
                          "cost_pct": pct(C["ge500_cost"], C["cost_units"])}
                    for lab, C in (("main", M), ("subagent", S), ("all", A))},
        "compactions": {"main": M["n_compact"], "subagent": S["n_compact"],
                        "per_100_main_requests": 100.0 * M["n_compact"] / M["n_req"] if M["n_req"] else None,
                        "sessions_with_compaction": sum(1 for th, _ in sessions if th.compactions)},
        "idle_rewrites": {lab: {"events_gt_60m": C["rewrite_events|gt_60m"], "tokens_gt_60m": C["rewrite_tokens|gt_60m"],
                                "active_hours": C["active_s"] / 3600.0,
                                "tokens_gt_60m_per_active_hour": C["rewrite_tokens|gt_60m"] / (C["active_s"] / 3600.0) if C["active_s"] else None,
                                "cost_units_gt_60m_share_pct": pct(2.0 * C["rewrite_tokens|gt_60m"], C["cost_units"])}
                          for lab, C in (("main", M), ("subagent", S))},
        "branch_at_start": {},
        "sessions_without_branch": 0,
        "sessions_switching_branch": sum(1 for th, _ in sessions if th.x.switched),
    }
    bc = collections.Counter()
    for th, _ in sessions:
        if th.x.start_branch:
            bc[inst.branch_class(th.x.start_branch)] += 1
        else:
            out["sessions_without_branch"] += 1
    out["branch_at_start"] = {k: bc[k] for k in ("base", "topic")}
    return out


def section_composition_b(ctx):
    return section_composition(ctx["G"], ctx["coef"], ctx["sys_coef"])


def section_framework_reads(ctx):
    sessions, G = ctx["sessions"], ctx["G"]
    by_file = collections.defaultdict(lambda: {"reads": 0, "chars": 0})
    for th, ss in sessions:
        for t in [th] + ss:
            for (bk, cls, chars, how, kreq) in t.read_events:
                if fw_like(cls):
                    # The internal label of a framework read is install-relative; the auto-memory
                    # files and the user's global CLAUDE.md live outside the install.
                    lab = label_path(bk if cls in ("fw", "fw-nested") else "~/" + os.path.basename(bk), ())
                    by_file[lab]["reads"] += 1
                    by_file[lab]["chars"] += int(chars)
    top = dict(sorted(by_file.items(), key=lambda kv: (-kv[1]["chars"], kv[0]))[:25])
    ch = [th.x.ch_total for th, _ in sessions]
    chb = [th.x.ch_before for th, _ in sessions]
    rr = {}
    for lab, C in (("main", G["main"]), ("subagent", G["subagent"]), ("all", G["all"])):
        rr[lab] = {"framework_read_calls": C["fw_read_calls"],
                   "same_path_same_segment": C["fw_reread_path"],
                   "same_path_same_segment_per_100_requests": 100.0 * C["fw_reread_path"] / C["n_req"] if C["n_req"] else None,
                   "exact_same_call_same_segment": C["fw_reread_exact"],
                   "exact_same_call_same_segment_per_100_requests": 100.0 * C["fw_reread_exact"] / C["n_req"] if C["n_req"] else None}
    return {
        "first_30_requests_chars_per_session": dist([th.rec["fw_first_30_chars"] for th, _ in sessions]),
        "whole_session_chars_per_session": dist([th.rec["fw_read_chars"] for th, _ in sessions]),
        "rereads": rr,
        "context_handoff": {
            "sessions_reading": sum(1 for v in ch if v),
            "chars_read_per_reading_session": dist([v for v in ch if v]),
            "sessions_reading_before_any_trigger": sum(1 for v in chb if v),
            "chars_read_before_any_trigger_per_session": dist([v for v in chb if v]),
            "chars_read_before_any_trigger_total": sum(chb),
            "sessions_with_a_trigger": sum(1 for th, _ in sessions if th.x.trigger),
        },
        "read_before_acting": read_before_acting(ctx),
        "by_file": top,
    }


def handoffs_of(th):
    """Merge one main thread's handoff signals into handoffs (signals within 15 minutes)."""
    x = th.x
    sig = list(x.signals)
    n = len(th.reqs)
    for (seq, ts, k, before, same, after) in x.task_continues:
        if k >= n - 10:
            sig.append((seq, ts, "task_continue_near_end", None, False, before, same, after))
    sig.sort(key=lambda s: s[0])
    groups = []
    for s in sig:
        if groups and s[1] and groups[-1][-1][1] and (s[1] - groups[-1][-1][1]).total_seconds() <= 900:
            groups[-1].append(s)
        else:
            groups.append([s])
    out = []
    for g in groups:
        sizes = [s[3] for s in g if s[3]]
        out.append({"kinds": set(s[2] for s in g), "size": max(sizes) if sizes else None,
                    "full": any(s[4] for s in g), "template": any(s[2] == "template" for s in g),
                    "before": g[0][5], "same": g[0][6], "after": g[0][7]})
    return out


def read_before_acting(ctx):
    if "rba" in ctx:
        return ctx["rba"]
    sessions = ctx["sessions"]
    hs = [h for th, _ in sessions for h in handoffs_of(th)]
    tw = [th.x.task_write_first for th, _ in sessions if th.x.task_write_first is not None]
    ctx["rba"] = {
        # "before" and "same_segment" are the pre-0.20 baseline's definitions (comparable with it);
        # "after_last_trigger" asks for a read after the trigger that preceded the handoff, so an
        # eager boot read alone does not count.
        "handoff_procedure_read_before_handoff": dict(share(sum(1 for h in hs if h["before"]), len(hs)),
                                                      same_segment_k=sum(1 for h in hs if h["same"]),
                                                      same_segment_pct=pct(sum(1 for h in hs if h["same"]), len(hs)),
                                                      after_last_trigger_k=sum(1 for h in hs if h["after"]),
                                                      after_last_trigger_pct=pct(sum(1 for h in hs if h["after"]), len(hs))),
        "task_records_read_before_first_task_write": share(sum(1 for v in tw if v), len(tw)),
    }
    return ctx["rba"]


def section_guardrails(ctx):
    G, sts = ctx["G"], ctx["sts"]
    # A completed task is an implementer subagent that returned DONE or DONE_WITH_CONCERNS: the one
    # unit that exists in every window, before and after v0.20.1. task close calls are reported
    # beside it, never added to it (the pre-0.20 baseline cannot have them).
    done = sum(1 for t in sts if t.role == "implementer" and t.x.status in ("DONE", "DONE_WITH_CONCERNS"))
    req = G["all"]["n_req"]
    return {
        "cache_read_share_of_input_pct": {lab: pct(G[lab]["cr"], G[lab]["inp"] + G[lab]["cc"] + G[lab]["cr"])
                                          for lab in ("main", "subagent", "all")},
        "turn_inflation": {"requests": req, "completed_tasks": done, "requests_per_completed_task": req / done if done else None,
                           "task_close_calls": G["main"]["task_close"]},
    }


def section_subagents(ctx):
    sessions, G, sts = ctx["sessions"], ctx["G"], ctx["sts"]
    coef, sys_coef = ctx["coef"], ctx["sys_coef"]
    tot_ctx, tot_cost = G["all"]["ctx"], G["all"]["cost_units"]

    def inherited(C):
        return C["sys_chars_carried"] * sys_coef + sum(C["inherited_listing|" + dg] * coef.get(dg, DEFAULT_COEF) for dg in DELTA_GROUPS)

    def table(attr):
        tab = collections.defaultdict(collections.Counter)
        for t in sts:
            tab[getattr(t, attr)].update(t.rec)
        return {k: {"threads": C["threads"], "requests": C["n_req"], "context_share_of_all_pct": pct(C["ctx"], tot_ctx),
                    "cost_share_of_all_pct": pct(C["cost_units"], tot_cost)}
                for k, C in sorted(tab.items(), key=lambda kv: (-kv[1]["ctx"], kv[0]))}
    S = G["subagent"]
    return {
        "threads": S["threads"],
        "threads_per_session": dist([len(ss) for _, ss in sessions]),
        "requests": S["n_req"],
        "context_share_of_all_pct": pct(S["ctx"], tot_ctx),
        "cost_share_of_all_pct": pct(S["cost_units"], tot_cost),
        "inherited_bootstrap_share_of_subagent_context_pct": pct(inherited(S), S["ctx"]),
        "first_context_tokens": dist([t.reqs[0]["ctx"] for t in sts]),
        "peak_context_tokens": dist([t.peak_ctx for t in sts]),
        "compactions": S["n_compact"],
        "by_agent_type": table("agent_type"),
        "by_role": table("role"),
        "by_model": table("model_label"),
    }


def section_handoffs(ctx):
    sessions = ctx["sessions"]
    hs, rvals, cont = [], [], 0
    sess_with = 0
    for th, _ in sessions:
        h = handoffs_of(th)
        hs.extend(h)
        sess_with += 1 if h else 0
        if th.x.continuation:
            cont += 1
            if th.x.first_edit_ctx is not None:
                rvals.append(th.x.first_edit_ctx)
    kinds = ("template", "user_phrase", "handoff_file", "task_continue_near_end")
    tmpl = [h for h in hs if h["template"]]
    return {
        "detected": len(hs),
        "sessions_with_a_handoff": sess_with,
        "by_signal": {k: sum(1 for h in hs if k in h["kinds"]) for k in kinds},
        "detected_without_the_template_heading": sum(1 for h in hs if not h["template"]),
        "size_chars": dist([h["size"] for h in hs if h["size"]]),
        "full_share_of_template_handoffs": share(sum(1 for h in tmpl if h["full"]), len(tmpl)),
        "continuation_sessions": cont,
        "r_continuation_tokens": {k: v for k, v in dist(rvals).items() if k in ("n", "p50", "p90")},
    }


def section_memory_md(ctx):
    sessions, G, sts, inst = ctx["sessions"], ctx["G"], ctx["sts"], ctx["inst"]
    coef = ctx["coef"].get("att", DEFAULT_COEF)
    sizes = [v for th, ss in sessions for t in [th] + ss for v in t.x.memory_sizes]
    last = None
    for th, ss in sessions:
        for t in [th] + ss:
            if t.x.memory_sizes:
                last = t.x.memory_sizes[-1]
    f_bytes = f_lines = None
    topics = 0
    present = False
    for pdir, _root, _main in inst.project_dirs:
        mp = os.path.join(pdir, "memory", "MEMORY.md")
        if os.path.isfile(mp):
            present = True
            try:
                with open(mp, "rb") as fh:
                    data = fh.read(4 << 20)
                f_bytes = (f_bytes or 0) + len(data.replace(b"\r\n", b"\n"))
                f_lines = (f_lines or 0) + data.count(b"\n")
            except OSError:
                pass
            try:
                topics += sum(1 for n in os.listdir(os.path.join(pdir, "memory")) if n.endswith(".md") and n != "MEMORY.md")
            except OSError:
                pass
    mts = ctx["mts"]
    return {
        "main_threads_loading": share(sum(1 for t in mts if t.x.memory_loads), len(mts)),
        "subagent_threads_loading": share(sum(1 for t in sts if t.x.memory_loads), len(sts)),
        "loads": sum(t.x.memory_loads for t in mts + sts),
        "size_chars": {"max_observed": max(sizes) if sizes else None, "last_observed": last},
        "carried_share_of_context_pct": {lab: pct(G[lab]["memory_md_carried"] * coef, G[lab]["ctx"]) for lab in ("all", "main", "subagent")},
        "auto_memory_with_topic_files_carried_share_of_context_pct": {
            lab: pct(sum(G[lab]["auto_memory_carried|" + dg] * ctx["coef"].get(dg, DEFAULT_COEF) for dg in DELTA_GROUPS), G[lab]["ctx"])
            for lab in ("all", "main", "subagent")},
        "index_file": {"present": present, "bytes": f_bytes, "lines": f_lines, "topic_files": topics},
    }


def section_second_brain(ctx):
    sessions, G = ctx["sessions"], ctx["G"]
    M = G["main"]
    mts = ctx["mts"]
    n = len(mts)
    by_file = {}
    for k, v in M.items():
        if k.startswith("a5|"):
            _, wl, f = k.split("|")
            by_file.setdefault(wl, {"attempts": 0, "failures": 0})[f] = v
    a15q = [t for t in mts if t.x.a15_qual]
    a16q = [t for t in mts if t.x.planning and t.x.first_artifact_write is not None]
    a16b = [t for t in mts if t.x.first_curated is not None]
    calls = {f: G["all"]["wiki_call|" + f] for f in ("digest", "digest_branch", "catalog", "search", "entry", "entry_list",
                                                    "task_show", "task_list", "task_write", "team", "lint")}
    return {
        "a4_digest_in_first_10_requests": share(sum(1 for t in mts if t.x.digest_first10), n),
        "a5_whole_file_reads": {
            "attempts": sum(v["attempts"] for v in by_file.values()),
            "failures": sum(v["failures"] for v in by_file.values()),
            "failures_first_30_requests": M["a5_failures_first_30"],
            "size_refused": M["a5_outcome|size_refused"], "token_capped": M["a5_outcome|token_capped"],
            "other_error": M["a5_outcome|other_error"],
            "sessions_with_a_failure": sum(1 for t in mts if t.x.a5_failed),
            "by_file": dict(sorted(by_file.items(), key=lambda kv: (-kv[1]["attempts"], kv[0]))),
        },
        "allow_large_reads": {"calls": M["allow_large"], "on_wiki_files": M["allow_large_wiki"]},
        "a6_calls_naming_boot_files": {"calls": sum(M["boot_call|" + b] for b in BOOT_NAMES),
                                       "sessions": sum(1 for t in mts if t.x.boot_calls),
                                       "calls_by_file": {b: M["boot_call|" + b] for b in BOOT_NAMES}},
        "a15_continuity": dict(share(sum(1 for t in a15q if t.x.a15_ok), len(a15q)),
                               task_records_with_branch_blocks=len(set(nm for s in ctx["inst"].records.values() for nm in s))),
        "a16_lookup_before_planning_artifact": share(sum(1 for t in a16q if t.x.first_artifact_write), len(a16q)),
        "a16b_lookup_before_curated_page_read": share(sum(1 for t in a16b if t.x.first_curated), len(a16b)),
        "q17_task_records_read_before_first_task_write": read_before_acting(ctx)["task_records_read_before_first_task_write"],
        "wiki_tool_calls": calls,
    }


def section_calibration(ctx):
    fit, sysfit = ctx["fit"], ctx["sysfit"]

    def clean(f, names):
        if not f:
            return {}
        d = {k: f[k] for k in names if k in f}
        d["r2"] = f.get("_r2")
        d["n"] = f.get("_n")
        return d
    return {
        "method": "research_delta_ols_v1",
        "fit_status": "fitted" if fit else "defaults",
        "request_pairs": ctx["npairs"],
        "tokens_per_char": dict(ctx["coef"]),
        "delta_fit_main": clean(fit, FIT_TERMS),
        "system_prompt_and_tools_tokens_per_char": ctx["sys_coef"],
        "first_request_fit": clean(sysfit, ("s", "c", "i")),
        "image_tokens_per_image": IMG_TOKENS,
        "default_tokens_per_char": DEFAULT_COEF,
        "price_multipliers": dict(PRICE),
    }


def section_totals(ctx):
    G = ctx["G"]
    out = {}
    for lab in ("main", "subagent", "all"):
        C = G[lab]
        out[lab] = {"threads": C["threads"], "requests": C["n_req"], "context_tokens": C["ctx"], "input_tokens": C["inp"],
                    "cache_creation_tokens": C["cc"], "cache_creation_5m_tokens": C["cc5"], "cache_creation_1h_tokens": C["cc1h"],
                    "cache_read_tokens": C["cr"], "output_tokens": C["out"], "thinking_tokens": C["think"],
                    "cost_units": C["cost_units"], "compactions": C["n_compact"], "thinking_carried_tokens": C["think_carried"],
                    "system_chars_carried": C["sys_chars_carried"], "visible_text_chars": C["vis_chars"],
                    "framework_read_events": C["fw_read_events"], "framework_read_chars": C["fw_read_chars"],
                    "raw_chars_by_group": {g: C["raw|" + g] for g in DELTA_GROUPS},
                    "carried_chars_by_group": {g: C["carried|" + g] for g in DELTA_GROUPS}}
    return out


# Section order, text titles and builders. R1-10 adds its "quality" section here.
SECTION_BUILDERS = [
    ("data_quality", lambda ctx: ctx["data_quality"]),
    ("session_shape", section_session_shape),
    ("composition", section_composition_b),
    ("framework_reads", section_framework_reads),
    ("guardrails", section_guardrails),
    ("subagents", section_subagents),
    ("handoffs", section_handoffs),
    ("memory_md", section_memory_md),
    ("second_brain", section_second_brain),
    ("calibration", section_calibration),
    ("totals", section_totals),
]
TITLES = {"data_quality": "Data quality", "session_shape": "Session shape",
          "composition": "Composition (calibrated share of context tokens)", "framework_reads": "Framework reads",
          "guardrails": "Guardrails", "subagents": "Subagents", "handoffs": "Handoffs",
          "memory_md": "MEMORY.md (Claude Code auto memory)", "second_brain": "Second brain",
          "calibration": "Calibration (for reproducing the totals)", "totals": "Totals (raw sums, for the differential)",
          "static_footprint": "Static footprint (no transcripts needed)"}


# ---------------------------------------------------------------------------- --static
LIVE_OF = {
    "CLAUDE.md.template": "CLAUDE.md",
    "AGENTS.md.template": "AGENTS.md",
    ".sumela/RULE_REGISTRY.md.template": ".sumela/RULE_REGISTRY.md",
    ".sumela/local.md.example": ".sumela/local.md",
    "docs/second-brain/template/wiki/_INDEX.md.template": "docs/second-brain/wiki/_INDEX.md",
    "docs/second-brain/template/wiki/active-project-context.md.template": "docs/second-brain/wiki/active-project-context.md",
}
STATIC_EXTRA = ("docs/second-brain/wiki/architecture-decisions.md", "docs/second-brain/wiki/tech-debt-and-known-issues.md",
                "docs/second-brain/wiki/_SEARCH_INDEX.md", "docs/second-brain/wiki/_LOG.md")


def _lf_size(path):
    try:
        with open(path, "rb") as fh:
            return len(fh.read().replace(b"\r\n", b"\n"))
    except OSError:
        return None


def static_report(root):
    rep = {"schema": SCHEMA, "generated_utc": iso(datetime.now(timezone.utc)), "status": "ok", "sections": {}}
    tsv = os.path.join(root, "scripts", "lib", "sumela-context-budgets.tsv")
    rows = []
    try:
        with open(tsv, "r", encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                ln = ln.rstrip("\r\n")
                if not ln or ln.startswith("#"):
                    continue
                cols = ln.split("\t")
                if len(cols) == 7:
                    rows.append(cols)
    except OSError:
        rep["status"] = "no_budget_table"
        return rep
    by_file, total, pinned_total, const = {}, 0, None, 0
    for kind, key, b, *_ in rows:
        if kind == "eager-member":
            live = LIVE_OF.get(key, key)
            size = _lf_size(os.path.join(root, live))
            src = "live"
            if size is None:
                size, src = _lf_size(os.path.join(root, key)), "template"
            lab = label_path(live, ())
            by_file[lab] = {"bytes": size, "pinned_bytes": int(b) if re.fullmatch(r"[0-9]{1,12}", b) else None, "live": src == "live"}
            total += size or 0
        elif kind == "eager-const":
            const += int(b) if re.fullmatch(r"[0-9]{1,12}", b) else 0
        elif kind == "eager-total":
            pinned_total = int(b) if re.fullmatch(r"[0-9]{1,12}", b) else None
    extra = {}
    for rel in STATIC_EXTRA:
        size = _lf_size(os.path.join(root, rel))
        if size is not None:
            extra[label_path(rel, ())] = {"bytes": size}
    rep["sections"]["static_footprint"] = {
        "eager_set": by_file, "eager_command_output_bytes": const, "eager_total_bytes": total + const,
        "eager_total_pinned_bytes": pinned_total, "wiki_registers_and_indexes": extra}
    return rep


# ---------------------------------------------------------------------------- the allow-list check
LABEL_MAP_KINDS = {"shares_pct": "comp", "by_file": "path", "by_agent_type": "agent_type", "by_role": "role",
                   "by_model": "model", "branch_at_start": "branch_class", "tokens_per_char": "delta_group",
                   "raw_chars_by_group": "delta_group", "carried_chars_by_group": "delta_group",
                   "delta_fit_main": "fit_term", "first_request_fit": "fit_term", "eager_set": "path",
                   "wiki_registers_and_indexes": "path", "calls_by_file": "wiki_name", "price_multipliers": "price"}
STATIC_TEXT = frozenset({SCHEMA, "ok", "no_sessions", "no_transcripts", "no_budget_table", "research_delta_ols_v1",
                         "fitted", "defaults", HINT_STATIC})
VALUE_KINDS = {"claude_code_versions": "version", "sumela_version": "version", "first_request_utc": "datetime",
               "last_request_utc": "datetime", "since": "datetime", "until": "datetime", "generated_utc": "datetime",
               "schema": "static", "status": "static", "method": "static", "fit_status": "static", "hint": "static"}


def _key_ok(kind, k):
    if kind == "path":
        return valid_path_label(k)
    if kind == "comp":
        if k in COMP_FIXED:
            return True
        m = re.fullmatch(r"(tool_result|tool_input):([^\n]+)", k)
        return bool(m) and m.group(2) in TOOL_LABELS
    if kind == "agent_type":
        return k in AGENT_TYPES
    if kind == "role":
        return k in ROLES
    if kind == "model":
        return bool(MODEL_RE.match(k)) or k in MODEL_ALIASES
    if kind == "branch_class":
        return k in ("base", "topic")
    if kind == "delta_group":
        return k in DELTA_GROUPS
    if kind == "fit_term":
        return k in FIT_TERMS or k in ("s", "c", "i", "r2", "n")
    if kind == "wiki_name":
        return k in BOOT_NAMES
    if kind == "price":
        return k in PRICE
    return False


def _val_ok(kind, v):
    if kind == "version":
        return bool(VERSION_RE.match(v))
    if kind == "datetime":
        return bool(DATETIME_RE.match(v))
    if kind == "static":
        return v in STATIC_TEXT
    return False


def sanitize(obj, parent=None, counter=None):
    """The allow-list, checked a second time on the finished report: keys are snake_case
    identifiers, or labels of the kind their map declares; strings are values of a declared
    kind. Whatever fails becomes "<redacted>" and is counted."""
    if counter is None:
        counter = [0]
    if isinstance(obj, dict):
        kind = LABEL_MAP_KINDS.get(parent)
        out = {}
        for k, v in obj.items():
            ok = isinstance(k, str) and (_key_ok(kind, k) if kind else bool(SNAKE_RE.match(k)))
            if not ok:
                counter[0] += 1
                k = "<redacted>"
                while k in out:
                    k += "_"
            out[k] = sanitize(v, k if ok else None, counter)
        return out
    if isinstance(obj, (list, tuple, set)):
        return [sanitize(v, parent, counter) for v in (sorted(obj) if isinstance(obj, set) else obj)]
    if isinstance(obj, bool) or obj is None:
        return obj
    if isinstance(obj, int):
        return obj
    if isinstance(obj, float):
        return None if obj != obj or obj in (float("inf"), float("-inf")) else obj
    if isinstance(obj, str):
        kind = VALUE_KINDS.get(parent)
        if kind and _val_ok(kind, obj):
            return obj
        counter[0] += 1
        return "<redacted>"
    counter[0] += 1
    return "<redacted>"


def finalize(rep):
    counter = [0]
    clean = sanitize(rep, None, counter)
    if counter[0]:
        dq = clean.get("sections", {}).get("data_quality")
        if isinstance(dq, dict):
            dq["labels_redacted"] = counter[0]
    return clean


# ---------------------------------------------------------------------------- rendering
DIST_KEYS = frozenset({"n", "p50", "p90", "mean", "max"})


def _fmt(v):
    if v is None:
        return "-"
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, float):
        if v.is_integer() and abs(v) < 1e15:
            return str(int(v))
        return ("%.3f" % v).rstrip("0").rstrip(".")
    if isinstance(v, list):
        return ", ".join(_fmt(x) for x in v) if v else "-"
    return str(v)


def _render(node, depth, out):
    pad = "  " * depth
    for k, v in node.items():
        if isinstance(v, dict) and v and set(v) <= DIST_KEYS and "n" in v:
            out.append("%s%s: %s" % (pad, k, " ".join("%s=%s" % (kk, _fmt(v[kk])) for kk in ("n", "p50", "p90", "mean", "max") if kk in v)))
        elif isinstance(v, dict) and {"n", "k", "share_pct"} <= set(v):
            extra = "".join(" %s=%s" % (kk, _fmt(vv)) for kk, vv in v.items() if kk not in ("n", "k", "share_pct"))
            out.append("%s%s: %s of %s (%s%%)%s" % (pad, k, _fmt(v["k"]), _fmt(v["n"]), _fmt(v["share_pct"]), extra))
        elif isinstance(v, dict) and v and len(v) <= 6 and not any(isinstance(vv, (dict, list)) for vv in v.values()):
            out.append("%s%s: %s" % (pad, k, " ".join("%s=%s" % (kk, _fmt(vv)) for kk, vv in v.items())))
        elif isinstance(v, dict):
            if not v:
                out.append("%s%s: -" % (pad, k))
                continue
            out.append("%s%s:" % (pad, k))
            _render(v, depth + 1, out)
        else:
            out.append("%s%s: %s" % (pad, k, _fmt(v)))


def render_text(rep):
    out = ["SumelaOS token report (aggregates only: no message text, prompts, code, tool inputs, non-framework paths or branch names)"]
    st = rep.get("status")
    if st == "no_transcripts":
        out.append("No Claude Code transcripts were found for this install. Another IDE? Run with --static for the")
        out.append("framework's static footprint (no transcripts needed).")
    elif st == "no_sessions":
        out.append("No session in the window (or none read the contract; --all-sessions counts every session).")
        out.append("Run with --static for the framework's static footprint (no transcripts needed).")
    elif st == "no_budget_table":
        out.append("--static needs scripts/lib/sumela-context-budgets.tsv, which this install does not have.")
    for key, _ in SECTION_BUILDERS + [("static_footprint", None)]:
        sec = rep.get("sections", {}).get(key)
        if sec is None or key in JSON_ONLY:
            continue
        out.append("")
        out.append(TITLES.get(key, key))
        _render(sec, 1, out)
    if st == "ok" and "totals" in rep.get("sections", {}):
        out.append("")
        out.append("The raw totals (per scope: requests, tokens, cost units, raw and carried chars) print with --json.")
    return "\n".join(out) + "\n"


JSON_ONLY = frozenset({"totals"})


def render_json(rep):
    def rnd(o):
        if isinstance(o, float):
            return round(o, 6)
        if isinstance(o, dict):
            return {k: rnd(v) for k, v in o.items()}
        if isinstance(o, list):
            return [rnd(v) for v in o]
        return o
    return json.dumps(rnd(rep), indent=1, ensure_ascii=True) + "\n"


# ---------------------------------------------------------------------------- command line
class Opts:
    root = None
    since = None
    until = None
    all_sessions = False
    main_only = False
    json = False
    static = False


USAGE = ("usage: sumela-token-report [--root <dir>] [--since <when>] [--until <when>] [--all-sessions]\n"
         "                           [--main-checkout-only] [--json]\n"
         "       sumela-token-report --static [--root <dir>] [--json]\n"
         "<when> is YYYY-MM-DD or an ISO 8601 date-time (UTC). Exit 0 ok, 2 degraded, 1 could not run.\n"
         "The header of scripts/sumela-token-report.py documents every section and the privacy contract.\n")


def parse_when(s, end_of_day):
    s = s.strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
        try:
            d = datetime.strptime(s, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        except ValueError:
            raise UsageError("invalid date")
        return d + timedelta(days=1) - timedelta(microseconds=1) if end_of_day else d
    dt = parse_ts(s)
    if dt is None:
        raise UsageError("invalid date-time")
    return dt


# Options: one row each. R1-10 adds its rows (baselines, --compare, --share, --test-cmd ...).
VALUE_OPTS = {"--root": ("root", lambda v: v), "--since": ("since", lambda v: parse_when(v, False)),
              "--until": ("until", lambda v: parse_when(v, True))}
FLAG_OPTS = {"--all-sessions": "all_sessions", "--main-checkout-only": "main_only", "--json": "json", "--static": "static"}


def parse_args(argv):
    o = Opts()
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            raise SystemExit(0)
        if a in VALUE_OPTS:
            if i + 1 >= len(argv):
                raise UsageError(a + " needs a value")
            attr, conv = VALUE_OPTS[a]
            setattr(o, attr, conv(argv[i + 1]))
            i += 2
            continue
        if a not in FLAG_OPTS:
            raise UsageError("unknown argument")
        setattr(o, FLAG_OPTS[a], True)
        i += 1
    return o


def report_from_install(inst, opts):
    """Parse the transcripts and build the finished, sanitized report (tests call this with a
    hand-built Install)."""
    inst.until = opts.until
    cp = parse_corpus(inst)
    return finalize(build_report(inst, cp, opts))


def run(argv, out=None):
    out = out or sys.stdout
    try:
        opts = parse_args(argv)
    except SystemExit:
        out.write(USAGE)
        return 0
    if opts.static:
        root = find_install_root(opts.root)
        if root is None:
            raise Failure("no SumelaOS install found (no .sumela/ above the working directory; use --root)")
        rep = finalize(static_report(root))
    else:
        inst = discover(opts)
        rep = report_from_install(inst, opts)
    text = render_json(rep) if opts.json else render_text(rep)
    out.write(text)
    out.flush()
    return 0 if rep.get("status") == "ok" else 2


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    try:
        return run(argv)
    except UsageError as e:
        sys.stderr.write("sumela-token-report: %s\n%s" % (e.args[0] if e.args and isinstance(e.args[0], str) else "usage error", USAGE))
        return 1
    except Failure as e:
        sys.stderr.write("sumela-token-report: could not run: %s\n" % e.args[0])
        return 1
    except BrokenPipeError:
        return 1
    except KeyboardInterrupt:
        return 1
    except Exception as e:      # a generic line only: an exception's text can carry transcript data
        name = type(e).__name__
        sys.stderr.write("sumela-token-report: could not run (internal error%s); no data was printed\n"
                         % (": " + name if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,60}", name) else ""))
        return 1


if __name__ == "__main__":
    sys.exit(main())
