---
name: root-cause-tracing
description: "Use when an error occurs deep in the call stack and the immediate failure location is not the root cause."
---

<HARD-GATE>
NEVER fix just where the error appears (symptom patching). You MUST trace the call chain backward to find the exact origin of the invalid data/state and fix it at the source.
</HARD-GATE>

<tracing_workflow>
Execute these steps strictly in order:

1. OBSERVE SYMPTOM: Note the exact error and its immediate execution point.
2. TRACE BACKWARD: Follow the call stack upward (caller → caller's parameter → original trigger). Identify exactly where the bad value (e.g., empty string, null, undefined) was first introduced.
3. FIX AT SOURCE (ADAPTIVE TDD): 
   - Check the `TDD Mode`.
   - IF Enabled: Write a failing test that targets the identified root cause specifically.
   - IF Skipped: Apply the fix directly. HOWEVER, if the root cause involves AuthN, AuthZ, or bypassing security controls, you MUST write a failing test to prove the vulnerability before fixing it.
   - Apply the fix strictly at the original trigger point.
4. ADD DEFENSE: Add validation at boundary layers to make the bug structurally impossible in the future. Ensure this validation strictly adheres to the `secure-coding-standard` (Reference: `./defense-in-depth.md`).
5. CLEANUP & STAGE (CRITICAL GATE):
   - You MUST remove ALL diagnostic logs (`console.error`, `DEBUG TRACE`, etc.) injected during the investigation.
   - Invoke `verification-before-completion` to ensure tests pass with a clean output.
   - ONLY stage the final, cleaned files (`git add <files>`). DO NOT run `git commit`. 
   - Inform the orchestrator/user that the fix is STAGED and ready for the `requesting-code-review` skill.
</tracing_workflow>

<instrumentation_rules>
If manual tracing is impossible, inject diagnostic logging EXACTLY BEFORE the failing operation:
- Use the stack's test-visible diagnostic channel. Examples: JS/TS `console.error`, .NET `Console.Error.WriteLine` or test output helpers, Python `print(..., file=sys.stderr)`.
- Capture the full stack/call chain using the stack-native mechanism (`new Error().stack`, `Environment.StackTrace`, `traceback.format_stack()`).
- Include sanitized environment context such as working directory, test name, environment name, and relevant non-secret variables.
- STRICT RULE: Never log tokens, credentials, PII, raw request bodies, or sensitive payloads. These diagnostics are temporary and MUST be removed in Step 5 before staging.
</instrumentation_rules>

<test_pollution_isolation>
If a test pollutes the environment but the exact culprit is unknown, do not guess. Run the bisection script:
- Helper scripts live beside this skill and are npm-test oriented.
- **Linux/macOS:** `bash .openskills/skills/systematic-debugging/find-polluter.sh <target-path> <test-pattern>`
- **Windows:** `.openskills\skills\systematic-debugging\find-polluter.cmd <target-path> <test-pattern>`
- For .NET or Python tests, use the same bisection approach with the stack's runner (`dotnet test --filter`, `pytest`, etc.) instead of blindly running the npm helper.
Once the polluter is found, apply the `tracing_workflow` to fix it, clean up, and stage the result.
</test_pollution_isolation>
