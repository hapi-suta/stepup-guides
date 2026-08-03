# Concepts 01: SRE for Databases

**Module 09: Operations at Scale and SRE**
**Reading Time:** 25-30 minutes

---

## What is Site Reliability Engineering (SRE)?

Site Reliability Engineering is a discipline that applies software engineering practices to infrastructure and operations work. Google created the term and the practice, and it has since become the industry standard for running reliable services at scale.

For database administrators, SRE transforms the role from reactive problem-solver ("the database is down, fix it") to proactive reliability engineer ("our availability SLO is 99.95%, we have 22 minutes of error budget remaining this quarter, and we are deploying with confidence").

The core insight of SRE is that reliability is a feature - it can be measured, budgeted, and engineered just like performance or security.

---

## Traditional DBA vs Database Reliability Engineer (DBRE)

The shift from DBA to DBRE is not about changing your technical skills. It is about changing how you think about and measure your work.

| Traditional DBA | Database Reliability Engineer |
|----------------|------------------------------|
| "The database is up" | "The database is 99.95% available this quarter" |
| "I tuned this query manually" | "I built monitoring that detects slow queries automatically" |
| "We need zero downtime" | "We need 99.9% uptime - the 0.1% is our error budget" |
| "I fixed it when it broke" | "I run chaos experiments to find weaknesses proactively" |
| "I did 20 manual tasks today" | "I automated 18 tasks and spent 2 hours on engineering" |
| "Changes are risky - avoid them" | "Error budget determines how aggressively we deploy" |
| "I check everything manually" | "Autonomous diagnostics check the fleet every 5 minutes" |

---

## Service Level Indicators (SLIs)

An SLI is a specific, measurable metric that tells you whether your database service is healthy. SLIs are the raw data points you collect continuously.

### The Four Golden SLIs for Aurora PostgreSQL

**SLI 1: Availability**

Can clients connect to the database and execute queries?

Measurement: Run a health check query every 10 seconds from your monitoring system. Track successes and failures.

```sql
-- Simple availability probe
SELECT 1;
```

If this query succeeds within a defined timeout (for example, 1 second), the database is "available" for that check interval.

Formula:

```
Availability = (successful health checks) / (total health checks) x 100
```

On Aurora, you can also use the CloudWatch metric `DatabaseConnections` as a proxy. If connections drop to zero unexpectedly, availability is compromised.

**SLI 2: Latency**

How long do queries take to execute? Latency is measured at percentiles, not averages.

- **p50 (median):** Half of queries complete faster than this. Represents typical experience.
- **p95:** 95% of queries complete faster. Catches the slow tail.
- **p99:** 99% of queries complete faster. Catches the worst outliers.

Why percentiles matter: average latency hides the worst-case experience. If the average is 10ms but p99 is 5 seconds, 1 in 100 users has a terrible experience. Averages lie - percentiles tell the truth.

On Aurora, the CloudWatch metrics `ReadLatency` and `WriteLatency` provide per-operation latency. For query-level latency, use `pg_stat_statements`:

```sql
SELECT
    round(mean_exec_time::numeric, 2) AS avg_ms,
    round(min_exec_time::numeric, 2) AS min_ms,
    round(max_exec_time::numeric, 2) AS max_ms,
    calls
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

**SLI 3: Error Rate**

What percentage of queries or transactions fail?

```sql
SELECT
    datname,
    xact_commit AS successful_txns,
    xact_rollback AS failed_txns,
    round(
        xact_rollback::numeric / NULLIF(xact_commit + xact_rollback, 0) * 100,
        4
    ) AS error_rate_pct
FROM pg_stat_database
WHERE datname NOT LIKE 'template%'
  AND datname IS NOT NULL;
```

Failed transactions include connection refused, query timeouts, constraint violations, and deadlocks. Not all rollbacks are errors (some are application-level retries), so calibrate your error rate definition based on your application's behavior.

**SLI 4: Throughput**

How many transactions per second (TPS) is the database processing?

```sql
SELECT
    datname,
    xact_commit + xact_rollback AS total_txns
FROM pg_stat_database
WHERE datname = 'myapp';
```

Sample twice, 10 seconds apart. TPS = (total_txns_now - total_txns_before) / 10. A sudden drop or spike in TPS is a signal to investigate.

### Additional SLIs for Aurora

| SLI | CloudWatch Metric | What It Tells You |
|-----|------------------|-------------------|
| Replication lag | `AuroraReplicaLag` | Time delay between writer and readers |
| Connection utilization | `DatabaseConnections` | How close to max_connections |
| Storage headroom | `FreeStorageSpace` | Remaining disk capacity |
| Cache effectiveness | Buffer cache hit ratio (SQL) | Whether working set fits in memory |
| CPU headroom | `CPUUtilization` | Compute capacity remaining |

---

## Service Level Objectives (SLOs)

An SLO is a target you set for an SLI. It is a measurable promise about how reliable the service should be.

### Setting SLOs for Aurora PostgreSQL

| SLI | SLO | Meaning |
|-----|-----|---------|
| Availability | 99.9% | No more than 8.76 hours downtime per year |
| Query latency (p95) | < 100ms | 95% of queries complete in under 100ms |
| Query latency (p99) | < 500ms | 99% of queries complete in under 500ms |
| Error rate | < 0.1% | Fewer than 1 in 1,000 transactions fail |
| Replication lag | < 5 seconds | Readers are within 5 seconds of the writer |

### The Nines of Availability

| Availability | Annual Downtime | Monthly Downtime | Common Name |
|-------------|----------------|-----------------|-------------|
| 99% | 3.65 days | 7.3 hours | "Two nines" |
| 99.5% | 1.83 days | 3.65 hours | |
| 99.9% | 8.76 hours | 43.8 minutes | "Three nines" |
| 99.95% | 4.38 hours | 21.9 minutes | |
| 99.99% | 52.56 minutes | 4.38 minutes | "Four nines" |
| 99.999% | 5.26 minutes | 26.3 seconds | "Five nines" |

Each additional nine is approximately 10x harder and more expensive to achieve. Going from 99.9% to 99.99% may require adding a standby, a connection pooler, automated failover, cross-region replication, and a dedicated on-call rotation. Most internal database services are well-served by 99.9% (three nines).

### How to Choose Your SLO

Ask three questions:

1. **What do users actually need?** If the application has a 5-second timeout, a p99 latency SLO of 500ms gives 10x headroom.

2. **What can you actually deliver?** If your Aurora cluster is single-AZ with no readers, do not promise 99.99%. Be honest about your architecture.

3. **What is the cost of higher reliability?** Each additional nine has a real dollar cost. Present this cost curve to stakeholders so they understand the trade-off.

---

## Service Level Agreements (SLAs)

An SLA is a contract with the business or external customers that includes consequences for missing targets.

| Aspect | SLO | SLA |
|--------|-----|-----|
| Audience | Engineering team | Business / customers |
| Consequence of missing | Action items, postmortem | Financial penalties, contract breach |
| Target | Aspirational (slightly aggressive) | Conservative (leave buffer) |
| Example | 99.95% availability | 99.9% availability |

Key principle: your SLO should always be tighter than your SLA. If your SLA promises 99.9%, your internal SLO should be 99.95%. This buffer prevents you from breaching the external agreement before you have time to react.

---

## Error Budgets

An error budget is the amount of unreliability your SLO allows. It is calculated as:

```
Error Budget = 1 - SLO target
```

**Example:** If your SLO is 99.9% availability per quarter:

```
Error Budget = 1 - 0.999 = 0.001 = 0.1%
0.1% of a quarter (90 days) = 0.09 days = 2.16 hours = 129.6 minutes
```

You are "allowed" 129.6 minutes of downtime per quarter. This budget funds both planned changes (deployments, migrations) and unplanned incidents.

### How Error Budgets Drive Decisions

| Error Budget Status | Action |
|--------------------|--------|
| Budget healthy (> 50% remaining) | Deploy freely, run chaos experiments, take risks |
| Budget warning (25-50% remaining) | Deploy carefully, extra testing required |
| Budget low (< 25% remaining) | Only deploy critical fixes, no new features |
| Budget exhausted (0%) | Change freeze until budget resets next quarter |

The error budget is the mediator between the reliability team ("no changes, they cause outages") and the feature team ("deploy faster, we need features"). When the budget is healthy, the feature team deploys freely. When the budget is exhausted, the reliability team gets their change freeze. Both sides accept this because it is driven by data, not politics.

### Tracking Error Budget Consumption

```sql
-- Error budget tracker for quarterly SLO
WITH params AS (
    SELECT
        0.999 AS slo_target,
        90 * 24 * 60 AS quarter_minutes,
        15.0 AS actual_downtime_minutes
)
SELECT
    round(quarter_minutes * (1 - slo_target), 1) AS budget_total_min,
    round(actual_downtime_minutes, 1) AS budget_used_min,
    round(quarter_minutes * (1 - slo_target) - actual_downtime_minutes, 1) AS budget_remaining_min,
    round(actual_downtime_minutes / (quarter_minutes * (1 - slo_target)) * 100, 1) AS budget_consumed_pct,
    CASE
        WHEN actual_downtime_minutes / (quarter_minutes * (1 - slo_target)) < 0.5 THEN 'HEALTHY'
        WHEN actual_downtime_minutes / (quarter_minutes * (1 - slo_target)) < 0.75 THEN 'WARNING'
        WHEN actual_downtime_minutes / (quarter_minutes * (1 - slo_target)) < 1.0 THEN 'LOW'
        ELSE 'EXHAUSTED'
    END AS budget_status
FROM params;
```

---

## Toil

Toil is work that is manual, repetitive, automatable, tactical, produces no enduring value, and scales linearly with fleet size. Google's SRE book recommends that teams spend no more than 50% of their time on toil. The other 50% should be spent on engineering - building systems that reduce future toil.

### Common DBA Toil

| Toil Task | Frequency | Manual Time | Automation Solution |
|-----------|-----------|-------------|---------------------|
| Create database users | 3x/week | 30 min | Python script with role templates |
| Verify backups | Daily | 15 min | Automated restore and verify script |
| Check disk space | Daily | 20 min | CloudWatch alarms and dashboard |
| Generate capacity report | Weekly | 2 hours | Lambda function with S3 output |
| Rotate SSL certificates | Monthly | 30 min | Automated rotation via ACM |
| Check replication lag | Hourly | 5 min | CloudWatch metric with alarm |
| Deploy schema migrations | Weekly | 45 min | CI/CD pipeline |

### The Toil Trap

If you spend 80% of your time on toil, you have no time to build automation. Without automation, the toil grows as you add more databases. This creates a vicious cycle where the team is always underwater, always reactive, and never has time to build the systems that would fix the problem.

Breaking the cycle requires a deliberate investment: carve out 20% of your time for automation even when toil is pressing. The first automation project should target your highest-frequency, lowest-complexity toil task - it delivers the fastest return.

### Measuring Toil

Track your tasks for one week. Categorize each task as toil or engineering. Calculate the percentage. If toil exceeds 50%, prioritize automation work. Score each toil task on two dimensions:

- **Time per occurrence** - how long does it take each time?
- **Frequency** - how often do you do it?

The product (time x frequency) gives you the annual cost in hours. Automate the highest-cost items first.

---

## SRE Practices Applied to Aurora Operations

### On-Call and Escalation

SRE-minded teams have structured on-call rotations with clear escalation paths:

1. **Primary on-call:** First responder. Uses runbooks to diagnose and mitigate.
2. **Secondary on-call:** Escalation if primary cannot resolve within 30 minutes.
3. **Subject matter expert:** Escalation for complex issues (wraparound, data corruption).

On-call quality metrics:
- Pages per week per engineer (target: < 5)
- Pages requiring human action vs. auto-resolved (target: > 50% auto-resolved)
- Time to acknowledge (target: < 5 minutes)
- MTTR for SEV1 incidents (target: < 30 minutes)

### Operational Reviews

SRE teams conduct regular operational reviews to track reliability metrics and toil trends:

```
## Weekly Operational Review Checklist

### SLO Status
- [ ] Availability: __% (SLO: 99.9%)
- [ ] Error budget remaining: __ minutes
- [ ] Latency p95: __ms (SLO: < 100ms)
- [ ] Replication lag max: __s (SLO: < 5s)

### Incidents This Week
- [ ] Number of SEV1/SEV2 incidents: __
- [ ] MTTR for this week: __ minutes
- [ ] Outstanding action items from PIRs: __

### Toil This Week
- [ ] Hours spent on toil: __
- [ ] Toil percentage: __% (target: <= 50%)
- [ ] New automation completed: __
```

### Reliability as a Feature

The most important mental model shift in SRE: reliability is not something separate from the product. It is a feature of the product. When you build monitoring, write runbooks, automate diagnostics, and run chaos experiments, you are building product features - just not the kind that users see directly.

When the database stays up during a traffic spike because you right-sized the instance, that is a feature. When a failover completes in 25 seconds because you tested it quarterly, that is a feature. When a cost spike is caught in 4 hours instead of 30 days because you built budget alerts, that is a feature.

---

## Summary

| Concept | Key Takeaway |
|---------|-------------|
| SRE | Applies engineering practices to operations - measure, budget, and automate reliability |
| SLI | A specific metric that indicates service health (availability, latency, error rate, throughput) |
| SLO | A target for your SLI (99.9% availability, p95 < 100ms) |
| SLA | A contract with business consequences for missing targets |
| Error budget | The allowed unreliability: 1 - SLO. Drives deployment velocity |
| Toil | Manual, repetitive, automatable work - keep under 50% of time |
| The nines | Each additional nine is 10x harder and more expensive |
| DBRE mindset | Measure everything, automate toil, engineer reliability |

**Next:** [Concepts 02 - Cost Optimization](./02-cost-optimization.md)
