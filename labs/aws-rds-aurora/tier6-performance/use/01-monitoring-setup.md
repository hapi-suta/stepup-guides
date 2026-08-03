# USE 01 - Set Up a Complete Monitoring Pipeline

**Time:** 45 minutes
**Difficulty:** Intermediate
**Prerequisites:** Build 01 and Build 02 complete. SNS topic created. `$DB_INSTANCE_ID`, `$REGION`, `$SNS_TOPIC_ARN` set.

---

## Objective

Build a production-ready monitoring stack for your RDS PostgreSQL instance. By the end you will have:
- Enhanced Monitoring at 60-second granularity
- Performance Insights with 7-day retention
- A CloudWatch dashboard with 8 panels
- 8 CloudWatch alarms covering the most critical failure modes
- A weekly pg_stat_statements report function

This is the minimum setup you should have on every production RDS instance before it goes live.

---

## Exercise Tasks

### Task 1 - Verify Monitoring is Enabled

Run these checks and confirm each returns the expected result.

**Check Enhanced Monitoring:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query "DBInstances[0].{MonitoringInterval:MonitoringInterval,PIEnabled:PerformanceInsightsEnabled}" \
  --output table \
  --region "$REGION"
```

Expected output:
```
---------------------------------------------
|          DescribeDBInstances              |
+--------------------+----------------------+
|  MonitoringInterval|  PIEnabled           |
+--------------------+----------------------+
|  60                |  True                |
+--------------------+----------------------+
```

If either is missing, return to Build 01 and Build 02 and enable them.

**Check pg_stat_statements:**

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT extname FROM pg_extension WHERE extname = 'pg_stat_statements';"
```

---

### Task 2 - Build the Alarm Stack

Create all 8 alarms using this script. Replace the threshold values based on your instance's max_connections:

```bash
# Get max_connections
MAX_CONN=$(psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t \
  -c "SHOW max_connections;" | tr -d ' ')
echo "max_connections: $MAX_CONN"

# Alarm 1: High CPU
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-CPU-High-${DB_INSTANCE_ID}" \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --ok-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"

# Alarm 2: CPU Critical
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-CPU-Critical-${DB_INSTANCE_ID}" \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --statistic Average \
  --period 60 \
  --evaluation-periods 3 \
  --threshold 95 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"

# Alarm 3: Connections High (80% of max)
CONN_THRESHOLD=$(( MAX_CONN * 80 / 100 ))
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-Connections-High-${DB_INSTANCE_ID}" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --statistic Average \
  --period 60 \
  --evaluation-periods 3 \
  --threshold "$CONN_THRESHOLD" \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"

# Alarm 4: Low Freeable Memory (less than 10% of instance RAM)
# Adjust 3221225472 for your instance (3GB = 10% of 32GB)
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-Memory-Low-${DB_INSTANCE_ID}" \
  --metric-name FreeableMemory \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 3221225472 \
  --comparison-operator LessThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"

# Alarm 5: Low Storage (10GB)
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-Storage-Low-${DB_INSTANCE_ID}" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 10737418240 \
  --comparison-operator LessThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"

# Alarm 6: Read Latency High (>20ms)
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-ReadLatency-High-${DB_INSTANCE_ID}" \
  --metric-name ReadLatency \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 0.02 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"

# Alarm 7: Write Latency High (>10ms)
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-WriteLatency-High-${DB_INSTANCE_ID}" \
  --metric-name WriteLatency \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 0.01 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"

# Alarm 8: TXID Wraparound (1.5 billion)
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-TXID-Wraparound-${DB_INSTANCE_ID}" \
  --metric-name MaximumUsedTransactionIDs \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --statistic Maximum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1500000000 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"

echo "All 8 alarms created"
```

### Task 3 - Verify All Alarms Are in OK State

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "RDS-" \
  --query "MetricAlarms[].{Name:AlarmName,State:StateValue}" \
  --output table \
  --region "$REGION"
```

All alarms should show `OK`. If any show `INSUFFICIENT_DATA`, wait 5 minutes and recheck.

### Task 4 - Install the Weekly Performance Report Function

Connect to your database and run the function from Build 05:

```sql
CREATE OR REPLACE FUNCTION weekly_perf_report()
RETURNS TABLE(
    report_section TEXT,
    rank INT,
    query_snippet TEXT,
    calls BIGINT,
    avg_ms NUMERIC,
    metric_value TEXT
) AS $$
BEGIN
    -- Top 5 by total time
    RETURN QUERY
    SELECT
        'TOP_TOTAL_TIME'::TEXT,
        row_number() OVER (ORDER BY total_exec_time DESC)::INT,
        left(query, 80),
        s.calls,
        round(mean_exec_time::numeric, 1),
        round(total_exec_time / 1000, 0)::TEXT || 's total'
    FROM pg_stat_statements s
    WHERE query NOT LIKE '%pg_stat_statements%'
    ORDER BY total_exec_time DESC
    LIMIT 5;

    -- Top 5 disk readers
    RETURN QUERY
    SELECT
        'TOP_DISK_READS'::TEXT,
        row_number() OVER (ORDER BY shared_blks_read DESC)::INT,
        left(query, 80),
        s.calls,
        round(mean_exec_time::numeric, 1),
        round(shared_blks_read::numeric / nullif(s.calls, 0), 0)::TEXT || ' reads/call'
    FROM pg_stat_statements s
    WHERE shared_blks_read > 0
      AND query NOT LIKE '%pg_stat_statements%'
    ORDER BY shared_blks_read DESC
    LIMIT 5;

    -- Top 5 temp spills
    RETURN QUERY
    SELECT
        'TOP_TEMP_SPILLS'::TEXT,
        row_number() OVER (ORDER BY temp_blks_written DESC)::INT,
        left(query, 80),
        s.calls,
        round(mean_exec_time::numeric, 1),
        pg_size_pretty(temp_blks_written::bigint * 8192 / nullif(s.calls, 0)) || '/call'
    FROM pg_stat_statements s
    WHERE temp_blks_written > 0
      AND query NOT LIKE '%pg_stat_statements%'
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

Fill out this checklist and keep it with your runbook:

```
MONITORING CHECKLIST - [DB_INSTANCE_ID]
Last verified: [DATE]

Enhanced Monitoring:  [ ] Enabled   Interval: ___ seconds
Performance Insights: [ ] Enabled   Retention: ___ days
pg_stat_statements:   [ ] Loaded    track: ___
track_io_timing:      [ ] ON

ALARMS:
[ ] RDS-CPU-High          threshold: 80%
[ ] RDS-CPU-Critical      threshold: 95%
[ ] RDS-Connections-High  threshold: ___
[ ] RDS-Memory-Low        threshold: ___GB
[ ] RDS-Storage-Low       threshold: 10GB
[ ] RDS-ReadLatency-High  threshold: 20ms
[ ] RDS-WriteLatency-High threshold: 10ms
[ ] RDS-TXID-Wraparound   threshold: 1.5B

SNS Topic: ___
Alert recipients: ___
```

---

## Validation

Run this final check to confirm the monitoring pipeline is complete:

```bash
echo "=== Monitoring Pipeline Validation ==="

echo -n "Enhanced Monitoring: "
aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query "DBInstances[0].MonitoringInterval" \
  --output text --region "$REGION"

echo -n "Performance Insights: "
aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query "DBInstances[0].PerformanceInsightsEnabled" \
  --output text --region "$REGION"

echo -n "Alarm count: "
aws cloudwatch describe-alarms \
  --alarm-name-prefix "RDS-${DB_INSTANCE_ID}" \
  --query "length(MetricAlarms)" \
  --output text --region "$REGION"
```

Expected output (yours will differ):
```
=== Monitoring Pipeline Validation ===
Enhanced Monitoring: 60
Performance Insights: True
Alarm count: 8
```
