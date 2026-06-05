<skills_system priority="1">
<usage>
This file is the SINGLE source of skill discovery for any agent (Claude, Gemini, Kimi, etc.) running in any IDE (Claude Code, Cursor, Codex, Antigravity, OpenCode, etc.). Skills live under `.sumela/skills/<name>/SKILL.md`, NOT under IDE-specific folders like `.claude/skills/` or `.opencode/skills/`. Read this file at session start and use the descriptions below to decide which skills to load.

How to load a skill:
- Use the <path> field from the entry below.
- Invoke: `cat <path>` (bash) or `Get-Content <path>` (PowerShell), or use the IDE's Read tool.
- The skill body loads into the current context. Once loaded, its `<execution_workflow>` becomes the operating directive.

Selection rules:
- Match the user's task against each `<description>`. If even 1% probability matches, load the skill.
- Skills share the context window — do NOT load the same skill twice.
- Security is paramount: cross-reference `secure-coding-standard` whenever planning, writing, or reviewing code.

What is NOT in this registry (deliberately):
Some skill directories contain helper files that are NOT independently discoverable:
- Prompt templates (e.g., `brainstorming/spec-document-reviewer-prompt.md`, `requesting-code-review/{reviewer-correctness-security,reviewer-design-contracts,reviewer-integration-ops}.md` (the parallel review-panel lanes) and `requesting-code-review/code-reviewer.md` (legacy single-reviewer fallback), `subagent-driven-development/{implementer,spec-reviewer,code-quality-reviewer}-prompt.md`, `writing-plans/plan-document-reviewer-prompt.md`) — payloads dispatched to a subagent BY a parent skill.
- Reference docs (e.g., `writing-skills/persuasion-principles.md`) — loaded BY the parent skill when relevant.
- Optional companions (e.g., `brainstorming/visual-companion.md`) — invoked BY parent skill on user opt-in.

These files MUST NOT be selected directly from this registry. The parent skill's body explains when to load them. Treat them as private to their parent skill.
</usage>

<available_skills>

<skill activation="eager">
<name>using-superpowers</name>
<description>Use at the start of every conversation and before generating any response — including clarifying questions — to dispatch the right skills, capture signals, and check for information gaps.</description>
<path>.sumela/skills/using-superpowers/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>idea-explore</name>
<description>Use for divergent product ideation — when the user wants help deciding WHAT to build ('what should I build', 'what do you suggest'), asks you to suggest or propose new features or product improvements (not code-level refactors), wants to discuss what would add value, or has only a raw, unclear, or not-yet-formed idea. Run BEFORE any architecture, design, or code; hand off to brainstorming once a direction is chosen.</description>
<path>.sumela/skills/brainstorming/idea-explore.md</path>
</skill>

<skill activation="lazy">
<name>brainstorming</name>
<description>Use when starting a new feature, system, or architectural change that is already chosen and clear enough to design — to produce approved design options and a saved spec, before any code is written, implementation skills are invoked, or project scaffolding begins. If the idea is still open-ended or the user wants help deciding WHAT to build or what would add value, start with idea-explore first.</description>
<path>.sumela/skills/brainstorming/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>writing-plans</name>
<description>Use when starting implementation from an approved spec or design — before any code is written or worktree is created.</description>
<path>.sumela/skills/writing-plans/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>executing-plans</name>
<description>Use when executing a written implementation plan inline after the user chooses not to use subagent-driven-development.</description>
<path>.sumela/skills/executing-plans/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>test-driven-development</name>
<description>Use when about to start implementation of any feature or bug fix — before writing any production code.</description>
<path>.sumela/skills/test-driven-development/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>systematic-debugging</name>
<description>Use when encountering a bug, test failure, or unexpected behavior — before attempting any fix.</description>
<path>.sumela/skills/systematic-debugging/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>requesting-code-review</name>
<description>Use when completing a task, implementing a major feature, or before merging - to catch issues before they cascade into committed history.</description>
<path>.sumela/skills/requesting-code-review/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>receiving-code-review</name>
<description>Use when receiving code review feedback from a subagent reviewer or human partner - before implementing any suggested changes.</description>
<path>.sumela/skills/receiving-code-review/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>verification-before-completion</name>
<description>Use when about to claim work is complete, fixed, or passing - before task completion, moving to the next task, code review, or committing any changes.</description>
<path>.sumela/skills/verification-before-completion/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>using-git-worktrees</name>
<description>Use when starting any implementation task that requires an isolated workspace — before creating branches or writing any code.</description>
<path>.sumela/skills/using-git-worktrees/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>subagent-driven-development</name>
<description>Use when executing an implementation plan with independent tasks in the current session — preferred over executing-plans for quality and context isolation.</description>
<path>.sumela/skills/subagent-driven-development/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>dispatching-parallel-agents</name>
<description>Use when facing 2+ independent tasks or failures with no shared state - to investigate or fix them concurrently without blocking each other.</description>
<path>.sumela/skills/dispatching-parallel-agents/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>root-cause-tracing</name>
<description>Use when an error occurs deep in the call stack and the immediate failure location is not the root cause.</description>
<path>.sumela/skills/systematic-debugging/root-cause-tracing.md</path>
</skill>

<skill activation="lazy">
<name>defense-in-depth</name>
<description>Use when fixing a bug caused by invalid data that can enter the system through multiple code paths or be bypassed by mocks and refactoring.</description>
<path>.sumela/skills/systematic-debugging/defense-in-depth.md</path>
</skill>

<skill activation="lazy">
<name>condition-based-waiting</name>
<description>Use when tests use arbitrary delays or are flaky due to race conditions in async operations.</description>
<path>.sumela/skills/systematic-debugging/condition-based-waiting.md</path>
</skill>

<skill activation="lazy">
<name>testing-anti-patterns</name>
<description>Use when writing or modifying tests — before adding mocks, test utilities, or test-only methods to production code.</description>
<path>.sumela/skills/test-driven-development/testing-anti-patterns.md</path>
</skill>

<skill activation="lazy">
<name>writing-skills</name>
<description>Use when creating new skills, editing existing skills, or verifying skills work before deployment.</description>
<path>.sumela/skills/writing-skills/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>finishing-a-development-branch</name>
<description>Use when implementation is complete and all code review is approved - to commit staged changes, integrate the branch, and update the Second Brain.</description>
<path>.sumela/skills/finishing-a-development-branch/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>secure-coding-standard</name>
<description>Use whenever the task touches user input, forms, APIs, database queries, authentication, authorization, passwords, file uploads, permissions, secrets, CORS, rate limiting, or any external/untrusted data — load before planning or coding, not after.</description>
<path>.sumela/skills/secure-coding-standard/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>performance-optimization</name>
<description>Use when performance requirements exist, a regression is suspected, or profiling reveals bottlenecks that need fixing.</description>
<path>.sumela/skills/performance-optimization/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>shipping-and-launch</name>
<description>Use when preparing to deploy to production — to run pre-launch checks, plan a staged rollout, set up monitoring, and document a rollback strategy.</description>
<path>.sumela/skills/shipping-and-launch/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>using-second-brain</name>
<description>Use when starting a session, ingesting a raw source, finishing a branch, answering a question that may reference prior work, or facing an information gap during reasoning (entity definitions, past decisions, call graphs, prior session context).</description>
<path>.sumela/skills/using-second-brain/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>self-improvement-curator</name>
<description>Use after every user turn to capture correction, confirmation, decision, friction, challenge, resolution, or preference signals (resolution = bugs the agent fixes itself; preference = standing user instructions); or when the user invokes /evolve, says 'evolve', 'review pending improvements', or asks to review captured learnings.</description>
<path>.sumela/skills/self-improvement-curator/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>init-sumela</name>
<description>Use when the user says '/initSumela', 'init SumelaOS', 'kur SumelaOS', or 'setup SumelaOS' in an existing project — auto-detects tech stack, architecture, and conventions, then generates AGENTS.md, rules, wiki, and IDE pointers.</description>
<path>.sumela/skills/init-sumela/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>onboard-sumela</name>
<description>Use when a developer joins a project that ALREADY has SumelaOS committed — '/onboardSumela', 'onboard SumelaOS', 'join this project', 'set up my clone' (or the equivalent in any language). Wires git hooks, sets the per-developer interaction language + domains, and offers the optional memory runtime — WITHOUT re-running install or touching team-wide config. NOT for first-time install (that is /initSumela).</description>
<path>.sumela/skills/onboard-sumela/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>qdrant-session-memory</name>
<description>Use when answering questions about past decisions, prior sessions, or 'why' questions — semantic search over Qdrant session history. Also use for code and wiki ingestion into Qdrant. Activates Tier-1 routing.</description>
<path>.sumela/memory-plugins/qdrant-session-memory/SKILL.md</path>
</skill>

<skill activation="lazy">
<name>graphify-code-graph</name>
<description>Use when answering questions about function callers/callees, code dependencies, impact analysis, or 'who calls X' — structural search over Graphify code graph. Activates Tier-2 routing.</description>
<path>.sumela/memory-plugins/graphify-code-graph/SKILL.md</path>
</skill>

<skill activation="eager">
<name>context-handoff</name>
<description>Use when context compaction warnings appear, after 8+ major tool sequences, after 3+ large file reads plus 2+ review cycles, when a sprint task closes mid-session with more work pending, or when the user asks for a handoff prompt or to start a new session (in any language).</description>
<path>.sumela/skills/context-handoff/SKILL.md</path>
</skill>

</available_skills>
</skills_system>
