# Module 10 - Build Guide 04: Monitoring Setup

**Objective:** Build a comprehensive monitoring stack for your Aurora cluster - CloudWatch dashboards, metric alarms, log metric filters, Performance Insights queries, and an SNS notification pipeline.
**Time:** 40 minutes
**Level:** Senior / Staff
**Prerequisites:** Build Guide 03 completed (Aurora cluster deployed and available).

---

## 1. Create the SNS Notification Topic

Before creating alarms, you need somewhere to send notifications. SNS (Simple Notification Service) is the routing layer.

**On your local workstation:**

```bash
aws sns create-topic \
  --name devops-lab-aurora-alerts \
  --tags Key=Project,Value=devops-lab Key=Environment,Value=production
```

`--name` sets the topic name. `--tags` adds metadata for cost tracking.

Expected output (yours will differ):
```json
{
  "TopicArn": "arn:aws:sns:us-east-1:123456789012:devops-lab-aurora-alerts"
}
```

Save the topic ARN - you will use it in every alarm:

```bash
export SNS_TOPIC_ARN="arn:aws:sns:us-east-1:123456789012:devops-lab-aurora-alerts"
```

Subscribe your email to the topic:

```bash
aws sns subscribe \
  --topic-arn $SNS_TOPIC_ARN \
  --protocol email \
  --notification-endpoint your-email@example.com
```

`--protocol email` sends alarm notifications via email. You must confirm the subscription by clicking the link in the confirmation email.

Expected output (yours will differ):
```json
{
  "SubscriptionArn": "pending confirmation"
}
```

Check your email and click the confirmation link before proceeding.

---

## 2. Create CloudWatch Alarms

### 2.1 CPU Utilization Alarm

**On your local workstation:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-cpu-high \
  --alarm-description "Aurora cluster CPU utilization above 80% for 5 minutes" \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --statistic Average \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching
```

- `--period 60` - Evaluates the metric every 60 seconds
- `--evaluation-periods 5` - Must breach for 5 consecutive periods (5 minutes)
- `--threshold 80` - Triggers when CPU exceeds 80%
- `--treat-missing-data notBreaching` - Prevents false alarms if the metric temporarily stops publishing
- `--ok-actions` - Sends a notification when the alarm returns to OK state

### 2.2 Database Connections Alarm

**On your local workstation:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-connections-high \
  --alarm-description "Aurora database connections above 200 for 5 minutes" \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 200 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching
```

### 2.3 Freeable Memory Alarm

**On your local workstation:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-memory-low \
  --alarm-description "Aurora freeable memory below 500 MB for 5 minutes" \
  --namespace AWS/RDS \
  --metric-name FreeableMemory \
  --dimensions Name=DBInstanceIdentifier,Value=devops-lab-cluster-w1 \
  --statistic Average \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 524288000 \
  --comparison-operator LessThanThreshold \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching
```

`--threshold 524288000` is 500 MB in bytes (500 * 1024 * 1024). FreeableMemory is reported in bytes.

### 2.4 Replica Lag Alarm

**On your local workstation:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-replica-lag-high \
  --alarm-description "Aurora replica lag above 30 seconds for 5 minutes" \
  --namespace AWS/RDS \
  --metric-name AuroraReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=devops-lab-cluster-r1 \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 30000 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching
```

`--threshold 30000` is 30 seconds in milliseconds. AuroraReplicaLag is reported in milliseconds.

### 2.5 Write Latency Alarm

**On your local workstation:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-write-latency-high \
  --alarm-description "Aurora write latency above 20ms for 10 minutes" \
  --namespace AWS/RDS \
  --metric-name WriteLatency \
  --dimensions Name=DBInstanceIdentifier,Value=devops-lab-cluster-w1 \
  --statistic Average \
  --period 60 \
  --evaluation-periods 10 \
  --threshold 0.020 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching
```

`--threshold 0.020` is 20 milliseconds. WriteLatency is reported in seconds, so 20ms = 0.020.

### 2.6 Read Latency Alarm

**On your local workstation:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-read-latency-high \
  --alarm-description "Aurora read latency above 20ms for 10 minutes" \
  --namespace AWS/RDS \
  --metric-name ReadLatency \
  --dimensions Name=DBInstanceIdentifier,Value=devops-lab-cluster-w1 \
  --statistic Average \
  --period 60 \
  --evaluation-periods 10 \
  --threshold 0.020 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching
```

---

## 3. Create Log Metric Filters

Log metric filters watch PostgreSQL log streams and create CloudWatch metrics when specific patterns appear.

### 3.1 Deadlock Metric Filter

**On your local workstation:**

```bash
aws logs put-metric-filter \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --filter-name devops-lab-deadlock-count \
  --filter-pattern "deadlock detected" \
  --metric-transformations \
    metricName=DeadlockCount,metricNamespace=DevOpsLab/Aurora,metricValue=1,unit=Count
```

- `--filter-pattern "deadlock detected"` - Matches any log line containing this text
- `metricNamespace=DevOpsLab/Aurora` - Custom namespace groups all your custom metrics together
- `metricValue=1` - Each match increments the metric by 1

### 3.2 Authentication Failure Metric Filter

**On your local workstation:**

```bash
aws logs put-metric-filter \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --filter-name devops-lab-auth-failures \
  --filter-pattern "authentication failed" \
  --metric-transformations \
    metricName=AuthFailureCount,metricNamespace=DevOpsLab/Aurora,metricValue=1,unit=Count
```

### 3.3 Temp File Metric Filter

**On your local workstation:**

```bash
aws logs put-metric-filter \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --filter-name devops-lab-temp-files \
  --filter-pattern "temporary file" \
  --metric-transformations \
    metricName=TempFileCount,metricNamespace=DevOpsLab/Aurora,metricValue=1,unit=Count
```

### 3.4 Transaction Wraparound Warning

**On your local workstation:**

```bash
aws logs put-metric-filter \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --filter-name devops-lab-wraparound-warning \
  --filter-pattern "transaction ID wraparound" \
  --metric-transformations \
    metricName=WraparoundWarningCount,metricNamespace=DevOpsLab/Aurora,metricValue=1,unit=Count
```

### 3.5 Alarm on Deadlock Metric

**On your local workstation:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-deadlocks \
  --alarm-description "Deadlock detected in Aurora cluster" \
  --namespace DevOpsLab/Aurora \
  --metric-name DeadlockCount \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching
```

### 3.6 Alarm on Authentication Failures

**On your local workstation:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-auth-failures \
  --alarm-description "Multiple authentication failures detected" \
  --namespace DevOpsLab/Aurora \
  --metric-name AuthFailureCount \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching
```

---

## 4. Set Log Retention Policy

By default, CloudWatch Logs retains data forever. Set a retention policy to control costs.

**On your local workstation:**

```bash
aws logs put-retention-policy \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --retention-in-days 90
```

`--retention-in-days 90` deletes log data older than 90 days. Adjust based on your compliance requirements. HIPAA requires 6 years (2190 days).

---

## 5. Create CloudWatch Dashboard

**On your local workstation:**

```bash
aws cloudwatch put-dashboard \
  --dashboard-name devops-lab-aurora-dashboard \
  --dashboard-body '{
    "widgets": [
      {
        "type": "metric",
        "x": 0, "y": 0, "width": 12, "height": 6,
        "properties": {
          "title": "CPU Utilization (%)",
          "metrics": [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "devops-lab-cluster-w1", {"label": "Writer", "color": "#d62728"}],
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "devops-lab-cluster-r1", {"label": "Reader", "color": "#1f77b4"}]
          ],
          "period": 60,
          "stat": "Average",
          "view": "timeSeries",
          "yAxis": {"left": {"min": 0, "max": 100}},
          "annotations": {
            "horizontal": [{"label": "Alarm threshold", "value": 80, "color": "#d62728"}]
          }
        }
      },
      {
        "type": "metric",
        "x": 12, "y": 0, "width": 12, "height": 6,
        "properties": {
          "title": "Database Connections",
          "metrics": [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "devops-lab-cluster-w1", {"label": "Writer"}],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "devops-lab-cluster-r1", {"label": "Reader"}]
          ],
          "period": 60,
          "stat": "Maximum",
          "view": "timeSeries",
          "annotations": {
            "horizontal": [{"label": "Alarm threshold", "value": 200, "color": "#d62728"}]
          }
        }
      },
      {
        "type": "metric",
        "x": 0, "y": 6, "width": 12, "height": 6,
        "properties": {
          "title": "Read / Write Latency (seconds)",
          "metrics": [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", "devops-lab-cluster-w1", {"label": "Read Latency"}],
            ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", "devops-lab-cluster-w1", {"label": "Write Latency"}]
          ],
          "period": 60,
          "stat": "Average",
          "view": "timeSeries",
          "annotations": {
            "horizontal": [{"label": "20ms threshold", "value": 0.020, "color": "#ff7f0e"}]
          }
        }
      },
      {
        "type": "metric",
        "x": 12, "y": 6, "width": 12, "height": 6,
        "properties": {
          "title": "Freeable Memory (bytes)",
          "metrics": [
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", "devops-lab-cluster-w1", {"label": "Writer"}],
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", "devops-lab-cluster-r1", {"label": "Reader"}]
          ],
          "period": 60,
          "stat": "Minimum",
          "view": "timeSeries",
          "annotations": {
            "horizontal": [{"label": "500 MB threshold", "value": 524288000, "color": "#d62728"}]
          }
        }
      },
      {
        "type": "metric",
        "x": 0, "y": 12, "width": 12, "height": 6,
        "properties": {
          "title": "Aurora Replica Lag (ms)",
          "metrics": [
            ["AWS/RDS", "AuroraReplicaLag", "DBInstanceIdentifier", "devops-lab-cluster-r1"]
          ],
          "period": 60,
          "stat": "Maximum",
          "view": "timeSeries",
          "annotations": {
            "horizontal": [{"label": "30s threshold", "value": 30000, "color": "#d62728"}]
          }
        }
      },
      {
        "type": "metric",
        "x": 12, "y": 12, "width": 12, "height": 6,
        "properties": {
          "title": "Custom Metrics (5-min intervals)",
          "metrics": [
            ["DevOpsLab/Aurora", "DeadlockCount", {"label": "Deadlocks", "stat": "Sum"}],
            ["DevOpsLab/Aurora", "AuthFailureCount", {"label": "Auth Failures", "stat": "Sum"}],
            ["DevOpsLab/Aurora", "TempFileCount", {"label": "Temp Files", "stat": "Sum"}]
          ],
          "period": 300,
          "view": "timeSeries"
        }
      },
      {
        "type": "alarm",
        "x": 0, "y": 18, "width": 24, "height": 3,
        "properties": {
          "title": "Alarm Status",
          "alarms": [
            "arn:aws:cloudwatch:us-east-1:ACCOUNT_ID:alarm:devops-lab-aurora-cpu-high",
            "arn:aws:cloudwatch:us-east-1:ACCOUNT_ID:alarm:devops-lab-aurora-connections-high",
            "arn:aws:cloudwatch:us-east-1:ACCOUNT_ID:alarm:devops-lab-aurora-memory-low",
            "arn:aws:cloudwatch:us-east-1:ACCOUNT_ID:alarm:devops-lab-aurora-replica-lag-high",
            "arn:aws:cloudwatch:us-east-1:ACCOUNT_ID:alarm:devops-lab-aurora-deadlocks"
          ]
        }
      }
    ]
  }'
```

Replace `ACCOUNT_ID` with your actual AWS account ID. Find it with:

```bash
aws sts get-caller-identity --query Account --output text
```

---

## 6. Verify the Monitoring Setup

### 6.1 Check Alarms

**On your local workstation:**

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix devops-lab-aurora \
  --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName]' \
  --output table
```

Expected output (yours will differ):
```
---------------------------------------------------------------------
|                      DescribeAlarms                               |
+-------------------------------------------+----+------------------+
|  devops-lab-aurora-cpu-high               | OK | CPUUtilization   |
|  devops-lab-aurora-connections-high       | OK | DatabaseConnections |
|  devops-lab-aurora-memory-low             | OK | FreeableMemory   |
|  devops-lab-aurora-replica-lag-high       | OK | AuroraReplicaLag |
|  devops-lab-aurora-write-latency-high     | OK | WriteLatency     |
|  devops-lab-aurora-read-latency-high      | OK | ReadLatency      |
|  devops-lab-aurora-deadlocks              | OK | DeadlockCount    |
|  devops-lab-aurora-auth-failures          | OK | AuthFailureCount |
+-------------------------------------------+----+------------------+
```

All alarms should be in `OK` state on a healthy cluster.

### 6.2 Check Metric Filters

**On your local workstation:**

```bash
aws logs describe-metric-filters \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --query 'metricFilters[*].[filterName,filterPattern]' \
  --output table
```

Expected output (yours will differ):
```
------------------------------------------------------------
|               DescribeMetricFilters                      |
+-----------------------------+----------------------------+
|  devops-lab-deadlock-count  | deadlock detected          |
|  devops-lab-auth-failures   | authentication failed      |
|  devops-lab-temp-files      | temporary file             |
|  devops-lab-wraparound-warning | transaction ID wraparound |
+-----------------------------+----------------------------+
```

### 6.3 Check Dashboard

**On your local workstation:**

```bash
aws cloudwatch list-dashboards \
  --query 'DashboardEntries[?DashboardName==`devops-lab-aurora-dashboard`].[DashboardName,Size]' \
  --output table
```

Expected output (yours will differ):
```
-----------------------------------------------
|            ListDashboards                   |
+-----------------------------+---------------+
|  devops-lab-aurora-dashboard|  2048         |
+-----------------------------+---------------+
```

Open the dashboard in the AWS Console: CloudWatch > Dashboards > devops-lab-aurora-dashboard.

### 6.4 Check Performance Insights

**On your local workstation:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier devops-lab-cluster-w1 \
  --query 'DBInstances[0].[PerformanceInsightsEnabled,MonitoringInterval]' \
  --output table
```

Expected output (yours will differ):
```
--------------------------
|  True  |  60           |
--------------------------
```

Performance Insights is `True` and Enhanced Monitoring interval is `60` seconds.

---

## 7. Test an Alarm (Optional)

To verify the notification pipeline works end to end, temporarily lower the CPU alarm threshold.

**On your local workstation:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-cpu-high \
  --alarm-description "TESTING - temporarily lowered threshold" \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --statistic Average \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching
```

Wait 2-3 minutes. You should receive an email notification that the alarm entered ALARM state (since CPU is always above 1%).

After confirming the notification works, restore the original threshold:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-cpu-high \
  --alarm-description "Aurora cluster CPU utilization above 80% for 5 minutes" \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --statistic Average \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching
```

---

## Summary

Your Aurora cluster now has comprehensive monitoring:

- **8 CloudWatch Alarms** covering CPU, connections, memory, replica lag, latency, deadlocks, and auth failures
- **4 Log Metric Filters** extracting operational signals from PostgreSQL logs
- **1 CloudWatch Dashboard** with 7 widgets showing cluster health at a glance
- **SNS notification pipeline** routing alerts to your email
- **Performance Insights** enabled for deep query analysis
- **Enhanced Monitoring** at 60-second granularity for OS-level metrics
- **90-day log retention** balancing cost and compliance

The on-call engineer can now open one dashboard and immediately see if the cluster is healthy. If something is wrong, alarms fire automatically and notifications reach the right people.

**Next:** [Build 05 - CI/CD Pipeline](./05-cicd-pipeline.md)
