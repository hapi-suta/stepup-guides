# BUILD 04: Cloud Database Monitoring and Cost Optimization

**Module 03 - Cloud Database Services**
**Time Estimate:** 75 minutes
**Prerequisites:** Running RDS or Aurora instance from BUILD 01/02, AWS CLI configured

---

## Step 1: CloudWatch Metrics for RDS/Aurora

**Analogy:** CloudWatch is like having a `pg_stat` view for your entire infrastructure - not just PostgreSQL, but CPU, memory, disk, and network too. Instead of querying `pg_stat_activity`, you query CloudWatch.

AWS automatically sends metrics from your RDS/Aurora instances to CloudWatch. No agent to install, no exporter to configure.

**Key metrics every DBA should know:**

| CloudWatch Metric | What It Measures | DBA Analogy |
|---|---|---|
| `CPUUtilization` | Percentage of CPU used | `top` or `htop` on your server |
| `FreeableMemory` | Available RAM in bytes | `free -m` output |
| `DatabaseConnections` | Current connection count | `SELECT count(*) FROM pg_stat_activity` |
| `ReadIOPS` / `WriteIOPS` | Disk read/write operations per second | `iostat` output |
| `ReadLatency` / `WriteLatency` | Average time per I/O operation | `pg_stat_io` wait times |
| `FreeStorageSpace` | Remaining disk space | `df -h $PGDATA` |
| `ReplicaLag` | Replication delay in seconds | `pg_stat_replication.replay_lag` |
| `SwapUsage` | Swap memory used | `swapon --show` |
| `NetworkReceiveThroughput` | Incoming network bytes/sec | `iftop` or `nethogs` |

**On your Mac, in your terminal:**

Query a metric directly:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=lab-postgres \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average Maximum \
  --output table
```

Expected output (yours will differ):
```
------------------------------------------------------------------
|                       GetMetricStatistics                      |
+---------------------+----------+----------+--------------------+
|      Timestamp      | Average  | Maximum  |      Unit          |
+---------------------+----------+----------+--------------------+
|  2026-06-09T14:55   |  3.42    |  5.17    | Percent            |
|  2026-06-09T15:00   |  2.89    |  4.33    | Percent            |
|  2026-06-09T15:05   |  3.11    |  6.22    | Percent            |
+---------------------+----------+----------+--------------------+
```

Check connection count:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=lab-postgres \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average Maximum \
  --output table
```

Check free storage:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=lab-postgres \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --query "Datapoints | sort_by(@, &Timestamp) | [-1].{AvgBytes:Average}" \
  --output table
```

---

## Step 2: CloudWatch Alarms

**Analogy:** CloudWatch Alarms are like writing a `pg_cron` job that checks a metric every minute and sends you an email when it crosses a threshold. Except you do not write any cron jobs or scripts - you just define the threshold and the notification target.

**Alarm states:**
- **OK** - Metric is within the threshold
- **ALARM** - Metric has breached the threshold
- **INSUFFICIENT_DATA** - Not enough data to evaluate (usually right after creation)

Before creating alarms, you need an SNS topic (the notification channel):

```bash
# Create an SNS topic for database alerts
TOPIC_ARN=$(aws sns create-topic --name db-alerts --query "TopicArn" --output text)
echo "SNS Topic: $TOPIC_ARN"

# Subscribe your email to the topic
aws sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol email \
  --notification-endpoint your-email@example.com
```

**Important:** Check your email and confirm the subscription. You will not receive alerts until you click the confirmation link.

Now create alarms for critical database metrics:

**Alarm 1: CPU over 80%**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "rds-lab-postgres-high-cpu" \
  --alarm-description "CPU utilization above 80% for 5 minutes" \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=lab-postgres \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions "$TOPIC_ARN" \
  --ok-actions "$TOPIC_ARN" \
  --treat-missing-data notBreaching
```

**What each flag means:**

- `--period 300` - Evaluate every 300 seconds (5 minutes)
- `--threshold 80` - Fire when above 80%
- `--evaluation-periods 1` - Fire after 1 consecutive breach (not a fluke filter)
- `--alarm-actions` - What to do when alarm fires (send to SNS topic)
- `--ok-actions` - What to do when alarm resolves (also notify)
- `--treat-missing-data notBreaching` - If no data, assume OK (do not fire false alarms)

**Alarm 2: Connection count over 80% of max**

For a db.t3.micro, `max_connections` is approximately 87. Set the alarm at 70:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "rds-lab-postgres-high-connections" \
  --alarm-description "Connection count above 70 (80% of max)" \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=lab-postgres \
  --statistic Maximum \
  --period 60 \
  --threshold 70 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 3 \
  --alarm-actions "$TOPIC_ARN" \
  --treat-missing-data notBreaching
```

**Alarm 3: Free storage below 2 GB**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "rds-lab-postgres-low-storage" \
  --alarm-description "Free storage below 2 GB" \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=lab-postgres \
  --statistic Average \
  --period 300 \
  --threshold 2147483648 \
  --comparison-operator LessThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions "$TOPIC_ARN" \
  --treat-missing-data notBreaching
```

**Note:** FreeStorageSpace is in bytes. 2 GB = 2,147,483,648 bytes.

List your alarms:

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "rds-lab" \
  --query "MetricAlarms[*].{Name:AlarmName,State:StateValue,Metric:MetricName,Threshold:Threshold}" \
  --output table
```

Expected output (yours will differ):
```
-------------------------------------------------------------------------
|                          DescribeAlarms                               |
+-------------------+--------------------+-----------+------------------+
|     Metric        |       Name         |  State    |  Threshold       |
+-------------------+--------------------+-----------+------------------+
| CPUUtilization    | rds-lab-...-cpu    | OK        | 80.0             |
| DatabaseConnect.. | rds-lab-...-conn   | OK        | 70.0             |
| FreeStorageSpace  | rds-lab-...-stor   | OK        | 2147483648.0     |
+-------------------+--------------------+-----------+------------------+
```

---

## Step 3: Performance Insights Deep Dive

Performance Insights gives you visibility into database-level performance that CloudWatch metrics cannot. It answers the question: "Which queries are causing the load?"

**Enable Performance Insights (if not already enabled):**

```bash
aws rds modify-db-instance \
  --db-instance-identifier lab-postgres \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --apply-immediately
```

**Access Performance Insights via CLI:**

```bash
# Get the DBI Resource ID (Performance Insights uses this, not the instance name)
DBI_RESOURCE_ID=$(aws rds describe-db-instances \
  --db-instance-identifier lab-postgres \
  --query "DBInstances[0].DbiResourceId" \
  --output text)

echo "Resource ID: $DBI_RESOURCE_ID"
```

Get the top wait events:

```bash
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier "$DBI_RESOURCE_ID" \
  --metric-queries '[{"Metric": "db.load.avg", "GroupBy": {"Group": "db.wait_event"}}]' \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period-in-seconds 300
```

**What Performance Insights shows you (in the Console):**

| Panel | What It Shows | DBA Equivalent |
|---|---|---|
| Database load | Active sessions over time | Counting non-idle rows in `pg_stat_activity` |
| Top wait events | What queries are waiting for | `wait_event_type` in `pg_stat_activity` |
| Top SQL | Queries consuming the most time | `pg_stat_statements` ORDER BY total_exec_time |
| Top hosts | Which application servers send the most load | GROUP BY client_addr in `pg_stat_activity` |
| Top users | Which database users consume the most | GROUP BY usename in `pg_stat_activity` |

**Reading the database load chart:**

- The chart shows "Average Active Sessions" (AAS) over time
- A horizontal line shows your vCPU count
- If AAS is below vCPU count, the database has headroom
- If AAS is above vCPU count, queries are queueing (waiting for CPU)
- Colors show different wait event types

---

## Step 4: Enhanced Monitoring

Enhanced Monitoring provides OS-level metrics at up to 1-second granularity. This is like having `htop`, `iostat`, and `vmstat` running on your RDS instance.

**Why you need it:** CloudWatch metrics are 1-minute granularity. For investigating performance spikes that last only seconds, you need Enhanced Monitoring.

**Metrics provided:**

| Category | Metrics |
|---|---|
| CPU | user, system, idle, iowait, steal |
| Memory | total, free, cached, buffers, active |
| Disk | read/write IOPS, read/write throughput, queue depth |
| Network | receive/transmit bytes, packets |
| Processes | running, blocked, total |
| Swap | in, out, total, free |

Enable Enhanced Monitoring:

```bash
# Note: This requires an IAM role. If the role already exists, this will work.
# If not, see AWS docs for creating the "rds-monitoring-role"

aws rds modify-db-instance \
  --db-instance-identifier lab-postgres \
  --monitoring-interval 60 \
  --apply-immediately
```

The `--monitoring-interval` can be 0 (off), 1, 5, 10, 15, 30, or 60 seconds.

---

## Step 5: Setting Up SNS Notifications for RDS Events

Beyond metric-based alarms, RDS sends event notifications for operational events like failovers, maintenance, and configuration changes.

```bash
aws rds create-event-subscription \
  --subscription-name lab-db-events \
  --sns-topic-arn "$TOPIC_ARN" \
  --source-type db-instance \
  --event-categories "availability" "failover" "failure" "maintenance" "notification" \
  --source-ids lab-postgres
```

**Event categories you care about as a DBA:**

| Category | What It Covers |
|---|---|
| `availability` | Instance started, stopped, restarted |
| `failover` | Multi-AZ failover occurred |
| `failure` | Instance failure, storage failure |
| `maintenance` | Pending maintenance, maintenance started/completed |
| `configuration change` | Parameter group changed, instance modified |
| `notification` | Instance approaching storage limit |

---

## Step 6: Cost Explorer for Database Spending

**On your Mac, in your terminal:**

Get your RDS costs for the current month:

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Relational Database Service"]}}' \
  --query "ResultsByTime[0].Total.BlendedCost"
```

Expected output (yours will differ):
```json
{
    "Amount": "12.47",
    "Unit": "USD"
}
```

Break down cost by usage type:

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Relational Database Service"]}}' \
  --group-by Type=DIMENSION,Key=USAGE_TYPE \
  --query "ResultsByTime[0].Groups[*].{Type:Keys[0],Cost:Metrics.BlendedCost.Amount}" \
  --output table
```

---

## Step 7: Reserved Instances vs On-Demand

**Analogy:** On-demand pricing is like paying for your data center servers month-to-month. Reserved instances are like signing an annual contract at a discount. Same servers, cheaper price, less flexibility.

| Pricing Model | Discount | Commitment | Flexibility |
|---|---|---|---|
| On-demand | 0% | None | Stop/start anytime |
| 1-year Reserved (no upfront) | ~20% | 1 year | Locked to instance type |
| 1-year Reserved (all upfront) | ~30% | 1 year | Locked to instance type |
| 3-year Reserved (all upfront) | ~50% | 3 years | Locked to instance type |

**When to buy reserved instances:**

- Production databases that run 24/7
- You are confident in the instance type for at least 1 year
- The database has been stable for 3+ months (past the "right-sizing" phase)

**When NOT to buy reserved instances:**

- Dev/test environments (turn them off nights/weekends)
- New applications (workload pattern unknown)
- Planning a migration to Aurora (different pricing model)

Check reserved instance pricing:

```bash
aws rds describe-reserved-db-instances-offerings \
  --db-instance-class db.r6g.xlarge \
  --product-description postgresql \
  --duration 31536000 \
  --query "ReservedDBInstancesOfferings[*].{Class:DBInstanceClass,Duration:Duration,Price:FixedPrice,Recurring:RecurringCharges[0].RecurringChargeAmount,Type:OfferingType}" \
  --output table
```

---

## Step 8: Right-Sizing Instances

**The most common cost waste in cloud databases is over-provisioning.** DBAs tend to over-allocate because running out of resources is painful. But in the cloud, right-sizing saves real money.

**How to identify over-provisioned databases:**

Check average CPU over the last 2 weeks:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=lab-postgres \
  --start-time $(date -u -v-14d +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Average Maximum \
  --output table
```

**Right-sizing rules of thumb:**

| Metric (2-week average) | Action |
|---|---|
| CPU Average < 20%, Max < 50% | Downsize instance |
| CPU Average 20-60% | Good fit |
| CPU Average > 60% | Consider upsize |
| FreeableMemory > 50% of total | Downsize instance |
| FreeableMemory < 20% of total | Upsize instance |

**Instance type guide for DBAs:**

| Instance Family | Use Case | Characteristics |
|---|---|---|
| `t3` / `t4g` | Dev, test, small workloads | Burstable CPU, cheapest |
| `m6g` | General purpose production | Balanced CPU and RAM |
| `r6g` | Memory-intensive production | High RAM, good for large `shared_buffers` |
| `r6gd` | High-performance production | NVMe local storage |
| `x2g` | Very large databases | Maximum memory |

---

## Step 9: Storage Optimization

| Storage Type | Max IOPS | Throughput | Cost | Best For |
|---|---|---|---|---|
| `gp2` | 16,000 (burst) | 250 MB/s | $0.115/GB | Legacy - use gp3 instead |
| `gp3` | 16,000 (configurable) | 1,000 MB/s | $0.08/GB + IOPS/throughput | Most workloads |
| `io1` | 64,000 | 1,000 MB/s | $0.125/GB + $0.065/IOPS | High-IOPS production |
| `io2` | 256,000 | 4,000 MB/s | $0.125/GB + $0.065/IOPS | Highest performance |
| Aurora | Automatic | Automatic | $0.10/GB | Aurora only |

**gp3 is almost always the right choice for RDS.** It replaced gp2 with lower cost and independently configurable IOPS and throughput.

Migrate from gp2 to gp3:

```bash
aws rds modify-db-instance \
  --db-instance-identifier lab-postgres \
  --storage-type gp3 \
  --apply-immediately
```

---

## Step 10: Practical - Set Up a Complete Monitoring Stack

Let us set up all three alarms plus event notifications for a production-like monitoring setup.

**On your Mac, in your terminal:**

```bash
# Ensure we have the SNS topic
TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn,'db-alerts')].TopicArn" --output text)

# Alarm: High CPU (warning at 70%, critical at 90%)
aws cloudwatch put-metric-alarm \
  --alarm-name "rds-lab-cpu-warning" \
  --alarm-description "CPU above 70% for 10 minutes" \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=lab-postgres \
  --statistic Average \
  --period 300 \
  --threshold 70 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions "$TOPIC_ARN" \
  --ok-actions "$TOPIC_ARN" \
  --treat-missing-data notBreaching

# Alarm: Storage below 15%
aws cloudwatch put-metric-alarm \
  --alarm-name "rds-lab-storage-critical" \
  --alarm-description "Free storage below 3 GB (15% of 20 GB)" \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=lab-postgres \
  --statistic Average \
  --period 300 \
  --threshold 3221225472 \
  --comparison-operator LessThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions "$TOPIC_ARN" \
  --treat-missing-data notBreaching

# Alarm: Replica lag (if you have a read replica)
aws cloudwatch put-metric-alarm \
  --alarm-name "rds-lab-replica-lag" \
  --alarm-description "Replication lag above 30 seconds" \
  --namespace AWS/RDS \
  --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=lab-postgres-replica \
  --statistic Maximum \
  --period 60 \
  --threshold 30 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 3 \
  --alarm-actions "$TOPIC_ARN" \
  --treat-missing-data notBreaching

# Alarm: Swap usage (should be near zero for a healthy database)
aws cloudwatch put-metric-alarm \
  --alarm-name "rds-lab-swap-usage" \
  --alarm-description "Swap usage above 100 MB" \
  --namespace AWS/RDS \
  --metric-name SwapUsage \
  --dimensions Name=DBInstanceIdentifier,Value=lab-postgres \
  --statistic Average \
  --period 300 \
  --threshold 104857600 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions "$TOPIC_ARN" \
  --treat-missing-data notBreaching
```

Verify all alarms are created:

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "rds-lab" \
  --query "MetricAlarms[*].{Name:AlarmName,State:StateValue,Metric:MetricName}" \
  --output table
```

Expected output (yours will differ):
```
--------------------------------------------------------------
|                      DescribeAlarms                        |
+--------------------+----------------------------+----------+
|     Metric         |          Name              | State    |
+--------------------+----------------------------+----------+
| CPUUtilization     | rds-lab-cpu-warning        | OK       |
| FreeStorageSpace   | rds-lab-storage-critical   | OK       |
| ReplicaLag         | rds-lab-replica-lag        | INSUF... |
| SwapUsage          | rds-lab-swap-usage         | OK       |
+--------------------+----------------------------+----------+
```

---

## Step 11: Clean Up Monitoring Resources

```bash
# Delete alarms
aws cloudwatch delete-alarms --alarm-names \
  "rds-lab-postgres-high-cpu" \
  "rds-lab-postgres-high-connections" \
  "rds-lab-postgres-low-storage" \
  "rds-lab-cpu-warning" \
  "rds-lab-storage-critical" \
  "rds-lab-replica-lag" \
  "rds-lab-swap-usage"

# Delete event subscription
aws rds delete-event-subscription --subscription-name lab-db-events

# Delete SNS topic
aws sns delete-topic --topic-arn "$TOPIC_ARN"

echo "Monitoring resources deleted"
```

---

## What You Learned

| Topic | Key Takeaway |
|---|---|
| CloudWatch metrics | Automatic OS and DB metrics - no agent needed |
| CloudWatch alarms | Threshold-based alerts with SNS notification |
| Performance Insights | Visual pg_stat_statements with wait event analysis |
| Enhanced Monitoring | OS-level metrics at up to 1-second granularity |
| SNS notifications | Event-based alerts for failovers, maintenance, failures |
| Cost Explorer | Track and break down database spending |
| Reserved Instances | 20-50% savings with 1-3 year commitment |
| Right-sizing | Check 2-week CPU/memory averages to find waste |
| Storage optimization | gp3 is the default choice - cheaper than gp2 with better performance |
