# Interview 01: Capstone - Shipping AI Products

Five interview questions covering product shipping, AI operations, and production AI systems.

---

## Question 1: Designing an AI product from scratch

**Interviewer asks:**
"You're asked to build an AI-powered system that monitors database health and alerts DBAs when something is wrong. Walk me through how you'd design, build, and ship this product."

**What they're testing:** Can you think end-to-end about an AI product? Not just the model, but the entire system.

**Strong answer:**

```
I'd approach this in phases:

PHASE 1: PLAN
- Define the problem: DBAs get too many alerts, most are noise,
  critical ones get buried
- Define success metrics BEFORE building:
  - Classification accuracy > 90%
  - Zero missed P1 alerts (non-negotiable safety requirement)
  - Latency < 200ms per classification
  - DBA feedback on > 50% of alerts
- Choose architecture: late fusion (text + metrics), keyword
  classifier (interpretable, fast, works with small data)
- Identify risks: misclassifying P1 as P4, model drift,
  feedback poisoning

PHASE 2: BUILD
- Feature extraction: keyword counting for text, normalization
  for metrics
- Classifier: separate text and metric classifiers, late fusion
  to combine
- Safety: metric floor (critical metrics force P1 regardless of text)
- API: FastAPI with input validation, health checks
- Feedback loop: collect DBA corrections

PHASE 3: TEST
- Unit tests: each component in isolation
- Integration tests: full pipeline end-to-end
- Behavioral tests: specific safety scenarios
  (e.g., "routine disk check" with 99% disk = P1)
- Load tests: can it handle 60 alerts per minute?

PHASE 4: DEPLOY
- Containerize with Docker
- Health checks (healthy/degraded/unhealthy)
- Model versioning with rollback capability
- Monitoring: accuracy, latency, error rate, per-category breakdown

PHASE 5: OPERATE
- Monitor accuracy trends (not just current values)
- Detect drift (new vocabulary, changing patterns)
- Monthly retraining on production data
- Incident response runbook ready

The key insight: shipping isn't just the model. It's the model
plus monitoring plus safety plus feedback plus operations.
A model in a notebook isn't shipped. A model behind an API
with monitoring and rollback is shipped.
```

**DBA parallel:** This is like designing a production database cluster. You don't just install PostgreSQL. You design replication, backup strategy, monitoring, alerting, failover, and runbooks. Same discipline for AI products.

---

## Question 2: Handling AI safety in production

**Interviewer asks:**
"Your AI classifier recommends killing a long-running query. How do you make sure it doesn't accidentally kill a critical report generation query?"

**What they're testing:** Do you understand AI safety constraints? Can you implement safeguards?

**Strong answer:**

```
Multiple layers of safety:

LAYER 1: ACTION RISK LEVELS
Every action has a risk level:
  - Low risk: read-only queries (SELECT from pg_stat_activity)
  - Medium risk: session management (pg_cancel_backend)
  - High risk: destructive actions (pg_terminate_backend)
  - Critical risk: DDL or config changes

Only low-risk actions can auto-execute. Everything else
requires human approval.

LAYER 2: METRIC FLOOR
Critical metrics force high priority regardless of text:
  - CPU > 95% = P1 minimum
  - Disk > 95% = P1 minimum
This prevents text like "routine check" from downgrading a
real emergency.

LAYER 3: QUERY CLASSIFICATION BEFORE ACTION
Before recommending "kill this query," check:
  - Is it a SELECT or DML? (DML is higher risk)
  - How long has it been running? (context matters)
  - Is it from a known application user or a DBA?
  - Is it accessing critical tables?

LAYER 4: RATE LIMITING
Max 3 actions per minute. This prevents the AI from
rapid-fire killing queries during an alert storm.

LAYER 5: KILL SWITCH
Any DBA can hit the emergency stop:
  - All agents switch to "recommend only" mode
  - No actions execute without explicit approval
  - Alert sent to all team members
  - Requires senior DBA to re-enable

The principle: the AI should never be more dangerous than
having no AI at all. A missed classification is bad.
An AI that kills production queries is worse.
```

**DBA parallel:** This is exactly how you'd manage automated failover. You don't let Patroni auto-promote in every scenario. Some situations (split-brain risk, network partition) require human judgment. Same for AI actions.

---

## Question 3: Diagnosing accuracy degradation

**Interviewer asks:**
"Your AI product launched at 92% accuracy. Three months later, a DBA reports it's been giving wrong answers. You check and find accuracy is 71%. What happened and how do you fix it?"

**What they're testing:** Can you diagnose and fix AI-specific production issues?

**Strong answer:**

```
STEP 1: ASSESS THE DAMAGE
- Check per-category accuracy (don't just look at overall)
- Identify which categories degraded most
- Check if any P1 alerts were missed (safety first)
- Determine when the degradation started

STEP 2: IDENTIFY THE DRIFT TYPE
Three types of drift:

1. Vocabulary drift: new tools changed alert text
   Example: Patroni says "timeline diverged" instead of
   "replication lag"
   Detection: track unknown words in incoming alerts

2. Metric drift: new monitoring added different metric names
   Example: "patroni_lag_bytes" instead of "replication_lag_seconds"
   Detection: track unknown metric names

3. Distribution drift: alert mix changed
   Example: more replication alerts after HA deployment
   Detection: compare category distribution to training data

STEP 3: IMMEDIATE MITIGATION
- Roll back to last known good model (if one exists)
- Or: add the missing keywords manually (quick fix)
- Or: switch degraded categories to "low confidence" mode
  (flag for human review)

STEP 4: ROOT CAUSE FIX
- Collect DBA corrections from the last 3 months
- Update keyword lists with new vocabulary
- Update metric normalization ranges
- Retrain on production data (not just original training data)
- Run full test suite including behavioral tests
- Deploy only if accuracy improves (quality gate)

STEP 5: PREVENT RECURRENCE
- Add drift detection monitoring (vocabulary + accuracy trends)
- Alert when per-category accuracy drops below 80%
- Schedule monthly keyword reviews
- Track accuracy trends, not just current values
- Document what changed (Patroni deployment, pgBouncer upgrade)

The key lesson: AI accuracy isn't "set and forget."
Production data changes continuously. The model must keep up.
This is like database maintenance. You don't set up PostgreSQL
and never run ANALYZE again. autovacuum exists for a reason.
```

**DBA parallel:** This is like table statistics going stale. PostgreSQL query planner uses statistics to choose execution plans. If you never run ANALYZE, the statistics become wrong, and the planner makes bad choices. Same for AI - training data is like statistics. When they go stale, predictions go bad.

---

## Question 4: Testing an AI system

**Interviewer asks:**
"How do you test an AI classification system? What's different about testing AI compared to testing regular software?"

**What they're testing:** Do you understand the unique testing challenges for AI systems?

**Strong answer:**

```
AI testing has unique challenges regular software doesn't:

1. NON-DETERMINISTIC IN SOME CASES
Regular software: same input always gives same output
AI: confidence scores might vary, edge cases are ambiguous
Fix: test for acceptable RANGES, not exact values

2. NO SINGLE "CORRECT" ANSWER
Regular software: 2 + 2 must equal 4
AI: is "connection timeout due to high CPU" a performance
or connectivity issue? Reasonable people disagree.
Fix: test clear-cut cases. Accept ambiguity in edge cases.

3. SAFETY IS MORE IMPORTANT THAN ACCURACY
Regular software: a bug is a bug
AI: a misclassified P1 alert can cause an outage
Fix: behavioral tests for safety scenarios

My testing strategy has four layers:

UNIT TESTS
- Does the feature extractor count keywords correctly?
- Does the normalizer handle edge values (0, max, above max)?
- Does the severity scorer apply the metric floor?
These are standard software tests.

INTEGRATION TESTS
- Does the full pipeline classify a real alert correctly?
- Does the API endpoint return the right format?
- Does the feedback loop record corrections?
These test components working together.

BEHAVIORAL TESTS (AI-specific)
- "Silent Killer": misleading text + critical metrics = P1?
- "Noisy Neighbor": dev environment alert = low priority?
- "Cascade": multi-signal alert = high priority?
- "Contradicting Signals": text says X, metrics say Y?
These test SCENARIOS that matter to users.

LOAD TESTS
- Can it handle 60 alerts per minute?
- Is latency under 200ms at p95?
- Does memory stay stable over 5000 requests?
- Is the same input always classified the same way?

The most important test: the metric floor test.
If critical metrics don't force P1 regardless of text,
the entire product fails its primary safety requirement.
```

**DBA parallel:** Testing AI is like testing a database migration. You don't just check "did the ALTER TABLE run?" You test data integrity, query performance, application compatibility, rollback capability. Multiple layers because the stakes are high.

---

## Question 5: Operating AI in production

**Interviewer asks:**
"Your AI product is live. What do you monitor day-to-day, and how do you know if something is going wrong?"

**What they're testing:** Can you operate an AI system, not just build one?

**Strong answer:**

```
I monitor three layers:

LAYER 1: SYSTEM HEALTH (is the service running?)
- Request rate: alerts per minute
- Error rate: should be < 1% (alert at > 1%)
- Latency: p50, p95, p99 (alert if p95 > 200ms)
- Uptime: health check endpoint (load balancer uses this)
- Component status: classifier, database, metrics pipeline

This is standard SRE monitoring. Same as monitoring any API.

LAYER 2: AI QUALITY (is the AI making good predictions?)
- Overall accuracy: target > 90% (from DBA feedback)
- Per-category accuracy: each category > 80%
- Confidence distribution: too many low-confidence predictions?
- Priority distribution: sudden spike in P1s = alert storm or bug?
- Drift score: how many unknown words are appearing?

This is AI-specific. Regular APIs don't have "accuracy."

LAYER 3: BUSINESS IMPACT (is it helping DBAs?)
- DBA feedback rate: are DBAs reviewing classifications?
- Correction rate: how often are DBAs changing the category?
- Time to acknowledge: are P1 alerts being seen faster?
- False P1 rate: are DBAs getting paged unnecessarily?
- Missed P1 rate: MUST BE ZERO (non-negotiable)

This measures whether the product is actually useful.

RED FLAGS I watch for:
1. Accuracy trend downward (even if still above threshold)
2. One category's accuracy dropping faster than others
3. Spike in unknown words (new tool deployed?)
4. Confidence distribution shifting toward low-confidence
5. DBA feedback rate dropping (they stopped trusting the system)

When something goes wrong:
1. Detect: monitoring alerts fire
2. Assess: severity level, scope, safety impact
3. Mitigate: rollback model, enable recommend-only mode
4. Fix: root cause analysis, targeted fix
5. Postmortem: blameless review, action items

The goal: catch problems before DBAs notice them.
If a DBA tells you the AI is giving wrong answers,
your monitoring has already failed.
```

**DBA parallel:** This is exactly how you monitor a PostgreSQL cluster. Layer 1 = is the database running? (pg_isready). Layer 2 = is it performing well? (pg_stat_statements). Layer 3 = is it serving the business? (application metrics). Same three layers, same discipline.

---

## Summary

| Question | Core Concept | Key Insight |
|----------|-------------|-------------|
| Design from scratch | End-to-end product thinking | Shipping = model + monitoring + safety + feedback |
| AI safety | Safety constraints | AI should never be more dangerous than no AI |
| Accuracy degradation | Model drift | Production data changes; the model must keep up |
| Testing AI | Multi-layer testing | Behavioral tests for safety are more important than accuracy tests |
| Operating AI | Production monitoring | Three layers: system health, AI quality, business impact |
