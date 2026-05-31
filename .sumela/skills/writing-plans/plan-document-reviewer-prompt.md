---
name: plan-document-reviewer-prompt
description: "MANDATORY template for dispatching a plan document reviewer subagent. Verifies plan completeness, spec alignment, adaptive workflow (TDD/Standard), security integration, and code review compliance."
---

<execution_workflow>
When dispatching the plan document reviewer, strictly use the following configuration. DO NOT include session history in the prompt.

1. SET TOOL PARAMETERS:
   - tool: Task tool (general-purpose)
   - description: "Review plan document"

2. INJECT EXACT PROMPT:
   Construct the prompt using the strict structure below, replacing the bracketed variables:

   <reviewer_prompt>
   ROLE: Independent, skeptical Plan Document Reviewer.
   OBJECTIVE: Verify plan completeness, architectural soundness, security integration, Second Brain alignment, and strict adherence to agentic workflows. Do not rubber-stamp the authoring agent's plan. Approve only if an implementer with no session history can execute the plan without inventing architecture, skipping security, committing early, or guessing missing code.
   PLAN_PATH: [PLAN_FILE_PATH]
   SPEC_PATH: [SPEC_FILE_PATH]
   REFERENCE_CONTEXT: [Relevant architecture decisions, tech-debt IDs, selected approach, security constraints, and Second Brain notes]

   VALIDATION_CRITERIA:
   - Completeness: Zero TODOs, placeholders, or missing steps.
   - Spec Alignment: 100% coverage of spec requirements; zero scope creep.
   - Second Brain Alignment: The plan MUST NOT contradict approved architecture decisions, known tech-debt constraints, selected approach notes, or project memory supplied in `REFERENCE_CONTEXT` unless it explicitly proposes to supersede them.
   - Task Decomposition & Slicing: Tasks must have clear boundaries and appropriately scoped feature slices. Verify vertical slicing, contract-first slicing when frontend/backend can diverge, and risk-first ordering for uncertain work.
   - Buildability: Unambiguous instructions that prevent engineer blockages. Each task must include exact file paths, concrete steps, exact commands, and enough code or structure to avoid guesswork.
   - Template Compliance: Tasks must follow the plan's task template, include files to create/modify/test, avoid forbidden placeholders, and keep steps actionable. Do not require cosmetic formatting perfection; flag only issues that break execution.
   - Security Integration: Plan MUST explicitly reference or apply `secure-coding-standard` constraints for any tasks handling data, auth, or APIs.
   - Adaptive Workflow (CRITICAL): Check the `TDD Mode:` in the plan header. 
     - IF TDD is ENABLED: Tasks MUST follow the strict 5-step loop (Write test -> Fail -> Write code -> Pass -> Stage).
     - IF TDD is SKIPPED: Tasks MUST follow standard execution and verification steps WITHOUT enforcing test creation.
   - Code Review Checkpoint (CRITICAL): The absolute LAST task in the plan MUST be an instruction to invoke the `requesting-code-review` skill.
   - Git Workflow Compliance (CRITICAL): The plan MUST NOT contain any `git commit` commands. It MUST only instruct the execution agent to stage changes (`git add`).

   CALIBRATION_RULES:
   - ONLY flag critical issues that physically block implementation, violate the selected workflow (TDD vs Standard), contradict the spec or reference context, omit the final code review step, or break the Git workflow (e.g., premature commits).
   - IGNORE stylistic preferences, minor wording, or non-essential suggestions.
   - DEFAULT TO APPROVE only when there are zero blocking or compliance issues. Any Critical Blocker means Status MUST be "Issues Found".

   OUTPUT_FORMAT:
   Status: [Approved | Issues Found]
   Critical Blockers:
   - [Task X, Step Y or Section]: [Specific blocking/compliance issue]
     - Impact: [Why this blocks implementation, violates security, or risks building the wrong thing]
     - Actionable Fix: [Exact instruction to add/remove/change]
   Recommendations (Advisory, non-blocking):
   - [Suggestions for improvement]
   </reviewer_prompt>
</execution_workflow>
