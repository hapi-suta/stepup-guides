# BUILD 01: SLIs, SLOs, and SLAs for Database Services

**Module 07: Database SRE Practices**
**Estimated Time: 60-75 minutes**

---

## What You Will Learn

How to define measurable reliability targets for your PostgreSQL services using the SRE framework - SLIs, SLOs, and SLAs - so you can make data-driven decisions about reliability vs velocity.

---

## What is SRE?

Site Reliability Engineering (SRE) is a discipline that applies software engineering practices to infrastructure and operations.

**DBA Analogy:** Traditional DBAs fix problems when they happen. SRE-minded DBAs (Database Reliability Engineers, or DBREs) build systems that prevent problems, measure reliability, and automate toil. Instead of being reactive - "the database is down, fix it!" - you become proactive: "our error budget allows one more hour of downtime this quarter, so we can safely deploy this migration."

### Traditional DBA vs DBRE Mindset

| Traditional DBA | Database Reliability Engineer |
|----------------|------------------------------|
| "The database is up, we are fine" | "The database is 99.95% available this quarter" |
| "I will tune this query manually" | "I will automate query performance monitoring" |
| "We need zero downtime" | "We need 99.9% uptime - 0.1% downtime is our error budget" |
| "I will fix it when it breaks" | "I will design chaos experiments to find weaknesses" |
| "I did 20 manual tasks today" | "I automated 18 tasks and spent 2 hours on engineering" |

---

## Step 1: Service Level Indicators (SLIs)

An SLI is a metric that tells you if your database service is "healthy." It is a specific, measurable number.

**DBA Analogy:** These are the vitals you check during your daily rounds - the specific numbers you look at to determine if the database is healthy.

### The Four Golden SLIs for PostgreSQL

### SLI 1: Availability

**Definition:** Can clients connect to the database and execute queries?

**Measurement:**
```sql
-- Simple availability check (run from monitoring)
SELECT 1;
-- If this succeeds, the database is "available"
```

**Formula:**
```
Availability = (successful connection checks) / (total connection checks) * 100
```

**How to collect:** Run a health check query every 10 seconds from your monitoring system. Track successes and failures over time.

```bash
# Simple bash health check
while true; do
    if psql -U monitor -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
        echo "$(date) UP"
    else
        echo "$(date) DOWN"
    fi
    sleep 10
done
```

---

### SLI 2: Latency

**Definition:** How long do queries take to execute?

**Measurement:** Track query response times at percentiles:

```sql
-- Requires pg_stat_statements extension. Enable it first:
-- ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
-- Then restart PostgreSQL and run: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
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

**Key percentiles:**
- **p50 (median):** Half of queries are faster than this. Represents typical experience.
- **p95:** 95% of queries are faster. Catches most slow queries.
- **p99:** 99% of queries are faster. Catches the worst outliers.

**DBA Analogy:** Average latency is misleading - like saying "the average body temperature in the morgue is 72F." p95 and p99 tell you about the real user experience.

---

### SLI 3: Error Rate

**Definition:** What percentage of queries fail?

**Measurement:**

```sql
-- Track errors per time window
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

**Formula:**
```
Error Rate = (failed queries) / (total queries) * 100
```

Failed queries include: connection refused, query timeouts, constraint violations (application errors), and deadlocks.

---

### SLI 4: Throughput

**Definition:** How many transactions per second is the database processing?

**Measurement:**

```sql
-- Current TPS (sample twice, 10 seconds apart, calculate difference)
SELECT
    datname,
    xact_commit + xact_rollback AS total_txns
FROM pg_stat_database
WHERE datname = 'myapp';

-- Wait 10 seconds, run again
-- TPS = (total_txns_now - total_txns_before) / 10
```

**DBA Analogy:** TPS is like the speedometer of your database. It tells you how much work the database is doing right now. A sudden drop or spike is a signal to investigate.

---

## Step 2: Service Level Objectives (SLOs)

An SLO is a target you set for an SLI. It is a promise to yourself (and your team) about how reliable the service should be.

**DBA Analogy:** An SLO is like setting a threshold on an alert. You decide: "query latency above 500ms at p95 is unacceptable." The SLO formalizes this into a measurable target.

### Setting SLOs for PostgreSQL

| SLI | SLO | Meaning |
|-----|-----|---------|
| Availability | 99.9% | No more than 8.76 hours downtime per year |
| Query Latency (p95) | < 100ms | 95% of queries complete in under 100ms |
| Query Latency (p99) | < 500ms | 99% of queries complete in under 500ms |
| Error Rate | < 0.1% | Fewer than 1 in 1,000 queries fail |
| Throughput | > 1,000 TPS | Database handles at least 1K transactions/second |

### The Nines of Availability

| Availability | Annual Downtime | Monthly Downtime | Common Name |
|-------------|----------------|-----------------|-------------|
| 99% | 3.65 days | 7.3 hours | "Two nines" |
| 99.5% | 1.83 days | 3.65 hours | |
| 99.9% | 8.76 hours | 43.8 minutes | "Three nines" |
| 99.95% | 4.38 hours | 21.9 minutes | |
| 99.99% | 52.56 minutes | 4.38 minutes | "Four nines" |
| 99.999% | 5.26 minutes | 26.3 seconds | "Five nines" |

**Reality check:** Going from 99.9% to 99.99% is not "a little better" - it is 10x harder. The cost of each additional nine increases exponentially. Most internal database services are well-served by 99.9% (three nines).

### How to Choose Your SLO

Ask these questions:

1. **What do users actually need?** If the application has a 5-second timeout, a p99 latency SLO of 500ms gives you 10x headroom.

2. **What can you actually deliver?** If your PostgreSQL is on a single server with no HA, do not promise 99.99%. Be honest about your architecture.

3. **What is the cost of higher reliability?** Going from 99.9% to 99.99% might require adding a standby, a connection pooler, automated failover, and a dedicated on-call rotation. Is that worth it for this service?

---

## Step 3: Service Level Agreements (SLAs)

An SLA is a contract with the business or external customers that includes consequences for missing targets.

**DBA Analogy:** If an SLO is a promise to yourself ("I will keep latency under 100ms"), an SLA is a contract with the business ("We guarantee 99.9% availability or we credit your account").

### SLO vs SLA

| Aspect | SLO | SLA |
|--------|-----|-----|
| Audience | Engineering team | Business / customers |
| Consequence of missing | Action items, postmortem | Financial penalties, contract breach |
| Target | Aspirational (slightly aggressive) | Conservative (leave buffer) |
| Example | 99.95% availability | 99.9% availability |

**Key principle:** Your SLO should be tighter than your SLA. If your SLA promises 99.9%, your internal SLO should be 99.95%. This gives you a buffer before you breach the external agreement.

---

## Step 4: Error Budgets

An error budget is the amount of unreliability your SLO allows.

**Formula:**
```
Error Budget = 1 - SLO target
```

**Example:** If your SLO is 99.9% availability per quarter:
```
Error Budget = 1 - 0.999 = 0.001 = 0.1%
0.1% of a quarter (90 days) = 0.09 days = 2.16 hours = 129.6 minutes
```

You are "allowed" 129.6 minutes of downtime per quarter. If you use it all, you should freeze changes until the next quarter.

### How Error Budgets Drive Decisions

| Error Budget Status | Action |
|--------------------|--------|
| Budget healthy (> 50% remaining) | Deploy freely, run experiments, take risks |
| Budget warning (25-50% remaining) | Deploy carefully, extra testing required |
| Budget low (< 25% remaining) | Only deploy critical fixes, no new features |
| Budget exhausted (0%) | Change freeze until budget resets |

**DBA Analogy:** Think of error budget like vacation days. If you have 10 days and it is January, you can take time off freely. If it is November and you have 1 day left, you save it for emergencies.

---

## Step 5: Practical - Define SLIs and SLOs for a PostgreSQL Service

Let's define SLIs and SLOs for a production PostgreSQL database backing an e-commerce application.

### The Service

- **Database:** PostgreSQL 16
- **Architecture:** 1 primary + 2 standbys with Patroni
- **Users:** 500 concurrent application connections
- **Workload:** Mixed OLTP (orders, inventory) + reporting queries
- **Business impact:** Every minute of downtime = $5,000 lost revenue

### Define SLIs

```bash
mkdir -p ~/dba-labs/sre-practice
cd ~/dba-labs/sre-practice
vi sli-definitions.yml
```

```yaml
---
service: ecommerce-postgresql
owner: dba-team

slis:
  availability:
    description: "Database accepts connections and responds to health check query"
    measurement: "SELECT 1 via monitoring probe every 10 seconds"
    good_event: "Health check returns within 1 second"
    bad_event: "Health check fails or times out"

  latency:
    description: "Query response time at p95 and p99 percentiles"
    measurement: "pg_stat_statements mean_exec_time, sampled every 60 seconds"
    good_event: "Query completes within threshold"
    bad_event: "Query exceeds threshold"

  error_rate:
    description: "Percentage of failed transactions"
    measurement: "xact_rollback / (xact_commit + xact_rollback) from pg_stat_database"
    good_event: "Transaction commits successfully"
    bad_event: "Transaction rolls back or connection fails"

  replication_lag:
    description: "Time delay between primary and standby"
    measurement: "extract(epoch from now() - pg_last_xact_replay_timestamp()) on standby"
    good_event: "Lag is within threshold"
    bad_event: "Lag exceeds threshold"
```

### Define SLOs

```bash
vi slo-definitions.yml
```

```yaml
---
service: ecommerce-postgresql
measurement_window: quarterly

slos:
  availability:
    target: 99.9%
    error_budget_minutes: 129.6    # per quarter
    rationale: "Patroni HA provides automatic failover within 30 seconds"

  latency_p95:
    target: "< 50ms"
    rationale: "Application timeout is 5 seconds; 50ms gives 100x headroom"

  latency_p99:
    target: "< 200ms"
    rationale: "Even the slowest 1% of queries should be under 200ms"

  error_rate:
    target: "< 0.05%"
    rationale: "Fewer than 1 in 2,000 transactions should fail"

  replication_lag:
    target: "< 5 seconds"
    rationale: "Read replicas should be within 5 seconds of primary"

alerts:
  - condition: "Availability < 99.9% over 1 hour window"
    severity: critical
    action: "Page on-call DBA"

  - condition: "Latency p95 > 50ms for 5 minutes"
    severity: warning
    action: "Notify DBA Slack channel"

  - condition: "Error rate > 0.1% for 5 minutes"
    severity: critical
    action: "Page on-call DBA"

  - condition: "Replication lag > 30 seconds"
    severity: critical
    action: "Page on-call DBA, check standby health"
```

### Calculate Error Budget

```bash
vi error-budget-tracker.sql
```

```sql
-- Error budget tracker for quarterly SLO
-- Run this weekly to track budget consumption

WITH params AS (
    SELECT
        0.999 AS slo_target,           -- 99.9%
        90 * 24 * 60 AS quarter_minutes, -- Total minutes in a quarter
        '2026-04-01'::date AS quarter_start,
        '2026-06-30'::date AS quarter_end,
        now()::date AS today
),
budget AS (
    SELECT
        quarter_minutes * (1 - slo_target) AS total_budget_minutes,
        -- Replace this with actual downtime tracking from your monitoring
        15.0 AS actual_downtime_minutes  -- Example: 15 minutes used
    FROM params
)
SELECT
    round(total_budget_minutes, 1) AS budget_total_min,
    round(actual_downtime_minutes, 1) AS budget_used_min,
    round(total_budget_minutes - actual_downtime_minutes, 1) AS budget_remaining_min,
    round(actual_downtime_minutes / total_budget_minutes * 100, 1) AS budget_consumed_pct,
    CASE
        WHEN actual_downtime_minutes / total_budget_minutes < 0.5 THEN 'HEALTHY'
        WHEN actual_downtime_minutes / total_budget_minutes < 0.75 THEN 'WARNING'
        WHEN actual_downtime_minutes / total_budget_minutes < 1.0 THEN 'LOW'
        ELSE 'EXHAUSTED'
    END AS budget_status
FROM budget;
```

Expected output:
```
 budget_total_min | budget_used_min | budget_remaining_min | budget_consumed_pct | budget_status
------------------+-----------------+----------------------+---------------------+---------------
            129.6 |            15.0 |                114.6 |                11.6 | HEALTHY
```

---

## Step 6: Monitoring SLIs in Practice

### Availability Monitoring Script

```bash
vi check-availability.sh
```

```bash
#!/bin/bash
# SLI: Availability check
# Run via cron every 10 seconds (or via monitoring tool)

DB_HOST="localhost"
DB_PORT="5432"
DB_USER="monitor"
DB_NAME="postgres"
LOG_FILE="/var/log/pg-sli-availability.log"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
   -c "SELECT 1;" -t -A > /dev/null 2>&1; then
    echo "${TIMESTAMP} status=UP" >> "$LOG_FILE"
else
    echo "${TIMESTAMP} status=DOWN" >> "$LOG_FILE"
fi
```

### Latency Monitoring Query

```sql
-- Run every minute to track latency SLI
SELECT
    datname,
    round(
        ((blk_read_time + blk_write_time) /
        NULLIF(xact_commit + xact_rollback, 0))::numeric,
        2
    ) AS avg_io_time_per_txn_ms
FROM pg_stat_database
WHERE datname = 'myapp';
```

### Replication Lag Monitoring

```sql
-- Run on standbys every 10 seconds
SELECT
    CASE
        WHEN pg_is_in_recovery() THEN
            extract(epoch FROM now() - pg_last_xact_replay_timestamp())
        ELSE 0
    END AS replication_lag_seconds;
```

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| SRE mindset | Treat reliability as a measurable, engineerable property |
| SLI | A specific metric that indicates service health (availability, latency, error rate) |
| SLO | A target for your SLI (99.9% availability, p95 < 100ms) |
| SLA | A contract with business consequences for missing targets |
| Error budget | The allowed unreliability: `1 - SLO` - drives deployment decisions |
| The nines | Each additional nine is 10x harder and more expensive |
| Availability | Can clients connect and execute queries? |
| Latency | p50, p95, p99 query response times (averages lie) |
| Error rate | Failed transactions as a percentage of total |
| Replication lag | Time delay between primary and standby |
| Budget-driven decisions | Deploy freely when budget is healthy; freeze when exhausted |

---

**Next:** BUILD 02 - Incident Response for Database Outages - structured processes for when things go wrong.
