# Build 01 - CloudWatch Metrics, Alarms, and Dashboards

**Time:** 40 minutes
**Goal:** Identify the key CloudWatch metrics for your Aurora cluster, create a production dashboard, and set up alarms that catch problems before users notice.
**Prerequisites:** Aurora PostgreSQL cluster `devops-lab-cluster` running. AWS CLI configured. Environment variables set.

---

## Step 1 - Set Your Environment Variables

**On your local machine, in your terminal:**

```bash
export CLUSTER_ID="devops-lab-cluster"
export REGION="us-east-1"
```

Verify they are set:

```bash
echo $CLUSTER_ID
echo $REGION
```

Get your writer instance ID:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier "$CLUSTER_ID" \
  --query "DBClusters[0].DBClusterMembers[?IsClusterWriter==\`true\`].DBInstanceIdentifier" \
  --output text \
  --region "$REGION"
```

`--query`: Filters the JSON output using JMESPath. This selects only the writer instance from the cluster members list.

Expected output (yours will differ):
```
devops-lab-cluster-instance-1
```

Save it:

```bash
export WRITER_INSTANCE="devops-lab-cluster-instance-1"
```

---

## Step 2 - Explore Available CloudWatch Metrics

List all metrics published for your Aurora cluster:

```bash
aws cloudwatch list-metrics \
  --namespace "AWS/RDS" \
  --dimensions Name=DBClusterIdentifier,Value="$CLUSTER_ID" \
  --query "Metrics[].MetricName" \
  --output table \
  --region "$REGION"
```

`--namespace "AWS/RDS"`: CloudWatch organizes metrics into namespaces. All RDS and Aurora metrics live in `AWS/RDS`.
`--dimensions`: Filters to metrics for your specific cluster.

Expected output (yours will differ):
```
--------------------------------------
|           ListMetrics              |
+------------------------------------+
|  AuroraReplicaLag                  |
|  BufferCacheHitRatio               |
|  CommitLatency                     |
|  CommitThroughput                  |
|  CPUUtilization                    |
|  DatabaseConnections               |
|  Deadlocks                         |
|  FreeableMemory                    |
|  ...                               |
+------------------------------------+
```

---

## Step 3 - Query Key Metrics via CLI

Get the current CPU utilization for your writer instance:

```bash
aws cloudwatch get-metric-statistics \
  --namespace "AWS/RDS" \
  --metric-name "CPUUtilization" \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 300 \
  --statistics Average \
  --region "$REGION"
```

Each flag explained:
- `--start-time` / `--end-time`: The time range to query. We use the last hour.
- `--period 300`: Aggregate data points into 5-minute buckets (300 seconds).
- `--statistics Average`: Calculate the average value for each period. Other options: Sum, Minimum, Maximum, SampleCount.

Expected output (yours will differ):
```json
{
    "Label": "CPUUtilization",
    "Datapoints": [
        {
            "Timestamp": "2026-06-09T14:00:00+00:00",
            "Average": 3.4,
            "Unit": "Percent"
        },
        {
            "Timestamp": "2026-06-09T14:05:00+00:00",
            "Average": 2.8,
            "Unit": "Percent"
        }
    ]
}
```

Get the buffer cache hit ratio (Aurora-specific):

```bash
aws cloudwatch get-metric-statistics \
  --namespace "AWS/RDS" \
  --metric-name "BufferCacheHitRatio" \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 300 \
  --statistics Average \
  --region "$REGION"
```

Expected output (yours will differ):
```json
{
    "Label": "BufferCacheHitRatio",
    "Datapoints": [
        {
            "Timestamp": "2026-06-09T14:00:00+00:00",
            "Average": 99.95,
            "Unit": "Percent"
        }
    ]
}
```

A value above 99% means your working set fits in memory. Below 95% indicates you may need a larger instance.

---

## Step 4 - Create an SNS Topic for Alerts

Before creating alarms, you need an SNS topic that alarms will send notifications to.

```bash
aws sns create-topic \
  --name "aurora-alerts-${CLUSTER_ID}" \
  --region "$REGION"
```

Expected output (yours will differ):
```json
{
    "TopicArn": "arn:aws:sns:us-east-1:123456789012:aurora-alerts-devops-lab-cluster"
}
```

Save the ARN:

```bash
export SNS_TOPIC_ARN="arn:aws:sns:us-east-1:123456789012:aurora-alerts-devops-lab-cluster"
```

Subscribe your email:

```bash
aws sns subscribe \
  --topic-arn "$SNS_TOPIC_ARN" \
  --protocol email \
  --notification-endpoint "your@email.com" \
  --region "$REGION"
```

Check your email and confirm the subscription by clicking the confirmation link.

---

## Step 5 - Create CloudWatch Alarms

### Alarm 1 - High CPU

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "Aurora-HighCPU-${WRITER_INSTANCE}" \
  --alarm-description "CPU above 80% for 10 minutes" \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --ok-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"
```

Each flag explained:
- `--period 300`: Evaluate each 5-minute window.
- `--evaluation-periods 2`: The condition must be true for 2 consecutive periods (10 minutes total) before alarming. This prevents alerting on brief CPU spikes.
- `--ok-actions`: Sends a notification when the alarm returns to OK state so you know the problem cleared.

### Alarm 2 - High Connections

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "Aurora-HighConnections-${WRITER_INSTANCE}" \
  --alarm-description "Connections above 80% of max_connections" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Average \
  --period 60 \
  --evaluation-periods 3 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"
```

Note: Adjust the `--threshold` to 80% of your actual max_connections value. For a db.r6g.large with max_connections around 800, use 640.

### Alarm 3 - Low Freeable Memory

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "Aurora-LowMemory-${WRITER_INSTANCE}" \
  --alarm-description "Freeable memory below 2GB" \
  --metric-name FreeableMemory \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 2147483648 \
  --comparison-operator LessThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"
```

`--threshold 2147483648`: 2 GB in bytes (2 * 1024 * 1024 * 1024). CloudWatch reports FreeableMemory in bytes.

### Alarm 4 - High Commit Latency

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "Aurora-HighCommitLatency-${WRITER_INSTANCE}" \
  --alarm-description "Commit latency above 20ms for 10 minutes" \
  --metric-name CommitLatency \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 20 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"
```

CommitLatency is Aurora-specific. It measures the average time to commit a transaction to the distributed storage layer. High values indicate storage contention.

### Alarm 5 - Replica Lag

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "Aurora-HighReplicaLag-${CLUSTER_ID}" \
  --alarm-description "Replica lag above 100ms for 5 minutes" \
  --metric-name AuroraReplicaLag \
  --namespace AWS/RDS \
  --dimensions Name=DBClusterIdentifier,Value="$CLUSTER_ID" \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"
```

Note: This uses `Maximum` statistic to catch the worst-case lag across readers.

### Alarm 6 - TXID Wraparound

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "Aurora-TXIDWraparound-${WRITER_INSTANCE}" \
  --alarm-description "Transaction ID age above 1 billion - investigate immediately" \
  --metric-name MaximumUsedTransactionIDs \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Maximum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1000000000 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"
```

This is a single-period alarm because TXID wraparound is so dangerous that any breach warrants immediate attention.

### Alarm 7 - Low Buffer Cache Hit Ratio

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "Aurora-LowCacheHit-${WRITER_INSTANCE}" \
  --alarm-description "Buffer cache hit ratio below 95%" \
  --metric-name BufferCacheHitRatio \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 95 \
  --comparison-operator LessThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"
```

### Alarm 8 - Deadlocks

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "Aurora-Deadlocks-${WRITER_INSTANCE}" \
  --alarm-description "Deadlocks detected" \
  --metric-name Deadlocks \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"
```

---

## Step 6 - Verify All Alarms

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "Aurora-" \
  --region "$REGION" \
  --query "MetricAlarms[].{Name:AlarmName,State:StateValue,Threshold:Threshold}" \
  --output table
```

Expected output (yours will differ):
```
-------------------------------------------------------------------
|                        DescribeAlarms                            |
+------------------------------------------+-------+--------------+
|                  Name                    | State |  Threshold   |
+------------------------------------------+-------+--------------+
|  Aurora-Deadlocks-devops-lab-instance-1  |  OK   |  1.0         |
|  Aurora-HighCommitLatency-devops-lab...  |  OK   |  20.0        |
|  Aurora-HighConnections-devops-lab...    |  OK   |  80.0        |
|  Aurora-HighCPU-devops-lab-instance-1    |  OK   |  80.0        |
|  Aurora-HighReplicaLag-devops-lab...     |  OK   |  100.0       |
|  Aurora-LowCacheHit-devops-lab...        |  OK   |  95.0        |
|  Aurora-LowMemory-devops-lab-instance-1  |  OK   |  2.147...    |
|  Aurora-TXIDWraparound-devops-lab...     |  OK   |  1.0E9       |
+------------------------------------------+-------+--------------+
```

All alarms should show `OK`. If any show `INSUFFICIENT_DATA`, wait 5 minutes and recheck.

---

## Step 7 - Create a CloudWatch Dashboard

Create a dashboard definition file:

```bash
cat > /tmp/aurora-dashboard.json << 'DASHBOARD_EOF'
{
    "widgets": [
        {
            "type": "metric", "x": 0, "y": 0, "width": 6, "height": 6,
            "properties": {
                "title": "CPU Utilization",
                "metrics": [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "REPLACE_WRITER"]],
                "period": 60, "stat": "Average", "view": "timeSeries", "region": "REPLACE_REGION"
            }
        },
        {
            "type": "metric", "x": 6, "y": 0, "width": 6, "height": 6,
            "properties": {
                "title": "Database Connections",
                "metrics": [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "REPLACE_WRITER"]],
                "period": 60, "stat": "Average", "view": "timeSeries", "region": "REPLACE_REGION"
            }
        },
        {
            "type": "metric", "x": 12, "y": 0, "width": 6, "height": 6,
            "properties": {
                "title": "Freeable Memory (GB)",
                "metrics": [["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", "REPLACE_WRITER"]],
                "period": 60, "stat": "Average", "view": "timeSeries", "region": "REPLACE_REGION",
                "yAxis": {"left": {"label": "Bytes"}}
            }
        },
        {
            "type": "metric", "x": 18, "y": 0, "width": 6, "height": 6,
            "properties": {
                "title": "Replica Lag (ms)",
                "metrics": [["AWS/RDS", "AuroraReplicaLag", "DBClusterIdentifier", "REPLACE_CLUSTER"]],
                "period": 60, "stat": "Maximum", "view": "timeSeries", "region": "REPLACE_REGION"
            }
        },
        {
            "type": "metric", "x": 0, "y": 6, "width": 6, "height": 6,
            "properties": {
                "title": "Commit Latency (ms)",
                "metrics": [["AWS/RDS", "CommitLatency", "DBInstanceIdentifier", "REPLACE_WRITER"]],
                "period": 60, "stat": "Average", "view": "timeSeries", "region": "REPLACE_REGION"
            }
        },
        {
            "type": "metric", "x": 6, "y": 6, "width": 6, "height": 6,
            "properties": {
                "title": "Commit Throughput",
                "metrics": [["AWS/RDS", "CommitThroughput", "DBInstanceIdentifier", "REPLACE_WRITER"]],
                "period": 60, "stat": "Average", "view": "timeSeries", "region": "REPLACE_REGION"
            }
        },
        {
            "type": "metric", "x": 12, "y": 6, "width": 6, "height": 6,
            "properties": {
                "title": "Buffer Cache Hit Ratio (%)",
                "metrics": [["AWS/RDS", "BufferCacheHitRatio", "DBInstanceIdentifier", "REPLACE_WRITER"]],
                "period": 60, "stat": "Average", "view": "timeSeries", "region": "REPLACE_REGION",
                "yAxis": {"left": {"min": 90, "max": 100}}
            }
        },
        {
            "type": "metric", "x": 18, "y": 6, "width": 6, "height": 6,
            "properties": {
                "title": "TXID Age",
                "metrics": [["AWS/RDS", "MaximumUsedTransactionIDs", "DBInstanceIdentifier", "REPLACE_WRITER"]],
                "period": 300, "stat": "Maximum", "view": "timeSeries", "region": "REPLACE_REGION"
            }
        },
        {
            "type": "metric", "x": 0, "y": 12, "width": 12, "height": 6,
            "properties": {
                "title": "Read & Write IOPS",
                "metrics": [
                    ["AWS/RDS", "VolumeReadIOPs", "DBClusterIdentifier", "REPLACE_CLUSTER"],
                    ["AWS/RDS", "VolumeWriteIOPs", "DBClusterIdentifier", "REPLACE_CLUSTER"]
                ],
                "period": 60, "stat": "Average", "view": "timeSeries", "region": "REPLACE_REGION"
            }
        },
        {
            "type": "metric", "x": 12, "y": 12, "width": 12, "height": 6,
            "properties": {
                "title": "Read & Write Latency",
                "metrics": [
                    ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", "REPLACE_WRITER"],
                    ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", "REPLACE_WRITER"]
                ],
                "period": 60, "stat": "Average", "view": "timeSeries", "region": "REPLACE_REGION"
            }
        }
    ]
}
DASHBOARD_EOF
```

Replace the placeholders and deploy:

```bash
sed -i '' "s/REPLACE_WRITER/$WRITER_INSTANCE/g" /tmp/aurora-dashboard.json
sed -i '' "s/REPLACE_CLUSTER/$CLUSTER_ID/g" /tmp/aurora-dashboard.json
sed -i '' "s/REPLACE_REGION/$REGION/g" /tmp/aurora-dashboard.json
```

Note: On Linux, use `sed -i` without the `''` after `-i`.

```bash
aws cloudwatch put-dashboard \
  --dashboard-name "Aurora-${CLUSTER_ID}" \
  --dashboard-body file:///tmp/aurora-dashboard.json \
  --region "$REGION"
```

Expected output (yours will differ):
```json
{
    "DashboardValidationMessages": []
}
```

An empty `DashboardValidationMessages` array means the dashboard JSON is valid and was saved.

---

## Step 8 - View Your Dashboard

1. Open the [CloudWatch Console](https://console.aws.amazon.com/cloudwatch/).
2. Click **Dashboards** in the left menu.
3. Click **Aurora-devops-lab-cluster**.
4. You should see 10 widgets arranged in 3 rows showing your cluster metrics.

---

## Summary

You have:
- Identified the key CloudWatch metrics for Aurora PostgreSQL
- Created an SNS topic for alarm notifications
- Set up 8 CloudWatch alarms covering CPU, connections, memory, commit latency, replica lag, TXID wraparound, cache hit ratio, and deadlocks
- Created a CloudWatch dashboard with 10 panels

These alarms represent the minimum production alert set for Aurora. Build 08 extends this into a comprehensive alerting strategy.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| Namespace | CloudWatch grouping for metrics. RDS/Aurora use `AWS/RDS` |
| Dimension | A key-value pair that identifies a specific metric source (e.g., DBInstanceIdentifier) |
| Period | Time window for metric aggregation (e.g., 300 seconds = 5 minutes) |
| Evaluation periods | Number of consecutive periods that must breach threshold to trigger alarm |
| CommitLatency | Aurora-specific metric measuring time to write WAL to distributed storage |
| BufferCacheHitRatio | Aurora-specific metric showing shared_buffers cache effectiveness |
| FreeableMemory | RAM available including reclaimable OS cache (not just truly free RAM) |
