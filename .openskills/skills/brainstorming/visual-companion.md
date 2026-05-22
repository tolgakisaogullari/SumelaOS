---
name: visual-companion-guide
description: "MANDATORY rules for using the browser-based visual companion. Generates interactive mockups and strictly presents Deep Options (Trade-offs, Pros/Cons, Security Impact) alongside the visuals."
---

<usage_criteria>
- USE BROWSER: UI mockups, architecture diagrams, complex visual comparisons, structural layouts.
- USE TERMINAL: Logic, backend API design, scope, conceptual choices, secure-coding-standard evaluations.
</usage_criteria>

<server_management>
Platform-adaptive commands (detect OS before executing):

**Linux/macOS:**
1. START: `.openskills/skills/brainstorming/scripts/start-server.sh --project-dir <path>`
   (Note: Use `run_in_background: true` if your environment blocks tool calls).
2. Save `$SCREEN_DIR` from the startup JSON (or read `$SCREEN_DIR/.server-info`).
3. STOP: `.openskills/skills/brainstorming/scripts/stop-server.sh $SCREEN_DIR`

**Windows (cmd.exe):**
1. START: `.openskills\skills\brainstorming\scripts\start-server.cmd --project-dir <path>`
2. Save `%SCREEN_DIR%` from the startup JSON (or read `%SCREEN_DIR%\.server-info`).
3. STOP: `.openskills\skills\brainstorming\scripts\stop-server.cmd %SCREEN_DIR%`
</server_management>

<execution_loop>
Execute these steps strictly in order:

1. WRITE HTML FRAGMENT: Use the available file-write tool (NEVER cat/heredoc) to create a new file in `$SCREEN_DIR`.
   - **SERVER HEALTH CHECK (MANDATORY):** Before each write, verify `$SCREEN_DIR/.server-info` exists. If it is missing OR `$SCREEN_DIR/.server-stopped` exists, the server has shut down — restart via `start-server.{sh,cmd}` before continuing. The server auto-exits after 30 minutes of inactivity OR if the owner process dies.
   - Write ONLY fragments (e.g., `<h2>...</h2>`). DO NOT write `<html>`, `<head>`, or CSS. The server auto-wraps it.
   - Use semantic, versioned filenames (`layout-v1.html`). NEVER overwrite or reuse filenames.
   - CRITICAL DESIGN RULE: You MUST utilize the `<div class="pros-cons">` class for every option you draw. Never present a visual choice without explaining its technical, UX, and **security trade-offs** on the screen.

2. NOTIFY USER (RICH TERMINAL COMPANION): 
   Share the URL in the terminal, but DO NOT just say "Here is the link". You MUST provide a "Deep Options" summary in the terminal alongside the link:
   "The visual mockup is ready at [URL]. 
   Here is the technical context for what you are seeing:
   - **Option A [Name]:** [Why did I draw this? Best for X scenario]. **Security/Privacy:** [Impact based on secure-coding-standard].
   - **Option B [Name]:** [Why did I draw this? Best for Y scenario]. **Security/Privacy:** [Impact based on secure-coding-standard].
   Please review the browser and click your choice, or reply here in the terminal."
   End turn and wait.

3. READ FEEDBACK: Next turn, read `$SCREEN_DIR/.events` (JSONL format) for click interactions. Merge this context with the user's terminal messages.

4. ITERATE OR HANDOFF: 
   - If visual iteration is needed (user wants changes), write `layout-v2.html` and loop back to Step 2.
   - If the visual decision is finalized, you MUST clear the screen by writing a `waiting.html` containing:
     `<div style="display:flex;align-items:center;justify-content:center;min-height:60vh"><p class="subtitle">Visuals finalized. Continuing in terminal...</p></div>`
   - CRITICAL HANDOFF: Explicitly announce in the terminal: "Visual design approved. Returning to the Brainstorming workflow." (This ensures a seamless transition back to `brainstorming` Step 3 or 4).
</execution_loop>

<available_css_classes>
Use these built-in classes in your HTML fragments to ensure high-quality presentation:
- Interactive Options: `<div class="options" [data-multiselect]>` containing `<div class="option" data-choice="a" onclick="toggleSelect(this)">`
- Visual Cards: `<div class="cards">` containing `<div class="card" data-choice="design1" onclick="toggleSelect(this)">`
- Layouts: `<div class="mockup">`, `<div class="split">` (side-by-side)
- Content: `<div class="pros-cons">` (MANDATORY FOR CHOICES), `.mock-nav`, `.mock-sidebar`, `.mock-button`, `.mock-input`
- Typography: `h2`, `h3`, `.subtitle`, `.section`, `.label`
</available_css_classes>

<design_rules>
- Scale fidelity to the question (wireframes vs polished).
- Max 2-4 options per screen to avoid cognitive overload.
- Explicitly explain the core question/dilemma at the top of the HTML screen (e.g., `<h2>Choose Navigation Architecture</h2>`).
- Never present a visual without its corresponding technical context.
- **Security UX:** If the mockup involves authentication, forms, or sensitive data, visually represent secure states and explicitly mention the security implications in the UI's context.
</design_rules>

<cleanup>
- STOP: `stop-server.{sh,cmd} $SCREEN_DIR` when the brainstorming session ends.
- When `--project-dir` was used at startup, mockups persist in the project-local brainstorm output directory reported by the startup JSON for later reference.
- `/tmp` sessions (no `--project-dir`) get deleted on stop.
- Reminder: add the reported project-local brainstorm output directory to `.gitignore` if persistent mockups are not desired in version control.
</cleanup>
