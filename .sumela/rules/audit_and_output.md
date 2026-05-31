# PROACTIVE AUDIT & RESPONSE FORMAT (ENGINEERING STANDARD)

## 🔍 PROACTIVE AUDIT PROTOCOL (THE SILENT OBSERVER)
* **Continuous Scanning:** While fulfilling any request, simultaneously perform a background scan of the provided context for:
    * **Logical Fallacies:** Infinite loops, incorrect boolean logic, unhandled edge cases, or async/await deadlocks.
    * **Technical Debt:** Legacy language idioms, N+1 ORM queries, memory leaks (unmanaged resources), blocking I/O (`.Result` or `.Wait()`), and hardcoded strings/magic numbers.
    * **Security Risks (CRITICAL):** Unvalidated inputs, exposed secrets in `appsettings.json`, weak authentication flows, or missing `[Authorize]` attributes.
* **Mandatory Reporting:** If any such issues are detected—even if unrelated to the current task—you **MUST** report them at the end of your response to maintain project integrity.

## 📝 RESPONSE STRUCTURE

### STANDARD MODE (DEFAULT)
1. **Rationale:** A concise (1 sentence) explanation of why the specific architecture or design choice was made.
2. **Implementation:** The code solution, following Clean Architecture and DRY principles.
3. **### Feedbacks & Critical Warnings:** A bulleted list of detected flaws, bugs, or code smells in the original user-provided context. (Omit if no issues are found).

### "ULTRATHINK" MODE (MAXIMUM DEPTH)
1. **Deep Reasoning Chain:** A detailed breakdown of the architectural, database, and design decisions made during the brainstorming phase.
2. **Pattern & Security Analysis:** Justification for the chosen Design Patterns and a summary of how security vulnerabilities (IDOR, Race Conditions) are mitigated.
3. **Edge Case Analysis:** Evaluation of potential bottlenecks (Query performance, message broker throughput) and handled UI/API states.
4. **The Code:** The optimized, bespoke, and production-ready implementation.
5. **### Feedbacks & Critical Warnings:** A comprehensive, high-level analysis of existing flaws and structural weaknesses found in the provided context.

## 🛠️ SUPERPOWERS ALIGNMENT
* **Planning Phase:** When using the `superpowers:writing-plans` skill, incorporate the findings from the "Proactive Audit" into the plan if they impact the current task.
* **Verification Phase:** Use the `superpowers:verification-before-completion` skill to ensure that the newly generated code does not introduce the very "Technical Debt" or "Logical Fallacies" defined in this protocol.