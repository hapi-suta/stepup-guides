# Interview Prep: Operations at Scale and SRE

**Module 09: Operations at Scale and SRE**

---

## How to Use This Guide

These questions are organized by experience level. Start with the Junior questions and work your way up. For each question, practice answering out loud - interviews reward clear, structured verbal responses.

---

## Junior DBA / Entry-Level

### Q1: What is the difference between an SLI, an SLO, and an SLA?

**Strong answer:**

An SLI (Service Level Indicator) is a specific metric that measures service health. For a database, common SLIs are availability (can you connect?), latency (how fast are queries?), error rate (what percentage of transactions fail?), and replication lag.

An SLO (Service Level Objective) is a target you set for an SLI. For example, "99.9% availability" or "p95 latency under 100ms." The SLO is an internal engineering goal.

An SLA (Service Level Agreement) is a contract with customers that includes consequences (usually financial penalties) for missing targets. Your SLO should always be tighter than your SLA - if your SLA promises 99.9%, your internal SLO should be 99.95% to give you a buffer.

---

### Q2: What does "three nines" mean and how much downtime does it allow?

**Strong answer:**

"Three nines" means 99.9% availability. Per year, that allows approximately 8.76 hours of downtime, or about 43.8 minutes per month. Each additional nine is roughly 10x harder and more expensive to achieve. Going from 99.9% to 99.99% ("four nines") reduces allowed downtime from 8.76 hours to 52.56 minutes per year, which typically requires adding standby instances, connection pooling, automated failover, and dedicated on-call rotations.

---

### Q3: What is an error budget and how does it drive deployment decisions?

**Strong answer:**

An error budget is the amount of allowed unreliability calculated from your SLO. If your SLO is 99.9% per quarter, the error budget is 0.1% of the quarter, which equals about 130 minutes. When the budget is healthy (over 50% remaining), teams deploy freely. When it is low (under 25%), only critical fixes are deployed. When exhausted (0% remaining), there is a change freeze until the budget resets next quarter. The error budget mediates between the reliability team who wants fewer changes and the feature team who wants to ship faster - both accept the data-driven outcome.

---

### Q4: What is toil in the SRE context?

**Strong answer:**

Toil is work that is manual, repetitive, automatable, tactical, produces no enduring value, and scales linearly with the size of the fleet. Examples for a DBA: manually creating database users, checking disk space by hand, running backup verification queries. Google's SRE book recommends spending no more than 50% of time on toil. The other 50% should be engineering work that reduces future toil - like building automation scripts, self-healing alerts, and monitoring dashboards.

---

### Q5: What are the five cost optimization levers for Aurora PostgreSQL?

**Strong answer:**

1. **Storage pricing model** - switching from Standard to I/O-Optimized when I/O charges exceed 25% of total Aurora spend (zero per-I/O charge)
2. **Reserved Instances** - committing to 1 or 3-year terms for 30-60% savings on stable workloads
3. **Graviton migration** - moving from Intel (r6i) to ARM-based Graviton (r6g, r7g) for 10-20% better price/performance
4. **Aurora Serverless v2** - pay-per-ACU for variable workloads, ideal for dev/test environments
5. **Right-sizing** - matching instance class to actual CPU, memory, and connection utilization

---

## Senior DBA

### Q6: You are designing SLOs for a new Aurora PostgreSQL cluster backing a payments system. Walk me through your process.

**Strong answer:**

First, I would define the SLIs: availability (health check query every 10 seconds), latency (p95 and p99 from pg_stat_statements), error rate (rollbacks vs total transactions), and replication lag.

For targets, I start with three questions: What do users need? (the application has a 5-second timeout, so p99 under 500ms gives 10x headroom). What can the architecture deliver? (Aurora Multi-AZ with automated failover supports 99.95%). What is the cost curve? (going to 99.99% would require cross-region replication).

For a payments system, I would set the SLO tighter than the SLA - if the SLA is 99.9%, my internal SLO would be 99.95%. I would calculate the error budget (about 22 minutes per month at 99.95%), set CloudWatch alarms at SLO thresholds, and create an error budget policy that defines actions at healthy/warning/low/exhausted levels.

Finally, I would build a dashboard that shows SLO compliance and error budget consumption, reviewed weekly.

---

### Q7: Your Aurora cluster's costs tripled last month. Walk me through your diagnosis.

**Strong answer:**

I would check five areas systematically:

1. **CloudWatch Logs** - was `log_min_duration_statement` set to 0? At $0.50/GB ingested, verbose logging on a busy instance can add thousands per month.

2. **I/O charges** - check Cost Explorer for `Aurora:StorageIOUsage`. If I/O exceeds 25% of total Aurora spend, switching to I/O-Optimized eliminates per-I/O charges.

3. **Orphaned snapshots** - manual snapshots are not auto-deleted. Teams that take pre-migration snapshots and forget them accumulate storage charges.

4. **Log retention** - CloudWatch Logs default to "never expire." Terabytes of old logs stored indefinitely.

5. **Instance changes** - was the instance class changed? Did someone add readers? Check RDS Events for modifications.

I would also check for inactive replication slots consuming storage, and whether dev/test environments are running production-sized instances.

---

### Q8: Describe your on-call rotation design for a team of 6 DBAs managing 30 Aurora clusters.

**Strong answer:**

I would set up a weekly primary/secondary rotation. With 6 people, each DBA is primary once every 6 weeks and secondary once every 6 weeks - sustainable without burnout.

Key metrics I would track: pages per week per engineer (target under 5), false positive rate (under 10%), acknowledge time (under 5 minutes), and MTTR for SEV1 (under 30 minutes).

The escalation path: primary acknowledges within 5 minutes and uses runbooks. If not resolved in 15 minutes, escalate to secondary. If not resolved in 30 minutes, escalate to subject matter expert. For customer-visible impact, declare SEV1 and assign an Incident Commander.

I would also invest in runbook automation - every incident type that fires more than 3 times should have an automated diagnosis Lambda that runs before the DBA even looks at it. The DBA wakes up to an analysis, not a raw alert.

---

### Q9: What is the difference between a proximate cause and a root cause in a post-incident review?

**Strong answer:**

The proximate cause is the immediate trigger - "a DBA ran a command that caused a restart." The root cause is the systemic condition that allowed the failure - "the change management process has no pre-flight check that validates whether a parameter change requires a restart."

Fixing the proximate cause (tell the DBA to be more careful) only prevents that specific person from making that specific mistake. Fixing the root cause (automated pre-flight validation) prevents the entire class of failure for everyone, forever. Blameless postmortems focus on root causes because improving systems is more reliable than improving individual behavior.

---

### Q10: How would you automate the response to a connection storm on Aurora?

**Strong answer:**

The automation pipeline: CloudWatch alarm fires when DatabaseConnections exceeds 80% of max_connections for 2 consecutive minutes. EventBridge matches the alarm state change. Lambda function runs the runbook steps automatically.

The Lambda function connects to the database, queries pg_stat_activity to break down connections by user, state, and client address. It identifies idle-in-transaction sessions older than 5 minutes and terminates them (with a protected users list that never gets auto-terminated). It publishes a detailed report to SNS so the on-call DBA gets a diagnosis, not just an alert.

Safety guardrails: maximum 20 terminations per invocation (more suggests a systemic issue needing human review), 5-minute cooldown between runs, never terminate on reader instances, log every termination for audit.

---

## Principal / Staff Level

### Q11: How do you balance cost optimization with reliability? Give a concrete example where optimizing for cost could harm reliability.

**Strong answer:**

Cost optimization and reliability are often in tension. The classic example: right-sizing a production instance from db.r6g.xlarge to db.r6g.large saves 50% on compute, but if the smaller instance does not have enough memory for a full-table VACUUM FREEZE during a wraparound emergency, you have created a reliability risk that only manifests during the worst possible moment.

My approach: cost optimization decisions must pass through the SLO lens. I ask, "Does this change put any SLO at risk?" For right-sizing, I verify the smaller instance handles peak load AND worst-case operations (VACUUM, failover, connection storm). For Reserved Instances, I align with the engineering roadmap so we do not commit to capacity that will be decommissioned. For Serverless v2 on dev/test, there is minimal reliability risk because those environments are not customer-facing.

The quarterly cost review includes a reliability check for every proposed change. Cost savings that consume error budget are not savings - they are borrowing from reliability.

---

### Q12: You are building an SRE practice for a team of DBAs who have been working in a traditional reactive model. How do you drive the cultural change?

**Strong answer:**

I would start with measurement, not mandates. Cultural change fails when you dictate process; it succeeds when you make the current state visible.

Phase 1 (Month 1): Instrument everything. Deploy SLI collection, create an SLO dashboard, and start measuring toil. When the team sees "we spent 72% of our time on toil last month," the motivation to automate becomes self-evident.

Phase 2 (Month 2-3): Quick wins. Automate the highest-frequency, lowest-complexity toil task. When the team sees a task they used to do 12 times per month now runs automatically, the mindset shifts from "we fix things" to "we build things that fix themselves."

Phase 3 (Month 3-6): Error budgets. Introduce the error budget framework and use it to have a data-driven conversation with engineering leadership about deployment velocity. When the feature team sees that good incident management (fast MTTR) preserves their deployment velocity, they become allies in reliability work.

Phase 4 (Ongoing): Post-incident reviews. Run blameless PIRs for every SEV1/SEV2. Track action item completion rate. The PIR is where the team builds shared knowledge - every incident that teaches something makes the next one faster to resolve.

The key insight: SRE is not a tooling change. It is a mindset change. Tools enable the mindset, but the mindset must come first.

---

### Q13: How do you design a multi-account Aurora fleet management strategy for a company with 50+ clusters?

**Strong answer:**

At 50+ clusters, manual management is impossible. The strategy has four pillars:

**Standardization:** Every cluster uses a parameter group derived from a base template with environment-specific overrides. Parameters are version-controlled alongside infrastructure code. Drift detection runs daily and alerts when any cluster diverges from the template.

**Automation:** Lambda functions handle health checks (every 5 minutes), slow query detection (every 15 minutes), and incident response (event-driven). EventBridge rules connect CloudWatch alarms to Lambda functions. The DBA team builds and maintains the automation, not manual runbooks.

**Observability:** A centralized SLO dashboard shows every cluster's availability, latency, error rate, and error budget status. Custom CloudWatch metrics from Lambda functions feed into this dashboard. Weekly operational reviews use this dashboard to spot trends.

**Governance:** AWS Config rules enforce compliance (encryption, tags, backup retention, Multi-AZ). Cross-account IAM roles with MFA allow the DBA team to manage all clusters from a central account. Tag policies ensure cost allocation is accurate.

The team's role shifts from "operating 50 databases" to "operating the platform that operates 50 databases." Toil should stay under 30% for a fleet this size, with 70% spent on platform engineering.

---

### Q14: A SEV1 incident consumed 85% of the quarterly error budget. What do you do for the rest of the quarter?

**Strong answer:**

With only 15% of the budget remaining, we are in "LOW" status. The immediate actions:

1. Only critical security patches and P0 bug fixes get deployed. No feature deployments for the rest of the quarter.
2. Mandatory post-incident review within 48 hours with P1 action items due within one week.
3. Focus engineering time on completing action items that prevent recurrence.
4. Weekly reliability review with engineering leadership showing budget status and action item progress.
5. If any additional incident consumes the remaining budget, we enter a full change freeze.

For the longer term, I would analyze why a single incident consumed 85% of the budget. Was the SLO too aggressive? Was the MTTR too slow? Should we invest in automated remediation that would have recovered faster? If the architecture cannot support the current SLO (maybe we need a connection pooler or cross-region capability), I would propose adjusting the SLO to match what the architecture can reliably deliver.

The error budget forces an honest conversation: either invest in reliability to support the current SLO, or adjust the SLO to match the current investment level.

---

### Q15: How do you measure the ROI of SRE practices for a database team?

**Strong answer:**

I measure ROI across four dimensions:

**Incident reduction:** Track incident count, MTTD, and MTTR over quarters. If MTTR dropped from 30 minutes to 8 minutes after deploying automated runbooks, quantify the saved downtime in dollars (downtime cost per minute times minutes saved per incident times incidents per quarter).

**Toil reduction:** Track toil percentage quarterly. If the team went from 70% toil to 40% toil, that is 30% of the team's capacity freed for engineering work. Quantify this as FTE-equivalent hours redirected to high-value work.

**Cost avoidance:** Error budget-driven deployment velocity means fewer outages from bad deploys. Quantify the outages prevented by the change-freeze mechanism when budget was low.

**Direct cost savings:** Automated cost optimization (right-sizing, RI coverage, storage mode switching) has a direct dollar value. A quarterly cost review that finds $100K in savings pays for the SRE investment many times over.

The pitch to leadership: "Before SRE practices, we had 12 SEV1 incidents last year with average MTTR of 35 minutes. After, we had 4 SEV1s with average MTTR of 9 minutes. That is 380 fewer minutes of downtime, which at $5,000/minute of revenue impact, represents $1.9M in protected revenue."

---

### Q16: What is the relationship between chaos engineering and error budgets?

**Strong answer:**

Chaos engineering consumes error budget intentionally. Running a failover test might cause 30 seconds of downtime - that comes out of the quarterly budget. This is exactly the point: chaos experiments are an investment of error budget to discover weaknesses before they cause unplanned outages.

When the budget is healthy (over 50% remaining), chaos experiments are encouraged. They find weaknesses that, if left undiscovered, could cause a SEV1 that consumes the entire budget. When the budget is low, chaos experiments stop - you cannot afford the risk.

The key insight: a team that never runs chaos experiments will eventually have an unplanned incident that tests the same failure mode. The difference is that chaos experiments happen during business hours with the team prepared, while real incidents happen at 2 AM with no preparation. Investing 30 seconds of planned downtime to prevent 30 minutes of unplanned downtime is a 60x return on error budget.

---

## Scenario-Based Questions

### Q17: Your monitoring shows AuroraReplicaLag spiking to 45 seconds. Walk through your investigation.

**Strong answer:**

First, I check for long-running transactions on the writer. Long transactions prevent readers from replaying WAL, causing lag:

```sql
SELECT pid, usename, state, extract(epoch FROM now() - xact_start) AS txn_age
FROM pg_stat_activity WHERE xact_start IS NOT NULL
ORDER BY xact_start ASC LIMIT 10;
```

If I find a transaction running for 30+ minutes, that is likely the cause. I would check if it is a batch job or a stuck session, then either wait for it to complete or terminate it.

Second, I check write IOPS. A burst of writes (batch insert, schema migration) generates WAL faster than readers can apply it. This is typically transient and resolves once the burst completes.

Third, I check reader instance status. A reader that is restarting or undersized may fall behind. I verify the reader is in `available` state and check its CPU utilization.

Fourth, I check for replication slot issues. Inactive logical replication slots do not directly cause replica lag on Aurora, but they can indicate broader replication health issues.

The remediation depends on the root cause: terminate stuck transactions, reschedule batch jobs, or upgrade reader instance class if undersized.

---

### Q18: Your CFO asks you to cut the database budget by 40% in 90 days. How do you approach this?

**Strong answer:**

I would not start cutting. I would start measuring. Week 1: build a complete cost inventory of every cluster, instance class, storage mode, RI coverage, and utilization metrics.

Then I would apply the five levers in order of risk:

1. Immediate, zero-risk: Switch I/O-heavy clusters to I/O-Optimized storage (online, no downtime). Fix verbose logging and orphaned snapshots. Set CloudWatch log retention.

2. Low-risk: Purchase Reserved Instances for stable production workloads (30-60% savings). This requires capital commitment but no technical change.

3. Medium-risk: Right-size over-provisioned instances (test in staging first). Convert dev/test to Serverless v2.

4. Higher-risk: Migrate Intel instances to Graviton (requires Blue/Green deployment and testing).

I would present a phased plan to the CFO with estimated savings per action, timeline, and any reliability risks. I would not commit to 40% if the analysis shows 30% is the safe maximum - cutting too deep risks incidents that cost more than the savings.

---

## Tips for Interview Success

1. **Structure your answers:** Use "First... Second... Third..." to organize your response.
2. **Use concrete numbers:** "99.9% availability allows 43.8 minutes of downtime per month" is stronger than "high availability."
3. **Show the trade-off:** Every technical decision has a trade-off. Acknowledge it.
4. **Connect to business impact:** "This reduces MTTR from 30 minutes to 8 minutes, which at $5,000/minute means $110,000 in protected revenue per incident."
5. **Practice the Five Whys:** Interviewers love root cause analysis. Practice getting from symptom to systemic cause in 5 steps.
