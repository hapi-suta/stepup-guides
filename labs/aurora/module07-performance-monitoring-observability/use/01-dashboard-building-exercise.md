# USE 01 - Build a Production-Ready Monitoring Dashboard

**Time:** 45 minutes
**Difficulty:** Intermediate
**Prerequisites:** Build 01, 02, 03 complete. CloudWatch alarms created. `$CLUSTER_ID`, `$WRITER_INSTANCE`, `$REGION`, `$SNS_TOPIC_ARN` set.

---

## Objective

Build a complete monitoring dashboard for your Aurora cluster that a DBA can use during an on-call shift. By the end you will have:
- A CloudWatch dashboard with 12 panels covering all critical metrics
- Verified that all 3 monitoring layers are active (CloudWatch, PI, Enhanced Monitoring)
- A connection health snapshot query saved as a reusable function

---

## Exercise Tasks

### Task 1 - Verify All Monitoring Layers Are Active

Run these checks and confirm each returns the expected result.

```bash
echo "=== Monitoring Layers Verification ==="

echo -n "1. Enhanced Monitoring interval: "
aws rds describe-db-instances \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --query "DBInstances[0].MonitoringInterval" \
  --output text --region "$REGION"

echo -n "2. Performance Insights enabled: "
aws rds describe-db-instances \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --query "DBInstances[0].PerformanceInsightsEnabled" \
  --output text --region "$REGION"

echo -n "3. CloudWatch alarm count: "
aws cloudwatch describe-alarms \
  --alarm-name-prefix "Aurora-" \
  --query "length(MetricAlarms)" \
  --output text --region "$REGION"
```

<details>
<summary>Expected output</summary>

```
=== Monitoring Layers Verification ===
1. Enhanced Monitoring interval: 60
2. Performance Insights enabled: True
3. CloudWatch alarm count: 8
```

If any value is wrong, go back to the corresponding BUILD guide and fix it.
</details>

### Task 2 - Build an Extended Dashboard

The Build 01 dashboard has 10 panels. Extend it to 12 by adding:

**Panel 11: Deadlocks per 5 minutes**

Add a widget for the Deadlocks metric. Use Sum statistic with a 300-second period.

<details>
<summary>Hint: Dashboard widget JSON for deadlocks</summary>

```json
{
    "type": "metric", "x": 0, "y": 18, "width": 12, "height": 6,
    "properties": {
        "title": "Deadlocks (5 min sum)",
        "metrics": [["AWS/RDS", "Deadlocks", "DBInstanceIdentifier", "YOUR_INSTANCE"]],
        "period": 300, "stat": "Sum", "view": "timeSeries", "region": "YOUR_REGION"
    }
}
```
</details>

**Panel 12: Disk Queue Depth**

Add a widget for DiskQueueDepth. Use Average statistic with a 60-second period. A sustained value above 10 indicates storage bottleneck.

<details>
<summary>Hint: Dashboard widget JSON for disk queue</summary>

```json
{
    "type": "metric", "x": 12, "y": 18, "width": 12, "height": 6,
    "properties": {
        "title": "Disk Queue Depth",
        "metrics": [["AWS/RDS", "DiskQueueDepth", "DBInstanceIdentifier", "YOUR_INSTANCE"]],
        "period": 60, "stat": "Average", "view": "timeSeries", "region": "YOUR_REGION"
    }
}
```
</details>

### Task 3 - Create a Connection Health Function

Create a reusable PostgreSQL function that returns a connection health snapshot:

```sql
CREATE OR REPLACE FUNCTION connection_health()
RETURNS TABLE(
    metric TEXT,
    value TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 'Total connections'::TEXT, count(*)::TEXT
    FROM pg_stat_activity WHERE backend_type = 'client backend';

    RETURN QUERY
    SELECT 'max_connections'::TEXT, setting
    FROM pg_settings WHERE name = 'max_connections';

    RETURN QUERY
    SELECT 'Active'::TEXT, count(*)::TEXT
    FROM pg_stat_activity WHERE state = 'active' AND backend_type = 'client backend';

    RETURN QUERY
    SELECT 'Idle'::TEXT, count(*)::TEXT
    FROM pg_stat_activity WHERE state = 'idle' AND backend_type = 'client backend';

    RETURN QUERY
    SELECT 'Idle in transaction'::TEXT, count(*)::TEXT
    FROM pg_stat_activity WHERE state = 'idle in transaction' AND backend_type = 'client backend';

    RETURN QUERY
    SELECT 'Idle > 5 min'::TEXT, count(*)::TEXT
    FROM pg_stat_activity
    WHERE state = 'idle' AND now() - state_change > interval '5 minutes'
      AND backend_type = 'client backend';

    RETURN QUERY
    SELECT 'Longest txn (seconds)'::TEXT, round(extract(epoch from max(now() - xact_start)))::TEXT
    FROM pg_stat_activity WHERE xact_start IS NOT NULL;
END;
$$ LANGUAGE plpgsql;
```

Test it:

```sql
SELECT * FROM connection_health();
```

<details>
<summary>Expected output</summary>

```
        metric         | value
-----------------------+-------
 Total connections     | 8
 max_connections       | 820
 Active                | 1
 Idle                  | 6
 Idle in transaction   | 1
 Idle > 5 min          | 2
 Longest txn (seconds) | 45
```
</details>

### Task 4 - Create a Weekly Performance Report Function

```sql
CREATE OR REPLACE FUNCTION weekly_perf_report()
RETURNS TABLE(
    section TEXT,
    rank INT,
    query_snippet TEXT,
    calls BIGINT,
    avg_ms NUMERIC,
    detail TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        'TOP_BY_TOTAL_TIME'::TEXT,
        row_number() OVER (ORDER BY total_exec_time DESC)::INT,
        left(query, 80),
        s.calls,
        round(mean_exec_time::numeric, 1),
        round(total_exec_time / 1000, 0)::TEXT || 's total'
    FROM pg_stat_statements s
    WHERE query NOT LIKE '%pg_stat_statements%'
    ORDER BY total_exec_time DESC
    LIMIT 5;

    RETURN QUERY
    SELECT
        'TOP_BY_DISK_READS'::TEXT,
        row_number() OVER (ORDER BY shared_blks_read DESC)::INT,
        left(query, 80),
        s.calls,
        round(mean_exec_time::numeric, 1),
        round(shared_blks_read::numeric / nullif(s.calls, 0), 0)::TEXT || ' reads/call'
    FROM pg_stat_statements s
    WHERE shared_blks_read > 0 AND query NOT LIKE '%pg_stat_statements%'
    ORDER BY shared_blks_read DESC
    LIMIT 5;

    RETURN QUERY
    SELECT
        'TOP_BY_TEMP_SPILLS'::TEXT,
        row_number() OVER (ORDER BY temp_blks_written DESC)::INT,
        left(query, 80),
        s.calls,
        round(mean_exec_time::numeric, 1),
        pg_size_pretty(temp_blks_written::bigint * 8192 / nullif(s.calls, 0)) || '/call'
    FROM pg_stat_statements s
    WHERE temp_blks_written > 0 AND query NOT LIKE '%pg_stat_statements%'
    ORDER BY temp_blks_written DESC
    LIMIT 5;
END;
$$ LANGUAGE plpgsql;
```

Test it:

```sql
SELECT * FROM weekly_perf_report();
```

### Task 5 - Document Your Monitoring Setup

Fill out this checklist:

```
MONITORING CHECKLIST - devops-lab-cluster
Last verified: [DATE]

Enhanced Monitoring:  [ ] Enabled   Interval: ___ seconds
Performance Insights: [ ] Enabled   Retention: ___ days
pg_stat_statements:   [ ] Loaded    track: ___
track_io_timing:      [ ] ON

DASHBOARD:
[ ] CloudWatch dashboard created with ___ panels

ALARMS (Tier 1 - Critical):
[ ] TXID Wraparound         threshold: 1.5B
[ ] Connection Exhaustion   threshold: 95% of ___
[ ] CPU Saturation          threshold: 95% for 5 min

ALARMS (Tier 2 - Warning):
[ ] CPU High                threshold: 80% for 10 min
[ ] Commit Latency          threshold: 20ms for 10 min
[ ] Replica Lag             threshold: 100ms for 5 min
[ ] Deadlocks               threshold: > 0

SNS Topics:
  Critical: ___
  Warning: ___

FUNCTIONS INSTALLED:
[ ] connection_health()
[ ] weekly_perf_report()
```

---

## Validation

Run this final check:

```bash
echo "=== Dashboard Validation ==="

echo -n "Enhanced Monitoring: "
aws rds describe-db-instances \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --query "DBInstances[0].MonitoringInterval" \
  --output text --region "$REGION"

echo -n "Performance Insights: "
aws rds describe-db-instances \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --query "DBInstances[0].PerformanceInsightsEnabled" \
  --output text --region "$REGION"

echo -n "Total alarms: "
aws cloudwatch describe-alarms \
  --alarm-name-prefix "Aurora-" \
  --query "length(MetricAlarms)" \
  --output text --region "$REGION"

echo -n "Critical alarms: "
aws cloudwatch describe-alarms \
  --alarm-name-prefix "CRITICAL-" \
  --query "length(MetricAlarms)" \
  --output text --region "$REGION"

echo -n "Warning alarms: "
aws cloudwatch describe-alarms \
  --alarm-name-prefix "WARNING-" \
  --query "length(MetricAlarms)" \
  --output text --region "$REGION"
```
