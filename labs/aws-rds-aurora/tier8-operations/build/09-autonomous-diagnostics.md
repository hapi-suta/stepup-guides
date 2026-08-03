# Tier 8 - Build Guide 09: Autonomous Diagnostics

**Objective:** Design and implement a rule-based health check system for fleet-wide RDS monitoring, build a library of read-only triage queries, configure automated alerting thresholds, and integrate with existing monitoring infrastructure.
**Time:** 40 minutes
**Level:** Expert
**infra_required:** Partial - The query library and design sections are reference material. The alerting and Lambda sections require AWS infrastructure.
**Prerequisites:** Tier 8 Build 03 completed (observability pipelines). At least one running RDS or Aurora PostgreSQL instance. Lambda and EventBridge permissions.

---

## 1. Design: Rule-Based Health Checks at Scale

The goal of autonomous diagnostics is to answer "Is every database in the fleet healthy right now?" without a human manually checking each instance. The system runs checks, evaluates rules, and alerts when a rule is violated.

### System architecture

```
EventBridge Schedule (every 5 min)
         |
         v
Lambda: Fleet Health Check Driver
  - List all RDS instances/clusters in the account
  - For each instance, check CloudWatch metrics against thresholds
  - For instances with direct connectivity, run SQL triage queries
         |
     +---+---+
     |       |
     v       v
SNS Alert  S3 Results
(violations)  (full report)
```

### Health check categories

Organize checks into five categories:

**1. Availability** - Is the database accepting connections?
- Metric: `DatabaseConnections` > 0 (if connections are expected)
- Metric: RDS instance status = `available`
- Check: Can the Lambda connect to the database?

**2. Performance** - Is it responding within acceptable latency?
- Metric: `ReadLatency` < 20ms (alert), < 100ms (critical)
- Metric: `WriteLatency` < 20ms (alert), < 100ms (critical)
- Metric: `CPUUtilization` < 80% (alert), < 95% (critical)

**3. Capacity** - Is it running out of resources?
- Metric: `FreeStorageSpace` > 20% (warn at 20%, critical at 10%)
- Metric: `FreeableMemory` > 10% of total RAM
- Metric: `DatabaseConnections` < 80% of `max_connections`

**4. Replication health** - Are all replicas in sync?
- Metric: `ReplicaLag` or `AuroraReplicaLag` < 30s (warn), < 300s (critical)

**5. PostgreSQL internal health** - Internal metrics only queryable via SQL
- `age(datfrozenxid)` < 1.5 billion (warn at 1B, critical at 1.5B)
- Dead tuple ratio < 20% on large tables
- Lock waits: any sessions in `lock wait` state for > 2 minutes

---

## 2. Read-Only Triage Query Library

All diagnostic queries must be read-only. Use a dedicated read-only database user for the diagnostic system.

### Create the diagnostic user (run on each database)

```sql
-- Create a read-only user for the diagnostic system
CREATE ROLE diagnostics_reader LOGIN PASSWORD '[STRONG-PASSWORD]';

-- Grant read access to pg_stat_* views
GRANT pg_monitor TO diagnostics_reader;
-- pg_monitor is a built-in role that grants read access to all monitoring views

-- If pg_monitor is not available (PostgreSQL < 10), grant individually:
GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO diagnostics_reader;
```

### Triage query 1: Instance overview

```sql
SELECT
  current_database() AS database,
  version() AS pg_version,
  pg_postmaster_start_time() AS started_at,
  now() - pg_postmaster_start_time() AS uptime,
  (SELECT count(*) FROM pg_stat_activity WHERE state != 'idle') AS active_connections,
  (SELECT count(*) FROM pg_stat_activity) AS total_connections,
  current_setting('max_connections')::int AS max_connections,
  round(
    (SELECT count(*) FROM pg_stat_activity)::numeric /
    current_setting('max_connections')::numeric * 100, 2
  ) AS connection_pct_used;
```

### Triage query 2: Long-running queries

```sql
SELECT
  pid,
  now() - query_start AS duration,
  state,
  wait_event_type,
  wait_event,
  left(query, 120) AS query_snippet
FROM pg_stat_activity
WHERE state != 'idle'
  AND query_start < now() - interval '5 minutes'
ORDER BY duration DESC
LIMIT 10;
```

### Triage query 3: Lock waits

```sql
SELECT
  blocked.pid AS blocked_pid,
  blocked.query AS blocked_query,
  now() - blocked.query_start AS blocked_duration,
  blocking.pid AS blocking_pid,
  blocking.query AS blocking_query,
  now() - blocking.query_start AS blocking_duration
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0
ORDER BY blocked_duration DESC;
```

### Triage query 4: Wraparound proximity

```sql
SELECT
  datname,
  age(datfrozenxid) AS xid_age,
  2000000000 - age(datfrozenxid) AS transactions_remaining,
  round(age(datfrozenxid) * 100.0 / 2000000000, 2) AS pct_of_limit,
  CASE
    WHEN age(datfrozenxid) > 1500000000 THEN 'CRITICAL'
    WHEN age(datfrozenxid) > 1000000000 THEN 'WARNING'
    ELSE 'OK'
  END AS status
FROM pg_database
ORDER BY xid_age DESC;
```

### Triage query 5: Table bloat estimate

```sql
SELECT
  schemaname,
  relname,
  n_live_tup,
  n_dead_tup,
  round(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 2) AS dead_pct,
  last_autovacuum,
  last_autoanalyze,
  CASE
    WHEN n_dead_tup > 1000000 AND
         n_dead_tup::numeric / NULLIF(n_live_tup, 0) > 0.2
    THEN 'HIGH BLOAT'
    WHEN n_dead_tup > 100000 AND
         n_dead_tup::numeric / NULLIF(n_live_tup, 0) > 0.1
    THEN 'MODERATE BLOAT'
    ELSE 'OK'
  END AS bloat_status
FROM pg_stat_user_tables
WHERE n_live_tup > 1000
ORDER BY n_dead_tup DESC
LIMIT 20;
```

### Triage query 6: Replication status (run on primary)

```sql
SELECT
  client_addr,
  state,
  sync_state,
  pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS send_lag_bytes,
  pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes,
  replay_lag
FROM pg_stat_replication
ORDER BY replay_lag_bytes DESC NULLS LAST;
```

### Triage query 7: Index usage - unused indexes

```sql
SELECT
  schemaname,
  relname AS table_name,
  indexrelname AS index_name,
  idx_scan AS index_scans,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 20;
```

Zero-scan indexes consume storage and slow down writes without providing query benefit. Candidates for removal (verify first - some indexes exist for constraint enforcement).

### Triage query 8: Cache hit ratio

```sql
SELECT
  sum(heap_blks_read) AS heap_read,
  sum(heap_blks_hit) AS heap_hit,
  round(
    sum(heap_blks_hit)::numeric /
    NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0) * 100, 2
  ) AS cache_hit_ratio
FROM pg_statio_user_tables;
```

A cache hit ratio below 95% indicates the working set is not fitting in memory. Below 90% on a production OLTP database typically indicates a right-sizing or memory pressure problem.

---

## 3. Automated Alerting Thresholds

### CloudWatch metric alarm thresholds reference

Define these alarms for every RDS instance in the fleet. Use a consistent naming convention: `rds-[METRIC]-[SEVERITY]-[INSTANCE-ID]`.

```bash
# Create all standard alarms for an instance
INSTANCE_ID=[INSTANCE-ID]
ACCOUNT_ID=[ACCOUNT-ID]
REGION=[REGION]
SNS_TOPIC=arn:aws:sns:${REGION}:${ACCOUNT_ID}:rds-alerts

# CPU Warning: >80% for 15 minutes
aws cloudwatch put-metric-alarm \
  --alarm-name rds-cpu-warn-${INSTANCE_ID} \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=${INSTANCE_ID} \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions ${SNS_TOPIC} \
  --ok-actions ${SNS_TOPIC} \
  --treat-missing-data notBreaching \
  --region ${REGION}

# CPU Critical: >95% for 5 minutes
aws cloudwatch put-metric-alarm \
  --alarm-name rds-cpu-crit-${INSTANCE_ID} \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=${INSTANCE_ID} \
  --statistic Average \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 95 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions ${SNS_TOPIC} \
  --treat-missing-data notBreaching \
  --region ${REGION}

# Free storage warning: <20% (set threshold based on actual instance storage)
# Example for 500GB instance: 20% = 100GB = 107374182400 bytes
aws cloudwatch put-metric-alarm \
  --alarm-name rds-storage-warn-${INSTANCE_ID} \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=${INSTANCE_ID} \
  --statistic Minimum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 107374182400 \
  --comparison-operator LessThanThreshold \
  --alarm-actions ${SNS_TOPIC} \
  --treat-missing-data notBreaching \
  --region ${REGION}

# Connection count warning: >200 (adjust to your max_connections setting)
aws cloudwatch put-metric-alarm \
  --alarm-name rds-connections-warn-${INSTANCE_ID} \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=${INSTANCE_ID} \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 3 \
  --threshold 200 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions ${SNS_TOPIC} \
  --treat-missing-data notBreaching \
  --region ${REGION}

# Write latency warning: >20ms
aws cloudwatch put-metric-alarm \
  --alarm-name rds-write-latency-warn-${INSTANCE_ID} \
  --namespace AWS/RDS \
  --metric-name WriteLatency \
  --dimensions Name=DBInstanceIdentifier,Value=${INSTANCE_ID} \
  --statistic Average \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 0.02 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions ${SNS_TOPIC} \
  --treat-missing-data notBreaching \
  --region ${REGION}
```

### Bulk alarm creation for the entire fleet

Script to apply standard alarms to every instance in the account:

```bash
#!/usr/bin/env bash
# Apply standard CloudWatch alarms to all RDS instances in a region

REGION=[REGION]
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SNS_TOPIC="arn:aws:sns:${REGION}:${ACCOUNT_ID}:rds-alerts"

INSTANCES=$(aws rds describe-db-instances \
  --query 'DBInstances[*].DBInstanceIdentifier' \
  --output text \
  --region ${REGION})

for INSTANCE_ID in ${INSTANCES}; do
  echo "Creating alarms for: ${INSTANCE_ID}"

  # CPU warning
  aws cloudwatch put-metric-alarm \
    --alarm-name "rds-cpu-warn-${INSTANCE_ID}" \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=${INSTANCE_ID} \
    --statistic Average \
    --period 300 \
    --evaluation-periods 3 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --alarm-actions ${SNS_TOPIC} \
    --ok-actions ${SNS_TOPIC} \
    --treat-missing-data notBreaching \
    --region ${REGION} 2>&1

  echo "  CPU alarm created"
done

echo "Done. Alarms applied to all instances."
```

---

## 4. Fleet-Wide Diagnostic Approach

### Lambda-based fleet health checker

This Lambda function runs on a schedule, checks all RDS instances in the account, and publishes a health summary.

```python
import boto3
import json
import os
from datetime import datetime, timedelta, timezone

def get_metric_value(cw, instance_id, metric_name, period_minutes=5):
    """Retrieve the most recent value of a CloudWatch metric for an RDS instance."""
    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(minutes=period_minutes)

    response = cw.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName=metric_name,
        Dimensions=[{'Name': 'DBInstanceIdentifier', 'Value': instance_id}],
        StartTime=start_time,
        EndTime=end_time,
        Period=period_minutes * 60,
        Statistics=['Average', 'Maximum', 'Minimum']
    )

    datapoints = response.get('Datapoints', [])
    if not datapoints:
        return None

    latest = sorted(datapoints, key=lambda x: x['Timestamp'])[-1]
    return latest

def check_instance_health(cw, instance: dict) -> dict:
    """Run health checks for a single RDS instance."""
    instance_id = instance['DBInstanceIdentifier']
    violations = []

    # Check CPU
    cpu_data = get_metric_value(cw, instance_id, 'CPUUtilization')
    if cpu_data:
        cpu_avg = cpu_data.get('Average', 0)
        if cpu_avg > 95:
            violations.append({'metric': 'CPUUtilization', 'value': cpu_avg, 'severity': 'CRITICAL', 'threshold': 95})
        elif cpu_avg > 80:
            violations.append({'metric': 'CPUUtilization', 'value': cpu_avg, 'severity': 'WARNING', 'threshold': 80})

    # Check connections
    conn_data = get_metric_value(cw, instance_id, 'DatabaseConnections')
    if conn_data:
        max_conns_param = 200  # adjust to your max_connections setting
        conn_max = conn_data.get('Maximum', 0)
        if conn_max > max_conns_param * 0.9:
            violations.append({'metric': 'DatabaseConnections', 'value': conn_max, 'severity': 'CRITICAL', 'threshold': max_conns_param * 0.9})

    # Check write latency
    latency_data = get_metric_value(cw, instance_id, 'WriteLatency')
    if latency_data:
        latency_avg = latency_data.get('Average', 0) * 1000  # convert to ms
        if latency_avg > 100:
            violations.append({'metric': 'WriteLatency_ms', 'value': round(latency_avg, 2), 'severity': 'CRITICAL', 'threshold': 100})
        elif latency_avg > 20:
            violations.append({'metric': 'WriteLatency_ms', 'value': round(latency_avg, 2), 'severity': 'WARNING', 'threshold': 20})

    return {
        'instance_id': instance_id,
        'status': 'CRITICAL' if any(v['severity'] == 'CRITICAL' for v in violations)
                  else 'WARNING' if violations
                  else 'OK',
        'violations': violations
    }

def handler(event, context):
    region = os.environ.get('AWS_REGION', 'us-east-1')
    sns_topic = os.environ.get('SNS_TOPIC_ARN')

    rds = boto3.client('rds', region_name=region)
    cw = boto3.client('cloudwatch', region_name=region)
    sns = boto3.client('sns', region_name=region)
    s3 = boto3.client('s3', region_name=region)

    # List all instances
    paginator = rds.get_paginator('describe_db_instances')
    instances = []
    for page in paginator.paginate():
        instances.extend(page['DBInstances'])

    # Run health checks
    results = [check_instance_health(cw, inst) for inst in instances]

    # Summarize
    critical = [r for r in results if r['status'] == 'CRITICAL']
    warning = [r for r in results if r['status'] == 'WARNING']
    healthy = [r for r in results if r['status'] == 'OK']

    report = {
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'total_instances': len(results),
        'critical': len(critical),
        'warning': len(warning),
        'healthy': len(healthy),
        'critical_details': critical,
        'warning_details': warning
    }

    # Alert if any critical violations
    if critical and sns_topic:
        message = f"CRITICAL: {len(critical)} RDS instance(s) have critical violations.\n\n"
        for item in critical:
            message += f"Instance: {item['instance_id']}\n"
            for v in item['violations']:
                message += f"  - {v['metric']}: {v['value']} (threshold: {v['threshold']})\n"

        sns.publish(
            TopicArn=sns_topic,
            Subject='RDS Fleet Health: CRITICAL',
            Message=message
        )

    # Store full report in S3
    bucket = os.environ.get('RESULTS_BUCKET')
    if bucket:
        key = f"fleet-health/{datetime.now(timezone.utc).strftime('%Y/%m/%d/%H%M%S')}.json"
        s3.put_object(Bucket=bucket, Key=key, Body=json.dumps(report, indent=2))

    return report
```

Deploy this Lambda with:
- Runtime: Python 3.12
- Timeout: 5 minutes
- Memory: 256 MB
- Environment variables: `SNS_TOPIC_ARN`, `RESULTS_BUCKET`
- IAM role: `rds:DescribeDBInstances`, `cloudwatch:GetMetricStatistics`, `sns:Publish`, `s3:PutObject`

### Schedule the health checker

```bash
aws events put-rule \
  --name rds-fleet-health-check \
  --schedule-expression "rate(5 minutes)" \
  --description "Run RDS fleet health check every 5 minutes" \
  --state ENABLED \
  --region [REGION]

aws events put-targets \
  --rule rds-fleet-health-check \
  --targets '[{
    "Id": "1",
    "Arn": "[LAMBDA-ARN]"
  }]' \
  --region [REGION]
```

---

## 5. Integration with Monitoring Stack

The autonomous diagnostic system generates structured output. Route that output to your existing monitoring tools.

### SNS to Slack/PagerDuty integration

SNS supports HTTPS subscriptions. Most monitoring tools (PagerDuty, OpsGenie, Slack via webhooks) accept SNS notifications directly.

```bash
# Subscribe PagerDuty to the RDS alerts SNS topic
aws sns subscribe \
  --topic-arn [SNS-TOPIC-ARN] \
  --protocol https \
  --notification-endpoint [PAGERDUTY-INTEGRATION-URL] \
  --region [REGION]
```

### RDS Event Subscriptions for instance-level events

CloudWatch metrics catch performance issues. RDS Event Subscriptions catch lifecycle events.

```bash
aws rds create-event-subscription \
  --subscription-name rds-all-events \
  --sns-topic-arn [SNS-TOPIC-ARN] \
  --source-type db-instance \
  --event-categories \
    availability failover failure low-storage maintenance notification recovery restoration \
  --enabled \
  --region [REGION]
```

This routes all critical RDS instance events to your SNS topic, which then routes to your alerting system.

---

## Viewing Diagnostics in the Console

The AWS Console gives you access to three powerful tools for understanding what is happening with your RDS instance right now: **DevOps Guru**, **Performance Insights**, and **CloudWatch anomaly detection**. You do not need any CLI access to use these - they are fully available in the browser.

### DevOps Guru: View Insights for Your RDS Instance

AWS DevOps Guru uses machine learning to detect unusual behavior in your AWS resources and surfaces them as **insights**. An insight is DevOps Guru's way of saying "something looks abnormal here."

1. Open the AWS Console at [https://console.aws.amazon.com](https://console.aws.amazon.com) and sign in.
2. In the top search bar, type `DevOps Guru` and click **DevOps Guru** under Services.
3. The first page you land on is the **Dashboard**. It shows:
   - **Reactive insights** - problems DevOps Guru has already detected.
   - **Proactive insights** - potential problems predicted before they cause an outage.
   - A summary count for each severity level (High, Medium, Low).
4. In the left sidebar, click **Insights**.
5. You will see a list of all current insights. Each row shows:
   - **Insight name** - a description of the anomaly.
   - **Status** - Ongoing or Closed.
   - **Severity** - High, Medium, or Low.
   - **Start time** - when DevOps Guru first noticed the anomaly.
6. Click any insight to open it. Inside you will see:
   - **Description** - what DevOps Guru detected.
   - **Recommendations** - specific actions to investigate or fix the issue.
   - **Related events** - CloudWatch alarms or RDS events that fired around the same time.
   - **Anomalous metrics** - a graph showing the metric that looked unusual, with the anomaly period highlighted in red or orange.

   Look for insights referencing your RDS instance identifier in the **Affected resources** section.

7. To narrow down to only RDS insights:
   - On the **Insights** page, click the **Filter** dropdown.
   - Under **Resource type**, select **AWS RDS**.
   - Click **Apply**.

   The list will now show only insights related to your RDS and Aurora resources.

> If you see no insights, that is expected - it means DevOps Guru has not detected any anomalies. DevOps Guru needs to be enabled for your account first. To check, click **Settings** in the left sidebar and confirm your RDS resources are included in coverage.

### Performance Insights: View the Database Load Dashboard

Performance Insights shows a real-time and historical view of what your database is spending time doing - broken down by wait events, SQL statements, users, and hosts.

1. In the top search bar, type `RDS` and click **RDS** under Services.
2. In the left sidebar, click **Databases**.
3. Click the **writer instance** of your Aurora cluster (or your standalone RDS instance). This is the row whose **Role** column shows **Writer instance**.
4. Click the **Monitoring** tab.
5. Scroll down until you see the **Performance Insights** section. Click **View in Performance Insights** (or look for a **Performance Insights** button near the top of the Monitoring tab).

   This opens the Performance Insights dashboard in a new view.

6. The dashboard has three main sections:
   - **Counter metrics** (top) - shows database-level counters like commits per second and rows examined.
   - **Database load** (middle) - the most important chart. The x-axis is time. The y-axis is **Average Active Sessions (AAS)**. Each colored band represents a different wait event type. The horizontal dashed line is your **max vCPUs** limit.
   - **Top load items** (bottom) - a table breaking down what is consuming the most load. By default it shows **Wait events**, but you can switch the **Slice by** dropdown to **SQL**, **User**, **Host**, or **Application**.

7. To understand what is causing a spike in the **Database load** chart:
   - Click on a spike in the chart. The time range selector will highlight that period.
   - Look at the **Top SQL** tab in the **Top load items** table below. You will see the exact SQL statements contributing to load during that window.
   - Click any SQL row to expand it and see the full query text, execution count, average latency, and average rows returned.

8. To change the time window:
   - Use the **Time range** selector at the top right. Options include the last 1 hour, 3 hours, 24 hours, 1 week, and custom ranges.

9. If the **Performance Insights** button is missing or greyed out, Performance Insights may not be enabled on your instance. To enable it:
   - Go back to the **Databases** list.
   - Select your instance, click **Modify**.
   - Scroll to the **Additional configuration** section.
   - Check **Enable Performance Insights**.
   - Click **Continue** and apply the change (no downtime required for this setting).

### CloudWatch Anomaly Detection: Check Anomalous Metrics

CloudWatch anomaly detection trains a model on historical metric data and draws an expected range (a band) around each metric. When a metric goes outside the band, it triggers an alarm.

1. In the top search bar, type `CloudWatch` and click **CloudWatch** under Services.
2. In the left sidebar, click **Alarms**, then click **All alarms**.
3. Look for alarms with names starting with `rds-` (the naming convention from the alerting section of this guide). Each alarm has a **State** column showing:
   - **OK** (green) - the metric is within threshold.
   - **In alarm** (red) - the metric has breached the threshold.
   - **Insufficient data** (grey) - not enough data points yet.
4. To see only RDS alarms that have fired, use the **Filter alarms** search box at the top and type `rds-`. Press Enter.
5. Click any alarm name to open its detail page. You will see:
   - A **History** tab showing every state change the alarm has had.
   - A metric graph with the threshold line drawn on it.
   - The current metric value vs. the threshold.

6. To view anomaly detection specifically (separate from threshold alarms):
   - In the left sidebar, click **Metrics**.
   - Click **All metrics**.
   - Under the **AWS namespaces** section, click **RDS**.
   - Click **Per-Database Metrics**.
   - Find your database identifier in the list and check the box next to the metric you want to inspect (for example, `CPUUtilization`).
   - The metric graph will appear at the top of the page.
   - Click **Graphed metrics** (the tab below the graph).
   - Click the **+** icon to the right of your metric row, or open the **Add math** dropdown and choose **Anomaly detection**.
   - CloudWatch will draw a grey band around the metric representing the expected range. Spikes outside the band are anomalies.

7. To view which metrics DevOps Guru flagged as anomalous (tying back to the insights you viewed earlier):
   - Go back to **DevOps Guru** - **Insights**.
   - Open any insight.
   - In the **Anomalous metrics** section, click any metric graph.
   - This takes you directly to the CloudWatch graph for that metric with the anomaly period highlighted, so you can zoom in and correlate with other events.

---

## Summary

- Autonomous diagnostics scales DBA expertise across the fleet. The goal is human-in-the-loop only for the decisions that require human judgment, not for routine health checks.
- All diagnostic queries must be read-only. Use a dedicated `diagnostics_reader` role with `pg_monitor` membership.
- The five health check categories (availability, performance, capacity, replication, PostgreSQL internals) cover the majority of production issues.
- Bulk alarm creation scripts ensure every new instance gets the standard alarm set applied consistently - not just the ones a human happened to check.
- Structured output (JSON to S3) builds a historical record of fleet health that enables trend analysis and capacity planning.

**Next:** Review the USE exercises to apply everything from this tier.

**Reference:** [Concepts: Operations at Scale](../concepts/operations.md)
