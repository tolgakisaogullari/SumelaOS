---
name: context-handoff
description: "Use when context compaction warnings appear, after 8+ major tool sequences, after 3+ large file reads plus 2+ review cycles, when a sprint task closes mid-session with more work pending, or when the user asks for a handoff prompt, says 'context doldu mu', 'yeni session', 'handoff hazırla'."
---

<purpose>
Long development sessions accumulate context — plan files, tool outputs, review diffs, logs. When context approaches capacity, raw compression loses critical task state. This skill protects against that loss by creating a durable session-summary/query-write-back artifact in the Second Brain, then generating a compact handoff prompt that points to it.

1. Detecting context pressure early — not at the wall.
2. Choosing the right protocol: clean finish vs. checkpoint park.
3. Updating the Second Brain surfaces that actually changed so the next session starts with accurate state.
4. Running /evolve pre-check so learning signals aren't lost across session boundaries.
5. Generating a handoff prompt the next agent can execute without rereading the entire session history.

**Core invariant:** The next agent must be able to continue exactly where this session stopped — no reconstruction, no guesswork.
</purpose>

<activation>
EAGER — loaded at session start. Context monitoring must be active from the first user turn because pressure builds gradually and the ideal stopping point appears before the crisis point, not at it.
</activation>

<trigger_conditions>
Activate the handoff-assessment workflow when ANY of these conditions are true:

1. **System signal:** Context compaction warnings appear, or significant prior message compression is observed.
2. **Task-count heuristic:** You have executed 8+ major tool call sequences (each task counts as one sequence) in the current session.
3. **Volume heuristic:** The session has involved 3+ full reads of large files (>200 lines) AND 2+ code-review cycles.
4. **Sprint milestone heuristic:** A sprint task is marked complete and the remaining task count suggests 2+ tasks still need to be done this session.
5. **Explicit user trigger:** User says "context handoff", "handoff prompt hazırla", "yeni session'a geçelim", "context doldu mu?", "bırak yeni session'da devam edelim".

**Rule:** Activate the assessment — do NOT interrupt the user mid-task. Always complete the current smallest meaningful unit first, THEN assess.
</trigger_conditions>

<assessment_workflow>
After completing the current task unit, when trigger conditions are met:

1. **Assess current state:**
   - Is there an active sprint plan? (Check `docs/second-brain/artifacts/plans/` if not in context.)
     - **If the sprint plan or recent session context is missing from working memory, run the four-tier decision tree before proceeding:** `python scripts/query-qdrant.py "<topic>" --limit 3` for session summaries (Tier 1), then `_SEARCH_INDEX.md` for wiki pages (Tier 3). Do NOT rely solely on manual file reads for historical context.
   - Is the current task FULLY DONE or IN PROGRESS?
   - Did the active sprint/project state change? If yes, is `wiki/active-project-context.md` up to date? If no, the session summary + `_SEARCH_INDEX.md` update may be the correct persistent artifact.
   - Run `(Select-String -Path docs/second-brain/wiki/_IMPROVEMENT_QUEUE.md -Pattern "status: pending").Count (PowerShell) or grep -c (bash)` to get the pending count — do NOT read the full file.

2. **Choose protocol:**
   - Current task is FULLY COMPLETE → **Protocol A**
   - Current task is IN PROGRESS → **Protocol B**

3. **Execute the chosen protocol.**

4. **Present handoff prompt to user and ask for confirmation.**
</assessment_workflow>

<protocol_a>
## Protocol A — Task Complete, Context Low

Use when: The current task is fully finished and verified.

### Steps

**Step 1 — Second Brain Update (MANDATORY):**
- If the active sprint/project state changed, update `wiki/active-project-context.md`:
  - Mark the completed task as done in the sprint section.
  - Update sprint progress counters.
- If this was a maintenance/audit/session-summary-only handoff with no active sprint state change, do not force `active-project-context.md`; preserve the state in the session summary and `_SEARCH_INDEX.md`.
- If a real loggable operation occurred, append the matching entry to `_LOG.md` (`code-commit`, `decision`, `evolve`, `migration`, etc.). Do not create a `_LOG.md` entry solely because a handoff prompt was generated.
- **Critical:** The next session's eager-load reads `active-project-context.md` first, then index/search surfaces. Stale active state is dangerous; unnecessary active-context churn is also dangerous.

**Step 2 — Evolve Check:**
- Run `(Select-String -Path docs/second-brain/wiki/_IMPROVEMENT_QUEUE.md -Pattern "status: pending").Count (PowerShell) or grep -c (bash)` — do NOT read the full file.
- If count > 0, ask the user (Turkish):
  > *"Handoff öncesinde {N} pending /evolve önerisi var. Şimdi hızlıca review etmek ister misin, yoksa handoff prompt'a not olarak ekleyeyim mi?"*
- If user says **şimdi**: execute `/evolve` workflow (self-improvement-curator skill).
- If user says **sonra**: note the pending count in the handoff prompt.
- **Timing constraint:** If /evolve review would consume too much remaining context, skip it and note it in handoff prompt. Never sacrifice handoff quality for evolve completeness.

**Step 3 — Session Summary (MANDATORY):**
- Create a session summary file following `<session_summary_protocol>` below.
- This persists the session's conversational context as a searchable wiki page.
- The handoff prompt will reference this summary file.
- Immediately after creating the summary, execute the applicable `<session_memory_ingestion>` steps: always index the session summary, and run code-graph/wiki memory maintenance only when the session changed code or other memory-sync inputs. **Relay the structured report output to the user in Turkish**.

**Step 4 — Generate and present handoff prompt** using `<handoff_template>` below.
</protocol_a>

<protocol_b>
## Protocol B — Task In Progress, Context Low

Use when: You are mid-task and context is running low.

### Steps

**Step 1 — Find a clean stopping point (CRITICAL):**
- Complete the **smallest meaningful compilable unit** you are currently in:
  - Finish the method body
  - Finish the file you are editing
  - Finish the test class (even if not all tests are written)
  - Finish the migration file
- **NEVER stop** in the middle of a method, a partial file edit, a half-written test, or an open transaction.
- If you are mid-refactor: bring the codebase to a state where it compiles, even if incomplete. Leave TODOs in comments.
- Stage completed changes only when the active workflow or user explicitly expects staged output. Otherwise leave them unstaged and document the exact `git status --short` state in the handoff.

**Step 2 — Mark CHECKPOINT in the plan file:**
- Open the active plan file under `docs/second-brain/artifacts/plans/`.
- Under the current in-progress task, append a checkpoint block:
  ```markdown
  > **[CHECKPOINT YYYY-MM-DD]:** <What was completed in this session — be specific (file names, method names).>  
  > **Next step:** <Exactly where to continue — file path, method name, test name, or migration step.>
  ```
- This checkpoint is the contract between sessions. Precision matters: "Next step: Add `IPaymentProcessor` registration to `Program.cs` line ~85, after `AddScoped<IOrderService>`" is good. "Continue implementation" is not.

**Step 3 — Second Brain Update (MANDATORY):**
- If the checkpoint changes active sprint/project state, update `wiki/active-project-context.md`:
  - Mark the task as `🔄 IN PROGRESS (checkpoint reached)`.
  - Add the checkpoint summary to the active sprint section.
- If this is a maintenance/audit checkpoint rather than active sprint execution, preserve the checkpoint in the plan/session summary and `_SEARCH_INDEX.md`; do not invent sprint state.
- Append an entry to `_LOG.md` only if a real loggable operation occurred. Staging alone is not a `code-commit`.

**Step 4 — Evolve Check:**
- Same as Protocol A Step 2.

**Step 5 — Session Summary (MANDATORY):**
- Same as Protocol A Step 3. Create session summary following `<session_summary_protocol>` below.
- Immediately after creating the summary, execute the applicable `<session_memory_ingestion>` steps: always index the session summary, and run code-graph/wiki memory maintenance only when the session changed code or other memory-sync inputs. **Relay the structured report output to the user in Turkish**.

**Step 6 — Generate and present handoff prompt** using `<handoff_template>` below.
- The "Sıradaki Görev" section MUST include the full checkpoint detail so the next agent continues from exactly where you stopped.
</protocol_b>

<session_summary_protocol>
## Session Summary Generation Protocol

This protocol creates a structured wiki page that persists the session's conversational context. In Karpathy LLM Wiki terms, this is the session-level query write-back artifact: future sessions answer "what did we discuss last time?" through `_SEARCH_INDEX.md`, Obsidian links, and optional Qdrant ingestion.

### When to create
- ALWAYS during context-handoff (Protocol A Step 3, Protocol B Step 5).
- OPTIONALLY when the user explicitly asks to save a session summary mid-session.

### File location
`docs/second-brain/wiki/session-summaries/YYYY-MM-DD-<topic>.md`

### Content extraction
From the current session context, extract:
1. **Topics discussed** — What subjects came up? (2-5 bullet points)
2. **Decisions made** — Any architectural, design, or workflow decisions (with rationale)
3. **Work completed** — Tasks finished, commits made, files changed
4. **Open questions** — Unresolved items for next session
5. **Related wiki pages** — Cross-links to existing wiki pages touched or referenced

### Steps
1. Read `_SCHEMA.md` Session Summary template (if not already in context).
2. Create the file at `wiki/session-summaries/YYYY-MM-DD-<topic>.md` using the template.
3. Update `_SEARCH_INDEX.md` with a new row for the session summary.
4. Update `_INDEX.md` Session Summaries section if this is the first session summary or a significant milestone.
5. Append to `_LOG.md` only if an actual loggable operation occurred. The session summary itself is usually the durable record; do not add a separate log entry just to say a handoff happened.

### Naming convention
- `<topic>` = primary activity of the session in kebab-case
- Examples: `memory-architecture-review`, `sprint-10-hardening`, `auth-refactor-debugging`
- If multiple unrelated topics: use the dominant one

### Token budget
Session summaries should be **concise** — 200-400 words max. They are a pointer to what happened, not a transcript.
</session_summary_protocol>

<session_memory_ingestion>
## Session Memory Ingestion (v2.2) — ROUTED AUTOMATION + USER REPORT

Context-handoff sırasında agent manuel karar yükünü kullanıcıya atmadan aşağıdaki uygun adımları çalıştırır ve **çıktıları kullanıcıya Türkçe özet olarak sunar**:

1. **Session Özeti Oluştur**
   - Session'ın ana konusunu, kararlarını, açık sorularını özetle
   - Format: `wiki/session-summaries/YYYY-MM-DD-topic.md`

2. **Qdrant'a Otomatik Indexle**
   ```bash
   python scripts/session-ingest.py docs/second-brain/wiki/session-summaries/YYYY-MM-DD-topic.md
   ```
   Bu script:
   - Markdown'ı chunk'lar (512 token, 50 overlap)
   - Ollama `qwen3-embedding:0.6b` ile embedding üretir
   - Qdrant `chat_history`'e otomatik upsert eder
   - Qdrant down ise sadece markdown summary kalır; retry gerekmez
   - **Çıktısı:** `SESSION INGEST REPORT` bloğu basar

   **Agent talimatı:** Script çalıştıktan sonra stdout'taki `SESSION INGEST REPORT` bloğunu oku ve kullanıcıya şu formatta Türkçe özet sun:
   > "Session belleği işlendi. {chunk sayısı} parçaya bölünüp Qdrant'a {'kaydedildi' | 'kaydedilemedi (markdown yedek olarak kalıyor)'}."

3. **Graphify + Qdrant Bakımı (Koşullu — Code/Memory Sync Sonu)**
   ```bash
   python scripts/auto-update-memory.py
   ```
   **Ne zaman çalışır:**
   - Code changes landed, a branch finish/code-commit occurred, or Graphify call graph can be stale.
   - Wiki sync inputs changed in a way that `sync-graphify-to-obsidian.py` must reflect.
   - The user explicitly requests memory maintenance or Second Brain health repair.

   **Ne zaman çalışmaz:**
   - Pure handoff prompt generation.
   - Session-summary-only maintenance/audit work where `_SEARCH_INDEX.md` already records the durable context.
   - Cases where running it would create misleading `_LOG.md` churn without a real code/wiki sync operation.

   Bu script:
   - `graphify update .` çalıştırır (kod graph'ı günceller)
   - `sync-graphify-to-obsidian.py` ile wiki'yi senkronize eder
   - Qdrant health check yapar
   - Gerektiğinde `_LOG.md`'ye gerçek bakım/sync sonucunu yazar
   - **Çıktısı:** `MEMORY UPDATE REPORT` bloğu basar

   **Agent talimatı:** Script çalıştıktan sonra stdout'taki `MEMORY UPDATE REPORT` bloğunu oku ve kullanıcıya şu formatta Türkçe özet sun:
   > "Bellek bakımı tamamlandı. Graphify kod graph'ı {'güncellendi' | 'başarısız oldu'}, wiki senkronizasyonu {'tamam' | 'hatalı'}, Qdrant {'ulaşılabilir' | 'ulaşılamıyor'}."
   Eğer koşullar oluşmadığı için script çalıştırılmadıysa, handoff'ta kısa ve açık yaz: "Graphify/wiki memory maintenance çalıştırılmadı; bu handoff yalnızca session summary + search index güncelledi."

**Qdrant Query Tool — Session-to-Session Bridge:**
Session summary'ler Qdrant'a indexlendikten sonra, bir sonraki session bu geçmişe `python scripts/query-qdrant.py "<soru>" --limit 3` ile semantic search yaparak erişebilir. Bu, REASONING AID workflow'unun Tier 1'ini oluşturur.

**Kural:** Kullanıcıdan asla "Graphify/Qdrant güncelleyeyim mi?" diye sorulmaz. Session summary ingestion her handoff'ta çalışır. `auto-update-memory.py` ise yalnızca yukarıdaki koşullar oluştuğunda çalışır; gereksiz çalıştırılıp `_LOG.md` veya wiki yüzeylerinde sahte bakım izi üretmemelidir. Hata olursa kullanıcıya bildirilir; başarı veya bilinçli skip durumunda da agent kısa bir Türkçe özet rapor sunmalıdır.
</session_memory_ingestion>

<handoff_template>
## Handoff Prompt Template

Present the filled template inside a fenced code block so the user can copy-paste it directly into a new session.

````
@.openskills/superpowers-agent-mode-prompt.md

## Session Handoff — {DATE}

### Proje & Branch
- Branch: `{branch-name}`
- Worktree: `{worktree-path}` (veya "ana repo, worktree yok")
- Plan / Artifact: [{plan-file-name}](docs/second-brain/artifacts/plans/{plan-file.md}) veya `{none - maintenance/session summary only}`

### Sprint Özeti
- Sprint: {sprint-id veya feature-adi}
- Toplam task: {N}
- Tamamlanan: {M} task ✅
- Kalan: {N-M} task

### Tamamlanan Tasklar (Bu Session)
{For each task completed in this session:}
- ✅ T{N}: {task-adi} — {commit-hash veya "staged"}

### 🔴 Devam Noktası
**T{N}: {task-adi}**

{Full task description copied from the plan file — do NOT summarize, copy verbatim so the next agent has full intent context.}

{Protocol B only — add the checkpoint block:}
> **[CHECKPOINT {DATE}]:** {What was done.}  
> **Next step:** {Exactly where to continue.}

### Bekleyen Kararlar / Blocker'lar
{List open decisions or blockers, or write "Yok."}

### Second Brain Durumu
- `active-project-context.md`: {Güncellendi ✅ | Değişmedi - aktif state değişmedi}
- Session summary: `{session-summary}`
- `/evolve` pending: {N önerim var — session başında hatırlatılacak} veya {Temiz ✅}

### Uncommitted / Staged Changes
{Run `git status` summary here, or write "Yok — tüm değişiklikler committed."}
````

### Template filling rules:
- `{DATE}` → today's date in YYYY-MM-DD format.
- `{branch-name}` → current git branch (run `git branch --show-current` if not known).
- Plan / Artifact → use the active plan when one exists; otherwise reference the maintenance artifact or session-summary path.
- Task description → copy verbatim from plan file when one exists; otherwise write `N/A - maintenance/session-summary handoff`.
- Checkpoint → exact file/method/line reference, not vague direction.
- `/evolve pending` → actual count from `(Select-String -Path docs/second-brain/wiki/_IMPROVEMENT_QUEUE.md -Pattern "status: pending").Count (PowerShell) or grep -c (bash)`.
- `{session-summary}` → path to the session summary created in Step 3/5.
- Staged changes → actual `git status --short` output or a concise summary.
</handoff_template>

<safety_invariants>
1. **Compilable state required.** Never end a session with a broken build. If Protocol B, ensure the partial implementation compiles before stopping.
2. **Second Brain update is non-negotiable.** A handoff must update the correct durable surface: `active-project-context.md` for active state changes, session summary + `_SEARCH_INDEX.md` for conversational/query write-back context.
3. **Never auto-terminate.** Always ask the user. They may want to push through, or they may need the handoff for a different reason.
4. **Document staged changes.** Uncommitted staged changes must be explicitly noted in the handoff prompt — the next agent needs to know what state git is in.
5. **Evolve before handoff (best-effort).** Try to handle /evolve first; if context is too tight, at minimum note the pending count in the handoff prompt.
6. **Checkpoint precision.** A vague checkpoint ("continue the service implementation") is worse than none. If you cannot be precise, describe the exact file state and what the next logical step is.
</safety_invariants>

<user_communication>
All user-facing text is in Turkish per project identity rules.

**When presenting the handoff:**

*Protocol A:*
> "Context dolmak üzere. Son task tamamlandı ✅. Second Brain güncellendi. Bir sonraki session için handoff prompt:"

*Protocol B:*
> "Context dolmak üzere. T{N} task'ını güvenli bir noktada bıraktım — plan dosyasına checkpoint eklendi. Second Brain güncellendi. Bir sonraki session için handoff prompt:"

Then present the filled template in a code block, followed by:
> "Bu prompt'u yeni bir session'da ilk mesaj olarak gönderebilirsin."
</user_communication>
