# BUILD 01: SLO Definition for Aurora PostgreSQL

**Module 09: Operations at Scale and SRE**
**Estimated Time:** 60-75 minutes
**Level:** Intermediate

---

## Objective

Define Service Level Indicators (SLIs), Service Level Objectives (SLOs), and error budgets for an Aurora PostgreSQL cluster. By the end of this guide, you will have a working SLO dashboard query, an error budget tracker, and alert threshold definitions for your `devops-lab-cluster`.

---

## Prerequisites

- Aurora PostgreSQL cluster `devops-lab-cluster` running
- `psql` client connected to the writer endpoint
- AWS CLI configured with appropriate permissions
- CloudWatch access in the AWS Console

---

## Section 1: Identify Your Service Level Indicators

SLIs are the raw metrics that tell you whether your database is healthy. You need to decide what to measure before you can set targets.

### 1.1 Enable pg_stat_statements

The `pg_stat_statements` extension tracks query execution statistics. It must be loaded before you can measure query latency.

**In the AWS Console:**

1. Open the **RDS** service.
2. Click **Parameter groups** in the left sidebar.
3. Select the parameter group attached to `devops-lab-cluster`.
4. Search for `shared_preload_libraries`.
5. Edit the value to include `pg_stat_statements`.
6. Click **Save changes**.
7. Reboot the writer instance for the change to take effect.

**Using the CLI:**

```bash
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name devops-lab-cluster-params \
    --parameters "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot"
```

The `--parameters` flag specifies which parameter to change and its new value. `ApplyMethod=pending-reboot` means the change takes effect after the next reboot.

Reboot the writer instance:

```bash
aws rds reboot-db-instance \
    --db-instance-identifier devops-lab-cluster-instance-1
```

Wait for the instance to become available:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier devops-lab-cluster-instance-1
```

The `wait` subcommand polls the instance status until it reaches the `available` state. This avoids the need to manually check.

Expected output (yours will differ):
```
(no output - the command returns silently when the instance is available)
```

### 1.2 Create the Extension

Connect to your Aurora writer endpoint using `psql`:

```bash
psql -h devops-lab-cluster.cluster-xxxxxxxxxxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

Create the extension:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Expected output:
```
CREATE EXTENSION
```

Verify it is loaded:

```sql
SELECT * FROM pg_stat_statements LIMIT 1;
```

If this returns a row (or an empty result set without an error), the extension is working.

### 1.3 Define the Four Golden SLIs

Run this query to check all four SLIs at once:

```sql
-- SLI 1: Availability (connection test)
SELECT 'availability' AS sli, 'connected' AS status;

-- SLI 2: Latency (top 10 slowest queries by average execution time)
SELECT
    left(query, 60) AS query_preview,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    round(max_exec_time::numeric, 2) AS max_ms,
    calls
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

Expected output (yours will differ):
```
     sli      |  status
--------------+-----------
 availability | connected
(1 row)

       query_preview        | avg_ms | max_ms | calls
----------------------------+--------+--------+-------
 SELECT pg_sleep($1)        |  50.23 | 102.45 |    12
 INSERT INTO orders ...     |   8.41 |  45.67 |  1024
 ...
```

Now check error rate and throughput:

```sql
-- SLI 3: Error Rate
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

Expected output (yours will differ):
```
 datname  | successful_txns | failed_txns | error_rate_pct
----------+-----------------+-------------+----------------
 postgres |           15234 |          12 |         0.0787
 myapp    |          102456 |          34 |         0.0332
```

```sql
-- SLI 4: Throughput (snapshot - run twice 10 seconds apart to calculate TPS)
SELECT
    datname,
    xact_commit + xact_rollback AS total_txns,
    now() AS sampled_at
FROM pg_stat_database
WHERE datname NOT LIKE 'template%'
  AND datname IS NOT NULL;
```

---

## Section 2: Check CloudWatch SLIs

Aurora publishes metrics to CloudWatch automatically. These complement the SQL-based SLIs.

### 2.1 Query Replication Lag

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name AuroraReplicaLag \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Average Maximum \
    --output table
```

The flags:
- `--namespace AWS/RDS` - CloudWatch groups metrics by service. RDS metrics live under `AWS/RDS`.
- `--metric-name AuroraReplicaLag` - the specific metric measuring replication delay in milliseconds.
- `--dimensions` - filters to your specific cluster.
- `--period 60` - aggregates data into 60-second intervals.
- `--statistics Average Maximum` - returns both the average and peak values for each interval.

Expected output (yours will differ):
```
--------------------------------------------------
|              GetMetricStatistics               |
+------------------------------------------------+
||                  Datapoints                  ||
|+----------+----------+-----------------------+|
|| Average  | Maximum  |      Timestamp        ||
|+----------+----------+-----------------------+|
||  12.45   |  45.67   | 2026-06-09T10:00:00Z  ||
||  11.23   |  38.90   | 2026-06-09T10:01:00Z  ||
|+----------+----------+-----------------------+|
```

### 2.2 Query CPU Utilization

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics Average Maximum \
    --output table
```

The `--period 300` flag aggregates into 5-minute intervals, which smooths out short CPU spikes.

### 2.3 Query Connection Count

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Average Maximum \
    --output table
```

---

## Section 3: Define Your SLOs

Now that you know what to measure, set targets for each SLI.

### 3.1 Create the SLO Definition File

Create a YAML file that documents your SLO definitions. This file becomes the single source of truth for your team.

```bash
mkdir -p ~/sre-practice
```

```bash
vi ~/sre-practice/slo-definitions.yml
```

Add this content:

```yaml
---
service: devops-lab-cluster
engine: aurora-postgresql
owner: dba-team
measurement_window: quarterly

slos:
  availability:
    sli: "Health check query (SELECT 1) succeeds within 1 second"
    target: 99.9%
    error_budget_minutes: 129.6
    rationale: "Aurora Multi-AZ provides automatic failover within 30 seconds"
    cloudwatch_metric: "DatabaseConnections"
    alert_threshold: "Availability < 99.9% over 1-hour rolling window"

  latency_p95:
    sli: "Query response time at 95th percentile"
    target: "< 100ms"
    rationale: "Application timeout is 5 seconds - 100ms gives 50x headroom"
    source: "pg_stat_statements mean_exec_time"
    alert_threshold: "p95 latency > 100ms for 5 consecutive minutes"

  latency_p99:
    sli: "Query response time at 99th percentile"
    target: "< 500ms"
    rationale: "Even worst-case queries should complete well under app timeout"
    source: "pg_stat_statements max_exec_time"
    alert_threshold: "p99 latency > 500ms for 5 consecutive minutes"

  error_rate:
    sli: "Percentage of failed transactions (rollbacks / total)"
    target: "< 0.1%"
    rationale: "Fewer than 1 in 1,000 transactions should fail"
    source: "pg_stat_database xact_rollback / (xact_commit + xact_rollback)"
    alert_threshold: "Error rate > 0.1% for 5 consecutive minutes"

  replication_lag:
    sli: "Time delay between writer and reader instances"
    target: "< 5 seconds"
    rationale: "Read replicas serve reporting queries - 5s delay is acceptable"
    cloudwatch_metric: "AuroraReplicaLag"
    alert_threshold: "Replication lag > 30 seconds for 2 consecutive minutes"

alerts:
  - condition: "Availability < 99.9% over 1-hour window"
    severity: critical
    action: "Page on-call DBA"

  - condition: "Latency p95 > 100ms for 5 minutes"
    severity: warning
    action: "Notify DBA Slack channel"

  - condition: "Error rate > 0.1% for 5 minutes"
    severity: critical
    action: "Page on-call DBA"

  - condition: "Replication lag > 30 seconds"
    severity: critical
    action: "Page on-call DBA, check reader health"
```

Save and exit vi (`:wq`).

### 3.2 Understand the Nines

Each additional "nine" of availability is approximately 10x harder and more expensive to achieve.

| Availability | Annual Downtime | Monthly Downtime | What It Requires |
|-------------|----------------|-----------------|-----------------|
| 99% | 3.65 days | 7.3 hours | Basic monitoring |
| 99.9% | 8.76 hours | 43.8 minutes | Multi-AZ, automated failover |
| 99.95% | 4.38 hours | 21.9 minutes | Connection pooler, tested failover |
| 99.99% | 52.56 minutes | 4.38 minutes | Cross-region, chaos testing, dedicated on-call |
| 99.999% | 5.26 minutes | 26.3 seconds | Active-active, zero-downtime deployments |

For most Aurora PostgreSQL workloads, 99.9% (three nines) is the right starting target. Aurora's built-in Multi-AZ replication and automatic failover make this achievable without additional infrastructure.

---

## Section 4: Build the Error Budget Tracker

The error budget is the amount of unreliability your SLO allows. It converts an abstract percentage into concrete minutes.

### 4.1 Create the Error Budget Table

Connect to your Aurora writer endpoint:

```sql
CREATE TABLE IF NOT EXISTS slo_error_budget (
    id SERIAL PRIMARY KEY,
    quarter VARCHAR(10) NOT NULL,
    slo_target NUMERIC(6,4) NOT NULL,
    quarter_start DATE NOT NULL,
    quarter_end DATE NOT NULL,
    total_budget_minutes NUMERIC(8,1) NOT NULL,
    used_minutes NUMERIC(8,1) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
```

Expected output:
```
CREATE TABLE
```

### 4.2 Insert the Current Quarter Budget

```sql
INSERT INTO slo_error_budget (quarter, slo_target, quarter_start, quarter_end, total_budget_minutes)
VALUES (
    'Q3-2026',
    0.999,
    '2026-07-01',
    '2026-09-30',
    92 * 24 * 60 * (1 - 0.999)  -- 92 days * 24 hours * 60 minutes * 0.1%
);
```

Expected output:
```
INSERT 0 1
```

Verify the budget:

```sql
SELECT
    quarter,
    slo_target,
    round(total_budget_minutes, 1) AS budget_total_min,
    round(used_minutes, 1) AS budget_used_min,
    round(total_budget_minutes - used_minutes, 1) AS budget_remaining_min,
    CASE
        WHEN used_minutes / total_budget_minutes < 0.5 THEN 'HEALTHY'
        WHEN used_minutes / total_budget_minutes < 0.75 THEN 'WARNING'
        WHEN used_minutes / total_budget_minutes < 1.0 THEN 'LOW'
        ELSE 'EXHAUSTED'
    END AS budget_status
FROM slo_error_budget
WHERE quarter = 'Q3-2026';
```

Expected output:
```
 quarter | slo_target | budget_total_min | budget_used_min | budget_remaining_min | budget_status
---------+------------+------------------+-----------------+----------------------+---------------
 Q3-2026 |     0.9990 |            132.5 |             0.0 |                132.5 | HEALTHY
```

### 4.3 Simulate an Incident

Record a 15-minute outage against the error budget:

```sql
UPDATE slo_error_budget
SET used_minutes = used_minutes + 15.0,
    updated_at = now()
WHERE quarter = 'Q3-2026';
```

Check the budget again:

```sql
SELECT
    quarter,
    round(total_budget_minutes, 1) AS budget_total_min,
    round(used_minutes, 1) AS budget_used_min,
    round(total_budget_minutes - used_minutes, 1) AS budget_remaining_min,
    round(used_minutes / total_budget_minutes * 100, 1) AS budget_consumed_pct,
    CASE
        WHEN used_minutes / total_budget_minutes < 0.5 THEN 'HEALTHY'
        WHEN used_minutes / total_budget_minutes < 0.75 THEN 'WARNING'
        WHEN used_minutes / total_budget_minutes < 1.0 THEN 'LOW'
        ELSE 'EXHAUSTED'
    END AS budget_status
FROM slo_error_budget
WHERE quarter = 'Q3-2026';
```

Expected output:
```
 quarter | budget_total_min | budget_used_min | budget_remaining_min | budget_consumed_pct | budget_status
---------+------------------+-----------------+----------------------+---------------------+---------------
 Q3-2026 |            132.5 |            15.0 |                117.5 |                11.3 | HEALTHY
```

The 15-minute outage consumed 11.3% of your quarterly error budget. You still have 117.5 minutes remaining.

### 4.4 Create the Incident Log Table

Track individual incidents that consume error budget:

```sql
CREATE TABLE IF NOT EXISTS incident_log (
    incident_id SERIAL PRIMARY KEY,
    severity VARCHAR(5) NOT NULL,
    title TEXT NOT NULL,
    detected_at TIMESTAMPTZ NOT NULL,
    responded_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    downtime_minutes NUMERIC(8,1),
    root_cause TEXT,
    action_items TEXT[],
    created_at TIMESTAMPTZ DEFAULT now()
);
```

Expected output:
```
CREATE TABLE
```

Insert the simulated incident:

```sql
INSERT INTO incident_log (severity, title, detected_at, responded_at, resolved_at, downtime_minutes, root_cause, action_items)
VALUES (
    'SEV2',
    'Writer instance unresponsive - automatic failover triggered',
    '2026-06-09 02:15:00+00',
    '2026-06-09 02:17:00+00',
    '2026-06-09 02:30:00+00',
    15.0,
    'Underlying hardware failure on writer instance triggered automatic failover',
    ARRAY['Add CloudWatch alarm for failover events', 'Test application reconnect behavior']
);
```

### 4.5 Query Incident Metrics

```sql
SELECT
    severity,
    count(*) AS incident_count,
    round(avg(downtime_minutes), 1) AS avg_downtime_min,
    round(avg(extract(epoch FROM responded_at - detected_at) / 60), 1) AS avg_response_min,
    round(avg(extract(epoch FROM resolved_at - detected_at) / 60), 1) AS avg_resolution_min
FROM incident_log
WHERE detected_at > now() - interval '90 days'
GROUP BY severity
ORDER BY severity;
```

Expected output:
```
 severity | incident_count | avg_downtime_min | avg_response_min | avg_resolution_min
----------+----------------+------------------+------------------+--------------------
 SEV2     |              1 |             15.0 |              2.0 |               15.0
```

---

## Section 5: Create CloudWatch Alarms for SLOs

### 5.1 Availability Alarm (Connection Count Drops to Zero)

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "devops-lab-cluster-availability" \
    --alarm-description "Alert when database connections drop to zero (potential outage)" \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --statistic Minimum \
    --period 60 \
    --threshold 0 \
    --comparison-operator LessThanOrEqualToThreshold \
    --evaluation-periods 2 \
    --treat-missing-data breaching \
    --ok-actions [] \
    --alarm-actions []
```

The flags:
- `--statistic Minimum` - checks the lowest connection count in the period. If even the minimum is zero, the database may be down.
- `--period 60` - evaluates every 60 seconds.
- `--evaluation-periods 2` - requires 2 consecutive periods below threshold before alarming. This prevents false alarms from brief connection dips.
- `--treat-missing-data breaching` - if CloudWatch receives no data, treat it as a breach. Missing data from a database metric usually means the database is unreachable.

Expected output (yours will differ):
```
(no output - the command succeeds silently)
```

### 5.2 Latency Alarm (Write Latency)

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "devops-lab-cluster-write-latency" \
    --alarm-description "Alert when write latency exceeds 100ms average" \
    --namespace AWS/RDS \
    --metric-name WriteLatency \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --statistic Average \
    --period 300 \
    --threshold 0.1 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 3 \
    --treat-missing-data notBreaching
```

The `--threshold 0.1` value is in seconds (100 milliseconds). CloudWatch reports RDS latency metrics in seconds.

### 5.3 Replication Lag Alarm

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "devops-lab-cluster-replication-lag" \
    --alarm-description "Alert when replication lag exceeds 30 seconds" \
    --namespace AWS/RDS \
    --metric-name AuroraReplicaLag \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --statistic Maximum \
    --period 60 \
    --threshold 30000 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --treat-missing-data notBreaching
```

The `--threshold 30000` value is in milliseconds. `AuroraReplicaLag` reports in milliseconds, not seconds.

### 5.4 Verify All Alarms

```bash
aws cloudwatch describe-alarms \
    --alarm-name-prefix "devops-lab-cluster" \
    --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Metric:MetricName,Threshold:Threshold}' \
    --output table
```

Expected output (yours will differ):
```
-----------------------------------------------------------------------
|                          DescribeAlarms                              |
+------------------------------------+---------+---------------------+-----------+
|               Name                 | State   | Metric              | Threshold |
+------------------------------------+---------+---------------------+-----------+
| devops-lab-cluster-availability    | OK      | DatabaseConnections |       0.0 |
| devops-lab-cluster-replication-lag | OK      | AuroraReplicaLag    |   30000.0 |
| devops-lab-cluster-write-latency   | OK      | WriteLatency        |       0.1 |
+------------------------------------+---------+---------------------+-----------+
```

---

## Section 6: Build an SLO Dashboard Query

### 6.1 Create a Comprehensive SLO Status View

This view combines all SLI data into a single dashboard query:

```sql
CREATE OR REPLACE VIEW slo_dashboard AS
WITH error_rate AS (
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
      AND datname IS NOT NULL
),
budget AS (
    SELECT
        quarter,
        slo_target,
        total_budget_minutes,
        used_minutes,
        round(total_budget_minutes - used_minutes, 1) AS remaining_minutes,
        round(used_minutes / total_budget_minutes * 100, 1) AS consumed_pct,
        CASE
            WHEN used_minutes / total_budget_minutes < 0.5 THEN 'HEALTHY'
            WHEN used_minutes / total_budget_minutes < 0.75 THEN 'WARNING'
            WHEN used_minutes / total_budget_minutes < 1.0 THEN 'LOW'
            ELSE 'EXHAUSTED'
        END AS status
    FROM slo_error_budget
    ORDER BY quarter_start DESC
    LIMIT 1
)
SELECT
    'Error Rate' AS sli,
    e.datname AS scope,
    e.error_rate_pct || '%' AS current_value,
    '< 0.1%' AS slo_target,
    CASE WHEN e.error_rate_pct < 0.1 THEN 'PASS' ELSE 'FAIL' END AS slo_status
FROM error_rate e
UNION ALL
SELECT
    'Error Budget' AS sli,
    b.quarter AS scope,
    b.remaining_minutes || ' min remaining' AS current_value,
    b.slo_target || ' availability' AS slo_target,
    b.status AS slo_status
FROM budget b;
```

Expected output:
```
CREATE VIEW
```

Query the dashboard:

```sql
SELECT * FROM slo_dashboard;
```

Expected output (yours will differ):
```
     sli      |  scope  |      current_value       | slo_target         | slo_status
--------------+---------+--------------------------+--------------------+------------
 Error Rate   | postgres | 0.0787%                 | < 0.1%             | PASS
 Error Rate   | myapp   | 0.0332%                  | < 0.1%             | PASS
 Error Budget | Q3-2026 | 117.5 min remaining      | 0.999 availability | HEALTHY
```

---

## Section 7: Error Budget Policy Document

### 7.1 Create the Policy

```bash
vi ~/sre-practice/error-budget-policy.md
```

Add this content:

```markdown
# Error Budget Policy: devops-lab-cluster

## Budget Calculation
- SLO: 99.9% availability per quarter
- Budget: 132.5 minutes per quarter (92 days)
- Reset: First day of each quarter

## Response Actions

### HEALTHY (< 50% consumed)
- Deploy freely with standard review process
- Run chaos experiments (failover tests, load tests)
- Perform non-critical maintenance during business hours

### WARNING (50-75% consumed)
- Extra review required for all deployments
- No chaos experiments
- Postpone non-critical maintenance to next quarter
- Investigate recent incidents for systemic issues

### LOW (75-100% consumed)
- Only deploy critical security patches and bug fixes
- No feature deployments
- Mandatory post-incident review for any new incident
- Begin root cause analysis of budget consumption pattern

### EXHAUSTED (100% consumed)
- Change freeze until budget resets next quarter
- Exception: critical security vulnerabilities only (requires VP approval)
- Team focuses exclusively on reliability improvements
- Weekly reliability review with engineering leadership

## Review Schedule
- Weekly: DBA team reviews error budget status
- Monthly: Engineering leadership reviews SLO compliance
- Quarterly: Adjust SLO targets based on actual performance and business needs
```

Save and exit vi (`:wq`).

---

## Cleanup

The CloudWatch alarms, database tables, and files you created in this lab are useful for ongoing SRE practice. If you want to remove the alarms:

```bash
aws cloudwatch delete-alarms \
    --alarm-names \
    "devops-lab-cluster-availability" \
    "devops-lab-cluster-write-latency" \
    "devops-lab-cluster-replication-lag"
```

To drop the database objects:

```sql
DROP VIEW IF EXISTS slo_dashboard;
DROP TABLE IF EXISTS incident_log;
DROP TABLE IF EXISTS slo_error_budget;
```

---

## Summary

| What You Did | Why It Matters |
|-------------|---------------|
| Enabled pg_stat_statements | Provides query-level latency data for the latency SLI |
| Defined 5 SLIs | Measurable indicators of database health |
| Set SLO targets | Converts "the database should be reliable" into concrete numbers |
| Built error budget tracker | Translates SLO percentage into actionable minutes of allowed downtime |
| Created CloudWatch alarms | Automated detection when SLIs breach SLO thresholds |
| Built SLO dashboard view | Single query to check all SLI/SLO status |
| Wrote error budget policy | Clear rules for how budget status drives deployment decisions |

**Next:** [BUILD 02 - Cost Analysis and Optimization](./02-cost-analysis-and-optimization.md)
