# Interview 01: AI for Databases Questions

---

## Question 1: How would you build an AI-powered alert classification system for databases?

**What they're asking:** Can you design a real AI system for infrastructure?

**Answer:**

I'd build it in four layers:

**Layer 1: Data ingestion**
- Collect alert text from monitoring (Prometheus, CloudWatch, custom)
- Collect metrics from postgres_exporter and node_exporter
- Collect logs from PostgreSQL server logs
- Pipeline from Module 12: validate, deduplicate, align timestamps

**Layer 2: Classification**
- Text classifier: keyword matching + TF-IDF features for 6 categories (performance, storage, replication, connectivity, security, backup)
- Metric classifier: threshold rules per metric (cpu > 85% = performance, disk > 85% = storage)
- Late fusion: combine both predictions, boost confidence on agreement, reduce on disagreement
- Handle missing modalities: if metrics are unavailable, fall back to text-only with lower confidence cap

**Layer 3: Severity and routing**
- Score severity 0-100 based on: metric values, environment (prod > staging > dev), rate of change
- Assign priority P1-P4
- Route to correct team (DBA, SRE, security)
- Critical metric floor: disk > 95% on production is always P1, no override

**Layer 4: Safety and feedback**
- Output guardrails: validate category is in allowed list, confidence in range
- Action safety: low-risk (read-only queries) = auto-execute, high-risk = human approval
- DBA feedback loop: corrections become training data for next retrain
- Trust levels: senior DBA feedback is auto-approved, junior is quarantined

**DBA parallel:** This is the same architecture as a database monitoring stack. Data sources (pg_stat views), processing (ETL), rules (alerting conditions), and routing (PagerDuty). The AI replaces the static alert rules with learned patterns.

---

## Question 2: How do you ensure the AI never takes a dangerous action?

**What they're asking:** Do you understand the safety requirements?

**Answer:**

Four safety layers:

**1. Action classification (least privilege)**
Every action has a risk level:
- Low: read-only queries (pg_stat_activity), logging, classification
- Medium: send alert, kill idle query, VACUUM
- High: kill active query, change config, restart service
- Critical: failover, DROP, data modification

AI can only auto-execute LOW risk. Everything else needs approval.

**2. Hardcoded safety rules**
Some things the AI can NEVER do, regardless of confidence:
- Execute arbitrary SQL on production
- DROP any table or database
- Promote a standby without human confirmation
- Modify pg_hba.conf or postgresql.conf

These are hardcoded, not learned. No amount of training data changes them.

**3. Metric floor override**
Even if the AI's classification says "low priority," critical metrics force minimum severity:
- disk >= 95% on production = always P1
- CPU >= 98% on production = always P1
- replication lag > 10 minutes on production = always P1

Text can never override critical metrics.

**4. Audit trail**
Every AI decision is logged:
- What was the input?
- What did the AI decide?
- What action was taken or recommended?
- Did a human approve it?

If something goes wrong, you can trace exactly what happened.

**DBA parallel:** Same as database security. GRANT SELECT (read-only = low risk). GRANT INSERT/UPDATE (medium risk, needs approval). REVOKE DROP (never allowed for the AI). pgaudit logs everything.

---

## Question 3: How does the AI learn from DBA feedback?

**What they're asking:** Can you build a system that improves over time?

**Answer:**

The feedback loop has five steps:

**Step 1: Prediction**
AI classifies an alert: category=storage, confidence=85%, severity=P2.

**Step 2: DBA review**
DBA sees the prediction and either:
- Confirms (AI was right - positive signal)
- Corrects (AI was wrong - provides correct answer)
- Escalates (AI can't handle this - identifies a gap)

**Step 3: Quality control**
Not all feedback is equal:
- Senior DBA corrections go directly to training
- Junior DBA corrections are quarantined for review
- Anomalous patterns flagged (one DBA correcting 50% of reviews)
- Category-change corrections require a second reviewer

**Step 4: Retraining**
Weekly automated retraining:
- Add confirmed predictions + corrections to training data
- Run data quality checks (no poisoning, distribution looks reasonable)
- Train new model, compare against holdout set
- Deploy in shadow mode first, then promote if per-category accuracy holds

**Step 5: Monitoring**
Track accuracy per category over time:
- If performance accuracy drops from 92% to 80%, investigate
- If corrections spike for one category, check data quality
- If one DBA's corrections are consistently wrong, coach them

The key insight: the DBA's expertise becomes training data. When a senior DBA retires, their knowledge lives on in the model.

**DBA parallel:** Like pg_stat_statements. The more queries run, the better the statistics. The more alerts resolved, the better the AI. But you need to audit the data (like VACUUM for dead statistics).

---

## Question 4: How would you handle a situation where the AI starts giving wrong recommendations?

**What they're asking:** Can you handle AI failures in production?

**Answer:**

Incident response for AI failures follows the same five steps as any database incident:

**1. Contain (first 5 minutes)**
- Switch AI to "safe mode": read-only classification, no action recommendations
- Route all alerts to human DBA directly (bypass AI routing)
- Don't shut down the AI entirely - just disable actions

**2. Assess (next 30 minutes)**
- Check accuracy per category: which category degraded?
- Check recent retraining: was there a model update recently?
- Check data quality: was training data corrupted? (feedback poisoning?)
- Check metric pipeline: are metrics stale or wrong?

**3. Fix (next 1-4 hours)**
- If model update caused it: rollback to previous model version
- If training data poisoned: quarantine bad data, retrain from clean data
- If metric pipeline broken: fix pipeline, switch to text-only mode
- If a new pattern emerged: add training examples for the new pattern

**4. Recover (next 24 hours)**
- Deploy fixed model in shadow mode
- Compare against production traffic for 24 hours
- If shadow model accuracy > current: promote
- Gradually re-enable action recommendations

**5. Learn (next week)**
- Write post-mortem: what failed, why, how to prevent
- Add the failure scenario to test suite
- Update monitoring thresholds
- Review feedback quality controls

The critical difference from normal incidents: with AI, you can always fall back to human-only mode. The AI augments DBAs - it doesn't replace them. If the AI breaks, DBAs handle alerts the old way until it's fixed.

---

## Question 5: What metrics would you track for a database AI system?

**What they're asking:** Can you operate an AI system in production?

**Answer:**

Five categories of metrics:

**1. Classification accuracy**
- Overall accuracy (target: > 90%)
- Per-category accuracy (no category below 80%)
- Confusion matrix (which categories get confused?)
- Trend: is accuracy improving or degrading over time?

**2. Severity scoring**
- Priority accuracy (was the P1/P2/P3/P4 assignment correct?)
- False P1 rate (how often do we page unnecessarily?)
- Missed P1 rate (how often does a real emergency get deprioritized?) - this is the MOST IMPORTANT metric
- Mean time to detect actual P1 incidents

**3. Operational metrics**
- Prediction latency (< 100ms for real-time classification)
- Throughput (alerts classified per second)
- Model serving uptime (> 99.9%)
- Metric pipeline freshness (< 5 minutes old)

**4. Feedback quality**
- DBA correction rate per category (spike = problem)
- Inter-annotator agreement (DBAs should agree > 85% of the time)
- Training data distribution (balanced across categories?)
- Time between retrains (weekly is typical)

**5. Business impact**
- Mean time to resolve (MTTR) - should decrease with AI
- Alert noise ratio (false positive rate should decrease)
- DBA time saved per week
- Incidents prevented by predictive alerts

The most dangerous metric to ignore: **missed P1 rate**. A false P1 is annoying (unnecessary page). A missed P1 is catastrophic (database down, nobody knows). Optimize for catching every P1, even if it means a few false alarms.

**DBA parallel:** Same categories as database monitoring. Query accuracy = classification accuracy. pg_stat_statements latency = prediction latency. Replication lag = pipeline freshness. And always: missed critical incidents is the metric that matters most.
