---
name: performance-optimization
description: "Use when performance requirements exist, a regression is suspected, or profiling reveals bottlenecks that need fixing."
---

<HARD-GATE>
NEVER optimize without measurement data. Optimization without profiling is guessing — and guessing adds complexity without improving what matters. Profile first, identify the actual bottleneck, fix it, measure again.
</HARD-GATE>

<optimization_workflow>
Execute in this exact order. Do NOT skip to Step 3 before completing Steps 1 and 2.

1. MEASURE — Establish a baseline with real, reproducible data.
   - Synthetic (controlled conditions, reproducible): DevTools Performance tab, Lighthouse, APM dashboards, load testing tools (k6, JMeter, etc.).
   - Real User Monitoring (actual conditions): web-vitals (frontend), production APM traces (backend).
   - **Both are required.** Synthetic finds the bottleneck. RUM validates the fix actually helped real users.
   - Stack-specific tooling lives in project rules. Examples: .NET → `dotnet-trace`, BenchmarkDotNet, EF Core query logging; Node → clinic.js, 0x; Python → cProfile, py-spy.

2. IDENTIFY — Find the actual bottleneck using symptoms as a guide:

   **What is slow?**
   ```
   First page load
   ├── Large bundle?           → Measure bundle size, check code splitting / lazy loading
   ├── Slow server response?   → Measure TTFB; profile backend queries and caching
   └── Render-blocking?        → Check network waterfall for CSS/JS blocking

   API / Backend
   ├── Single endpoint slow?   → Profile DB queries, check for N+1, missing indexes
   ├── All endpoints slow?     → Check connection pool, memory pressure, CPU saturation
   └── Intermittent slowness?  → Check lock contention, GC pauses, external dependency latency

   UI Interaction
   ├── Freezes on click?       → Profile main thread for long tasks (>50ms)
   ├── Input lag?              → Check re-renders, controlled component overhead
   └── Animation jank?         → Check layout thrashing, forced reflows
   ```

   **Backend bottleneck table:**
   | Symptom | Likely Cause | Investigation |
   |---------|-------------|---------------|
   | Slow API responses | N+1 queries, missing indexes | Enable DB query logging, review LINQ execution plans |
   | Memory growth | Unbounded caches, large payloads, missing `.AsNoTracking()` | Heap snapshot, memory profiler |
   | CPU spikes | Sync I/O blocking async threads, regex backtracking | CPU profiler, check for `.Result` / `.Wait()` |
   | High latency spikes | Lock contention, cold starts, GC pressure | APM traces, check Gen2 GC frequency |

   **Frontend bottleneck table:**
   | Symptom | Likely Cause | Investigation |
   |---------|-------------|---------------|
   | Slow LCP | Large images, render-blocking resources, slow TTFB | Network waterfall, image sizes |
   | High CLS | Images without dimensions, late-loading content | Layout shift attribution in DevTools |
   | Poor INP | Heavy JS on main thread, large DOM updates | Long Tasks in Performance trace |
   | Slow navigation | N+1 API fetches per route, no caching | Network tab, API waterfall |

3. FIX — Address ONLY the specific bottleneck identified in Step 2. Do NOT bundle unrelated optimizations.

   **N+1 Query Pattern (most common backend bottleneck):**
   - ORM: Use the framework's eager-loading mechanism (`.Include()` in EF Core, `include:` in Prisma, `joinedload` in SQLAlchemy) to fetch related data in a single query.
   - Raw SQL: Use JOINs or batched queries instead of queries inside loops.

   **Missing Indexes:**
   - Analyze slow-query logs. Add indexes on columns used in WHERE, ORDER BY, and JOIN clauses.

   **Read-Heavy Queries Without Tracking:**
   - Disable change tracking on read-only queries when the ORM supports it (EF Core: `.AsNoTracking()`; SQLAlchemy: `Session(expire_on_commit=False)` + detached objects). Eliminates change-tracking overhead.

   **Unbounded Data Fetching:**
   - Always paginate list endpoints. Never fetch all rows.
   - Apply pagination at the query level, not in memory.

   **Missing Caching:**
   - Cache frequently-read, rarely-changed data (e.g., config, reference data) with explicit TTL.
   - Use in-process cache for single-instance state, distributed cache (Redis, Memcached, etc.) for shared state.
   - Set `Cache-Control` headers on API responses that can be cached by clients.

   **Synchronous Blocking in Async Context:**
   - NEVER block on async work from synchronous code paths (e.g., `.Result`, `.Wait()`, `.GetAwaiter().GetResult()` in .NET; `asyncio.run()` inside an existing event loop in Python).
   - Fix: `await` all async calls; propagate cancellation tokens / signals.

   **Bundle Size / Code Splitting (Frontend):**
   - Use dynamic `import()` for heavy, rarely-used features.
   - Route-level code splitting via `lazy()` / `Suspense` (React).
   - Profile bundle before and after with a bundle analyzer.

   **Image Optimization (Frontend/Mobile):**
   - Serve correct dimensions. Never scale down large images in CSS.
   - Use modern formats (WebP/AVIF). Add `loading="lazy"` for below-the-fold images.
   - For LCP images: add `fetchpriority="high"`.

4. VERIFY — Measure again against the baseline from Step 1.
   - Confirm the specific metric improved (with numbers).
   - Confirm no regressions in other metrics.
   - Invoke `verification-before-completion` to ensure no behavioral regressions.

5. GUARD — Prevent the bottleneck from returning.
   - Add a performance test or benchmark (e.g., BenchmarkDotNet, k6 load test).
   - Add CI enforcement if a budget exists (bundle size check, Lighthouse CI).
   - Note any intentional trade-off in `wiki/tech-debt-and-known-issues.md` if deferred.
</optimization_workflow>

<performance_budgets>
Set budgets and enforce them in CI. Adjust per project, but these are sensible defaults:

| Metric | Target |
|--------|--------|
| API response time (p95) | < 200ms |
| API response time (p99) | < 500ms |
| JS bundle (initial, gzipped) | < 200KB |
| Time to Interactive | < 3.5s on 4G |
| Lighthouse Performance score | ≥ 90 |
| LCP | ≤ 2.5s |
| INP | ≤ 200ms |
| CLS | ≤ 0.1 |
</performance_budgets>

<common_rationalizations>
| Rationalization | Reality |
|---|---|
| "We'll optimize later" | Performance debt compounds. Fix obvious anti-patterns now, defer micro-optimizations. |
| "It's fast on my machine" | Your machine isn't the user's. Profile on representative hardware and networks. |
| "This optimization is obvious" | If you didn't measure, you don't know. Profile first — always. |
| "Users won't notice 100ms" | Research shows 100ms delays impact conversion rates. Users notice more than you think. |
| "The framework handles performance" | Frameworks prevent some issues. They can't fix N+1 queries or oversized bundles. |
| "We're using Redis, so it's fine" | Caching hides slow queries. Fix the query AND cache. |
</common_rationalizations>

<verification>
After any performance-related change:
- [ ] Before and after measurements exist (specific numbers, not impressions)
- [ ] The specific bottleneck is identified and addressed — not a guess
- [ ] No N+1 queries in new data fetching code
- [ ] All list endpoints are paginated
- [ ] Read-only DB queries skip change tracking where the ORM supports it
- [ ] No synchronous blocking calls in async code paths
- [ ] Bundle size hasn't increased significantly (if frontend work)
- [ ] Performance budget passes in CI (if configured)
- [ ] Existing tests still pass — optimization didn't break behavior
</verification>
