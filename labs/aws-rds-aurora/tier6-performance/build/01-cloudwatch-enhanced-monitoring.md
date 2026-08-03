# Build 01 - CloudWatch Metrics and Enhanced Monitoring

**Time:** 35 minutes
**Goal:** Enable Enhanced Monitoring, create a CloudWatch dashboard, and configure alarms that catch problems before users notice.
**Prerequisites:** RDS PostgreSQL instance running. AWS CLI configured. Your `$DB_INSTANCE_ID` and `$REGION` env vars set.

---

## Step 1 - Verify Your Environment Variables

Open a terminal and confirm these are set:

```bash
echo $DB_INSTANCE_ID
echo $REGION
```

If they are blank, set them now:

```bash
export DB_INSTANCE_ID="your-rds-instance-id"
export REGION="us-east-1"
```

---

## Step 2 - Enable Enhanced Monitoring via AWS Console

Enhanced Monitoring runs an agent inside your RDS instance and reports OS-level metrics at up to 1-second granularity.

1. Open the [RDS Console](https://console.aws.amazon.com/rds/).
2. Click **Databases** in the left menu.
3. Click your database instance name.
4. Click the **Modify** button (top right).
5. Scroll down to the **Monitoring** section.
6. Find **Enhanced monitoring** and set it to **Enable enhanced monitoring**.
7. Set **Monitoring Role** to **Default** (or create a new IAM role if prompted).
8. Set **Granularity** to **60 seconds** (use 1 second only on instances where you need sub-minute diagnosis - it increases CloudWatch Logs cost).
9. Scroll to the bottom and click **Continue**.
10. On the summary screen, select **Apply immediately**.
11. Click **Modify DB Instance**.

> **Concept:** Enhanced Monitoring writes to the CloudWatch Logs group `RDSOSMetrics`. This is different from the standard CloudWatch Metrics namespace `AWS/RDS`. The distinction matters when querying or alarming.

---

## Step 3 - Enable Enhanced Monitoring via CLI

If you prefer CLI or want to script this for multiple instances:

```bash
aws rds modify-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --monitoring-interval 60 \
  --monitoring-role-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/rds-monitoring-role" \
  --apply-immediately \
  --region "$REGION"
```

Each flag explained:
- `--monitoring-interval 60`: Report every 60 seconds. Valid values: 0 (off), 1, 5, 10, 15, 30, 60.
- `--monitoring-role-arn`: The IAM role that allows RDS to write to CloudWatch Logs.
- `--apply-immediately`: Apply without waiting for the next maintenance window.

Wait for the modification to complete:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$REGION"
```

Expected output (yours will differ):
```
(no output - the command exits when the instance is in available state)
```

---

## Step 4 - View Enhanced Monitoring Data in the Console

1. Go to the RDS Console and click your database.
2. Click the **Monitoring** tab.
3. Click **Enhanced monitoring** (there is a dropdown at the top of the monitoring graphs).
4. You will see a set of OS-level metrics including:
   - **OS process list:** Which processes are using CPU (postgres worker, autovacuum, etc.)
   - **Memory:** Active, buffers, cached, dirty, free, swap
   - **Disk I/O:** Reads and writes per device
   - **Network:** Receive and transmit per interface

---

## Step 5 - Query Enhanced Monitoring Data via CLI

Enhanced Monitoring data lives in CloudWatch Logs. You can retrieve it:

```bash
aws logs get-log-events \
  --log-group-name "RDSOSMetrics" \
  --log-stream-name "$DB_INSTANCE_ID" \
  --limit 5 \
  --region "$REGION"
```

`--limit 5` retrieves only the 5 most recent log events (each event is one minute of metrics in JSON format).

Expected output (yours will differ):
```json
{
    "events": [
        {
            "timestamp": 1706745600000,
            "message": "{\"engine\":\"AURORA\",\"instanceID\":\"your-instance\",\"instanceResourceID\":\"db-ABC123\",\"timestamp\":\"2024-01-31T12:00:00Z\",\"version\":1.0,\"uptime\":\"10 days...\",\"numVCPUs\":2,\"cpuUtilization\":{\"guest\":0.0,\"irq\":0.0,\"system\":1.2,\"wait\":0.3,\"idle\":96.8,\"user\":1.7,\"total\":3.2,\"steal\":0.0,\"nice\":0.0},..."
        }
    ]
}
```

---

## Step 6 - Create a CloudWatch Dashboard

A dashboard gives you a single-pane view of your instance health.

### Console

1. Open [CloudWatch Console](https://console.aws.amazon.com/cloudwatch/).
2. Click **Dashboards** in the left menu.
3. Click **Create dashboard**.
4. Name it: `RDS-Performance-[ENV]` (replace [ENV] with prod, staging, etc.)
5. Click **Create dashboard**.
6. In the widget type selector, choose **Line** and click **Next**.
7. Choose **Metrics** and click **Next**.
8. In the metrics browser, go to **RDS > Per-Database Metrics**.
9. Find your instance and select:
   - `CPUUtilization`
   - `DatabaseConnections`
   - `FreeableMemory`
   - `ReadLatency`
   - `WriteLatency`
10. Click **Create widget**.
11. Repeat to add widgets for `ReadIOPS`, `WriteIOPS`, `FreeStorageSpace`, and `ReplicaLag`.

### CLI - Create a Dashboard with JSON

Create a file called `/tmp/dashboard.json`:

```bash
cat > /tmp/dashboard.json << 'DASHBOARD_EOF'
{
    "widgets": [
        {
            "type": "metric",
            "x": 0, "y": 0, "width": 12, "height": 6,
            "properties": {
                "title": "CPU Utilization",
                "metrics": [
                    ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "REPLACE_INSTANCE_ID"]
                ],
                "period": 60,
                "stat": "Average",
                "view": "timeSeries",
                "region": "REPLACE_REGION"
            }
        },
        {
            "type": "metric",
            "x": 12, "y": 0, "width": 12, "height": 6,
            "properties": {
                "title": "Database Connections",
                "metrics": [
                    ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "REPLACE_INSTANCE_ID"]
                ],
                "period": 60,
                "stat": "Average",
                "view": "timeSeries",
                "region": "REPLACE_REGION"
            }
        },
        {
            "type": "metric",
            "x": 0, "y": 6, "width": 12, "height": 6,
            "properties": {
                "title": "Freeable Memory",
                "metrics": [
                    ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", "REPLACE_INSTANCE_ID"]
                ],
                "period": 60,
                "stat": "Average",
                "view": "timeSeries",
                "region": "REPLACE_REGION"
            }
        },
        {
            "type": "metric",
            "x": 12, "y": 6, "width": 12, "height": 6,
            "properties": {
                "title": "Read and Write Latency",
                "metrics": [
                    ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", "REPLACE_INSTANCE_ID"],
                    ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", "REPLACE_INSTANCE_ID"]
                ],
                "period": 60,
                "stat": "Average",
                "view": "timeSeries",
                "region": "REPLACE_REGION"
            }
        }
    ]
}
DASHBOARD_EOF
```

Replace the placeholder and deploy it:

```bash
sed -i "s/REPLACE_INSTANCE_ID/$DB_INSTANCE_ID/g" /tmp/dashboard.json
sed -i "s/REPLACE_REGION/$REGION/g" /tmp/dashboard.json
```

```bash
aws cloudwatch put-dashboard \
  --dashboard-name "RDS-Performance-${DB_INSTANCE_ID}" \
  --dashboard-body file:///tmp/dashboard.json \
  --region "$REGION"
```

`--dashboard-body file://...`: Reads the dashboard JSON from a local file.

Expected output (yours will differ):
```json
{
    "DashboardValidationMessages": []
}
```

An empty `DashboardValidationMessages` means the dashboard JSON is valid and was saved.

---

## Step 7 - Create CloudWatch Alarms

### Create an SNS Topic for Alerts First

Create a topic that alarms will send to:

```bash
aws sns create-topic \
  --name "rds-alerts-${DB_INSTANCE_ID}" \
  --region "$REGION"
```

Expected output (yours will differ):
```json
{
    "TopicArn": "arn:aws:sns:us-east-1:123456789012:rds-alerts-your-instance"
}
```

Save the ARN:

```bash
export SNS_TOPIC_ARN="arn:aws:sns:us-east-1:123456789012:rds-alerts-your-instance"
```

Subscribe your email to the topic:

```bash
aws sns subscribe \
  --topic-arn "$SNS_TOPIC_ARN" \
  --protocol email \
  --notification-endpoint "your@email.com" \
  --region "$REGION"
```

Check your email and confirm the subscription.

### Alarm 1 - High CPU

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-HighCPU-${DB_INSTANCE_ID}" \
  --alarm-description "CPU above 80% for 5 minutes" \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"
```

Each flag explained:
- `--period 300`: Evaluate each 5-minute window (300 seconds).
- `--evaluation-periods 1`: Alarm after 1 period above threshold.
- `--threshold 80`: Trigger at 80% CPU.
- `--comparison-operator GreaterThanThreshold`: Alarm when metric exceeds threshold.

### Alarm 2 - High Connections

First get max_connections for your instance:

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name default.postgres16 \
  --query "Parameters[?ParameterName=='max_connections'].ParameterValue" \
  --output text \
  --region "$REGION"
```

Then create the alarm (replace MAX_CONNECTIONS with the value you got):

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-HighConnections-${DB_INSTANCE_ID}" \
  --alarm-description "Connections above 80% of max_connections" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --statistic Average \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --region "$REGION"
```

### Alarm 3 - Low Free Storage

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-LowStorage-${DB_INSTANCE_ID}" \
  --alarm-description "Free storage below 10GB" \
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
```

`--threshold 10737418240`: 10GB in bytes (10 * 1024 * 1024 * 1024). CloudWatch metrics for storage are in bytes.

### Alarm 4 - Transaction ID Wraparound (Critical)

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-TXIDWraparound-${DB_INSTANCE_ID}" \
  --alarm-description "Transaction ID usage above 1.5 billion - URGENT" \
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
```

---

## Step 8 - Verify Alarms

List your alarms:

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "RDS-" \
  --region "$REGION" \
  --query "MetricAlarms[].{Name:AlarmName,State:StateValue,Threshold:Threshold}" \
  --output table
```

Expected output (yours will differ):
```
----------------------------------------------------------------------
|                         DescribeAlarms                             |
+--------------------------------------+----------+------------------+
|               Name                   |  State   |    Threshold     |
+--------------------------------------+----------+------------------+
|  RDS-HighCPU-mydb-instance           |  OK      |  80.0            |
|  RDS-HighConnections-mydb-instance   |  OK      |  80.0            |
|  RDS-LowStorage-mydb-instance        |  OK      |  10737418240.0   |
|  RDS-TXIDWraparound-mydb-instance    |  OK      |  1500000000.0    |
+--------------------------------------+----------+------------------+
```

---

## Summary

You have:
- Enabled Enhanced Monitoring at 60-second granularity
- Created a CloudWatch dashboard for your RDS instance
- Set up SNS alerts for CPU, connections, storage, and TXID wraparound

The alarms in Step 7 represent the minimum production alert set. Tier 6 USE exercise 01 extends this into a complete monitoring pipeline.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| Enhanced Monitoring | OS-agent based monitoring at 1-60s granularity, in CloudWatch Logs |
| CloudWatch Metrics | Hypervisor-level metrics at 60s minimum, in AWS/RDS namespace |
| RDSOSMetrics | CloudWatch Logs group where Enhanced Monitoring data lands |
| SNS | Simple Notification Service - sends alarm notifications to email, Lambda, etc. |
| FreeableMemory | RAM available for use (includes reclaimable cache, not just truly free) |
