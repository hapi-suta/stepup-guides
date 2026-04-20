# BUILD 04 - Monitoring and Performance on RDS

## What You Will Build

By the end of this guide you will know how to monitor RDS PostgreSQL using CloudWatch metrics, Enhanced Monitoring, Performance Insights, pg_stat_statements, event subscriptions, and alarms. These are the tools you use daily to keep RDS healthy.

---

## Prerequisites

- Completed BUILD 01 (RDS instance `suta-pg-lab` running)
- AWS CLI v2 configured
- psql client installed

---

## Step 1 - CloudWatch Metrics for RDS

Every RDS instance automatically sends metrics to CloudWatch. No setup required.

List available metrics for your instance:

```bash
aws cloudwatch list-metrics \
    --namespace AWS/RDS \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab \
    --query "Metrics[*].MetricName" \
    --output text > /tmp/rds-metrics.txt
```

This saves all metric names to a file.

```bash
tr '\t' '\n' < /tmp/rds-metrics.txt > /tmp/rds-metrics-lines.txt
```

This converts tabs to newlines so each metric appears on its own line.

```bash
sort /tmp/rds-metrics-lines.txt
```

This orders the metrics alphabetically for easy reading.

Expected output (yours will differ):

```
CPUUtilization
DatabaseConnections
DiskQueueDepth
FreeStorageSpace
FreeableMemory
NetworkReceiveThroughput
NetworkTransmitThroughput
ReadIOPS
ReadLatency
ReadThroughput
SwapUsage
WriteIOPS
WriteLatency
WriteThroughput
```

The most important metrics to watch:

| Metric | What It Tells You | Concern Threshold |
|--------|-------------------|-------------------|
| CPUUtilization | Percent CPU used | Above 80% sustained |
| FreeableMemory | Available RAM in bytes | Below 256 MB |
| FreeStorageSpace | Available disk in bytes | Below 10% of total |
| DatabaseConnections | Active connections | Near max_connections |
| ReadLatency / WriteLatency | Average I/O time in seconds | Above 10ms |
| DiskQueueDepth | Number of queued I/O requests | Above 10 |

---

## Step 2 - Query Specific Metrics

Get CPU utilization for the last hour:

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics Average Maximum \
    --query "sort_by(Datapoints, &Timestamp)[*].{Time:Timestamp,AvgCPU:Average,MaxCPU:Maximum}" \
    --output table
```

Flag breakdown:
- `--namespace AWS/RDS` - the CloudWatch namespace for RDS metrics
- `--metric-name CPUUtilization` - the specific metric to query
- `--dimensions` - filters to your specific instance
- `--start-time` / `--end-time` - time range (1 hour window)
- `--period 300` - aggregate data in 5-minute intervals (seconds)
- `--statistics Average Maximum` - compute both average and max per period

Expected output (yours will differ):

```
------------------------------------------------------------
|                  GetMetricStatistics                     |
+--------+----------------------------+-------------------+
| AvgCPU |           Time             |      MaxCPU       |
+--------+----------------------------+-------------------+
|  3.2   |  2024-01-15T11:40:00+00:00 |  5.1              |
|  2.8   |  2024-01-15T11:45:00+00:00 |  4.3              |
|  4.1   |  2024-01-15T11:50:00+00:00 |  7.2              |
...
```

Get free storage space:

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name FreeStorageSpace \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics Average \
    --query "sort_by(Datapoints, &Timestamp) | [-1].{FreeSpaceGB: Average}" \
    --output text
```

The value is in bytes. Divide by 1073741824 to get GB.

---

## Step 3 - Enable Enhanced Monitoring

Standard CloudWatch metrics update every 60 seconds. Enhanced Monitoring collects OS-level metrics every 1-60 seconds.

First, create the IAM role for Enhanced Monitoring:

```bash
aws iam create-role \
    --role-name rds-enhanced-monitoring \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "monitoring.rds.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'
```

This creates a role that allows the RDS monitoring service to assume it.

Attach the managed policy:

```bash
aws iam attach-role-policy \
    --role-name rds-enhanced-monitoring \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole
```

This grants the role permission to publish Enhanced Monitoring data to CloudWatch Logs.

Get the role ARN:

```bash
MONITORING_ROLE_ARN=$(aws iam get-role --role-name rds-enhanced-monitoring --query "Role.Arn" --output text)
```

Enable Enhanced Monitoring on your instance:

```bash
aws rds modify-db-instance \
    --db-instance-identifier suta-pg-lab \
    --monitoring-interval 5 \
    --monitoring-role-arn "${MONITORING_ROLE_ARN}" \
    --apply-immediately
```

The `--monitoring-interval 5` means data is collected every 5 seconds. Valid values: 0 (off), 1, 5, 10, 15, 30, 60 seconds.

Enhanced Monitoring provides these additional metrics that standard CloudWatch does not:
- Per-process CPU and memory
- OS-level file system usage
- Disk I/O per device
- Network interface statistics
- Load average

---

## Step 4 - Enable Performance Insights

Performance Insights is the most powerful monitoring tool for RDS. It shows you exactly which queries are consuming resources and what they are waiting on.

```bash
aws rds modify-db-instance \
    --db-instance-identifier suta-pg-lab \
    --enable-performance-insights \
    --performance-insights-retention-period 7 \
    --apply-immediately
```

The `--enable-performance-insights` turns on the feature. `--performance-insights-retention-period 7` keeps 7 days of data (free tier). You can set 731 days (2 years) for the paid tier.

Wait for the modification:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab
```

Verify it is enabled:

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{PerformanceInsights:PerformanceInsightsEnabled,Retention:PerformanceInsightsRetentionPeriod}" \
    --output table
```

Expected output:

```
-------------------------------------------
|          DescribeDBInstances            |
+--------------------+--------------------+
| PerformanceInsights|      Retention     |
+--------------------+--------------------+
|  True              |  7                 |
+--------------------+--------------------+
```

---

## Step 5 - Query Performance Insights Data

Get the DBI resource ID (Performance Insights uses this, not the instance identifier):

```bash
DBI_RESOURCE_ID=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].DbiResourceId" --output text)
```

Get the top wait events over the last hour:

```bash
aws pi get-resource-metrics \
    --service-type RDS \
    --identifier "${DBI_RESOURCE_ID}" \
    --metric-queries '[{"Metric": "db.load.avg", "GroupBy": {"Group": "db.wait_event"}}]' \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period-in-seconds 300
```

The `--metric-queries` specifies what to retrieve. `db.load.avg` is the average active sessions (AAS) metric. `GroupBy db.wait_event` breaks down the load by what the database is waiting on.

Common PostgreSQL wait events:

| Wait Event | Category | Meaning |
|------------|----------|---------|
| CPU | CPU | Query executing on CPU |
| IO:DataFileRead | IO | Reading data from disk |
| IO:WALWrite | IO | Writing WAL records |
| Lock:transactionid | Lock | Waiting for row lock |
| LWLock:BufferMapping | LWLock | Shared buffer contention |
| Client:ClientRead | Client | Waiting for client to send data |

Get the top SQL queries by load:

```bash
aws pi get-resource-metrics \
    --service-type RDS \
    --identifier "${DBI_RESOURCE_ID}" \
    --metric-queries '[{"Metric": "db.load.avg", "GroupBy": {"Group": "db.sql", "Limit": 5}}]' \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period-in-seconds 300
```

The `GroupBy db.sql` with `Limit 5` returns the top 5 SQL statements by average active sessions.

---

## Step 6 - Enable pg_stat_statements

pg_stat_statements tracks execution statistics for all SQL statements. You enabled the extension in BUILD 01 via `shared_preload_libraries`. Now activate it in the database.

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

This creates the extension in the current database. The `IF NOT EXISTS` guard prevents errors if it already exists.

Check the top queries by total time:

```sql
SELECT
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    round((100 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 2) AS pct,
    substring(query, 1, 80) AS query_preview
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

This ranks queries by total execution time. `calls` is how many times the query ran. `total_ms` is total time across all calls. `avg_ms` is average per call. `pct` is what percentage of total database time this query consumes.

Expected output (yours will differ):

```
 calls | total_ms | avg_ms | pct   | query_preview
-------+----------+--------+-------+------------------------------------------
    47 |   234.56 |   4.99 | 35.21 | SELECT * FROM recovery_test
    12 |   123.45 |  10.29 | 18.53 | INSERT INTO recovery_test (data) VALUES
   103 |    89.12 |   0.87 | 13.38 | SELECT version()
...
```

Reset the statistics (do this periodically or after deployments):

```sql
SELECT pg_stat_statements_reset();
```

Exit psql:

```sql
\q
```

---

## Step 7 - Create an RDS Event Subscription

Event subscriptions send notifications when important things happen to your RDS instances (failovers, maintenance, configuration changes).

First, create an SNS topic:

```bash
aws sns create-topic \
    --name suta-rds-events
```

This creates an SNS topic that will receive RDS event notifications.

Expected output (yours will differ):

```json
{
    "TopicArn": "arn:aws:sns:us-east-1:123456789012:suta-rds-events"
}
```

Save the ARN:

```bash
TOPIC_ARN=$(aws sns create-topic --name suta-rds-events --query "TopicArn" --output text)
```

Subscribe your email:

```bash
aws sns subscribe \
    --topic-arn "${TOPIC_ARN}" \
    --protocol email \
    --notification-endpoint your-email@example.com
```

Replace `your-email@example.com` with your actual email. You will receive a confirmation email that you must click.

Create the RDS event subscription:

```bash
aws rds create-event-subscription \
    --subscription-name suta-rds-events \
    --sns-topic-arn "${TOPIC_ARN}" \
    --source-type db-instance \
    --source-ids suta-pg-lab \
    --event-categories "availability" "failover" "failure" "maintenance" "configuration change"
```

Flag breakdown:
- `--subscription-name` - unique name for this subscription
- `--sns-topic-arn` - where to send events
- `--source-type db-instance` - subscribe to instance events (could also be db-cluster, db-snapshot, etc.)
- `--source-ids` - which specific instances to monitor
- `--event-categories` - which types of events to receive

---

## Step 8 - Set Up CloudWatch Alarms

Create an alarm for high CPU:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name suta-rds-high-cpu \
    --alarm-description "RDS CPU above 80% for 5 minutes" \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions "${TOPIC_ARN}" \
    --ok-actions "${TOPIC_ARN}" \
    --tags Key=Environment,Value=lab
```

Flag breakdown:
- `--period 300` - evaluate every 5 minutes (300 seconds)
- `--threshold 80` - alarm when CPU exceeds 80%
- `--comparison-operator GreaterThanThreshold` - trigger when metric is above threshold
- `--evaluation-periods 1` - alarm after 1 consecutive breach (5 minutes total)
- `--alarm-actions` - send notification when alarm triggers
- `--ok-actions` - send notification when alarm clears

Create an alarm for low storage:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name suta-rds-low-storage \
    --alarm-description "RDS free storage below 5 GB" \
    --namespace AWS/RDS \
    --metric-name FreeStorageSpace \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab \
    --statistic Average \
    --period 300 \
    --threshold 5368709120 \
    --comparison-operator LessThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions "${TOPIC_ARN}" \
    --tags Key=Environment,Value=lab
```

The threshold is in bytes. 5368709120 bytes = 5 GB.

Create an alarm for high database connections:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name suta-rds-high-connections \
    --alarm-description "RDS connections above 80" \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions "${TOPIC_ARN}" \
    --tags Key=Environment,Value=lab
```

The `--evaluation-periods 2` means the metric must exceed 80 for two consecutive periods (10 minutes total) before alarming. This avoids false alarms from brief connection spikes.

---

## Step 9 - Check Alarm Status

```bash
aws cloudwatch describe-alarms \
    --alarm-name-prefix suta-rds \
    --query "MetricAlarms[*].{Name:AlarmName,State:StateValue,Metric:MetricName,Threshold:Threshold}" \
    --output table
```

Expected output:

```
----------------------------------------------------------------------
|                        DescribeAlarms                              |
+---------------------------+------------+-------------------+-------+
|           Name            |   State    |      Metric       |Threshold|
+---------------------------+------------+-------------------+---------+
| suta-rds-high-connections | OK         | DatabaseConnections| 80    |
| suta-rds-high-cpu         | OK         | CPUUtilization     | 80    |
| suta-rds-low-storage      | OK         | FreeStorageSpace   | 5.37e9|
+---------------------------+------------+-------------------+---------+
```

All alarms should be in `OK` state.

---

## Step 10 - View RDS Events

Check recent events for your instance:

```bash
aws rds describe-events \
    --source-identifier suta-pg-lab \
    --source-type db-instance \
    --duration 1440 \
    --query "Events[*].{Time:Date,Message:Message}" \
    --output table
```

The `--duration 1440` shows events from the last 1440 minutes (24 hours).

Expected output (yours will differ):

```
-------------------------------------------------------------------
|                        DescribeEvents                           |
+----------------------------+------------------------------------+
|           Time             |              Message               |
+----------------------------+------------------------------------+
| 2024-01-15T12:30:00+00:00 | DB instance created                |
| 2024-01-15T12:38:00+00:00 | Finished updating DB parameter..  |
| 2024-01-15T12:40:00+00:00 | DB instance restarted              |
+----------------------------+------------------------------------+
```

---

## Summary

You set up:
- CloudWatch metrics for CPU, memory, storage, connections, and I/O
- Enhanced Monitoring at 5-second granularity with OS-level metrics
- Performance Insights for top SQL and wait event analysis
- pg_stat_statements for in-database query tracking
- SNS event subscriptions for failover and maintenance alerts
- CloudWatch alarms for CPU, storage, and connections

Monitoring strategy for production:
1. CloudWatch alarms for automated alerting (CPU, storage, connections)
2. Performance Insights for investigating slow periods
3. pg_stat_statements for long-term query analysis
4. Enhanced Monitoring for OS-level debugging
5. Event subscriptions for operational awareness

---

## Clean Up

Delete alarms:

```bash
aws cloudwatch delete-alarms \
    --alarm-names suta-rds-high-cpu suta-rds-low-storage suta-rds-high-connections
```

Delete event subscription:

```bash
aws rds delete-event-subscription \
    --subscription-name suta-rds-events
```

Delete SNS topic:

```bash
aws sns delete-topic \
    --topic-arn "${TOPIC_ARN}"
```
