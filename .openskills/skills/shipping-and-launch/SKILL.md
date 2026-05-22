---
name: shipping-and-launch
description: "Use when preparing to deploy to production — to run pre-launch checks, plan a staged rollout, set up monitoring, and document a rollback strategy."
---

<core_principle>
Every launch must be reversible, observable, and incremental.
The goal is not just to deploy — it's to deploy safely, with monitoring in place and a rollback plan ready before the first user is affected.
</core_principle>

<pre_launch_checklist>
Complete ALL sections before deploying. A failed item is a blocked deployment.

**Code Quality**
- [ ] All tests pass (unit, integration, e2e)
- [ ] Build succeeds with no errors or warnings
- [ ] Code reviewed and approved (`requesting-code-review` was executed)
- [ ] No debug statements or TODO items that must be resolved before launch
- [ ] Error handling covers expected failure modes

**Security** (cross-reference `secure-coding-standard`)
- [ ] No secrets in code or version control
- [ ] Dependency audit clean (`npm audit` / `pip-audit` / `dotnet list package --vulnerable` / equivalent) — no Critical/High issues
- [ ] Input validation on all user-facing endpoints
- [ ] Authentication and authorization checks in place
- [ ] Security headers configured (CSP, HSTS)
- [ ] Rate limiting on auth endpoints
- [ ] CORS restricted to known origins

**Performance** (cross-reference `performance-optimization`)
- [ ] No N+1 queries in critical paths
- [ ] All list endpoints paginated
- [ ] Read-only DB queries skip change tracking where the ORM supports it
- [ ] DB indexes in place for critical query paths
- [ ] Caching configured for high-frequency reads

**Infrastructure**
- [ ] All environment variables set in production environment
- [ ] Database migrations applied (or scripted and ready)
- [ ] Health check endpoint exists and responds 200
- [ ] Logging and error reporting active and verified
- [ ] SSL/TLS configured

**Documentation**
- [ ] Second Brain updated (via `finishing-a-development-branch` → Second Brain ingest)
- [ ] API documentation current (`api-registry.md` reflects new endpoints)
- [ ] ADRs written for any new architectural decisions
- [ ] Changelog or release notes updated
</pre_launch_checklist>

<feature_flag_strategy>
Ship behind feature flags to decouple deployment from release. Code enters production inactive; users are enabled incrementally.

**Lifecycle:**
```
1. DEPLOY with flag OFF     → Code is live but inactive. Zero user impact.
2. ENABLE for team/internal → Test in real production environment, real data.
3. CANARY (5% of users)     → Monitor for 24-48h. Compare metrics vs. baseline.
4. GRADUAL ROLLOUT          → 25% → 50% → 100%, monitoring at each step.
5. FULL ROLLOUT             → 100% of users. Monitor for 1 week.
6. CLEAN UP                 → Remove flag and dead code path within 2 weeks.
```

**Rules:**
- Every flag has a named owner and an expiration date — no orphaned flags
- Never nest feature flags (creates exponential test combinations)
- Always test BOTH flag states (on and off) in CI
- For mobile apps: flags are the primary rollback mechanism since you cannot force app updates
</feature_flag_strategy>

<staged_rollout>
### Rollout Sequence

```
1. Deploy to staging         → Full test suite + manual smoke test of critical flows
2. Deploy to production      → Feature flag OFF. Verify health check, check for new errors.
3. Enable for team           → 24-hour internal monitoring window.
4. Canary (5%)               → 24-48h window. Compare metrics vs. baseline (see thresholds below).
5. Gradual increase          → 25% → 50% → 100%. Same monitoring at each step.
6. Full rollout              → Monitor for 1 week. Remove feature flag.
```

### Rollout Decision Thresholds

At each canary/gradual step, use this table to decide: advance, hold, or roll back:

| Metric | Advance (green) | Hold and investigate (yellow) | Roll back (red) |
|--------|-----------------|-------------------------------|-----------------|
| Error rate | Within 10% of baseline | 10–100% above baseline | > 2× baseline |
| P95 latency | Within 20% of baseline | 20–50% above baseline | > 50% above baseline |
| Client errors | No new error types | New errors < 0.1% of sessions | New errors > 0.1% of sessions |
| Business metrics | Neutral or positive | Decline < 5% (may be noise) | Decline > 5% |

**Roll back immediately if any RED threshold is crossed.** Do not wait to investigate first — roll back, then investigate from a safe state.
</staged_rollout>

<rollback_strategy>
Document this BEFORE deploying. A rollback plan that doesn't exist before launch is useless.

```markdown
## Rollback Plan: [Feature/Release Name]

### Trigger Conditions (auto-rollback if ANY of these):
- Error rate > 2× baseline
- P95 latency > [X]ms
- User-reported issues spike
- Data integrity issues detected
- Security vulnerability discovered

### Rollback Steps:
**Option A — Feature flag (fastest: < 1 minute):**
1. Disable feature flag for all users
2. Verify: health check 200, error rate normal

**Option B — Redeploy previous version (< 5 minutes):**
1. `git revert <commit-sha> && git push`
2. Trigger deployment pipeline
3. Verify: health check 200, error rate normal

**Option C — Database rollback (< 15 minutes, use only if needed):**
1. Run down migration script
2. Verify data integrity
3. Redeploy previous version

### Communications:
- Notify team in [channel] immediately
- Update status page if user-facing impact > 5 minutes

### Post-Rollback:
- File incident report within 24h
- Add TD entry to `wiki/tech-debt-and-known-issues.md`
- Root cause analysis before re-deploying
```
</rollback_strategy>

<post_launch_verification>
In the first hour after deploying to production — do NOT leave the keyboard:

1. Health check endpoint returns 200
2. Error monitoring dashboard — no new error types
3. Latency dashboard — no regression vs. baseline
4. Test the critical user flow manually (happy path)
5. Verify logs are flowing and readable
6. Confirm rollback mechanism is ready (feature flag accessible, or pipeline can redeploy)
7. Watch business metrics for 30 minutes (conversion, engagement, session start)
</post_launch_verification>

<common_rationalizations>
| Rationalization | Reality |
|---|---|
| "It works in staging, it'll work in production" | Production has different data, scale, and edge cases. Monitor after every deploy. |
| "We don't need feature flags for this" | Every feature needs a kill switch. "Simple" changes break things too. |
| "Monitoring is overhead" | No monitoring means you discover problems from user complaints, not dashboards. |
| "We'll add monitoring later" | Add it before launch. You can't debug what you can't see. |
| "Rolling back is admitting failure" | Rolling back is responsible engineering. Shipping a broken feature is the failure. |
| "It's Friday, let's ship it" | Never. Deploy early in the week when the full team is available to respond. |
</common_rationalizations>

<red_flags>
- Deploying without a documented rollback plan
- No monitoring or error reporting active before deploying
- Big-bang release — everything at once, no staged rollout
- Feature flags with no owner or expiration date
- No one watching the deployment for the first hour
- Production configuration done from memory, not code
- "It's Friday afternoon, let's ship it"
</red_flags>
